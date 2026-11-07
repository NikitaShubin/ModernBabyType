# What the arm had to do: the press pose with the yield on and off.
extends SceneTree
const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")
const IK := preload("res://ik.gd")
const Kbd3D := preload("res://kbd3d.gd")
const HomePose := preload("res://home_pose.gd")
const ROOTS := {"L": -72.51, "R": 43.94}
const THUMB_R := [11.8, 10.8, 9.6, 6.6]

func _init() -> void:
	var want := "Alt"
	var keys := Kbd3D.keys()
	var idx := Kbd3D.index_of(keys, want)
	var r: Rect2 = keys[idx]["r"]
	var hx := r.get_center().x - 0.6 * r.size.x * 0.5
	var ray := String(Kbd3D.hand_finger(want, hx)[1])
	var deep := Vector3(hx - ROOTS["L"], r.get_center().y, Kbd3D.FACE_Z - Kbd3D.TRAVEL)
	var home: Dictionary = HomePose.build("L", ROOTS["L"])
	var idle: Dictionary = HomePose.build("R", ROOTS["R"])
	var caps := _foreign(idle, "R", "L", ROOTS["L"])
	for tag in [["off", false], ["on", true]]:
		var pr: Dictionary = IK.solve_chain(ray, deep, home,
			{"arm": true, "thumb_dof": 4, "clear_z": Kbd3D.FACE_Z,
			"clear_w": 100.0, "dir_w": 30.0, "foreign": caps,
			"hover_z": Kbd3D.FACE_Z + 12.0, "arm_yield": bool(tag[1])})
		var p: Dictionary = pr["pose"]
		var pad: Vector3 = ArmModel.hand_transform(p["arm"]) * HandModel.finger_pad(
			ray, HandModel.finger_fk(ray, p["fingers"][ray]))
		print("%-4s err %.3f pad (%.3f %.3f %.3f) arm %s" % [tag[0],
			float(pr["error"]), pad.x, pad.y, pad.z, str(_a(p["arm"]))])
		print("     thumb %s" % str(_t(HandModel.thumb_of_pose(p))))
	quit(0)

func _a(a: Dictionary) -> Array:
	var out := []
	for j in ArmModel.ALL_JOINTS:
		out.append("%s %.2f" % [j, float(a[j])])
	return out

func _t(t: Dictionary) -> Array:
	var out := []
	for j in HandModel.THUMB_JOINTS:
		out.append("%s %.1f" % [j, float(t[j])])
	return out

func _foreign(idle: Dictionary, other: String, side: String, root_x: float) -> Array:
	var xo := ArmModel.hand_transform(idle["arm"])
	var out := []
	var it: PackedVector3Array = HandModel.thumb_fk(
		HandModel.thumb_of_pose(idle))["pts"]
	for i in 3:
		out.append({"a": _loc(root_x, _w(other, float(ROOTS[other]), xo * it[i])),
			"b": _loc(root_x, _w(other, float(ROOTS[other]), xo * it[i + 1])),
			"r": maxf(float(THUMB_R[i]), float(THUMB_R[i + 1]))})
	for f in HandModel.FINGERS:
		var fp: PackedVector3Array = HandModel.finger_fk(f,
			idle["fingers"][f])["pts"]
		for i in 3:
			out.append({"a": _loc(root_x, _w(other, float(ROOTS[other]), xo * fp[i])),
				"b": _loc(root_x, _w(other, float(ROOTS[other]), xo * fp[i + 1])),
				"r": maxf(float(HandModel.SKIN_R[f][i]),
					float(HandModel.SKIN_R[f][i + 1]))})
	return out

func _loc(root_x: float, w: Vector3) -> Vector3:
	return Vector3(w.x - root_x, w.y, w.z)

func _w(side: String, root_x: float, q: Vector3) -> Vector3:
	if side == "R":
		return Vector3(root_x - q.x, q.y, q.z)
	return Vector3(root_x + q.x, q.y, q.z)
