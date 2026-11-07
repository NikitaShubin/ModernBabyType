# Where each key lands on the screen in the board viewer's own camera.
#
# The viewer picks a key by casting the mouse ray onto the key plane, so the
# screen position of a key can only be trusted if it comes from the viewer's
# Camera3D itself — a second copy of the camera math drifted by a whole row
# (the copy used the wrong viewport height and picked "к" instead of "4").
# This probe instantiates the real scene, lets `_fit_camera()` run, and prints
# `unproject_position` for every key centre, so scripted clicks are exact.
#
#   mbt-godot --headless --path /work/tools/hand3d --script res://screen_probe.gd
extends SceneTree

const Kbd3D := preload("res://kbd3d.gd")

var _frames := 0
var _root: Node


func _initialize() -> void:
	get_root().size = Vector2i(1000, 1200)
	var scene: PackedScene = load("res://board.tscn")
	_root = scene.instantiate()
	get_root().add_child(_root)
	process_frame.connect(_tick)


func _tick() -> void:
	_frames += 1
	if _frames < 4:
		return
	if _root == null:
		printerr("no root")
		quit(1)
		return
	var vp := get_root().get_visible_rect().size
	var cam: Camera3D = _root.get("_cam")
	printerr("viewport %s cam %s" % [str(vp), str(cam)])
	var ks := Kbd3D.keys()
	var io := Kbd3D.index_of(ks, "о")
	if io >= 0:
		printerr("index_of о = %d (%s) centre %s" % [io, String(ks[io]["s"]),
			str(Kbd3D.centre(ks[io]))])
	else:
		printerr("index_of о = -1")
	if cam == null:
		quit(1)
		return
	for k in Kbd3D.keys():
		var r: Rect2 = k["r"]
		var p := Vector3(r.get_center().x, r.get_center().y, Kbd3D.FACE_Z)
		var sp := cam.unproject_position(p * 0.001)
		printerr("%-7s %.1f %.1f" % [String(k["s"]), sp.x, sp.y])
	quit(0)
