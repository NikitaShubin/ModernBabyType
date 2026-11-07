# The thumb's pad target is one point and its chain has four joints, so the
# poses that reach it form a curve. The solver lands on the cheapest point of
# that curve, and on the home pose the cheapest point HOOKS: the IP joint sits
# inboard of the pad (left x -5.0, right +9.0), so the two middle phalanges
# cross by 7.4 mm although the pads are 41 mm apart.
#
# This probe walks the whole curve instead of trusting the solver: take the
# Jacobian of the pad with respect to the four joints, step along its null
# direction, and pull the pad back onto the target with minimum-norm Newton
# corrections. Every step is a real pose that touches the same point. Printing
# the IP joint's x along the curve answers one question: does ANY pose on it
# put the IP joint outboard of the pad?
#
#   mbt-godot --headless --path /work/tools/hand3d --script res://thumb_family_walk.gd
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")
const IK := preload("res://ik.gd")
const Kbd3D := preload("res://kbd3d.gd")
const HomePose := preload("res://home_pose.gd")

const ROOTS := {"L": -72.51, "R": 43.94}
const THUMB_R := [11.8, 10.8, 9.6, 6.6]
const WALK := 2.4
const WALK_STEPS := 96


func _world(side: String, q: Vector3) -> Vector3:
	if side == "R":
		return Vector3(float(ROOTS[side]) - q.x, q.y, q.z)
	return Vector3(float(ROOTS[side]) + q.x, q.y, q.z)


func _angles(q: Array) -> Dictionary:
	return IK.thumb_angles_of_shares(q)


func _pad(side: String, xf: Transform3D, q: Array) -> Vector3:
	return xf * HandModel.thumb_pad(HandModel.thumb_fk(_angles(q)))


func _jac(side: String, xf: Transform3D, q: Array) -> Array:
	var p0 := _pad(side, xf, q)
	var cols := []
	for j in 4:
		# A joint pinned at its stop has a zero FORWARD difference (the clamp
		# eats the step), and a zero column reads as "this joint cannot move
		# the pad" — the null vector then points along it and the walk is
		# trapped at the stop. Take the difference that goes back into the
		# range instead.
		var d := 0.005
		if float(q[j]) > 0.995:
			d = -0.005
		elif float(q[j]) < -0.995:
			d = 0.005
		var qq: Array = q.duplicate()
		qq[j] = clampf(float(qq[j]) + d, -1.0, 1.0)
		var p1 := _pad(side, xf, qq)
		cols.append((p1 - p0) / d)
	return cols


static func _cross3(a: Vector3, b: Vector3) -> Vector3:
	return Vector3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z,
		a.x * b.y - a.y * b.x)


# The null vector of a 3x4 Jacobian, by cofactors (the 4D cross product).
static func _null(cols: Array) -> Array:
	var a: Vector3 = cols[0]
	var b: Vector3 = cols[1]
	var c: Vector3 = cols[2]
	var d: Vector3 = cols[3]
	var n := [_cross3(b, c).dot(d), -_cross3(a, c).dot(d),
		_cross3(a, b).dot(d), -_cross3(a, b).dot(c)]
	var m := sqrt(float(n[0]) * float(n[0]) + float(n[1]) * float(n[1])
		+ float(n[2]) * float(n[2]) + float(n[3]) * float(n[3]))
	if m < 1e-12:
		return [0.0, 0.0, 0.0, 0.0]
	return [float(n[0]) / m, float(n[1]) / m, float(n[2]) / m, float(n[3]) / m]


# Minimum-norm correction: dq = -J^T (J J^T + lam I)^-1 e, 3x3 by Cramer.
static func _correct(cols: Array, e: Vector3, lam: float) -> Array:
	var g := [[0.0, 0.0, 0.0], [0.0, 0.0, 0.0], [0.0, 0.0, 0.0]]
	for i in 3:
		for j in 3:
			var s := 0.0
			for k in 4:
				s += (cols[k] as Vector3)[i] * (cols[k] as Vector3)[j]
			g[i][j] = s
		g[i][i] += lam
	var det := float(g[0][0]) * (float(g[1][1]) * float(g[2][2])
		- float(g[1][2]) * float(g[2][1])) \
		- float(g[0][1]) * (float(g[1][0]) * float(g[2][2])
		- float(g[1][2]) * float(g[2][0])) \
		+ float(g[0][2]) * (float(g[1][0]) * float(g[2][1])
		- float(g[1][1]) * float(g[2][0]))
	if absf(det) < 1e-14:
		return [0.0, 0.0, 0.0, 0.0]
	var y := []
	for i in 3:
		var m := []
		for r in 3:
			var row := []
			for c in 3:
				row.append(float(g[r][c]))
			m.append(row)
		for r in 3:
			m[r][i] = e[r]
		y.append((float(m[0][0]) * (float(m[1][1]) * float(m[2][2])
			- float(m[1][2]) * float(m[2][1]))
			- float(m[0][1]) * (float(m[1][0]) * float(m[2][2])
			- float(m[1][2]) * float(m[2][0]))
			+ float(m[0][2]) * (float(m[1][0]) * float(m[2][1])
			- float(m[1][1]) * float(m[2][0]))) / det)
	var dq := []
	for k in 4:
		var s := 0.0
		for i in 3:
			s += (cols[k] as Vector3)[i] * float(y[i])
		dq.append(-s)
	return dq


