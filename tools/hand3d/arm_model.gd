# The arm the hand hangs from, for the hand study.
#
# The author (28.10.2026): "Руку делать достаточно до локтя. Плечё не нужно."
# The model is therefore cut at the elbow: a forearm from the elbow stump to
# the wrist, and the hand on top. There is no upper arm, no shoulder ball and
# no moving elbow. The elbow is the FIXED ROOT of the chain; the forearm turns
# about it, pronates, and the wrist bends. This is the honest kinematic cut:
# in a real arm the forearm's direction is the combined work of the shoulder
# and elbow, so cutting the upper arm away leaves a two-axis ball at the cut.
#
# REST = THE STRAIGHT FOREARM. Every angle is zero, the hand transform is the
# identity, and the approved hand geometry does not move by a micron. That is
# the same rule the fingers follow: the rest pose is the zero of the energy.
#
# LENGTHS. The hand is the measured part (189 mm, baseline v1). The forearm
# of an adult is about 255 mm, but the study shows only the distal 150 mm —
# the author asked for "part of the forearm", not a whole arm.
#
# RANGES. Wrist, forearm and elbow are clinical values (eatonhand.com/nor/
# nor002.htm): wrist extension/flexion 70/75°, radial/ulnar 20/35°, forearm
# pronation/supination 70/85°. The root's two angles are not an anatomical
# joint: they are the direction of the forearm in space, limited to the
# forward hemisphere the study uses (the hand would otherwise turn its back
# to the viewer). The MCP abduction ranges live in hand_model.gd (25–30° in
# total, abduction dominating, per physical-therapy.us/metacarpophalangeal-
# mcp-joints and the goniometry literature).
#
# HIERARCHY. The prior weights below are what makes the chain hierarchical:
# the solver always prefers the cheapest joint that can do the job. The fan
# is the cheapest of all (one finger, intrinsic muscles), then the finger
# flexors, the wrist (the whole hand), pronation (the hand's roll), and the
# forearm root (the hand + forearm) is the last resort. The weights are in
# mm² per share², the same units as ik.gd's W_PRIOR, and are tuned against
# the tests in ik_test.gd. They are effective inertias, not joint ranges:
# the author's point is that a small sideways reach is cheap with one finger
# and expensive with the whole arm, even though the whole arm has the longer
# lever.
extends RefCounted

const FOREARM_L := 150.0       # visible distal part of the forearm
const ELBOW := Vector3(0, -FOREARM_L, 0)  # rest position of the elbow
const WRIST := Vector3.ZERO    # hand-local origin, the cut at the wrist

# The share of the wrist angle carried by the skin AT the cut. The hand's wall
# above the cut and the forearm's sweep below it both start from this blended
# frame, so a bend is split between them instead of the hand's wall staying
# rigid while the whole forearm bends. Half is the crease's own place: the cut
# lies in the middle of the bend. At rest the blend is the identity.
#
# 0.65 was tried and kept the seam numbers, but at 70° the palmar wall still
# folded into a wedge (frames W4). At 0.50 the same bend reads as a crease
# (frames B50) and nothing measured got worse: tangent kink 5.16° palmar /
# 5.14° dorsal, silhouette kink 11.45° against 12.40°, seam gap 0.0059 mm.
# BEND_L stays 35 mm: the "rubber" forearm of the earlier 0.5 trial came from
# bending it over 55 mm, not from the half split itself.
const WRIST_BLEND := 0.50

# Distal to proximal. The solver takes its variables in this order, and the
# viewer's HUD walks the same list.
#
# The root has TWO angles, not three: the forearm's direction in space. The
# roll around the forearm is pronation, one level down, exactly as a real
# forearm twists distal to the elbow. A third root axis would duplicate it.
const JOINTS := ["wrist_flex", "wrist_dev", "pronation",
	"forearm_flex", "forearm_abd"]

