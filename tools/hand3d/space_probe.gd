# TEMP probe (author, 03.11.2026, #6): "при нажатии на пробел почему-то
# шевелится вся рука, а не только большой палец, хотя он уже лежит на
# пробеле". Presses the bar on each hand and measures, frame by frame, how far
# the WRIST travels and how far the thumb's pad travels. A press that the thumb
# alone can make must leave the wrist where it was.
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")

var v: Node


func _init() -> void:
	var scn: PackedScene = load("res://board.tscn")
	v = scn.instantiate()
	root.add_child(v)
	v.process_mode = Node.PROCESS_MODE_DISABLED
	_run.call_deferred()


func _origin(side: String) -> Vector3:
	var xf := ArmModel.hand_transform(v._hands[side]["disp"].get("arm", {}))
	return xf.origin


func _pad(side: String) -> Vector3:
	return v._pad_of_pose(side, "I", v._hands[side]["disp"])


func _settle() -> int:
	for i in 600:
		v._process(1.0 / 60.0)
		if (v._sim_anim["L"] as Dictionary).is_empty() \
				and (v._sim_anim["R"] as Dictionary).is_empty():
			return i + 1
	return -1


func _case(label: String, key: String, side: String) -> void:
	var k: int = v._find_key(key, side)
	if k < 0:
		print("%s: no key %s on %s" % [label, key, side])
		return
	var w0 := _origin(side)
	var p0 := _pad(side)
	v._sim_press(k, side)
	var frames := _settle()
	var w1 := _origin(side)
	var p1 := _pad(side)
	print("%-22s %s %-6s | wrist moved (%+6.2f %+6.2f %+6.2f) len %5.2f | thumb pad moved (%+6.2f %+6.2f %+6.2f) | %d frames"
		% [label, side, key, w1.x - w0.x, w1.y - w0.y, w1.z - w0.z,
			(w1 - w0).length(), p1.x - p0.x, p1.y - p0.y, p1.z - p0.z, frames])
	# Release and let the hand come home before the next case.
	v._sim_release(k)
	_settle()


func _run() -> void:
	await process_frame
	await process_frame
	print("wrist = the arm transform's origin; a space press should move it ~0")
	for side in ["R", "L"]:
		_case("space (bar)", "пробел", side)
		_case("о (home key, II)", "о", side)
		_case("л (home key, III)", "л", side)
	quit()

