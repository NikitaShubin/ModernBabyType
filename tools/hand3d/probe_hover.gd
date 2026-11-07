# Where along the click does the other hand get hit, and is it the press or the
# hover? Solves with the other hand as an obstacle, builds the path the test
# builds, and prints the cross-hand penetration at every sample together with
# the thumb's tip in world coordinates. The hover is a rigid lift of the press
# pose, so a press that clears by a tenth of a millimetre can still climb into
# the other thumb's knuckle.
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")
const IK := preload("res://ik.gd")
const Kbd3D := preload("res://kbd3d.gd")
const ClickPath := preload("res://click_path.gd")
const HomePose := preload("res://home_pose.gd")

const ROOTS := {"L": -122.51, "R": 93.94}
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
	var other := "R" if side == "L" else "L"
	var idle: Dictionary = HomePose.build(other, float(ROOTS[other]))
	var foreign := _foreign(idle, other, side, root_x)
	var hov := THUMB_HOVER if ray == "I" else KEY_HOVER
	var pr: Dictionary = IK.solve_chain(ray, deep, home,
		{"arm": true, "thumb_dof": 4, "clear_z": Kbd3D.FACE_Z,
		"clear_w": 100.0, "dir_w": 30.0, "foreign": foreign,
		"hover_z": Kbd3D.FACE_Z + hov})
	var pp: Dictionary = pr["pose"]
	var ppad := _pad(ray, pp)
	var lift := maxf(0.0, (Kbd3D.FACE_Z + hov) - ppad.z)
	var hp: Dictionary = pp.duplicate(true)
	hp["arm"]["elbow_z"] = float(hp["arm"].get("elbow_z", 0.0)) + lift
	print("%s %s ray %s  lift %.2f  thumb %s" % [side, want, ray, lift,
		str(_t(pp))])
	# Call the tuck again, by hand, with the same obstacles: does the search
	# improve, or is it already at its own answer?
	var old_fo := IK.set_foreign(foreign)
	IK.dbg = true
	var e0: Dictionary = IK._thumb_eval(ArmModel.hand_transform(pp["arm"]),
		HandModel.thumb_of_pose(pp), pp["fingers"])
	IK._tuck_thumb(pp)
	IK.restore_foreign(old_fo)
	var e1: Dictionary = IK._thumb_eval(ArmModel.hand_transform(pp["arm"]),
		HandModel.thumb_of_pose(pp), pp["fingers"])
	print("  tuck again: v %.3f p %.3f f %.3f -> v %.3f p %.3f f %.3f  thumb %s"
		% [float(e0["v"]), float(e0["p"]), float(e0["f"]), float(e1["v"]),
		float(e1["p"]), float(e1["f"]), str(_t(pp))])
	print("  press cross %6.2f   hover cross %6.2f" % [_cross(pp, side, idle,
		other), _cross(hp, side, idle, other)])
	var path: Dictionary = ClickPath.build(home, hp, pp, 0.35, 0.16, 0.12,
		0.40, {"ray": ray, "clear_z": Kbd3D.FACE_Z,
		"key_rects": _local_keys(side, root_x), "own": idx})
	var total := float(path["total"])
	var worst := 0.0
	var worst_t := 0.0
	for i in STEPS + 1:
		var t := total * float(i) / float(STEPS)
		var p: Dictionary = ClickPath.at(path, t)
		var c := _cross(p, side, idle, other)
		if c > worst:
			worst = c
			worst_t = t
		if i % 4 == 0 or c > 0.1:
			var xf := ArmModel.hand_transform(p["arm"])
			var tp: PackedVector3Array = HandModel.thumb_fk(
				HandModel.thumb_of_pose(p))["pts"]
			var w: Vector3 = _world(side, xf * tp[3])
			print("  t %.3f cross %6.2f  tip (%6.1f %6.1f %6.1f)  elbow_z %6.1f"
				% [t, c, w.x, w.y, w.z, float(p["arm"]["elbow_z"])])
	print("  worst %.2f at t %.3f" % [worst, worst_t])
	quit(0)


func _t(p: Dictionary) -> Array:
	var a: Dictionary = HandModel.thumb_of_pose(p)
	return [snappedf(float(a["cmc_flex"]), 0.01),
		snappedf(float(a["cmc_abd"]), 0.01), snappedf(float(a["mcp"]), 0.01),
		snappedf(float(a["ip"]), 0.01)]


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


func _foreign(idle: Dictionary, other: String, side: String,
		root_x: float) -> Array:
	var sgn := -1.0 if side == "R" else 1.0
	var xf := ArmModel.hand_transform(idle["arm"])
	var out := []
	var tpts: PackedVector3Array = HandModel.thumb_fk(
		HandModel.thumb_of_pose(idle))["pts"]
	for i in 3:
		out.append({"a": _loc(sgn, root_x, _world(other, xf * tpts[i])),
			"b": _loc(sgn, root_x, _world(other, xf * tpts[i + 1])),
			"r": maxf(float(THUMB_R[i]), float(THUMB_R[i + 1]))})
	for ray in HandModel.FINGERS:
		var pts: PackedVector3Array = HandModel.finger_fk(ray,
			idle["fingers"][ray])["pts"]
		var rr: Array = HandModel.SKIN_R[ray]
		for i in 3:
			out.append({"a": _loc(sgn, root_x, _world(other, xf * pts[i])),
				"b": _loc(sgn, root_x, _world(other, xf * pts[i + 1])),
				"r": maxf(float(rr[i]), float(rr[i + 1]))})
	return out


func _loc(sgn: float, root_x: float, w: Vector3) -> Vector3:
	return Vector3((w.x - root_x) * sgn, w.y, w.z)


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
		if side == "R":
			out.append(Rect2(-(r.end.x - root_x), r.position.y, r.size.x,
				r.size.y))
		else:
			out.append(Rect2(r.position.x - root_x, r.position.y, r.size.x,
				r.size.y))
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
