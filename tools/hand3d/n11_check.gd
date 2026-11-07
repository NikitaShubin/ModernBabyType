# #11 follow-up's two promises, measured (04.11.2026).
#
#   1. The bottom-row price list is GATED: the other rows must stay bit for
#      bit the poses the author approved. The probe solves every key's press
#      twice — approved hierarchy vs the final profile — and compares the
#      whole pose dictionary as text: "non-bottom changed: 0 | bottom
#      changed: 6".
#   2. A release really returns the hand home, including the two paths that
#      are not a plain press->release: a quick tap (press and release in the
#      same instant) and a chord of two fingers on one hand. The gap to the
#      canonical home is printed; it must be 0.0000.
#
#   mbt-godot --headless --path /work/tools/hand3d --script res://n11_check.gd
extends SceneTree

const Kbd3D := preload("res://kbd3d.gd")

var v: Node
var done := false


func _init() -> void:
	v = load("res://board.tscn").instantiate()
	root.add_child(v)
	v.process_mode = Node.PROCESS_MODE_DISABLED


func _step(n := 900) -> void:
	for f in n:
		v._process(1.0 / 60.0)
		var busy := false
		for side in ["L", "R"]:
			if not (v._sim_anim[side] as Dictionary).is_empty():
				busy = true
		if not busy and (v._sim_held as Dictionary).is_empty() \
				and (v._sim_queue as Array).is_empty():
			return


func _gap(side: String) -> float:
	return v._pose_gap(v._hands[side]["disp"], v._hands[side]["home"])


func _cfg(w: Dictionary, p: float) -> void:
	v._sim_bot_w = w.duplicate(true)
	v._sim_bot_prior = p


func _press(i: int, side: String) -> Dictionary:
	var rx := float(v._sim_rest_rx[side])
	var home: Dictionary = (v._sim_rest_home[side] as Dictionary).duplicate(true)
	return v._sim_stroke(side, i, home, rx, v._foreign_rest(side))["press"]


func _process(_dt: float) -> bool:
	if done:
		return true
	done = true
	var picks := []
	for i in v._keys.size():
		var s := String((v._keys[i] as Dictionary)["s"])
		var side := String(v._sim_key_side(i))
		if side == "":
			continue
		picks.append([i, s, side])
	# Old build: gated stop, no weight override.
	_cfg({}, 0.05)
	var old := {}
	for pick in picks:
		old["%s/%s" % [String(pick[2]), String(pick[1])]] = _press(
			int(pick[0]), String(pick[2]))
	# Final build.
	_cfg({"elbow_x": 10.0, "elbow_y": 10.0, "forearm_abd": 10.0}, 2.0)
	var diff := 0
	var bottom_diff := 0
	for pick in picks:
		var key := "%s/%s" % [String(pick[2]), String(pick[1])]
		var a: Dictionary = old[key]
		var b: Dictionary = _press(int(pick[0]), String(pick[2]))
		var bottom := (Kbd3D.ROW_BOTTOM as Array).has(String(pick[1]))
		var same := str(a) == str(b)
		if not same:
			if bottom:
				bottom_diff += 1
			else:
				diff += 1
				print("CHANGED non-bottom %s\n  old %s\n  new %s" % [key, str(a), str(b)])
	print("non-bottom changed: %d | bottom changed: %d" % [diff, bottom_diff])
	# Quick taps on every key and a chord, with the final profile.
	var worst := 0.0
	for pick in picks:
		var s := String(pick[1])
		if s == "пробел":
			continue
		var i := int(pick[0])
		var side := String(pick[2])
		v._sim_press(i, side)
		v._sim_release(i)
		_step()
		var g := _gap(side)
		worst = maxf(worst, g)
		if g > 0.01:
			print("TAP %-2s %-7s gap %7.4f" % [side, s, g])
	# Chord on the right hand: Ctrl + Alt (far bottom keys).
	var ctrl := -1
	var alt := -1
	for pick in picks:
		if String(pick[2]) != "R":
			continue
		if String(pick[1]) == "Ctrl":
			ctrl = int(pick[0])
		if String(pick[1]) == "Alt" and alt < 0:
			alt = int(pick[0])
	if ctrl >= 0 and alt >= 0:
		v._sim_press(ctrl, "R")
		_step(80)
		v._sim_press(alt, "R")
		_step(80)
		v._sim_release(ctrl)
		_step(80)
		v._sim_release(alt)
		_step()
		var g2 := _gap("R")
		worst = maxf(worst, g2)
		print("CHORD Ctrl+Alt R gap %7.4f" % g2)
	print("WORST tap gap %.4f" % worst)
	quit()
	return true
