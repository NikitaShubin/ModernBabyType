# Renders the standalone hand study: skin views + bone views.
# Frames land in /tmp/opencode/hand3d (mounted into the container).
extends Node3D

const HandModel := preload("res://hand_model.gd")
const Mesher := preload("res://mesher.gd")
const BoneView := preload("res://bone_view.gd")

const OUT := "/tmp/opencode/hand3d"
const CACHE := "res://cache/skin.res"
const VSTEP := 2.0          # mm per SDF voxel
const SCALE := 0.001        # model is in mm

var _sub: SubViewport
var _cam: Camera3D
var _skins := {}     # pose -> MeshInstance3D
var _boness := {}    # pose -> Node3D
var _skin: MeshInstance3D
var _bones: Node3D
var _lights: Node3D
var _mat_skin: StandardMaterial3D
var _mat_flat: StandardMaterial3D
var _mat_nocull: StandardMaterial3D
var _mat_normals: ShaderMaterial

var views := [
	{"name": "skin-dorsal", "pos": Vector3(0, 92, 560), "target": Vector3(0, 92, 0),
		"skin": true, "ortho": false},
	{"name": "skin-palmar", "pos": Vector3(0, 92, -560), "target": Vector3(0, 92, 0),
		"skin": true, "ortho": false},
	{"name": "skin-radial", "pos": Vector3(560, 92, 0), "target": Vector3(0, 92, 0),
		"skin": true, "ortho": false},
	{"name": "skin-ulnar", "pos": Vector3(-560, 92, 0), "target": Vector3(0, 92, 0),
		"skin": true, "ortho": false},
	{"name": "skin-3q", "pos": Vector3(330, 160, 460), "target": Vector3(0, 92, 0),
		"skin": true, "ortho": false},
	{"name": "skin-straight-open-dorsal", "pos": Vector3(0, 92, 560), "target": Vector3(0, 92, 0),
		"skin": true, "ortho": false, "pose": "straight_open"},
	{"name": "skin-straight-rest-dorsal", "pos": Vector3(0, 92, 560), "target": Vector3(0, 92, 0),
		"skin": true, "ortho": false, "pose": "straight_rest"},
	{"name": "skin-straight-press-dorsal", "pos": Vector3(0, 92, 560), "target": Vector3(0, 92, 0),
		"skin": true, "ortho": false, "pose": "straight_press"},
	{"name": "skin-straight-press-palmar", "pos": Vector3(0, 92, -560), "target": Vector3(0, 92, 0),
		"skin": true, "ortho": false, "pose": "straight_press"},
	{"name": "skin-straight-press-radial", "pos": Vector3(560, 92, -120), "target": Vector3(0, 92, 0),
		"skin": true, "ortho": false, "pose": "straight_press"},
	{"name": "skin-straight-press-3q", "pos": Vector3(330, 160, 460), "target": Vector3(0, 92, 0),
		"skin": true, "ortho": false, "pose": "straight_press"},
	{"name": "skin-straight-open-3q", "pos": Vector3(330, 160, 460), "target": Vector3(0, 92, 0),
		"skin": true, "ortho": false, "pose": "straight_open"},
	{"name": "bones-dorsal", "pos": Vector3(0, 88, 600), "target": Vector3(0, 88, 0),
		"skin": false, "ortho": true, "pose": "straight_open"},
	{"name": "bones-palmar", "pos": Vector3(0, 88, -600), "target": Vector3(0, 88, 0),
		"skin": false, "ortho": true, "pose": "straight_open"},
	{"name": "bones-side", "pos": Vector3(600, 88, 0), "target": Vector3(0, 88, 0),
		"skin": false, "ortho": true, "pose": "straight_open"},
	{"name": "bones-rest-dorsal", "pos": Vector3(0, 88, 600), "target": Vector3(0, 88, 0),
		"skin": false, "ortho": true, "pose": "straight_rest"},
	{"name": "bones-press-dorsal", "pos": Vector3(0, 88, 600), "target": Vector3(0, 88, 0),
		"skin": false, "ortho": true, "pose": "straight_press"},
	{"name": "bones-press-side", "pos": Vector3(600, 88, -60), "target": Vector3(0, 88, 0),
		"skin": false, "ortho": true, "pose": "straight_press"},
	{"name": "bones-rest-side", "pos": Vector3(600, 88, -60), "target": Vector3(0, 88, 0),
		"skin": false, "ortho": true, "pose": "straight_rest"},
	{"name": "bones-open-side", "pos": Vector3(600, 88, -60), "target": Vector3(0, 88, 0),
		"skin": false, "ortho": true, "pose": "straight_open"},
	{"name": "bones-open-dorsal", "pos": Vector3(0, 88, 600), "target": Vector3(0, 88, 0),
		"skin": false, "ortho": true, "pose": "straight_open"},
	{"name": "dbg-flat", "pos": Vector3(0, 92, 560), "target": Vector3(0, 92, 0),
		"skin": true, "ortho": false, "mat": "flat"},
	{"name": "dbg-nocull", "pos": Vector3(0, 92, 560), "target": Vector3(0, 92, 0),
		"skin": true, "ortho": false, "mat": "nocull"},
	{"name": "dbg-normals", "pos": Vector3(0, 92, 560), "target": Vector3(0, 92, 0),
		"skin": true, "ortho": false, "mat": "normals"},
	{"name": "dbg-normals-palmar", "pos": Vector3(0, 92, -560), "target": Vector3(0, 92, 0),
		"skin": true, "ortho": false, "mat": "normals"},
	{"name": "dbg-noshadow", "pos": Vector3(0, 92, -560), "target": Vector3(0, 92, 0),
		"skin": true, "ortho": false, "shadow": false},
	# The thumb alone, one camera for all three states: the sheet has to show
	# the three joints bending together, and from the dorsal side the pressing
	# thumb is foreshortened into a stump. Framed from the radial-palmar
	# corner, where the whole column is seen in profile.
	{"name": "thumb-skin-rest", "pos": Vector3(900, 110, -70), "target": Vector3(38, 88, -40),
		"skin": true, "ortho": true, "size": 0.235, "pose": "straight_rest"},
	{"name": "thumb-skin-open", "pos": Vector3(900, 110, -70), "target": Vector3(38, 88, -40),
		"skin": true, "ortho": true, "size": 0.235, "pose": "straight_open"},
	{"name": "thumb-skin-press", "pos": Vector3(900, 110, -70), "target": Vector3(38, 88, -40),
		"skin": true, "ortho": true, "size": 0.235, "pose": "straight_press"},
	{"name": "thumb-bones-rest", "pos": Vector3(900, 110, -70), "target": Vector3(38, 88, -40),
		"skin": false, "ortho": true, "size": 0.235, "pose": "straight_rest"},
	{"name": "thumb-bones-open", "pos": Vector3(900, 110, -70), "target": Vector3(38, 88, -40),
		"skin": false, "ortho": true, "size": 0.235, "pose": "straight_open"},
	{"name": "thumb-bones-press", "pos": Vector3(900, 110, -70), "target": Vector3(38, 88, -40),
		"skin": false, "ortho": true, "size": 0.235, "pose": "straight_press"},
]


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	_write_states()
	_make_viewport()
	_make_lights()
	# Six states: the four fingers curled or straight, crossed with the thumb's
	# own three values of f. Each is baked once and cached, so the viewer can
	# switch the thumb alone without waiting for the field.
	for f in HandModel.POSE_FINGERS:
		for t in HandModel.POSE_THUMBS:
			var key := "%s_%s" % [f, t]
			var flex: float = HandModel.POSE_FINGERS[f]
			var thumb_f: float = HandModel.POSE_THUMBS[t]
			_skins[key] = _make_skin("skin_%s" % key, flex, thumb_f)
			_boness[key] = _make_bones(flex, thumb_f)
	await _shoot_all()
	get_tree().quit()


