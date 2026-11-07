# Which way does the left thumb have to go to leave the right hand alone?
# Takes the guarded L Alt press pose and scans cmc_abd (and then mcp) with the
# penetration at the press and at the hover height, plus the thumb's MCP x.
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
	var args := OS.get_cmdline_user_args()
	var side := String(args[0]) if args.size() > 0 else "L"
	var want := String(args[1]) if args.size() > 1 else "Alt"
	var keys := Kbd3D.keys()
	var idx := Kbd3D.index_of(keys, want)
	var key: Dictionary = keys[idx]
	var r: Rect2 = key["r"]
	var hx := r.get_center().x
	if r.size.x > Kbd3D.KEY_W * 1.05:
		hx = r.get_center().x + (-0.6 if side == "L" else 0.6) \
			* r.size.x * 0.5
	var hit := Vector2(hx, r.get_center().y)
	var ray := String(Kbd3D.hand_finger(want, hx)[1])
	var root_x: float = ROOTS[side]
	var sgn := -1.0 if side == "R" else 1.0
	var deep := Vector3((hit.x - root_x) * sgn, hit.y,
		Kbd3D.FACE_Z - Kbd3D.TRAVEL)
	var home: Dictionary = HomePose.build(side, root_x)
	var other := "R" if side == "L" else "L"
	var idle: Dictionary = HomePose.build(other, float(ROOTS[other]))
	var hov := KEY_HOVER
	var pr: Dictionary = IK.solve_chain(ray, deep, home,
		{"arm": true, "thumb_dof": 4, "clear_z": Kbd3D.FACE_Z,
		"clear_w": 100.0, "dir_w": 30.0,
		"foreign": _caps_foreign(idle, other, side, root_x),
		"hover_z": Kbd3D.FACE_Z + hov})
	var p: Dictionary = pr["pose"]
	var xf := ArmModel.hand_transform(p["arm"])
	var cur: Dictionary = HandModel.thumb_of_pose(p)
	var lift := maxf(0.0, (Kbd3D.FACE_Z + hov) - _padz(p, side, ray))
	print("%s %s ray %s lift %.2f thumb %s" % [side, want, ray, lift,
		str(_q(cur))])
	print("  arm %s" % str(p["arm"]))
	print("  mcp x %.1f  tip %s" % [_mcp_x(xf, cur, side), str(_tip(xf, cur,
		side))])
	print("   abd   press  hover   own    key   mcp_x")
	var a := cur.duplicate()
	for it in 23:
		var abd := -25.0 + 2.5 * float(it)
		a["cmc_abd"] = abd
		print("  %5.1f  %6.2f %6.2f %6.2f %6.2f %7.1f" % [abd,
			_pen_foreign(xf, a, side, idle, other, 0.0),
			_pen_foreign(xf, a, side, idle, other, lift),
			_own(xf, a, p), IK._thumb_violation(xf, a),
			_mcp_x(xf, a, side)])
	quit(0)


func _q(t: Dictionary) -> Array:
	return [snappedf(float(t["cmc_flex"]), 0.01),
		snappedf(float(t["cmc_abd"]), 0.01), snappedf(float(t["mcp"]), 0.01),
		snappedf(float(t["ip"]), 0.01)]


func _mcp_x(xf: Transform3D, a, side: String) -> float:
	return _w(side, float(ROOTS[side]), xf * _pts(a)[1]).x


func _tip(xf: Transform3D, a, side: String) -> Vector3:
	return _w(side, float(ROOTS[side]), xf * _pts(a)[3])


func _pts(a) -> PackedVector3Array:
	return HandModel.thumb_fk(a)["pts"]


func _padz(p: Dictionary, side: String, ray: String) -> float:
	var xf := ArmModel.hand_transform(p["arm"])
	if ray == "I":
		return (xf * HandModel.thumb_pad(HandModel.thumb_fk(
			HandModel.thumb_of_pose(p)))).z
	return (xf * HandModel.finger_pad(ray,
		HandModel.finger_fk(ray, p["fingers"][ray]))).z


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


func _pen_foreign(xf: Transform3D, a, side: String, idle: Dictionary,
		other: String, dz: float) -> float:
	var xo := ArmModel.hand_transform(idle["arm"])
	var out := 0.0
	var up := Vector3(0.0, 0.0, dz)
	var tpts: PackedVector3Array = HandModel.thumb_fk(a)["pts"]
	for i in 3:
		var p := _w(side, float(ROOTS[side]), xf * tpts[i]) + up
		var q := _w(side, float(ROOTS[side]), xf * tpts[i + 1]) + up
		var rr := maxf(float(THUMB_R[i]), float(THUMB_R[i + 1]))
		var it: PackedVector3Array = HandModel.thumb_fk(
			HandModel.thumb_of_pose(idle))["pts"]
		for j in 3:
			var d := _seg_dist(p, q, _w(other, float(ROOTS[other]), xo * it[j]),
				_w(other, float(ROOTS[other]), xo * it[j + 1]))
			out = maxf(out, rr + maxf(float(THUMB_R[j]),
				float(THUMB_R[j + 1])) - d)
		for f in HandModel.FINGERS:
			var fp: PackedVector3Array = HandModel.finger_fk(f,
				idle["fingers"][f])["pts"]
			for j in 3:
				var d := _seg_dist(p, q,
					_w(other, float(ROOTS[other]), xo * fp[j]),
					_w(other, float(ROOTS[other]), xo * fp[j + 1]))
				out = maxf(out, rr + maxf(float(HandModel.SKIN_R[f][j]),
					float(HandModel.SKIN_R[f][j + 1])) - d)
	return out


func _own(xf: Transform3D, a, p: Dictionary) -> float:
	var tpts: PackedVector3Array = HandModel.thumb_fk(a)["pts"]
	var out := 0.0
	for f in HandModel.FINGERS:
		var fp: PackedVector3Array = HandModel.finger_fk(f,
			p["fingers"][f])["pts"]
		for i in 3:
			for j in 3:
				var d := _seg_dist(xf * tpts[i], xf * tpts[i + 1],
					xf * fp[j], xf * fp[j + 1])
				out = maxf(out, maxf(float(THUMB_R[i]), float(THUMB_R[i + 1]))
					+ maxf(float(HandModel.SKIN_R[f][j]),
						float(HandModel.SKIN_R[f][j + 1])) - d)
	return out


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
