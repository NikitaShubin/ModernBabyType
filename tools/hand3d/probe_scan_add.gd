# The tuck's candidate scan for one idle finger: keyboard violation and the
# capsule penetration against the pressing finger, as a function of the uniform
# flexion share added. The question: does CURLING clear the keyboard too, and
# at what |add|, compared with the uncurl the tuck picked?
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")
const IK := preload("res://ik.gd")
const Kbd3D := preload("res://kbd3d.gd")
const HomePose := preload("res://home_pose.gd")

const ROOTS := {"L": -72.51, "R": 43.94}


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var side := String(args[0]) if args.size() > 0 else "L"
	var want := String(args[1]) if args.size() > 1 else "3"
	var keys := Kbd3D.keys()
	var key: Dictionary = keys[Kbd3D.index_of(keys, want)]
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
	var base := {"arm": true, "thumb_dof": 4, "clear_z": Kbd3D.FACE_Z,
		"dir_w": 30.0, "tuck": false, "clear_w": 0.0}
	var s1: Dictionary = IK._solve_once(ray, deep, home, base)
	var p: Dictionary = s1["pose"]
	var xf := ArmModel.hand_transform(p["arm"])
	IK.clear_z = Kbd3D.FACE_Z
	IK.clear_w = 100.0
	IK.idle_sink = 0.5
	print("=== %s %s ray %s" % [side, want, ray])
	for other in ["II", "III", "IV", "V"]:
		if other == ray:
			continue
		var a0: Dictionary = p["fingers"][other]
		var s := IK.shares_of(other, a0)
		print("--- %s base %s shares %s" % [other, str(a0), str(s)])
		for it in 21:
			var add := -1.0 + float(it) / 10.0
			var a := IK._curled(other, s, add)
			var v := IK._finger_violation(xf, other, a, 0.0)
			var pen := _pair_pen(xf, other, a, ray, p["fingers"][ray])
			if v <= 0.05 or pen > 0.05:
				print("  add %5.2f viol %6.2f pen %5.2f" % [add, v, pen])
	quit(0)


func _pair_pen(xf: Transform3D, ray: String, a: Dictionary,
		other: String, b: Dictionary) -> float:
	var pa: PackedVector3Array = HandModel.finger_fk(ray, a)["pts"]
	var pb: PackedVector3Array = HandModel.finger_fk(other, b)["pts"]
	var ra: Array = HandModel.SKIN_R[ray]
	var rb: Array = HandModel.SKIN_R[other]
	var worst := 0.0
	for i in 3:
		if i < 1:
			continue
		for j in 3:
			if j < 1:
				continue
			var d := _seg_dist(xf * pa[i], xf * pa[i + 1],
				xf * pb[j], xf * pb[j + 1])
			var pen := maxf(float(ra[i]), float(ra[i + 1])) \
				+ maxf(float(rb[j]), float(rb[j + 1])) - d
			worst = maxf(worst, pen)
	return worst


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
