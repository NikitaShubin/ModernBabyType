# Live viewer for the hand study: one skinned hand on a visible arm, driven by
# inverse kinematics.
#
# Not part of the game. Drag the blue target ball with the left button; the
# selected finger follows through IK and the skin deforms on the GPU. Shift
# while dragging moves the target along the view direction (depth). Orbit with
# the left button off the ball or with the right button, zoom with the wheel.
# Tab switches the finger, Space returns to rest, D runs the hierarchy demo,
# F freezes/unfreezes the arm, 1 2 3 switch skin / bones / x-ray, R cycles the
# camera framing, K shows a key grid.
#
# The model itself is hand_model.gd, the arm is arm_model.gd, the solver is
# ik.gd, the deformable hand skin is skin_rig.gd over the baked rest mesh, and
# the arm's visible geometry is arm_view.gd. Nothing here contains anatomy of
# its own — it is a window onto those modules.
extends Node3D

const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")
const ArmView := preload("res://arm_view.gd")
const BoneView := preload("res://bone_view.gd")
const SkinRig := preload("res://skin_rig.gd")
const IK := preload("res://ik.gd")
const ClickPath := preload("res://click_path.gd")
const WristOpen := preload("res://wrist_open.gd")

const SCALE := 0.001                     # mm → m
const REST_MESH := "res://cache/skin_curled_rest.res"
const FONT_PATH := "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"

const CYCLE := ["II", "III", "IV", "V", "I"]
const FINGER_NAME := {"I": "большой", "II": "указательный", "III": "средний",
	"IV": "безымянный", "V": "мизинец"}

const TARGET_R := 3.4                    # mm, the drag ball
const PICK_PX := 30.0
const CLAMP_MIN := Vector3(-300, -340, -300)
const CLAMP_MAX := Vector3(300, 340, 200)

# The key grid. It is a study aid: a click on a key sends the selected finger
# to it through the same IK target as a drag, so the whole chain (finger, fan,
# wrist, pronation, forearm, elbow) takes part in the reach and in the press.
# The grid lies in the palmar plane, 70 mm in front of the palm; the keys are
# 17 mm squares on a 20 mm pitch, five rows of ten.
const KEY_COLS := 10
const KEY_ROWS := 5
const KEY_PITCH := 20.0
const KEY_SIZE := 17.0
const KEY_X0 := -90.0
const KEY_Y0 := 80.0
const KEY_Z := -70.0
const KEY_FACE := KEY_Z + 1.0            # camera-side face of a 2 mm key
const KEY_TRAVEL := 2.6                  # how deep the key sinks
const KEY_HOVER := 12.0                  # the fingertip waits this far in front
# The thumb's hover is shorter on purpose: the author's rule (30.10.2026) is
# that the hand must not sink when the thumb presses, and the only hover the
# thumb's kinematics can build in this geometry is a rigid hand translation.
# Five millimetres is the smallest approach that still reads as a hover, and it
# cuts the hand's vertical travel by more than half.
const THUMB_HOVER := 5.0
# The keys as a slab in x/y: 10 x 5 keys, centres x -90..90 and y 80..160, each
# 17 mm wide, so the footprint is 197 x 97 mm centred on (0, 120). The clearance
# rule uses it instead of an infinite wall, because a finger below the bottom row
# may legitimately hang behind the face.
const KEY_RECT := Rect2(Vector2(0.0, 120.0), Vector2(98.5, 48.5))
const KEY_IDLE := Color("#2b3440")       # alpha is set per state below
const KEY_HOVER_COL := Color("#2f6fd0")
const KEY_DOWN_COL := Color("#3f86e8")
# A click is a scripted pose path, not a sequence of solver targets. The pose
# that PRESSES the key is solved once with the whole arm free, and the HOVER is
# that same pose pulled straight back along the key normal by a rigid elbow
# translation: every joint, every finger and the whole forearm keep their
# angles, so the hand's shape does not change between hover and press and only
# its distance to the keyboard does. This is what the author asked for: nothing
# but the target finger may cross the key face, and the skin must not deform
# during the press ("кожа руки опять неестественно деформируется, хотя сами
# углы скручивания скелета корректны"). The four fingers and the thumb both
# need the arm to back off — their own flexion arc runs ALONG the keyboard
# (measured: the thumb's pad moves 3 mm in z against 15 mm sideways, the
# index's 13 mm against 50 mm up), so a hover made by moving the finger alone
# would either stay in the key or slide across a neighbour. Solving the press
# with the arm free also keeps the thumb out of full extension: at f = -1 the
# thenar skin folds (1.8 mm edges), at f = -0.35 the worst edge is 0.58 mm
# (smooth_cmp.gd).
const THUMB_PRESS_LO := -0.35   # cap on the thumb's extension while pressing
const CLICK_APPROACH_MIN := 0.22
const CLICK_APPROACH_MAX := 0.50
const CLICK_PRESS := 0.16
const CLICK_RELEASE := 0.12
const CLICK_RETURN := 0.40
# The key starts to sink this far in front of its face. The pad is soft and
# the keycap has some give; starting exactly at the face made the 2.6 mm of
# travel happen in two frames.
const CLICK_SINK_LEAD := 3.0

