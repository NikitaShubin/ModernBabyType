# Renders the press pose the click solver finds at the top-left key for several
# caps on the thumb's extension, plus the hover that goes with one of them.
# The question is visual: which cap parks the hand in a pose that reads as
# "thumb presses the key" rather than "the whole arm leans in".
#   mbt-godot --path /work/tools/hand3d res://press_render.tscn
extends Node3D

const HandModel := preload("res://hand_model.gd")
const IK := preload("res://ik.gd")

const OUT := "/tmp/opencode"
const W := 900
const H := 900
const KEY := Vector3(-90.0, 160.0, -70.0)
const KEY_FACE := -69.0
const DEEP := 3.6
const LIFT := 0.30

var _vp: SubViewport
var _view: Node3D


func _ready() -> void:
	var deep := Vector3(KEY.x, KEY.y, KEY_FACE - DEEP)
	var rest := HandModel.rest_pose()
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
	for c in _view.get_children():
		if c is CanvasLayer:
			(c as CanvasLayer).visible = false
	_view.set("_yaw", 0.62)
	_view.set("_pitch", 0.10)
	_view.set("_dist", 0.42)
	_view.set("_center", Vector3(-30, 100, -35) * 0.001)
	_view.set("_active_ray", "I")
	_view.call("_update_camera")
	var grid: Node3D = _view.get("_grid")
	if grid != null:
		grid.visible = true
	for lo in [-1.0, -0.6, -0.35, -0.1]:
		var p: Dictionary = IK.solve_chain("I", deep, rest,
			{"arm": true, "f_lo": float(lo)})
		print("f_lo %5.2f press f %5.2f err %5.2f" % [float(lo),
			float(p["thumb_f"]), float(p["error"])])
		await _shot("press-lo%03d" % int(round(-float(lo) * 100.0)), p["pose"])
		if absf(float(lo) + 0.35) < 0.001:
			var h: Dictionary = p["pose"].duplicate(true)
			h["thumb_f"] = clampf(float(h["thumb_f"]) + LIFT, -1.0, 1.0)
			await _shot("press-lo035-hover", h)
	get_tree().quit()


func _shot(name: String, pose: Dictionary) -> void:
	_view.set("_pose", pose)
	_view.set("_disp", pose.duplicate(true))
	_view.set("_target", _view.call("_pad_now"))
	_view.set("_error", 0.0)
	_view.set("_demo", false)
	_view.call("_apply")
	for i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := _vp.get_texture().get_image()
	var path := "%s/%s.png" % [OUT, name]
	img.save_png(path)
	print("shot: ", path)