func _energy(q: Array) -> float:
	var e := 0.0
	for v in q:
		e += float(v) * float(v)
	return e


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


func _walk(side: String) -> Array:
	var root_x: float = ROOTS[side]
	var home: Dictionary = HomePose.build(side, root_x)
	var xf := ArmModel.hand_transform(home["arm"])
	var tgt: Vector3 = HomePose.target(side, "I", root_x)
	var q: Array = IK.thumb_shares_of(HandModel.thumb_of_pose(home))
	var n: Array = _null(_jac(side, xf, q))
	print("=== %s target %s  start q %s  null %s" % [side, str(tgt), str(q),
		str(n)])
	var fam := []
	for i in WALK_STEPS + 1:
		var t := -WALK + 2.0 * WALK * float(i) / float(WALK_STEPS)
		var qt := []
		for k in 4:
			qt.append(clampf(float(q[k]) + t * float(n[k]), -1.0, 1.0))
		for it in 12:
			var e := _pad(side, xf, qt) - tgt
			if e.length() < 0.01:
				break
			var dq := _correct(_jac(side, xf, qt), e, 1e-6)
			for k in 4:
				qt[k] = clampf(float(qt[k]) + float(dq[k]), -1.0, 1.0)
		var err := (_pad(side, xf, qt) - tgt).length()
		if err > 0.05:
			continue
		var fk: Dictionary = HandModel.thumb_fk(_angles(qt))
		var pts: PackedVector3Array = fk["pts"]
		fam.append({"q": qt, "t": t, "ip": _world(side, xf * pts[2]).x,
			"tip": _world(side, xf * pts[3]).x,
			"pad": _world(side, xf * HandModel.thumb_pad(fk)).x,
			"e": _energy(qt), "err": err,
			"angles": _angles(qt)})
	print("  family members %d" % fam.size())
	var lo := 1e9
	var hi := -1e9
	for m in fam:
		lo = minf(lo, float(m["ip"]))
		hi = maxf(hi, float(m["ip"]))
	print("  IP x range %7.2f .. %7.2f" % [lo, hi])
	var by_ip: Array = fam.duplicate()
	by_ip.sort_custom(func(a, b): return float(a["ip"]) < float(b["ip"]))
	for idx in [0, by_ip.size() / 4, by_ip.size() / 2, by_ip.size() * 3 / 4,
			by_ip.size() - 1]:
		var m: Dictionary = by_ip[idx]
		print("    t %6.2f  E %6.3f  IP x %7.2f  tip x %7.2f  pad x %7.2f  %s"
			% [float(m["t"]), float(m["e"]), float(m["ip"]), float(m["tip"]),
			float(m["pad"]), str(m["angles"])])
	return fam


func _gap(a: Dictionary, b: Dictionary, xfa: Transform3D, xfb: Transform3D,
		sa: String, sb: String) -> float:
	var ja: PackedVector3Array = HandModel.thumb_fk(a["angles"])["pts"]
	var jb: PackedVector3Array = HandModel.thumb_fk(b["angles"])["pts"]
	var worst := 1e9
	for i in 3:
		for k in 3:
			var d := _seg_dist(_world(sa, xfa * ja[i]), _world(sa, xfa * ja[i + 1]),
				_world(sb, xfb * jb[k]), _world(sb, xfb * jb[k + 1]))
			var g := d - maxf(float(THUMB_R[i]), float(THUMB_R[i + 1])) \
				- maxf(float(THUMB_R[k]), float(THUMB_R[k + 1]))
			worst = minf(worst, g)
	return worst


func _init() -> void:
	var fl := _walk("L")
	var fr := _walk("R")
	var xfl := ArmModel.hand_transform(HomePose.build("L", ROOTS["L"])["arm"])
	var xfr := ArmModel.hand_transform(HomePose.build("R", ROOTS["R"])["arm"])
	var best := -1e9
	var best_l := {}
	var best_r := {}
	for a in fl:
		for b in fr:
			var g := _gap(a, b, xfl, xfr, "L", "R")
			if g > best:
				best = g
				best_l = a
				best_r = b
	print("== best pair over both families: gap %6.2f mm" % best)
	if not best_l.is_empty():
		print("   L t %6.2f E %6.3f IP x %7.2f %s" % [float(best_l["t"]),
			float(best_l["e"]), float(best_l["ip"]), str(best_l["angles"])])
		print("   R t %6.2f E %6.3f IP x %7.2f %s" % [float(best_r["t"]),
			float(best_r["e"]), float(best_r["ip"]), str(best_r["angles"])])
	quit(0)
