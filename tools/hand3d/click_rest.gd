# TEMP: the CLICK path of the board viewer (no MBT_SIM): does the hand come
# back to its rest pose after one click, after two quick clicks (the second
# cancels the first mid-flight) and after a right-click that cancels a click?
extends SceneTree

const Kbd3D := preload("res://kbd3d.gd")

var v: Node
var done := false


func _init() -> void:
	v = load("res://board.tscn").instantiate()
	root.add_child(v)
	v.process_mode = Node.PROCESS_MODE_DISABLED


func _step(n: int) -> void:
	for f in n:
		v._process(1.0 / 60.0)


func _find(want: String, side: String) -> int:
	for i in v._keys.size():
		if String((v._keys[i] as Dictionary)["s"]) == want \
				and String(v._sim_key_side(i)) == side:
			return i
	return -1


func _click(k: int) -> void:
	var r: Rect2 = (v._keys[k] as Dictionary)["r"]
	v._start_click(k, Vector3(r.get_center().x, r.get_center().y, Kbd3D.FACE_Z))


# What _input does on a left click that lands on a key.
func _press(k: int) -> void:
	v._cancel_click()
	_click(k)


func _report(tag: String, side: String) -> void:
	var st: Dictionary = v._hands[side]
	print("%-40s gap %8.4f | stage '%s' | dev %+6.1f elbow %+6.1f %+6.1f %+6.1f"
		% [tag, v._pose_gap(st["disp"], st["home"]), String(v._click_stage),
		float((st["disp"]["arm"] as Dictionary)["wrist_dev"]),
		float((st["disp"]["arm"] as Dictionary)["elbow_x"]),
		float((st["disp"]["arm"] as Dictionary)["elbow_y"]),
		float((st["disp"]["arm"] as Dictionary)["elbow_z"])])


func _process(_dt: float) -> bool:
	if done:
		return true
	done = true
	print("sim ", v._sim)
	var ctrl := _find("Ctrl", "R")
	var alt := _find("Alt", "R")
	var glob := _find("глобус", "R")
	var let := _find("н", "R")
	print("ctrl ", ctrl, " alt ", alt, " glob ", glob, " letter ", let)
	_report("open", "R")

	_press(ctrl)
	_step(400)
	_report("A one click Ctrl R", "R")

	_press(alt)
	_step(12)
	_press(alt)
	_step(400)
	_report("B Alt R twice, 12 frames apart", "R")

	_press(glob)
	_step(12)
	v._cancel_click()          # a right-click / a miss: orbit starts
	_step(400)
	_report("C глобус cancelled mid-click", "R")

	_press(ctrl)
	_step(6)
	_press(let)
	_step(400)
	_report("D Ctrl R, then н mid-click", "R")

	_press(let)
	_step(6)
	_press(ctrl)
	_step(400)
	_report("E н, then Ctrl R mid-click", "R")

	_step(600)
	_report("final", "R")
	quit()
	return true