# Framing. The whole study is the hand (205 mm, generously) plus the visible
# forearm (150 mm to the elbow stump). Three presets: whole arm (355 mm),
# hand + forearm (305 mm), hand alone (205 mm). The middle one is the default:
# most of the forearm is visible and the fingers are still large enough to
# read.
const HAND_MM := 205.0
const BODY_MM := HAND_MM + ArmModel.FOREARM_L
const HAND_ARM_MM := 305.0
const BODY_MID_X := 20.0
const HUD_BOTTOM := 250.0
const HINT_TOP := 122.0
const FIT_FILL := 0.90                   # of the free height
# The fingertip of the middle finger is at y = 189 mm (baseline v1). The
# camera frames the ACTUAL body extent, not the hand preset's 205 mm span:
# the extra 16 mm is margin, and the presets centre the window on the
# fingertip so the hand does not drift under the hint bar.
const FINGERTIP_MM := 189.0
# The hierarchy sometimes hands a target from one basin to the next in a
# single solve (the wrist reaches its limit and the forearm root or pronation
# takes over). The solver is right to do it — it is the physical handoff — but
# on screen it would read as a snap. The displayed pose chases the solved one
# at these rates, so the handoff is shown as a short movement instead.
#
# The rate follows the author's rule (29.10.2026): the larger the part of the
# arm that takes part, the more expensive and the SLOWER the movement. A
# finger answers at once; the elbow, which carries the whole arm, is a
# deliberate, heavy move.
const SMOOTH_RATE := 22.0                # 1/s, finger and fan
const SMOOTH_RATE_WRIST := 14.0          # wrist, deviation, pronation
const SMOOTH_RATE_FOREARM := 8.0         # forearm root
const SMOOTH_RATE_ELBOW := 4.0           # elbow travel
const LEVEL_EPS := 0.5                   # percent of a share; below it, still
const SMOOTH_SNAP := 0.05                # degrees; below this the poses are one
# The container renders with llvmpipe: 60 fps of a 1000×1200 window costs most
# of the machine. The viewer is interactive, not a benchmark, so it runs at
# full rate while the mouse or keys are busy and stops redrawing once nothing
# has happened for a moment. The demo and the spin keep full rate.
const FPS_ACTIVE := 60
const FPS_IDLE := 10
const FPS_UNFOCUSED := 5
const IDLE_AFTER := 1.2                  # s

var _yaw := 0.62
var _pitch := 0.10
var _dist := 0.62
var _center := Vector3(0.0, 0.0, 0.0)
var _cam_preset := 1
var _mode := 0
var _spin := false
var _drag := ""                          # "", "orbit", "target"

var _pose: Dictionary
var _disp: Dictionary                    # shown pose, chases _pose
var _model: Object
var _active_ray := "II"
var _target := Vector3.ZERO
var _error := 0.0
var _shares := []
var _spread := 0.0
var _energy := 0.0
var _thumb_f := 0.0
var _arm_shares := []
var _levels := {}
var _chain_energy := 0.0
var _free_arm := true
var _demo := false
var _demo_t := 0.0
var _demo_waypoints := []
# A static wrist pose for judging the seam: the IK cannot reach 70° of flexion
# on its own, and the seam is the one thing the author asked to look at. The
# mode is a straight override of the shown pose, dropped by any drag.
var _wrist_test := -1
const WRIST_TESTS := [0.0, 35.0, 55.0, 70.0, -60.0]
var _idle_t := 0.0
var _focused := true
var _render_on := true

var _rig: Dictionary
var _live: Dictionary
var _arm_view: Dictionary
var _grid: Node3D
var _grid_keys: Array[MeshInstance3D] = []
var _grid_mats: Array[StandardMaterial3D] = []
var _grid_hover := -1
var _grid_down := -1
var _click_stage := ""                   # "", "click"
var _click_t := 0.0
var _click_key := -1
var _click_approach_t := CLICK_APPROACH_MIN
# The click's poses and their times: rest, hover, press, hover, rest. The path
# is one PCHIP through them, so the hover is a waypoint the hand passes through
# at speed, not a stop; the press begins before the hover is reached and the
# release begins as the press bottoms out.
var _click_pose_rest := {}
var _click_pose_hover := {}
var _click_pose_press := {}
var _click_path := {}
var _click_face := Vector3.ZERO          # key face centre, mm
var _click_press_pad := Vector3.ZERO     # where the pad ends, mm
var _click_lift := 0.0                   # rigid pull-back of the hover, mm
var _click_err_rest := 0.0
var _click_rest := Vector3.ZERO
var _cam: Camera3D
var _rig_root: Node3D
var _target_node: MeshInstance3D
var _pad_node: MeshInstance3D
var _line: MeshInstance3D
var _line_mesh: ImmediateMesh
var _mat_skin: StandardMaterial3D
var _mat_xray: StandardMaterial3D
var _mat_bones: StandardMaterial3D
var _title: Label
var _state: Label
var _hint: Label


func _ready() -> void:
	Engine.max_fps = FPS_ACTIVE
	get_window().title = "Кисть 189 мм — IK палец → кисть → предплечье → локоть (Escape — выход)"
	_make_env()
	_make_lights()
	_make_camera()
	_make_hand()
	_make_grid()
	_make_markers()
	_make_ui()
	_pose = HandModel.rest_pose()
	_disp = _pose.duplicate(true)
	_model = HandModel.new(1.0, 0.0, _pose)
	_shares = [0.0, 0.0, 0.0]
	_arm_shares = ArmModel.shares_of(_pose["arm"])
	_levels = ArmModel.levels(_pose["arm"])
	_target = _pad_now()
	_solve()
	_fit_camera()
	get_viewport().size_changed.connect(_fit_camera)


func _make_env() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#dfe3e6")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#ffffff")
	env.ambient_light_energy = 0.05
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.tonemap_exposure = 0.72
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


func _make_lights() -> void:
	# The rig turns with the camera, so the key light is always above-left of
	# the viewer and the hand never turns into a silhouette.
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
	_cam.far = 4.0
	add_child(_cam)
	_cam.current = true


