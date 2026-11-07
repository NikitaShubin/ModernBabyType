# The author's rule (31.10.2026): "при любой анимации касаний, а тем более
# пересечений рук и пальцев быть не должно. Можешь сделать это отдельным
# тестом. Сейчас большие пальцы пересекаются из-за непараллельности
# предплечий и отсутствия разведения кистей."
#
# This is that test. It plays the SAME click the viewer plays — the press solved
# with the whole arm free, the hover pulled straight back, the path one C1 PCHIP
# (click_path.gd) — and at every sampled instant measures the two hands against
# each other and a hand against itself.
#
# The measure is the SDF's own soft tissue, not an invented box: every bone is a
# capsule whose end radii are the skin radii the mesh is built from (SKIN_R for
# the four fingers, the thumb's own four radii, THUMB_TIP_R at its tip). Two
# capsules cross when the distance between their bone segments is less than the
# sum of their radii. A pair at exactly zero is CONTACT (a finger may touch a
# neighbour); only penetration counts as a crossing.
#
# Which pairs are checked, and why the rest are not:
#   · left hand vs right hand — every capsule, metacarpals included (they are
#     the palm's proxy): this is the thumbs' rule;
#   · non-adjacent fingers of one hand (II–IV, II–V, III–V) — all segments;
#   · adjacent fingers (II–III, III–IV, IV–V) — only from the PIP outward: the
#     proximal segments meet at the knuckle by anatomy, the web between them is
#     shared skin, and a capsule sum of ~20 mm across a 19.05 mm pitch would
#     "cross" on every real hand at rest. From the PIP the flesh is separate;
#   · the thumb against every finger of its own hand — all segments;
#   · NOT the thumb against its own palm, nor a finger against its own palm:
#     they are one body. The thumb's base sits inside the thenar by
#     construction, and a fist legitimately brings a fingertip to the palm.
#
#   mbt-godot --headless --path /work/tools/hand3d --script res://intersect_test.gd
#   ... -- all              # every key of the board (the default)
#   ... -- L глобус         # one hand, one key
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")
const IK := preload("res://ik.gd")
const Kbd3D := preload("res://kbd3d.gd")
const ClickPath := preload("res://click_path.gd")
const HomePose := preload("res://home_pose.gd")

const ROOTS := {"L": -122.51, "R": 93.94}
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
const PEN_TOL := 0.1            # mm of penetration that counts as a crossing
const THUMB_R := [11.8, 10.8, 9.6, 6.6]
const MC_R := 10.0              # the palm's proxy, cross-hand checks only

const APART := [["II", "IV"], ["II", "V"], ["III", "V"]]
const ADJACENT := [["II", "III"], ["III", "IV"], ["IV", "V"]]

var _keys: Array


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
	for k in _keys:
		var r: Rect2 = k["r"]
		if side == "R":
			out.append(Rect2(-(r.end.x - root_x), r.position.y, r.size.x,
				r.size.y))
		else:
			out.append(Rect2(r.position.x - root_x, r.position.y, r.size.x,
				r.size.y))
	return out


# Every capsule of one hand in WORLD space: four fingers, the thumb, and the
# four metacarpals (the palm's proxy, used by the cross-hand pass only).
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
				"ra": float(rr[i]), "rb": float(rr[i + 1]),
				"seg": i, "tag": "%s_%d" % [ray, i]})
		out[ray] = cs
	var tfk: Dictionary = HandModel.thumb_fk(HandModel.thumb_of_pose(pose))
	var tpts: PackedVector3Array = tfk["pts"]
	var tc := []
	for i in 3:
		tc.append({"a": _world(side, xf * tpts[i]),
			"b": _world(side, xf * tpts[i + 1]),
			"r": maxf(float(THUMB_R[i]), float(THUMB_R[i + 1])),
			"ra": float(THUMB_R[i]), "rb": float(THUMB_R[i + 1]),
			"seg": i, "tag": "I_%d" % i})
	out["I"] = tc
	var mc := []
	for ray in HandModel.FINGERS:
		var mb: Vector3 = HandModel.MC_BASE[ray]
		mc.append({"a": _world(side, xf * mb),
			"b": _world(side, xf * HandModel.metacarpal_head(ray)),
			"r": MC_R, "ra": MC_R, "rb": MC_R, "seg": 0,
			"tag": "MC_%s" % ray})
	out["MC"] = mc
	return out


# The other hand's capsules in THIS hand's model frame — the frame `deep` is
# in, which is the only one the solver knows. Mirrored by the solving hand's
# own root and sign, so the solver sees the other hand exactly where it is.
func _foreign(idle: Dictionary, other: String, side: String,
		root_x: float) -> Array:
	var caps := _caps(idle, other)
	var sgn := -1.0 if side == "R" else 1.0
	var out := []
	for ray in caps:
		for c in caps[ray]:
			var a: Vector3 = c["a"]
			var b: Vector3 = c["b"]
			out.append({"a": Vector3((a.x - root_x) * sgn, a.y, a.z),
				"b": Vector3((b.x - root_x) * sgn, b.y, b.z),
				"r": float(c["r"]),
				"ra": float(c.get("ra", c["r"])),
				"rb": float(c.get("rb", c["r"]))})
	return out


