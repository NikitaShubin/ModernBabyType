# Hand skeleton + skin field, all numbers in millimetres.
#
# Bone lengths are adult male values for a hand of 189 mm (wrist crease to
# middle fingertip). The guiding rule from the reference sheet is
# P ≈ M + D for every finger; per-ray ratios P : M : D ≈ 1 : 0.60 : 0.45.
extends RefCounted

const Sdf := preload("res://sdf.gd")
const ArmModel := preload("res://arm_model.gd")

const FINGERS := ["II", "III", "IV", "V"]

# Metacarpals: II is the longest, then III, IV, V. The thumb's is short.
const MC_LEN := {"I": 46.0, "II": 67.0, "III": 65.0, "IV": 62.0, "V": 56.0}

# Phalanges: proximal, middle, distal (the thumb has no middle one).
# The sheet the author pointed at says the proximal phalanx equals the
# middle plus the distal one; the measured series is ~5 % short of that
# (P/(M+D) = 0.95), so the phalanx sum is split as P = S/2 and the rest
# in the measured proportion M : D = 4 : 3. Totals stay as measured.
const PH_LEN := {
	"I": [34.0, 25.0],
	"II": [44.0, 25.0, 19.0],
	"III": [48.0, 27.0, 21.0],
	"IV": [47.0, 27.0, 20.0],
	"V": [37.0, 21.0, 16.0],
}

const MC_BASE := {
	"I": Vector3(22, 26, -4),
	"II": Vector3(19, 28, 4),
	"III": Vector3(4, 27, 5),
	"IV": Vector3(-10, 27, 3),
	"V": Vector3(-24, 26, 0),
}
const MC_AIM := {
	"I": Vector3(47, 65, -13),
	"II": Vector3(28.0, 92.0, 4.5),
	"III": Vector3(6.5, 92.0, 6),
	"IV": Vector3(-14, 88.5, 2.5),
	"V": Vector3(-33.5, 81.5, -1),
}

# ---- the rest state ---------------------------------------------------
# The hand at rest is THE minimum-energy state of the model: the posture the
# passive hand falls into when nothing pulls on it. Every energy (an IK step,
# a passive stiffness model) therefore measures its deviation from these
# angles, and this pose is its zero. Numbers below are that state, not a
# random pose: the fingers fan a little and curl naturally, the little one
# curls most, the middle fingertip ends ~45 mm palmar of the palm plane.
const FAN := {"II": 1.2, "III": 0.2, "IV": -1.0, "V": -2.2}
# Flexion at MCP, PIP, DIP, in degrees, at the rest state.
const FLEX := {"II": [20.0, 34.0, 14.0], "III": [19.0, 33.0, 14.0],
	"IV": [22.0, 36.0, 15.0], "V": [26.0, 40.0, 17.0]}

