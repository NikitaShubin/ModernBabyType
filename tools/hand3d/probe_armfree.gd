extends SceneTree
const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")
const IK := preload("res://ik.gd")
const Kbd3D := preload("res://kbd3d.gd")
const HomePose := preload("res://home_pose.gd")
const ROOTS := {"L": -72.51, "R": 43.94}

func _init() -> void:
	var keys := Kbd3D.keys()
	for want in ["Alt", "и", "3", "6", "в"]:
		var idx := Kbd3D.index_of(keys, want)
		var r: Rect2 = keys[idx]["r"]
		var hx := r.get_center().x
		if r.size.x > Kbd3D.KEY_W * 1.05:
			hx = r.get_center().x - 0.6 * r.size.x * 0.5
		var ray := String(Kbd3D.hand_finger(want, hx)[1])
		var deep := Vector3(hx - ROOTS["L"], r.get_center().y, Kbd3D.FACE_Z - Kbd3D.TRAVEL)
		var home: Dictionary = HomePose.build("L", ROOTS["L"])
		var a: Dictionary = IK.solve_chain(ray, deep, home,
			{"arm": false, "thumb_dof": 4, "clear_z": Kbd3D.FACE_Z,
			"clear_w": 100.0, "dir_w": 30.0})
		var b: Dictionary = IK.solve_chain(ray, deep, home,
			{"arm": true, "thumb_dof": 4, "clear_z": Kbd3D.FACE_Z,
			"clear_w": 100.0, "dir_w": 30.0})
		print("%s ray %s  frozen err %.2f  free err %.2f  arm %s" % [want, ray,
			float(a["error"]), float(b["error"]),
			str(_d(b["pose"]["arm"]))])
	quit(0)

func _d(arm: Dictionary) -> Array:
	var out := []
	for j in ["wrist_flex", "wrist_dev", "pronation", "forearm_abd", "elbow_x"]:
		out.append("%s %.1f" % [j, float(arm[j])])
	return out
