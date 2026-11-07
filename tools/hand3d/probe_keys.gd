# Projects the key grid to screen coordinates at the screenshot's window size,
# so a click can be aimed at a key without guessing. Headless:
#   mbt-godot --headless --path /work/tools/hand3d --script res://probe_keys.gd
extends SceneTree

const Viewer := preload("res://viewer.gd")


func _init() -> void:
	var v: Node3D = Viewer.new()
	get_root().add_child(v)
	get_root().size = Vector2i(640, 760)
	v._fit_camera()
	print("dist %.3f  center %s  yaw %.2f pitch %.2f" % [v._dist, str(v._center), v._yaw, v._pitch])
	for iy in v.KEY_ROWS:
		var row := []
		for ix in v.KEY_COLS:
			var p: Vector3 = v._grid_key_pos(iy * v.KEY_COLS + ix)
			var s: Vector2 = v._cam.unproject_position(p)
			row.append("(%3d,%3d)" % [int(s.x), int(s.y)])
		print("row %d: %s" % [iy, " ".join(row)])
	quit()
