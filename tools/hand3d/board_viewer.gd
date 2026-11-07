# The project's keyboard with BOTH hands over it.
#
# This is the integration step of the hand study: the keyboard is the game's
# own five-row board (kbd3d.gd), and a click on a key picks the hand and the
# finger from the key's place on that board — the user never chooses a finger.
# The left hand is the model; the right hand is the SAME model, solver and bone
# poses rendered under a root mirrored in x (hand_rig.gd), so the two sides
# cannot disagree.
#
# Every click goes through the same chain as the single-hand study: the press
# pose is solved with the whole arm free (finger → fan → wrist → pronation →
# forearm → elbow), the hover is that pose pulled straight back along +z by a
# rigid elbow translation, and the path rest → hover → press → hover → rest is
# one C1 PCHIP (click_path.gd). The idle fingers are kept above the key face
# over the WHOLE plane, not just over a keycap; the pressing tip is the only
# part allowed through, and its own path is guarded against the other keys.
#
# Controls: click a key — the hand and finger are chosen by the board; Space —
# both hands to rest; R — camera (whole board / left hand / right hand);
# 1/2/3 — skin / bones / x-ray; mouse drag off a key — orbit; wheel — zoom;
# Esc — quit.
extends Node3D

const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")
const HandRig := preload("res://hand_rig.gd")
const Kbd3D := preload("res://kbd3d.gd")
const IK := preload("res://ik.gd")
const ClickPath := preload("res://click_path.gd")
const HomePose := preload("res://home_pose.gd")

const SCALE := 0.001
const REST_MESH := "res://cache/skin_curled_rest.res"
const FONT_PATH := "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"

const FINGER_NAME := {"I": "большой", "II": "указательный",
	"III": "средний", "IV": "безымянный", "V": "мизинец"}
const SIDE_NAME := {"L": "левая", "R": "правая"}

# The keycaps. The face is kbd3d.gd's; the box is centred half a thickness
# below it, so its top face is exactly FACE_Z and a press sinks it by TRAVEL.
const KEY_Z := Kbd3D.FACE_Z - Kbd3D.THICK * 0.5
const KEY_HOVER := 12.0
const THUMB_HOVER := 5.0
# The thumb's soft-tissue radii at the four FK joints, mm (hand_model.gd's
# SDF uses the same numbers). The foreign capsules use them as segment radii.
const THUMB_R := [11.8, 10.8, 9.6, 6.6]
const THUMB_PRESS_LO := -0.35
const CLEAR_Z := Kbd3D.FACE_Z + 3.0
const SINK_LEAD := 3.0
const CLICK_APPROACH_MIN := 0.22
const CLICK_APPROACH_MAX := 0.50
const CLICK_PRESS := 0.16
const CLICK_RELEASE := 0.12
const CLICK_RETURN := 0.40

const SMOOTH_RATE := 22.0
const SMOOTH_RATE_WRIST := 14.0
const SMOOTH_RATE_FOREARM := 8.0
const SMOOTH_RATE_ELBOW := 4.0
const LEVEL_EPS := 0.5
const SMOOTH_SNAP := 0.05

const FPS_ACTIVE := 60
const FPS_IDLE := 10
const FPS_UNFOCUSED := 5
const IDLE_AFTER := 1.2

# Framing. The board is 285 mm wide and the visible arms reach 150 mm behind
# the wrists, so the whole study is about 400 mm tall. The hand presets keep
# the keyboard in the picture, because a hand alone no longer says where it is.
const FIT_FILL := 0.90
const HUD_BOTTOM := 230.0
const HINT_TOP := 120.0
const CAM_SPAN := [400.0, 260.0, 260.0]
const CAM_MID := [Vector2(0.0, 30.0), Vector2(-70.0, 105.0),
	Vector2(45.0, 105.0)]

const KEY_IDLE := Color("#e6e0d2")
const KEY_HOVER_COL := Color("#cbdcf2")
const KEY_DOWN_COL := Color("#9dc3ef")
const BOARD_COL := Color("#3b424d")

var _keys: Array
var _board_root: Node3D
var _key_nodes: Array[MeshInstance3D] = []
var _key_mats: Array[StandardMaterial3D] = []
var _hover_key := -1
var _down_key := -1

var _hands := {}
var _focus := "L"
var _mode := 0

var _cam: Camera3D
var _rig_root: Node3D
var _yaw := 0.18
var _pitch := 0.52
var _dist := 0.7
var _center := Vector3.ZERO
var _cam_preset := 0
var _drag := ""

var _click_stage := ""
var _click_hand := ""
var _click_ray := ""
var _click_key := -1
var _click_t := 0.0
var _click_pose_rest := {}
var _click_pose_end := {}
var _click_pose_hover := {}
var _click_pose_press := {}
var _click_path := {}
var _click_lift := 0.0
var _click_face := Vector3.ZERO
var _click_press_pad := Vector3.ZERO
var _click_err_rest := 0.0
# The HUD's "остаток" is the distance from the DISPLAYED pad to the press
# point, not a stale number: the solver's own error is always zero because the
# elbow nudge closes it, so it cannot tell the eye how far the hand still is.
var _press_on := false
var _press_side := ""
var _press_ray := ""
var _press_target := Vector3.ZERO
var _frozen := false

var _mat_skin: StandardMaterial3D
var _mat_xray: StandardMaterial3D
var _mat_skin_r: StandardMaterial3D
var _mat_xray_r: StandardMaterial3D
var _title: Label
var _state: Label
var _hint: Label

var _idle_t := 0.0
var _focused := true
var _render_on := true
var _auto := false          # MBT_SHOT mode: programmatic comparable stills
var _halves := {}           # split/tent concept: side -> hinge node

# ---- simulator (MBT_SIM=1) ---------------------------------------------
# MBT_SIM=1 turns the window into the typed simulator the author asked for
# (02.11.2026): pressing a REAL key plays the very same press animation as a
# click — the board names the key, Kbd3D.hand_finger picks the hand and the
# finger, the press is solved with the whole arm free by the same call the
# click path uses. Every held key keeps its fingertip on its cap: when a
# second finger of the same hand presses, the held finger is re-solved onto
# its own key from the new arm pose (the 2D game's "зажатие держит палец"
# rule). The space bar goes to the thumb of the hand opposite the last
# letter, left first — the game's own "пробел:Л/П" rule.
var _sim := false
var _simdbg := OS.get_environment("MBT_SIM_DEBUG") != ""
var _sim_held := {}         # key index -> {side, ray, deep}
var _sim_click_key := -1    # the key the mouse button is holding down
# Presses waiting for their stroke, one taken per frame (author, #9: "если
# нажимать несколько клавиш быстро подряд, то симулятор зависает"). The event
# handler must not solve: a queued burst used to run every stroke inside _input,
# one behind the other, with no frame drawn in between. Taking them one per
# frame keeps the window painting while the queue drains, and a key released
# before its stroke started is remembered in _sim_tapped and played as the
# short tap it was.
var _sim_queue := []        # [[key index, side], ...]
var _sim_tapped := {}       # key index released while still queued
# "side:key" -> the whole stroke {hover, press, glide, hz, hover_t, deep}: the
# stroke of one key, solved once (see _sim_stroke_cached). The base is the
# canonical home and the other hand rests, so the answer cannot drift; a chord
# never enters here.
var _sim_pose_cache := {}
# THE WARMING PASS (author, #9: "если нажимать несколько клавиш быстро подряд,
# то симулятор зависает"). One press costs 0.05–1.9 s of solving, and a key
# typed behind it waited on the main thread — the window stopped painting. The
# stroke of a key is a function of (hand, key) alone, so it is computed AHEAD
# OF TIME, one key per idle frame: by the time a key is struck its stroke is
# usually already in the cache and the press costs nothing at all.
#
# It runs on the MAIN thread, in the idle window the viewer already has (the
# render loop is off there, so the half-second a stroke takes is invisible).
# A worker thread was tried first and abandoned: ik.gd keeps its solver state
# in statics, and a solve on another thread raced with the main thread's own
# IK calls (measured: ArmModel.WEIGHT lookups failing mid-solve).
var _sim_warm_queue := []   # [[side, key index], ...] in warming order
var _sim_warm_i := 0
var _sim_rest_home := {}    # side -> the canonical pose, frozen at open
var _sim_rest_rx := {}      # side -> the hand root's world x, frozen at open
var _sim_rest_foreign := {} # side -> the other hand's capsules AT REST
var _sim_ev := {}           # event identity -> key index (for keyup)
# THE BOTTOM ROW'S OWN PRICE LIST (#11 follow-up, see ArmModel.WEIGHT_OVERRIDE).
# The approved hierarchy makes the elbow thirty-five times dearer per mm than a
# wrist bend and the finger nearly free, which on the far bottom keys left the
# hand in place and curled the pinky (measured: 1.4 mm of hand travel on left
# Ctrl, mcp 76°). The author's rule is the other way round, so the bottom-row
# strokes charge a cheap elbow and forearm swing and a dearer finger. Empty
# `_sim_bot_w` would mean the approved hierarchy.
var _sim_bot_w := {"elbow_x": 10.0, "elbow_y": 10.0, "forearm_abd": 10.0}
var _sim_bot_prior := 2.0
var _sim_letter_side := ""  # the side of the last letter key pressed
var _sim_space := -1        # the space bar's index (its hand field is RIGHT regardless)
var _sim_lat2ru := {}       # latin legend -> Cyrillic key name, for EN typing
# The typed stroke is a PROFILED animation, one per hand, on a pose path
# (click_path.gd's PCHIP sampler). The exponential chase that a click uses
# cannot serve typing: its arm joints decay at SMOOTH_RATE_ELBOW, so a far
# key's arrival tails off for over a second, and every fast keystroke resets
# that tail from wherever the hand happens to be — the eye loses the whole
# stroke and the contact becomes an imperceptible crawl (the author's
# report 02.11.2026). The typed stroke is instead one path through three
# poses — the hand as it is now, the HOVER (the finger already over its key,
# the arm already travelled), and the PRESS (the pad at the key's bottom) —
# then HOLD; the release is the same three keyframes backwards, so the
# withdrawal starts the moment the bottom is reached.
var _sim_anim := {"L": {}, "R": {}}
var _sim_down := {}         # keys whose cap has been struck (sampled display pad)
var _sim_up := {}           # released keys whose cap still rides the finger up

# Stroke times, seconds. The approach scales with the travel distance
# (SIM_APPROACH_DIV metres of distance per second of glide), like the click
# path's own rule but snappier, because typing is a rehearsal, not a tour.
const SIM_APPROACH_MIN := 0.16
const SIM_APPROACH_MAX := 0.34
const SIM_APPROACH_DIV := 900.0
const SIM_HOVER_DIV := 30.0    # mm of travel per full hover height
const SIM_HOVER_MIN := 4.0     # closer than this, the hover is the home pose
const SIM_SETTLE_EPS := 0.2    # mm of depth the finger leaves to the hand
const SIM_STRIKE := 0.06     # hover -> the key's bottom, the visible hit
const SIM_STRIKE_DIV := 300.0  # a deeper descent takes a little longer
const SIM_STRIKE_MAX := 0.16
const SIM_UPLIFT := 0.10     # press -> hover, on release
const SIM_RETURN_MIN := 0.20
const SIM_RETURN_MAX := 0.40
# The warming pass runs in the window the viewer already treats as idle: the
# same threshold that stops the render loop (author, #9). A keystroke that lands
# while a stroke is being warmed waits for it — at most one stroke, which is
# what that keystroke would have cost cold anyway. While the author types,
# _idle_t keeps resetting, so warming stands aside and never slows typing.
# A released cap rides its finger only so long as a real return stroke lasts
# (the longest path below is ~0.35 s). Past this ceiling it pops back up even
# if the pad never clears the face: in the degenerate same-ray case (a key
# held while the SAME finger is asked to press — outside real typing) the
# parked hover is unreachable with the arm pinned, the pad stays under the
# face forever, and the whole sim reports "busy" until the frames run out.
# The ceiling keeps the sim from wedging; real strokes always finish earlier.
const SIM_RIDER_LIFE := 0.45

