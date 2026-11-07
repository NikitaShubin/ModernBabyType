# РЕВИЗИЯ СИЛУЭТА КИСТИ (автор 05.11.2026: «со стороны большого пальца
# линия контура, движущаяся к лучезапястному суставу, содержит непонятный
# шишах. В реальной руке такого нет, а у тебя в большинстве поз есть.
# Проведи внимательную ревизию. Исправления — на уровне 3д-модели»).
#
# Меряем ЧЕСТНЫЙ силуэт модели: тень SDF на плоскость доски, то есть
# min по z поля (p = (x, y, z)). Точка (x, y) в силуэте, если хоть при
# какой глубине z тело там есть — ровно то, что видно сверху.
#
# Печатает:
#   1) профиль силуэта со стороны большого пальца (max x при каждом y)
#      и метки бугров (локальный максимум x по y);
#   2) вклад каждого примитива — кто именно вылезает бугром;
#   3) PNG тени /tmp/opencode/shadow-rest.png.
# Запуск (headless):
#   docker run --rm ... mbt-godot --headless --path /work/tools/hand3d \
#     --script res://shadow_probe.gd
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const Sdf := preload("res://sdf.gd")

const X0 := -62.0
const X1 := 66.0
const Y0 := -30.0
const Y1 := 76.0
const Z0 := -30.0
const Z1 := 26.0
const ZSTEP := 2.0

var _m = null
var _frame := 0


func _initialize() -> void:
	_m = HandModel.new(1.0, 0.0)


func _min_z(f: Callable, x: float, y: float) -> float:
	var best := 1.0e9
	var z := Z0
	while z <= Z1:
		best = minf(best, float(f.call(Vector3(x, y, z))))
		z += ZSTEP
	return best


func _shadow(x: float, y: float) -> float:
	return _min_z(Callable(self, "_field_of"), x, y)


func _field_of(p: Vector3) -> float:
	return _m.field(p)


## Правый край тела: скан справа налево, потом уточнение бисекцией.
func _right_edge(f: Callable, y: float) -> float:
	var x := X1
	while x >= X0:
		if _min_z(f, x, y) <= 0.0:
			var lo := x
			var hi := x + 2.0
			for i in 14:
				var mid := (lo + hi) * 0.5
				if _min_z(f, mid, y) <= 0.0:
					lo = mid
				else:
					hi = mid
			return lo
		x -= 2.0
	return X0


func _process(_dt: float) -> bool:
	_frame += 1
	if _frame < 2:
		return false
	# --- картинка тени (1 мм/px, x4) --------------------------------
	var nx := int(X1 - X0) + 1
	var ny := int(Y1 - Y0) + 1
	var sc := 4
	var img := Image.create(nx * sc, ny * sc, false, Image.FORMAT_RGB8)
	img.fill(Color(0.98, 0.96, 0.92))
	for iy in ny:
		var y := Y0 + float(iy)
		for ix in nx:
			var x := X0 + float(ix)
			if _shadow(x, y) <= 0.0:
				for dy in sc:
					for dx in sc:
						img.set_pixel(ix * sc + dx, iy * sc + dy,
							Color(0.1, 0.1, 0.1))
	img.save_png("/tmp/opencode/shadow-rest.png")
	print("PNG /tmp/opencode/shadow-rest.png %dx%d (1 мм/px, x%d)" % [nx, ny, sc])

	# --- профиль ------------------------------------------------------
	print("\nПРОФИЛЬ: y, max x, dx, бугор")
	var prev := NAN
	var rows := []
	var bumps := []
	var y := Y0
	var last_dx := 0.0
	while y <= Y1:
		var x := _right_edge(Callable(self, "_field_of"), y)
		var d := x - prev
		var mark := ""
		if not is_nan(prev) and last_dx > 0.0 and d < -0.3:
			mark = "  <<< БУГОР"
			bumps.append(y)
		rows.append("%6.1f  x=%6.2f  dx=%6.2f%s" % [y, x, d, mark])
		last_dx = d
		prev = x
		y += 1.0
	print("\n".join(rows))
	print("бугры (y): ", bumps)

	# --- примитивы ----------------------------------------------------
	print("\nПРИМИТИВЫ: max x при выбранных y")
	for y2 in [-10.0, -1.5, 0.0, 4.0, 8.0, 12.0, 16.0, 20.0, 24.0, 28.0,
			32.0, 36.0, 40.0, 44.0, 48.0, 52.0, 56.0, 60.0]:
		print("y=%6.1f  " % y2, _edges_all(y2))
	return true


func _edges_all(y: float) -> String:
	var m = _m
	var prims := {}
	prims["wrist"] = func(p: Vector3) -> float:
		return Sdf.capsule_scaled(p, HandModel.WRIST_A, HandModel.WRIST_B,
			27.0, 27.5, Vector3(1, 1, 0.72))
	prims["carpus"] = func(p: Vector3) -> float:
		return Sdf.ellipsoid(p, HandModel.CARPUS_C, HandModel.CARPUS_R)
	prims["dorsal"] = func(p: Vector3) -> float:
		return Sdf.ellipsoid(p, Vector3(33, 56, 4), Vector3(12, 18, 11))
	prims["thenar"] = func(p: Vector3) -> float:
		return Sdf.ellipsoid_oriented(p, m._thenar_c, HandModel.THENAR_R,
			m._thenar_ax[0], m._thenar_ax[1], m._thenar_ax[2])
	prims["hypoth"] = func(p: Vector3) -> float:
		return Sdf.ellipsoid(p, HandModel.HYPOTH_C, HandModel.HYPOTH_R)
	prims["thumb_mc"] = func(p: Vector3) -> float:
		return Sdf.cone(p, m._thumb_pts[0], m._thumb_pts[1],
			m._thumb_r[0], m._thumb_r[1])
	prims["thumb_p"] = func(p: Vector3) -> float:
		return Sdf.cone(p, m._thumb_pts[1], m._thumb_pts[2],
			m._thumb_r[1], m._thumb_r[2])
	prims["palm"] = func(p: Vector3) -> float:
		var d := 1.0e9
		for c in m._palm_cones:
			d = minf(d, Sdf.capsule_scaled(p, c[0], c[1], c[2], c[3],
				Vector3(1, 1, 1.12)))
		return d
	var out := []
	for k in prims.keys():
		var e := _right_edge(prims[k], y)
		out.append("%s=%6.1f" % [k, e])
	return " ".join(out)
