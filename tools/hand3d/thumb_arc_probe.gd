# Where the thumb tip and the little fingertip actually go as their own
# coordinates move. The home pose needs the thumb to drop ~9 mm and the little
# finger to reach ~9 mm further forward; this prints the arcs so the limits are
# visible instead of guessed.
extends SceneTree

const HandModel := preload("res://hand_model.gd")


func _init() -> void:
	print("thumb pad vs f:")
	for i in 11:
		var f := -1.0 + 0.2 * float(i)
		var fk := HandModel.thumb_fk(f)
		print("  f %5.2f  pad %s  angles %s" % [f, str(HandModel.thumb_pad(fk)),
			str(fk["angles"])])
	print("little finger pad vs flex share (fan 0):")
	for i in 11:
		var s := float(i) / 10.0
		var q := [s, s, s, 0.0]
		var a: Dictionary = {
			"mcp": 26.0 + s * (0.0 - 26.0),
			"pip": 40.0 + s * (0.0 - 40.0),
			"dip": 17.0 + s * (0.0 - 17.0),
			"fan": 0.0,
		}
		var fk := HandModel.finger_fk("V", a)
		print("  s %4.2f  pad %s" % [s, str(HandModel.finger_pad("V", fk))])
	quit(0)
