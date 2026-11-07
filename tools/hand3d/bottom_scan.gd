# TEMP probe: how the arm answers the bottom row (author, #11: the far bottom
# keys should not be reached by twisting the wrist alone).
#
# Prints, per bottom-row key, the HOVER pose's arm angles (that is where the
# reach happens — the press only settles under it) and where the hand and the
# pad actually end up in the world.
extends SceneTree

const ArmModel := preload("res://arm_model.gd")
const Kbd3D := preload("res://kbd3d.gd")

var v: Node
var done := false


func _init() -> void:
	var scn: PackedScene = load("res://board.tscn")
	v = scn.instantiate()
	root.add_child(v)
	v.process_mode = Node.PROCESS_MODE_DISABLED


func _process(_dt: float) -> bool:
	if done:
		return true
	done = true
	print("== bottom row, hover pose")
	for i in v._keys.size():
		var key: Dictionary = v._keys[i]
		var s := String(key["s"])
		if not (Kbd3D.ROW_BOTTOM as Array).has(s):
			continue
		var side := String(v._sim_key_side(i))
		if side == "":
			print("%-7s (no finger)" % s)
			continue
		var home: Dictionary = (v._sim_rest_home[side] as Dictionary).duplicate(true)
		var rx := float(v._sim_rest_rx[side])
		var st: Dictionary = v._sim_stroke(side, i, home, rx,
			v._foreign_rest(side))
		var c := Kbd3D.centre(key)
		var ray := String(Kbd3D.hand_finger(s, c.x)[1])
		_line("%-7s %s %s" % [s, side, ray], st["hover"], side, rx, c, ray)
		_line("  press", st["press"], side, rx, c, ray)
	print("== left/right extremes of the other rows, for scale")
	for s in ["ф", "я", "Shift", "ъ", "\\", "э", "↵", "←", "ё"]:
		for i in v._keys.size():
			if String((v._keys[i] as Dictionary)["s"]) != s:
				continue
			var side := String(v._sim_key_side(i))
			if side == "":
				continue
			var home: Dictionary = (v._sim_rest_home[side] as Dictionary).duplicate(true)
			var rx := float(v._sim_rest_rx[side])
			var st: Dictionary = v._sim_stroke(side, i, home, rx,
				v._foreign_rest(side))
			var c := Kbd3D.centre(v._keys[i])
			var ray := String(Kbd3D.hand_finger(s, c.x)[1])
			_line("%-7s %s %s" % [s, side, ray], st["hover"], side, rx, c, ray)
			break
	quit()
	return true


func _line(tag: String, p: Dictionary, side: String, rx: float,
		c: Vector3, ray: String) -> void:
	var a: Dictionary = p["arm"]
	var f := ArmModel.frames(a)
	var wrist: Vector3 = v._w(side, rx, f["wrist"])
	var pad: Vector3 = v._w(side, rx, v._pad_of_pose(side, ray, p))
	print("%-14s dev %+6.1f flex %+6.1f pron %+6.1f abd %+6.1f ff %+5.1f"
		% [tag, float(a["wrist_dev"]), float(a["wrist_flex"]),
		float(a["pronation"]), float(a["forearm_abd"]),
		float(a["forearm_flex"])]
		+ " | elbow %+6.1f %+6.1f %+6.1f | wrist %+7.2f %+7.2f %+6.2f"
		% [float(a["elbow_x"]), float(a["elbow_y"]), float(a["elbow_z"]),
		wrist.x, wrist.y, wrist.z]
		+ " | pad %+7.2f %+7.2f %+6.2f key %+7.2f %+7.2f"
		% [pad.x, pad.y, pad.z, c.x, c.y])