# Physical chord table: keycode → board key, the same physical rows as the
# game's board. Godot's keycode is the layout's Latin identity, so a QWERTY-A
# key under the ru layout reports KEY_F while the typed character is "а".
const SIM_QWERTY := {
	KEY_Q: "й", KEY_W: "ц", KEY_E: "у", KEY_R: "к", KEY_T: "е",
	KEY_Y: "н", KEY_U: "г", KEY_I: "ш", KEY_O: "щ", KEY_P: "з",
	KEY_BRACKETLEFT: "х", KEY_BRACKETRIGHT: "ъ", KEY_BACKSLASH: "\\",
	KEY_A: "ф", KEY_S: "ы", KEY_D: "в", KEY_F: "а", KEY_G: "п",
	KEY_H: "р", KEY_J: "о", KEY_K: "л", KEY_L: "д", KEY_SEMICOLON: "ж",
	KEY_APOSTROPHE: "э", KEY_Z: "я", KEY_X: "ч", KEY_C: "с", KEY_V: "м",
	KEY_B: "и", KEY_N: "т", KEY_M: "ь", KEY_COMMA: "б", KEY_PERIOD: "ю",
	KEY_QUOTELEFT: "ё", KEY_MINUS: "-", KEY_EQUAL: "=",
}
# Shifted characters → the base key that carries them (RU digits row and the
# US pairs the layout shares). The real Shift presses its own key separately,
# so the sim needs no synthetic modifier: the author IS holding shift.
const SIM_SHIFT_CHAR := {
	"!": "1", "\"": "2", "@": "2", "№": "3", "#": "3", ";": "4", "$": "4",
	"%": "5", ":": "6", "^": "6", "?": "7", "&": "7", "*": "8",
	"(": "9", ")": "0", "_": "-", "+": "=", "~": "ё", ",": ".",
}


func _ready() -> void:
	Engine.max_fps = FPS_ACTIVE
	_auto = OS.get_environment("MBT_SHOT") != ""
	get_window().title = "Клавиатура проекта · две кисти · IK до локтя (Esc — выход)"
	_keys = Kbd3D.keys()
	_make_env()
	_make_lights()
	_make_camera()
	_make_hands()
	_make_keyboard()
	_make_ui()
	_fit_camera()
	get_viewport().size_changed.connect(_fit_camera)
	_apply_all()
	_update_hud()
	if OS.get_environment("MBT_SIM") != "":
		_sim_open()
	if _auto:
		_auto_shoot(OS.get_environment("MBT_SHOT"))


func _make_env() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#dfe3e6")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#ffffff")
	env.ambient_light_energy = 0.06
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.tonemap_exposure = 0.72
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


func _make_lights() -> void:
	_rig_root = Node3D.new()
	add_child(_rig_root)
	_add_light(Vector3(-48, -56, 0), 1.05, Color("#fff6ea"))
	_add_light(Vector3(-10, 52, 0), 0.09, Color("#eaf2ff"))
	_add_light(Vector3(-72, 166, 0), 0.30, Color("#ffffff"))


func _add_light(rot_deg: Vector3, energy: float, col: Color) -> void:
	var l := DirectionalLight3D.new()
	l.rotation_degrees = rot_deg
	l.light_energy = energy
	l.light_color = col
	l.shadow_enabled = false
	_rig_root.add_child(l)


func _make_camera() -> void:
	_cam = Camera3D.new()
	_cam.fov = 30.0
	_cam.near = 0.01
	_cam.far = 6.0
	add_child(_cam)
	_cam.current = true


# ---- the two hands -----------------------------------------------------

func _make_hands() -> void:
	var rest := HandModel.rest_pose()
	# The wrists sit where the model's own index pad is over its home key:
	# the left index over "а", the right index over "о". The board's home row
	# is at y = 152, and the model's rest pads are already at that depth, so a
	# single x translation per hand puts the hands over their halves.
	var pad_ii := HandModel.finger_pad("II",
		HandModel.finger_fk("II", rest["fingers"]["II"])).x
	var a := Kbd3D.centre(_keys[Kbd3D.index_of(_keys, "а")]).x
	var o := Kbd3D.centre(_keys[Kbd3D.index_of(_keys, "о")]).x
	# The enshrined home pose carries its own whole-arm-shifted roots; the
	# env (MBT_ROOT_L / MBT_ROOT_R) is only for probes and sweeps film.
	var roots := [float(HomePose.HOME_ROOTS["L"]),
		float(HomePose.HOME_ROOTS["R"])]
	var el := OS.get_environment("MBT_ROOT_L")
	var er := OS.get_environment("MBT_ROOT_R")
	if el != "":
		roots[0] = float(el)
	if er != "":
		roots[1] = float(er)
	print("hands: left root %.1f mm, right root %.1f mm (index pads at %.1f / %.1f)"
		% [roots[0], roots[1], a, o])

	var mesh: ArrayMesh = load(REST_MESH)
	if mesh == null:
		push_error("нет rest-сетки %s — соберите render.sh --rebake" % REST_MESH)
		return
	_mat_skin = _skin_material(false)
	_mat_xray = _skin_material(true)
	# A negative determinant turns the triangles inside out; the mirrored hand
	# therefore renders both sides. The normals are still the mirror of the
	# left hand's, so the shading stays the same.
	_mat_skin_r = _skin_material(false)
	_mat_skin_r.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat_xray_r = _skin_material(true)
	_mat_xray_r.cull_mode = BaseMaterial3D.CULL_DISABLED

	var rest_model := HandModel.new(1.0, 0.0)
	var vis := HandRig.build_pair(mesh, rest_model, roots, _mat_skin, _mat_xray)
	for side in ["L", "R"]:
		var v: Dictionary = vis[side]
		add_child(v["root"])
		var rx := float(v["root_x"])
		var p := HomePose.build(side, rx)
		_hands[side] = {
			"vis": v, "pose": p, "disp": p.duplicate(true),
			"home": p.duplicate(true),
			"model": HandModel.new(1.0, 0.0, p),
			"active_ray": "II", "target": Vector3.ZERO, "error": 0.0,
			"shares": [0.0, 0.0, 0.0], "spread": 0.0, "energy": 0.0,
			"arm_shares": ArmModel.shares_of(p["arm"]),
			"levels": ArmModel.levels(p["arm"]), "chain_energy": 0.0,
		}


func _skin_material(xray: bool) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("#cb9077", 0.26 if xray else 1.0)
	mat.roughness = 0.78 if not xray else 0.9
	mat.metallic_specular = 0.14
	mat.rim_enabled = true
	mat.rim = 0.07
	mat.rim_tint = 0.6
	if xray:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


func _apply_hand(side: String) -> void:
	var st: Dictionary = _hands[side]
	st["model"] = HandModel.new(1.0, 0.0, st["disp"])
	var vis: Dictionary = st["vis"]
	var skin: StandardMaterial3D = _mat_skin
	var xray: StandardMaterial3D = _mat_xray
	if side == "R":
		skin = _mat_skin_r
		xray = _mat_xray_r
	HandRig.set_mode(vis, _mode, skin, xray)
	HandRig.apply(vis, st["model"])


func _apply_all() -> void:
	for side in ["L", "R"]:
		_apply_hand(side)


func _set_pose(side: String, p: Dictionary) -> void:
	var st: Dictionary = _hands[side]
	st["pose"] = p
	st["disp"] = p.duplicate(true)
	var ray := String(st["active_ray"])
	if ray == "I":
		st["shares"] = IK.thumb_shares_of(HandModel.thumb_of_pose(p))
		st["spread"] = 0.0
		var en := 0.0
		for v in st["shares"]:
			en += float(v) * float(v)
		st["energy"] = en
	else:
		st["shares"] = IK.shares_of(ray, p["fingers"][ray])
		st["spread"] = 0.0
		st["energy"] = 0.0
	st["arm_shares"] = ArmModel.shares_of(p.get("arm", {}))
	st["levels"] = ArmModel.levels(p.get("arm", {}))
	st["chain_energy"] = 0.0
	_apply_hand(side)
	_update_hud()


func _rest(side: String) -> void:
	_cancel_click()
	var st: Dictionary = _hands[side]
	var p: Dictionary = (st["home"] as Dictionary).duplicate(true)
	_set_pose(side, p)


func _pad_of_pose(side: String, ray: String, p: Dictionary) -> Vector3:
	var xf := ArmModel.hand_transform(p.get("arm", {}))
	if ray == "I":
		return xf * HandModel.thumb_pad(HandModel.thumb_fk(
			HandModel.thumb_of_pose(p)))
	return xf * HandModel.finger_pad(ray,
		HandModel.finger_fk(ray, p["fingers"][ray]))


# World point (mm) → the solver's hand-local space (the left model's space).
func _local_point(side: String, p: Vector3) -> Vector3:
	return _lp(side, float(_hands[side]["vis"]["root_x"]), p)


# The same, with the root given: the pure stroke takes it as an argument so it
# can be solved without reading the hand's live state.
func _lp(side: String, rx: float, p: Vector3) -> Vector3:
	if side == "R":
		return Vector3(-(p.x - rx), p.y, p.z)
	return Vector3(p.x - rx, p.y, p.z)


# The other hand as capsule segments in THIS hand's local frame: the solver's
# own obstacle (opts["foreign"]), the same one intersect_test.gd feeds it.
# Without it the click solves as if the other hand were not there, and the
# two thumbs meet in the middle of the board. The radii travel PER JOINT
# (ra/rb) because the thumb tapers: with the old max-of-two the resting
# thumbs read 0.92 mm of penetration and every non-space press tucked the
# resting thumb 13.58 mm off the bar; tapered, the real gap is 5.08 mm and
# the resting thumb does not move (measured in SS50h).
func _foreign_of(side: String) -> Array:
	var other := "R" if side == "L" else "L"
	return _foreign_pose(side, (_hands[other] as Dictionary)["disp"])


# The other hand AS IT RESTS. Every cached stroke is solved against this, and
# so is every press that is not a chord — that is what makes one key one
# answer (author, #9), and it is also what lets the warming thread compute a
# stroke without touching the live poses the main thread is animating.
func _foreign_rest(side: String) -> Array:
	return (_sim_rest_foreign[side] as Array).duplicate(true)


func _foreign_pose(side: String, p: Dictionary) -> Array:
	var other := "R" if side == "L" else "L"
	var xo := ArmModel.hand_transform(p.get("arm", {}))
	var rx := float(_hands[side]["vis"]["root_x"])
	var ro := float(_hands[other]["vis"]["root_x"])
	var out := []
	var it: PackedVector3Array = HandModel.thumb_fk(
		HandModel.thumb_of_pose(p))["pts"]
	for i in 3:
		out.append({"a": _loc(side, rx, _w(other, ro, xo * it[i])),
			"b": _loc(side, rx, _w(other, ro, xo * it[i + 1])),
			"r": maxf(float(THUMB_R[i]), float(THUMB_R[i + 1])),
			"ra": float(THUMB_R[i]), "rb": float(THUMB_R[i + 1])})
	for f in HandModel.FINGERS:
		var fp: PackedVector3Array = HandModel.finger_fk(
			f, p["fingers"][f])["pts"]
		for i in 3:
			out.append({"a": _loc(side, rx, _w(other, ro, xo * fp[i])),
				"b": _loc(side, rx, _w(other, ro, xo * fp[i + 1])),
				"r": maxf(float(HandModel.SKIN_R[f][i]),
					float(HandModel.SKIN_R[f][i + 1])),
				"ra": float(HandModel.SKIN_R[f][i]),
				"rb": float(HandModel.SKIN_R[f][i + 1])})
	return out


# World point → THIS hand's local frame. The right hand's frame is the left
# model's mirrored in x (the same rule as _local_point): forgetting the mirror
# puts the other hand's capsules at the wrong side of the root, and the guard
# silently measures a phantom.
func _loc(side: String, root_x: float, w: Vector3) -> Vector3:
	if side == "R":
		return Vector3(-(w.x - root_x), w.y, w.z)
	return Vector3(w.x - root_x, w.y, w.z)


func _w(side: String, root_x: float, q: Vector3) -> Vector3:
	if side == "R":
		return Vector3(root_x - q.x, q.y, q.z)
	return Vector3(root_x + q.x, q.y, q.z)


# The whole board in one hand's local space, for the click path's tip guard.
func _local_keys(side: String) -> Array:
	var out := []
	var rx := float(_hands[side]["vis"]["root_x"])
	for k in _keys:
		var r: Rect2 = k["r"]
		if side == "R":
			out.append(Rect2(rx - r.end.x, r.position.y, r.size.x,
				r.size.y))
		else:
			out.append(Rect2(r.position.x - rx, r.position.y, r.size.x,
				r.size.y))
	return out


