# The press of one key, stage by stage: the natural press, the clearance
# refine, and what the tuck does to the idle index finger. The question: is the
# II/III crossing created by the tuck uncurling II, and does the tuck see it?
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
		"dir_w": 30.0, "tuck": false}
	var s1: Dictionary = IK._solve_once(ray, deep, home,
		_merge(base, {"clear_w": 0.0}))
	var s2: Dictionary = IK._solve_once(ray, deep, s1["pose"],
		_merge(base, {"clear_w": 100.0, "idle_sink": 0.5}))
	_show("natural", s1["pose"], ray)
	_show("refine", s2["pose"], ray)
	var out: Dictionary = (s2["pose"] as Dictionary).duplicate(true)
	IK.clear_z = Kbd3D.FACE_Z
	IK.clear_w = 100.0
	IK.idle_sink = 0.5
	IK._tuck_others(ray, out, 0.0)
	_show("tuck0", out, ray)
	IK._tuck_others(ray, out, 2.0)
	_show("tuck2", out, ray)
	quit(0)


func _merge(a: Dictionary, b: Dictionary) -> Dictionary:
	var o := a.duplicate(true)
	for k in b:
		o[k] = b[k]
	return o


func _show(tag: String, p: Dictionary, ray: String) -> void:
	var xf := ArmModel.hand_transform(p["arm"])
	print("--- %s err? arm %s" % [tag, str(p["arm"])])
	for f in ["II", "III", "IV", "V"]:
		var a: Dictionary = p["fingers"][f]
		var fk: Dictionary = HandModel.finger_fk(f, a)
		var pts: PackedVector3Array = fk["pts"]
		var rr: Array = HandModel.SKIN_R[f]
		var lo := []
		for j in 4:
			var w: Vector3 = xf * pts[j]
			lo.append(str(snappedf(w.z - float(rr[j]) - Kbd3D.FACE_Z, 0.01)))
		var v := IK._finger_violation(xf, f, a, 0.0)
		print("  %s mcp %6.2f pip %6.2f dip %6.2f fan %6.2f viol %5.2f z-r %s"
			% [f, float(a["mcp"]), float(a["pip"]), float(a["dip"]),
			float(a["fan"]), v, str(lo)])
	var c2 := _caps(xf, "II", p["fingers"]["II"])
	var c3 := _caps(xf, "III", p["fingers"]["III"])
	var worst := 0.0
	for i in 3:
		if i < 1:
			continue
		for j in 3:
			if j < 1:
				continue
			var d := _seg_dist(c2[i]["a"], c2[i]["b"], c3[j]["a"], c3[j]["b"])
			var pen := float(c2[i]["r"]) + float(c3[j]["r"]) - d
			if pen > worst:
				worst = pen
	print("  II/III worst pen %.2f" % worst)


func _caps(xf: Transform3D, ray: String, a: Dictionary) -> Array:
	var pts: PackedVector3Array = HandModel.finger_fk(ray, a)["pts"]
	var rr: Array = HandModel.SKIN_R[ray]
	var out := []
	for i in 3:
		out.append({"a": xf * pts[i], "b": xf * pts[i + 1],
			"r": maxf(float(rr[i]), float(rr[i + 1]))})
	return out


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
