extends SceneTree
## ПРОБА: наложить контур ИГРЫ (пиксели доски) на честную тень поля.
## Нужна, чтобы числом и глазами сверить: ладонь + ленты пальцев дают ту
## же границу, что и тень модели вдоль мировой z.
##
## Контур игры лежит в /tmp/opencode/outline-L-px.txt (game/tests/
## hand_px_dump.gd): строка MAP, строка OFF, дальше "x,y" в пикселях.
## Обратный ход: пиксели → мир → система кисти (xf⁻¹) → растер.
## Кадры: /tmp/opencode/shadow_overlay.png, .log.

const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")

const HOME := [-20.0000, -10.0000, 0.0000, 0.0000, 34.0000, -83.8789,
	45.6444, -49.0000, 38.0315, 33.9876, 14.0965, -12.2396, 27.5328,
	55.4005, 28.8211, -7.2805, 23.6516, 63.6973, 34.8851, -2.9139,
	33.9503, 42.4299, 19.5347, 0.5225, 4.1371, -9.0000, -10.0000,
	21.3197, 0.7834]

const POSES := "/work/game/scripts/hands_poses.gd"
const SRC := "/tmp/opencode/outline-%s-px.txt"
const OUT_PNG := "/tmp/opencode/shadow_overlay-%s.png"
const OUT_LOG := "/tmp/opencode/shadow_overlay-%s.log"

const X0 := -70.0
const X1 := 70.0
const Y0 := -60.0
const Y1 := 175.0
const STEP := 1.0
const T0 := -105.0
const T1 := 60.0
const TSTEP := 2.5

var _m = null
var _d := Vector3.BACK
var _xf := Transform3D()


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


func _inside(x: float, y: float) -> bool:
	var base := Vector3(x, y, 0.0)
	var t := T0
	while t <= T1:
		if _m.field(base + _d * t) <= 0.0:
			return true
		t += TSTEP
	return false


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
			# "L": { — начало раздела нажатий этой руки.
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


