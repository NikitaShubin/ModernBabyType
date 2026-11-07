extends SceneTree

const HandModel := preload("res://hand_model.gd")


func _init() -> void:
	var a := {"mcp": 37.8958655757382, "pip": 53.994095998482,
		"dip": 28.5973879338234, "fan": -8.0}
	var fk: Dictionary = HandModel.finger_fk("II", a)
	print("pts %s" % str(fk["pts"]))
	print("pad %s" % str(HandModel.finger_pad("II", fk)))
	var r: Dictionary = HandModel.rest_pose()
	print("rest II %s" % str(r["fingers"]["II"]))
	print("rest pts %s" % str(HandModel.finger_fk("II",
		r["fingers"]["II"])["pts"]))
	quit(0)
