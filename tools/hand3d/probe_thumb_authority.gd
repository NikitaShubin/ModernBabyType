# How much can the thumb move OUT of the other hand's way, and what answers
# for it? Two sweeps on a real press pose:
#   A) the thumb's own cmc_abd / cmc_flex, arm frozen — can the thumb adduct
#      away from the centre line, and does its own index stop it?
#   B) the forearm's abduction, thumb frozen — how far does the arm have to
#      back off, i.e. what does the reach pay for the guard?
# Prints the thumb's world x per joint, the cross-hand penetration, and the
# own-hand I/II penetration at every step.
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")
const IK := preload("res://ik.gd")
const Kbd3D := preload("res://kbd3d.gd")
const HomePose := preload("res://home_pose.gd")

const ROOTS := {"L": -72.51, "R": 43.94}
const THUMB_R := [11.8, 10.8, 9.6, 6.6]


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
	print("%s %s ray %s  pad %s  arm fabd %.2f wdev %.2f" % [side, want, ray,
		str(_pad(ray, pp)), float(pp["arm"]["forearm_abd"]),
		float(pp["arm"]["wrist_dev"])])
	var ha: Dictionary = pp["arm"].duplicate(true)
	var ta: Dictionary = HandModel.thumb_of_pose(pp)
	print("A) cmc_abd sweep (arm frozen), home abd %.2f flex %.2f mcp %.2f ip %.2f"
		% [float(ta["cmc_abd"]), float(ta["cmc_flex"]), float(ta["mcp"]),
		float(ta["ip"])])
	for abd in [-25.0, -22.0, -20.0, -18.0, -15.25, -12.0, -9.0, -6.0, 0.0]:
		var a := ta.duplicate()
		a["cmc_abd"] = abd
		var q: Dictionary = pp.duplicate(true)
		q["thumb"] = a
		_row("abd %6.2f" % abd, q, side, idle, other)
	print("B) forearm_abd sweep (thumb frozen at home)")
	for fa in [28.08, 27.0, 26.0, 25.0, 24.0, 23.0, 22.0]:
		var q: Dictionary = pp.duplicate(true)
		q["arm"] = ha.duplicate(true)
		q["arm"]["forearm_abd"] = fa
		var err: float = (_pad(ray, q) - deep).length()
		_row("fabd %6.2f" % fa, q, side, idle, other, err)
	quit(0)


func _row(tag: String, p: Dictionary, side: String, idle: Dictionary,
		other: String, err := -1.0) -> void:
	var xf := ArmModel.hand_transform(p["arm"])
	var tpts: PackedVector3Array = HandModel.thumb_fk(
		HandModel.thumb_of_pose(p))["pts"]
	var xs := []
	for i in 4:
		xs.append("%6.1f" % _world(side, xf * tpts[i]).x)
	var cr := _cross(p, side, idle, other)
	var own := _own(p, side, "II")
	print("  %s  x %s  cross %6.2f  I/II %5.2f%s" % [tag, str(xs), cr, own,
		"" if err < 0.0 else "  err %6.2f" % err])


func _own(p: Dictionary, side: String, ray: String) -> float:
	var xf := ArmModel.hand_transform(p["arm"])
	var tpts: PackedVector3Array = HandModel.thumb_fk(
		HandModel.thumb_of_pose(p))["pts"]
	var pts: PackedVector3Array = HandModel.finger_fk(ray,
		p["fingers"][ray])["pts"]
	var worst := 0.0
	for i in 3:
		for j in 3:
			var d := _seg_dist(xf * tpts[i], xf * tpts[i + 1],
				xf * pts[j], xf * pts[j + 1])
			var rr := maxf(float(THUMB_R[i]), float(THUMB_R[i + 1])) \
				+ maxf(float(HandModel.SKIN_R[ray][j]),
					float(HandModel.SKIN_R[ray][j + 1]))
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


func _pad(ray: String, p: Dictionary) -> Vector3:
	var xf := ArmModel.hand_transform(p["arm"])
	if ray == "I":
		return xf * HandModel.thumb_pad(HandModel.thumb_fk(
			HandModel.thumb_of_pose(p)))
	return xf * HandModel.finger_pad(ray,
		HandModel.finger_fk(ray, p["fingers"][ray]))


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