func _make_hand() -> void:
	var rest := HandModel.new(1.0, 0.0)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("#cb9077")
	mat.roughness = 0.78
	mat.metallic_specular = 0.14
	mat.rim_enabled = true
	mat.rim = 0.07
	mat.rim_tint = 0.6
	_mat_skin = mat

	var xray := StandardMaterial3D.new()
	xray.albedo_color = Color("#cb9077", 0.26)
	xray.roughness = 0.9
	xray.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	xray.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat_xray = xray

	_mat_bones = StandardMaterial3D.new()
	_mat_bones.albedo_color = Color("#f1e7d2")

	if not ResourceLoader.exists(REST_MESH):
		push_error("нет rest-сетки %s — соберите render.sh --rebake" % REST_MESH)
		return
	var mesh: ArrayMesh = load(REST_MESH)
	_rig = SkinRig.build(rest, WristOpen.open_wrist(mesh, rest), REST_MESH,
		WristOpen.WRIST_FLAT_H)
	add_child(_rig["skeleton"])
	add_child(_rig["instance"])
	SkinRig.wire(_rig)
	(_rig["instance"] as MeshInstance3D).scale = Vector3.ONE * SCALE
	(_rig["instance"] as MeshInstance3D).material_override = _mat_skin

	_live = BoneView.build_live(rest)
	add_child(_live["root"])

	# The forearm is lofted from the hand's own cut contour, so there is no
	# capsule stuck onto the wrist and no cap to hide a hollow stump.
	_arm_view = ArmView.build(mesh, rest)
	add_child(_arm_view["root"])
	ArmView.wire(_arm_view)
	ArmView.set_skin_material(_arm_view, _mat_skin)


# A faint key grid at the palmar plane, so a target can be put on a key
# instead of in mid-air. Off by default; K toggles it. Every key owns its
# material, because hover and press are shown by colour and by depth.
func _make_grid() -> void:
	_grid = Node3D.new()
	# The grid is the target of the whole click demo, so it is on from the
	# start: the author asked for a clickable keyboard, not for a keyboard he
	# has to discover behind a key. K still hides it.
	_grid.visible = true
	var box := BoxMesh.new()
	box.size = Vector3(KEY_SIZE, KEY_SIZE, 2.0) * SCALE
	for iy in KEY_ROWS:
		for ix in KEY_COLS:
			var mi := MeshInstance3D.new()
			mi.mesh = box
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(KEY_IDLE, 0.20)
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			mi.material_override = mat
			mi.position = _grid_key_pos(iy * KEY_COLS + ix)
			_grid.add_child(mi)
			_grid_keys.append(mi)
			_grid_mats.append(mat)
	add_child(_grid)


# The centre of a key in millimetres, in the viewer's world frame.
func _grid_key_pos(k: int) -> Vector3:
	var ix := k % KEY_COLS
	var iy := k / KEY_COLS
	return Vector3(KEY_X0 + float(ix) * KEY_PITCH,
		KEY_Y0 + float(iy) * KEY_PITCH, KEY_Z) * SCALE


# The key under the mouse, or -1. The hit area is the pitch, not the 17 mm
# face: the 3 mm gaps are not something a person aims at.
func _grid_key_at(mouse: Vector2) -> int:
	if _grid == null or not _grid.visible:
		return -1
	var origin := _cam.project_ray_origin(mouse)
	var dir := _cam.project_ray_normal(mouse)
	var plane := Plane(Vector3(0.0, 0.0, 1.0), KEY_Z * SCALE)
	var hit = plane.intersects_ray(origin, dir)
	if hit == null:
		return -1
	var p: Vector3 = (hit as Vector3) / SCALE
	var fx := (p.x - KEY_X0) / KEY_PITCH
	var fy := (p.y - KEY_Y0) / KEY_PITCH
	var ix := int(round(fx))
	var iy := int(round(fy))
	if ix < 0 or ix >= KEY_COLS or iy < 0 or iy >= KEY_ROWS:
		return -1
	if absf(fx - float(ix)) > 0.5 or absf(fy - float(iy)) > 0.5:
		return -1
	return iy * KEY_COLS + ix


# Repaint every key from the three states. Called only when a state changes,
# not per frame.
func _paint_grid() -> void:
	for i in _grid_mats.size():
		var c := KEY_IDLE
		var a := 0.20
		if i == _grid_down:
			c = KEY_DOWN_COL
			a = 0.92
		elif i == _grid_hover:
			c = KEY_HOVER_COL
			a = 0.55
		_grid_mats[i].albedo_color = Color(c, a)


func _update_grid_hover(mouse: Vector2) -> void:
	var k := _grid_key_at(mouse)
	if k == _grid_hover:
		return
	_grid_hover = k
	_paint_grid()
	Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND if k >= 0
		else Input.CURSOR_ARROW)


func _clear_grid_hover() -> void:
	if _grid_hover == -1:
		return
	_grid_hover = -1
	_paint_grid()
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)


