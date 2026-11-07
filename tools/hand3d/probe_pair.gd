# One failing case, one instant: every pair that crosses, with the numbers
# behind it (segment endpoints, distance, radii). Built exactly as
# intersect_test builds the click.
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")
const IK := preload("res://ik.gd")
const Kbd3D := preload("res://kbd3d.gd")
const ClickPath := preload("res://click_path.gd")
const HomePose := preload("res://home_pose.gd")

const ROOTS := {"L": -72.51, "R": 43.94}
const KEY_HOVER := 12.0
const THUMB_HOVER := 5.0
const CLEAR_Z := Kbd3D.FACE_Z + 0.0
const CLEAR_W := 100.0
const DIR_W := 30.0
const APPROACH := 0.35
const PRESS := 0.16
const RELEASE := 0.12
const RETURN := 0.40
const STEPS := 24
const THUMB_R := [11.8, 10.8, 9.6, 6.6]
const MC_R := 10.0
const APART := [["II", "IV"], ["II", "V"], ["III", "V"]]
const ADJACENT := [["II", "III"], ["III", "IV"], ["IV", "V"]]


func _local(side: String, root_x: float, p: Vector3) -> Vector3:
	if side == "R":
		return Vector3(-(p.x - root_x), p.y, p.z)
	return Vector3(p.x - root_x, p.y, p.z)


func _world(side: String, q: Vector3) -> Vector3:
	if side == "R":
		return Vector3(float(ROOTS[side]) - q.x, q.y, q.z)
	return Vector3(float(ROOTS[side]) + q.x, q.y, q.z)


func _pad(ray: String, p: Dictionary) -> Vector3:
	var xf := ArmModel.hand_transform(p.get("arm", {}))
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


func _caps(pose: Dictionary, side: String) -> Dictionary:
	var out := {}
	var xf := ArmModel.hand_transform(pose.get("arm", {}))
	for ray in HandModel.FINGERS:
		var fk: Dictionary = HandModel.finger_fk(ray, pose["fingers"][ray])
		var pts: PackedVector3Array = fk["pts"]
		var rr: Array = HandModel.SKIN_R[ray]
		var cs := []
		for i in 3:
			cs.append({"a": _world(side, xf * pts[i]),
				"b": _world(side, xf * pts[i + 1]),
				"r": maxf(float(rr[i]), float(rr[i + 1])),
				"seg": i, "tag": "%s_%d" % [ray, i]})
		out[ray] = cs
	var tfk: Dictionary = HandModel.thumb_fk(HandModel.thumb_of_pose(pose))
	var tpts: PackedVector3Array = tfk["pts"]
	var tc := []
	for i in 3:
		tc.append({"a": _world(side, xf * tpts[i]),
			"b": _world(side, xf * tpts[i + 1]),
			"r": maxf(float(THUMB_R[i]), float(THUMB_R[i + 1])),
			"seg": i, "tag": "I_%d" % i})
	out["I"] = tc
	var mc := []
	for ray in HandModel.FINGERS:
		mc.append({"a": _world(side, xf * HandModel.MC_BASE[ray]),
			"b": _world(side, xf * HandModel.metacarpal_head(ray)),
			"r": MC_R, "seg": 0, "tag": "MC_%s" % ray})
	out["MC"] = mc
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


func _pen(ca: Dictionary, cb: Dictionary) -> float:
	return maxf(0.0, float(ca["r"]) + float(cb["r"]) -
		_seg_dist(ca["a"], ca["b"], cb["a"], cb["b"]))


