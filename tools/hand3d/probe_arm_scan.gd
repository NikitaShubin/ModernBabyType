# Can a slightly different ARM pose both reach the key and let the thumb tuck
# clear the other hand? Scans forearm_abd, elbow_x, wrist_dev with the fingers
# re-solved at each arm pose (arm frozen), then reports the reach error and the
# residual cross-hand penetration after the tuck.
extends SceneTree
const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")
const IK := preload("res://ik.gd")
const Kbd3D := preload("res://kbd3d.gd")
const HomePose := preload("res://home_pose.gd")
const ROOTS := {"L": -72.51, "R": 43.94}
const THUMB_R := [11.8, 10.8, 9.6, 6.6]
const MC_R := 10.0

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
	print("  abd  elbow_x  wdev   err   cross   thumb")
	for abd in [22.0, 24.0, 26.0, 28.0]:
		for ex in [-56.19, -49.0, -42.0]:
			for wd in [-20.0, -16.0]:
				var base: Dictionary = home.duplicate(true)
				base["arm"] = (home["arm"] as Dictionary).duplicate(true)
				base["arm"]["forearm_abd"] = abd
				base["arm"]["elbow_x"] = ex
				base["arm"]["wrist_dev"] = wd
				var a: Dictionary = IK.solve_chain(ray, deep, base,
					{"arm": false, "thumb_dof": 4, "clear_z": Kbd3D.FACE_Z,
					"clear_w": 100.0, "dir_w": 30.0, "foreign": caps,
					"hover_z": Kbd3D.FACE_Z + 12.0})
				var p: Dictionary = a["pose"]
				var xf := ArmModel.hand_transform(p["arm"])
				var cross := _cross(xf, HandModel.thumb_of_pose(p), idle)
				print("%5.1f %8.2f %5.1f %6.2f %6.2f   %s" % [abd, ex, wd,
					float(a["error"]), cross,
					str(_q(HandModel.thumb_of_pose(p)))])
	quit(0)

func _q(t: Dictionary) -> Array:
	return [snappedf(float(t["cmc_flex"]), 0.1), snappedf(float(t["cmc_abd"]), 0.1),
		snappedf(float(t["mcp"]), 0.1), snappedf(float(t["ip"]), 0.1)]

func _cross(xf: Transform3D, a: Dictionary, idle: Dictionary) -> float:
	var xo := ArmModel.hand_transform(idle["arm"])
	var out := 0.0
	var tpts: PackedVector3Array = HandModel.thumb_fk(a)["pts"]
	for i in 3:
		var p := _w("L", ROOTS["L"], xf * tpts[i])
		var q := _w("L", ROOTS["L"], xf * tpts[i + 1])
		var rr := maxf(float(THUMB_R[i]), float(THUMB_R[i + 1]))
		var it: PackedVector3Array = HandModel.thumb_fk(
			HandModel.thumb_of_pose(idle))["pts"]
		for j in 3:
			var d := _seg_dist(p, q, _w("R", ROOTS["R"], xo * it[j]),
				_w("R", ROOTS["R"], xo * it[j + 1]))
			out = maxf(out, rr + maxf(float(THUMB_R[j]), float(THUMB_R[j + 1])) - d)
		for f in HandModel.FINGERS:
			var fp: PackedVector3Array = HandModel.finger_fk(f,
				idle["fingers"][f])["pts"]
			for j in 3:
				var d := _seg_dist(p, q, _w("R", ROOTS["R"], xo * fp[j]),
					_w("R", ROOTS["R"], xo * fp[j + 1]))
				out = maxf(out, rr + maxf(float(HandModel.SKIN_R[f][j]),
					float(HandModel.SKIN_R[f][j + 1])) - d)
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
	for f in HandModel.FINGERS:
		out.append({"a": _loc(root_x, _w(other, float(ROOTS[other]), xo * HandModel.MC_BASE[f])),
			"b": _loc(root_x, _w(other, float(ROOTS[other]), xo * HandModel.metacarpal_head(f))),
			"r": MC_R})
	return out

func _loc(root_x: float, w: Vector3) -> Vector3:
	return Vector3(w.x - root_x, w.y, w.z)

func _w(side: String, root_x: float, q: Vector3) -> Vector3:
	if side == "R":
		return Vector3(root_x - q.x, q.y, q.z)
	return Vector3(root_x + q.x, q.y, q.z)

func _seg_dist(p1: Vector3, q1: Vector3, p2: Vector3, q2: Vector3) -> float:
	var d1 := q1 - p1
	var d2 := q2 - p2
	var r := p1 - p2
	var a := d1.dot(d1)
	var e := d2.dot(d2)
	var f := d2.dot(r)
	var s := 0.0
	var t := 0.0
	if a <= 1e-12 and e <= 1e-12:
		return r.length()
	if a <= 1e-12:
		t = clampf(f / e, 0.0, 1.0)
	elif e <= 1e-12:
		s = clampf(-d1.dot(r) / a, 0.0, 1.0)
	else:
		var c := d1.dot(r)
		var b := d1.dot(d2)
		var denom := a * e - b * b
		if absf(denom) > 1e-12:
			s = clampf((b * f - c * e) / denom, 0.0, 1.0)
		t = (b * s + f) / e
		if t < 0.0:
			t = 0.0
			s = clampf(-c / a, 0.0, 1.0)
		elif t > 1.0:
			t = 1.0
			s = clampf((b - c) / a, 0.0, 1.0)
	var c1 := p1 + d1 * s
	var c2 := p2 + d2 * t
	return c1.distance_to(c2)