# Begin a press of key k with the selected finger. The press pose is solved
# once, with the whole arm free and with the keyboard clearance and the press
# direction on. The hover is that same pose pulled straight back along the key
# normal by a rigid elbow translation, so every joint keeps its angle: the
# hand's shape and orientation do not change, the skin stays rigid, and only
# the distance to the keyboard changes. The path through rest → hover → press →
# hover → rest is one C1 spline, so the hover is a waypoint the hand passes at
# speed, not a stop.
func _start_click(k: int) -> void:
	if _click_stage != "":
		return
	_demo = false
	_wrist_test = -1
	_click_key = k
	_click_stage = "click"
	_click_t = 0.0
	# The rest pose is what is ON SCREEN, not the last solved pose: a click
	# may start while the display is still chasing, and returning to the
	# solved pose would jump.
	_click_pose_rest = _disp.duplicate(true)
	_click_err_rest = _error
	_click_rest = _pad_of_pose(_active_ray, _click_pose_rest)
	var c := _grid_key_pos(k) / SCALE
	_click_face = Vector3(c.x, c.y, KEY_FACE)
	var deep := Vector3(c.x, c.y, KEY_FACE - KEY_TRAVEL)
	var flo := THUMB_PRESS_LO if _active_ray == "I" else -1.0
	# The click is its own animation: the study toggle that freezes the arm for
	# the target ball must not cripple it. Clearance keeps every idle joint
	# 3 mm in front of the key face; the direction term makes the target
	# finger meet its key along the normal instead of lying across it.
	var press: Dictionary = IK.solve_chain(_active_ray, deep, _pose,
		{"arm": true, "f_lo": flo, "clear_z": KEY_FACE + 3.0,
		"clear_w": 100.0, "dir_w": 30.0, "clear_rect": KEY_RECT})
	_click_pose_press = press["pose"]
	_click_press_pad = _pad_of_pose(_active_ray, _click_pose_press)
	# The hover is the press pose pulled straight back along +z. elbow_z is a
	# world-space translation of the wrist, so the pad moves by exactly the
	# same amount and the hover pad lands the hover distance in front of the
	# face. The thumb gets the shorter distance (see THUMB_HOVER).
	var hover := THUMB_HOVER if _active_ray == "I" else KEY_HOVER
	# An unreachable key leaves the pad above the hover plane; the hover must
	# never sink below the press pose, so the pull-back is clamped at zero.
	_click_lift = maxf(0.0, (_click_face.z + hover) - _click_press_pad.z)
	_click_pose_hover = _click_pose_press.duplicate(true)
	_click_pose_hover["arm"]["elbow_z"] = float(
		_click_pose_hover["arm"].get("elbow_z", 0.0)) + _click_lift
	_click_approach_t = clampf(CLICK_APPROACH_MIN
		+ _click_rest.distance_to(_click_face) / 700.0,
		CLICK_APPROACH_MIN, CLICK_APPROACH_MAX)
	_click_path = ClickPath.build(_click_pose_rest, _click_pose_hover,
		_click_pose_press, _click_approach_t, CLICK_PRESS, CLICK_RELEASE,
		CLICK_RETURN, {"ray": _active_ray, "clear_z": KEY_FACE + 3.0,
		"clear_rect": KEY_RECT, "key": k})
	_set_click_pose(_click_pose_rest)


func _cancel_click() -> void:
	if _click_stage == "":
		return
	_click_stage = ""
	_click_key = -1
	_click_t = 0.0
	if _grid_down != -1:
		_grid_down = -1
		_paint_grid()
	for mi in _grid_keys:
		mi.position.z = KEY_Z * SCALE
	_update_markers()


func _advance_click(delta: float) -> void:
	if _click_stage == "":
		return
	_click_t += delta
	if _click_t >= float(_click_path["total"]):
		_set_click_pose(_click_pose_rest)
		_grid_keys[_click_key].position.z = KEY_Z * SCALE
		_click_stage = ""
		_click_key = -1
		_click_t = 0.0
		_error = _click_err_rest
		_grid_down = -1
		_paint_grid()
		# The stage was still set when the last pose was applied, so the
		# markers were hidden; show the target ball again even if the display
		# has nothing left to chase.
		_apply()
		return
	_set_click_pose(ClickPath.at(_click_path, _click_t))


# A click is a scripted path, so the pose the solver state holds and the pose
# on screen are the same every frame. That is what keeps the key sinking
# exactly with the fingertip drawn on it: no chase sits between the two.
func _set_click_pose(p: Dictionary) -> void:
	_pose = p
	_disp = p.duplicate(true)
	_error = 0.0
	_thumb_f = float(p.get("thumb_f", 0.0))
	if _active_ray == "I":
		_shares = []
		_spread = 0.0
		_energy = _thumb_f * _thumb_f
	else:
		_shares = IK.shares_of(_active_ray, p["fingers"][_active_ray])
		_spread = 0.0
		_energy = 0.0
	_arm_shares = ArmModel.shares_of(p.get("arm", {}))
	_levels = ArmModel.levels(p.get("arm", {}))
	_chain_energy = 0.0
	_apply()


# The key sinks by how far the DISPLAYED pad is past its face. The pad point is
# the contact surface itself (the thumb's palmar pad, a finger's tip surface),
# so the key starts to give CLICK_SINK_LEAD before the face and bottoms out
# KEY_TRAVEL past it. The pose path moves the pad monotonically along z, so the
# key follows the finger without a separate phase clock.
func _update_click_key() -> void:
	if _click_key < 0:
		return
	var pad := _pad_of_pose(_active_ray, _disp)
	var u := clampf((KEY_FACE + CLICK_SINK_LEAD - pad.z)
		/ (KEY_TRAVEL + CLICK_SINK_LEAD), 0.0, 1.0)
	_grid_keys[_click_key].position.z = (KEY_Z - KEY_TRAVEL * u) * SCALE
	var down := u > 0.0
	if down != (_grid_down == _click_key):
		_grid_down = _click_key if down else -1
		_paint_grid()


func _make_markers() -> void:
	_target_node = MeshInstance3D.new()
	var sp := SphereMesh.new()
	sp.radius = TARGET_R * SCALE
	sp.height = TARGET_R * 2.0 * SCALE
	sp.radial_segments = 24
	sp.rings = 12
	_target_node.mesh = sp
	var tm := StandardMaterial3D.new()
	tm.albedo_color = Color("#1e6fd9")
	tm.emission_enabled = true
	tm.emission = Color("#1e6fd9")
	tm.emission_energy_multiplier = 0.55
	tm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# Always on top: in the demo the target walks the palmar side and would
	# otherwise hide behind the fingers, leaving the motion unmotivated.
	tm.no_depth_test = true
	_target_node.material_override = tm
	add_child(_target_node)

	_pad_node = MeshInstance3D.new()
	_pad_node.mesh = sp.duplicate()
	(_pad_node.mesh as SphereMesh).radius = 1.8 * SCALE
	(_pad_node.mesh as SphereMesh).height = 3.6 * SCALE
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color("#b3261e")
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_pad_node.material_override = pm
	add_child(_pad_node)

	_line_mesh = ImmediateMesh.new()
	_line = MeshInstance3D.new()
	_line.mesh = _line_mesh
	var lm := StandardMaterial3D.new()
	lm.albedo_color = Color("#b3261e")
	lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lm.no_depth_test = true
	_line.material_override = lm
	add_child(_line)


