# The pose path of one key click, shared by the viewer and the clearance probe
# so the two can never disagree.
#
# The click has four stages: rest → hover → press → hover → rest. The path is
# one C1 curve through those five keyframes, and every scalar of the pose (the
# four fingers' angles, the thumb's joints — its four angles, or the legacy
# single f — the eight arm joints) gets its own monotone cubic Hermite (PCHIP):
#
#   * the hover is an interior waypoint, so its slope is the harmonic mean of
#     the approach and press slopes — nonzero whenever the hand keeps moving
#     the same way. That is the author's "начало нажатия происходит уже в
#     конце наведения": the press begins before the hover is reached.
#   * the press bottom is a local extremum, so its slope is zero and the
#     release starts there without a pause — "конец нажатия сопровождается
#     началом отведения".
#   * both ends ease from and to rest.
#   * monotone means no overshoot: a joint never swings past a keyframe.
extends RefCounted

const ArmModel := preload("res://arm_model.gd")
const HandModel := preload("res://hand_model.gd")
const IK := preload("res://ik.gd")

# The keyboard the click is aimed at, for the target tip's own guard: the tip is
# exempt from the general clearance because it must press its own key, but on
# the way there it must not sweep through a NEIGHBOUR's keycap. The grid is the
# viewer's: 17 mm keys on a 20 mm pitch, ten columns from x = -90 and five rows
# from y = 80.
const KEY_PITCH := 20.0
const KEY_X0 := -90.0
const KEY_Y0 := 80.0
const KEY_HALF := 8.5

# The path guard measures the SKIN, not the bone: the blend bulges up to
# 1.9 mm past the joint capsule at a bent fingertip, and the interpolated
# approach (rest -> hover) dips an idle tip that far behind the key face even
# when both keyframes are clean. The solver itself still reasons about bones;
# only the guard and the tip guard carry the margin.
#
# 4.0 was tried for the four edge grazes that remain (II k40, V k19/k39/k49:
# the idle ring tip passes 0.2-2 mm into the last column's cap on the way to a
# far key). It does not help — a z-lift cannot clear a sphere that is inside
# through the SIDE, it only moves another slice of the fingertip into the slab
# — and it invents a corner violation at the ring PIP (7.5 mm outside the
# footprint, 8.6 mm above the plane) that shortens the press by 1.1 mm. The
# residual stays a hidden pass-through behind the cap's front face; a real fix
# is the palm-placement pass the author deferred.
const SKIN_MARGIN := 2.0


# times: [0, approach, approach+press, +release, +return].
#
# The path starts at `rest` and, unless told otherwise, ends at the same pose.
# `opts["return"]` is a DIFFERENT end keyframe: the hand's canonical rest. A
# click that begins while the hand is still flying from the previous one must
# not take that mid-flight pose as its destination — it started from it, but
# it has to finish at rest (author, #11 follow-up: "правая рука опять
# изменила состояние покоя после нажатия правой нижней кнопки"; measured: a
# second click 12 frames into the first left the hand parked 24.5° away from
# home, and it stayed there).
#
# clear_z / ray are optional: when the path is given a keyboard plane, every
# sampled pose is lifted along +z by however much its idle geometry would cross
# that plane. Interpolating joint angles is not a clearance-safe operation — a
# curled finger can straighten through a lower pose between two clean keyframes
# (the ring finger dives 10 mm behind the face on the way to the little
# finger's far key) — so the lift is the guard, and it is exactly the worst
# violation, which means it is zero at both clean ends and never more than
# needed in between.
static func build(rest: Dictionary, hover: Dictionary, press: Dictionary,
		a: float, p: float, r: float, q: float, opts: Dictionary = {}) -> Dictionary:
	var back: Dictionary = opts.get("return", rest)
	var keys := [rest, hover, press, hover, back]
	var t1 := a
	var t2 := a + p
	var t3 := t2 + r
	var t4 := t3 + q
	return {"keys": keys, "times": [0.0, t1, t2, t3, t4], "total": t4,
		"ray": str(opts.get("ray", "")),
		"clear_z": float(opts.get("clear_z", -1e9)),
		"clear_rect": opts.get("clear_rect", Rect2()),
		"key": int(opts.get("key", -1)),
		# The real keyboard, when the caller has one: a list of key rectangles
		# in the solver's own space and the index of the key being pressed.
		# The old uniform grid (`key`) stays for the single-hand study. The
		# name is not "keys": that one is already the pose keyframes above.
		"key_rects": opts.get("key_rects", []),
		"own": int(opts.get("own", -1))}


