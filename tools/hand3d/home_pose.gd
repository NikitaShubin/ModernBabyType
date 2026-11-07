# The typing home pose, shared by the board viewer and the home search.
#
# SS50h — the author's brief of 03.11.2026 (#8): "руки в локтях надо развести
# посильнее, вместе с чем развентутся и кисти. после этого положение больших
# пальцев надо расслабить. Для сохранения горизонтальности кончиков 4-х
# пальцев руки естественным следствием окажется то, что мизинец должен быть
# более скручен, чем указательный палец."
#
# WHAT THE WIDE ELBOWS DO TO THE HAND. The hand's world yaw is
# forearm_abd + wrist_dev; turning the forearm out by 12° more (22 → 34)
# turns the hand with it. The four home keys do not move, so every knuckle
# has to adduct by the amount the hand turned. The fan is NOT a fixed
# multiple of the yaw: the four fingers need different corrections, and the
# gradient across them is what the author predicted. At the chosen 24° the
# finger planes sit at 11.8 / 16.7 / 21.1 / 24.5° (fan −12.24 / −7.28 /
# −2.91 / +0.52), i.e. the little finger is twisted as far as the hand and
# the index is twisted back the most. 24° is the practical ceiling: the
# index's adduction is already near its band limit, and beyond it the pad
# no longer finds its key.
#
# THE HAND SITS 5 mm DEEPER (toward the board), AND THAT IS NOT COSMETIC. The
# index is the short one: at elbow_z −44 its home key asks 90.40 mm from the
# metacarpal head while the fully straight chain spans 86.66 mm (V −1.17 mm),
# so the pad could not reach the key at all. Bringing the wrist to −49 leaves
# only 19.7 mm of depth to the pad instead of 24.7 (the knuckle carries the
# difference, the two distal joints stay almost straight) and all four pads
# land within 0.01 mm of their faces.
#
# THE THUMBS ARE RELAXED, NOT TUCKED. The held twist drops from −30 to −10:
# the distal phalanx lies 18.8° off the key face instead of 5°, which is the
# "almost tangent" the author asked for in #6, and the pad still lands on the
# bar. The two thumbs are 18.28 mm apart at the tips (5.08 mm of tapered
# flesh), so they do not touch — measured with the capsule radii tapered from
# joint to joint, not the old max-of-two (that read 0.92 mm of penetration
# and made every press tuck the resting thumb 13.58 mm off the bar).
#
# SS50f (kept for history) made the right thumb an EXACT TWIN of the left:
# the angles are LOCAL and the right's world enters x-reversed
# (world = root_R − q.x), so both hands solve the identical local thumb
# problem and HomePose.build returns byte-identical thumb dicts (checked,
# thumb_mirror_r.gd). The mirror axis is the home group "ф"↔"ж", not the
# screen centre: the board's letter rows are shifted right by the left
# hand's modifiers (Tab/Caps/Shift), so the two roots are symmetric about
# x −14.29, not about 0.
#
# The author's brief (31.10.2026): "в реальной позиции предплечья не
# параллельны, а разведены, чтобы между локтями было куда бОльшее расстояние.
# ... Пальцы, кроме больших, лежат едва касаясь клавиш «фываолдж»... большие
# ... на ±20–23 мм с зазором ≥15–20 мм и подъёмом ~2 мм".
#
# The arm is placed, not solved at runtime: the placement below was found by
# home_solve4.gd (the wrists, the splay, the turn) and then checked digit by
# digit with the depth scanned across each key (depth_scan.gd). The forearms
# are splayed 34 degrees, the elbows 384.2 mm apart (the old straight-down
# pose had 115.2), and every pad lies ON its key's face.
#
# DEPTH IS FREE, WIDTH AND HEIGHT ARE NOT. A key is 20.76 mm deep, and the
# fingers are not one line across it. The old pose fixed x and y and let z
# float (the pads hovered 5..20 mm above the keys); fixing y instead is what
# lets the pads TOUCH. The y offsets are all zero at SS50h: every pad's x/z
# residual is zero with its own row's y, so no finger needs a per-digit
# depth offset.
extends RefCounted