# How far a joint travels, in degrees, in the model's own angle convention
# (flexion toward the palm is positive). The IK solver takes its limits from
# here, so a target outside the range stalls at the stop and reports the
# residual instead of driving the bone through itself. The fan is absolute
# (it is the MCP abduction angle the chain is built with); a few degrees of
# hyperextension are allowed because a relaxed hand uses them.
#
# THE FAN IS THE MCP'S SIDE-TO-SIDE DEGREE OF FREEDOM, and it is deliberately
# wide at the index and the little finger: those are the two the author says
# do the reaching for far keys. The clinical MCP abduction/adduction range is
# 25–30° in total, with abduction dominating (physical-therapy.us/metacarpo-
# phalangeal-mcp-joints; goniometry texts agree). The ranges below give II–V
# 32°, 25°, 28° and 38° of fan; the extra travel sits on the two outer rays
# (II toward +X, V toward −X) — the asymmetry the anatomy reports — while III
# and IV stay inside the clinical band. The index's −14 is what lets it
# adduct under the SS50h hand yaw of 24° (the hand turns, the four home keys
# do not). The rest angles FAN are unchanged, so the approved pose is still
# the same pose; only the space the joints may travel has grown.
const ROM := {
	"II": {"mcp": [-10.0, 90.0], "pip": [-5.0, 110.0], "dip": [-5.0, 70.0],
		"fan": [-14.0, 18.0]},
	"III": {"mcp": [-10.0, 90.0], "pip": [-5.0, 110.0], "dip": [-5.0, 70.0],
		"fan": [-8.0, 17.0]},
	"IV": {"mcp": [-10.0, 90.0], "pip": [-5.0, 110.0], "dip": [-5.0, 70.0],
		"fan": [-12.0, 16.0]},
	"V": {"mcp": [-10.0, 90.0], "pip": [-5.0, 110.0], "dip": [-5.0, 70.0],
		"fan": [-22.0, 16.0]},
}
# ---- the thumb: THREE mobile joints -------------------------------
# The thumb column is not one hinge with a tip. All three of its joints move
# (the author, 27.10.2026), and the whole chain is modelled the way the
# anatomy describes it (Kapandji, "The Physiology of the Joints", vol. 1):
#
#   CMC  trapezio-metacarpal, a saddle: two degrees of freedom —
#        · palmar/dorsal swing: flexion 0–15°, extension 0–20°;
#        · swing in the plane of the palm (abduction 0–70° from full
#          adduction) which opens the first web space.
#   MCP  condylar: flexion 0–50/60°, extension 0–10/20°.
#   IP   hinge: flexion 0–80/90°.
#
# The first metacarpal therefore MOVES at the CMC; it is placed at its rest
# aim by _build_metacarpals and rebuilt here around the trapezium. Angles are
# in degrees and are read as a deviation from the rest pose below — that pose
# is the zero, so REST is not "no joints bent", it is the hand's own posture.
#
# THE CMC ALSO TURNS THE COLUMN (opposition), and that turn is a joint of its
# own. The saddle's two swings aim the metacarpal; they do not decide which way
# the distal phalanges FOLD, because the MCP and the IP are hinges whose axis
# rides on the column. Without the turn the fold plane is fixed by the palm
# vector, and the thumb can only reach a space bar that lies under the palm by
# overshooting inboard at the metacarpal and folding back outboard at the IP —
# the hook that made the two thumbs cross (01.11.2026: the target sat at the
# EDGE of the four-joint reachable set, one pose in 158 760 within 1 mm).
# The game's hand (game/scripts/hands.gd, fk_chain) has carried this joint
# since 26.10.2026 for exactly this reason: "без поворота хорда четверти
# пробела недостижима, кончик тонул под доску". The study now has it too:
# twist = 0 is the approved rest pose, unchanged.
const THUMB_REST := {"cmc_flex": 0.0, "cmc_abd": 0.0, "twist": 0.0,
	"mcp": 16.0, "ip": 34.0}

# The thumb's own joints and their travel, in the same convention as ROM: an
# absolute angle range, with the rest pose somewhere inside it. The thumb is
# solved by the same energy rule as the four fingers — one share per joint,
# zero at rest, ±1 at the stops — but its joints are not interchangeable:
# the saddle has two axes (palmar swing and abduction), the MCP and the IP are
# hinges. Keeping them as four independent coordinates is what lets the
# column reach a key by opening or closing, instead of walking one arc that
# cannot answer a second target (the author's rule, 31.10.2026: dynamics from
# common rules and individual joint limits, not per-finger exceptions).
const THUMB_JOINTS := ["cmc_flex", "cmc_abd", "twist", "mcp", "ip"]
const THUMB_ROM := {
	"cmc_flex": [-10.0, 25.0],
	"cmc_abd": [-25.0, 30.0],
	"twist": [-30.0, 95.0],
	"mcp": [-4.0, 60.0],
	"ip": [-4.0, 90.0],
}

# The thumb has ONE coordinate, not four independent angles.  A live hand
# works its joints together: when the column closes, every joint gives the
# same SHARE of its own range, so there is no pose with one joint twisted
# to its stop while its neighbour stays almost straight — the load spreads
# evenly (the author, 27.10.2026).  The state of the thumb is therefore a
# single number f:
#
#   f = 0   the rest pose above — the approved one, and the zero-energy
#           reference every other state is measured from;
#   f < 0   opening; f = -1 is the far end, the straight thumb;
#   f > 0   closing into a press; f = +1 is the far end, every joint at the
#           end of its own travel from rest.
#
# Each joint takes f times its OWN travel from rest, so the three move
# together in relative terms and none can be folded while its neighbour
# sleeps.  The direction of that travel is the one the movement actually
# uses, and for the saddle the two axes are coupled:
#
#   closing (a press)   the first metacarpal ADDUCTS — it tips palmar, out
#                       of the plane of the palm, toward the keys — while
#                       MCP and IP flex.  CMC flexion (the swing across the
#                       palm, toward the little finger) is NOT part of a
#                       press: mixed in, it walks the thumb over the palm
#                       and the pose reads like a fumble, not a key press.
#   opening             the metacarpal extends and abducts (the web opens),
#                       MCP and IP straighten.
#
# At f = 1 the CMC has used its 20° of adduction, the MCP its 34° and the IP
# its 46° — 100% each; at f = 0.4, 40% each.  That is what "the joints are
# worked together" means in numbers, and it is what an IK energy term should
# penalise: a deviation of one shared coordinate, not three independent
# joint angles.
const THUMB_ROOM := {
	"close": {"cmc_abd": -20.0, "mcp": 34.0, "ip": 46.0},
	"open": {"cmc_flex": -6.0, "cmc_abd": 10.0, "mcp": -16.0, "ip": -34.0},
}