# ---- the keyboard ------------------------------------------------------

func _make_keyboard() -> void:
	_board_root = Node3D.new()
	_board_root.name = "Board"
	_board_root.scale = Vector3.ONE * SCALE
	add_child(_board_root)

	# Concept mode: MBT_SPLIT moves the two halves apart, MBT_TENT tilts them
	# toward the centre, MBT_SPLAY fans them out in plan. Viewer-only — the
	# game's board (kbd3d.gd) is untouched: the pitches and the roots stay
	# where they are, the halves are just rigid groups of its own keys.
	var split := _env_f("MBT_SPLIT")
	var tent := _env_f("MBT_TENT")
	var splay := _env_f("MBT_SPLAY")
	var w := Kbd3D.board_w()
	var top := Kbd3D.row_y(0) + Kbd3D.ROW_H * 0.5
	var bottom := Kbd3D.row_y(4) - Kbd3D.ROW_H * 0.5
	if split > 0.0:
		for side in ["L", "R"]:
			var half := Node3D.new()
			half.name = "half_" + side
			half.position = Vector3((-1.0 if side == "L" else 1.0)
				* split * 0.5 * SCALE, 0.0, 0.0)
			add_child(half)
			var board := Node3D.new()
			board.name = "board"
			board.position = Vector3(-half.position.x, 0.0, 0.0)
			board.scale = Vector3.ONE * SCALE
			half.add_child(board)
			_halves[side] = half

	# The case under the keys. Its top is just below the keycaps, so the caps
	# look set into it; it is what makes the plane read as a keyboard.
	if split <= 0.0:
		var base := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(w + 8.0, top - bottom + 8.0, 4.0)
		base.mesh = bm
		var bmat := StandardMaterial3D.new()
		bmat.albedo_color = BOARD_COL
		bmat.roughness = 0.85
		base.material_override = bmat
		# The case top sits 1.2 mm BELOW the caps' undersides: a pressed cap sinks
		# by TRAVEL (2.6 mm) and must still show its face above the case. Flush
		# (the old -2.0) hid the whole cap in the solid slab and the press read as
		# a dark hole.
		base.position = Vector3(0.0, (top + bottom) * 0.5,
			KEY_Z - Kbd3D.THICK * 0.5 - 3.2)
		_board_root.add_child(base)

	var font := _load_font()
	for k in _keys:
		var r: Rect2 = k["r"]
		var c: Vector2 = r.get_center()
		var host: Node3D = _board_root
		if split > 0.0 and absf(c.x) > 2.0:
			host = (_halves["L" if c.x < 0.0 else "R"] as Node3D) \
				.get_node("board")
		var mi := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(r.size.x, r.size.y, Kbd3D.THICK)
		mi.mesh = box
		var mat := StandardMaterial3D.new()
		mat.albedo_color = KEY_IDLE
		mat.roughness = 0.72
		mi.material_override = mat
		mi.position = Vector3(r.get_center().x, r.get_center().y, KEY_Z)
		host.add_child(mi)
		_key_nodes.append(mi)
		_key_mats.append(mat)

		var s := String(k["s"])
		var text := Kbd3D.legend(s)
		# The headless renderer has no text server output for Label3D and
		# spams "Parameter m is null" once per label per frame; the legends
		# are a visual aid only, so they are skipped when there is no picture.
		if text != "" and DisplayServer.get_name() != "headless":
			var lab := Label3D.new()
			lab.text = text.to_upper() if s.length() == 1 else text
			lab.font = font
			lab.font_size = 40 if s.length() == 1 else 28
			lab.pixel_size = 0.12
			lab.modulate = Color("#242830")
			lab.outline_size = 0
			lab.no_depth_test = false
			lab.double_sided = false
			lab.position = Vector3(0.0, 0.0, Kbd3D.THICK * 0.5 + 0.6)
			mi.add_child(lab)
	_paint_keys()

	if split <= 0.0:
		return
	# The space bar and anything under the centre keep a flat bridge strip,
	# so the two tilted halves read as a split board, not as a hole.
	var m0 := Vector2(INF, INF)
	var m1 := Vector2(-INF, -INF)
	for k in _keys:
		var r2: Rect2 = k["r"]
		if absf(r2.get_center().x) <= 2.0:
			m0 = m0.min(r2.position)
			m1 = m1.max(r2.end)
	if m1.x > m0.x:
		var strip := MeshInstance3D.new()
		var sb := BoxMesh.new()
		sb.size = Vector3(m1.x - m0.x + 8.0, m1.y - m0.y + 8.0, 4.0)
		strip.mesh = sb
		var smat := StandardMaterial3D.new()
		smat.albedo_color = BOARD_COL
		smat.roughness = 0.85
		strip.material_override = smat
		strip.position = Vector3((m0.x + m1.x) * 0.5, (m0.y + m1.y) * 0.5,
			KEY_Z - Kbd3D.THICK * 0.5 - 3.2)
		_board_root.add_child(strip)
	_ride_split(tent, splay)


# The split halves carry the hands as rigid bodies: the pads stay on their
# keys because the hand is solved on the flat board and rides the same hinge.
# The forearms cross the rim of the half — acceptable on a concept still.
func _ride_split(tent: float, splay: float) -> void:
	var tr := deg_to_rad(tent)
	var sr := deg_to_rad(splay)
	_rot_half(_halves["L"], Vector3(0.0, -tr, sr))
	_rot_half(_halves["R"], Vector3(0.0, tr, -sr))


func _rot_half(half: Node3D, rot: Vector3) -> void:
	var side := "L" if String(half.name).ends_with("_L") else "R"
	var vroot: Node3D = _hands[side]["vis"]["root"]
	var xf: Transform3D = vroot.transform
	# add_child refuses while the node has another parent, and the failure is
	# silent in a still render: the hands stayed where the flat board put them
	# while only the key halves rotated.
	if vroot.get_parent() != null:
		vroot.get_parent().remove_child(vroot)
	half.add_child(vroot)
	# Preserve the hand's world placement, expressed in the half's frame.
	vroot.transform = half.transform.affine_inverse() * xf
	half.rotation = rot


func _load_font() -> Font:
	var f := FontFile.new()
	if f.load_dynamic_font(FONT_PATH) == OK:
		return f
	return null


func _paint_keys() -> void:
	for i in _key_mats.size():
		var c := KEY_IDLE
		if _sim:
			# The simulator's own bookkeeping, not the mouse: a struck cap
			# is down, a held-but-not-yet-struck one glows as a promise;
			# the mouse's hover says nothing about what the keys will do.
			if _sim_down.has(i):
				c = KEY_DOWN_COL
			elif _sim_held.has(i):
				c = KEY_HOVER_COL
		elif i == _down_key:
			c = KEY_DOWN_COL
		elif i == _hover_key:
			c = KEY_HOVER_COL
		_key_mats[i].albedo_color = c


func _key_at(mouse: Vector2) -> int:
	if _board_root == null:
		return -1
	var origin := _cam.project_ray_origin(mouse)
	var dir := _cam.project_ray_normal(mouse)
	var plane := Plane(Vector3(0.0, 0.0, 1.0), Kbd3D.FACE_Z * SCALE)
	var hit = plane.intersects_ray(origin, dir)
	if hit == null:
		return -1
	var p: Vector3 = (hit as Vector3) / SCALE
	return Kbd3D.key_at(_keys, Vector2(p.x, p.y), 1.0)


func _key_point(mouse: Vector2) -> Vector3:
	var origin := _cam.project_ray_origin(mouse)
	var dir := _cam.project_ray_normal(mouse)
	var plane := Plane(Vector3(0.0, 0.0, 1.0), Kbd3D.FACE_Z * SCALE)
	var hit = plane.intersects_ray(origin, dir)
	if hit == null:
		return Vector3.ZERO
	return (hit as Vector3) / SCALE


func _update_hover(mouse: Vector2) -> void:
	if _sim:
		return
	var k := _key_at(mouse)
	if k == _hover_key:
		return
	_hover_key = k
	_paint_keys()
	Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND if k >= 0
		else Input.CURSOR_ARROW)
	_update_hud()


# ---- a click -----------------------------------------------------------

# The press point on a key: the centre of a small key; a wide key (the space
# bar) takes the clicked point, inset by half a key, exactly the game's own
# `press_point` rule. This is a property of the KEY, not of a finger.
func _press_xy(k: Dictionary, hit: Vector3) -> Vector2:
	var r: Rect2 = k["r"]
	if r.size.x <= Kbd3D.KEY_W * 1.05 + 0.01 \
			and r.size.y <= Kbd3D.ROW_H * 1.05 + 0.01:
		return r.get_center()
	var ix := minf(Kbd3D.KEY_W * 0.5, r.size.x * 0.5)
	return Vector2(clampf(hit.x, r.position.x + ix, r.end.x - ix),
		r.get_center().y)


func _start_click(k: int, hit: Vector3) -> void:
	if _click_stage != "" or k < 0:
		return
	var key: Dictionary = _keys[k]
	var s := String(key["s"])
	var hf := Kbd3D.hand_finger(s, hit.x)
	var side := "L" if int(hf[0]) == 0 else "R"
	var ray := String(hf[1])
	if ray == "":
		return
	_focus = side
	_click_hand = side
	_click_ray = ray
	_click_key = k
	_click_stage = "click"
	_click_t = 0.0
	var st: Dictionary = _hands[side]
	st["active_ray"] = ray
	# The path STARTS where the hand is (a click during a flight must not
	# teleport) but ENDS at the canonical rest — a click that took the pose it
	# found as its destination parked the hand mid-air for good (author, #11
	# follow-up; see ClickPath.build's "return").
	_click_pose_rest = (st["disp"] as Dictionary).duplicate(true)
	_click_pose_end = (st["home"] as Dictionary).duplicate(true)
	_click_err_rest = float(st["error"])
	var xy := _press_xy(key, hit)
	_click_face = Vector3(xy.x, xy.y, Kbd3D.FACE_Z)
	var deep := _local_point(side,
		Vector3(xy.x, xy.y, Kbd3D.FACE_Z - Kbd3D.TRAVEL))
	_frozen = false
	_press_on = true
	_press_side = side
	_press_ray = ray
	_press_target = deep
	# No clear_rect: the idle fingers must stay above the key face over the
	# WHOLE plane, not only over a keycap (the author's rule, 31.10.2026).
	# The other hand is an obstacle and the hover height counts: the solver's
	# guard is the same one the intersection test measures (see _foreign_of).
	var hover := THUMB_HOVER if ray == "I" else KEY_HOVER
	# The press is solved FROM THE CANONICAL REST, never from the pose the
	# hand happens to show (the same rule the typed stroke follows, author
	# #5): one key must give one answer, and a click that lands mid-flight
	# must not land in another valley.
	var press: Dictionary = IK.solve_chain(ray, deep, _click_pose_end,
		_row_profile({"arm": true, "thumb_dof": 4, "clear_z": CLEAR_Z,
		"clear_w": 100.0, "dir_w": 30.0, "foreign": _foreign_of(side),
		"hover_z": Kbd3D.FACE_Z + hover}, s))
	_click_pose_press = press["pose"]
	_click_press_pad = _pad_of_pose(side, ray, _click_pose_press)
	_click_lift = maxf(0.0, (_click_face.z + hover) - _click_press_pad.z)
	_click_pose_hover = _click_pose_press.duplicate(true)
	_click_pose_hover["arm"]["elbow_z"] = float(
		_click_pose_hover["arm"].get("elbow_z", 0.0)) + _click_lift
	var rest_pad := _pad_of_pose(side, ray, _click_pose_rest)
	var approach := clampf(CLICK_APPROACH_MIN
		+ rest_pad.distance_to(deep) / 700.0,
		CLICK_APPROACH_MIN, CLICK_APPROACH_MAX)
	_click_path = ClickPath.build(_click_pose_rest, _click_pose_hover,
		_click_pose_press, approach, CLICK_PRESS, CLICK_RELEASE,
		CLICK_RETURN, {"ray": ray, "clear_z": CLEAR_Z,
		"key_rects": _local_keys(side), "own": k,
		"return": _click_pose_end})
	_set_pose(side, _click_pose_rest)


