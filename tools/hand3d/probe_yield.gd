# Does the hand itself have room to get out of the other hand's way, without
# losing the press? Takes the solved L Alt press, rotates the arm, puts the
# elbow back so the pad stays exactly on the key, re-tucks the thumb and
# reports the other hand's penetration at the press and at the hover.
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
	print("press pad (%7.3f %7.3f %7.3f) arm %s" % [pad0.x, pad0.y, pad0.z,
		str(p0["arm"])])
	print("  d_abd  d_dev  d_flex  d_pro  d_fflex | elbow dx  press  hover")
	for cfg in [[0.0, 0.0, 0.0, 0.0, 0.0], [2.0, 0.0, 0.0, 0.0, 0.0],
			[4.0, 0.0, 0.0, 0.0, 0.0], [6.0, 0.0, 0.0, 0.0, 0.0],
			[8.0, 0.0, 0.0, 0.0, 0.0], [4.0, 2.0, 0.0, 0.0, 0.0],
			[4.0, -2.0, 0.0, 0.0, 0.0], [4.0, 0.0, 2.0, 0.0, 0.0],
			[4.0, 0.0, -2.0, 0.0, 0.0], [4.0, 0.0, 0.0, 2.0, 0.0],
			[4.0, 0.0, 0.0, 0.0, 2.0], [-4.0, 0.0, 0.0, 0.0, 0.0],
			[0.0, 4.0, 0.0, 0.0, 0.0], [0.0, -4.0, 0.0, 0.0, 0.0]]:
		var a: Dictionary = (p0["arm"] as Dictionary).duplicate(true)
		a["forearm_abd"] = float(a["forearm_abd"]) + float(cfg[0])
		a["wrist_dev"] = float(a["wrist_dev"]) + float(cfg[1])
		a["wrist_flex"] = float(a["wrist_flex"]) + float(cfg[2])
		a["pronation"] = float(a["pronation"]) + float(cfg[3])
		a["forearm_flex"] = float(a["forearm_flex"]) + float(cfg[4])
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
		var lift := maxf(0.0, (Kbd3D.FACE_Z + KEY_HOVER) - pad0.z)
		IK.thumb_lift = lift
		IK._tuck_thumb(cand)
		IK.thumb_lift = 0.0
		var xf := ArmModel.hand_transform(cand["arm"])
		var tfk: Dictionary = HandModel.thumb_fk(HandModel.thumb_of_pose(cand))
		var fh := IK._thumb_foreign(xf, tfk)
		IK.thumb_lift = lift
		var fh2 := IK._thumb_foreign(xf, tfk)
		IK.thumb_lift = 0.0
		IK.restore_foreign(old)
		print("  %5.1f  %5.1f  %5.1f  %5.1f  %5.1f | %7.2f  %5.2f  %5.2f  thumb %s" % [
			float(cfg[0]), float(cfg[1]), float(cfg[2]), float(cfg[3]),
			float(cfg[4]), d.x, fh, fh2, str(_q(HandModel.thumb_of_pose(cand)))])
	quit(0)

func _q(t: Dictionary) -> Array:
	return [snappedf(float(t["cmc_flex"]), 0.1), snappedf(float(t["cmc_abd"]), 0.1),
		snappedf(float(t["mcp"]), 0.1), snappedf(float(t["ip"]), 0.1)]

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