static func thumb_at(f: float) -> Dictionary:
	f = clampf(f, -1.0, 1.0)
	var room: Dictionary = THUMB_ROOM["close"] if f > 0.0 else THUMB_ROOM["open"]
	var t := THUMB_REST.duplicate(true)
	if is_zero_approx(f):
		return t
	for k in room:
		t[k] = float(t[k]) + float(room[k]) * absf(f)
	return t


# How much of its own range each joint has spent in a state, in percent.
# The whole point of the single coordinate is that these three numbers stay
# equal; the probe and the HUD show them so the author can see it.  The
# saddle has two axes and a joint is credited with the larger of them: when
# the thumb closes, the CMC's work is its adduction, not its flexion.
static func thumb_effort(t: Dictionary) -> Dictionary:
	var branch := "close" if float(t["mcp"]) >= float(THUMB_REST["mcp"]) else "open"
	var room: Dictionary = THUMB_ROOM[branch]
	var out := {}
	for j in ["cmc", "mcp", "ip"]:
		var best := 0.0
		for k in room:
			if not str(k).begins_with(j):
				continue
			var r := float(room[k])
			if is_zero_approx(r):
				continue
			best = maxf(best, (float(t[k]) - float(THUMB_REST[k])) / r)
		out[j] = 0.0 if is_zero_approx(best) else maxf(0.0, best) * 100.0
	return out


# The states the study shows, as two independent axes: the four fingers are
# curled or straight, and the thumb is at one of its own values of f. The
# thumb is NOT tied to the fingers — with the fingers straight the author can
# cycle the thumb alone and watch CMC, MCP and IP move together.
const POSE_FINGERS := {"curled": 1.0, "straight": 0.0}
const POSE_THUMBS := {"rest": 0.0, "open": -1.0, "press": 0.4}


# The whole articulation state as absolute angles in degrees:
#   {"fingers": {"II": {"mcp", "pip", "dip", "fan"}, ...}, "thumb_f": f,
#    "arm": {"wrist_flex", ...}}
# IK works in this space, and so does the viewer; the six baked study states
# are just two values of flex_scale crossed with three values of f. The arm
# is part of the state because the IK chain continues past the wrist; at rest
# every arm angle is zero and its transform is the identity.
static func rest_pose() -> Dictionary:
	var p := {"fingers": {}, "thumb_f": 0.0,
		"arm": ArmModel.rest_arm()}
	for ray in FINGERS:
		p["fingers"][ray] = {"mcp": float(FLEX[ray][0]), "pip": float(FLEX[ray][1]),
			"dip": float(FLEX[ray][2]), "fan": float(FAN[ray])}
	return p


# The study's two finger states: flex_scale 1 keeps the rest angles, 0
# straightens every flexion. The fan is a posture, not a flexion, so it stays.
static func scaled_pose(flex_scale: float, thumb_f: float = 0.0) -> Dictionary:
	var p := rest_pose()
	for ray in FINGERS:
		for j in ["mcp", "pip", "dip"]:
			p["fingers"][ray][j] = float(p["fingers"][ray][j]) * flex_scale
	p["thumb_f"] = clampf(thumb_f, -1.0, 1.0)
	return p


# One finger's chain from absolute angles: the four joints and the three
# segment directions. Pure arithmetic — the SDF build, the IK solver and the
# bone view all take their geometry from here, so none of them can drift.
static func metacarpal_head(ray: String) -> Vector3:
	var base: Vector3 = MC_BASE[ray]
	var aim: Vector3 = MC_AIM[ray]
	return base + (aim - base).normalized() * float(MC_LEN[ray])


static func finger_fk(ray: String, angles: Dictionary) -> Dictionary:
	var mcp := metacarpal_head(ray)
	var down := Vector3(0, 0, -1)
	var fan := deg_to_rad(float(angles.get("fan", FAN[ray])))
	var d := Vector3(sin(fan), cos(fan), 0.0)
	# The flexion axis is fixed for the whole finger: all three hinges are
	# parallel, and the chain never leaves the plane they define. Deriving it
	# from each segment (d × down) is the same direction in exact arithmetic,
	# but when a phalanx points straight down that cross product collapses and
	# the joint refuses to bend — a discontinuity a dragged target walks right
	# into (21.10.2026, found by ik_test through a 17 mm jump in the middle of
	# a smooth target path). One axis, computed once, no singularity.
	var axis := d.cross(down).normalized()
	var lens: Array = PH_LEN[ray]

	var d1 := _bend(d, axis, deg_to_rad(float(angles.get("mcp", FLEX[ray][0]))))
	var pip := mcp + d1 * float(lens[0])
	var d2 := _bend(d1, axis, deg_to_rad(float(angles.get("pip", FLEX[ray][1]))))
	var dip := pip + d2 * float(lens[1])
	var d3 := _bend(d2, axis, deg_to_rad(float(angles.get("dip", FLEX[ray][2]))))
	var tip := dip + d3 * float(lens[2])

	return {"pts": PackedVector3Array([mcp, pip, dip, tip]), "dirs": [d1, d2, d3],
		"axis": axis}


