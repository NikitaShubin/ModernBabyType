# Close-ups of the thenar at three thumb states, in the rest hand frame, from
# the radial side and from the palm. The point is the SKIN at the thumb base:
# does the web or the ball of the thumb pinch, fold or bulge as f opens?
#   mbt-godot --path /work/tools/hand3d res://thenar_render.tscn
extends Node3D

const HandModel := preload("res://hand_model.gd")

const OUT := "/tmp/opencode"
const W := 900
const H := 900
const STATES := [["open", -1.0], ["lo35", -0.35], ["rest", 0.0], ["press", 0.55]]

# name, yaw, pitch, distance (m), centre (mm)
const CAMS := [["dorsal", 0.15, 0.30, 0.18, Vector3(40, 70, 0)],
	["radial", 1.30, 0.10, 0.18, Vector3(40, 70, 0)],
	["palmar", 0.25, -0.45, 0.18, Vector3(40, 70, 0)]]

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
	for c in _view.get_children():
		if c is CanvasLayer:
			(c as CanvasLayer).visible = false
	for st in STATES:
		var pose := HandModel.rest_pose()
		pose["thumb_f"] = float(st[1])
		var m := HandModel.new(1.0, 0.0, pose)
		print("%s thenar %s axis0 %s axis1 %s" % [st[0], str(m._thenar_c),
			str(m._thenar_ax[0]), str(m._thenar_ax[1])])
		for cam in CAMS:
			_view.set("_yaw", float(cam[1]))
			_view.set("_pitch", float(cam[2]))
			_view.set("_dist", float(cam[3]))
			_view.set("_center", (cam[4] as Vector3) * 0.001)
			_view.call("_update_camera")
			await _shot("thenar-%s-%s" % [st[0], cam[0]], pose)
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
