# TEMP: a MOUSE click in the SIMULATOR (MBT_SIM=1) on the bottom row — the
# keys that have no physical keycode. Goes through the real _input path, not
# through _sim_click_press directly, and checks the hand comes home.
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
				and (side == "" or String(v._sim_key_side(i)) == side):
			return i
	return -1


func _screen(k: int) -> Vector2:
	var c: Vector3 = Kbd3D.centre(v._keys[k] as Dictionary)
	var w: Vector3 = c * float(v.SCALE)
	return v._cam.unproject_position(w)


func _click(k: int, frames: int) -> void:
	var p := _screen(k)
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = p
	v._input(down)
	_step(frames)
	print("   held-mid %-8s key %2d | held %d queue %d | gapL %7.4f gapR %7.4f | pad z %7.2f"
		% [String((v._keys[k] as Dictionary)["s"]), k, v._sim_held.size(),
		v._sim_queue.size(),
		v._pose_gap(v._hands["L"]["disp"], v._hands["L"]["home"]),
		v._pose_gap(v._hands["R"]["disp"], v._hands["R"]["home"]),
		float(v._key_nodes[k].position.z)])
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = p
	v._input(up)


func _report(tag: String, side: String) -> void:
	var st: Dictionary = v._hands[side]
	print("%-38s gap %8.4f | held %d queue %d clicked %d"
		% [tag, v._pose_gap(st["disp"], st["home"]), v._sim_held.size(),
		v._sim_queue.size(), v._sim_click_key])


func _process(_dt: float) -> bool:
	if done:
		return true
	done = true
	print("sim ", v._sim)
	_step(30)
	var cases := [["Ctrl", "L"], ["Win", "L"], ["Alt", "L"], ["Alt", "R"],
		["глобус", "R"], ["Ctrl", "R"], ["пробел", ""]]
	var idx := []
	for pair in cases:
		var k := _find(String(pair[0]), String(pair[1]))
		idx.append(k)
		print("case ", pair[0], " ", pair[1], " -> ", k,
			" screen ", _screen(k) if k >= 0 else Vector2.ZERO)
	for i in cases.size():
		var k := int(idx[i])
		if k < 0:
			continue
		var side := String(v._sim_key_side(k))
		if side == "":
			side = "R"
		_click(k, 20)
		_step(400)
		_report("after click %s %s" % [cases[i][0], cases[i][1]], side)
	# a click during the previous click's flight
	var alt := _find("Alt", "R")
	var glob := _find("глобус", "R")
	_click(alt, 8)
	_click(glob, 8)
	_step(400)
	_report("Alt then глобус, 8 frames apart", "R")
	# a fast click: down and up in the same frame
	var ctrl := _find("Ctrl", "R")
	var p := _screen(ctrl)
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = p
	v._input(down)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = p
	v._input(up)
	_step(400)
	_report("fast click Ctrl R (same frame)", "R")
	# a left click that misses the board must not leave anything held
	var miss := InputEventMouseButton.new()
	miss.button_index = MOUSE_BUTTON_LEFT
	miss.pressed = true
	miss.position = Vector2(1, 1)
	v._input(miss)
	var miss_up := InputEventMouseButton.new()
	miss_up.button_index = MOUSE_BUTTON_LEFT
	miss_up.pressed = false
	miss_up.position = Vector2(1, 1)
	v._input(miss_up)
	_step(400)
	_report("left click off the board", "R")
	_step(300)
	_report("final", "R")
	quit()
	return true
