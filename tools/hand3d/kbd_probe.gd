# Checks the real keyboard layout against the game's own board.
extends SceneTree

const Kbd3D := preload("res://kbd3d.gd")

var _fails := 0


func _check(ok: bool, what: String) -> void:
	if ok:
		print("  ok   ", what)
	else:
		_fails += 1
		print("  FAIL ", what)


func _init() -> void:
	var ks := Kbd3D.keys()
	print("keys: ", ks.size(), "  board width: ", Kbd3D.board_w())
	var w := Kbd3D.board_w()
	_check(ks.size() == 60, "60 keys (14+14+13+12+7)")
	var counts := {}
	var bad_side := 0
	var bad_map := 0
	var overlap := 0
	var outside := 0
	for i in ks.size():
		var k: Dictionary = ks[i]
		var r: Rect2 = k["r"]
		counts[k["row"]] = int(counts.get(k["row"], 0)) + 1
		if r.position.x < -w * 0.5 - 0.001 or r.end.x > w * 0.5 + 0.001:
			outside += 1
		if int(k["hand"]) < 0 or String(k["finger"]) == "":
			bad_map += 1
		for j in range(i + 1, ks.size()):
			var o: Dictionary = ks[j]
			if int(o["row"]) != int(k["row"]):
				continue
			var s: Rect2 = o["r"]
			if r.intersects(s, false):
				overlap += 1
	_check(counts == {0: 14, 1: 14, 2: 13, 3: 12, 4: 7},
		"row counts 14/14/13/12/7: " + str(counts))
	_check(outside == 0, "every key inside the board")
	_check(overlap == 0, "no two keys of a row overlap")
	_check(bad_map == 0, "every key has a hand and a finger")

	# Home row: the four fingers of each hand on their own key.
	var home := {"ф": ["V", 0], "ы": ["IV", 0], "в": ["III", 0],
		"а": ["II", 0], "о": ["II", 1], "л": ["III", 1],
		"д": ["IV", 1], "ж": ["V", 1]}
	for s in home:
		var i := Kbd3D.index_of(ks, s)
		var k: Dictionary = ks[i]
		var want: Array = home[s]
		_check(String(k["finger"]) == String(want[0]) and int(k["hand"]) == int(want[1]),
			"%s -> hand %d finger %s" % [s, int(want[1]), String(want[0])])

	# The board's geometry: home row centre at HOME_Y, rows 22.9 mm apart.
	var a: Dictionary = ks[Kbd3D.index_of(ks, "а")]
	var o: Dictionary = ks[Kbd3D.index_of(ks, "о")]
	var ca: Vector2 = (a["r"] as Rect2).get_center()
	var co: Vector2 = (o["r"] as Rect2).get_center()
	print("а centre ", ca, "  о centre ", co,
		"  gap ", co.x - ca.x, " (three pitches = ", 3.0 * Kbd3D.PITCH, ")")
	_check(absf(ca.y - Kbd3D.HOME_Y) < 0.001, "home row centre y = 152")
	_check(absf((co.x - ca.x) - 3.0 * Kbd3D.PITCH) < 0.001,
		"а and о are three centre steps apart")
	var q: Dictionary = ks[Kbd3D.index_of(ks, "й")]
	var z: Dictionary = ks[Kbd3D.index_of(ks, "я")]
	_check(absf((q["r"] as Rect2).get_center().y
		- (a["r"] as Rect2).get_center().y - Kbd3D.ROW_STEP) < 0.001,
		"Q row one step away")
	_check(absf((z["r"] as Rect2).get_center().y
		- (a["r"] as Rect2).get_center().y + Kbd3D.ROW_STEP) < 0.001,
		"Z row one step the other way")

	# Bottom row: the space is one third of the board, the service keys are on
	# their own side.
	var sp: Dictionary = ks[Kbd3D.index_of(ks, "пробел")]
	var spr: Rect2 = sp["r"]
	var unit := (w - 6.0 * Kbd3D.GAP) / 9.0
	print("space width ", spr.size.x, " (three bottom-row units = ",
		3.0 * unit, ")")
	_check(absf(spr.size.x - 3.0 * unit) < 0.001,
		"space is three of the bottom row's nine units")
	var lc: Dictionary = ks[Kbd3D.index_of(ks, "Ctrl", 0)]
	var rc: Dictionary = ks[Kbd3D.index_of(ks, "Ctrl", 1)]
	_check(int(lc["hand"]) == 0 and int(rc["hand"]) == 1,
		"left/right Ctrl belong to the left/right hand")
	var h := Kbd3D.hand_finger("пробел", -1.0)
	var h2 := Kbd3D.hand_finger("пробел", 1.0)
	_check(int(h[0]) == 0 and int(h2[0]) == 1, "space halves choose the thumb")

	# The hit test: every key centre must hit its own key.
	var miss := 0
	for i in ks.size():
		var c: Vector2 = (ks[i]["r"] as Rect2).get_center()
		if Kbd3D.key_at(ks, c) != i:
			miss += 1
	_check(miss == 0, "hit test finds every key by its centre")

	# Typography: the main letters of the home row are the Russian ones.
	var labels := []
	for k in ks:
		labels.append(String(k["s"]))
	_check(labels.has("ё") and labels.has("\\") and labels.has("↵")
		and labels.has("←") and labels.has("ShiftR"),
		"the project's service keys are present")
	print("RESULT: ", "PASS" if _fails == 0 else "FAIL (%d)" % _fails)
	quit(0 if _fails == 0 else 1)
