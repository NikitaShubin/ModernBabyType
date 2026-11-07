# Renders the wrist at several bend angles, close up, so the seam and the
# skin weights can be judged on pixels instead of numbers.
#
#   godot --rendering-driver opengl3 --path . res://wrist_bench.tscn
#
# Frames land in /tmp/opencode/wrist-*.png.
extends Node3D

const HandModel := preload("res://hand_model.gd")

const OUT := "/tmp/opencode"
const W := 900
const H := 900

# name, wrist_flex, wrist_dev, pronation
const POSES := [
	["rest", 0.0, 0.0, 0.0],
	["flex55", 55.0, 0.0, 0.0],
	["flex70", 70.0, 0.0, 0.0],
	["dev+30", 0.0, 30.0, 0.0],
	["dev-30", 0.0, -30.0, 0.0],
	["pron+70", 0.0, 0.0, 70.0],
	["pron-70", 0.0, 0.0, -70.0],
	["flex55-pron40", 55.0, 0.0, 40.0],
	["flex55-dev25", 55.0, 25.0, 0.0],
]

const CAMS := [
	["side", 1.45, 0.10],
	["palm", -1.30, 0.10],
]

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
	# The viewer throttles itself to a still frame after a moment of quiet and
	# stops the render loop; a bench that awaits frame_post_draw would wait
	# forever. The bench drives every frame itself.
	_view.set_process(false)
	RenderingServer.render_loop_enabled = true
	# The viewer's own camera framing is for the full window; this bench is
	# close up on the wrist, so it drives the camera directly. The HUD is
	# hidden: it would cover the joint.
	for c in _view.get_children():
		if c is CanvasLayer:
			(c as CanvasLayer).visible = false
	_view.set("_cam_preset", 2)
	_view.call("_fit_camera")
	_view.set("_dist", 0.34)
	_view.set("_center", Vector3(0.0, 0.035, 0.0))

	for pose in POSES:
		for cam in CAMS:
			_view.set("_yaw", float(cam[1]))
			_view.set("_pitch", float(cam[2]))
			_view.call("_update_camera")
			await _shot("wrist-%s-%s" % [pose[0], cam[0]],
				float(pose[1]), float(pose[2]), float(pose[3]))
	get_tree().quit()


func _shot(name: String, flex: float, dev: float, pron: float) -> void:
	var pose: Dictionary = HandModel.rest_pose()
	pose["arm"]["wrist_flex"] = flex
	pose["arm"]["wrist_dev"] = dev
	pose["arm"]["pronation"] = pron
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