# The shortest distance between two segments (Ericson, Real-Time Collision
# Detection, 5.1.9) AND the closest points' parameters, so a capsule's radius
# can taper from one joint to the next. The doc above promises "end radii are
# the skin radii the mesh is built from"; the old max-of-two shortcut broke
# that promise and read the two resting thumbs (tips 6.6, DIPs 9.6) as
# 0.92 mm inside each other when the tapered flesh is 5.08 mm clear
# (measured 03.11.2026).
func _seg_pts(p1: Vector3, q1: Vector3, p2: Vector3, q2: Vector3) -> Array:
	var d1 := q1 - p1
	var d2 := q2 - p2
	var r := p1 - p2
	var a := d1.dot(d1)
	var e := d2.dot(d2)
	var f := d2.dot(r)
	var s := 0.0
	var t := 0.0
	if a <= 1e-12 and e <= 1e-12:
		return [r.length(), 0.0, 0.0]
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
	return [((p1 + d1 * s) - (p2 + d2 * t)).length(), s, t]


func _pen(ca: Dictionary, cb: Dictionary) -> float:
	var c := _seg_pts(ca["a"], ca["b"], cb["a"], cb["b"])
	var ra := lerpf(float(ca["ra"]), float(ca["rb"]), float(c[1]))
	var rb := lerpf(float(cb["ra"]), float(cb["rb"]), float(c[2]))
	return maxf(0.0, ra + rb - float(c[0]))


# Cheap bounding-sphere reject before the segment distance: most cross-hand
# pairs are a hundred millimetres apart.
func _near(ca: Dictionary, cb: Dictionary) -> bool:
	var ma: Vector3 = (ca["a"] + ca["b"]) * 0.5
	var mb: Vector3 = (cb["a"] + cb["b"]) * 0.5
	var ra: float = (ca["a"] as Vector3).distance_to(ca["b"]) * 0.5 \
		+ float(ca["r"])
	var rb: float = (cb["a"] as Vector3).distance_to(cb["b"]) * 0.5 \
		+ float(cb["r"])
	return ma.distance_to(mb) <= ra + rb + PEN_TOL


# Same hand: the pairs that must never cross. Returns [worst, tag].
func _same(caps: Dictionary) -> Array:
	var worst := 0.0
	var tag := ""
	for pair in APART:
		for ca in caps[pair[0]]:
			for cb in caps[pair[1]]:
				var p := _pen(ca, cb)
				if p > worst:
					worst = p
					tag = "%s/%s" % [ca["tag"], cb["tag"]]
	for pair in ADJACENT:
		for ca in caps[pair[0]]:
			if int(ca["seg"]) < 1:
				continue
			for cb in caps[pair[1]]:
				if int(cb["seg"]) < 1:
					continue
				var p := _pen(ca, cb)
				if p > worst:
					worst = p
					tag = "%s/%s" % [ca["tag"], cb["tag"]]
	for ray in HandModel.FINGERS:
		for ca in caps["I"]:
			for cb in caps[ray]:
				var p := _pen(ca, cb)
				if p > worst:
					worst = p
					tag = "I/%s" % cb["tag"]
	return [worst, tag]


# Left hand against right hand: every capsule, palms included.
func _cross(a: Dictionary, b: Dictionary) -> Array:
	var worst := 0.0
	var tag := ""
	var tags: Array = []
	tags.append_array(HandModel.FINGERS)
	tags.append("I")
	tags.append("MC")
	for ra in tags:
		for ca in a[ra]:
			for rb in tags:
				for cb in b[rb]:
					if not _near(ca, cb):
						continue
					var p := _pen(ca, cb)
					if p > worst:
						worst = p
						tag = "%s/%s" % [ca["tag"], cb["tag"]]
	return [worst, tag]


