# TEMP: the space bar is in ROW_BOTTOM, so the #11 profile applies to it too.
# Does the space press still keep the arm still (author #6), and does the hand
# come back home after a space press?
extends SceneTree

const Kbd3D := preload("res://kbd3d.gd")
const ArmModel := preload("res://arm_model.gd")

var v: Node
var done := false


func _init() -> void:
	v = load("res://board.tscn").instantiate()
	root.add_child(v)
	v.process_mode = Node.PROCESS_MODE_DISABLED


func _step(n: int) -> void:
	for f in n:
		v._process(1.0 / 60.0)


func _report(tag: String, side: String) -> void:
	var st: Dictionary = v._hands[side]
	var a: Dictionary = st["disp"]["arm"]
	print("%-30s gap %8.4f | dev %+6.1f abd %+6.1f elbow %+6.1f %+6.1f %+6.1f"
		% [tag, v._pose_gap(st["disp"], st["home"]),
		float(a["wrist_dev"]), float(a["forearm_abd"]),
		float(a["elbow_x"]), float(a["elbow_y"]), float(a["elbow_z"])])


func _process(_dt: float) -> bool:
	if done:
		return true
	done = true
	var space := -1
	for i in v._keys.size():
		if String((v._keys[i] as Dictionary)["s"]) == "пробел":
			space = i
			break
	print("space index ", space)
	for side in ["R", "L"]:
		v._sim_letter_side = "L" if side == "R" else "R"
		_report("before space (%s)" % side, side)
		v._sim_press(space, side)
		_step(2)
		var a: Dictionary = v._hands[side]["disp"]["arm"]
		print("   press: dev %+6.1f elbow %+6.1f %+6.1f %+6.1f"
			% [float(a["wrist_dev"]), float(a["elbow_x"]),
			float(a["elbow_y"]), float(a["elbow_z"])])
		_step(40)
		_report("held space (%s)" % side, side)
		v._sim_release(space)
		_step(180)
		_report("after space (%s)" % side, side)
	quit()
	return true
