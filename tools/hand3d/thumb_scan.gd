# TEMP probe (author, 03.11.2026): the flattest REACHABLE resting contact for
# the thumb, and what it costs in position. The target point pins all three
# free thumb degrees, so the tangency term cannot help — the contact itself
# has to move. This prints the trade-off curve: how far the pad has to travel
# out of the shipped spot for the distal phalanx to lie along the cap.
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const HomePose := preload("res://home_pose.gd")
const ArmModel := preload("res://arm_model.gd")
const IK := preload("res://ik.gd")
const Kbd3D := preload("res://kbd3d.gd")


func _home_base(side: String, root_x: float, twist: float, abd: float) -> Dictionary:
	var p := HandModel.rest_pose()
	p["arm"] = (HomePose.ARM as Dictionary).duplicate(true)
	p["thumb_f"] = 0.0
	p["thumb"] = HandModel.thumb_at(0.0)
	p["thumb_dof"] = 4
	p["thumb_hold"] = {"twist": twist, "cmc_abd": abd}
	for ray in ["II", "III", "IV", "V"]:
		var o := {"arm": false, "tuck": false, "clear_w": 0.0, "dir_w": 0.0}
		p = IK.solve_chain(ray, HomePose.target(side, ray, root_x), p, o)["pose"]
	return p


func _probe(p: Dictionary, lx: float, ly: float) -> Dictionary:
	var t := Vector3(lx, ly, Kbd3D.FACE_Z + 2.0)
	var o := {"arm": false, "tuck": false, "clear_w": 0.0, "dir_w": 0.0,
		"thumb_dof": 4}
	var r: Dictionary = IK.solve_chain("I", t, p.duplicate(true), o)
	var pose: Dictionary = r["pose"]
	var th := HandModel.thumb_of_pose(pose)
	var tfk := HandModel.thumb_fk(th)
	var xf := ArmModel.hand_transform(pose.get("arm", {}))
	var d2: Vector3 = (xf.basis * (tfk["dirs"][2] as Vector3)).normalized()
	return {"off": rad_to_deg(asin(clampf(absf(d2.z), 0.0, 1.0))),
		"th": th, "reach": float(r["error"])}


func _run() -> void:
	var root := float(HomePose.HOME_ROOTS["L"])
	for tw in [-10.0]:
		for ab in [-9.0]:
			var p := _home_base("L", root, tw, ab)
			var line := "twist %+.0f abd %+.0f:" % [tw, ab]
			for ly in [108.0, 112.0, 116.0]:
				for lx in [84.0, 88.0, 92.0, 96.0, 100.0]:
					var q := _probe(p, lx, ly)
					if float(q["reach"]) > 0.15:
						continue
					var th: Dictionary = q["th"]
					line += "\n   x %5.1f y %5.1f -> tip %4.1f ip %+5.1f mcp %+5.1f cmcf %+5.1f (miss %.2f)" \
						% [lx, ly, float(q["off"]), float(th["ip"]),
							float(th["mcp"]), float(th["cmc_flex"]),
							float(q["reach"])]
			print(line)


func _init() -> void:
	_run()
	quit()
