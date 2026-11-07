# Finer scan of the hand's own freedom at L Alt: rotate the arm by (abd, dev)
# and put the elbow back so the pad stays exactly on the key, then re-tuck.
# Prints the other hand's penetration at the press and at the hover, and how
# far the elbow had to travel.
extends SceneTree
const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")
const IK := preload("res://ik.gd")
const Kbd3D := preload("res://kbd3d.gd")
const HomePose := preload("res://home_pose.gd")
const ROOTS := {"L": -72.51, "R": 43.94}
const THUMB_R := [11.8, 10.8, 9.6, 6.6]
const KEY_HOVER := 12.0

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
	IK.clear_z = Kbd3D.FACE_Z
	IK.clear_hx = -1.0
	var pr: Dictionary = IK.solve_chain(ray, deep, home,
		{"arm": true, "thumb_dof": 4, "clear_z": Kbd3D.FACE_Z,
		"clear_w": 100.0, "dir_w": 30.0, "foreign": caps,
		"hover_z": Kbd3D.FACE_Z + KEY_HOVER})
	var p0: Dictionary = pr["pose"]
	var pad0: Vector3 = ArmModel.hand_transform(p0["arm"]) * HandModel.finger_pad(
		ray, HandModel.finger_fk(ray, p0["fingers"][ray]))
	var lift := maxf(0.0, (Kbd3D.FACE_Z + KEY_HOVER) - pad0.z)
	print("lift %.2f  arm abd %.2f dev %.2f" % [lift,
		float(p0["arm"]["forearm_abd"]), float(p0["arm"]["wrist_dev"])])
	print("  d_abd d_dev | elbow dx dy dz | press hover")
	for da in [-8.0, -6.0, -4.0, -2.0, 0.0, 2.0, 4.0, 6.0, 8.0]:
		for dd in [-6.0, -4.0, -2.0, 0.0, 2.0, 4.0, 6.0]:
			var a: Dictionary = (p0["arm"] as Dictionary).duplicate(true)
			a["forearm_abd"] = float(a["forearm_abd"]) + da
			a["wrist_dev"] = float(a["wrist_dev"]) + dd
			var cand: Dictionary = p0.duplicate(true)
			cand["arm"] = a
			var pad: Vector3 = ArmModel.hand_transform(a) * HandModel.finger_pad(
				ray, HandModel.finger_fk(ray, cand["fingers"][ray]))
			var d := pad0 - pad
			a["elbow_x"] = float(a["elbow_x"]) + d.x
			a["elbow_y"] = float(a["elbow_y"]) + d.y
			a["elbow_z"] = float(a["elbow_z"]) + d.z
			cand["arm"] = a
			var old := IK.set_foreign(caps)
			IK.thumb_lift = lift
			IK._tuck_thumb(cand)
			var xf := ArmModel.hand_transform(cand["arm"])
			var tfk: Dictionary = HandModel.thumb_fk(HandModel.thumb_of_pose(cand))
			var fh := IK._thumb_foreign(xf, tfk)
			IK.thumb_lift = 0.0
			var fp := IK._thumb_foreign(xf, tfk)
			IK.restore_foreign(old)
			var mark := "  "
			if maxf(fp, fh) <= 0.1:
				mark = "OK"
			print("%s %5.1f %5.1f | %6.1f %5.1f %5.1f | %5.2f %5.2f" % [mark,
				da, dd, d.x, d.y, d.z, fp, fh])
	quit(0)

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