# The thumb's four angles from a pose. New poses carry the full dictionary;
# older probes and the single-hand study carry only `thumb_f`, whose arc is
# still a valid thumb state. One reader, so nothing can drift between them.
static func thumb_of_pose(p: Dictionary) -> Dictionary:
	if int(p.get("thumb_dof", 0)) == 4 and p.has("thumb"):
		var t: Dictionary = p["thumb"]
		var out := {}
		for j in THUMB_JOINTS:
			out[j] = float(t.get(j, THUMB_REST[j]))
		return out
	return thumb_at(float(p.get("thumb_f", 0.0)))


# The thumb's chain from four joint angles. A float is still accepted: it is
# the old one-coordinate arc, expanded by thumb_at(), so the single-hand study
# and its probes keep their exact geometry.
static func thumb_fk(arg) -> Dictionary:
	var th: Dictionary
	if arg is Dictionary:
		var d := arg as Dictionary
		th = {}
		for j in THUMB_JOINTS:
			th[j] = float(d.get(j, THUMB_REST[j]))
	else:
		th = thumb_at(float(arg))

	var base: Vector3 = MC_BASE["I"]
	var lens: Array = PH_LEN["I"]
	var palm := Vector3(-0.35, 0.10, -0.93).normalized()
	var palmar := Vector3(0, 0, -1)
	var radial := Vector3(1, 0, 0)

	var d0 := (Vector3(MC_AIM["I"]) - base).normalized()
	d0 = _flex(d0, palmar, deg_to_rad(float(th["cmc_flex"])))
	d0 = _flex(d0, radial, deg_to_rad(float(th["cmc_abd"])))
	var mcp := base + d0 * float(MC_LEN["I"])
	# Both phalanx hinges share one axis, as the four fingers do: the axis of
	# the saddle's palmar swing in the frame the column now has. Recomputing
	# it from each segment loses it when a segment points along `palm`.
	# The column can also TURN about its own axis (CMC opposition): that turn
	# carries the fold plane with it, so the distal phalanges can close toward
	# the key instead of only across the palm.
	var palm_t := palm.rotated(d0, deg_to_rad(float(th["twist"])))
	var axis := d0.cross(palm_t).normalized()
	var d1 := _bend(d0, axis, deg_to_rad(float(th["mcp"])))
	var ip := mcp + d1 * float(lens[0])
	var d2 := _bend(d1, axis, deg_to_rad(float(th["ip"])))
	var tip := ip + d2 * float(lens[1])

	return {"pts": PackedVector3Array([base, mcp, ip, tip]), "dirs": [d0, d1, d2],
		"angles": th, "palm": palm, "palmar": palmar, "radial": radial}


# The point a fingertip touches with: the lowest point of the tip sphere, on
# the skin surface, not the bone tip. The IK target sits here, so the ball the
# viewer drags is the ball the hand actually presses. Down is world -z because
# the keyboard is a wall at constant z: a sphere touches it straight below its
# centre whatever direction the phalanx points. Offsetting along the phalanx
# instead (the old rule) understated the depth by R * (1 - |d3.z|), up to 2.4 mm
# on a finger lying 55 degrees to the key, and the mesh crossed the face while
# the pad still read above it (measured 30.10.2026).
static func finger_pad(ray: String, fk: Dictionary) -> Vector3:
	return fk["pts"][3] + Vector3(0.0, 0.0, -float(SKIN_R[ray][3]))


# The thumb touches a key with the lowest point of its tip. The tip is a
# spherical cap of THUMB_TIP_R, so the skin reaches furthest toward the key
# straight below the bone tip, whatever direction the distal phalanx points.
# The palmar projection (the point across the bone) understated the depth by
# 1.8 mm once the thumb was angled down 37 degrees: the pad still read 1.8 mm
# above the face while the mesh was already through it (measured 30.10.2026,
# I k24). A sphere has no such blind spot.
static func thumb_pad(fk: Dictionary) -> Vector3:
	return fk["pts"][3] + Vector3(0.0, 0.0, -THUMB_TIP_R)