func _make_ui() -> void:
	var font := _load_font()

	var layer := CanvasLayer.new()
	add_child(layer)

	var panel := PanelContainer.new()
	panel.position = Vector2(18, 18)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1.0, 1.0, 1.0, 0.88)
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

	_title = Label.new()
	_title.text = "Кисть 189 мм · IK: палец → кисть → предплечье → локоть"
	_title.add_theme_font_size_override("font_size", 21)
	_title.add_theme_color_override("font_color", Color("#17181b"))
	if font != null:
		_title.add_theme_font_override("font", font)
	box.add_child(_title)

	var nums := Label.new()
	nums.text = ("пястные 46·67·65·62·56 · фаланги II 44·25·19 · III 48·27·21"
		+ " · IV 47·27·20 · V 37·21·16 мм\n"
		+ "предплечье 150 мм (видимая часть до локтя) · кисть 189 мм")
	nums.add_theme_font_size_override("font_size", 14)
	nums.add_theme_color_override("font_color", Color("#3b3b40"))
	if font != null:
		nums.add_theme_font_override("font", font)
	box.add_child(nums)

	_state = Label.new()
	_state.add_theme_font_size_override("font_size", 16)
	_state.add_theme_color_override("font_color", Color("#1b4a86"))
	if font != null:
		_state.add_theme_font_override("font", font)
	box.add_child(_state)

	var bar := PanelContainer.new()
	bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_top = -112
	var bsb := StyleBoxFlat.new()
	bsb.bg_color = Color(1.0, 1.0, 1.0, 0.82)
	bsb.content_margin_left = 18
	bsb.content_margin_top = 8
	bsb.content_margin_bottom = 8
	bar.add_theme_stylebox_override("panel", bsb)
	layer.add_child(bar)

	_hint = Label.new()
	_hint.text = ("ЛКМ по синему шарику — тянуть цель   ·   Shift+ЛКМ — глубина   ·   ЛКМ/ПКМ мимо — вращать   ·   колесо — масштаб\n"
		+ "Tab — палец   ·   Space — покой   ·   W — сгиб запястья   ·   D — демо   ·   F — заморозить руку\n"
		+ "K — скрыть сетку клавиш; клик по клавише — нажатие выделенным пальцем\n"
		+ "1 кожа   ·   2 кости   ·   3 просвет   ·   R — камера   ·   A — автоповорот   ·   Esc — выход")
	_hint.add_theme_font_size_override("font_size", 15)
	_hint.add_theme_color_override("font_color", Color("#33343a"))
	if font != null:
		_hint.add_theme_font_override("font", font)
	bar.add_child(_hint)


func _load_font() -> Font:
	var f := FontFile.new()
	if f.load_dynamic_font(FONT_PATH) == OK:
		return f
	return null


# ---- model, solver, skin ----------------------------------------------

func _pad_of_pose(ray: String, p: Dictionary) -> Vector3:
	var xf := ArmModel.hand_transform(p.get("arm", {}))
	if ray == "I":
		return xf * HandModel.thumb_pad(HandModel.thumb_fk(float(p["thumb_f"])))
	return xf * HandModel.finger_pad(ray,
		HandModel.finger_fk(ray, p["fingers"][ray]))


func _pad_now() -> Vector3:
	return _pad_of_pose(_active_ray, _pose)


# The wrist test: a static pose with a fixed flexion, through the same apply
# path as the solver. Leaving the mode returns to IK at the pad of the pose on
# screen, so nothing jumps.
func _wrist_pose() -> void:
	if _wrist_test < 0:
		_demo = false
		_target = _pad_now()
		_solve()
		return
	var p := HandModel.rest_pose()
	p["arm"]["wrist_flex"] = float(WRIST_TESTS[_wrist_test])
	_pose = p
	_disp = p.duplicate(true)
	_error = 0.0
	_thumb_f = 0.0
	_shares = [0.0, 0.0, 0.0]
	_spread = 0.0
	_energy = 0.0
	_arm_shares = ArmModel.shares_of(p["arm"])
	_levels = ArmModel.levels(p["arm"])
	_chain_energy = 0.0
	_apply()


func _solve() -> void:
	var r: Dictionary = IK.solve_chain(_active_ray, _target, _pose,
		{"arm": _free_arm})
	_pose = r["pose"]
	_error = float(r["error"])
	_thumb_f = float(_pose["thumb_f"])
	_arm_shares = r.get("arm_shares", [])
	_levels = r.get("levels", {})
	_chain_energy = float(r.get("chain_energy", 0.0))
	if _active_ray == "I":
		_shares = []
		_spread = 0.0
		_energy = _thumb_f * _thumb_f
	else:
		_shares = r["shares"]
		_spread = float(r["spread"])
		_energy = float(r["energy"])
	_apply()


func _apply() -> void:
	_model = HandModel.new(1.0, 0.0, _disp)
	if not _rig.is_empty():
		SkinRig.apply_pose(_rig, _model)
		var mi: MeshInstance3D = _rig["instance"]
		mi.visible = _mode != 1
		mi.material_override = _mat_xray if _mode == 2 else _mat_skin
	if not _live.is_empty():
		BoneView.update_live(_live, _model)
		(_live["root"] as Node3D).visible = _mode != 0
	if not _arm_view.is_empty():
		ArmView.update_live(_arm_view, _disp.get("arm", {}))
		(_arm_view["skin_root"] as Node3D).visible = _mode != 1
		(_arm_view["bone_root"] as Node3D).visible = _mode != 0
		ArmView.set_skin_material(_arm_view, _mat_xray if _mode == 2 else _mat_skin)
	_update_markers()
	_update_hud()