# The elbow's travel (author, 29.10.2026: a fingertip must reach ANY point,
# and when the rotations run out the elbow itself moves). Three translations
# in millimetres, the last and most expensive level of the chain. They move
# the hand AND the whole forearm rigidly, so they are the last resort — the
# small joints answer first and the elbow only closes what they cannot.
const ROOT_JOINTS := ["elbow_x", "elbow_y", "elbow_z"]
const ELBOW_RANGE := 220.0     # mm at share 1, per axis
const ALL_JOINTS := ["wrist_flex", "wrist_dev", "pronation",
	"forearm_flex", "forearm_abd", "elbow_x", "elbow_y", "elbow_z"]

const ROM := {
	"wrist_flex": [-70.0, 75.0],    # + flexion (palm toward forearm), - extension
	"wrist_dev": [-35.0, 20.0],     # + radial (toward the thumb), - ulnar
	"pronation": [-85.0, 70.0],     # + pronation, - supination
	# The forearm direction: flex is the elevation from the XY plane (+Z is
	# dorsal, -Z palmar), abd is the azimuth around Y (+X is the thumb side).
	# The rest is straight up. The limits keep the hand's back toward the
	# viewer and avoid the pole where the azimuth loses its meaning.
	"forearm_flex": [-80.0, 80.0],
	"forearm_abd": [-120.0, 120.0],
}

# Prior weights: fan (in ik.gd) < finger flexors < wrist < pronation < root
# < elbow travel. The root moves the hand AND the forearm, so it is the most
# expensive rotation group; its long lever still lets it answer a far target
# when the wrist cannot. The elbow is a translation: per millimetre it costs
# sqrt(16000)/220 = 0.57 in the residual, against the wrist's 0.016 — thirty-five
# times dearer, so it only moves when the joints above are at their stops.
const WEIGHT := {
	"wrist_flex": 1.5,
	"wrist_dev": 1.5,
	"pronation": 4.0,
	"forearm_flex": 30.0,
	"forearm_abd": 30.0,
	"elbow_x": 16000.0,
	"elbow_y": 16000.0,
	"elbow_z": 16000.0,
}


# THE WRIST'S SIDEWAYS BEND IS NOT FREE FOREVER (author, #11, 04.11.2026:
# "при нажатии крайне левых и крайне правых нижних кнопок руке легче было бы
# не поворачивать лучезапястный сустав в бок, а перемещать всю кисть и
# предплечье. Сделай нечто среднее").
#
# Up to DEV_FREE degrees of EXTRA ulnar bend (towards the little finger) from
# the pose the hand is ALREADY in, the wrist is as cheap as it ever was — the
# approved SS50h posture itself (wrist_dev −10) pays nothing, so the dead zone
# is measured from the base, not from the model's zero. Beyond it every degree
# costs DEV_SOFT of residual, far more than a degree of the forearm's swing
# (sqrt(30)/120 = 0.046), so the rest of a far key's sideways reach goes to
# the forearm. "Something in between": the wrist takes the near part of the
# reach, the arm takes the far part.
#
# WHY IT IS THE CALLER'S SWITCH. The energy is a global landscape with
# several near-degenerate valleys, and any new term — even one that is zero
# at the approved pose — re-picks those valleys: measured on the digit row,
# a stop that paid 1.5/deg turned «1» from +20° radial to −8.4° and «0» from
# +2.6° to +20°, and the ring finger started crossing the middle on «2».
# The author's note is about the BOTTOM row only ("в остальном вроде бы
# хорошо"), so the stop is switched on for the bottom-row strokes alone and
# every other key keeps the approved SS50h answer bit for bit. On that row
# it does exactly the asked-for split: глобус −17.2° → −13.2°, right Ctrl
# −15.6° → −12.9°, left Ctrl (already inside the dead zone) untouched.
static var DEV_FREE := 3.0
static var DEV_SOFT := 1.5

# The caller's switch for the stop above. It is OFF by default, so every
# solve that does not ask for it (the study's own tests, the click path,
# any target the author approved) keeps the exact hierarchy it had. The
# simulator turns it on for the bottom-row strokes only.
static var DEV_STOP := false

