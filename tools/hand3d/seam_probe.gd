# Ultra close-up of the hand/arm seam: skin, view-space normals, each surface
# alone and the wireframe. The seam is a shared curve of two separate meshes,
# so positions can match while the shading does not; the normal pass shows the
# split and the wireframe shows how fine the two tessellations are there.
# Frames: /tmp/opencode/seam-*.png.
extends Node3D

const HandModel := preload("res://hand_model.gd")

const OUT := "/tmp/opencode"
const W := 1000
const H := 1000

const CAMS := [["palm", -1.30], ["side", 1.45]]
const FLEXES := [0.0, 70.0]

var _vp: SubViewport
var _view: Node3D
var _skin: Material
var _norm: ShaderMaterial


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
	_view.set("_cam_preset", 2)
	_view.call("_fit_camera")
	_view.set("_dist", 0.095)
	_view.set("_center", Vector3(0.0, -0.002, 0.0))
	_skin = _view.get("_mat_skin")
	var sh := Shader.new()
	sh.code = "shader_type spatial; render_mode unshaded; void fragment(){ ALBEDO = NORMAL * 0.5 + 0.5; }"
	_norm = ShaderMaterial.new()
	_norm.shader = sh
	for cam in CAMS:
		for flex in FLEXES:
			_view.set("_yaw", float(cam[1]))
			_view.set("_pitch", 0.05)
			_view.call("_update_camera")
			var tag := "%s-f%02d" % [cam[0], int(flex)]
			_view.set("_mat_skin", _skin)
			await _shot("seam-skin-" + tag, float(flex))
			_view.set("_mat_skin", _norm)
			await _shot("seam-norm-" + tag, float(flex))
			_view.set("_mat_skin", _skin)
			await _shot("seam-hand-" + tag, float(flex), "hand")
			await _shot("seam-arm-" + tag, float(flex), "arm")
			RenderingServer.set_debug_generate_wireframes(true)
			_vp.debug_draw = Viewport.DEBUG_DRAW_WIREFRAME
			await _shot("seam-wire-" + tag, float(flex))
			_vp.debug_draw = Viewport.DEBUG_DRAW_DISABLED
	get_tree().quit()


func _shot(name: String, flex: float, who: String = "both") -> void:
	var pose: Dictionary = HandModel.rest_pose()
	pose["arm"]["wrist_flex"] = flex
	_view.set("_pose", pose)
	_view.set("_disp", pose.duplicate(true))
	_view.set("_target", _view.call("_pad_now"))
	_view.set("_error", 0.0)
	_view.set("_demo", false)
	_view.call("_apply")
	var rig: Dictionary = _view.get("_rig")
	var arm: Dictionary = _view.get("_arm_view")
	(rig["instance"] as MeshInstance3D).visible = true
	(arm["skin_root"] as Node3D).visible = true
	if who != "both":
		(rig["instance"] as MeshInstance3D).visible = who != "arm"
		(arm["skin_root"] as Node3D).visible = who != "hand"
	for i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := _vp.get_texture().get_image()
	var path := "%s/%s.png" % [OUT, name]
	img.save_png(path)
	print("shot: ", path)