func _update_markers() -> void:
	_target_node.position = _target * SCALE
	# During a key click the blue ball would sit on the key and hide the
	# contact; the hand itself is the marker there.
	var show := _click_stage == ""
	_target_node.visible = show
	var pad := _pad_of_pose(_active_ray, _disp)
	_pad_node.visible = _error > 0.5 and show
	_pad_node.position = pad * SCALE
	_line_mesh.clear_surfaces()
	if _error > 0.5 and show:
		_line_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
		_line_mesh.surface_add_vertex(pad * SCALE)
		_line_mesh.surface_add_vertex(_target * SCALE)
		_line_mesh.surface_end()


# The largest joint difference between two poses, in degrees (the thumb's
# single coordinate is scaled to the same order; the elbow's millimetres are
# on the same order as the shares). Used to decide whether the display has
# caught up with the solver.
func _pose_gap(a: Dictionary, b: Dictionary) -> float:
	var worst := absf(float(a.get("thumb_f", 0.0)) - float(b.get("thumb_f", 0.0))) * 100.0
	var fa: Dictionary = a.get("fingers", {})
	var fb: Dictionary = b.get("fingers", {})
	for ray in fa:
		for j in ["mcp", "pip", "dip", "fan"]:
			worst = maxf(worst, absf(float(fa[ray][j]) - float(fb[ray][j])))
	var aa: Dictionary = a.get("arm", {})
	var ab: Dictionary = b.get("arm", {})
	for j in ArmModel.ALL_JOINTS:
		worst = maxf(worst, absf(float(aa.get(j, 0.0)) - float(ab.get(j, 0.0))))
	return worst


func _lerp_pose(a: Dictionary, b: Dictionary, t: float) -> Dictionary:
	var out := a.duplicate(true)
	for ray in out["fingers"]:
		for j in ["mcp", "pip", "dip", "fan"]:
			out["fingers"][ray][j] = lerpf(float(a["fingers"][ray][j]),
				float(b["fingers"][ray][j]), t)
	out["thumb_f"] = lerpf(float(a.get("thumb_f", 0.0)), float(b.get("thumb_f", 0.0)), t)
	for j in ArmModel.ALL_JOINTS:
		out["arm"][j] = lerpf(float(a["arm"].get(j, 0.0)), float(b["arm"].get(j, 0.0)), t)
	return out


# Which level is still moving, and therefore how fast the display may chase.
# Shares normalise degrees and millimetres to one scale, so a 2 mm elbow move
# and a 1 degree wrist move are compared as fractions of their own ranges.
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


# Move the shown pose toward the solved one. A normal drag is a few degrees
# per frame and looks immediate; a basin handoff is tens of degrees and is
# spread over a fraction of a second instead of snapping. The rate comes from
# the largest level that is still moving, so the elbow never snaps.
func _advance_display(delta: float) -> void:
	if _disp.is_empty():
		_disp = _pose.duplicate(true)
		_apply()
		return
	var gap := _pose_gap(_disp, _pose)
	if gap <= SMOOTH_SNAP:
		return
	var rate := _chase_rate(_disp, _pose)
	var t := 1.0 - exp(-rate * delta)
	_disp = _lerp_pose(_disp, _pose, t)
	if _pose_gap(_disp, _pose) <= SMOOTH_SNAP:
		_disp = _pose.duplicate(true)
	_apply()


func _update_hud() -> void:
	var demo := "   ·   демо" if _demo else ""
	var frozen := "   ·   рука заморожена" if not _free_arm else ""
	var wtest := ""
	if _wrist_test >= 0:
		wtest = "   ·   тест запястья %+.0f°" % float(WRIST_TESTS[_wrist_test])
	var pos := "цель %.1f, %.1f, %.1f мм" % [_target.x, _target.y, _target.z]
	var arm: Dictionary = _pose.get("arm", {})
	var lev: Dictionary = _levels
	var wf := float(arm.get("wrist_flex", 0.0))
	var wd := float(arm.get("wrist_dev", 0.0))
	var pr := float(arm.get("pronation", 0.0))
	var ff := float(arm.get("forearm_flex", 0.0))
	var fa := float(arm.get("forearm_abd", 0.0))
	var ex := float(arm.get("elbow_x", 0.0))
	var ey := float(arm.get("elbow_y", 0.0))
	var ez := float(arm.get("elbow_z", 0.0))
	if _active_ray == "I":
		var th := HandModel.thumb_at(_thumb_f)
		var eff := HandModel.thumb_effort(th)
		_state.text = ("большой палец · f = %+.2f%s%s%s\n%s · остаток %.2f мм\n"
			+ "CMC %.1f° / %.1f°   ·   MCP %.1f°   ·   IP %.1f°   ·   усилие %.0f/%.0f/%.0f%%\n"
			+ "уровни: палец %.0f%% · кисть %.0f%% · пронация %.0f%% · предплечье %.0f%% · локоть %.0f%%\n"
			+ "запястье %+.1f/%+.1f° · пронация %+.1f° · предплечье %+.1f/%+.1f°\n"
			+ "локоть %+.1f, %+.1f, %+.1f мм") % [
			_thumb_f, demo, frozen, wtest, pos, _error,
			float(th["cmc_flex"]), float(th["cmc_abd"]), float(th["mcp"]), float(th["ip"]),
			float(eff["cmc"]), float(eff["mcp"]), float(eff["ip"]),
			float(lev.get("thumb", 0.0)), float(lev.get("wrist", 0.0)),
			float(lev.get("pronation", 0.0)), float(lev.get("forearm", 0.0)),
			float(lev.get("elbow", 0.0)), wf, wd, pr, ff, fa, ex, ey, ez]
		return
	var a: Dictionary = _pose["fingers"][_active_ray]
	_state.text = ("палец %s (%s)%s%s%s\n%s · остаток %.2f мм\n"
		+ "MCP %.1f°   ·   PIP %.1f°   ·   DIP %.1f°   ·   веер %+.1f°\n"
		+ "доли хода %+.0f%% / %+.0f%% / %+.0f%%   ·   разброс %.3f   ·   энергия %.2f\n"
		+ "уровни: палец %.0f%% · веер %.0f%% · кисть %.0f%% · пронация %.0f%% · предплечье %.0f%% · локоть %.0f%%\n"
		+ "запястье %+.1f/%+.1f° · пронация %+.1f° · предплечье %+.1f/%+.1f°\n"
		+ "локоть %+.1f, %+.1f, %+.1f мм") % [
		_active_ray, FINGER_NAME[_active_ray], demo, frozen, wtest, pos, _error,
		float(a["mcp"]), float(a["pip"]), float(a["dip"]), float(a["fan"]),
		float(_shares[0]) * 100.0, float(_shares[1]) * 100.0, float(_shares[2]) * 100.0,
		_spread, _energy,
		float(lev.get("finger", 0.0)), float(lev.get("fan", 0.0)),
		float(lev.get("wrist", 0.0)), float(lev.get("pronation", 0.0)),
		float(lev.get("forearm", 0.0)), float(lev.get("elbow", 0.0)),
		wf, wd, pr, ff, fa, ex, ey, ez]


