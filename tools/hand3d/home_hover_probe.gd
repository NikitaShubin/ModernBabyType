# ВРЕМЕННАЯ проба: как подъём цели над клавишей расслабляет пальцы покоя.
#   mbt-godot --headless --path /work/tools/hand3d --script res://home_hover_probe.gd
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")
const HomePose := preload("res://home_pose.gd")
const IK := preload("res://ik.gd")
const Kbd3D := preload("res://kbd3d.gd")


func _pad(side: String, ray: String, p: Dictionary) -> Vector3:
	var xf := ArmModel.hand_transform(p.get("arm", {}))
	if ray == "I":
		return xf * HandModel.thumb_pad(HandModel.thumb_fk(
			HandModel.thumb_of_pose(p)))
	return xf * HandModel.finger_pad(ray, HandModel.finger_fk(ray,
		p["fingers"][ray]))


func _build(side: String, root_x: float, lift: float) -> Dictionary:
	var p := HandModel.rest_pose()
	p["arm"] = (HomePose.ARM as Dictionary).duplicate(true)
	p["thumb_f"] = 0.0
	p["thumb"] = HandModel.thumb_at(0.0)
	p["thumb_dof"] = 4
	p["thumb_hold"] = {"twist": float(HomePose.THUMB_TWIST[side]),
		"cmc_abd": float(HomePose.THUMB_ABD[side])}
	for ray in ["II", "III", "IV", "V", "I"]:
		var t := HomePose.target(side, ray, root_x)
		if ray != "I":
			t.z = Kbd3D.FACE_Z + lift
		var r: Dictionary = IK.solve_chain(ray, t, p, HomePose._opts(ray))
		p = r["pose"]
	return p


func _initialize() -> void:
	for side in ["L", "R"]:
		var rx := float(HomePose.HOME_ROOTS[side])
		print("\n==== %s ====" % side)
		for lift in [0.3, 5.0, 10.0, 15.0, 20.0, 25.0, 30.0]:
			var p := _build(side, rx, lift)
			var line := "lift %4.1f:" % lift
			for ray in ["II", "III", "IV", "V"]:
				var a: Dictionary = p["fingers"][ray]
				var pad := _pad(side, ray, p)
				var mcp: Vector3 = HandModel.metacarpal_head(ray)
				var span := Vector2(pad.x - mcp.x, pad.y - mcp.y).length()
				line += "  %s %3.0f/%3.0f/%3.0f (сумма %3.0f, размах %4.1f)" % [
					ray, float(a["mcp"]), float(a["pip"]), float(a["dip"]),
					float(a["mcp"]) + float(a["pip"]) + float(a["dip"]), span]
			print(line)
			var t := HomePose.target(side, "II", rx)
			var pad := _pad(side, "II", p)
			print("           pad II %s  цель %s" % [str(pad), str(t)])
	quit(0)