# Soft-tissue radii: at the knuckle, the two interphalangeal joints, the tip.
# The thumb's tip skin radius, the last of the SDF's thumb radii.
const THUMB_TIP_R := 6.6

const SKIN_R := {
	"II": [9.8, 8.7, 7.4, 5.5],
	"III": [10.2, 9.0, 7.6, 5.7],
	"IV": [9.6, 8.5, 7.2, 5.3],
	"V": [8.6, 7.6, 6.5, 4.9],
}

const WRIST_A := Vector3(0, -30, 0)
const WRIST_B := Vector3(0, 8, 0)
const CARPUS_C := Vector3(0, 14, 0)
const CARPUS_R := Vector3(24.0, 17, 14.5)
const THENAR_C := Vector3(23, 44, -6)
const THENAR_R := Vector3(12.5, 23, 11.5)
const HYPOTH_C := Vector3(-30, 45, -4)
const HYPOTH_R := Vector3(9.0, 20, 9.0)

# ---- the silhouette filler -------------------------------------------
# The game draws the hand as the UNION of the primitives' projections. A
# union of projections is not the projection of the union: field() blends
# its primitives with smin, and the 9–11 mm fillet between the wrist, the
# first metacarpal and the thenar pushes the real surface up to 5 mm
# further out than the widest single projection. In the top view that
# deficit ends in a shelf where the thumb's metacarpal hands over to the
# wrist — the bump the author saw on the thumb side (05.11.2026: «со
# стороны большого пальца, линия контура, движущаяся к лучезапястному
# суставу, содержит непонятный шишах»).
#
# This ellipsoid is the mass that fillet stands for: the proximal thenar /
# radiocarpal web. It is deliberately NOT part of field(). It lies inside
# the approved surface almost everywhere, so the field would only gain a
# crease where it grazes the skin — a defect that exists in the projection
# alone. Its projected right edge was fitted to the TRUE shadow
# (shadow_probe.gd, 1 mm steps, y = 0…55) and stays 0.1–1.5 mm inside it
# along the whole radial border, so the drawn silhouette is the study's
# silhouette, not an approximation of it.
#
# It swings with the first metacarpal, exactly like the thenar: the rest
# rotation is identity, so the numbers below are rest numbers. Fitted on
# the game's rest pose (the pose the player sees most).
const FILL_C := Vector3(35.35, 38.08, -0.16)
const FILL_R := Vector3(9.98, 47.10, 9.0)
const FILL_AX := [Vector3(-0.94512, -0.31205, -0.09683),
	Vector3(-0.31623, 0.94818, 0.03098),
	Vector3(0.08214, 0.05990, -0.99482)]

var joints := {}
var bones := []
var nails := []           # [{pos, dir, up, w, l, t}]

