extends SceneTree
## ВРЕМЕННАЯ проба: КРУПНЫЙ вид честной тени поля (3D) у корней пальцев —
## что на самом деле делает силуэт там, где палец входит в ладонь.
## MBT_SIDE=L|R, MBT_PRESS=метка (пусто — покой).
## Кадр /tmp/opencode/root-<side>-<label>.png, 0.25 мм на клетку.

const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")

const POSES := "/work/game/scripts/hands_poses.gd"
const X0 := -45.0
const X1 := 45.0
const Y0 := 66.0
const Y1 := 112.0
const STEP := 0.1
const T0 := -105.0
const T1 := 60.0
const TSTEP := 1.5

var _m = null
var _d := Vector3.BACK


func _initialize() -> void:
	var side := OS.get_environment("MBT_SIDE")
	if side == "":
		side = "R"
	var label := OS.get_environment("MBT_PRESS")
	var flat := _read_flat(side, label)
	if flat.is_empty():
		push_error("нет позы %s '%s'" % [side, label])
		quit(1)
		return
	var pose := _pose_from_flat(flat)
	_m = HandModel.new(1.0, 0.0, pose)
	var W := int(round((X1 - X0) / STEP)) + 1
	var H := int(round((Y1 - Y0) / STEP)) + 1
	var img := Image.create(W, H, false, Image.FORMAT_RGB8)
	for j in H:
		var y := Y1 - float(j) * STEP
		for i in W:
			var x := X0 + float(i) * STEP
			var ins := _inside(x, y)
			img.set_pixel(i, j, Color(0.55, 0.55, 0.55) if ins
				else Color(1, 1, 1))
	# Корни пальцев (MCP) и ось каждого пальца — чтобы видеть, где что.
	for f in HandModel.FINGERS:
		var pts: PackedVector3Array = _m.finger_fk(f, pose["fingers"][f])["pts"]
		for k in 2:
			var a: Vector3 = pts[0].lerp(pts[1], float(k) * 0.5)
			_mark(img, a.x, a.y, Color(0.9, 0.1, 0.1))
	img.save_png("/tmp/opencode/root-%s-%s.png" % [side,
		"rest" if label == "" else label])
	print("root-%s-%s.png %dx%d (0.25 мм/клетка)" % [side,
		"rest" if label == "" else label, W, H])
	# Числом: ширина щели между соседними пальцами на нескольких высотах.
	for f in HandModel.FINGERS:
		var pp: PackedVector3Array = _m.finger_fk(f, pose["fingers"][f])["pts"]
		print("  %s mcp %s pip %s" % [f, str(pp[0]), str(pp[1])])
	for y in [86.0, 90.0, 94.0, 98.0, 102.0]:
		var line := "y=%5.1f:" % y
		for f in HandModel.FINGERS:
			var pts: PackedVector3Array = _m.finger_fk(f, pose["fingers"][f])["pts"]
			var t: float = 0.0
			if absf(pts[1].y - pts[0].y) > 0.001:
				t = (y - pts[0].y) / (pts[1].y - pts[0].y)
			if t < 0.0 or t > 1.0:
				continue
			var cx: float = pts[0].lerp(pts[1], t).x
			var r := 0.0
			# Полуширина силуэта вдоль x на этой высоте.
			var a := cx
			while a > cx - 14.0 and _inside(a, y):
				a -= STEP
			var b := cx
			while b < cx + 14.0 and _inside(b, y):
				b += STEP
			line += "  %s %.1f..%.1f (%.1f)" % [f, a, b, b - a]
		print(line)
	quit(0)


func _mark(img: Image, x: float, y: float, c: Color) -> void:
	var i := int(round((x - X0) / STEP))
	var j := int(round((Y1 - y) / STEP))
	for dj in 2:
		for di in 2:
			if i + di >= 0 and i + di < img.get_width() and j + dj >= 0 \
					and j + dj < img.get_height():
				img.set_pixel(i + di, j + dj, c)


func _inside(x: float, y: float) -> bool:
	var base := Vector3(x, y, 0.0)
	var t := T0
	while t <= T1:
		if _m.field(base + _d * t) <= 0.0:
			return true
		t += TSTEP
	return false


func _pose_from_flat(f: Array) -> Dictionary:
	var p := HandModel.rest_pose()
	var arm := {}
	for j in ArmModel.ALL_JOINTS.size():
		arm[ArmModel.ALL_JOINTS[j]] = float(f[j])
	p["arm"] = arm
	for i in HandModel.FINGERS.size():
		var ray: String = HandModel.FINGERS[i]
		p["fingers"][ray] = {"mcp": float(f[8 + i * 4]),
			"pip": float(f[9 + i * 4]), "dip": float(f[10 + i * 4]),
			"fan": float(f[11 + i * 4])}
	p["thumb_dof"] = 4
	var th := {}
	for j in HandModel.THUMB_JOINTS.size():
		th[HandModel.THUMB_JOINTS[j]] = float(f[24 + j])
	p["thumb"] = th
	return p


func _read_flat(side: String, label: String) -> Array:
	var txt := FileAccess.get_file_as_string(POSES)
	if txt == "":
		return []
	var in_press := false
	var cur := ""
	for raw in txt.split("\n"):
		var ln := raw.strip_edges()
		if ln.begins_with("const HOME"):
			in_press = false
			continue
		if ln.begins_with("const PRESS"):
			in_press = true
			continue
		if not ln.begins_with("\""):
			continue
		var q := ln.find("\":")
		if q < 0:
			continue
		var key := _unesc(ln.substr(1, q - 1))
		var arr := _nums(ln)
		if arr.size() != 29:
			if (key == "L" or key == "R") and ln.contains("{"):
				cur = key
			continue
		if not in_press:
			if key == side and label == "":
				return arr
			continue
		if cur == side and key == label:
			return arr
	return []


func _unesc(s: String) -> String:
	var out := ""
	var i := 0
	while i < s.length():
		var ch := s[i]
		if ch == "\\" and i + 1 < s.length():
			i += 1
			out += s[i]
		else:
			out += ch
		i += 1
	return out


func _nums(s: String) -> Array:
	var i := s.find("[")
	var j := s.find("]")
	if i < 0 or j < 0:
		return []
	var out := []
	for part in s.substr(i + 1, j - i - 1).split(",", false):
		out.append(float(part.strip_edges()))
	return out
