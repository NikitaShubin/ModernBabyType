# Isolates the wrist notch: the hand alone and the arm alone in the same bend,
# from the same camera. If the notch is in the hand's own palmar wall it shows
# with the arm hidden; if the arm's bend field makes it, it shows on the arm.
extends Node3D

const HandModel := preload("res://hand_model.gd")

const OUT := "/tmp/opencode"
const W := 900
const H := 900

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
	_view.set("_yaw", 1.45)
	_view.set("_pitch", 0.10)
	_view.set("_dist", 0.30)
	_view.set("_center", Vector3(0.0, 0.020, 0.0))
	_view.call("_update_camera")

	var rig: Dictionary = _view.get("_rig")
	var arm: Dictionary = _view.get("_arm_view")
	var hand := rig["instance"] as MeshInstance3D
	var arm_skin := arm["skin_root"] as Node3D
	var arm_bones := arm["bone_root"] as Node3D
	var live := _view.get("_live")["root"] as Node3D

	for flex in [0.0, 70.0]:
		var pose: Dictionary = HandModel.rest_pose()
		pose["arm"]["wrist_flex"] = flex
		_view.set("_pose", pose)
		_view.set("_disp", pose.duplicate(true))
		_view.set("_target", _view.call("_pad_now"))
		_view.set("_error", 0.0)
		_view.set("_demo", false)
		_view.call("_apply")

		hand.visible = true
		arm_skin.visible = false
		arm_bones.visible = false
		live.visible = false
		await _shot("split-hand-f%02d" % int(flex))

		hand.visible = false
		arm_skin.visible = true
		await _shot("split-arm-f%02d" % int(flex))

		hand.visible = true
	get_tree().quit()


func _shot(name: String) -> void:
	for i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := _vp.get_texture().get_image()
	var path := "%s/%s.png" % [OUT, name]
	img.save_png(path)
	print("shot: ", path)