# Pick the distance from the free height (below the panel, above the key bar)
# and lift the orbit centre so the study's middle lands on that free area's
# middle. Works in both a portrait window and a wide test window.
func _cam_span(preset: int) -> float:
	match preset:
		0:
			return BODY_MM
		1:
			return HAND_ARM_MM
		_:
			return HAND_MM


func _cam_mid_y(preset: int) -> float:
	match preset:
		0:
			return (FINGERTIP_MM - ArmModel.FOREARM_L) * 0.5
		1:
			return FINGERTIP_MM - HAND_ARM_MM * 0.5
		_:
			return FINGERTIP_MM - HAND_MM * 0.5


func _fit_camera() -> void:
	var h := get_viewport().get_visible_rect().size.y
	if h < 200.0:
		return
	var free := maxf(h - HUD_BOTTOM - HINT_TOP, 200.0)
	var preset := clampi(_cam_preset, 0, 2)
	var view_mm := _cam_span(preset) * h / (free * FIT_FILL)
	_dist = view_mm / (2.0 * tan(deg_to_rad(_cam.fov * 0.5)) * 1000.0)
	var mid := (HUD_BOTTOM + h - HINT_TOP) * 0.5
	var shift_mm := (mid - h * 0.5) * view_mm / h
	_center = Vector3(BODY_MID_X * SCALE,
		(_cam_mid_y(preset) + shift_mm) * SCALE, 0.0)
	_update_camera()


func _update_camera() -> void:
	var dir := Vector3(sin(_yaw) * cos(_pitch), sin(_pitch), cos(_yaw) * cos(_pitch))
	_cam.position = _center + dir * _dist
	_cam.look_at(_center, Vector3.UP)
	_rig_root.rotation.y = _yaw


# ---- input -------------------------------------------------------------

func _near_target(mouse: Vector2) -> bool:
	var t := _target * SCALE
	if _cam.is_position_behind(t):
		return false
	return _cam.unproject_position(t).distance_to(mouse) <= PICK_PX


func _aim(mouse: Vector2) -> Variant:
	var origin := _cam.project_ray_origin(mouse)
	var dir := _cam.project_ray_normal(mouse)
	var n := -_cam.global_transform.basis.z
	var plane := Plane(n, n.dot(_target * SCALE))
	var hit = plane.intersects_ray(origin, dir)
	if hit == null:
		return null
	return (hit as Vector3) / SCALE


func _set_target(mm: Vector3) -> void:
	var p := Vector3(clampf(mm.x, CLAMP_MIN.x, CLAMP_MAX.x),
		clampf(mm.y, CLAMP_MIN.y, CLAMP_MAX.y),
		clampf(mm.z, CLAMP_MIN.z, CLAMP_MAX.z))
	if p.distance_to(_target) < 0.001:
		return
	_target = p
	_demo = false
	_solve()


func _input(event: InputEvent) -> void:
	# The event itself is handled now; the rate and the render loop are put
	# back by _process on this same iteration (it runs after input).
	_idle_t = 0.0
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_spin = false
			if _near_target(mb.position):
				_cancel_click()
				_drag = "target"
				_wrist_test = -1
			else:
				var k := _grid_key_at(mb.position)
				if k >= 0:
					_cancel_click()
					_start_click(k)
					_drag = ""
				else:
					_cancel_click()
					_drag = "orbit"
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			_spin = false
			_cancel_click()
			_drag = "orbit"
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_dist = clampf(_dist * 0.92, 0.18, 1.6)
			_update_camera()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_dist = clampf(_dist / 0.92, 0.18, 1.6)
			_update_camera()
		elif not mb.pressed:
			_drag = ""
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _drag == "orbit":
			_yaw -= mm.relative.x * 0.007
			_pitch = clampf(_pitch + mm.relative.y * 0.007, -1.45, 1.45)
			_update_camera()
		elif _drag == "target":
			if Input.is_key_pressed(KEY_SHIFT):
				# Depth: up on the screen pushes the target away from the
				# camera, down pulls it closer. 0.8 mm per pixel is a
				# comfortable speed at the default framing.
				var fwd := -_cam.global_transform.basis.z.normalized()
				_set_target(_target + fwd * (-mm.relative.y * 0.8))
			else:
				var hit = _aim(mm.position)
				if hit != null:
					_set_target(hit as Vector3)
	elif event is InputEventKey:
		_key(event as InputEventKey)