# THE BOTTOM ROW'S OWN PRICE LIST (author, #11 follow-up, 04.11.2026: "Обе
# руки по-прежнему вообще не двигаются в сторону крайних точек, а сильно
# сгибает лучезапястный сустав, что должно быть труднее, чем движение
# предплечья").
#
# The approved hierarchy makes the elbow travel thirty-five times dearer per
# millimetre than a wrist bend, and the finger prior ten times cheaper per
# degree than either. On the far bottom keys that adds up to a hand that
# stays put while the pinky curls: measured on the gated build, the wrist
# translated 1.4 mm on left Ctrl while the little finger went to 0.72 share.
# The author's rule is the other way round — moving the hand and forearm is
# the EASY answer, bending the wrist is the dear one — so the bottom-row
# strokes get a price list of their own: the elbow (which moves the whole
# arm rigidly, i.e. exactly "кисть и предплечье") is cheap, the forearm's
# swing is cheap, and the finger is no longer nearly free.
#
# It is a per-solve override, empty by default, so every other key keeps the
# approved SS50h answer bit for bit (the solver is branch-chaotic: a weight
# change re-picks valleys board-wide, measured on the digit row).
static var WEIGHT_OVERRIDE := {}


static func weight_of(j: String) -> float:
	if WEIGHT_OVERRIDE.has(j):
		return float(WEIGHT_OVERRIDE[j])
	return float(WEIGHT[j])


# A share is a fraction of the joint's OWN range, and the wrist's two sides
# have different ranges (ulnar 35°, radial 20°), so a share difference is not
# a degree. The soft stop is written in degrees and converted here.
static func dev_degrees(d_share: float) -> float:
	var lo := -float(ROM["wrist_dev"][0])
	var hi := float(ROM["wrist_dev"][1])
	return d_share * (lo if d_share < 0.0 else hi)


static func dev_soft_cost(d: float) -> float:
	if not DEV_STOP or DEV_SOFT <= 0.0:
		return 0.0
	return DEV_SOFT * maxf(0.0, absf(dev_degrees(d)) - DEV_FREE)


static func rest_arm() -> Dictionary:
	var a := {}
	for j in ALL_JOINTS:
		a[j] = 0.0
	return a


static func _angles(arm: Dictionary) -> Dictionary:
	var a := rest_arm()
	if arm != null:
		for j in ALL_JOINTS:
			if arm.has(j):
				a[j] = float(arm[j])
	return a


# The same share measure as ik.gd: 0 at rest, +1 at the high stop, -1 at the
# low stop. Kept here so the arm can be solved without loading the hand solver.
static func share(q: float, rest: float, lo: float, hi: float) -> float:
	if q >= rest:
		return (q - rest) / maxf(hi - rest, 0.001)
	return (q - rest) / maxf(rest - lo, 0.001)


static func angle_of(s: float, rest: float, lo: float, hi: float) -> float:
	if s >= 0.0:
		return rest + s * (hi - rest)
	return rest + s * (rest - lo)


static func shares_of(arm: Dictionary) -> Array:
	var a := _angles(arm)
	var out := []
	for j in JOINTS:
		out.append(share(float(a[j]), 0.0, float(ROM[j][0]), float(ROM[j][1])))
	for j in ROOT_JOINTS:
		out.append(float(a[j]) / ELBOW_RANGE)
	return out


static func angles_of_shares(q: Array) -> Dictionary:
	var out := {}
	for i in JOINTS.size():
		var j: String = JOINTS[i]
		out[j] = angle_of(clampf(float(q[i]), -1.0, 1.0), 0.0,
			float(ROM[j][0]), float(ROM[j][1]))
	for i in ROOT_JOINTS.size():
		out[ROOT_JOINTS[i]] = clampf(float(q[JOINTS.size() + i]), -1.0, 1.0) \
			* ELBOW_RANGE
	return out


static func clamp_arm(arm: Dictionary) -> Dictionary:
	var a := _angles(arm)
	for j in JOINTS:
		a[j] = clampf(float(a[j]), float(ROM[j][0]), float(ROM[j][1]))
	for j in ROOT_JOINTS:
		a[j] = clampf(float(a[j]), -ELBOW_RANGE, ELBOW_RANGE)
	return a


# Where the elbow sits: its rest point plus the three translations.
static func elbow_of(arm: Dictionary) -> Vector3:
	var a := _angles(arm)
	return ELBOW + Vector3(float(a["elbow_x"]), float(a["elbow_y"]),
		float(a["elbow_z"]))