# The thumb's states, as numbers, for the sheet: sheet.py must not carry its
# own copy of the angle arithmetic, or the labels drift from the mesh.
func _write_states() -> void:
	var out := {}
	for t in HandModel.POSE_THUMBS:
		var f: float = HandModel.POSE_THUMBS[t]
		var th := HandModel.thumb_at(f)
		var e := HandModel.thumb_effort(th)
		out[t] = {"f": f, "angles": th, "effort": e}
	var fa := FileAccess.open("%s/thumb_states.json" % OUT, FileAccess.WRITE)
	if fa != null:
		fa.store_string(JSON.stringify(out, "\t"))
		fa.close()


func _make_viewport() -> void:
	_sub = SubViewport.new()
	_sub.size = Vector2i(1000, 1300)
	_sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_sub.msaa_3d = Viewport.MSAA_4X
	_sub.transparent_bg = false
	add_child(_sub)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#d9dde0")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#ffffff")
	env.ambient_light_energy = 0.045
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.tonemap_exposure = 0.70
	var we := WorldEnvironment.new()
	we.environment = env
	_sub.add_child(we)

	_cam = Camera3D.new()
	_cam.fov = 30.0
	_cam.near = 0.01
	_cam.far = 4.0
	_sub.add_child(_cam)
	_cam.current = true


func _make_lights() -> void:
	_lights = Node3D.new()
	_sub.add_child(_lights)
	_add_light(Vector3(-48, -56, 0), 1.05, Color("#fff6ea"), true)
	_add_light(Vector3(-10, 52, 0), 0.09, Color("#eaf2ff"), false)
	_add_light(Vector3(-72, 166, 0), 0.30, Color("#ffffff"), false)