# A still press for the eye and for screenshots: solve the hovered key's
# press and hold it, no path. Space returns both hands to rest. The point is
# to see the POSE the solver chose, not a frame of the chase: the path ends at
# rest, so a screenshot taken after the click shows the hand back home.
func _freeze_press() -> void:
	if _hover_key < 0:
		return
	var k := _hover_key
	var key: Dictionary = _keys[k]
	var s := String(key["s"])
	var hf := Kbd3D.hand_finger(s, Kbd3D.centre(key).x)
	var side := "L" if int(hf[0]) == 0 else "R"
	var ray := String(hf[1])
	if ray == "":
		return
	_cancel_click()
	_focus = side
	_click_hand = side
	_click_ray = ray
	_click_key = k
	var st: Dictionary = _hands[side]
	st["active_ray"] = ray
	var xy := _press_xy(key, Kbd3D.centre(key))
	_click_face = Vector3(xy.x, xy.y, Kbd3D.FACE_Z)
	var deep := _local_point(side,
		Vector3(xy.x, xy.y, Kbd3D.FACE_Z - Kbd3D.TRAVEL))
	var press: Dictionary = IK.solve_chain(ray, deep, st["pose"],
		_row_profile({"arm": true, "thumb_dof": 4, "clear_z": CLEAR_Z,
		"clear_w": 100.0, "dir_w": 30.0, "foreign": _foreign_of(side),
		"hover_z": Kbd3D.FACE_Z + (THUMB_HOVER if ray == "I" else KEY_HOVER)},
		s))
	_click_pose_press = press["pose"]
	_press_on = true
	_press_side = side
	_press_ray = ray
	_press_target = deep
	_frozen = true
	_set_pose(side, _click_pose_press)
	_update_click_key()


func _cancel_click() -> void:
	if _click_stage == "" and not _frozen:
		return
	# A cancelled click (a right-click to orbit, a miss, a new click on
	# another key) must not leave the hand where the flight stopped: the
	# click owned the pose, so the rest pose is put back and the display
	# chases it home (author, #11 follow-up: the rest pose changed after a
	# right bottom key and stayed changed).
	if _click_hand != "" and _hands.has(_click_hand):
		var st: Dictionary = _hands[_click_hand]
		st["pose"] = (st["home"] as Dictionary).duplicate(true)
	_click_stage = ""
	_click_key = -1
	_click_t = 0.0
	_frozen = false
	_press_on = false
	if _down_key != -1:
		_down_key = -1
		_paint_keys()
	for mi in _key_nodes:
		mi.position.z = KEY_Z
	_update_hud()


func _advance_click(delta: float) -> void:
	if _click_stage == "":
		return
	_click_t += delta
	if _click_t >= float(_click_path["total"]):
		_set_pose(_click_hand, _click_pose_end)
		_key_nodes[_click_key].position.z = KEY_Z
		_click_stage = ""
		_click_key = -1
		_click_t = 0.0
		_down_key = -1
		_press_on = false
		_paint_keys()
		return
	_set_pose(_click_hand, ClickPath.at(_click_path, _click_t))


func _update_click_key() -> void:
	if _click_key < 0:
		return
	var st: Dictionary = _hands[_click_hand]
	var pad := _pad_of_pose(_click_hand, _click_ray, st["disp"])
	var u := clampf((Kbd3D.FACE_Z + SINK_LEAD - pad.z)
		/ (Kbd3D.TRAVEL + SINK_LEAD), 0.0, 1.0)
	_key_nodes[_click_key].position.z = KEY_Z - Kbd3D.TRAVEL * u
	var down := u > 0.0
	if down != (_down_key == _click_key):
		_down_key = _click_key if down else -1
		_paint_keys()


# ---- display chasing ---------------------------------------------------

func _pose_gap(a: Dictionary, b: Dictionary) -> float:
	var ta := HandModel.thumb_of_pose(a)
	var tb := HandModel.thumb_of_pose(b)
	var worst := 0.0
	for j in HandModel.THUMB_JOINTS:
		worst = maxf(worst, absf(float(ta[j]) - float(tb[j])))
	var fa: Dictionary = a.get("fingers", {})
	var fb: Dictionary = b.get("fingers", {})
	for ray in fa:
		for j in ["mcp", "pip", "dip", "fan"]:
			worst = maxf(worst, absf(float(fa[ray][j]) - float(fb[ray][j])))
	var aa: Dictionary = a.get("arm", {})
	var ab: Dictionary = b.get("arm", {})
	for j in ArmModel.ALL_JOINTS:
		worst = maxf(worst, absf(float(aa.get(j, 0.0))
			- float(ab.get(j, 0.0))))
	return worst


func _lerp_pose(a: Dictionary, b: Dictionary, t: float) -> Dictionary:
	var out := a.duplicate(true)
	for ray in out["fingers"]:
		for j in ["mcp", "pip", "dip", "fan"]:
			out["fingers"][ray][j] = lerpf(float(a["fingers"][ray][j]),
				float(b["fingers"][ray][j]), t)
	out["thumb_f"] = 0.0
	var ta := HandModel.thumb_of_pose(a)
	var tb := HandModel.thumb_of_pose(b)
	var th := {}
	for j in HandModel.THUMB_JOINTS:
		th[j] = lerpf(float(ta[j]), float(tb[j]), t)
	out["thumb"] = th
	out["thumb_dof"] = 4
	for j in ArmModel.ALL_JOINTS:
		out["arm"][j] = lerpf(float(a["arm"].get(j, 0.0)),
			float(b["arm"].get(j, 0.0)), t)
	return out


func _chase_rate(a: Dictionary, b: Dictionary) -> float:
	var sa := ArmModel.shares_of(a.get("arm", {}))
	var sb := ArmModel.shares_of(b.get("arm", {}))
	var elbow := maxf(absf(float(sa[5]) - float(sb[5])),
		maxf(absf(float(sa[6]) - float(sb[6])),
			absf(float(sa[7]) - float(sb[7])))) * 100.0
	if elbow > LEVEL_EPS:
		return SMOOTH_RATE_ELBOW
	var fore := maxf(absf(float(sa[3]) - float(sb[3])),
		absf(float(sa[4]) - float(sb[4]))) * 100.0
	if fore > LEVEL_EPS:
		return SMOOTH_RATE_FOREARM
	var wrist := maxf(absf(float(sa[0]) - float(sb[0])),
		maxf(absf(float(sa[1]) - float(sb[1])),
			absf(float(sa[2]) - float(sb[2])))) * 100.0
	if wrist > LEVEL_EPS:
		return SMOOTH_RATE_WRIST
	return SMOOTH_RATE


func _advance_display(side: String, delta: float) -> void:
	var st: Dictionary = _hands[side]
	if (st["disp"] as Dictionary).is_empty():
		st["disp"] = (st["pose"] as Dictionary).duplicate(true)
		_apply_hand(side)
		return
	var gap := _pose_gap(st["disp"], st["pose"])
	if gap <= SMOOTH_SNAP:
		return
	var rate := _chase_rate(st["disp"], st["pose"])
	var t := 1.0 - exp(-rate * delta)
	st["disp"] = _lerp_pose(st["disp"], st["pose"], t)
	if _pose_gap(st["disp"], st["pose"]) <= SMOOTH_SNAP:
		st["disp"] = (st["pose"] as Dictionary).duplicate(true)
	_apply_hand(side)


# ---- HUD ---------------------------------------------------------------

func _make_ui() -> void:
	var font := _load_font()
	var layer := CanvasLayer.new()
	add_child(layer)

	var panel := PanelContainer.new()
	panel.position = Vector2(18, 18)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1.0, 1.0, 1.0, 0.90)
	sb.corner_radius_top_left = 12
	sb.corner_radius_top_right = 12
	sb.corner_radius_bottom_left = 12
	sb.corner_radius_bottom_right = 12
	sb.content_margin_left = 16
	sb.content_margin_right = 20
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", sb)
	layer.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	panel.add_child(box)

	if _auto:
		# Comparable stills: label only, and translucent so the board shows
		# through at the top-left corner where the interactive HUD sits.
		_title = Label.new()
		_title.text = OS.get_environment("MBT_SHOT_LABEL")
		_title.add_theme_font_size_override("font_size", 26)
		_title.add_theme_color_override("font_color", Color("#17181b"))
		if font != null:
			_title.add_theme_font_override("font", font)
		box.add_child(_title)
		panel.add_theme_stylebox_override("panel", _translucent_box())
		layer.add_child(panel)
		var bar := PanelContainer.new()
		bar.visible = false
		layer.add_child(bar)
		return

	_title = Label.new()
	_title.text = "Клавиатура проекта · две кисти · рука и палец по клавише"
	if _auto:
		var lbl := OS.get_environment("MBT_SHOT_LABEL")
		if lbl != "":
			_title.text = lbl
	_title.add_theme_font_size_override("font_size", 21)
	_title.add_theme_color_override("font_color", Color("#17181b"))
	if font != null:
		_title.add_theme_font_override("font", font)
	box.add_child(_title)

	var nums := Label.new()
	nums.text = ("питч 19.05 мм · ряды цифр / Tab / Caps / Shift / низ · "
		+ "60 клавиш · клавиатура 284.75 × 108.8 мм\n"
		+ "левая кисть — модель, правая — её зеркало с тем же решателем")
	nums.add_theme_font_size_override("font_size", 14)
	nums.add_theme_color_override("font_color", Color("#3b3b40"))
	if font != null:
		nums.add_theme_font_override("font", font)
	box.add_child(nums)

	_state = Label.new()
	_state.add_theme_font_size_override("font_size", 15)
	_state.add_theme_color_override("font_color", Color("#1b4a86"))
	if font != null:
		_state.add_theme_font_override("font", font)
	box.add_child(_state)

	# The bottom hint bar is for the interactive viewer; the shot mode keeps
	# the whole frame for the picture itself.
	if not _auto:
		var bar := PanelContainer.new()
		bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		bar.offset_top = -108
		var bsb := StyleBoxFlat.new()
		bsb.bg_color = Color(1.0, 1.0, 1.0, 0.82)
		bsb.content_margin_left = 18
		bsb.content_margin_top = 8
		bsb.content_margin_bottom = 8
		bar.add_theme_stylebox_override("panel", bsb)
		layer.add_child(bar)

		_hint = Label.new()
		_hint.text = ("Клик по клавише — рука и палец выбираются по карте клавиатуры; "
			+ "нажатие идёт через IK до локтя\n"
			+ "Space — обе кисти в покой   ·   R — камера (вся доска / левая / правая)   ·   "
			+ "1 кожа · 2 кости · 3 просвет\n"
			+ "ЛКМ мимо клавиши — вращать   ·   колесо — масштаб   ·   Esc — выход")
		_hint.add_theme_font_size_override("font_size", 15)
		_hint.add_theme_color_override("font_color", Color("#33343a"))
		if font != null:
			_hint.add_theme_font_override("font", font)
		bar.add_child(_hint)


func _translucent_box() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1.0, 1.0, 1.0, 0.62)
	sb.content_margin_left = 14
	sb.content_margin_right = 16
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb


func _hover_text() -> String:
	if _hover_key < 0:
		return ""
	var k: Dictionary = _keys[_hover_key]
	var s := String(k["s"])
	var hf := Kbd3D.hand_finger(s, _key_point(get_viewport().get_mouse_position()).x)
	var hand := "левая" if int(hf[0]) == 0 else "правая"
	var finger := String(FINGER_NAME.get(String(hf[1]), String(hf[1])))
	return "под курсором «%s» → %s рука, %s" % [s, hand, finger]


func _update_hud() -> void:
	if _state == null:
		return
	var lines := []
	var hover := _hover_text()
	if hover != "":
		lines.append(hover)
	for side in ["L", "R"]:
		var st: Dictionary = _hands.get(side, {})
		if st.is_empty():
			continue
		var ray := String(st["active_ray"])
		if _sim:
			var bits := []
			for k in _sim_held:
				var rec: Dictionary = _sim_held[k]
				if String(rec["side"]) == side:
					bits.append("«%s»" % String(_keys[k]["s"]))
			if bits.is_empty():
				lines.append("%s кисть: в покое (%s)" % [
					SIDE_NAME[side], String(FINGER_NAME.get(ray, ray))])
			else:
				var pack := PackedStringArray()
				for b in bits:
					pack.append(String(b))
				lines.append("%s кисть: жмёт %s (%s)" % [
					SIDE_NAME[side], ", ".join(pack),
					String(FINGER_NAME.get(ray, ray))])
			continue
		var p: Dictionary = st["disp"]
		var key := ""
		if (_click_stage != "" or _frozen) and _click_hand == side:
			key = " · жмёт «%s»" % String(_keys[_click_key]["s"])
		var tail := ""
		if _press_on and _press_side == side:
			var d := _pad_of_pose(side, _press_ray, p).distance_to(_press_target)
			tail = " · остаток %.2f мм" % d
		lines.append("%s кисть: %s%s%s" % [
			SIDE_NAME[side], String(FINGER_NAME.get(ray, ray)), key, tail])
	_state.text = "\n".join(lines)


