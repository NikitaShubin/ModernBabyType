# The wrist under flexion from three angles: the joint's fold is judged here.
# Frames: /tmp/opencode/bend-*.png.
extends Node3D

const HandModel := preload("res://hand_model.gd")

const OUT := "/tmp/opencode"
const W := 800
const H := 800

const YAWS := [1.5708, 3.1416, 0.7854]

var _vp: SubViewport
var _view: Node3D


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
	_view.set("_dist", 0.17)
	_view.set("_center", Vector3(0.0, -0.01, -0.01))
	_set_flex(70.0)
	for i in 4:
		await get_tree().process_frame
	for yaw in YAWS:
		_view.set("_yaw", float(yaw))
		_view.set("_pitch", 0.10)
		_view.call("_update_camera")
		await _shot("bend-y%03d" % [int(round(rad_to_deg(yaw)))])
	get_tree().quit()


func _set_flex(flex: float) -> void:
	var p := HandModel.rest_pose()
	p["arm"]["wrist_flex"] = flex
	_view.set("_disp", p)
	_view.set("_error", 0.0)
	_view.set("_demo", false)
	_view.call("_apply")


func _shot(name: String) -> void:
	for i in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := _vp.get_texture().get_image()
	var path := "%s/%s.png" % [OUT, name]
	img.save_png(path)
	print("shot: ", path)
