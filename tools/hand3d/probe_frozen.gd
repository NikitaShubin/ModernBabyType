extends SceneTree
const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")
const IK := preload("res://ik.gd")
const Kbd3D := preload("res://kbd3d.gd")
const HomePose := preload("res://home_pose.gd")
const ROOTS := {"L": -72.51, "R": 43.94}

func _init() -> void:
	var keys := Kbd3D.keys()
	for want in ["Alt", "и", "3"]:
		var idx := Kbd3D.index_of(keys, want)
		var r: Rect2 = keys[idx]["r"]
		var hx := r.get_center().x
		if r.size.x > Kbd3D.KEY_W * 1.05:
			hx = r.get_center().x - 0.6 * r.size.x * 0.5
		var ray := String(Kbd3D.hand_finger(want, hx)[1])
		var tgt := Vector3(hx, r.get_center().y, Kbd3D.FACE_Z - Kbd3D.TRAVEL)
		var deep := Vector3(tgt.x - ROOTS["L"], tgt.y, tgt.z)
		var home: Dictionary = HomePose.build("L", ROOTS["L"])
		var a: Dictionary = IK.solve_chain(ray, deep, home,
			{"arm": false, "thumb_dof": 4, "clear_z": Kbd3D.FACE_Z,
			"clear_w": 100.0, "dir_w": 30.0})
		var p: Dictionary = a["pose"]
		var xf := ArmModel.hand_transform(p["arm"])
		var pad: Vector3 = xf * HandModel.finger_pad(ray, HandModel.finger_fk(ray, p["fingers"][ray]))
		print("%s frozen pad (%7.2f %7.2f %7.2f) tgt (%7.2f %7.2f %7.2f) err %6.2f" % [
			want, pad.x, pad.y, pad.z, deep.x, deep.y, deep.z, float(a["error"])])
		print("   finger %s fan %.1f" % [str(_f(p["fingers"][ray])), float(p["fingers"][ray]["fan"])])
	quit(0)

func _f(a: Dictionary) -> Array:
	return [snappedf(float(a["mcp"]), 0.1), snappedf(float(a["pip"]), 0.1),
		snappedf(float(a["dip"]), 0.1)]