# ---- camera ------------------------------------------------------------

func _fit_camera() -> void:
	var h := get_viewport().get_visible_rect().size.y
	if h < 200.0:
		return
	var free := maxf(h - HUD_BOTTOM - HINT_TOP, 200.0)
	var preset := clampi(_cam_preset, 0, CAM_SPAN.size() - 1)
	var view_mm: float = float(CAM_SPAN[preset]) * h / (free * FIT_FILL)
	_dist = view_mm / (2.0 * tan(deg_to_rad(_cam.fov * 0.5)) * 1000.0)
	var mid := (HUD_BOTTOM + h - HINT_TOP) * 0.5
	var shift_mm := (mid - h * 0.5) * view_mm / h
	var cm: Vector2 = CAM_MID[preset]
	_center = Vector3(cm.x * SCALE, (cm.y + shift_mm) * SCALE, 0.0)
	_update_camera()


func _update_camera() -> void:
	var dir := Vector3(sin(_yaw) * cos(_pitch), sin(_pitch),
		cos(_yaw) * cos(_pitch))
	_cam.position = _center + dir * _dist
	_cam.look_at(_center, Vector3.UP)
	_rig_root.rotation.y = _yaw


# ---- input -------------------------------------------------------------

func _input(event: InputEvent) -> void:
	_idle_t = 0.0
	if _simdbg and event is InputEventKey:
		var ek := event as InputEventKey
		print("KEY ", ek.keycode, " press=", ek.pressed, " loc=", ek.location,
			" uni=", ek.unicode, " phys=", ek.physical_keycode)
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			var k := _key_at(mb.position)
			if k >= 0 and _sim:
				# A click presses the key through the SAME stroke the typed
				# one uses (cached, canonical base), so the hand looks the
				# same however the key was struck. Without this the far
				# bottom keys — Ctrl, Win, Alt, the globe: no physical
				# keycode reaches them — could not be pressed at all in the
				# simulator, which is the row #11 is about.
				_drag = ""
				_sim_click_press(k)
			elif k >= 0:
				_cancel_click()
				_start_click(k, _key_point(mb.position))
				_drag = ""
			else:
				_cancel_click()
				_drag = "orbit"
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			_cancel_click()
			_drag = "orbit"
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_dist = clampf(_dist * 0.92, 0.20, 3.0)
			_update_camera()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_dist = clampf(_dist / 0.92, 0.20, 3.0)
			_update_camera()
		elif not mb.pressed:
			if _sim and mb.button_index == MOUSE_BUTTON_LEFT:
				_sim_click_release()
			_drag = ""
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _drag == "orbit":
			_yaw -= mm.relative.x * 0.007
			_pitch = clampf(_pitch + mm.relative.y * 0.007, -1.45, 1.45)
			_update_camera()
	elif event is InputEventKey:
		_key(event as InputEventKey)


func _key(k: InputEventKey) -> void:
	if k.echo:
		return
	if _sim:
		_sim_key(k)
		get_viewport().set_input_as_handled()
		return
	if not k.pressed:
		return
	match k.keycode:
		KEY_SPACE:
			_cancel_click()
			_rest("L")
			_rest("R")
		KEY_R:
			_cam_preset = (_cam_preset + 1) % CAM_SPAN.size()
			_yaw = 0.18
			_pitch = 0.52
			_fit_camera()
		KEY_1:
			_mode = 0
			_apply_all()
		KEY_2:
			_mode = 1
			_apply_all()
		KEY_3:
			_mode = 2
			_apply_all()
		KEY_P:
			_freeze_press()
		KEY_ESCAPE:
			get_tree().quit()
			return
		_:
			return
	get_viewport().set_input_as_handled()


# ---- simulator ---------------------------------------------------------

# Opened after the UI is built: retargets the labels, keys up the EN→RU
# legend table (the author may type in the EN layout — the physical key is
# the same, only the typed character differs), and prints its own hello.
func _sim_open() -> void:
	_sim = true
	for ru in Kbd3D.RU_EN:
		var lat := String(Kbd3D.RU_EN[ru])
		if lat != ".":
			_sim_lat2ru[lat] = String(ru)
	# The board's "." key is the one the EN layout calls "/" (the game's own
	# legends), so EN "/" heads there; EN "." is left out of the table on
	# purpose: the bare "." character names the "." key directly.
	_sim_lat2ru["/"] = "."
	get_window().title = "СИМУЛЯТОР · печатайте на клавиатуре"
	if _title != null:
		_title.text = "СИМУЛЯТОР · реальная клавиша нажимает свой палец на доске"
	if _hint != null:
		_hint.text = ("Печатайте — рука и палец по карте клавиатуры; "
			+ "шифт держит мизинец, пробел — большой свободной руки\n"
			+ "ЛКМ по клавише — нажать её (Ctrl, Win, Alt, глобус — только так)   ·   "
			+ "F1 кожа · F2 кости · F3 просвет · F4 камера\n"
			+ "ЛКМ мимо клавиши — вращать   ·   колесо — масштаб   ·   Esc — выход")
	# The mouse's own states are meaningless here: no hover highlight (the
	# caps speak for the real keystrokes), and the pointing-hand cursor the
	# board uses for clicks is back to the plain arrow.
	_hover_key = -1
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	_paint_keys()
	print("СИМУЛЯТОР: печатайте или жмите клавишу мышью — рука и палец по карте доски; F1-F4 вид/кожа; Esc — выход")
	_update_hud()
	# The resting poses are frozen ONCE, here: every cached stroke is solved
	# against them, so they must not be read from the poses the main thread
	# animates (see _foreign_rest and _sim_warm_step).
	for side in ["L", "R"]:
		_sim_rest_home[side] = (_hands[side]["home"] as Dictionary).duplicate(true)
		_sim_rest_rx[side] = float(_hands[side]["vis"]["root_x"])
	for side in ["L", "R"]:
		_sim_rest_foreign[side] = _foreign_pose(side,
			_sim_rest_home["R" if side == "L" else "L"])
	_sim_build_warm_queue()


# The warming order: the letters first (that is what gets typed), nearest keys
# before far ones (a stroke that lands under a keystroke must be short), then
# digits and modifiers, the space bar last.
func _sim_build_warm_queue() -> void:
	var letters := []
	var rest := []
	var space := -1
	for i in _keys.size():
		var s := String((_keys[i] as Dictionary)["s"])
		if s == "пробел":
			space = i
			continue
		var side := _sim_key_side(i)
		if side == "":
			continue
		var job := [side, i, _sim_glide(side, i)]
		if Kbd3D.RU_EN.has(s):
			letters.append(job)
		else:
			rest.append(job)
	letters.sort_custom(_sim_warm_before)
	rest.sort_custom(_sim_warm_before)
	_sim_warm_queue = letters + rest
	# The bar belongs to the hand OPPOSITE the last letter, so both hands'
	# strokes are warmed.
	if space >= 0:
		_sim_warm_queue.append(["L", space, 0.0])
		_sim_warm_queue.append(["R", space, 0.0])


func _sim_warm_before(a: Array, b: Array) -> bool:
	return float(a[2]) < float(b[2])


# How far the finger has to travel from its resting pad to the key, the same
# measure _sim_stroke uses for the hover height. Only FK, no solve: it orders
# the warming queue.
func _sim_glide(side: String, k: int) -> float:
	var key: Dictionary = _keys[k]
	var s := String(key["s"])
	if s == "пробел":
		return 0.0
	var c := Kbd3D.centre(key)
	var ray := String(Kbd3D.hand_finger(s, c.x)[1])
	if ray == "":
		return 1e9
	var lp := _lp(side, float(_sim_rest_rx[side]), Vector3(c.x, c.y, 0.0))
	var cur := _pad_of_pose(side, ray, _sim_rest_home[side])
	return Vector2(lp.x - cur.x, lp.y - cur.y).length()


# Which hand strikes a key, by the same map _sim_press uses. "" = the sim has
# no finger for it.
func _sim_key_side(k: int) -> String:
	var kd: Dictionary = _keys[k]
	var s := String(kd["s"])
	if s == "пробел":
		return ""
	var hf: Array = Kbd3D.hand_finger(s, Kbd3D.centre(kd).x)
	if String(hf[1]) == "":
		return ""
	return "L" if int(hf[0]) == 0 else "R"


# One key per idle frame (see _sim_warm_queue). The caller has already checked
# that nothing is being animated, so the half second a stroke costs is spent in
# a window the author is not watching.
func _sim_warm_step() -> void:
	var job: Array = _sim_warm_queue[_sim_warm_i]
	_sim_warm_i += 1
	var side := String(job[0])
	var k := int(job[1])
	var ck := "%s:%d" % [side, k]
	if _sim_pose_cache.has(ck):
		return
	_sim_pose_cache[ck] = _sim_stroke(side, k,
		(_sim_rest_home[side] as Dictionary).duplicate(true),
		float(_sim_rest_rx[side]), _foreign_rest(side))


func _key_name_exists(s: String) -> bool:
	for k in _keys:
		if String(k["s"]) == s:
			return true
	return false


# Whether a held record is a shift: the typed uppercase/shifted characters
# check this own bookkeeping, not Input's global state, so the answer is
# exactly as true as the pinkies the sim already pressed.
func _sim_shift_down() -> bool:
	for k in _sim_held:
		var s := String(_keys[k]["s"])
		if s == "Shift" or s == "ShiftR":
			return true
	return false


# The board key name of a key event. Service keys by keycode and location;
# letters and digits by the typed character; the physical QWERTY table when
# no character arrives. The real Shift presses its own key separately — the
# sim never invents a modifier.
func _sim_symbol(ev: InputEventKey) -> String:
	match ev.keycode:
		KEY_SHIFT:
			return "ShiftR" if ev.location == KEY_LOCATION_RIGHT else "Shift"
		KEY_TAB: return "Tab"
		KEY_CAPSLOCK: return "Caps"
		KEY_BACKSPACE: return "←"
		KEY_ENTER, KEY_KP_ENTER: return "↵"
		KEY_SPACE: return "пробел"
		KEY_1: return "1"
		KEY_2: return "2"
		KEY_3: return "3"
		KEY_4: return "4"
		KEY_5: return "5"
		KEY_6: return "6"
		KEY_7: return "7"
		KEY_8: return "8"
		KEY_9: return "9"
		KEY_0: return "0"
		KEY_MINUS: return "-"
		KEY_EQUAL: return "="
	if ev.unicode != 0:
		var ch := String.chr(ev.unicode)
		var low := ch.to_lower()
		if low != ch:
			# A capital is the letter key itself; the physical shift already
			# pressed its own pinky. EN capitals ride their letter traces.
			return String(_sim_lat2ru.get(low, low))
		if _sim_shift_down() and SIM_SHIFT_CHAR.has(ch):
			var base := String(SIM_SHIFT_CHAR[ch])
			if ch == "?" and ev.keycode == KEY_SLASH:
				base = "."
			elif ch == ":" and ev.keycode == KEY_SEMICOLON:
				base = "ж"
			elif ch == "\"" and ev.keycode == KEY_APOSTROPHE:
				base = "э"
			return base
		if _sim_lat2ru.has(ch):
			return String(_sim_lat2ru[ch])
		if _key_name_exists(ch):
			return ch
	return String(SIM_QWERTY.get(ev.keycode, ""))


