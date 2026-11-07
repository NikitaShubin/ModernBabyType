# The pairs that sit closest in the HOME pose and in the PRESS pose of one key:
# the thumb's proximal phalanx against the index's proximal one (the web), and
# the index/middle middle phalanges. The question: is the 0.58 mm on L "3" a
# crossing the animation creates, or the web's own constant adjacency that the
# capsule proxy always reports?
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
	_report("home", home)
	var pr: Dictionary = IK.solve_chain(ray, deep, home,
		{"arm": true, "thumb_dof": 4, "clear_z": Kbd3D.FACE_Z,
		"clear_w": 100.0, "dir_w": 30.0})
	_report("press", pr["pose"])
	quit(0)


func _report(tag: String, p: Dictionary) -> void:
	var xf := ArmModel.hand_transform(p["arm"])
	print("=== %s arm %s" % [tag, str(p["arm"])])
	var tpts: PackedVector3Array = HandModel.thumb_fk(
		HandModel.thumb_of_pose(p))["pts"]
	for ray in ["II", "III"]:
		var pts: PackedVector3Array = HandModel.finger_fk(ray,
			p["fingers"][ray])["pts"]
		for ti in 3:
			for j in 3:
				var d := _seg_dist(xf * tpts[ti], xf * tpts[ti + 1],
					xf * pts[j], xf * pts[j + 1])
				var rr := maxf(float(THUMB_R[ti]), float(THUMB_R[ti + 1])) \
					+ maxf(float(HandModel.SKIN_R[ray][j]),
						float(HandModel.SKIN_R[ray][j + 1]))
				if rr - d > -1.0:
					print("  I_%d/%s_%d d %6.2f r %5.2f pen %5.2f" % [ti, ray, j, d, rr, rr - d])
	for pair in [["II", "III"], ["III", "IV"], ["IV", "V"]]:
		var a: PackedVector3Array = HandModel.finger_fk(pair[0],
			p["fingers"][pair[0]])["pts"]
		var b: PackedVector3Array = HandModel.finger_fk(pair[1],
			p["fingers"][pair[1]])["pts"]
		for i in range(1, 3):
			for j in range(1, 3):
				var d := _seg_dist(xf * a[i], xf * a[i + 1],
					xf * b[j], xf * b[j + 1])
				var rr := maxf(float(HandModel.SKIN_R[pair[0]][i]),
					float(HandModel.SKIN_R[pair[0]][i + 1])) \
					+ maxf(float(HandModel.SKIN_R[pair[1]][j]),
						float(HandModel.SKIN_R[pair[1]][j + 1]))
				if rr - d > -1.0:
					print("  %s_%d/%s_%d d %6.2f r %5.2f pen %5.2f" % [pair[0], i, pair[1], j, d, rr, rr - d])


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
