# TEMP: render the home thumb with its column held at several abductions.
#   mbt-godot --path tools/hand3d res://thumb_abd_render.tscn
extends Node3D

const HandModel := preload("res://hand_model.gd")
const HomePose := preload("res://home_pose.gd")
const IK := preload("res://ik.gd")

const OUT := "/tmp/opencode/abd"
const W := 800
const H := 800
const ABDS := [-15.18, -8.0, 0.0, 8.0]
const CAMS := [["back", 0.0, 0.05, 0.26, Vector3(35, 70, -20)],
	["rad", 0.9, 0.10, 0.26, Vector3(35, 70, -20)]]

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
			(c as CanvasLayer).show()
	var side := "L"
	var root := float(HomePose.HOME_ROOTS[side])
	var home: Dictionary = HomePose.build(side, root)
	var target: Vector3 = HomePose.target(side, "I", root)
	for abd in ABDS:
		var base: Dictionary = home.duplicate(true)
		base["thumb_hold"] = {"twist": float(HomePose.THUMB_TWIST[side]),
			"cmc_abd": float(abd)}
		var r: Dictionary = IK.solve_chain("I", target, base,
			{"arm": false, "tuck": false, "clear_w": 0.0, "dir_w": 0.0,
			"thumb_dof": 4})
		var pose: Dictionary = r["pose"]
		print("abd %.1f err %.2f thumb %s" % [abd, float(r["error"]),
			str(HandModel.thumb_of_pose(pose))])
		for cam in CAMS:
			_view.set("_yaw", float(cam[1]))
			_view.set("_pitch", float(cam[2]))
			_view.set("_dist", float(cam[3]))
			_view.set("_center", (cam[4] as Vector3) * 0.001)
			_view.call("_update_camera")
			await _shot("abd-%s-%s" % [str(abd), str(cam[0])], pose)
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
