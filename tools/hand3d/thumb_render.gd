# TEMP driver: the SS50h pose (wide elbows, turned hands, relaxed thumbs,
# all four pads on their keys). The author's view, straight down, both profiles
# and a close-up of the index, whose knuckle carries the reach at this arm.
extends SceneTree

const OUT := "/tmp/opencode"

var v: Node3D


func _init() -> void:
	var scn: PackedScene = load("res://board.tscn")
	v = scn.instantiate()
	root.add_child(v)
	v.process_mode = Node.PROCESS_MODE_DISABLED
	_run.call_deferred()


func _cam(yaw_deg: float, pitch_deg: float, span: float,
		cx: float, cy: float, cz: float) -> void:
	v.set("_yaw", deg_to_rad(yaw_deg))
	v.set("_pitch", deg_to_rad(pitch_deg))
	var fov := float((v.get("_cam") as Camera3D).fov)
	v.set("_dist", span / (2.0 * tan(deg_to_rad(fov * 0.5)) * 1000.0))
	v.set("_center", Vector3(cx, cy, cz) * 0.001)
	v.call("_update_camera")


func _shot(name: String) -> void:
	RenderingServer.render_loop_enabled = true
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	if img == null:
		print("shot empty: ", name)
		return
	img.save_png(OUT.path_join("%s.png" % name))
	print("shot: ", name)


func _run() -> void:
	await process_frame
	await process_frame
	for c in v.get_children():
		if c is CanvasLayer:
			(c as CanvasLayer).visible = false
	# The author's view of both hands, the same camera as the SS50f frame.
	_cam(10.3, 29.8, 330.0, 0.0, 120.0, -40.0)
	await _shot("ss50h-both")
	_cam(35.0, 42.0, 330.0, 0.0, 120.0, -40.0)
	await _shot("ss50h-3q")
	# Straight down: are the four pads level and on their keys?
	_cam(0.0, 78.0, 360.0, 0.0, 120.0, -60.0)
	await _shot("ss50h-top")
	# The right hand from the front (the author's usual look at the thumbs).
	_cam(10.3, 29.8, 190.0, -6.0, 112.0, -60.0)
	await _shot("ss50h-r-front")
	# Profiles: the curl of the four fingers and the thumb's tangency.
	_cam(90.0, 12.0, 230.0, 0.0, 110.0, -55.0)
	await _shot("ss50h-side")
	# Close-up of the left index on "а": the knuckle carries the reach.
	_cam(30.0, 20.0, 110.0, -55.0, 145.0, -60.0)
	await _shot("ss50h-index")
	quit()