const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")
const IK := preload("res://ik.gd")
const Kbd3D := preload("res://kbd3d.gd")

const TOUCH := 0.3            # the pad's sphere bottom above the key face, mm
# THE THUMBS ARE POSE TWINS (SS50f, the author's call of 02.11.2026). With
# the dicts below both sides run the identical LOCAL thumb problem, so every
# HomePose.build returns the same canonical thumb posture: the left keeps its
# own target (-22.51, y 112) and the twin lands (-6.06, y 112) — the same
# local (+100, 112) both times; no IK retargeting is done by hand.
#
# THE PAD LIES ON THE CAP, NOT HOOKED INTO IT (author, 03.11.2026, #6):
# "первые фаланги больших пальцев неестественно согнуты, направля кончик
# пальца строго вниз на кнопку штопором… кончики лежат почти по касательной
# к поверхности кнопки". The old contact (local 92, y 100, at the old -30°
# twist) is INSIDE the column's easy reach, and the only way the pad gets
# there is by folding the IP joint 74° — a corkscrew no hand holds for a
# minute. A point target pins all three free thumb degrees, so no tangency
# weight can answer it: the CONTACT has to move out. Scanned over the thumb's
# own grid at the held twist/abduction (thumb_scan.gd, re-run at SS50h),
# local (100, 112) is the flattest reachable point — the distal phalanx lies
# 18.8° off the face, MCP +21.3, IP +0.8 (the first phalanx carries the bend,
# the tip stays extended), and the pad lands on the target (miss 0.06).
# Everything nearer the palm is hooked again: (96, 108) is 46.4° with the IP
# at +49.5, (92, 108) 47.7°. Further out is out of reach (the reachable grid
# stops at x 100). The twin's x goes NEGATIVE because the hands' midpoint is
# not the bar's: it is 6.06 mm past the bar's centre. The two pads are
# 18.28 mm apart at the tips and 5.08 mm apart with the capsule radii tapered
# joint to joint, so the flesh does not touch (the old max-of-two radii read
# 0.92 mm of penetration — see ik.gd).
const THUMB_XS := {"L": 22.51, "R": -6.06}
const THUMB_LIFT := 2.0       # the resting thumb hovers this much, mm
# DEPTH IS FREE FOR THE THUMB TOO — and THE SAME for both: the twin's pad
# copies the left's depth (y 112) with no solving on the right. This is the
# outer half of the bar (98.1..118.9), which is where a thumb pointing away
# from the typist lies; y 100 put the pad on the near edge only because the
# hooked column could not reach further.
const THUMB_Y := {"L": 112.0, "R": 112.0}
# THE OPPOSITION IS A POSTURE, HELD PER HAND — and under SS50f HELD AS A
# PAIR: the twin copies whatever the left's solve produced, twist included;
# these constants only keep the direct-IK path and the HUD consistent.
# Held twist keeps the thumb from folding ACROSS the palm (the IP joint
# would land at world x 0 instead of -5) while only turning the plane the
# distal phalanx folds in, and the IP joints stay under their own pads.
# -10 is the RELAXED hold of SS50h (03.11.2026, #8): at the old -30 the tip
# stood 5° off the key face — a corkscrew — at -10 it lies 18.8° off, and the
# pad still lands on the bar (thumb_geo.gd).
const THUMB_TWIST := {"L": -10.0, "R": -10.0}
# THE COLUMN STANDS ABDUCTED (02.11.2026). This is the CMC abduction held
# while the thumb is solved: the joint is the thumb's own radial swing, and
# holding it at -9 (instead of the -15.18 the old target forced) lets the
# first metacarpal rise OUT of the palm's silhouette — the third phalanx is
# no longer tucked under the palm (author, #2). The twins share it.
const THUMB_ABD := {"L": -9.0, "R": -9.0}
const HOME_DY := {"II": 0.0, "III": 0.0, "IV": 0.0, "V": 0.0} # all zero at SS50h: every pad's x/z residual is zero with its own row's y (thumb_geo.gd)

