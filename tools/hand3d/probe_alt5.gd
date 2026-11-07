extends SceneTree
const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")
const IK := preload("res://ik.gd")
const Kbd3D := preload("res://kbd3d.gd")
const HomePose := preload("res://home_pose.gd")
const ROOTS := {"L": -72.51, "R": 43.94}
const THUMB_R := [11.8, 10.8, 9.6, 6.6]

func _init() -> void:
	var keys := Kbd3D.keys()
	var idx := Kbd3D.index_of(keys, "Alt")
	var r: Rect2 = keys[idx]["r"]
	var hit := Vector2(r.get_center().x - 0.6 * r.size.x * 0.5, r.get_center().y)
	var ray := String(Kbd3D.hand_finger("Alt", hit.x)[1])
	var root_x := -72.51
	var deep := Vector3(hit.x - root_x, hit.y, Kbd3D.FACE_Z - Kbd3D.TRAVEL)
	var home: Dictionary = HomePose.build("L", root_x)
	var idle: Dictionary = HomePose.build("R", 43.94)
	IK.dbg = true
	var pr: Dictionary = IK.solve_chain(ray, deep, home,
		{"arm": true, "thumb_dof": 4, "clear_z": Kbd3D.FACE_Z,
		"clear_w": 100.0, "dir_w": 30.0,
		"foreign": _caps_foreign(idle, "R", "L", root_x),
		"hover_z": Kbd3D.FACE_Z + 12.0})
	print("FINAL thumb %s" % str(HandModel.thumb_of_pose(pr["pose"])))
	quit(0)

func _caps_foreign(idle: Dictionary, other: String, side: String,
		root_x: float) -> Array:
	var xo := ArmModel.hand_transform(idle["arm"])
	var out := []
	var sgn := -1.0 if side == "R" else 1.0
	var it: PackedVector3Array = HandModel.thumb_fk(
		HandModel.thumb_of_pose(idle))["pts"]
	for i in 3:
		out.append({"a": _loc(sgn, root_x, _w(other, float(ROOTS[other]), xo * it[i])),
			"b": _loc(sgn, root_x, _w(other, float(ROOTS[other]), xo * it[i + 1])),
			"r": maxf(float(THUMB_R[i]), float(THUMB_R[i + 1]))})
	for f in HandModel.FINGERS:
		var fp: PackedVector3Array = HandModel.finger_fk(f,
			idle["fingers"][f])["pts"]
		for i in 3:
			out.append({"a": _loc(sgn, root_x, _w(other, float(ROOTS[other]), xo * fp[i])),
				"b": _loc(sgn, root_x, _w(other, float(ROOTS[other]), xo * fp[i + 1])),
				"r": maxf(float(HandModel.SKIN_R[f][i]),
					float(HandModel.SKIN_R[f][i + 1]))})
	return out

func _loc(sgn: float, root_x: float, w: Vector3) -> Vector3:
	return Vector3((w.x - root_x) * sgn, w.y, w.z)

func _w(side: String, root_x: float, q: Vector3) -> Vector3:
	if side == "R":
		return Vector3(root_x - q.x, q.y, q.z)
	return Vector3(root_x + q.x, q.y, q.z)
