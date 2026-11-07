# The wrist from every side: eight yaws around the joint at rest and at full
# flexion, plus two zooms on the palmar fold. The author judges the junction
# by eye, so a single camera is not enough. Frames: /tmp/opencode/turn-*.png.
extends Node3D

const HandModel := preload("res://hand_model.gd")

const OUT := "/tmp/opencode"
const W := 800
const H := 800

const FLEXES := [0.0, 70.0]
const YAWS := [0.0, 0.7854, 1.5708, 2.3562, 3.1416, -2.3562, -1.5708, -0.7854]

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
	_view.set("_dist", 0.16)
	_view.set("_center", Vector3(0.0, -0.005, -0.01))
	print("ready")
	for flex in FLEXES:
		_set_flex(flex)
		for i in 4:
			await get_tree().process_frame
		for yaw in YAWS:
			_view.set("_yaw", float(yaw))
			_view.set("_pitch", 0.10)
			_view.call("_update_camera")
			await _shot("turn-f%02d-y%03d" % [int(flex), int(round(rad_to_deg(yaw)))])
	# Two zooms on the palmar side, where the fold lives.
	_set_flex(70.0)
	for i in 4:
		await get_tree().process_frame
	_view.set("_dist", 0.105)
	_view.set("_pitch", 0.02)
	for yaw in [3.1416, -2.3562]:
		_view.set("_yaw", float(yaw))
		_view.call("_update_camera")
		await _shot("turn-zoom-y%03d" % [int(round(rad_to_deg(yaw)))])
	print("done")
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