# The placement from home_solve4.gd, re-tuned for SS50h: the wrist at
# (0, 20, -49) in the hand's own frame, the forearms splayed 34 degrees, the
# hand turned by -10 degrees of ulnar deviation and -20 of extension, no
# pronation. The elbow is derived:
#   elbow = wrist - 150 * (sin abd, cos abd, 0)
# so the two elbows land at x = -83.88 and +83.88 mm from their roots — world
# x -206.4 and +177.8, 384.2 mm apart (SS50f had 228.8). The elbow fields
# below are ArmModel's own (elbow = ELBOW + these), not the wrist: elbow_y is
# the wrist's y plus 150 - 150 cos(abd). elbow_z sits 5 mm deeper than SS50f's
# -44 because at that height the index could not reach its home key at all
# (see the header: 90.40 mm asked, 86.66 mm of chain).
const ARM := {
	"wrist_flex": -20.0,
	"wrist_dev": -10.0,
	"pronation": 0.0,
	"forearm_flex": 0.0,
	"forearm_abd": 34.0000,
	"elbow_x": -83.878936,
	"elbow_y": 45.644364,
	"elbow_z": -49.0,
}

# THE WHOLE-ARM SHIFT (02.11.2026, approved by the author): the wrist
# roots sit ONE WRIST OUTSIDE the D-era pair. Every tool that owns a
# root constant reads THIS dict first — the pose and its audience
# can never disagree about where the hands hang.
const HOME_ROOTS := {"L": -122.51, "R": 93.94}

const HOME_LABELS := {
	"L": {"II": "а", "III": "в", "IV": "ы", "V": "ф"},
	"R": {"II": "о", "III": "л", "IV": "д", "V": "ж"},
}


static func _opts(ray: String) -> Dictionary:
	var o := {"arm": false, "tuck": false, "clear_w": 0.0, "dir_w": 0.0}
	if ray == "I":
		o["thumb_dof"] = 4
	return o


static func _key_x(label: String) -> float:
	var ks := Kbd3D.keys()
	return Kbd3D.centre(ks[Kbd3D.index_of(ks, label)]).x


# The target of one digit in the model's local space, for a hand whose root
# sits at root_x and whose visual is mirrored for the right side.
static func target(side: String, ray: String, root_x: float) -> Vector3:
	var sgn := -1.0 if side == "R" else 1.0
	if ray == "I":
		var wx: float = float(THUMB_XS[side])
		var txx: float = -wx if side == "L" else wx
		var v := Vector3((txx - root_x) * sgn, float(THUMB_Y[side]),
			Kbd3D.FACE_Z + THUMB_LIFT)
		return v
	var label: String = (HOME_LABELS[side] as Dictionary)[ray]
	return Vector3((_key_x(label) - root_x) * sgn,
		Kbd3D.row_y(2) + float(HOME_DY[ray]), Kbd3D.FACE_Z + TOUCH)


# Each digit is solved once to its own key point: the arm is frozen, the tuck
# is off (no finger may be moved behind another's back on the home row), and
# the keyboard clearance is off (the idle fingers REST on their own keys; a
# clearance plane would push the whole hand up off the board).
static func build(side: String, root_x: float,
		arm: Dictionary = ARM) -> Dictionary:
	var p := HandModel.rest_pose()
	p["arm"] = arm.duplicate(true)
	p["thumb_f"] = 0.0
	p["thumb"] = HandModel.thumb_at(0.0)
	p["thumb_dof"] = 4
	p["thumb_hold"] = {"twist": float(THUMB_TWIST[side]),
		"cmc_abd": float(THUMB_ABD[side])}
	for ray in ["II", "III", "IV", "V", "I"]:
		var r: Dictionary = IK.solve_chain(ray, target(side, ray, root_x), p,
			_opts(ray))
		p = r["pose"]
	return p
