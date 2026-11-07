# ВРЕМЕННАЯ проба: насколько расслабляет кисть отодвигание её от доски.
#   mbt-godot --headless --path /work/tools/hand3d --script res://home_back_probe.gd
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


func _build(side: String, root_x: float, back: float) -> Dictionary:
	var p := HandModel.rest_pose()
	var arm := (HomePose.ARM as Dictionary).duplicate(true)
	arm["elbow_y"] = float(arm["elbow_y"]) + back
	p["arm"] = arm
	p["thumb_f"] = 0.0
	p["thumb"] = HandModel.thumb_at(0.0)
	p["thumb_dof"] = 4
	p["thumb_hold"] = {"twist": float(HomePose.THUMB_TWIST[side]),
		"cmc_abd": float(HomePose.THUMB_ABD[side])}
	for ray in ["II", "III", "IV", "V", "I"]:
		var r: Dictionary = IK.solve_chain(ray, HomePose.target(side, ray, root_x),
			p, HomePose._opts(ray))
		p = r["pose"]
	return p


func _initialize() -> void:
	for side in ["L", "R"]:
		var rx := float(HomePose.HOME_ROOTS[side])
		print("\n==== %s ====" % side)
		var flex := HandModel.rest_pose()
		flex["arm"] = (HomePose.ARM as Dictionary).duplicate(true)
		var fk_line := "FLEX  "
		for ray in ["II", "III", "IV", "V"]:
			var a: Dictionary = flex["fingers"][ray]
			fk_line += " %s %3.0f/%3.0f/%3.0f (сумма %3.0f)" % [ray,
				float(a["mcp"]), float(a["pip"]), float(a["dip"]),
				float(a["mcp"]) + float(a["pip"]) + float(a["dip"])]
		print(fk_line)
		for back in [0.0, -5.0, -10.0, -15.0, -20.0, -25.0, -30.0]:
			var p := _build(side, rx, back)
			var line := "back %4.1f:" % back
			for ray in ["II", "III", "IV", "V"]:
				var a: Dictionary = p["fingers"][ray]
				var pad := _pad(side, ray, p)
				var tgt := HomePose.target(side, ray, rx)
				line += "  %s %3.0f/%3.0f/%3.0f (%3.0f, мисс %4.1f)" % [ray,
					float(a["mcp"]), float(a["pip"]), float(a["dip"]),
					float(a["mcp"]) + float(a["pip"]) + float(a["dip"]),
					pad.distance_to(tgt)]
			print(line)
			var th := _pad(side, "I", p)
			var tt := HomePose.target(side, "I", rx)
			print("           большой: мисс %4.1f мм  pad %s" % [
				th.distance_to(tt), str(th)])
	quit(0)
