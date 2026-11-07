# TEMP: the TYPED (sim) path under fast mixed input: does any tap leave the
# hand away from home? Presses land while the previous stroke is still
# flying, taps are released in the same frame (the queue's _sim_tapped), and
# the space bar alternates hands.
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


func _report(tag: String, side: String) -> void:
	var st: Dictionary = v._hands[side]
	print("%-36s gap %8.4f | held %d anim '%s'"
		% [tag, v._pose_gap(st["disp"], st["home"]), v._sim_held.size(),
		String((v._sim_anim[side] as Dictionary).get("kind", ""))])


func _process(_dt: float) -> bool:
	if done:
		return true
	done = true
	var keys := []
	for want in ["н", "г", "ш", "щ", "з", "х", "ъ", "ж", "э", "ю", "б", "т",
			"ь", "1", "9", "0", "-", "=", "пробел"]:
		keys.append(_find(want, ""))
	print("indices ", str(keys))
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261104
	var worst := 0.0
	for round in 3:
		for k in keys:
			var side := String(v._sim_key_side(k))
			if String((v._keys[k] as Dictionary)["s"]) == "пробел":
				side = "L" if v._sim_letter_side != "L" else "R"
			v._sim_press(k, side)
			# a tap released in the same frame, a quick tap, or a hold
			var hold: int = [0, 1, 3, 8, 20, 45][rng.randi() % 6]
			_step(hold)
			v._sim_release(k)
			# the next key may land mid-flight; sometimes let it settle
			_step([2, 6, 30, 240][rng.randi() % 4])
		_step(400)
		for side in ["L", "R"]:
			var g: float = v._pose_gap(v._hands[side]["disp"],
				v._hands[side]["home"])
			worst = maxf(worst, g)
			if g > 0.0001:
				_report("AWAY after round %d %s" % [round, side], side)
	_step(400)
	for side in ["L", "R"]:
		_report("settled %s" % side, side)
		var g: float = v._pose_gap(v._hands[side]["disp"], v._hands[side]["home"])
		worst = maxf(worst, g)
	print("WORST gap over the run: ", worst)
	quit()
	return true