static func at(path: Dictionary, t: float) -> Dictionary:
	var keys: Array = path["keys"]
	var times: Array = path["times"]
	var out: Dictionary = keys[0].duplicate(true)
	for ray in out["fingers"]:
		for j in ["mcp", "pip", "dip", "fan"]:
			var ys := []
			for p in keys:
				ys.append(float(p["fingers"][ray][j]))
			out["fingers"][ray][j] = _scalar(ys, times, t)
	var tf := []
	for p in keys:
		tf.append(float(p.get("thumb_f", 0.0)))
	out["thumb_f"] = _scalar(tf, times, t)
	# The thumb has either the legacy single coordinate f or its four joints.
	# A path is built from keyframes of one kind, so the kind is read from the
	# keys once and the same interpolation is applied to every joint scalar.
	var four := false
	for p in keys:
		if int(p.get("thumb_dof", 0)) == 4:
			four = true
			break
	if four:
		var th := {}
		for j in HandModel.THUMB_JOINTS:
			var yt := []
			for p in keys:
				yt.append(float(HandModel.thumb_of_pose(p).get(j,
					HandModel.THUMB_REST[j])))
			th[j] = _scalar(yt, times, t)
		out["thumb"] = th
		out["thumb_dof"] = 4
		out["thumb_f"] = 0.0
	else:
		out.erase("thumb_dof")
	for j in ArmModel.ALL_JOINTS:
		var ya := []
		for p in keys:
			ya.append(float(p["arm"].get(j, 0.0)))
		out["arm"][j] = _scalar(ya, times, t)
	var ray := str(path.get("ray", ""))
	var cz := float(path.get("clear_z", -1e9))
	if ray != "" and cz > -1e8:
		var lift := IK.clearance(ray, out, cz,
			path.get("clear_rect", Rect2()), SKIN_MARGIN)
		var krects: Array = path.get("key_rects", [])
		if not krects.is_empty():
			lift = maxf(lift, _tip_lift_keys(ray, out, cz, krects,
				int(path.get("own", -1))))
		else:
			var key := int(path.get("key", -1))
			if key >= 0:
				lift = maxf(lift, _tip_lift(ray, out, cz, key))
		if lift > 0.0:
			out["arm"]["elbow_z"] = float(out["arm"].get("elbow_z", 0.0)) + lift
	return out


# How far the target fingertip's own sphere is inside a keycap OTHER than its
# own, against the same margin zc the rest of the hand uses. The general
# clearance exempts the tip (it is the one part allowed to touch a key), so
# without this the fingertip could sweep through the row behind on its way to
# the target — measured on IV k6: the tip crossed k25 0.8 mm below the face on
# the approach, and the general guard could not lift it because the tip is
# exempt. The own key is skipped: the pad IS the bottom of this sphere, so the
# tip can only reach below the face once the key is already sinking with it.
static func _tip_lift(ray: String, p: Dictionary, zc: float, key: int) -> float:
	var xf := ArmModel.hand_transform(p.get("arm", {}))
	var tip: Vector3
	var r: float
	if ray == "I":
		var tpts: PackedVector3Array = HandModel.thumb_fk(
			HandModel.thumb_of_pose(p))["pts"]
		tip = xf * tpts[3]
		r = HandModel.THUMB_TIP_R
	else:
		var pts: PackedVector3Array = HandModel.finger_fk(ray,
			p["fingers"][ray])["pts"]
		tip = xf * pts[3]
		r = float(HandModel.SKIN_R[ray][3])
	var worst := 0.0
	for k in 50:
		if k == key:
			continue
		var cx := KEY_X0 + float(k % 10) * KEY_PITCH
		var cy := KEY_Y0 + float(k / 10) * KEY_PITCH
		worst = maxf(worst, _key_violation(tip, r, cx, cy, zc))
	return worst