# The index of a board key by name. Duplicate bottom-row keys (the two Ctrl,
# Win, Alt) are told apart by the hand their physical half belongs to; the
# space bar is one record whose stored hand is always RIGHT, so it falls
# back to the name.
func _find_key(s: String, side: String) -> int:
	for i in _keys.size():
		var k: Dictionary = _keys[i]
		var hs := "L" if int(k["hand"]) == 0 else "R"
		if String(k["s"]) == s and hs == side:
			return i
	if s == "пробел":
		for i in _keys.size():
			if String(_keys[i]["s"]) == s:
				return i
	return -1


func _sim_key(ev: InputEventKey) -> void:
	if not ev.pressed:
		var id := "%d:%d" % [ev.keycode, ev.location]
		if _sim_ev.has(id):
			var kk := int(_sim_ev[id])
			_sim_ev.erase(id)
			if _sim_queued(kk):
				# The stroke has not started yet: remember the tap, it plays
				# in full when the queue reaches it (a real tap must never be
				# swallowed by the queue).
				_sim_tapped[kk] = true
			else:
				_sim_release(kk)
		return
	match ev.keycode:
		KEY_ESCAPE:
			get_tree().quit()
			return
		KEY_F1:
			_mode = 0
			_apply_all()
			return
		KEY_F2:
			_mode = 1
			_apply_all()
			return
		KEY_F3:
			_mode = 2
			_apply_all()
			return
		KEY_F4:
			_cam_preset = (_cam_preset + 1) % CAM_SPAN.size()
			_yaw = 0.18
			_pitch = 0.52
			_fit_camera()
			return
	var s := _sim_symbol(ev)
	if s == "":
		return
	var side := "L"
	if s == "пробел":
		side = "L" if _sim_letter_side != "L" else "R"
	else:
		# The key name carries its own hand: the FINGER_MAP [side, finger]
		# pair (LEFT/RIGHT as compiled on the board) picks the arm; a name
		# without a map entry falls through to name search on both sides
		# (ShiftR lives only in the right hand).
		var hf: Array = Kbd3D.hand_finger(s, 0.0)
		if int(hf[0]) == Kbd3D.RIGHT:
			side = "R"
		elif int(hf[0]) == Kbd3D.LEFT:
			side = "L"
		elif s.ends_with("ShiftR"):
			side = "R"
		if _find_key(s, side) < 0:
			var other := "R" if side == "L" else "L"
			if _find_key(s, other) >= 0:
				side = other
	var k := _find_key(s, side)
	if _simdbg:
		print("SIM ", s, " side=", side, " idx=", k)
	if k < 0:
		return
	_sim_ev["%d:%d" % [ev.keycode, ev.location]] = k
	_sim_enqueue(k, side)


# A press waits its turn (see _sim_queue): the event handler never solves.
func _sim_enqueue(k: int, side: String) -> void:
	if k < 0 or _sim_held.has(k) or _sim_queued(k):
		return
	_sim_queue.append([k, side])


func _sim_queued(k: int) -> bool:
	for q in _sim_queue:
		if int(q[0]) == k:
			return true
	return false


# One queued press per frame, before the poses advance, so the stroke it starts
# gets this frame's delta. A tap released while it was queued plays in full.
func _sim_tick_press() -> void:
	if _sim_queue.is_empty():
		return
	var q: Array = _sim_queue.pop_front()
	var k := int(q[0])
	var tap := bool(_sim_tapped.erase(k))
	if _sim_held.has(k):
		return
	_sim_press(k, String(q[1]))
	if tap:
		_sim_release(k)


# One typed press. The pose is solved in TWO steps — hover, then the press —
# and both are IK answers for the same finger, not one pose slid up and down:
#   * hover: the pad KEY_HOVER above its key, the arm free. It is the shallow
#     target's own answer, so the hand has already travelled toward the key
#     and the finger has already extended when the descent starts.
#   * press: the pad at the key's bottom, solved FROM the hover pose.
# The stroke is then one path through [now, hover, press] (PCHIP, C1): the
# arrival at the hover still carries speed, so the press begins there, and the
# release is the same three keyframes backwards — the withdrawal begins the
# moment the bottom is reached (author, 02.11.2026).
# The base of the solve is the CANONICAL HOME, never the pose the hand happens
# to show: chaining from the previous press made the same key land in a
# different valley every time and the hand contort on repeats (author, #5).
# Sliding one pose's elbow up and down was the old stroke — it moved the whole
# hand to the far key FIRST and pressed straight down afterwards, which is
# exactly what the author rejected (#1).
# THE PURE HALF OF A PRESS (author, #9): the two poses a stroke passes
# through, from a given base pose. Every input is an argument — the key, the
# base pose, the hand's root x, the other hand's capsules — so it reads no
# scene state and the warming pass can solve it without touching the poses the
# main thread is animating (see _sim_warm_step). _sim_press is the stateful
# half: it picks the base, the hand and the timing, and turns the answer into
# a path.

# THE BOTTOM ROW'S OWN PRICE LIST (#11 follow-up) — stated in ONE place so a
# typed key and a mouse click on the same key show the same hand. The gate is
# the ROW, not the input device: the author asked about the far bottom keys,
# and every other key must stay bit for bit the pose he approved.
func _row_profile(o: Dictionary, s: String) -> Dictionary:
	if (Kbd3D.ROW_BOTTOM as Array).has(s):
		# The wrist's sideways stop, then the hierarchy: the whole hand and
		# forearm move (a cheap elbow translation and forearm swing), the
		# finger is no longer nearly free. See ArmModel.WEIGHT_OVERRIDE.
		o["dev_stop"] = true
		o["weights"] = _sim_bot_w
		o["prior"] = _sim_bot_prior
	return o


func _sim_stroke(side: String, k: int, base: Dictionary, rx: float,
		foreign: Array) -> Dictionary:
	var key: Dictionary = _keys[k]
	var s := String(key["s"])
	var xy := Vector2.ZERO
	var ray := "I"
	if s != "пробел":
		var c := Kbd3D.centre(key)
		xy = Vector2(c.x, c.y)
		ray = String(Kbd3D.hand_finger(s, xy.x)[1])
	else:
		# The part of the bar under the thumb AT REST, kept inside the cap:
		# the hand must not travel to the middle of the space just to reach a
		# chosen point of it (author, 03.11.2026, #6: "при нажатии на пробел
		# почему-то шевелится вся рука, а не только большой палец, хотя он
		# уже лежит на пробеле"). The pad of the base pose is where the thumb
		# already is, and the press is a straight 2.6 mm descent from it. The
		# old clamp also forced each thumb into ITS OWN HALF of the bar — with
		# the twin's rest 6.06 mm past the centre (home_pose.gd) that alone
		# threw the target 12 mm sideways and moved the arm.
		#
		# The BASE, not the displayed pose (author, #9): one key must give one
		# answer, or the press cache could not exist — a space struck between
		# two other keys would land somewhere else every time.
		var pad := _pad_of_pose(side, "I", base)
		var w := _w(side, rx, pad)
		var r: Rect2 = key["r"]
		var m := 3.0
		xy = Vector2(clampf(w.x, r.position.x + m, r.end.x - m),
			clampf(w.y, r.position.y + m, r.end.y - m))
	# THE HOVER IS THE LAST POINT OF THE TRAVEL, NOT A LIFT-OFF. Its height
	# grows with the horizontal distance and never rises above where the pad
	# already is: a key the finger already sits over is pressed straight down
	# from the resting height (no silly 9 mm curtsy), while a far key is
	# reached by travelling high enough to clear the caps — and the descent
	# from that point IS the press, which is the diagonal the author asked for
	# (02.11.2026, #1).
	var cur_pad := _pad_of_pose(side, ray, base)
	var lp := _lp(side, rx, Vector3(xy.x, xy.y, 0.0))
	var glide := Vector2(lp.x - cur_pad.x, lp.y - cur_pad.y).length()
	var rise := clampf(glide / SIM_HOVER_DIV, 0.0, 1.0)
	var hz := maxf(cur_pad.z, Kbd3D.FACE_Z
		+ (THUMB_HOVER if ray == "I" else KEY_HOVER) * rise)
	var hover_t := Vector3(lp.x, lp.y, hz)
	var deep := _lp(side, rx, Vector3(xy.x, xy.y, Kbd3D.FACE_Z - Kbd3D.TRAVEL))
	var opts := _row_profile({"arm": true, "thumb_dof": 4,
		"clear_z": Kbd3D.FACE_Z, "clear_w": 100.0, "pair_w": 100.0,
		"dir_w": 0.0, "foreign": foreign, "hover_z": hz}, s)
	# #11: on the bottom row the wrist may not roll further sideways than the
	# approved pose by more than a few degrees — the rest of that reach is the
	# whole hand's. Every other row keeps the approved split (the author's
	# "в остальном вроде бы хорошо").
	var hov: Dictionary
	var pose: Dictionary
	if glide < SIM_HOVER_MIN:
		# The finger already sits over its key: there is no travel to make,
		# so the hover IS the canonical pose. Solving it again only lets the
		# solver wander into another valley (the home "о" moved the elbow
		# 19 mm for a 1.5 mm glide) — the hand would swing on a key it is
		# already touching.
		hov = base.duplicate(true)
	else:
		hov = (IK.solve_chain(ray, hover_t, base, opts)["pose"]
			as Dictionary).duplicate(true)
		var hpad := _pad_of_pose(side, ray, hov)
		hov["arm"]["elbow_z"] = float(hov["arm"].get("elbow_z", 0.0)) \
			+ (hover_t.z - hpad.z)
	# THE PRESS IS THE FINGER'S; THE HAND ONLY SETTLES UNDER IT (02.11.2026,
	# #1 and #5). The hand has already travelled — from here the descent
	# must cost the finger alone. Solved with the arm free, a home key the
	# finger cannot quite cover was answered by rolling the wrist four
	# degrees, which dipped the idle fingers 13 mm through the board; the
	# clearance guard then lifted the palm 31 mm to save them, and the hand
	# bounced on a key it was already touching. Instead the hand SETTLES by
	# exactly the depth the finger cannot cover — downwards only, never up
	# — and the idle fingers tuck above the face as the solve goes. The
	# settle is also the diagonal the author asked for: the last of the
	# travel already descends, and the release begins at the bottom.
	var press_opts: Dictionary = opts.duplicate(true)
	press_opts["arm"] = false
	var settled: Dictionary = hov.duplicate(true)
	pose = hov.duplicate(true)
	for i in 4:
		var r: Dictionary = IK.solve_chain(ray, deep, settled, press_opts)
		pose = (r["pose"] as Dictionary).duplicate(true)
		var d := deep.z - _pad_of_pose(side, ray, pose).z
		if absf(d) < SIM_SETTLE_EPS:
			break
		settled = pose.duplicate(true)
		settled["arm"]["elbow_z"] = float(settled["arm"]["elbow_z"]) + d
	# The solver may stop a fraction of a millimetre short of the bottom;
	# the elbow carries the pad the rest of the way, so a held key shows
	# FULLY down and the hit is never a crawl. The nudge lowers the WHOLE
	# hand, though, and with it the idle pads the solve has just tucked
	# clear of the caps — so the finger is re-solved once at the new
	# height, which spends the nudge on the finger instead of on its
	# neighbours (02.11.2026: the leftover 0.4–0.9 mm end-guard lift).
	var pad2 := _pad_of_pose(side, ray, pose)
	if absf(deep.z - pad2.z) > 0.02:
		pose["arm"]["elbow_z"] = float(pose["arm"].get("elbow_z", 0.0)) \
			+ (deep.z - pad2.z)
		pose = (IK.solve_chain(ray, deep, pose, press_opts)["pose"]
			as Dictionary).duplicate(true)
		pad2 = _pad_of_pose(side, ray, pose)
	if _simdbg:
		print("PRESS ", s, " side=", side, " ray=", ray,
			" cur_pad ", str(cur_pad), " glide ", str(glide),
			" hover_t ", str(hover_t),
			" hov_elbow ", str(hov["arm"]["elbow_z"]),
			" deep ", str(deep), " pad2 ", str(pad2),
			" elbow ", str(pose["arm"]["elbow_z"]),
			" settle ", str(float(pose["arm"]["elbow_z"])
				- float(hov["arm"]["elbow_z"])))
	pose["arm"]["elbow_z"] = float(pose["arm"].get("elbow_z", 0.0)) \
		+ (deep.z - pad2.z)
	return {"hover": hov, "press": pose, "glide": glide, "hz": hz,
		"hover_t": hover_t, "deep": deep}