func _key(k: InputEventKey) -> void:
	if not k.pressed or k.echo:
		return
	# Any keyboard mode change takes the hand back from a running key click.
	if k.keycode in [KEY_TAB, KEY_SPACE, KEY_W, KEY_D, KEY_F]:
		_cancel_click()
	match k.keycode:
		KEY_1:
			_mode = 0
		KEY_2:
			_mode = 1
		KEY_3:
			_mode = 2
		KEY_TAB:
			var i := CYCLE.find(_active_ray)
			_active_ray = CYCLE[(i + 1) % CYCLE.size()]
			_demo = false
			_wrist_test = -1
			_target = _pad_now()
			_solve()
		KEY_SPACE:
			_pose = HandModel.rest_pose()
			_demo = false
			_wrist_test = -1
			_target = _pad_now()
			_error = 0.0
			_shares = [0.0, 0.0, 0.0]
			_spread = 0.0
			_energy = 0.0
			_thumb_f = 0.0
			_arm_shares = ArmModel.shares_of(_pose["arm"])
			_levels = ArmModel.levels(_pose["arm"])
			_chain_energy = 0.0
			_apply()
		KEY_D:
			_demo = not _demo
			_wrist_test = -1
			if _demo:
				_start_demo()
		KEY_W:
			_wrist_test += 1
			if _wrist_test >= WRIST_TESTS.size():
				_wrist_test = -1
			_demo = false
			_wrist_pose()
		KEY_F:
			_free_arm = not _free_arm
			_solve()
		KEY_K:
			if _grid != null:
				_grid.visible = not _grid.visible
				if not _grid.visible:
					_clear_grid_hover()
					_cancel_click()
		KEY_A:
			_spin = not _spin
		KEY_R:
			_cam_preset = (_cam_preset + 1) % 3
			_yaw = 0.62
			_pitch = 0.10
			_spin = false
			_fit_camera()
		KEY_ESCAPE:
			get_tree().quit()
			return
		_:
			return
	_apply()
	get_viewport().set_input_as_handled()


# ---- demo --------------------------------------------------------------

# The demo walks a sequence of targets, each built from a pose that engages
# one more level of the chain: rest, finger press, fan, wrist, forearm root,
# back to rest. Every target is reachable by construction, so the residual is
# a check of the solver rather than a hope.
func _start_demo() -> void:
	_demo = true
	_demo_t = 0.0
	_demo_waypoints = _build_demo()


func _build_demo() -> Array:
	var base := HandModel.rest_pose()
	var out := []
	out.append(_pad_of_pose(_active_ray, base))

	var p := base.duplicate(true)
	if _active_ray == "I":
		p["thumb_f"] = 0.55
	else:
		p["fingers"][_active_ray] = IK.angles_of_shares(_active_ray,
			[0.55, 0.55, 0.55, 0.0])
	out.append(_pad_of_pose(_active_ray, p))

	if _active_ray != "I":
		p = base.duplicate(true)
		p["fingers"][_active_ray] = IK.angles_of_shares(_active_ray,
			[0.0, 0.0, 0.0, 1.0])
		out.append(_pad_of_pose(_active_ray, p))

	p = base.duplicate(true)
	p["arm"]["wrist_dev"] = 18.0
	p["arm"]["wrist_flex"] = 10.0
	out.append(_pad_of_pose(_active_ray, p))

	p = base.duplicate(true)
	p["arm"]["forearm_flex"] = -35.0
	p["arm"]["wrist_flex"] = 5.0
	out.append(_pad_of_pose(_active_ray, p))

	p = base.duplicate(true)
	p["arm"]["forearm_abd"] = 35.0
	p["arm"]["forearm_flex"] = -20.0
	out.append(_pad_of_pose(_active_ray, p))

	out.append(out[0])
	return out


func _process(delta: float) -> void:
	# Idle throttle: the window renders through llvmpipe, so 60 fps costs most
	# of the machine. When nothing moves for a moment the frame rate drops and
	# the render loop stops — a still image needs neither. The first event
	# restores both before the next frame.
	_idle_t += delta
	# A drag cannot outlive the window's focus or its button: if the release
	# happened outside, the flag would otherwise pin the viewer at full rate.
	if _drag != "" and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) \
			and not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		_drag = ""
	if not _focused:
		Engine.max_fps = FPS_UNFOCUSED
		_set_render_loop(false)
	else:
		var busy := _demo or _spin or _drag != "" or _click_stage != ""
		var idle := not busy and _idle_t >= IDLE_AFTER
		var want := FPS_IDLE if idle else FPS_ACTIVE
		if Engine.max_fps != want:
			Engine.max_fps = want
		_set_render_loop(not idle)
	# The hovered key follows the pointer even when the camera is being
	# orbited, so it is recomputed from the live pointer rather than from the
	# last motion event.
	if _grid != null and _grid.visible and _drag == "":
		_update_grid_hover(get_viewport().get_mouse_position())
	if _click_stage != "":
		_advance_click(delta)
	elif _demo:
		_demo_t += delta
		if _demo_waypoints.size() >= 2:
			var n := _demo_waypoints.size()
			var seg_t := 1.1
			var hold_t := 0.35
			var step := seg_t + hold_t
			var total := step * float(n - 1)
			var t := fmod(_demo_t, total)
			var i := int(t / step)
			var local := t - float(i) * step
			var u := 0.0
			if local > hold_t:
				u = smoothstep(0.0, 1.0, (local - hold_t) / seg_t)
			var a: Vector3 = _demo_waypoints[i]
			var b: Vector3 = _demo_waypoints[(i + 1) % n]
			_target = a.lerp(b, u)
		_solve()
	elif _spin and _drag == "":
		_yaw += delta * 0.22
		_update_camera()
	_advance_display(delta)
	_update_click_key()


# A still frame does not need to be drawn again. Stopping the render loop
# (not the viewport update) leaves the last presented frame on screen, while
# the event loop keeps running so the next input wakes the view instantly.
func _set_render_loop(on: bool) -> void:
	if on == _render_on:
		return
	_render_on = on
	RenderingServer.render_loop_enabled = on


func _notification(what: int) -> void:
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
			# A resized window is damaged: draw it again even if it was idle.
			if _focused:
				_idle_t = 0.0
				_set_render_loop(true)
		NOTIFICATION_WM_CLOSE_REQUEST:
			get_tree().quit()
