# Continuation by LIFTING THE ARM instead of tucking the idle fingers: the
# natural press hangs them under the key face, so raise the whole arm by the
# violation and let the refine flex the pressing finger back down. The
# question: does the arm stay high (idle fingers home, no collisions) or does
# the solver drop it back into the same valley?
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
	var base := {"arm": true, "thumb_dof": 4, "clear_z": Kbd3D.FACE_Z,
		"dir_w": 30.0, "tuck": false}
	var s1: Dictionary = IK._solve_once(ray, deep, home,
		_merge(base, {"clear_w": 0.0}))
	_show("natural", s1["pose"], ray)
	var v := IK.clearance(ray, s1["pose"], Kbd3D.FACE_Z, Rect2(), 0.0)
	print("lift %.2f" % v)
	var up: Dictionary = (s1["pose"] as Dictionary).duplicate(true)
	up["arm"]["elbow_z"] = float(up["arm"].get("elbow_z", 0.0)) + v
	_show("lifted", up, ray)
	var s2: Dictionary = IK._solve_once(ray, deep, up,
		_merge(base, {"clear_w": 100.0, "idle_sink": 0.5}))
	_show("refine", s2["pose"], ray)
	quit(0)


func _merge(a: Dictionary, b: Dictionary) -> Dictionary:
	var o := a.duplicate(true)
	for k in b:
		o[k] = b[k]
	return o


func _show(tag: String, p: Dictionary, ray: String) -> void:
	var xf := ArmModel.hand_transform(p["arm"])
	var pad := Vector3.ZERO
	if ray == "I":
		pad = xf * HandModel.thumb_pad(HandModel.thumb_fk(
			HandModel.thumb_of_pose(p)))
	else:
		pad = xf * HandModel.finger_pad(ray,
			HandModel.finger_fk(ray, p["fingers"][ray]))
	print("--- %s pad %s arm %s" % [tag, str(pad), str(p["arm"])])
	var tfk: Dictionary = HandModel.thumb_fk(HandModel.thumb_of_pose(p))
	var tpts: PackedVector3Array = tfk["pts"]
	print("    thumb tip %s pad %s" % [str(xf * tpts[3]),
		str(xf * HandModel.thumb_pad(tfk))])
	print("    thumb %s" % str(HandModel.thumb_of_pose(p)))
	for f in ["II", "III", "IV", "V"]:
		var a: Dictionary = p["fingers"][f]
		print("  %s mcp %6.2f pip %6.2f dip %6.2f fan %6.2f viol %5.2f"
			% [f, float(a["mcp"]), float(a["pip"]), float(a["dip"]),
			float(a["fan"]), IK._finger_violation(xf, f, a, 0.0)])
	print("  keyclr %.2f  I/II %.2f  II/III %.2f" % [
		IK.clearance(ray, p, Kbd3D.FACE_Z, Rect2(), 0.0),
		_thumb_finger(xf, p, "II"), _pair(xf, p, "II", "III")])


func _thumb_finger(xf: Transform3D, p: Dictionary, ray: String) -> float:
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


func _pair(xf: Transform3D, p: Dictionary, a: String, b: String) -> float:
	var pa: PackedVector3Array = HandModel.finger_fk(a,
		p["fingers"][a])["pts"]
	var pb: PackedVector3Array = HandModel.finger_fk(b,
		p["fingers"][b])["pts"]
	var worst := 0.0
	for i in range(1, 3):
		for j in range(1, 3):
			var d := _seg_dist(xf * pa[i], xf * pa[i + 1],
				xf * pb[j], xf * pb[j + 1])
			var rr := maxf(float(HandModel.SKIN_R[a][i]),
				float(HandModel.SKIN_R[a][i + 1])) \
				+ maxf(float(HandModel.SKIN_R[b][j]),
					float(HandModel.SKIN_R[b][j + 1]))
			worst = maxf(worst, rr - d)
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