# The stroke of one key, solved ONCE (author, #9: "если нажимать несколько
# клавиш быстро подряд, то симулятор зависает"). With the base fixed at the
# canonical home and the other hand at rest, the whole stroke — hover,
# settle, nudge — is a function of (hand, key) alone, so it is solved once
# and REPLAYED. A press used to cost 0.5–3.4 s of solving, and every key
# typed behind it queued up on the main thread: the window froze. A chord is
# not pure (its base and its neighbour are live poses), so it bypasses the
# cache in both directions.
#
# The warming pass fills this on idle frames (_sim_warm_step), so a press that
# finds its key warmed never solves at all.
func _sim_stroke_cached(side: String, k: int, base: Dictionary, chord: bool,
		rx: float) -> Dictionary:
	var ck := "%s:%d" % [side, k]
	var foreign := _foreign_of(side) if chord else _foreign_rest(side)
	var out: Dictionary = {}
	if not chord:
		out = _sim_pose_cache.get(ck, {})
	if out.is_empty():
		out = _sim_stroke(side, k, base, rx, foreign)
		if not chord:
			_sim_pose_cache[ck] = out
	return out


func _sim_press(k: int, side: String) -> void:
	if k < 0 or _sim_held.has(k):
		return
	var key: Dictionary = _keys[k]
	var s := String(key["s"])
	var ray := "I"
	if s != "пробел":
		var c := Kbd3D.centre(key)
		ray = String(Kbd3D.hand_finger(s, c.x)[1])
		side = "L" if int(Kbd3D.hand_finger(s, c.x)[0]) == 0 else "R"
	if ray == "":
		return
	var st: Dictionary = _hands[side]
	var rx := float(st["vis"]["root_x"])
	if Kbd3D.RU_EN.has(s):
		_sim_letter_side = side
	# THE BASE OF A STROKE IS THE CANONICAL HOME, never the pose the hand
	# happens to show: chaining from the previous press made the same key land
	# in a different valley every time and the hand contort on repeats
	# (author, #5). A CHORD is the exception (02.11.2026): when this hand
	# already holds another key, its palm has settled under that key, and
	# starting the second stroke from the canonical home would lift the hand —
	# and with it the held cap — by the settle it just paid. The second stroke
	# starts where the hand IS.
	var base: Dictionary = (st["home"] as Dictionary).duplicate(true)
	var chord := false
	for other in _sim_held:
		var rec: Dictionary = _sim_held[other]
		if String(rec["side"]) == side and String(rec["ray"]) != ray:
			base = (st["disp"] as Dictionary).duplicate(true)
			chord = true
			break
	var stroke := _sim_stroke_cached(side, k, base, chord, rx)
	var hov: Dictionary = (stroke["hover"] as Dictionary).duplicate(true)
	var pose: Dictionary = (stroke["press"] as Dictionary).duplicate(true)
	var glide := float(stroke["glide"])
	var hz := float(stroke["hz"])
	var hover_t: Vector3 = stroke["hover_t"]
	var deep: Vector3 = stroke["deep"]
	# Any finger this hand is already holding stays on its own cap.
	for other in _sim_held:
		var rec: Dictionary = _sim_held[other]
		if String(rec["side"]) != side or int(other) == k:
			continue
		if String(rec["ray"]) == ray:
			# One finger cannot hold two keys at once (shift + «ф» are both
			# the left pinky): the stroke wins, and the held cap rides the
			# same pad instead of dragging the finger off its own target.
			continue
		var tgt: Vector3 = rec["deep"]
		hov = _sim_land_ray(side, hov, String(rec["ray"]), tgt)
		pose = _sim_land_ray(side, pose, String(rec["ray"]), tgt)
	st["active_ray"] = ray
	var a := clampf(SIM_APPROACH_MIN + glide / SIM_APPROACH_DIV,
		SIM_APPROACH_MIN, SIM_APPROACH_MAX)
	var strike := _sim_strike_t(hz - deep.z)
	var path := _sim_path(
		[(st["disp"] as Dictionary).duplicate(true), hov, pose],
		[0.0, a, a + strike], side, ray, k)
	_sim_anim[side] = {"kind": "press", "t": 0.0, "path": path, "end": pose}
	# The hover and the press are kept PER KEY: the release walks back through
	# exactly this stroke's own keyframes, even when the same hand struck
	# another key in between.
	_sim_held[k] = {"side": side, "ray": ray, "deep": deep,
		"hover": hov, "hover_t": hover_t, "hover_z": hz, "press": pose}
	_sim_down.erase(k)
	_sim_up.erase(k)
	_paint_keys()
	_update_hud()


# Re-solve ONE finger chain with the arm frozen: the held cap must be back
# under its fingertip after a newer press carried the arm away.
func _sim_land_ray(side: String, pose: Dictionary, ray: String,
		target: Vector3) -> Dictionary:
	var solved: Dictionary = IK.solve_chain(ray, target, pose, {
		"arm": false, "thumb_dof": 4, "clear_z": CLEAR_Z, "clear_w": 100.0,
		"pair_w": 100.0, "dir_w": 30.0})["pose"]
	var out: Dictionary = pose.duplicate(true)
	if ray == "I":
		out["thumb"] = (solved["thumb"] as Dictionary).duplicate(true)
	else:
		out["fingers"][ray] = (solved["fingers"][ray] as Dictionary).duplicate(true)
	return out


# One keyup: the same three keyframes backwards — [press, hover, home]. The
# withdrawal therefore BEGINS at the bottom instead of a straight lift of one
# frozen pose: the finger leaves the cap on its way to the hover the stroke
# already knows, and only then does the arm glide home (author, 02.11.2026).
# An early keyup — a fast typist releasing while the finger is still gliding —
# must not swallow the hit (the contact is the whole point of the simulator):
# the unfinished press is compressed, straight down to the stored bottom,
# then the same hover and home.
func _sim_release(k: int) -> void:
	if not _sim_held.has(k):
		return
	var rec: Dictionary = _sim_held[k]
	_sim_held.erase(k)
	var side := String(rec["side"])
	var ray := String(rec["ray"])
	var st: Dictionary = _hands[side]
	var still := false
	for other in _sim_held:
		var o: Dictionary = _sim_held[other]
		if String(o["side"]) == side:
			still = true
			break
	var cur: Dictionary = (st["disp"] as Dictionary).duplicate(true)
	var cur_pad := _pad_of_pose(side, ray, cur)
	var home: Dictionary = (st["home"] as Dictionary).duplicate(true)
	var hov: Dictionary = (rec["hover"] as Dictionary).duplicate(true)
	var press: Dictionary = (rec["press"] as Dictionary).duplicate(true)
	var strike := _sim_strike_t(float(rec["hover_z"])
		- (rec["deep"] as Vector3).z)
	var kind := "return"
	var keys: Array
	var times: Array
	var end: Dictionary
	var finishing := not _sim_down.has(k) \
		and String(_sim_anim[side].get("kind", "")) == "press"
	if finishing:
		kind = "finish"
		var home_pad := _pad_of_pose(side, ray, home)
		var glide := Vector2(cur_pad.x - home_pad.x,
			cur_pad.y - home_pad.y).length()
		var q := clampf(SIM_RETURN_MIN + glide / SIM_APPROACH_DIV,
			SIM_RETURN_MIN, SIM_RETURN_MAX)
		var t1 := strike + SIM_UPLIFT
		keys = [cur, press, hov, home]
		times = [0.0, strike, t1, t1 + q]
		end = home
	elif still:
		# A sibling key still owns the arm: only the released finger
		# lifts — back over its own key at hover height, the arm stays
		# where the held keys hold it.
		var hold: Dictionary = (st["pose"] as Dictionary).duplicate(true)
		var parked: Dictionary = _sim_land_ray(side, hold, ray,
			rec["hover_t"])
		keys = [cur, parked]
		times = [0.0, strike]
		end = parked
	else:
		var home_pad := _pad_of_pose(side, ray, home)
		var glide := Vector2(cur_pad.x - home_pad.x,
			cur_pad.y - home_pad.y).length()
		var q := clampf(SIM_RETURN_MIN + glide / SIM_APPROACH_DIV,
			SIM_RETURN_MIN, SIM_RETURN_MAX)
		keys = [cur, hov, home]
		times = [0.0, strike, strike + q]
		end = home
	var path := _sim_path(keys, times, side, ray, k)
	_sim_anim[side] = {"kind": kind, "t": 0.0, "path": path, "end": end}
	_sim_up[k] = {"side": side, "ray": ray, "t": 0.0}
	_paint_keys()
	_update_hud()


# A mouse click on the board in the simulator presses the key through the
# SAME queue and stroke the typed path uses, so the hand looks identical
# however the key was struck, and a click never solves inside the event
# handler. Ctrl, Win, Alt and the globe have no physical keycode, so before
# this the row #11 is about could not be pressed in the simulator at all.
func _sim_click_press(k: int) -> void:
	if k < 0:
		return
	_sim_click_release()
	var side := _sim_key_side(k)
	if side == "":
		# The space bar is ONE record whose stored hand is always RIGHT; the
		# game's own rule gives it to the free hand (the side the last letter
		# was typed with is taken).
		side = "L" if _sim_letter_side != "L" else "R"
	_sim_click_key = k
	_sim_enqueue(k, side)


# The button came up. A press still waiting in the queue is remembered as a
# tap and plays in full when its turn comes (a real tap must never be
# swallowed by the queue); a press already running is released normally.
func _sim_click_release() -> void:
	var k := _sim_click_key
	_sim_click_key = -1
	if k < 0:
		return
	if _sim_queued(k):
		_sim_tapped[k] = true
	else:
		_sim_release(k)


# ---- stroke mechanics --------------------------------------------------

# The rays whose keys this hand is still holding. Their chains own their caps
# and are exempt from the stroke's plane guard (see _sim_plane_lift).
func _sim_held_rays(side: String) -> Dictionary:
	var out := {}
	for other in _sim_held:
		var rec: Dictionary = _sim_held[other]
		if String(rec["side"]) == side:
			out[String(rec["ray"])] = true
	return out


# How long the strike (and the lift-off that mirrors it) takes: a short dip
# onto a key already under the pad, a touch longer for a far key reached from
# a high hover. Never a crawl, never a slam.
func _sim_strike_t(descent: float) -> float:
	return clampf(SIM_STRIKE + descent / SIM_STRIKE_DIV,
		SIM_STRIKE, SIM_STRIKE_MAX)


# A stroke's pose path in the sampler's dict shape, built directly (build()
# would weld the five click keyframes in). "ray" is left EMPTY on purpose:
# ClickPath.at then skips its own guards, and the stroke applies its OWN
# held-aware ones per sample (click clearance exempts only the stroking tip;
# a still-held chain sits below the face on purpose and would answer with a
# several-millimetre lift that floats the whole stroke).
func _sim_path(keys: Array, times: Array, side: String, ray: String,
		own: int) -> Dictionary:
	return {"keys": keys, "times": times,
		"total": float(times[times.size() - 1]),
		"ray": "", "clear_z": -1e9, "clear_rect": Rect2(), "key": -1,
		"sray": ray, "own": own, "key_rects": _local_keys(side)}


# One sample of a stroke: the pose at t with the two guards applied — the
# held-aware keyboard-plane measure, and the stroking tip's own walk against
# OTHER caps (skipped once the tip has entered its own key's column: the
# descent there is a vertical fall in the safe column, and what the prism
# still reports is the shoulder of its own cap, not a crossing).
func _sim_sample(path: Dictionary, t: float, side: String,
		arc := true) -> Dictionary:
	var pose: Dictionary = ClickPath.at(path, t)
	var ray := String(path.get("sray", ""))
	if ray == "":
		return pose
	var key_rects: Array = path.get("key_rects", [])
	var lift := 0.0
	if arc:
		# The descending press is the only flight that needs the caps guard:
		# the release paths' keyframes are solved poses (hold, parked hover,
		# home) and their home already carries the resting dips the guard
		# would re-lift, popping the last frame.
		lift = _sim_plane_lift(ray, pose, side, key_rects)
		if not key_rects.is_empty() and not _sim_tip_home(path, pose, ray):
			lift = maxf(lift, _sim_tip_lift(ray, pose, key_rects,
				int(path.get("own", -1))))
	if lift > 0.0:
		pose["arm"]["elbow_z"] = float(pose["arm"].get("elbow_z", 0.0)) + lift
	return pose


