extends SceneTree
const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")
const IK := preload("res://ik.gd")
const Kbd3D := preload("res://kbd3d.gd")
const HomePose := preload("res://home_pose.gd")
const ROOTS := {"L": -72.51, "R": 43.94}

func _init() -> void:
	var keys := Kbd3D.keys()
	for want in ["Alt", "и"]:
		var idx := Kbd3D.index_of(keys, want)
		var r: Rect2 = keys[idx]["r"]
		var hx := r.get_center().x
		if r.size.x > Kbd3D.KEY_W * 1.05:
			hx = r.get_center().x - 0.6 * r.size.x * 0.5
		var ray := String(Kbd3D.hand_finger(want, hx)[1])
		var deep := Vector3(hx - ROOTS["L"], r.get_center().y, Kbd3D.FACE_Z - Kbd3D.TRAVEL)
		var home: Dictionary = HomePose.build("L", ROOTS["L"])
		for cfg in [["frozen+noclear", false, 0.0], ["frozen+clear", false, 100.0],
				["free+noclear", true, 0.0], ["free+clear", true, 100.0]]:
			var a: Dictionary = IK.solve_chain(ray, deep, home,
				{"arm": bool(cfg[1]), "thumb_dof": 4, "clear_z": Kbd3D.FACE_Z,
				"clear_w": float(cfg[2]), "dir_w": 30.0})
			var xf := ArmModel.hand_transform(a["pose"]["arm"])
			var tp: PackedVector3Array = HandModel.thumb_fk(HandModel.thumb_of_pose(a["pose"]))["pts"]
			print("%s %-16s err %6.2f  wrist_x %7.2f  thumb MCP x %7.2f tip x %7.2f" % [
				want, cfg[0], float(a["error"]), ROOTS["L"] + xf.origin.x,
				ROOTS["L"] + (xf * tp[1]).x, ROOTS["L"] + (xf * tp[3]).x])
	quit(0)
