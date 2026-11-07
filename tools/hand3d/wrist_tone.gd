# Two-tone seam diagnostic: the hand is blue, the forearm is orange, both
# unshaded. The seam is then visible as a colour boundary, so a silhouette
# corner can be attributed to the hand's wall or to the arm's sweep.
# Frames: /tmp/opencode/tone-*.png.
extends Node3D

const HandModel := preload("res://hand_model.gd")
const ArmView := preload("res://arm_view.gd")

const OUT := "/tmp/opencode"
const W := 900
const H := 900

var _vp: SubViewport
var _view: Node3D
var _hand_mat: StandardMaterial3D
var _arm_mat: StandardMaterial3D


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

	_hand_mat = StandardMaterial3D.new()
	_hand_mat.albedo_color = Color("#3b6fd4")
	_hand_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_arm_mat = StandardMaterial3D.new()
	_arm_mat.albedo_color = Color("#d98a3b")
	_arm_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	for cam in [[1.45, 0.10, "side"], [-1.30, 0.10, "palm"],
			[0.30, 0.35, "front"]]:
		_view.set("_yaw", float(cam[0]))
		_view.set("_pitch", float(cam[1]))
		_view.set("_dist", 0.34)
		_view.set("_center", Vector3(0.0, 0.035, 0.0))
		_view.call("_update_camera")
		for flex in [0.0, 70.0]:
			await _shot("tone-%s-f%02d" % [cam[2], int(flex)], flex)
	get_tree().quit()


func _shot(name: String, flex: float) -> void:
	var pose: Dictionary = HandModel.rest_pose()
	pose["arm"]["wrist_flex"] = flex
	_view.set("_pose", pose)
	_view.set("_disp", pose.duplicate(true))
	_view.set("_target", _view.call("_pad_now"))
	_view.set("_error", 0.0)
	_view.set("_demo", false)
	_view.call("_apply")
	var rig: Dictionary = _view.get("_rig")
	var skin := rig["instance"] as MeshInstance3D
	skin.material_override = _hand_mat
	var arm: Dictionary = _view.get("_arm_view")
	(arm["skin_mesh"] as MeshInstance3D).material_override = _arm_mat
	for i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := _vp.get_texture().get_image()
	var path := "%s/%s.png" % [OUT, name]
	img.save_png(path)
	print("shot: ", path)