# The target tip's guard against a real keyboard: the same sphere-versus-prism
# measure, one key at a time, skipping the key being pressed. The tip is exempt
# from the general clearance (it must reach its own key), so this is the only
# thing that keeps it out of a neighbour's cap on the way.
static func _tip_lift_keys(ray: String, p: Dictionary, zc: float,
		keys: Array, own: int) -> float:
	var xf := ArmModel.hand_transform(p.get("arm", {}))
	var tip: Vector3
	var r: float
	if ray == "I":
		var tpts: PackedVector3Array = HandModel.thumb_fk(
			HandModel.thumb_of_pose(p))["pts"]
		tip = xf * tpts[3]
		r = HandModel.THUMB_TIP_R
	else:
		var pts: PackedVector3Array = HandModel.finger_fk(ray,
			p["fingers"][ray])["pts"]
		tip = xf * pts[3]
		r = float(HandModel.SKIN_R[ray][3])
	var worst := 0.0
	for k in keys.size():
		if k == own:
			continue
		worst = maxf(worst, _key_violation_rect(tip, r, keys[k], zc))
	return worst


# The prism SDF of one keycap (its footprint and the plane z = zc), the same
# measure ik.gd applies to the whole keyboard.
static func _key_violation(p: Vector3, r: float, cx: float, cy: float,
		zc: float) -> float:
	return _key_violation_rect(p, r, Rect2(cx - KEY_HALF, cy - KEY_HALF,
		KEY_HALF * 2.0, KEY_HALF * 2.0), zc)


static func _key_violation_rect(p: Vector3, r: float, rect: Rect2,
		zc: float) -> float:
	var c := rect.get_center()
	var qx := absf(p.x - c.x) - rect.size.x * 0.5
	var qy := absf(p.y - c.y) - rect.size.y * 0.5
	var qz := p.z - zc
	var ox := maxf(qx, 0.0)
	var oy := maxf(qy, 0.0)
	var oz := maxf(qz, 0.0)
	var sdf := sqrt(ox * ox + oy * oy + oz * oz) \
		+ minf(maxf(qx, maxf(qy, qz)), 0.0)
	return maxf(0.0, r - sdf)


static func _scalar(ys: Array, ts: Array, t: float) -> float:
	var n := ys.size()
	if t <= float(ts[0]):
		return float(ys[0])
	if t >= float(ts[n - 1]):
		return float(ys[n - 1])
	var i := 0
	while i < n - 2 and t > float(ts[i + 1]):
		i += 1
	var h := float(ts[i + 1]) - float(ts[i])
	if h <= 0.000001:
		return float(ys[i + 1])
	var s := (t - float(ts[i])) / h
	var d0 := _slope(ys, ts, i)
	var d1 := _slope(ys, ts, i + 1)
	var s2 := s * s
	var s3 := s2 * s
	return (2.0 * s3 - 3.0 * s2 + 1.0) * float(ys[i]) \
		+ (s3 - 2.0 * s2 + s) * h * d0 \
		+ (-2.0 * s3 + 3.0 * s2) * float(ys[i + 1]) \
		+ (s3 - s2) * h * d1


static func _slope(ys: Array, ts: Array, i: int) -> float:
	var n := ys.size()
	if i == 0 or i == n - 1:
		return 0.0
	var h0 := float(ts[i]) - float(ts[i - 1])
	var h1 := float(ts[i + 1]) - float(ts[i])
	if h0 <= 0.000001 or h1 <= 0.000001:
		return 0.0
	var d0 := (float(ys[i]) - float(ys[i - 1])) / h0
	var d1 := (float(ys[i + 1]) - float(ys[i])) / h1
	if d0 * d1 <= 0.0:
		return 0.0
	var w0 := 2.0 * h1 + h0
	var w1 := h1 + 2.0 * h0
	return (w0 + w1) / (w0 / d0 + w1 / d1)
