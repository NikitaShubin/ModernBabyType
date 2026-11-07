# Can the thumb ALONE get out of the other hand's way? Takes a solved press
# pose, then searches the thumb's four joints (twist held) for the smallest
# move that clears both the other hand's idle thumb and its own index, the
# arm frozen. Prints the found pose, what it bought, and what it cost.
# This is the question the tuck has to answer: if the thumb cannot clear, the
# arm has to give, and the reach pays.
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")
const IK := preload("res://ik.gd")
const Kbd3D := preload("res://kbd3d.gd")
const HomePose := preload("res://home_pose.gd")

const ROOTS := {"L": -72.51, "R": 43.94}
const THUMB_R := [11.8, 10.8, 9.6, 6.6]
const W := {"cmc_flex": 1.0, "cmc_abd": 1.0, "mcp": 1.0, "ip": 1.0}


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
	var pr: Dictionary = IK.solve_chain(ray, deep, home,
		{"arm": true, "thumb_dof": 4, "clear_z": Kbd3D.FACE_Z,
		"clear_w": 100.0, "dir_w": 30.0})
	var pp: Dictionary = pr["pose"]
	var other := "R" if side == "L" else "L"
	var idle: Dictionary = HomePose.build(other, float(ROOTS[other]))
	var t0: Dictionary = HandModel.thumb_of_pose(pp)
	print("%s %s ray %s  home thumb %s" % [side, want, ray, str(_q(t0))])
	print("  cross %6.2f  own %5.2f  keyclr %5.2f" % [_cross(pp, side, idle,
		other), _own(pp, side), _key(pp, side)])
	var best: Dictionary = t0.duplicate(true)
	var step := 0.20
	for pass_i in 5:
		var improved := true
		while improved:
			improved = false
			for j in ["cmc_flex", "cmc_abd", "mcp", "ip"]:
				for dir in [-1.0, 1.0]:
					var cand := best.duplicate(true)
					var rom: Array = HandModel.THUMB_ROM[j]
					cand[j] = clampf(float(best[j]) + dir * step
						* (float(rom[1]) - float(rom[0])), float(rom[0]),
						float(rom[1]))
					var q: Dictionary = pp.duplicate(true)
					q["thumb"] = cand
					var c := _cost(q, t0, side, idle, other)
					if c < _cost(_with(pp, best), t0, side, idle, other) - 1e-9:
						best = cand
						improved = true
		step *= 0.5
	var q2: Dictionary = pp.duplicate(true)
	q2["thumb"] = best
	print("  BEST %s" % str(_q(best)))
	print("  cross %6.2f  own %5.2f  keyclr %5.2f  dshare %s" % [
		_cross(q2, side, idle, other), _own(q2, side), _key(q2, side),
		str(_d(t0, best))])
	print("  pad world %s  (was %s)" % [str(_pw(q2, side, ray)),
		str(_pw(pp, side, ray))])
	quit(0)


func _with(p: Dictionary, t: Dictionary) -> Dictionary:
	var q: Dictionary = p.duplicate(true)
	q["thumb"] = t
	return q


func _cost(q: Dictionary, t0: Dictionary, side: String, idle: Dictionary,
		other: String) -> float:
	var c := _cross(q, side, idle, other)
	var o := _own(q, side)
	var k := _key(q, side)
	var t: Dictionary = q["thumb"]
	var d := 0.0
	for j in ["cmc_flex", "cmc_abd", "mcp", "ip"]:
		var span := float(HandModel.THUMB_ROM[j][1]) \
			- float(HandModel.THUMB_ROM[j][0])
		var x := (float(t[j]) - float(t0[j])) / span
		d += W[j] * x * x
	return 10000.0 * maxf(0.0, c) * maxf(0.0, c) \
		+ 10000.0 * maxf(0.0, o) * maxf(0.0, o) \
		+ 10000.0 * maxf(0.0, k) * maxf(0.0, k) + d


func _q(t: Dictionary) -> Array:
	return [snappedf(float(t["cmc_flex"]), 0.01),
		snappedf(float(t["cmc_abd"]), 0.01), snappedf(float(t["mcp"]), 0.01),
		snappedf(float(t["ip"]), 0.01)]


func _d(a: Dictionary, b: Dictionary) -> Array:
	var out := []
	for j in ["cmc_flex", "cmc_abd", "mcp", "ip"]:
		out.append(snappedf(float(b[j]) - float(a[j]), 0.01))
	return out


func _pw(p: Dictionary, side: String, ray: String) -> Vector3:
	var xf := ArmModel.hand_transform(p["arm"])
	if ray == "I":
		return _world(side, xf * HandModel.thumb_pad(HandModel.thumb_fk(
			HandModel.thumb_of_pose(p))))
	return _world(side, xf * HandModel.finger_pad(ray,
		HandModel.finger_fk(ray, p["fingers"][ray])))


func _key(p: Dictionary, side: String) -> float:
	return IK._thumb_violation(ArmModel.hand_transform(p["arm"]),
		HandModel.thumb_of_pose(p))


func _own(p: Dictionary, side: String) -> float:
	var xf := ArmModel.hand_transform(p["arm"])
	var tpts: PackedVector3Array = HandModel.thumb_fk(
		HandModel.thumb_of_pose(p))["pts"]
	var worst := 0.0
	for f in ["II", "III", "IV", "V"]:
		var pts: PackedVector3Array = HandModel.finger_fk(f,
			p["fingers"][f])["pts"]
		for i in 3:
			for j in 3:
				var d := _seg_dist(xf * tpts[i], xf * tpts[i + 1],
					xf * pts[j], xf * pts[j + 1])
				var rr := maxf(float(THUMB_R[i]), float(THUMB_R[i + 1])) \
					+ maxf(float(HandModel.SKIN_R[f][j]),
						float(HandModel.SKIN_R[f][j + 1]))
				worst = maxf(worst, rr - d)
	return worst


func _cross(a: Dictionary, sa: String, b: Dictionary, sb: String) -> float:
	var xa := ArmModel.hand_transform(a["arm"])
	var xb := ArmModel.hand_transform(b["arm"])
	var ta: PackedVector3Array = HandModel.thumb_fk(
		HandModel.thumb_of_pose(a))["pts"]
	var tb: PackedVector3Array = HandModel.thumb_fk(
		HandModel.thumb_of_pose(b))["pts"]
	var worst := 0.0
	for i in 3:
		for j in 3:
			var d := _seg_dist(_world(sa, xa * ta[i]), _world(sa, xa * ta[i + 1]),
				_world(sb, xb * tb[j]), _world(sb, xb * tb[j + 1]))
			var rr := maxf(float(THUMB_R[i]), float(THUMB_R[i + 1])) \
				+ maxf(float(THUMB_R[j]), float(THUMB_R[j + 1]))
			worst = maxf(worst, rr - d)
	return worst


func _world(side: String, q: Vector3) -> Vector3:
	if side == "R":
		return Vector3(float(ROOTS[side]) - q.x, q.y, q.z)
	return Vector3(float(ROOTS[side]) + q.x, q.y, q.z)


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
	return (p1 + d1 * s).distance_to(p2 + d2 * t)