func _initialize() -> void:
	var side := OS.get_environment("MBT_SIDE")
	if side == "":
		side = "L"
	var label := OS.get_environment("MBT_PRESS")
	var flat := _read_flat(side, label)
	if flat.is_empty():
		push_error("нет позы %s / '%s'" % [side, label])
		quit(1)
		return
	var pose := _pose_from_flat(flat)
	print("поза %s '%s': II %.1f/%.1f/%.1f  V %.1f/%.1f/%.1f" % [side, label,
		float(flat[8]), float(flat[9]), float(flat[10]),
		float(flat[20]), float(flat[21]), float(flat[22])])
	_m = HandModel.new(1.0, 0.0, pose)
	_xf = ArmModel.hand_transform(pose["arm"])
	_d = Vector3.BACK   # та же ось, что у запекания: локальная z кисти
	var tag := "%s-%s" % [side, "rest" if label == "" else label]
	var src := SRC % side

	var txt := FileAccess.get_file_as_string(src)
	if txt == "":
		push_error("нет %s" % SRC)
		quit(1)
		return
	var map := []
	var off := Vector2.ZERO
	var poly := PackedVector2Array()
	for raw in txt.split("\n"):
		var ln := raw.strip_edges()
		if ln == "":
			continue
		if ln.begins_with("MAP "):
			for v in ln.substr(4).split(" "):
				map.append(float(v))
			continue
		if ln.begins_with("OFF "):
			var o := ln.substr(4).split(" ")
			off = Vector2(float(o[0]), float(o[1]))
			continue
		var xy := ln.split(",")
		poly.append(Vector2(float(xy[0]), float(xy[1])))
	if map.size() < 6 or poly.size() < 3:
		push_error("плохой ввод")
		quit(1)
		return
	var sx := float(map[0])
	var sy := float(map[1])
	var ox := float(map[2])
	var oy := float(map[3])
	var home_y := float(map[4])
	var root_x := float(map[5])

	# Пиксели → система кисти модели. Обратный ход — 2×2, а НЕ полный
	# обратный xf: игра берёт локальную точку (x, y, 0), крутит её xf и
	# ОТБРАСЫВАЕТ z. Полный обратный xf дал бы сдвиг на z-поворот кисти
	# (ловлено: контур «уезжал» на 10 мм вниз).
	var ax := Vector2(_xf.basis.x.x, _xf.basis.x.y)
	var ay := Vector2(_xf.basis.y.x, _xf.basis.y.y)
	var det := ax.x * ay.y - ax.y * ay.x
	var local := PackedVector2Array()
	var sgn := -1.0 if side == "R" else 1.0
	for p in poly:
		var q: Vector2 = p - off
		var wx := sgn * ((q.x - ox) / sx - root_x)
		var wy := home_y - (q.y - oy) / sy
		var dx := wx - _xf.origin.x
		var dy := wy - _xf.origin.y
		local.append(Vector2((dx * ay.y - dy * ay.x) / det,
			(dy * ax.x - dx * ax.y) / det))

	var W := int(round((X1 - X0) / STEP)) + 1
	var H := int(round((Y1 - Y0) / STEP)) + 1
	var lx0 := INF
	var lx1 := -INF
	var ly0 := INF
	var ly1 := -INF
	for q in local:
		lx0 = minf(lx0, q.x)
		lx1 = maxf(lx1, q.x)
		ly0 = minf(ly0, q.y)
		ly1 = maxf(ly1, q.y)
	print("контур в системе кисти: x %.1f..%.1f y %.1f..%.1f" % [lx0, lx1, ly0, ly1])
	print("off %s  xf.origin %s  root_x %.2f" % [str(off), str(_xf.origin), root_x])
	print("raw0 %s  local0 %s" % [str(poly[0]), str(local[0])])
	var chk := _xf * Vector3(local[0].x, local[0].y, 0.0)
	var chk_wx := (root_x - chk.x) if side == "R" else (root_x + chk.x)
	var chk_px := Vector2(float(ox) + chk_wx * sx,
		float(oy) - (chk.y - float(home_y)) * sy) + off
	print("прямой ход: %s" % str(chk_px))
	var imax := 0
	var imin := 0
	for k in local.size():
		if local[k].x > local[imax].x:
			imax = k
		if local[k].x < local[imin].x:
			imin = k
	print("max x точка %d %s (px %s); min x точка %d %s (px %s)" % [imax,
		str(local[imax]), str(poly[imax]), imin, str(local[imin]), str(poly[imin])])
	var img := Image.create(W, H, false, Image.FORMAT_RGB8)
	var log := PackedStringArray()
	log.append("# тень поля (серый) и контур игры (красный)")
	var diff := 0
	var inside_n := 0
	for j in H:
		var y := Y1 - float(j) * STEP
		for i in W:
			var x := X0 + float(i) * STEP
			var ins := _inside(x, y)
			if ins:
				inside_n += 1
			img.set_pixel(i, j, Color(0.82, 0.82, 0.82) if ins
				else Color(1, 1, 1))
	# Контур игры — в тот же растер.
	for k in local.size():
		var a := local[k]
		var b := local[(k + 1) % local.size()]
		var n := int(ceil(maxf(absf(b.x - a.x), absf(b.y - a.y)) / STEP)) + 1
		for s in n:
			var t := float(s) / float(n)
			var q := a.lerp(b, t)
			var i := int(round((q.x - X0) / STEP))
			var j := int(round((Y1 - q.y) / STEP))
			if i >= 0 and i < W and j >= 0 and j < H:
				img.set_pixel(i, j, Color(0.85, 0.05, 0.05))
	img.save_png(OUT_PNG % tag)
	print("растер %dx%d, тень %d клеток, контур %d точек" % [W, H,
		inside_n, local.size()])
	var f := FileAccess.open(OUT_LOG % tag, FileAccess.WRITE)
	f.store_string("\n".join(log))
	f.close()
	quit(0)
