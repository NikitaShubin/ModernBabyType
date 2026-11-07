# Steps a real click of a key with the selected finger through the viewer and
# saves frames of the approach and the press, with the pose numbers alongside.
# This is what the author sees: one C1 path through rest → hover → press →
# hover → rest, shared with click_clear.gd, so the hand and the finger move
# together, the hover is passed at speed, and the key sinks with the drawn pad.
#   mbt-godot --path /work/tools/hand3d res://click_frames.tscn -- --ray I --key 40
extends Node3D

const HandModel := preload("res://hand_model.gd")

const OUT := "/tmp/opencode"
const W := 900
const H := 900
const KEY := 40                            # top-left: row 4, col 0
const KEY_Z_MM := -70.0
const DT := 1.0 / 60.0
const FRAMES := 96
const EVERY := 4

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
	var ray := "I"
	var key := KEY
	var cx := -30.0
	var cy := 100.0
	var cz := -35.0
	var every := EVERY
	var frames := FRAMES
	var dist := 0.42
	var yaw := 0.62
	var pitch := 0.10
	var ua := OS.get_cmdline_user_args()
	for i in ua.size():
		if ua[i] == "--ray" and i + 1 < ua.size():
			ray = ua[i + 1]
		if ua[i] == "--key" and i + 1 < ua.size():
			key = int(ua[i + 1])
		if ua[i] == "--cx" and i + 1 < ua.size():
			cx = float(ua[i + 1])
		if ua[i] == "--cy" and i + 1 < ua.size():
			cy = float(ua[i + 1])
		if ua[i] == "--cz" and i + 1 < ua.size():
			cz = float(ua[i + 1])
		if ua[i] == "--dist" and i + 1 < ua.size():
			dist = float(ua[i + 1])
		if ua[i] == "--every" and i + 1 < ua.size():
			every = int(ua[i + 1])
		if ua[i] == "--frames" and i + 1 < ua.size():
			frames = int(ua[i + 1])
		if ua[i] == "--yaw" and i + 1 < ua.size():
			yaw = float(ua[i + 1])
		if ua[i] == "--pitch" and i + 1 < ua.size():
			pitch = float(ua[i + 1])
	_view.set("_active_ray", ray)
	_view.set("_yaw", yaw)
	_view.set("_pitch", pitch)
	_view.set("_dist", dist)
	_view.set("_center", Vector3(cx, cy, cz) * 0.001)
	_view.call("_update_camera")
	var grid: Node3D = _view.get("_grid")
	if grid != null:
		grid.visible = true
	var pose: Dictionary = HandModel.rest_pose()
	_view.set("_pose", pose)
	_view.set("_disp", pose.duplicate(true))
	_view.set("_target", _view.call("_pad_now"))
	_view.call("_apply")
	_view.call("_start_click", key)
	for i in frames:
		_view.call("_advance_click", DT)
		_view.call("_advance_display", DT)
		_view.call("_update_click_key")
		if i % every == 0:
			var p: Dictionary = _view.get("_disp")
			var arm: Dictionary = p["arm"]
			var pad: Vector3 = _view.call("_pad_of_pose", ray, p)
			var keys: Array = _view.get("_grid_keys")
			var keyz := KEY_Z_MM
			if keys.size() > key:
				keyz = (keys[key] as MeshInstance3D).position.z / 0.001
			var finger := ""
			if ray != "I":
				var a: Dictionary = p["fingers"][ray]
				finger = " | mcp %5.1f pip %5.1f dip %5.1f" % [float(a["mcp"]),
					float(a["pip"]), float(a["dip"])]
			print("%s f %5.2f stage %-8s pad %7.2f %7.2f %7.2f keyz %6.2f%s | wrist %6.1f/%6.1f pron %5.1f fore %5.1f/%5.1f elbow %5.1f,%5.1f,%5.1f" % [
				ray, float(p["thumb_f"]), str(_view.get("_click_stage")),
				pad.x, pad.y, pad.z, keyz, finger,
				float(arm["wrist_flex"]), float(arm["wrist_dev"]),
				float(arm["pronation"]), float(arm["forearm_flex"]),
				float(arm["forearm_abd"]), float(arm["elbow_x"]),
				float(arm["elbow_y"]), float(arm["elbow_z"])])
			await _shot("click-frame-%s-%03d" % [ray, i])
	get_tree().quit()


func _shot(name: String) -> void:
	for i in 2:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := _vp.get_texture().get_image()
	var path := "%s/%s.png" % [OUT, name]
	img.save_png(path)