# The middle of the key walk the click's sampler uses outside the target
# column: a straight interpolation between clean keyframes can dip an idle
# tip through a cap it passes over (measured IV k6 crossing k25), and the
# lift is exactly the worst violation.
func _sim_tip_home(path: Dictionary, pose: Dictionary, ray: String) -> bool:
	var own := int(path.get("own", -1))
	if own < 0:
		return false
	var rect: Rect2 = (path["key_rects"] as Array)[own]
	var xf := ArmModel.hand_transform(pose.get("arm", {}))
	var tip: Vector3
	if ray == "I":
		var pts: PackedVector3Array = HandModel.thumb_fk(
			HandModel.thumb_of_pose(pose))["pts"]
		tip = xf * pts[3]
	else:
		var pts: PackedVector3Array = HandModel.finger_fk(ray,
			pose["fingers"][ray])["pts"]
		tip = xf * pts[3]
	return rect.has_point(Vector2(tip.x, tip.y))


# The stroking tip against every OTHER cap, the same prism measure the click
# path's `_tip_lift_keys` applies (its own key is exempt: the pad IS the
# bottom of that sphere, so the tip can only be below the face once the key
# is sinking with it).
func _sim_tip_lift(ray: String, p: Dictionary, key_rects: Array,
		own: int) -> float:
	var xf := ArmModel.hand_transform(p.get("arm", {}))
	var tip: Vector3
	var r: float
	if ray == "I":
		var pts: PackedVector3Array = HandModel.thumb_fk(
			HandModel.thumb_of_pose(p))["pts"]
		tip = xf * pts[3]
		r = HandModel.THUMB_TIP_R
	else:
		var pts: PackedVector3Array = HandModel.finger_fk(ray,
			p["fingers"][ray])["pts"]
		tip = xf * pts[3]
		r = float(HandModel.SKIN_R[ray][3])
	var worst := 0.0
	for i in key_rects.size():
		if i == own:
			continue
		worst = maxf(worst, _sim_prism(tip, r, key_rects[i], CLEAR_Z))
	return worst


# One ball against one keycap prism (footprint x/y, cap-top plane at zc) — the
# same SDF the click path's `_key_violation_rect` measures.
func _sim_prism(p: Vector3, r: float, rect: Rect2, zc: float) -> float:
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


# The whole-plane measure, held-aware, and SCOPED TO THE CAPS: every ball of
# the idle chains and the thumb, against every key's prism (footprint x/y,
# cap-top plane). NOT the solver's sanctity halfspace (CLEAR_Z, 3 mm above
# the faces): the resting home itself dips below that invisible line (the
# SS50h pads sit at z -68.70 against CLEAR_Z -66, 2.7 mm under), so a
# per-sample guard on
# it floats every stroke — the pad stalls just past the face and the last
# 2.4 mm land in a single frame. Dips the home pose already owns — behind
# the board, between keys — are not over any cap and count zero here; only
# a genuine dive onto someone's cap lifts. Two exemptions, as before: a held
# chain (its cap is already sunk with it), and the stroking chain's own body
# (its proximal joints ride over the pressed key's own footprint, hidden
# under the sinking cap; the tip's prism guard still covers the neighbour
# sweep, and the solver clears the pose the path lands on).
#
# NO SKIN MARGIN HERE (02.11.2026). The click path's 2 mm margin is a safety
# band for a hand travelling in the air; the home rests the idle pads
# ON their own caps, so the margin lifted EVERY press sample by 2 mm — and
# the held pose, which is not sampled, then snapped down by that much on the
# last frame. The guard is exact: a ball may touch a cap top, not cross it.
#
# The one tolerance kept is the soft tissue's own give — the same IDLE_SINK
# the solver's clearance allows (half a millimetre). Without it the guard was
# stricter than the solve it guards and re-lifted every pose by the solver's
# own residual: the last frame dropped by 0.4–0.9 mm after a smooth descent.
func _sim_plane_lift(ray: String, p: Dictionary, side: String,
		rects: Array) -> float:
	var held := _sim_held_rays(side)
	var xf := ArmModel.hand_transform(p.get("arm", {}))
	var give := IK.IDLE_SINK
	var worst := 0.0
	for other in ["II", "III", "IV", "V"]:
		if other == ray or (held.has(other) and other != ray):
			continue
		var pts: PackedVector3Array = HandModel.finger_fk(other,
			p["fingers"][other])["pts"]
		var radii: Array = HandModel.SKIN_R[other]
		for j in 4:
			var w: Vector3 = xf * pts[j]
			for i in rects.size():
				worst = maxf(worst, _sim_prism(w,
					float(radii[j]) - give, rects[i], Kbd3D.FACE_Z))
	if ray != "I":
		var tpts: PackedVector3Array = HandModel.thumb_fk(
			HandModel.thumb_of_pose(p))["pts"]
		var tradii := [11.8, 10.8, 9.6, 6.6]
		for j in 4:
			var tw: Vector3 = xf * tpts[j]
			for i in rects.size():
				worst = maxf(worst, _sim_prism(tw,
					float(tradii[j]) - give, rects[i], Kbd3D.FACE_Z))
	return worst


# The cap's sunk share from a pad depth: it starts sinking SINK_LEAD above
# the face and reaches the bottom exactly when the pad is TRAVEL down.
func _sink_u(z: float) -> float:
	return clampf((Kbd3D.FACE_Z + SINK_LEAD - z)
		/ (Kbd3D.TRAVEL + SINK_LEAD), 0.0, 1.0)


# The caps follow the DISPLAY pad every frame. A held key's cap sinks as the
# fingertip descends and stays down while its key is held; a released key's
# cap rides the finger back up (the rider list) until the sink lead ends and
# only then pops back. A cap is colored down when the pad actually touches
# the face — the visible contact the eye must catch — not at the slightly
# earlier depth where the sinking itself has already begun.
func _update_hold_keys(delta: float = 0.0) -> void:
	var landed := []
	for k in _sim_up:
		var rec: Dictionary = _sim_up[k]
		rec["t"] = float(rec.get("t", 0.0)) + delta
		var side := String(rec["side"])
		var pad := _pad_of_pose(side, String(rec["ray"]),
			_hands[side]["disp"])
		var u := _sink_u(pad.z)
		if u > 0.0 and float(rec["t"]) <= SIM_RIDER_LIFE:
			_key_nodes[k].position.z = KEY_Z - Kbd3D.TRAVEL * u
		else:
			_key_nodes[k].position.z = KEY_Z
			landed.append(k)
	for k in landed:
		_sim_up.erase(k)
		if _sim_down.has(k):
			_sim_down.erase(k)
			_paint_keys()
	for k in _sim_held:
		var rec: Dictionary = _sim_held[k]
		var side := String(rec["side"])
		var pad := _pad_of_pose(side, String(rec["ray"]),
			_hands[side]["disp"])
		_key_nodes[k].position.z = KEY_Z - Kbd3D.TRAVEL * _sink_u(pad.z)
		if pad.z <= Kbd3D.FACE_Z:
			if not _sim_down.has(k):
				_sim_down[k] = true
				_paint_keys()
		elif _sim_down.has(k):
			# a dip without a touchdown (the finger bounced off its cap):
			# the mark goes out while the pad is over the face again
			_sim_down.erase(k)
			_paint_keys()


# The display follows the stroke sample-for-sample: the exponential chase is
# what made the contacts crawl, so while an anim runs, the pose and the shown
# pose are the SAME sample. The hold state (when the path ends) is the solved
# press itself, not the last sample: there the key is FULLY down and nothing
# guards against its own cap.
func _advance_sim(delta: float) -> void:
	for side in ["L", "R"]:
		var anim: Dictionary = _sim_anim[side]
		if anim.is_empty():
			_advance_display(side, delta)
			continue
		var path: Dictionary = anim["path"]
		var total := float(path["total"])
		var t := float(anim["t"]) + delta
		if total - t <= 1e-6:
			_sim_anim[side] = {}
			_set_pose(side, anim["end"])
			continue
		anim["t"] = minf(t, total)
		_set_pose(side, _sim_sample(path, float(anim["t"]), side,
			String(anim.get("kind", "")) == "press"))


# ---- frame loop --------------------------------------------------------

func _process(delta: float) -> void:
	if _auto:
		return
	_idle_t += delta
	if _drag != "" and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) \
			and not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		_drag = ""
	if not _focused:
		Engine.max_fps = FPS_UNFOCUSED
		_set_render_loop(false)
	else:
		var busy: bool = _drag != "" or _click_stage != "" \
				or (_sim and (not _sim_held.is_empty()
					or not _sim_up.is_empty()
					or not _sim_queue.is_empty()
					or not _sim_anim["L"].is_empty()
					or not _sim_anim["R"].is_empty()))
		var idle: bool = not busy and _idle_t >= IDLE_AFTER
		var want := FPS_IDLE if idle else FPS_ACTIVE
		if Engine.max_fps != want:
			Engine.max_fps = want
		_set_render_loop(not idle)
	if _drag == "" and not _sim:
		_update_hover(get_viewport().get_mouse_position())
	if _click_stage != "":
		_advance_click(delta)
	if _sim:
		_sim_tick_press()
		_advance_sim(delta)
		_update_hold_keys(delta)
		if not _sim_held.is_empty() or not _sim_up.is_empty():
			_update_hud()
		# One stroke per idle frame (author, #9): by the time a key is struck its
		# answer is usually already in the cache, so fast typing never queues a
		# solve behind the keystroke. The render loop is off in this window, so
		# the half second a stroke costs is spent where nothing is being drawn.
		if _focused and _idle_t >= IDLE_AFTER and _click_stage == "" \
				and _sim_held.is_empty() and _sim_up.is_empty() \
				and _sim_queue.is_empty() \
				and _sim_anim["L"].is_empty() and _sim_anim["R"].is_empty() \
				and _sim_warm_i < _sim_warm_queue.size():
			_sim_warm_step()
	else:
		for side in ["L", "R"]:
			_advance_display(side, delta)
		_update_click_key()


func _set_render_loop(on: bool) -> void:
	if on == _render_on:
		return
	_render_on = on
	RenderingServer.render_loop_enabled = on


func _notification(what: int) -> void:
	if _auto:
		return
	match what:
		NOTIFICATION_WM_WINDOW_FOCUS_OUT:
			_focused = false
			_drag = ""
			Engine.max_fps = FPS_UNFOCUSED
			_set_render_loop(false)
		NOTIFICATION_WM_WINDOW_FOCUS_IN:
			_focused = true
			_idle_t = 0.0
			Engine.max_fps = FPS_ACTIVE
			_set_render_loop(true)
		NOTIFICATION_WM_SIZE_CHANGED:
			if _focused:
				_idle_t = 0.0
				_set_render_loop(true)
		NOTIFICATION_WM_CLOSE_REQUEST:
			get_tree().quit()


# ---- shot mode ---------------------------------------------------------
# MBT_SHOT="name,yaw°,pitch°,span_mm,cx,cy,cz;..." renders every spec from
# exactly those camera numbers and saves PNGs to MBT_SHOT_DIR, then quits.
# No drags, no wheel, no mouse: the same numbers frame every variant, so a
# card of candidates compares like with like.

func _env_f(name: String, d := 0.0) -> float:
	var s := OS.get_environment(name)
	return d if s == "" else float(s)


func _auto_shoot(plan: String) -> void:
	var dir := OS.get_environment("MBT_SHOT_DIR")
	print("auto_shoot: plan=[", plan, "] dir=[", dir, "]")
	if dir == "":
		push_error("MBT_SHOT без MBT_SHOT_DIR — некуда класть кадры")
		get_tree().quit()
		return
	for spec in plan.split(";", false):
		var p: PackedStringArray = String(spec).split(",")
		_yaw = deg_to_rad(float(p[1]))
		_pitch = deg_to_rad(float(p[2]))
		var span: float = float(p[3])
		_dist = span / (2.0 * tan(deg_to_rad(_cam.fov * 0.5)) * 1000.0)
		_center = Vector3(float(p[4]), float(p[5]), float(p[6])) * SCALE
		_update_camera()
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		if img == null:
			push_error("кадр пуст: " + spec)
			continue
		var path := dir.path_join(String(p[0]) + ".png")
		img.save_png(path)
		print("shot: %s %dx%d" % [path, img.get_width(), img.get_height()])
	get_tree().quit()
