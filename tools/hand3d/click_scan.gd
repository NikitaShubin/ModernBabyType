# TEMP: the MOUSE CLICK path on the far bottom keys — does it move the hand
# the way the typed stroke does (the #11 rule), or does it still pay with the
# wrist? Prints the same numbers bot_scan.gd prints for the typed stroke.
extends SceneTree

const Kbd3D := preload("res://kbd3d.gd")
const ArmModel := preload("res://arm_model.gd")
const HandModel := preload("res://hand_model.gd")

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


func _report(tag: String, side: String, ray: String,
		pose: Dictionary) -> void:
	var home: Dictionary = v._hands[side]["home"]
	var a: Dictionary = pose["arm"]
	var travel := ArmModel.hand_transform(a).origin.distance_to(
		ArmModel.hand_transform(home["arm"]).origin)
	var mcp := "-"
	if ray != "I":
		mcp = str(int(round(float(pose["fingers"][ray]["mcp"]))))
	print("%-4s %-8s hand %5.1f mm | dev %+6.1f | abd %+6.1f | flex %+6.1f | elbow %+6.1f %+6.1f %+6.1f | mcp %3s"
		% [side, tag, travel, float(a["wrist_dev"]), float(a["forearm_abd"]),
		float(a["wrist_flex"]), float(a["elbow_x"]), float(a["elbow_y"]),
		float(a["elbow_z"]), mcp])


func _process(_dt: float) -> bool:
	if done:
		return true
	done = true
	print("sim ", v._sim)
	for pair in [["Ctrl", "L"], ["Win", "L"], ["Alt", "L"],
			["Alt", "R"], ["глобус", "R"], ["Ctrl", "R"]]:
		var want := String(pair[0])
		var side := String(pair[1])
		var k := _find(want, side)
		if k < 0:
			continue
		var ray := String(Kbd3D.hand_finger(want,
			Kbd3D.centre(v._keys[k] as Dictionary).x)[1])
		var r: Rect2 = (v._keys[k] as Dictionary)["r"]
		v._start_click(k, Vector3(r.get_center().x, r.get_center().y,
			Kbd3D.FACE_Z))
		_report(want, side, ray, v._click_pose_press)
		_step(400)
	quit()
	return true
