# Who owns the sawtooth at the inner wrist fold? Renders the same bend with the
# hand in flat red and the arm in flat blue, then with normals, close on the
# joint. Frames: /tmp/opencode/fold-*.png.
extends Node3D

const HandModel := preload("res://hand_model.gd")
const ArmView := preload("res://arm_view.gd")

const OUT := "/tmp/opencode"
const W := 800
const H := 800

var _vp: SubViewport
var _view: Node3D
var _mat_hand: StandardMaterial3D
var _mat_arm: StandardMaterial3D
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
	_mat_hand = StandardMaterial3D.new()
	_mat_hand.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat_hand.albedo_color = Color(0.85, 0.15, 0.15)
	_mat_arm = StandardMaterial3D.new()
	_mat_arm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat_arm.albedo_color = Color(0.15, 0.25, 0.85)
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded;
void fragment() {
	ALBEDO = NORMAL * 0.5 + vec3(0.5);
}
"""
	_mat_norm = ShaderMaterial.new()
	_mat_norm.shader = sh

	_view.set("_dist", 0.12)
	_view.set("_center", Vector3(0.0, -0.012, -0.01))
	for cam in [[1.45, 0.10, "side"], [-1.30, 0.10, "palm"]]:
		_view.set("_yaw", float(cam[0]))
		_view.set("_pitch", float(cam[1]))
		_view.call("_update_camera")
		for flex in [0.0, 70.0]:
			await _shot("fold-%s-f%02d-color" % [cam[2], int(flex)], float(flex), "color")
			await _shot("fold-%s-f%02d-norm" % [cam[2], int(flex)], float(flex), "norm")
		await _shot("fold-%s-f70-armnorm" % cam[2], 70.0, "armnorm")
		await _shot("fold-%s-f70-handnorm" % cam[2], 70.0, "handnorm")
	get_tree().quit()


func _shot(name: String, flex: float, how: String) -> void:
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
	var arm: Dictionary = _view.get("_arm_view")
	var arm_skin := arm["skin_mesh"] as MeshInstance3D
	if how == "color":
		skin.material_override = _mat_hand
		ArmView.set_skin_material(arm, _mat_arm)
	else:
		skin.material_override = _mat_norm
		ArmView.set_skin_material(arm, _mat_norm)
	skin.visible = how != "armnorm"
	(arm["skin_root"] as Node3D).visible = how != "handnorm"
	for i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := _vp.get_texture().get_image()
	var path := "%s/%s.png" % [OUT, name]
	img.save_png(path)
	print("shot: ", path)