func _add_light(rot_deg: Vector3, energy: float, col: Color, shadow: bool) -> void:
	var l := DirectionalLight3D.new()
	l.rotation_degrees = rot_deg
	l.light_energy = energy
	l.light_color = col
	l.shadow_enabled = shadow
	if shadow:
		# The hand is 0.19 m tall; a 1.6 m shadow frustum covers it with a
		# handful of texels and turns every cast shadow into a hard blob.
		l.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
		l.directional_shadow_max_distance = 0.42
		l.shadow_bias = 0.006
		# A hard cast shadow across the palm reads as a hole in the surface.
		l.light_angular_distance = 7.0
	_lights.add_child(l)


func _make_skin(tag: String, flex: float, thumb_f: float) -> MeshInstance3D:
	var cache := "res://cache/%s.res" % tag
	var mesh: ArrayMesh
	if FileAccess.file_exists(cache) and not _want_rebake():
		mesh = load(cache)
		print("skin: loaded cache")
	else:
		var t0 := Time.get_ticks_msec()
		var model := HandModel.new(flex, thumb_f)
		mesh = Mesher.build(model, model.bounds_min(), model.bounds_max(), VSTEP)
		var tris := 0
		if mesh.get_surface_count() > 0:
			tris = mesh.surface_get_array_len(0) / 3
		print("skin: baked in %d ms, tris %d" % [Time.get_ticks_msec() - t0, tris])
		DirAccess.make_dir_recursive_absolute("res://cache")
		ResourceSaver.save(mesh, cache)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("#cb9077")
	mat.roughness = 0.78
	mat.metallic_specular = 0.14
	mat.metallic = 0.0
	mat.rim_enabled = true
	mat.rim = 0.07
	mat.rim_tint = 0.6
	_mat_skin = mat
	_mat_flat = StandardMaterial3D.new()
	_mat_flat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat_flat.albedo_color = Color("#c88060")
	_mat_flat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat_nocull = mat.duplicate()
	_mat_nocull.cull_mode = BaseMaterial3D.CULL_DISABLED
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, cull_disabled;
varying vec3 v_n;
void vertex() { v_n = NORMAL; }
void fragment() { ALBEDO = normalize(v_n) * 0.5 + 0.5; }
"""
	_mat_normals = ShaderMaterial.new()
	_mat_normals.shader = sh
	var inst := MeshInstance3D.new()
	inst.mesh = mesh
	inst.scale = Vector3.ONE * SCALE
	inst.material_override = mat
	_sub.add_child(inst)
	return inst


func _make_bones(flex: float, thumb_f: float) -> Node3D:
	var model := HandModel.new(flex, thumb_f)
	var root: Node3D = BoneView.build(model)
	_sub.add_child(root)
	return root


func _want_rebake() -> bool:
	return OS.get_cmdline_user_args().has("--rebake")


func _shoot_all() -> void:
	var only := ""
	var ua := OS.get_cmdline_user_args()
	if ua.has("--view"):
		only = str(ua[ua.find("--view") + 1])
	for v in views:
		if only != "" and not str(v["name"]).begins_with(only):
			continue
		var is_skin: bool = v["skin"]
		var shade := str(v.get("mat", "skin"))
		var pose := str(v.get("pose", "curled_rest"))
		_skin = _skins[pose]
		_bones = _boness[pose]
		for k in _skins:
			(_skins[k] as Node3D).visible = is_skin and k == pose
			(_boness[k] as Node3D).visible = (not is_skin) and k == pose
		match shade:
			"flat":
				_skin.material_override = _mat_flat
			"nocull":
				_skin.material_override = _mat_nocull
			"normals":
				_skin.material_override = _mat_normals
			_:
				_skin.material_override = _mat_skin
		var pos: Vector3 = v["pos"] * SCALE
		var target: Vector3 = v["target"] * SCALE
		_cam.projection = Camera3D.PROJECTION_ORTHOGONAL if v["ortho"] else Camera3D.PROJECTION_PERSPECTIVE
		if v["ortho"]:
			_cam.size = float(v.get("size", 0.255))
		_cam.look_at_from_position(pos, target, Vector3.UP)
		var want_shadow: bool = v.get("shadow", not is_skin)
		for c in _lights.get_children():
			var dl := c as DirectionalLight3D
			if dl != null and dl.directional_shadow_mode == DirectionalLight3D.SHADOW_ORTHOGONAL:
				dl.shadow_enabled = want_shadow
		# Keep the key light at the same angle to the camera in every view.
		_lights.rotation = Vector3(0, atan2(pos.x - target.x, pos.z - target.z), 0)
		await _settle(3)
		var img := _sub.get_texture().get_image()
		var path := "%s/%s.png" % [OUT, v["name"]]
		img.save_png(path)
		print("shot: ", path)


func _settle(n: int) -> void:
	for i in n:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