# The frames of the arm at one state. Everything is in hand-local space at
# rest, so hand_transform(rest_arm()) is the identity.
#
#   R_root  the forearm's direction: shortest arc from UP to dir, no twist
#   R_fore  pronation around the forearm's own Y
#   R_wrist wrist deviation then flexion, in the forearm's frame
#
# The shortest arc is a choice: it leaves the forearm's roll at zero, so the
# palm keeps facing palmar until pronation says otherwise. Euler angles would
# introduce a made-up roll and a gimbal lock at the pole.
static func frames(arm: Dictionary) -> Dictionary:
	var a := _angles(arm)
	var flex := deg_to_rad(float(a["forearm_flex"]))
	var abd := deg_to_rad(float(a["forearm_abd"]))
	var dir := Vector3(sin(abd) * cos(flex), cos(abd) * cos(flex), sin(flex))
	var r_root := _rot_up_to(dir)
	var r_fore := r_root * Basis(Vector3.UP, deg_to_rad(float(a["pronation"])))
	var r_wrist := r_fore * Basis(Vector3.BACK, deg_to_rad(-float(a["wrist_dev"]))) \
		* Basis(Vector3.RIGHT, deg_to_rad(-float(a["wrist_flex"])))
	var elbow := elbow_of(a)
	var wrist := elbow + r_root * Vector3(0, FOREARM_L, 0)
	return {"elbow": elbow, "wrist": wrist, "r_root": r_root, "r_fore": r_fore,
		"r_wrist": r_wrist, "angles": a}


# The rotation that carries UP to `dir` by the shortest arc. At the rest
# direction it is exactly the identity, so the approved pose is untouched.
static func _rot_up_to(dir: Vector3) -> Basis:
	var d := dir.normalized()
	var c := clampf(Vector3.UP.dot(d), -1.0, 1.0)
	if c > 0.999999:
		return Basis.IDENTITY
	var axis := Vector3.UP.cross(d)
	if axis.length_squared() < 0.000000001:
		# Straight down: no shortest arc exists. The ROM keeps the forearm
		# out of this pole; a caller that asks anyway gets a half-turn.
		return Basis(Vector3.RIGHT, PI)
	return Basis(axis.normalized(), acos(c))


static func hand_transform(arm: Dictionary) -> Transform3D:
	var f := frames(arm)
	return Transform3D(f["r_wrist"], f["wrist"])


# The rigid transform of the forearm segment: rest points (hand-local space)
# to posed space. At rest it is the identity. Used by the arm skin and bones.
static func forearm_transform(arm: Dictionary) -> Transform3D:
	var f := frames(arm)
	return Transform3D(f["r_fore"], f["elbow"]) * Transform3D(Basis.IDENTITY, -ELBOW)


# The frame of the skin at the wrist cut: the wrist joint's own point, with a
# rotation between the forearm's and the hand's (`t` = 0 forearm, 1 hand).
# This is not a bone of the anatomy — it is the seam's frame. The hand's cut
# rim and the arm's first loft ring are both carried by it, so they stay one
# edge under any bend, and the band above the rim fades from it to the palm.
# At rest it is exactly the identity, so the approved geometry does not move.
static func wrist_blend(arm: Dictionary, t: float) -> Transform3D:
	var f := frames(arm)
	var q0: Quaternion = (f["r_fore"] as Basis).get_rotation_quaternion()
	var q1: Quaternion = (f["r_wrist"] as Basis).get_rotation_quaternion()
	return Transform3D(Basis(q0.slerp(q1, clampf(t, 0.0, 1.0))), f["wrist"])