var _pose := {}
var _thumb := THUMB_REST
var _skins := []          # [{pts, rs, axis}]
var _tips := []           # [[pos, radius], ...]
var _thenar_c := THENAR_C
var _thenar_ax := [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
var _fill_c := FILL_C
var _fill_ax := FILL_AX
var _thumb_pts := PackedVector3Array()
var _thumb_r := PackedFloat32Array()
var _thumb_axis := Vector3.RIGHT
var _knuckles := PackedVector3Array()
var _palm_cones := []     # [[a, b, ra, rb], ...]


func _init(flex_scale: float = 1.0, thumb_f: float = 0.0, pose: Dictionary = {}) -> void:
	_pose = pose.duplicate(true) if not pose.is_empty() else scaled_pose(flex_scale, thumb_f)
	_thumb = thumb_of_pose(_pose)
	_build_metacarpals()
	_build_fingers()
	_build_thumb()


func _build_metacarpals() -> void:
	for ray in ["I", "II", "III", "IV", "V"]:
		var base: Vector3 = MC_BASE[ray]
		var aim: Vector3 = MC_AIM[ray]
		var dir := (aim - base).normalized()
		var head := base + dir * float(MC_LEN[ray])
		joints[ray + "_BASE"] = base
		joints[ray + "_MCP"] = head
		bones.append({"name": ray + " MC", "a": base, "b": head,
			"r1": 5.6, "r2": 5.2, "len": float(MC_LEN[ray])})
		if ray != "I":
			# The head radius IS the skin radius of that ray's finger. With a
			# flat 10.4 the knuckle of the little finger stuck out 1.8 mm past
			# its own 8.6 mm finger: the palm is wider than the digit at the
			# very joint where the two meet, so the silhouette grew a lip
			# (author, 07.11.2026). The head sphere is shared with the finger
			# stub (field_roots), so equal radii make the two surfaces meet
			# tangentially — the knuckle becomes exactly the finger's width.
			_palm_cones.append([base - dir * 1.5, head, 10.6,
				float(SKIN_R[ray][0])])


func _build_fingers() -> void:
	for ray in FINGERS:
		var fk := finger_fk(ray, _pose["fingers"][ray])
		var pts: PackedVector3Array = fk["pts"]
		var axis: Vector3 = fk["axis"]
		var lens: Array = PH_LEN[ray]
		var mcp: Vector3 = pts[0]
		var pip: Vector3 = pts[1]
		var dip: Vector3 = pts[2]
		var tip: Vector3 = pts[3]

		joints[ray + "_PIP"] = pip
		joints[ray + "_DIP"] = dip
		joints[ray + "_TIP"] = tip

		bones.append({"name": ray + " P", "a": mcp, "b": pip,
			"r1": 4.4, "r2": 4.0, "len": float(lens[0])})
		bones.append({"name": ray + " M", "a": pip, "b": dip,
			"r1": 3.7, "r2": 3.4, "len": float(lens[1])})
		bones.append({"name": ray + " D", "a": dip, "b": tip,
			"r1": 3.1, "r2": 2.2, "len": float(lens[2])})

		var rr: Array = SKIN_R[ray]
		var rs := PackedFloat32Array([float(rr[0]), float(rr[1]), float(rr[2]), float(rr[3])])
		_skins.append({"pts": pts, "rs": rs, "axis": axis})
		_knuckles.append(mcp)
		_add_nail(dip, tip, axis, float(rr[2]), float(rr[3]), float(lens[2]), ray)


func _build_thumb() -> void:
	var fk := thumb_fk(_thumb)
	var base: Vector3 = fk["pts"][0]
	var mcp: Vector3 = fk["pts"][1]
	var ip: Vector3 = fk["pts"][2]
	var tip: Vector3 = fk["pts"][3]
	var d0: Vector3 = fk["dirs"][0]
	var palm: Vector3 = fk["palm"]
	var lens: Array = PH_LEN["I"]
	_thumb = (fk["angles"] as Dictionary).duplicate(true)

	joints["I_BASE"] = base
	joints["I_MCP"] = mcp
	for b in bones:
		if str(b["name"]) == "I MC":
			b["b"] = mcp
			break

	# MCP and IP — the two flexion hinges of the column, each its own joint.
	# _flex(d, palm, a) turns the segment toward the palm (the same rule the
	# four fingers use with their own "down"), so the column dips toward the
	# keys rather than swinging sideways. thumb_fk() has already done it.
	joints["I_IP"] = ip
	joints["I_TIP"] = tip
	bones.append({"name": "I P", "a": mcp, "b": ip, "r1": 5.0, "r2": 4.6, "len": float(lens[0])})
	bones.append({"name": "I D", "a": ip, "b": tip, "r1": 3.8, "r2": 2.8, "len": float(lens[1])})

	# The thenar eminence is a muscle belly ON the first metacarpal, so it
	# swings with the bone. Pinned to the world it stayed behind when the
	# column abducted, and the web between thumb and index stretched into a
	# fin. The rest frame is the world one (rotation = identity at rest), so
	# the approved rest surface is untouched to the last vertex.
	var rest_dir := (Vector3(MC_AIM["I"]) - base).normalized()
	var rot := Quaternion(rest_dir, d0)
	_thenar_c = base + rot * (THENAR_C - base)
	_thenar_ax = [rot * Vector3.RIGHT, rot * Vector3.UP, rot * Vector3.BACK]
	# The silhouette filler rides the same bone (see FILL_C).
	_fill_c = base + rot * (FILL_C - base)
	_fill_ax = [rot * (FILL_AX[0] as Vector3), rot * (FILL_AX[1] as Vector3),
		rot * (FILL_AX[2] as Vector3)]

	var axis := d0.cross(palm).normalized()
	_thumb_pts = PackedVector3Array([base, mcp, ip, tip])
	_thumb_r = PackedFloat32Array([11.8, 10.8, 9.6, THUMB_TIP_R])
	_thumb_axis = axis
	_add_nail(ip, tip, axis, 6.2, 5.4, float(lens[1]), "I")


func _add_nail(a: Vector3, b: Vector3, flex_axis: Vector3, r_base: float, r_tip: float,
		length: float, tag: String) -> void:
	var nd := (b - a).normalized()
	var dorsal := nd.cross(flex_axis).normalized()
	# The nail bed starts a little behind the tip joint and stops short of
	# the fingertip; it sits on the skin, not on the bone.
	var at := 0.55
	var r_at := lerpf(r_base, r_tip, at)
	var pos := a + nd * (length * at) + dorsal * (r_at * 0.99)
	nails.append({"pos": pos, "dir": nd, "up": dorsal, "tag": tag,
		"w": r_tip * 1.52, "l": length * 0.74, "t": 1.4})


# Rotate d toward t: the joint bends in that plane.
static func _flex(d: Vector3, t: Vector3, ang: float) -> Vector3:
	if absf(ang) < 0.00001:
		return d
	var axis := d.cross(t)
	if axis.length_squared() < 0.0000001:
		return d
	return d.rotated(axis.normalized(), ang)


# Rotate around an axis that is already known. A hinge's axis does not depend
# on where the segment currently points, and deriving it from the segment is
# what degenerates when the segment points along the bend direction.
static func _bend(d: Vector3, axis: Vector3, ang: float) -> Vector3:
	if absf(ang) < 0.00001:
		return d
	return d.rotated(axis, ang)


# ---- signed distance field of the skin --------------------------------

func field(p: Vector3) -> float:
	var d := field_palm(p)
	# Thumb skin: three cones along the first metacarpal and its phalanges.
	# The thumb is NOT part of field_palm for the same reason the fingers are
	# not: it sticks out of the palm, and a polar outline from the palm's
	# centre turns it into a spike.
	d = Sdf.smin(d, Sdf.cone(p, _thumb_pts[0], _thumb_pts[1], _thumb_r[0], _thumb_r[1]), 10.0)
	d = Sdf.smin(d, Sdf.cone(p, _thumb_pts[1], _thumb_pts[2], _thumb_r[1], _thumb_r[2]), 6.5)
	d = Sdf.smin(d, Sdf.cone(p, _thumb_pts[2], _thumb_pts[3], _thumb_r[2], _thumb_r[3]), 4.5)
	# Fingers are welded to the PALM, never to each other: blending each one
	# into the accumulating field glued neighbour to neighbour wherever the
	# surface gap was under the smoothing radius, and the joints of II-III-IV
	# read as one fused slab. The union of the four is hard (a crease is what
	# a real interdigital fold looks like), and only that union meets the palm
	# with a fillet.
	var fingers := 1.0e9
	for f in _skins.size():
		var skin: Dictionary = _skins[f]
		var pts: PackedVector3Array = skin["pts"]
		var rs: PackedFloat32Array = skin["rs"]
		var df := Sdf.cone(p, pts[0], pts[1], rs[0], rs[1])
		df = Sdf.smin(df, Sdf.cone(p, pts[1], pts[2], rs[1], rs[2]), 5.0)
		df = Sdf.smin(df, Sdf.cone(p, pts[2], pts[3], rs[2], rs[3]), 4.6)
		fingers = minf(fingers, df)
	return Sdf.smin(d, fingers, 6.0)


# THE PALM WITH THE FINGER ROOTS (author, 06.11.2026: "на бэкспейсе контур
# там, где палец переходит в ладонь, имеет неестественный изгиб"; the fingers
# must grow out of the palm organically IN EVERY POSE).
#
# WHY THE PALM ALONE IS NOT ENOUGH. The game draws the palm as one contour and
# each finger as its own band, then welds them with a HARD union
# (Geometry2D.merge_polygons). The palm alone ended at the knuckle line with a
# cap WIDER than the finger it feeds (a flat 10.4 mm for every ray, while the
# little finger's skin is 8.6), so the band's side crossed the palm's edge and
# the hard union kept the sharp V there — the notch the author saw on the
# backspace pose sat right at the little finger's root, and the same crossing
# made the knuckle lip he reported at rest (07.11.2026).
#
# THE FIX IS IN THE FIELD, SO THE 2D ONLY INHERITS IT. Bake the palm from a
# field that ALREADY carries the first 13 mm of every finger: each finger's
# proximal cone, truncated, hard-unioned with its neighbours (fingers never
# weld to each other — see field(): that glued II-III-IV into one slab) and
# then hard-unioned with the palm. The baked contour then turns up into the
# finger tangentially and the band's straight side continues it without a
# kink. The union is HARD because the palm's metacarpal head carries the same
# skin radius as the finger it feeds (see _build_metacarpals): the two bodies
# share one cap sphere at the MCP, so there is no step for a fillet to hide —
# and a fillet would only widen the knuckle (author, 07.11.2026).
#
# The stub is 13 mm because that is what the TRUE shadow shows: sampled at
# 0.1 mm (tools/hand3d/root_zoom.gd) the interdigital slits of the rest pose
# close 4-9 mm above the knuckle line, with a smooth taper — the fingers, not a
# cut. The stub lies entirely INSIDE the band the game draws (same radii,
# same axis), so it never widens the finger; it only rounds the root.
const ROOT_STUB := 13.0

func field_roots(p: Vector3) -> float:
	var d := field_palm(p)
	var stubs := 1.0e9
	for f in _skins.size():
		var skin: Dictionary = _skins[f]
		var pts: PackedVector3Array = skin["pts"]
		var rs: PackedFloat32Array = skin["rs"]
		var seg := pts[1] - pts[0]
		var l := seg.length()
		if l < 0.001:
			continue
		var k := clampf(ROOT_STUB / l, 0.0, 1.0)
		stubs = minf(stubs, Sdf.cone(p, pts[0], pts[0] + seg * k,
			rs[0], lerpf(rs[0], rs[1], k)))
	# A HARD union, not a fillet: the palm's metacarpal head now carries the
	# finger's own skin radius (_build_metacarpals), so the two surfaces share
	# one cap sphere at the MCP and meet tangentially. The 6 mm fillet that
	# used to hide the step also pushed the silhouette out by k/4 = 1.5 mm —
	# the rest of the knuckle lip (author, 07.11.2026). With nothing to hide,
	# the fillet has nothing left to do but widen the joint.
	return minf(d, stubs)


# The palm alone: everything the hand is made of except the five digits.
# The game draws the palm as one contour and each digit as its own band from
# the digit's own chain (tools/hand3d/bake_outline.gd bakes the first, the
# game's FK builds the second), so this is the half of the silhouette the
# polar outline can hold: the palm has no thin protrusions at all (the thumb
# web is a wide V filled by the thenar), and the digits are nothing but
# slits and spikes seen from the palm's centre.
#
# field_roots() above is what the game's outline is actually baked from; this
# one is the palm on its own (the study's tools measure it: palm width, the
# wrist cut, the thenar).
func field_palm(p: Vector3) -> float:
	var d := Sdf.capsule_scaled(p, WRIST_A, WRIST_B, 27.0, 27.5, Vector3(1, 1, 0.72))
	d = Sdf.smin(d, Sdf.ellipsoid(p, CARPUS_C, CARPUS_R), 13.0)
	# The palm itself: a fan of tapered cones along the metacarpals. That
	# keeps the knuckle line arched and leaves no step at the finger roots.
	for c in _palm_cones:
		d = Sdf.smin(d, Sdf.capsule_scaled(p, c[0], c[1], c[2], c[3], Vector3(1, 1, 1.12)), 9.5)
	# The first dorsal interosseous: the muscle that fills the web between the
	# thumb and the index. Without it the web is a thin fin of blended cones.
	d = Sdf.smin(d, Sdf.ellipsoid(p, Vector3(33, 56, 4), Vector3(12, 18, 11)), 9.0)
	# The palm is flat, not dished: its hollow lives between the two
	# eminences, and a subtracted dish only made a step where the thenar and
	# the hypothenar rise out of it.
	d = maxf(d, -1.5 - p.y)    # the forearm is cut flat, not rounded off
	d = Sdf.smin(d, Sdf.ellipsoid_oriented(p, _thenar_c, THENAR_R,
		_thenar_ax[0], _thenar_ax[1], _thenar_ax[2]), 11.0)
	d = Sdf.smin(d, Sdf.ellipsoid(p, HYPOTH_C, HYPOTH_R), 11.0)

	# Nail beds are not modelled: a bed is 0.5 mm deep, the grid is 2 mm, and
	# the rim of that facet returned noisy normals (dark zigzags at every DIP).
	# The knuckle and joint creases come from the field itself.

	return d


# The rest angles, collected in one place. Anything that needs "the hand's
# zero" (IK energy, a passivity model, a test that a free hand stays put)
# takes it from here instead of carrying its own copy.
func rest_angles() -> Dictionary:
	return {
		"flex": FLEX.duplicate(true),
		"fan": FAN.duplicate(),
		"thumb_f": 0.0,
		"thumb": THUMB_REST.duplicate(true),
		"thumb_room": THUMB_ROOM.duplicate(true),
		"thumb_states": POSE_THUMBS.duplicate(),
	}


# The thumb's angles as they are actually applied, for the HUD and for tests:
# the CMC and MCP degrees are what move the column, not a label.
func thumb_angles() -> Dictionary:
	return _thumb.duplicate(true)


# The projection filler (see FILL_C): the mass the smin fillet stands for,
# as a world-space ellipsoid. The game projects it with the rest of the
# skin; the field does not include it.
func fill_ellipsoid() -> Dictionary:
	return {"c": _fill_c, "r": FILL_R, "ax": _fill_ax.duplicate()}


func bounds_min() -> Vector3:
	return Vector3(-70, -30, -95)


func bounds_max() -> Vector3:
	# x reaches 108: a straight abducted thumb puts its tip past 95, and the
	# field would cut it off with a flat face at the end of the grid.
	return Vector3(108, 215, 55)