func _case(side: String, idx: int) -> Dictionary:
	var key: Dictionary = _keys[idx]
	var label := String(key["s"])
	var r: Rect2 = key["r"]
	var hx := r.get_center().x
	if r.size.x > Kbd3D.KEY_W * 1.05:
		hx = r.get_center().x + (-0.6 if side == "L" else 0.6) \
			* r.size.x * 0.5
	var hit := Vector2(hx, r.get_center().y)
	var ray := String(Kbd3D.hand_finger(label, hx)[1])
	var root_x: float = ROOTS[side]
	var home: Dictionary = HomePose.build(side, root_x)
	var deep := _local(side, root_x, Vector3(hit.x, hit.y,
		Kbd3D.FACE_Z - Kbd3D.TRAVEL))
	var other := "R" if side == "L" else "L"
	var idle: Dictionary = HomePose.build(other, float(ROOTS[other]))
	# The solver models one hand. This scene is the only place that has both,
	# so it is the one that tells the solver where the other one is — or the
	# thumbs collide mid-press and the solve cannot even see it.
	var hov := THUMB_HOVER if ray == "I" else KEY_HOVER
	var pr: Dictionary = IK.solve_chain(ray, deep, home,
		{"arm": true, "thumb_dof": 4, "clear_z": CLEAR_Z,
		"clear_w": CLEAR_W, "dir_w": DIR_W,
		"foreign": _foreign(idle, other, side, root_x),
		"hover_z": Kbd3D.FACE_Z + hov})
	var pp: Dictionary = pr["pose"]
	var ppad := _pad(ray, pp)
	var lift := maxf(0.0, (Kbd3D.FACE_Z + hov) - ppad.z)
	var hp: Dictionary = pp.duplicate(true)
	hp["arm"]["elbow_z"] = float(hp["arm"].get("elbow_z", 0.0)) + lift
	var rects := _local_keys(side, root_x)
	var path: Dictionary = ClickPath.build(home, hp, pp, APPROACH, PRESS,
		RELEASE, RETURN, {"ray": ray, "clear_z": CLEAR_Z,
		"key_rects": rects, "own": idx})
	var total := float(path["total"])
	var idle_caps := _caps(idle, other)
	var worst := 0.0
	var worst_tag := ""
	var worst_t := 0.0
	var worst_kind := ""
	var bad := 0
	var first := ""
	for i in STEPS + 1:
		var t := total * float(i) / float(STEPS)
		var p: Dictionary = ClickPath.at(path, t)
		var caps := _caps(p, side)
		var s := _same(caps)
		var c := _cross(caps, idle_caps)
		if float(s[0]) > worst:
			worst = float(s[0])
			worst_tag = String(s[1])
			worst_t = t
			worst_kind = "own"
		if float(c[0]) > worst:
			worst = float(c[0])
			worst_tag = String(c[1])
			worst_t = t
			worst_kind = "hands"
		var hit_now := maxf(float(s[0]), float(c[0])) > PEN_TOL
		if hit_now:
			bad += 1
			if first == "":
				first = "t %.3f %s %s" % [t, worst_kind, worst_tag]
	return {"side": side, "label": label, "ray": ray,
		"err": float(pr["error"]), "worst": worst, "tag": worst_tag,
		"t": worst_t, "kind": worst_kind, "bad": bad, "first": first,
		"samples": STEPS + 1}


func _init() -> void:
	_keys = Kbd3D.keys()
	var cases := []
	var args := OS.get_cmdline_user_args()
	if args.size() >= 2:
		for i in _keys.size():
			if String(_keys[i]["s"]) != str(args[1]):
				continue
			if int(Kbd3D.hand_finger(str(args[1]),
					Kbd3D.centre(_keys[i]).x)[0]) != (0 if str(args[0]) == "L" else 1):
				continue
			cases.append([str(args[0]), i])
			break
	else:
		for i in _keys.size():
			var s := String(_keys[i]["s"])
			if s == "Caps" or s == "Shift" or s == "Tab":
				continue
			var r: Rect2 = _keys[i]["r"]
			for side in ["L", "R"]:
				var hx := r.get_center().x
				if r.size.x > Kbd3D.KEY_W * 1.05:
					hx = r.get_center().x + (-0.6 if side == "L" else 0.6) \
						* r.size.x * 0.5
				var hf := Kbd3D.hand_finger(s, hx)
				if int(hf[0]) != (0 if side == "L" else 1):
					continue
				if String(hf[1]) == "":
					continue
				cases.append([side, i])
	var failed := 0
	var worst_line := ""
	var worst_pen := 0.0
	for c in cases:
		var res := _case(String(c[0]), int(c[1]))
		var line := "%s %-7s %s err %4.2f | worst %6.2f mm %s %s at t %.2f | bad %2d/%2d" % [
			String(res["side"]), String(res["label"]), String(res["ray"]),
			float(res["err"]), float(res["worst"]), String(res["kind"]),
			String(res["tag"]), float(res["t"]), int(res["bad"]),
			int(res["samples"])]
		if float(res["worst"]) > PEN_TOL:
			failed += 1
			line = "BAD " + line
			if String(res["first"]) != "":
				line += " | first " + String(res["first"])
		if float(res["worst"]) > worst_pen:
			worst_pen = float(res["worst"])
			worst_line = line
		print(line)
	print("SUMMARY %d/%d cases with a crossing (penetration > %.1f mm), worst %.2f"
		% [failed, cases.size(), PEN_TOL, worst_pen])
	if worst_pen > PEN_TOL:
		print("  worst: " + worst_line)
	quit(0 if failed == 0 else 1)
