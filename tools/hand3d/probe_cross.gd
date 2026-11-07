# The cross-hand thumb collision: at the worst instant of one click, where are
# the two thumbs in world x? Prints every thumb joint of both hands, the arm,
# and the penetration, so the fix can be aimed at the joint that actually
# crosses the centre line.
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")
const IK := preload("res://ik.gd")
const Kbd3D := preload("res://kbd3d.gd")
const ClickPath := preload("res://click_path.gd")
const HomePose := preload("res://home_pose.gd")

const ROOTS := {"L": -72.51, "R": 43.94}
const THUMB_R := [11.8, 10.8, 9.6, 6.6]
const KEY_HOVER := 12.0
const THUMB_HOVER := 5.0
const STEPS := 24


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
	var ppad := _pad(ray, pp)
	var hov := THUMB_HOVER if ray == "I" else KEY_HOVER
	var lift := maxf(0.0, (Kbd3D.FACE_Z + hov) - ppad.z)
	var hp: Dictionary = pp.duplicate(true)
	hp["arm"]["elbow_z"] = float(hp["arm"].get("elbow_z", 0.0)) + lift
	var path: Dictionary = ClickPath.build(home, hp, pp, 0.35, 0.16, 0.12,
		0.40, {"ray": ray, "clear_z": Kbd3D.FACE_Z,
		"key_rects": _local_keys(side, root_x), "own": idx})
	var other := "R" if side == "L" else "L"
	var idle: Dictionary = HomePose.build(other, float(ROOTS[other]))
	var total := float(path["total"])
	var worst := 0.0
	var worst_t := 0.0
	for i in STEPS + 1:
		var t := total * float(i) / float(STEPS)
		var p: Dictionary = ClickPath.at(path, t)
		var w := _cross_thumb(p, side, idle, other)
		if w > worst:
			worst = w
			worst_t = t
	print("%s %s ray %s  worst %.2f at t %.3f" % [side, want, ray, worst,
		worst_t])
	var pt: Dictionary = ClickPath.at(path, worst_t)
	_dump("press", pt, side)
	_dump("idle ", idle, other)
	quit(0)


func _dump(tag: String, p: Dictionary, side: String) -> void:
	var root_x: float = ROOTS[side]
	var xf := ArmModel.hand_transform(p["arm"])
	var tpts: PackedVector3Array = HandModel.thumb_fk(
		HandModel.thumb_of_pose(p))["pts"]
	var xs := []
	for i in 4:
		var w: Vector3 = _world(side, xf * tpts[i])
		xs.append("%6.1f" % w.x)
	print("  %s %s thumb world x %s  arm %s" % [tag, side, str(xs),
		str(p["arm"])])


func _cross_thumb(a: Dictionary, sa: String, b: Dictionary,
		sb: String) -> float:
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


func _local_keys(side: String, root_x: float) -> Array:
	var out := []
	for k in Kbd3D.keys():
		var r: Rect2 = k["r"]
		var p := r.position
		var x := p.x - root_x
		if side == "R":
			x = -x - r.size.x
		out.append(Rect2(x, p.y, r.size.x, r.size.y))
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