# A starting pose for the arm that puts the WRIST at a given point. The wrist
# is rigidly FOREARM_L away from the elbow, so the elbow must lie on the
# sphere of that radius around the wrist. With the elbow free the seed picks
# the point on that sphere nearest the rest elbow — the least travel — and
# points the forearm at the wrist. A wrist within the rest reach keeps the
# elbow exactly at rest, which is the old seed and the pose the author
# approved.
static func seed_for(wrist_target: Vector3) -> Dictionary:
	var arm := rest_arm()
	var d := wrist_target - ELBOW
	var dist := d.length()
	var elbow := ELBOW
	if dist > FOREARM_L:
		elbow = wrist_target - d / dist * FOREARM_L
		elbow.x = clampf(elbow.x - ELBOW.x, -ELBOW_RANGE, ELBOW_RANGE) + ELBOW.x
		elbow.y = clampf(elbow.y - ELBOW.y, -ELBOW_RANGE, ELBOW_RANGE) + ELBOW.y
		elbow.z = clampf(elbow.z - ELBOW.z, -ELBOW_RANGE, ELBOW_RANGE) + ELBOW.z
	var u := wrist_target - elbow
	if u.length_squared() < 0.000001:
		u = Vector3.UP
	u = u.normalized()
	arm["forearm_abd"] = rad_to_deg(atan2(u.x, u.y))
	arm["forearm_flex"] = rad_to_deg(asin(clampf(u.z, -1.0, 1.0)))
	arm["elbow_x"] = elbow.x - ELBOW.x
	arm["elbow_y"] = elbow.y - ELBOW.y
	arm["elbow_z"] = elbow.z - ELBOW.z
	return arm


# A full arm seed for a TARGET of the pad, not of the wrist.
#
# The pad hangs `pad_local` away from the wrist, so a wrist at
# `target - from * pad_len` puts the pad on the target with the hand in its
# rest orientation. The elbow is then placed by seed_for: at rest when the
# wrist is within the forearm's reach, carried along the shortest path when
# it is not.
#
# The hand is then turned by the shortest rotation that aims the pad at the
# target, and the three wrist angles are read back from that rotation in the
# order the wrist chain uses (deviation, flexion, pronation).
static func seed_hand(pad_local: Vector3, target: Vector3) -> Dictionary:
	var pad_len := pad_local.length()
	var from := pad_local / maxf(pad_len, 0.001)
	var wrist := target - from * pad_len
	var arm := seed_for(wrist)
	var f := frames(arm)
	var r_root: Basis = f["r_root"]
	var w: Vector3 = f["wrist"]
	var aim := target - w
	if aim.length_squared() < 0.000000001:
		return arm
	var to := (r_root.inverse() * aim).normalized()
	var axis := from.cross(to)
	var r := Basis.IDENTITY
	if axis.length_squared() > 0.000000001:
		r = Basis(axis.normalized(), acos(clampf(from.dot(to), -1.0, 1.0)))
	# r_wrist = r_root * Basis(UP, pron) * Basis(BACK, -dev) * Basis(RIGHT, -flex)
	# so the matrix below is exactly the wrist part of the chain. Godot stores
	# basis vectors as columns, hence the transposed-looking indices.
	var dev := -asin(clampf(r.x.y, -1.0, 1.0))
	var flex := atan2(r.z.y, r.y.y)
	var pron := atan2(-r.x.z, r.x.x)
	arm["pronation"] = rad_to_deg(pron)
	arm["wrist_dev"] = rad_to_deg(dev)
	arm["wrist_flex"] = rad_to_deg(flex)
	return arm


# The nearest and farthest the wrist can sit from the elbow. The wrist is
# rigidly on the forearm, so both are the same sphere; the names stay because
# the tests and the viewer ask for the reach.
static func reach_max() -> float:
	return FOREARM_L


static func reach_min() -> float:
	return FOREARM_L


# The share spent by each level, in percent. The viewer shows these to make
# the hierarchy visible: the finger is busy first, the elbow last.
static func levels(arm: Dictionary) -> Dictionary:
	var s := shares_of(arm)
	return {
		"wrist": maxf(absf(float(s[0])), absf(float(s[1]))) * 100.0,
		"pronation": absf(float(s[2])) * 100.0,
		"forearm": maxf(absf(float(s[3])), absf(float(s[4]))) * 100.0,
		"elbow": maxf(absf(float(s[5])), maxf(absf(float(s[6])),
			absf(float(s[7])))) * 100.0,
	}


static func effort(arm: Dictionary) -> Dictionary:
	var s := shares_of(arm)
	var out := {}
	for i in ALL_JOINTS.size():
		out[ALL_JOINTS[i]] = absf(float(s[i])) * 100.0
	return out