func _dump(a: Dictionary, b: Dictionary, what: String) -> void:
	var pairs := []
	for p in APART:
		pairs.append([p[0], p[1], 0])
	for p in ADJACENT:
		pairs.append([p[0], p[1], 1])
	for p in pairs:
		for ca in a[p[0]]:
			if int(ca["seg"]) < int(p[2]):
				continue
			for cb in b[p[1]]:
				if int(cb["seg"]) < int(p[2]):
					continue
				var pen := _pen(ca, cb)
				if pen > 0.1:
					print("  %s %-10s/%-10s pen %5.2f  d %5.2f  r %4.1f+%4.1f" % [
						what, ca["tag"], cb["tag"], pen,
						_seg_dist(ca["a"], ca["b"], cb["a"], cb["b"]),
						float(ca["r"]), float(cb["r"])])
	for cr in HandModel.FINGERS:
		for ca in a["I"]:
			for cb in b[cr]:
				var pen := _pen(ca, cb)
				if pen > 0.1:
					print("  %s %-10s/%-10s pen %5.2f  d %5.2f  r %4.1f+%4.1f" % [
						what, ca["tag"], cb["tag"], pen,
						_seg_dist(ca["a"], ca["b"], cb["a"], cb["b"]),
						float(ca["r"]), float(cb["r"])])


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var side := String(args[0])
	var want := String(args[1])
	var keys := Kbd3D.keys()
	var idx := -1
	for i in keys.size():
		if String(keys[i]["s"]) == want:
			idx = i
			break
	var key: Dictionary = keys[idx]
	var r: Rect2 = key["r"]
	var hx := r.get_center().x
	if r.size.x > Kbd3D.KEY_W * 1.05:
		hx = r.get_center().x + (-0.6 if side == "L" else 0.6) \
			* r.size.x * 0.5
	var hit := Vector2(hx, r.get_center().y)
	var ray := String(Kbd3D.hand_finger(want, hx)[1])
	var root_x: float = ROOTS[side]
	var home: Dictionary = HomePose.build(side, root_x)
	var deep := _local(side, root_x, Vector3(hit.x, hit.y,
		Kbd3D.FACE_Z - Kbd3D.TRAVEL))
	var pr: Dictionary = IK.solve_chain(ray, deep, home,
		{"arm": true, "thumb_dof": 4, "clear_z": CLEAR_Z,
		"clear_w": CLEAR_W, "dir_w": DIR_W})
	var pp: Dictionary = pr["pose"]
	print("=== %s %s ray %s err %.3f" % [side, want, ray,
		float(pr["error"])])
	print("  arm %s" % str(pp["arm"]))
	print("  thumb %s" % str(HandModel.thumb_of_pose(pp)))
	for f in ["II", "III", "IV", "V"]:
		print("  %s %s" % [f, str(pp["fingers"][f])])
	var ppad := _pad(ray, pp)
	var hov := THUMB_HOVER if ray == "I" else KEY_HOVER
	var lift := maxf(0.0, (Kbd3D.FACE_Z + hov) - ppad.z)
	var hp: Dictionary = pp.duplicate(true)
	hp["arm"]["elbow_z"] = float(hp["arm"].get("elbow_z", 0.0)) + lift
	var path: Dictionary = ClickPath.build(home, hp, pp, APPROACH, PRESS,
		RELEASE, RETURN, {"ray": ray, "clear_z": CLEAR_Z,
		"key_rects": _local_keys(side, root_x), "own": idx})
	var total := float(path["total"])
	var other := "R" if side == "L" else "L"
	var idle: Dictionary = HomePose.build(other, float(ROOTS[other]))
	for i in STEPS + 1:
		var t := total * float(i) / float(STEPS)
		var p: Dictionary = ClickPath.at(path, t)
		var caps := _caps(p, side)
		var w := 0.0
		var tag := ""
		for pair in APART:
			for ca in caps[pair[0]]:
				for cb in caps[pair[1]]:
					var q := _pen(ca, cb)
					if q > w:
						w = q
						tag = "%s/%s" % [ca["tag"], cb["tag"]]
		for pair in ADJACENT:
			for ca in caps[pair[0]]:
				if int(ca["seg"]) < 1:
					continue
				for cb in caps[pair[1]]:
					if int(cb["seg"]) < 1:
						continue
					var q := _pen(ca, cb)
					if q > w:
						w = q
						tag = "%s/%s" % [ca["tag"], cb["tag"]]
		for cr in HandModel.FINGERS:
			for ca in caps["I"]:
				for cb in caps[cr]:
					var q := _pen(ca, cb)
					if q > w:
						w = q
						tag = "I/%s" % cb["tag"]
		if w > 0.1:
			print("t %.3f own worst %5.2f %s" % [t, w, tag])
	# Dump one instant in full.
	var t_want := float(args[2]) if args.size() > 2 else 0.086
	var pt: Dictionary = ClickPath.at(path, t_want)
	print("=== detail at t %.3f" % t_want)
	_dump(_caps(pt, side), _caps(pt, side), "own")
	_dump(_caps(pt, side), _caps(idle, other), "hands")
	quit(0)
