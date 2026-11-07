# Zebra stripes from the reflection vector: the standard way to see curvature
# breaks. A C1/C2 step in the surface makes the stripes kink or tear; a smooth
# joint keeps them continuous across the seam. Frames: /tmp/opencode/zebra-*.
extends Node3D

const HandModel := preload("res://hand_model.gd")

const OUT := "/tmp/opencode"
const W := 800
const H := 800

const POSES := [0.0, 35.0, 70.0]
const CAMS := [["side", 1.45], ["palm", -1.30]]

var _vp: SubViewport
var _view: Node3D
var _mat: ShaderMaterial
var _mat_norm: ShaderMaterial


func _ready() -> void:
	_vp = SubViewport.new()
	_vp.size = Vector2i(W, H)
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.msaa_3d = Viewport.MSAA_4X
	add_child(_vp)
	var scene: PackedScene = load("res://viewer.tscn")
	_view = scene.instantiate()
	_vp.add_child(_view)
	await get_tree().process_frame
	await get_tree().process_frame
	_view.set_process(false)
	RenderingServer.render_loop_enabled = true
	for c in _view.get_children():
		if c is CanvasLayer:
			(c as CanvasLayer).visible = false

	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, cull_disabled;
varying vec3 vw;
void vertex() {
	vw = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	vec3 n = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 v = normalize(CAMERA_POSITION_WORLD - vw);
	vec3 r = reflect(-v, n);
	float s = sin(46.0 * r.y);
	ALBEDO = mix(vec3(0.10, 0.11, 0.13), vec3(0.93, 0.92, 0.88),
		smoothstep(-0.10, 0.10, s));
}
"""
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	var shn := Shader.new()
	shn.code = """
shader_type spatial;
render_mode unshaded, cull_disabled;
void fragment() {
	ALBEDO = NORMAL * 0.5 + vec3(0.5);
}
"""
	_mat_norm = ShaderMaterial.new()
	_mat_norm.shader = shn

	_view.set("_cam_preset", 2)
	_view.call("_fit_camera")
	_view.set("_dist", 0.16)
	_view.set("_center", Vector3(0.0, -0.005, -0.01))
	var rig: Dictionary = _view.get("_rig")
	var arm: Dictionary = _view.get("_arm_view")
	for flex in POSES:
		for cam in CAMS:
			_view.set("_yaw", float(cam[1]))
			_view.set("_pitch", 0.10)
			_view.call("_update_camera")
			await _shot("zebra-%s-f%02d" % [cam[0], int(flex)], float(flex))
			await _shot("norm-%s-f%02d" % [cam[0], int(flex)], float(flex), _mat_norm)
	get_tree().quit()


func _shot(name: String, flex: float, mat: Material = null) -> void:
	var pose: Dictionary = HandModel.rest_pose()
	pose["arm"]["wrist_flex"] = flex
	_view.set("_pose", pose)
	_view.set("_disp", pose.duplicate(true))
	_view.set("_target", _view.call("_pad_now"))
	_view.set("_error", 0.0)
	_view.set("_demo", false)
	_view.call("_apply")
	var rig: Dictionary = _view.get("_rig")
	var use: Material = _mat if mat == null else mat
	(rig["instance"] as MeshInstance3D).material_override = use
	var arm: Dictionary = _view.get("_arm_view")
	_arm_set(arm, use)
	for i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := _vp.get_texture().get_image()
	var path := "%s/%s.png" % [OUT, name]
	img.save_png(path)
	print("shot: ", path)


func _arm_set(arm: Dictionary, mat: Material) -> void:
	(arm["skin_mesh"] as MeshInstance3D).material_override = mat

