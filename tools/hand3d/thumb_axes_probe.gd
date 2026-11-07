# What each thumb joint actually does, in the hand's own millimetres: move one
# joint by +10 and -10 degrees from rest and print how the metacarpal head, the
# IP joint and the pad move. The sign conventions in the comments have drifted
# before, and the home pose is decided by which joint can move the IP joint
# OUTBOARD.
#
#   mbt-godot --headless --path /work/tools/hand3d --script res://thumb_axes_probe.gd
extends SceneTree

const HandModel := preload("res://hand_model.gd")


func _row(tag: String, t: Dictionary) -> void:
	var fk: Dictionary = HandModel.thumb_fk(t)
	var p: PackedVector3Array = fk["pts"]
	var pad: Vector3 = HandModel.thumb_pad(fk)
	print("  %-14s mcp %s  ip %s  tip %s  pad %s" % [tag, str(p[1]), str(p[2]),
		str(p[3]), str(pad)])


func _init() -> void:
	print("rest %s" % str(HandModel.THUMB_REST))
	_row("rest", HandModel.THUMB_REST.duplicate(true))
	for j in HandModel.THUMB_JOINTS:
		for d in [-10.0, 10.0]:
			var t: Dictionary = HandModel.THUMB_REST.duplicate(true)
			t[j] = float(t[j]) + d
			_row("%s %+d" % [j, int(d)], t)
	print("-- tip radii: %s  (pad = tip + (0,0,-%.1f))" % [str(HandModel.THUMB_TIP_R),
		HandModel.THUMB_TIP_R])
	quit(0)
