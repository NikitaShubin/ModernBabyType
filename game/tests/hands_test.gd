extends SceneTree
## КИСТИ НАД ДОСКОЙ — ПРОЕКЦИЯ 3D-МОДЕЛИ ИССЛЕДОВАНИЯ (tools/hand3d).
##
## Автор 04.11.2026: «это должны быть те самые руки из 3д», а 05.11.2026
## назвал два дефекта проекции: короткие предплечья-обрубки и «шишах» на
## стороне большого пальца у запястья. Оба чинились НА УРОВНЕ МОДЕЛИ,
## поэтому тест держит именно унаследованное:
##
##   1. Ладонь с предплечьем — ЗАПЕЧЁННЫЙ полярный контур поля
##      (hands_shape.gd), предплечье уходит ЗА КРАЙ ЭКРАНА в любой позе:
##      контур пересекает границу экрана ровно дважды, а не заканчивается
##      обрубком внутри. Радиусы гладкие (шишах — это скачок радиуса) и
##      ДОТЯГИВАЮТСЯ вдоль каждого пальца до корня: 06.11.2026 автор
##      увидел залом там, где палец переходит в ладонь, — контур печётся
##      уже с заготовками корней (`HandModel.field_roots`).
##   2. Пальцы — ленты из FK модели: ширина ленты = 2·радиус кожи,
##      все суставы внутри, соседние пальцы не слипаются в рукавицу,
##      подушечки стоят на своих клавишах в КАЖДОЙ запечённой позе.
##   3. Зеркало: правая кисть — отражение левой (ось — дом-группа «ф»↔«ж»).
##   4. Демонстрация подсказки — чистая фаза (подъём/выдержка/спад/пауза).
##
## Каждая проверка сформулирована так, чтобы сломанное правило краснело
## (правило репозитория: тест, который никогда не падает, бесполезен).
##
## Headless картинку не рисует — все меры ЧИСТЫЕ и меряются числом.
## Окно ставим руками: по умолчанию 64×64, доска на нём вырожденная.

const KB_FRAC := 0.46
const Shape := preload("res://scripts/hands_shape.gd")

## Экраны, на которых кисти обязаны вести себя одинаково: телефон
## портретом, телефон альбомом и десктопное окно.
const SCREENS := [[540.0, 1140.0], [1140.0, 540.0], [1600.0, 1000.0]]


func _initialize() -> void:
	main_window_setup()
	_hands_test()
	_painter = Painter.new()
	_painter.bs = _board_at(540.0, 1140.0)
	_painter.rest = Hands.rest_both(_painter.bs)
	root.add_child(_painter)


var _painter: Painter = null
var _frame := 0


## Рисование проверяется КАДРОМ (см. Painter): ждём его _draw и только
## потом судим кэш.
func _process(_dt: float) -> bool:
	_frame += 1
	if _painter == null or not _painter.done:
		if _frame > 30:
			_check(false, "draw_both draws within 30 frames")
			quit(1)
			return true
		return false
	_check(_painter.keys1.size() == 1, "draw_both fills the contour cache")
	_check(_painter.keys1 == _painter.keys2,
		"draw_both reuses the cache key")
	_check(_painter.keys3.size() == 1,
		"a new press replaces the cached pose")
	if _fails == 0:
		print("HANDS_TEST: PASS")
	quit(0 if _fails == 0 else 1)
	return true


var _fails := 0


func main_window_setup() -> void:
	DisplayServer.window_set_size(Vector2i(540, 1140))
	root.size = Vector2i(540, 1140)


func _check(ok: bool, msg: String) -> void:
	if not ok:
		print("HANDS: FAIL: ", msg)
		_fails += 1


## Доска игры при данном окне: та же арифметика, что у main/hands_sandbox.
func _board_at(w: float, h: float) -> Array:
	var m := 16.0 + Ui.bottom_inset(h)
	var hmax := maxf(160.0, (h - m) * KB_FRAC)
	var bw := w - 32.0
	var bh := Kbd.height_for(bw)
	if bh > hmax:
		bw = clampf(Kbd.width_for(hmax), 240.0, w - 32.0)
		bh = Kbd.height_for(bw)
	return Kbd.buttons(Rect2((w - bw) * 0.5, h - bh - m, bw, bh),
		false, false)


func _hands_test() -> void:
	var bs: Array = _board_at(540.0, 1140.0)
	_check(Hands.pitch_of(bs) > 0.0, "pitch from buttons is positive")
	_map_covers_board(bs)
	_map_spot_checks(bs)
	_shape_data_checks()
	for s in SCREENS:
		var sc: Array = s as Array
		var w := float(sc[0])
		var hh := float(sc[1])
		var board := _board_at(w, hh)
		var tag := "%dx%d" % [int(w), int(hh)]
		_check(Hands.pitch_of(board) > 0.0, "pitch is positive at " + tag)
		_palm_checks(board, Vector2(w, hh), tag)
		_finger_checks(board, tag)
		_mirror_checks(board, tag)
		_space_checks(board, tag)
		_tap_checks(board, tag)
		_multi_checks(board, Vector2(w, hh), tag)
	_press_checks(bs)
	_idle_checks()
	_hint_checks(bs)
	_outline_checks(bs)
	_one_object_checks(bs)
	_tint_checks(bs)


## ---------------------------------------------------------------- карта

## Каждая клавиша ДОСКИ имеет палец: карта не может отстать от
## раскладки — новая клавиша без пальца должна ломать тест.
func _map_covers_board(bs: Array) -> void:
	for b in bs:
		var s := String(b["s"])
		var f := Hands.finger_of(s)
		_check(f[0] >= 0,
			"key '%s' has a finger in the map (%s)" % [s, str(Hands.finger_of(s))])


## Точечные правила карты: дом-ряд, крайние колонки, служебные.
func _map_spot_checks(bs: Array) -> void:
	_check(Hands.finger_of("ф") == [Hands.LEFT, Hands.PINKY], "ф is left pinky")
	_check(Hands.finger_of("ы") == [Hands.LEFT, Hands.RING], "ы is left ring")
	_check(Hands.finger_of("в") == [Hands.LEFT, Hands.MIDDLE], "в is left middle")
	_check(Hands.finger_of("а") == [Hands.LEFT, Hands.INDEX], "а is left index")
	_check(Hands.finger_of("и") == [Hands.LEFT, Hands.INDEX],
		"и is left index (key b is under the LEFT palm)")
	_check(Hands.finger_of("о") == [Hands.RIGHT, Hands.INDEX], "о is right index")
	_check(Hands.finger_of("л") == [Hands.RIGHT, Hands.MIDDLE], "л is right middle")
	_check(Hands.finger_of("б") == [Hands.RIGHT, Hands.MIDDLE],
		"б is right middle (key , is under the RIGHT palm)")
	_check(Hands.finger_of("ъ") == [Hands.RIGHT, Hands.PINKY], "ъ is right pinky")
	_check(Hands.finger_of("Shift") == [Hands.LEFT, Hands.PINKY],
		"left shift is left pinky")
	_check(Hands.finger_of("ShiftR") == [Hands.RIGHT, Hands.PINKY],
		"right shift is right pinky")
	_check(Hands.finger_of("↵") == [Hands.RIGHT, Hands.PINKY],
		"enter is right pinky")
	_check(Hands.finger_of("←") == [Hands.RIGHT, Hands.PINKY],
		"backspace is right pinky")
	_check(Hands.finger_of("4") == [Hands.LEFT, Hands.INDEX], "4 is left index")
	_check(Hands.finger_of("5") == [Hands.LEFT, Hands.INDEX], "5 is left index")
	_check(Hands.finger_of("6") == [Hands.RIGHT, Hands.INDEX], "6 is right index")
	_check(Hands.finger_of("7") == [Hands.RIGHT, Hands.INDEX], "7 is right index")
	_check(Hands.finger_of("пробел:Л") == [Hands.LEFT, Hands.THUMB],
		"left space half is the left thumb")
	_check(Hands.finger_of("пробел:П") == [Hands.RIGHT, Hands.THUMB],
		"right space half is the right thumb")
	# key_label — подпись ДОСКИ. Кириллица остаётся собой (иначе
	# двусторонняя RU_EN уводит «м» в латинскую «v», и поза нажатия
	# ищется не там — ловил combo_test 05.11.2026).
	_check(Hands.key_label("м") == "м", "key_label keeps a Cyrillic letter")
	_check(Hands.key_label("М") == "м", "key_label lowercases a capital")
	_check(Hands.key_label("v") == "м", "key_label maps a Latin key to its Russian pair")
	_check(Hands.key_label("Shift") == "Shift", "key_label keeps a service label")
	_check(Hands.key_label("пробел:Л") == "пробел:Л",
		"key_label keeps the space half")
	_check(Hands.key_label(" ") == " ", "key_label keeps the bare space")


## ------------------------------------------------------- данные запекания

## Запечённый контур обязан покрывать ВСЕ позы и все позы — целиком:
## пропавшая поза иначе тихо откатывалась бы к покою.
func _shape_data_checks() -> void:
	_check(Shape.N == 256, "baked contour has 256 rays (%d)" % Shape.N)
	_check((Shape.CENTER as Vector2).is_finite(), "baked centre is finite")
	for side in ["L", "R"]:
		var table: Dictionary = Shape.RADII[side] as Dictionary
		var presses: Dictionary = HandsPoses.PRESS[side] as Dictionary
		_check(table.size() == presses.size() + 1,
			"%s: baked %d poses for %d presses + rest" % [side,
				table.size(), presses.size()])
		_check(table.has(""), "%s: rest pose is baked" % side)
		var bad := 0
		var worst := 0.0
		var bumps := 0
		var bump_pose := ""
		var jumps := 0
		var jump_pose := ""
		var worst_jump := 0.0
		var roots := 0
		var root_pose := ""
		var knuckles := 0
		var knuckle_pose := ""
		var knuckle_worst := -999.0
		var knuckle_ray := ""
		var narrows := 0
		var narrow_pose := ""
		var narrow_worst := 999.0
		var narrow_ray := ""
		var joints_out := 0
		var joints_pose := ""
		for k in table.keys():
			var a: Array = table[k] as Array
			if a.size() != Shape.N:
				bad += 1
				continue
			for v in a:
				var f := float(v)
				if not is_finite(f) or f <= 0.0:
					bad += 1
				worst = maxf(worst, f)
			var flat: Array = HandsPoses.HOME[side] as Array
			if String(k) != "":
				flat = presses[k] as Array
			var rule := _palm_rule(a, flat)
			if int(rule["bumps"]) > 0:
				bumps += 1
				if bump_pose == "":
					bump_pose = String(k)
			if int(rule["jumps"]) > 0:
				jumps += 1
				if jump_pose == "":
					jump_pose = String(k)
			worst_jump = maxf(worst_jump, float(rule["worst"]))
			if int(rule["roots"]) > 0:
				roots += 1
				if root_pose == "":
					root_pose = String(k)
			if int(rule["knuckle"]) > 0:
				knuckles += 1
				if knuckle_pose == "":
					knuckle_pose = String(k)
			if float(rule["knuckle_worst"]) > knuckle_worst:
				knuckle_worst = float(rule["knuckle_worst"])
				knuckle_ray = String(rule["knuckle_ray"])
			if int(rule["narrow"]) > 0:
				narrows += 1
				if narrow_pose == "":
					narrow_pose = String(k)
			if float(rule["narrow_worst"]) < narrow_worst:
				narrow_worst = float(rule["narrow_worst"])
				narrow_ray = String(rule["narrow_ray"])
			if int(rule["joints"]) > 0:
				joints_out += int(rule["joints"])
				if joints_pose == "":
					joints_pose = String(k)
		_check(bumps == 0,
			"%s: the visible palm is smooth in every baked pose (%d poses, e.g. '%s')"
			% [side, bumps, bump_pose])
		_check(jumps == 0,
			"%s: the visible palm has no steps (worst %.1f mm, %d poses, e.g. '%s')"
			% [side, worst_jump, jumps, jump_pose])
		_check(roots == 0,
			"%s: the palm reaches into every finger root in every pose (%d poses, e.g. '%s')"
			% [side, roots, root_pose])
		var kw := "none exposed"
		if knuckle_worst > -900.0:
			kw = "%+.2f mm on %s" % [knuckle_worst, knuckle_ray]
		var nw := "%+.2f mm on %s" % [narrow_worst, narrow_ray]
		_check(knuckles == 0,
			"%s: no knuckle is wider than its finger (worst visible %s, %d poses, e.g. '%s')"
			% [side, kw, knuckles, knuckle_pose])
		_check(narrows == 0,
			"%s: the palm is never narrower than its finger at the knuckle (worst %s, %d poses, e.g. '%s')"
			% [side, nw, narrows, narrow_pose])
		_check(joints_out == 0,
			"%s: every finger joint stays inside the drawn hand (%d outside, e.g. '%s')"
			% [side, joints_out, joints_pose])
		_check(bad == 0, "%s: every baked ray is a positive number (%d bad)"
			% [side, bad])
		_check(worst > 300.0,
			"%s: the forearm reaches far past the wrist (%.0f mm)" % [side, worst])


## ------------------------------------------------------- ладонь и предплечье

## КОРЕНЬ ПАЛЬЦА В КОНТУРЕ ЛАДОНИ (автор 06.11.2026: «на бэкспейсе контур
## там, где палец переходит в ладонь, имеет неестественный изгиб»).
##
## Причина — стык двух мер: ладонь печётся из поля БЕЗ пальцев, пальцы
## рисуются лентами, и жёсткое объединение (Geometry2D.merge_polygons)
## оставляло на пересечении острый залом. Правка живёт В ПОЛЕ —
## `HandModel.field_roots()`: контур ладони печётся уже с заготовками
## первых 13 мм каждого пальца. Здесь держатся ТРИ СЛЕДСТВИЯ правки, все
## меряются числом:
##
##   1. ГДЕ КОНТУР ВИДЕН (луч не накрыт лентой пальца) — он гладкий:
##      нет шага > 8 мм и нет местного выступа/вмятины > 1.5 мм. Под
##      лентой радиуса не видно, и заготовка корня там законно торчит:
##      она лежит ВНУТРИ ленты (те же оси и радиусы), поэтому силуэт
##      пальца не расширяет — только скругляет его основание.
##   2. Контур ДОТЯГИВАЕТСЯ вдоль каждого пальца до конца заготовки.
##      Тогда лента продолжает его касательной, а не пересекает под
##      углом. Сними заготовки — краснеет каждая поза (проверено: на
##      прежних данных 108 из 108).
##   3. КОСТЯШКА НЕ ШИРЕ СВОЕГО ПАЛЬЦА (автор 07.11.2026: «у основания
##      мизинца костяшка слишком выпирает даже в покое»). Головка пясти
##      в модели несла ОДИН радиус на все лучи (10.4 мм), а кожа мизинца
##      — 8.6: ладонь у самого стыка была на 1.8 мм шире пальца, и
##      силуэт получал бугор. Плюс фаска smin(6) выносила поверхность
##      ещё на 1.5 мм. Теперь радиус головки — кожа СВОЕГО пальца, а
##      объединение жёсткое: ладонь и заготовка делят ОДНУ сферу в
##      костяшке. Здесь это держится с двух сторон: видимый выступ
##      (луч не накрыт ничьей лентой) ≤ 0.5 мм и ладонь не УЖЕ пальца
##      (расстояние от головки до контура ≥ радиуса кожи − 0.5 мм).
##      Плюс каждый сустав каждого пальца обязан лежать ВНУТРИ
##      нарисованной кисти — иначе кисть «костлявая».
const ROOT_STUB := 13.0
## Зона корня вокруг оси пальца и допуск выступа, мм.
const KNUCKLE_ZONE := 14.0
const KNUCKLE_TOL := 0.5


func _palm_rule(radii: Array, flat: Array) -> Dictionary:
	var n := radii.size()
	var bands := _pose_bands(flat)
	var vis := []
	vis.resize(n)
	for i in n:
		vis[i] = not _under_band(_ray_pt(radii, i), bands)
	var jumps := 0
	var worst := 0.0
	for i in n:
		if not vis[i] or not vis[(i + 1) % n]:
			continue
		var b := float(radii[i])
		var c := float(radii[(i + 1) % n])
		if maxf(b, c) >= 95.0:
			continue
		worst = maxf(worst, absf(b - c))
		if absf(b - c) > 8.0:
			jumps += 1
	var bumps := 0
	for i in n:
		if not vis[i] or not vis[(i - 1 + n) % n] or not vis[(i + 1) % n]:
			continue
		var a := float(radii[(i - 1 + n) % n])
		var b := float(radii[i])
		var c := float(radii[(i + 1) % n])
		if maxf(maxf(a, b), c) >= 95.0:
			continue
		if (b > a + 1.5 and b > c + 1.5) or (b < a - 1.5 and b < c - 1.5):
			bumps += 1
	var poly := _palm_mm(radii)
	var roots := 0
	var knuckle := 0
	var knuckle_worst := -999.0
	var knuckle_ray := ""
	var narrow := 0
	var narrow_worst := 999.0
	var narrow_ray := ""
	var joints := 0
	for b in bands:
		var bd: Dictionary = b as Dictionary
		var pts: PackedVector3Array = bd["pts"] as PackedVector3Array
		var rs: Array = bd["rs"] as Array
		var ray := String(bd["ray"])
		if not _stub_inside(poly, bd):
			roots += 1
		# Костяшка: контур ладони в зоне корня не выходит за ленту пальца.
		var mcp := Vector2(pts[0].x, pts[0].y)
		var axis := (mcp - Shape.CENTER).angle()
		for i in n:
			var a := TAU * float(i) / float(n)
			if absf(wrapf(a - axis, -PI, PI)) > deg_to_rad(KNUCKLE_ZONE):
				continue
			if not vis[i]:
				continue
			var rb := _band_r(Vector2(cos(a), sin(a)), pts, rs)
			if rb <= 0.0:
				continue
			var lip := float(radii[i]) - rb
			if lip > knuckle_worst:
				knuckle_worst = lip
				knuckle_ray = ray
			if lip > KNUCKLE_TOL:
				knuckle += 1
		# Обратная сторона: ладонь в костяшке не УЖЕ своего пальца, иначе
		# основание ленты торчит из ладони и на стыке залом.
		var gap := _poly_margin(poly, mcp) - float(rs[0])
		if gap < narrow_worst:
			narrow_worst = gap
			narrow_ray = ray
		if gap < -KNUCKLE_TOL:
			narrow += 1
		# Сустав внутри нарисованной кисти с запасом кожи.
		for j in pts.size():
			var q := Vector2(pts[j].x, pts[j].y)
			if not Geometry2D.is_point_in_polygon(q, poly) \
					and not _under_band(q, bands, -1.0):
				joints += 1
	return {"jumps": jumps, "worst": worst, "bumps": bumps, "roots": roots,
		"knuckle": knuckle, "knuckle_worst": knuckle_worst,
		"knuckle_ray": knuckle_ray, "narrow": narrow,
		"narrow_worst": narrow_worst, "narrow_ray": narrow_ray,
		"joints": joints}


func _ray_pt(radii: Array, i: int) -> Vector2:
	var c: Vector2 = Shape.CENTER
	var a := TAU * float(i) / float(radii.size())
	return c + Vector2(cos(a), sin(a)) * float(radii[i])


func _palm_mm(radii: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(radii.size())
	for i in radii.size():
		out[i] = _ray_pt(radii, i)
	return out


## Цепь каждого пальца в СИСТЕМЕ КИСТИ — той же, в которой запечена ладонь
## (ладони игра кладёт `xf * (x, y, 0)`, ленты — `xf * pts`).
func _pose_bands(flat: Array) -> Array:
	var out := []
	for ray in Hands3D.FINGERS:
		var pts := Hands3D.finger_fk(ray, Hands3D.finger_angles(flat, ray))
		out.append({"pts": pts, "rs": Hands3D.SKIN_R[ray] as Array, "ray": ray})
	return out


## Точка накрыта лентой пальца: расстояние до цепи в плоскости xy минус
## радиус кожи (лента — объединение тех же усечённых конусов, и её
## проекция вдоль локальной z есть ровно эта капсула).
func _under_band(q: Vector2, bands: Array, pad: float = 0.5) -> bool:
	for b in bands:
		var d: Dictionary = b as Dictionary
		var pts: PackedVector3Array = d["pts"] as PackedVector3Array
		var rs: Array = d["rs"] as Array
		for i in 3:
			var a := Vector2(pts[i].x, pts[i].y)
			var z := Vector2(pts[i + 1].x, pts[i + 1].y)
			var az := z - a
			var t := 0.0
			if az.length_squared() > 0.000001:
				t = clampf((q - a).dot(az) / az.length_squared(), 0.0, 1.0)
			var r := lerpf(float(rs[i]), float(rs[i + 1]), t)
			if q.distance_to(a + az * t) <= r + pad:
				return true
	return false


## Радиус ленты пальца по лучу из центра полярной меры. 0 — луч проходит
## мимо ленты (или выходит через торец, а не через бок первого сегмента:
## там ладонь законно шире, это не костяшка).
func _band_r(dir: Vector2, pts: PackedVector3Array, rs: Array) -> float:
	var r := 0.0
	var entered := false
	var prev := 0.0
	var hit := -1.0
	while r <= 440.0:
		var inside := _band_d(Shape.CENTER + dir * r, pts, rs) <= 0.0
		if not entered:
			if inside:
				entered = true
			r += 2.5
			continue
		if not inside:
			hit = r
			break
		prev = r
		r += 2.5
	if hit < 0.0:
		return 0.0
	var lo := prev
	var hi := hit
	for i in 10:
		var mid := (lo + hi) * 0.5
		if _band_d(Shape.CENTER + dir * mid, pts, rs) <= 0.0:
			lo = mid
		else:
			hi = mid
	var q := Shape.CENTER + dir * lo
	var a := Vector2(pts[0].x, pts[0].y)
	var ab := Vector2(pts[1].x, pts[1].y) - a
	var t := (q - a).dot(ab) / maxf(ab.length_squared(), 0.000001)
	if t < 0.15 or t > 0.95:
		return 0.0
	return lo


func _band_d(q: Vector2, pts: PackedVector3Array, rs: Array) -> float:
	var best := 1.0e9
	for i in 3:
		var a := Vector2(pts[i].x, pts[i].y)
		var b := Vector2(pts[i + 1].x, pts[i + 1].y)
		var ab := b - a
		var t := 0.0
		if ab.length_squared() > 0.000001:
			t = clampf((q - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		var r := lerpf(float(rs[i]), float(rs[i + 1]), t)
		best = minf(best, q.distance_to(a + ab * t) - r)
	return best


## Расстояние от точки до ближайшего ребра контура — «полуширина» ладони
## в самом узком направлении от этой точки.
func _poly_margin(poly: PackedVector2Array, q: Vector2) -> float:
	var best := 1.0e9
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		var ab := b - a
		var t := 0.0
		if ab.length_squared() > 0.000001:
			t = clampf((q - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		best = minf(best, q.distance_to(a + ab * t))
	return best


## Заготовка корня пальца лежит внутри контура ладони — по ОСИ пальца.
##
## Почему по оси, а не по бокам: контур ладони снимается с поля лучом и
## берёт ПЕРВЫЙ выход (bake_outline.gd `_ray`), потому что впадина между
## пальцами — граница, а не провал. Из-за этого «карман» между двумя
## соседними корнями в полярную меру не попадает и не должен: его всё
## равно накрывает лента пальца. Ось же пальца обязана быть внутри
## контура при любой позе — иначе лента начинается вне ладони, и на
## стыке появляется залом (замерено на прежних данных: все четыре
## пальца во всех 108 позах, на новых — ни одного).
func _stub_inside(poly: PackedVector2Array, b: Dictionary) -> bool:
	var pts: PackedVector3Array = b["pts"] as PackedVector3Array
	var a := Vector2(pts[0].x, pts[0].y)
	var tip := Vector2(pts[1].x, pts[1].y)
	var seg := tip - a
	var l := seg.length()
	if l < 0.001:
		return true
	var k := clampf(ROOT_STUB / l, 0.0, 1.0)
	for j in 4:
		var q := a + seg * (k * float(j) / 3.0)
		if not Geometry2D.is_point_in_polygon(q, poly):
			print("  ROOT %s: %.1f,%.1f is outside the palm (mcp %.1f,%.1f, pip %.1f,%.1f)"
				% [str(b["ray"]), q.x, q.y, a.x, a.y, tip.x, tip.y])
			return false
	return true


## Ладонь с предплечьем: гладкие радиусы, кисть уходит ЗА КРАЙ экрана,
## подушечки покоя стоят на дом-клавишах.
func _palm_checks(bs: Array, view: Vector2, tag: String) -> void:
	var pitch := Hands.pitch_of(bs)
	var rest := Hands.rest_both(bs)
	_check(not rest.is_empty(), tag + ": rest pose is built")
	if rest.is_empty():
		return
	var map: Dictionary = rest["map"] as Dictionary
	_check(not map.is_empty(), tag + ": board map is measured")
	for h in [Hands.LEFT, Hands.RIGHT]:
		var side := Hands.side_name(h)
		var radii := Hands.shape_radii(h, {})
		_check(radii.size() == Shape.N,
			"%s %s: rest contour has 256 radii (%d)" % [tag, side, radii.size()])
		# ШИШАХ — это ЛОКАЛЬНЫЙ выступ: радиус вырос и тут же упал (или
		# наоборот — вмятина). Меряется ТОЛЬКО ВИДИМАЯ часть контура: под
		# лентой пальца радиуса не видно, и заготовка корня там законно
		# торчит наружу (см. _palm_rule). Обрыв к предплечью законный — там
		# стенка трубы почти радиальна, и мерить его гладкостью бессмысленно.
		var st := Hands.pose_of(bs, h, rest, {})
		var flat: Array = st["flat"] as Array
		var rule := _palm_rule(radii, flat)
		_check(int(rule["jumps"]) == 0,
			"%s %s: the visible palm has no steps (worst %.1f mm, %d)"
			% [tag, side, float(rule["worst"]), int(rule["jumps"])])
		_check(int(rule["bumps"]) == 0,
			"%s %s: no bump or notch on the visible palm (%d)"
			% [tag, side, int(rule["bumps"])])
		# КОРЕНЬ ПАЛЬЦА: контур ладони обязан дорасти вдоль пальца до
		# конца заготовки — тогда лента продолжает его касательной, а не
		# пересекает под углом (залом на бэкспейсе, автор 06.11.2026).
		_check(int(rule["roots"]) == 0,
			"%s %s: the palm reaches into every finger root (%d)"
			% [tag, side, int(rule["roots"])])
		# Предплечье вниз: радиус огромный в ОБЕИХ нижних четвертях.
		var down := 0.0
		for i in [radii.size() * 3 / 4 - 2, radii.size() * 3 / 4 + 2]:
			down = maxf(down, float(radii[i]))
		_check(down > 250.0,
			"%s %s: forearm reaches past the wrist (%.0f mm)" % [tag, side, down])
		var poly := Hands.hand_outline(bs, rest, {}, h)
		_check(poly.size() >= 32,
			"%s %s: contour is built (%d points)" % [tag, side, poly.size()])
		_check(absf(Hands._poly_area(poly)) > 4.0 * pitch * pitch,
			"%s %s: contour has the area of a hand" % [tag, side])
		# ОБРУБОК ЛОВИТСЯ ЗДЕСЬ: кисть обязана УЙТИ за нижний край экрана —
		# пересечь его хотя бы дважды (вошла и вышла). Торец внутри экрана
		# дал бы ноль, а замкнутый контур целиком в кадре — тоже.
		var cross := _edge_crossings(poly, Vector2(0.0, view.y),
			Vector2(view.x, view.y))
		var low := -INF
		for p in poly:
			low = maxf(low, p.y)
		_check(cross >= 2 and low > view.y + 4.0,
			"%s %s: forearm leaves the screen (%d crossings, lowest %.0f of %.0f)"
			% [tag, side, cross, low, view.y])
		# Подушечки покоя — на дом-клавишах.
		var off: Vector2 = st["shift"] as Vector2
		var root_x := float(HandsPoses.ROOT_MM[side])
		var homes: Dictionary = Hands.HOME_KEY[h] as Dictionary
		for f in [Hands.INDEX, Hands.MIDDLE, Hands.RING, Hands.PINKY]:
			var r := Hands.key_rect(bs, String(homes[f]))
			if r.size == Vector2.ZERO:
				continue
			var pad := Hands.to_px(map, Hands3D.pad(flat, side, root_x,
				String(Hands3D.RAY_OF[f]))) + off
			_check(pad.distance_to(r.get_center()) <= 0.5 * pitch,
				"%s %s: finger %d rests on '%s' (%.1f px)"
				% [tag, side, f, String(homes[f]),
					pad.distance_to(r.get_center())])


## Сколько раз контур пересекает ОТРЕЗОК (например, нижнюю границу экрана).
## Предплечье уходит вниз, поэтому нижняя граница — та, которую оно обязано
## пересечь. Боковые границы считались бы дважды, если кисть стоит у края.
func _edge_crossings(poly: PackedVector2Array, a: Vector2, b: Vector2) -> int:
	var n := poly.size()
	var cnt := 0
	for i in n:
		if Geometry2D.segment_intersects_segment(poly[i],
				poly[(i + 1) % n], a, b) != null:
			cnt += 1
	return cnt


## ------------------------------------------------------------- пальцы

## Пальцы — ленты из FK модели: ширина равна коже, суставы внутри,
## кончик на цепи, соседние не слипаются, большой на своей стороне.
func _finger_checks(bs: Array, tag: String) -> void:
	var pitch := Hands.pitch_of(bs)
	var rest := Hands.rest_both(bs)
	if rest.is_empty():
		return
	var map: Dictionary = rest["map"] as Dictionary
	var sr := float(map["sr"])
	for h in [Hands.LEFT, Hands.RIGHT]:
		var side := Hands.side_name(h)
		var st := Hands.pose_of(bs, h, rest, {})
		var flat: Array = st["flat"] as Array
		var off: Vector2 = st["shift"] as Vector2
		var root_x := float(HandsPoses.ROOT_MM[side])
		var xf := Hands3D.hand_xf(Hands3D.arm_of(flat))
		var bands := {}
		for ray in Hands3D.FINGERS:
			var pts := Hands3D.finger_fk(ray, Hands3D.finger_angles(flat, ray))
			var px := PackedVector2Array()
			for i in pts.size():
				px.append(Hands.to_px(map, Hands3D.to_world(side, root_x,
					xf * pts[i])) + off)
			var band := Hands.finger_band(flat, side, root_x, String(ray),
				map, xf, off)
			bands[ray] = band
			_check(band.size() >= 3,
				"%s %s %s: finger band is built" % [tag, side, ray])
			if band.size() < 3:
				continue
			var inner := 0
			for p in px:
				if Geometry2D.is_point_in_polygon(p, band):
					inner += 1
			_check(inner == px.size(),
				"%s %s %s: every joint is inside its band (%d/%d)"
				% [tag, side, ray, inner, px.size()])
			# Ширина ленты = 2·радиус кожи, и меряется ОНА, а не площадь:
			# у согнутой цепи площадь/длина завышена (хорда короче дуги, а
			# торцы-полукруги добавляют площадь). Расстояние от сустава до
			# границы ленты и есть радиус кожи в этом суставе.
			var rs: Array = Hands3D.SKIN_R[ray] as Array
			for i in px.size():
				var d := _dist_to_boundary(px[i], band)
				var want := float(rs[i]) * sr
				_check(d >= 0.70 * want and d <= 1.40 * want,
					"%s %s %s: joint %d is as thick as the skin (%.1f vs %.1f px)"
					% [tag, side, ray, i, d, want])
		# Соседние пальцы не слипаются в рукавицу: общая площадь мала.
		for pair in [["II", "III"], ["III", "IV"], ["IV", "V"]]:
			var pa: Array = pair as Array
			var a: PackedVector2Array = bands[pa[0]] as PackedVector2Array
			var b: PackedVector2Array = bands[pa[1]] as PackedVector2Array
			if a.size() < 3 or b.size() < 3:
				continue
			var ia := 0.0
			for q in Geometry2D.intersect_polygons(a, b):
				ia += absf(Hands._poly_area(q))
			var small := minf(absf(Hands._poly_area(a)),
				absf(Hands._poly_area(b)))
			_check(ia <= 0.35 * small,
				"%s %s: fingers %s+%s are separate (%.0f%%)" % [tag, side,
					pa[0], pa[1], 100.0 * ia / maxf(small, 1.0)])
		# Большой: лента построена, кончик внутри, палец на СВОЕЙ стороне
		# (у левой кисти — правее ладони, у правой — левее).
		var th := Hands.thumb_band(flat, side, root_x, map, xf, off)
		_check(th.size() >= 3, "%s %s: thumb band is built" % [tag, side])
		if th.size() >= 3:
			var tpts: PackedVector3Array = (Hands3D.thumb_fk(
				Hands3D.thumb_angles(flat))["pts"]) as PackedVector3Array
			var tip := Hands.to_px(map, Hands3D.to_world(side, root_x,
				xf * tpts[tpts.size() - 1])) + off
			_check(Geometry2D.is_point_in_polygon(tip, th),
				"%s %s: thumb tip is inside its band" % [tag, side])
			var palm := Hands.hand_outline(bs, rest, {}, h)
			var cx := 0.0
			for p in palm:
				cx += p.x
			cx /= maxf(float(palm.size()), 1.0)
			var inner := (tip.x > cx) if h == Hands.LEFT else (tip.x < cx)
			_check(inner, "%s %s: thumb is on the inner side of the hand"
				% [tag, side])
			_check(absf(Hands._poly_area(th)) > pitch * pitch,
				"%s %s: thumb is a real digit, not a sliver" % [tag, side])


## ------------------------------------------------------------- зеркало

## Правая кисть — отражение левой: ось зеркала — дом-группа «ф»↔«ж»,
## а не центр экрана (доска асимметрична по служебным клавишам).
func _mirror_checks(bs: Array, tag: String) -> void:
	var rest := Hands.rest_both(bs)
	if rest.is_empty():
		return
	var axis := 0.5 * ((Hands.key_rect(bs, "ф") as Rect2).get_center().x
		+ (Hands.key_rect(bs, "ж") as Rect2).get_center().x)
	var pl := Hands.hand_outline(bs, rest, {}, Hands.LEFT)
	var pr := Hands.hand_outline(bs, rest, {}, Hands.RIGHT)
	if pl.size() < 3 or pr.size() < 3:
		_check(false, tag + ": both contours are built for the mirror")
		return
	var worst := 0.0
	for p in pl:
		var m := Vector2(2.0 * axis - p.x, p.y)
		worst = maxf(worst, _dist_to_poly(m, pr))
	_check(worst <= 2.0,
		"%s: right hand mirrors the left (worst %.2f px)" % [tag, worst])


## ------------------------------------------------------------- нажатия

## КАЖДАЯ запечённая поза: подушечка — в своей клавише, контур до неё
## доходит, форма кисти меняется. Это главное обещание кистей.
func _press_checks(bs: Array) -> void:
	var pitch := Hands.pitch_of(bs)
	var rest := Hands.rest_both(bs)
	if rest.is_empty():
		_check(false, "presses: rest pose is built")
		return
	var map: Dictionary = rest["map"] as Dictionary
	var total := 0
	var bad_key := 0
	var bad_pad := 0
	var bad_reach := 0
	var bad_move := 0
	var worst_reach := 0.0
	for h in [Hands.LEFT, Hands.RIGHT]:
		var side := Hands.side_name(h)
		var own := 0
		var root_x := float(HandsPoses.ROOT_MM[side])
		var presses: Dictionary = HandsPoses.PRESS[side] as Dictionary
		var labels := presses.keys()
		labels.sort()
		var rest_poly := Hands.hand_outline(bs, rest, {}, h)
		for lb in labels:
			var sig := String(lb)
			var f := Hands.finger_of(sig)
			# Запечены ОБЕ кисти на все 53 подписи доски: у чужой руки
			# поза — покой (её пальцы эту клавишу не жмут). Проверяем
			# только СВОИ подписи, чужие молча пропускаем.
			if (f[0] as int) != h:
				continue
			var r := Hands.sig_rect(bs, sig)
			if r.size == Vector2.ZERO:
				_check(false, "key '%s' has no rect on the board" % sig)
				continue
			total += 1
			own += 1
			var presses_now := {h: {(f[1] as int): [sig, 1.0]}}
			var poly := Hands.hand_outline(bs, rest, presses_now, h)
			if poly.size() < 3:
				_check(false, "pressed '%s' keeps a contour" % sig)
				continue
			var st := Hands.pose_of(bs, h, rest, presses_now)
			var flat: Array = st["flat"] as Array
			var off: Vector2 = st["shift"] as Vector2
			var ray := "I" if (f[1] as int) == Hands.THUMB \
				else String(Hands3D.RAY_OF[f[1]])
			var pad := Hands.to_px(map, Hands3D.pad(flat, side, root_x, ray)) + off
			if not r.grow(1.0).has_point(pad):
				bad_key += 1
				if bad_key <= 3:
					print("PRESS: '%s' pad %.1f,%.1f outside %s" % [sig,
						pad.x, pad.y, str(r)])
			if not Geometry2D.is_point_in_polygon(pad, poly):
				bad_pad += 1
			var d := _dist_to_poly(r.get_center(), poly)
			worst_reach = maxf(worst_reach, d)
			if d > 0.5 * pitch:
				bad_reach += 1
				if bad_reach <= 3:
					print("PRESS: '%s' contour %.1f px from the key" % [sig, d])
			if _same_poly(poly, rest_poly):
				bad_move += 1
				if bad_move <= 3:
					print("PRESS: '%s' does not move the contour" % sig)
		_check(own >= 20,
			"%s: own presses are all checked (%d)" % [side, own])
	_check(total >= 50, "all baked presses are checked (%d)" % total)
	_check(bad_key == 0, "every press puts its pad on the key (%d bad)" % bad_key)
	_check(bad_pad == 0, "every pad is inside its contour (%d bad)" % bad_pad)
	_check(bad_reach == 0,
		"every press reaches its key (worst %.1f px, %d bad)"
		% [worst_reach, bad_reach])
	_check(bad_move == 0, "every press moves the hand (%d still)" % bad_move)


## --------------------------------------------------- пробел и подрагивание

## Дом-клавиши обеих кистей (та же карта, что HOME_KEY в hands.gd):
## [подпись, рука, палец].
const HOME_PRESS := [
	["ф", Hands.LEFT, Hands.PINKY], ["а", Hands.LEFT, Hands.INDEX],
	["в", Hands.LEFT, Hands.MIDDLE], ["ы", Hands.LEFT, Hands.RING],
	["о", Hands.RIGHT, Hands.INDEX], ["л", Hands.RIGHT, Hands.MIDDLE],
	["д", Hands.RIGHT, Hands.RING], ["ж", Hands.RIGHT, Hands.PINKY]]


## Точка кончика пальца на экране в данной позе (со сдвигом кисти).
func _tip_px(rest: Dictionary, h: int, flat: Array, shift: Vector2,
		finger: int) -> Vector2:
	var map: Dictionary = rest["map"] as Dictionary
	if finger == Hands.THUMB:
		var d := Hands3D.thumb_fk(Hands3D.thumb_angles(flat))
		return Hands.to_px(map, (d["pts"] as PackedVector3Array)[3]) + shift
	var ray := String(Hands3D.RAY_OF[finger])
	var fk := Hands3D.finger_fk(ray, Hands3D.finger_angles(flat, ray))
	return Hands.to_px(map, fk[3]) + shift


## Подушечка большого в покое на экране (с поправкой покоя).
func _thumb_rest_px(rest: Dictionary, h: int) -> Vector2:
	var side := Hands.side_name(h)
	var root_x := float(HandsPoses.ROOT_MM[side])
	var map: Dictionary = rest["map"] as Dictionary
	return Hands.to_px(map, Hands3D.pad(rest[h] as Array, side, root_x, "I")) \
		+ ((rest["shift"] as Dictionary)[h] as Vector2)


## Подушечка пальца на экране в данной позе (со сдвигом кисти).
func _pad_px(rest: Dictionary, h: int, flat: Array, shift: Vector2,
		finger: int) -> Vector2:
	var side := Hands.side_name(h)
	var root_x := float(HandsPoses.ROOT_MM[side])
	var ray := "I" if finger == Hands.THUMB else String(Hands3D.RAY_OF[finger])
	var map: Dictionary = rest["map"] as Dictionary
	return Hands.to_px(map, Hands3D.pad(flat, side, root_x, ray)) + shift


## ПРОБЕЛ (автор 07.11.2026: «при нажатии пробела правым пальцем
## перемещается вся рука, хотя это бессмысленно»). Правило: подушечка
## большого уже лежит на пробеле, поэтому кисть при нажатии не едет
## вовсе — движется только палец. Граница половин пробела при этом не
## середина клавиши, а ось между кистями: подушечки больших делят её
## пополам, и каждая стоит на своей половине.
func _space_checks(bs: Array, tag: String) -> void:
	var rest := Hands.rest_both(bs)
	var sp := Hands.key_rect(bs, "пробел")
	if rest.is_empty() or sp.size.x <= 0.0:
		_check(false, tag + ": space: rest pose is built")
		return
	var split := Kbd.space_split(bs)
	_check(split > sp.position.x and split < sp.end.x,
		"%s: the space split stays inside the key (%.1f)" % [tag, split])
	var lp := _thumb_rest_px(rest, Hands.LEFT)
	var rp := _thumb_rest_px(rest, Hands.RIGHT)
	_check(absf((lp.x + rp.x) * 0.5 - split) <= 2.0,
		"%s: the split is the middle between the resting thumbs (%.1f vs %.1f)"
			% [tag, split, (lp.x + rp.x) * 0.5])
	_check(lp.x < split and rp.x > split,
		"%s: each thumb rests on its own half of the space" % tag)
	# Пробел обязан держать ОБЕ подушечки с запасом: при тройной ширине
	# правая стояла на самом краю (замер 07.11.2026: подушечка 259 против
	# края 257.9), и четвёртая единица ширины это лечит.
	var edge := 0.25 * Hands.pitch_of(bs)
	for h in [Hands.LEFT, Hands.RIGHT]:
		var sig := "пробел:" + ("Л" if h == Hands.LEFT else "П")
		var rs: Vector2 = (rest["shift"] as Dictionary)[h]
		var st := Hands.pose_of(bs, h, rest, {h: {Hands.THUMB: [sig, 1.0]}})
		var off: Vector2 = st["shift"] as Vector2
		_check(absf(off.x - rs.x) <= 0.5 and absf(off.y - rs.y) <= 0.5,
			"%s: pressing '%s' does not move the hand (%.1f,%.1f)"
				% [tag, sig, off.x - rs.x, off.y - rs.y])
		var pad := _pad_px(rest, h, st["flat"] as Array, off, Hands.THUMB)
		var pad0 := _thumb_rest_px(rest, h)
		_check(pad.x >= sp.position.x + edge and pad.x <= sp.end.x - edge,
			"%s: the pressed thumb stays on the space with a margin (%.1f not in %.1f..%.1f)"
				% [tag, pad.x, sp.position.x + edge, sp.end.x - edge])
		_check(pad0.x >= sp.position.x + edge and pad0.x <= sp.end.x - edge,
			"%s: the resting thumb sits on the space with a margin (%.1f not in %.1f..%.1f)"
				% [tag, pad0.x, sp.position.x + edge, sp.end.x - edge])


## ПОДРАГИВАНИЕ (автор 07.11.2026: «при нажатии на любую клавишу, которая
## уже находится под пальцем, желательно видеть мелкое подрагивание этого
## пальца. Иначе нет ощущения нажатия»). У дом-клавиш запечённая поза
## почти равна покою, и без подрагивания кадр не меняется. Меряем ДВИЖЕНИЕ
## КОНЧИКА (его видит глаз) и то, что кисть при этом стоит на месте.
func _tap_checks(bs: Array, tag: String) -> void:
	var pitch := Hands.pitch_of(bs)
	var rest := Hands.rest_both(bs)
	if rest.is_empty() or pitch <= 0.0:
		_check(false, tag + ": tap: rest pose is built")
		return
	for item in HOME_PRESS:
		var sig := String(item[0])
		var h: int = item[1]
		var f: int = item[2]
		var rs: Vector2 = (rest["shift"] as Dictionary)[h]
		var a := _tip_px(rest, h, rest[h] as Array, rs, f)
		var st := Hands.pose_of(bs, h, rest, {h: {f: [sig, 1.0]}})
		var off: Vector2 = st["shift"] as Vector2
		var b := _tip_px(rest, h, st["flat"] as Array, off, f)
		var d := b.distance_to(a)
		_check(d >= 0.12 * pitch,
			"%s: pressing the home key '%s' twitches its fingertip (%.1f px)"
				% [tag, sig, d])
		_check(d <= 0.5 * pitch,
			"%s: the twitch on '%s' stays small (%.1f px)" % [tag, sig, d])
		_check(absf(off.x - rs.x) <= 0.5 and absf(off.y - rs.y) <= 0.5,
			"%s: the twitch on '%s' does not move the hand (%.1f,%.1f)"
				% [tag, sig, off.x - rs.x, off.y - rs.y])


## ------------------------------------------- несколько нажатий на кисти

## НЕСКОЛЬКО НАЖАТИЙ НА ОДНОЙ КИСТИ (автор 07.11.2026: «если одновременно,
## или, может быть, просто с коротким интервалом нажать сразу несколько
## клавиш, то кисть принимает какую-то странную форму, а может вообще уйти
## с экрана»).
##
## Запечённая поза — ЦЕЛАЯ кисть, и складывать их нельзя: два нажатия по 1
## давали 2·38° в пальце и 2·(−12°) в плече — кисть выгибало в блин, а
## сдвиг складывал поправки и уводил её за экран (кадр до правки: левой
## кисти на экране нет вовсе). Правило: плечо — ВЫПУКЛАЯ комбинация
## (среднее, сумма весов не больше 1), каждый нажатый палец — СВОЯ поза,
## сдвиг — СРЕДНЕЕ поправок. Меряем оба симптома: форму (углы) и экран
## (кончики).
func _multi_checks(bs: Array, view: Vector2, tag: String) -> void:
	var rest := Hands.rest_both(bs)
	var pitch := Hands.pitch_of(bs)
	if rest.is_empty() or pitch <= 0.0:
		_check(false, tag + ": multi: rest pose is built")
		return
	var combos := [
		[Hands.LEFT, {Hands.PINKY: ["ё", 1.0], Hands.INDEX: ["м", 1.0]}],
		[Hands.LEFT, {Hands.PINKY: ["ф", 1.0], Hands.INDEX: ["а", 1.0]}],
		[Hands.LEFT, {Hands.RING: ["ч", 0.6], Hands.MIDDLE: ["с", 1.0]}],
		[Hands.LEFT, {Hands.PINKY: ["ё", 1.0], Hands.RING: ["ч", 1.0],
			Hands.MIDDLE: ["с", 1.0], Hands.INDEX: ["м", 1.0]}],
		[Hands.RIGHT, {Hands.PINKY: ["0", 1.0], Hands.INDEX: ["т", 1.0]}],
		[Hands.RIGHT, {Hands.PINKY: ["ж", 1.0], Hands.INDEX: ["о", 1.0]}],
		[Hands.RIGHT, {Hands.PINKY: ["0", 1.0], Hands.RING: ["щ", 1.0],
			Hands.MIDDLE: ["л", 1.0], Hands.INDEX: ["т", 1.0]}],
	]
	var bad_arm := 0
	var bad_finger := 0
	var bad_shift := 0
	var bad_tip := 0
	var worst_tip := 0.0
	var screen := Rect2(Vector2.ZERO, view).grow(2.0)
	for item in combos:
		var arr: Array = item as Array
		var h: int = arr[0]
		var m: Dictionary = arr[1]
		var side := Hands.side_name(h)
		var pd: Dictionary = HandsPoses.PRESS[side] as Dictionary
		var base: Array = rest[h] as Array
		var poses := {}
		for f in m.keys():
			poses[f] = [pd[String((m[f] as Array)[0])],
				float((m[f] as Array)[1])]
		var flat := Hands3D.blend_many(base, poses)
		# 1. Плечо — выпуклая комбинация участвующих поз: сумма весов
		# больше единицы выносила угол за обе границы (старый дефект).
		for i in Hands3D.ARM_JOINTS.size():
			var lo := float(base[i])
			var hi := lo
			for f in poses.keys():
				var p: Array = (poses[f] as Array)[0]
				lo = minf(lo, float(p[i]))
				hi = maxf(hi, float(p[i]))
			if float(flat[i]) < lo - 1e-4 or float(flat[i]) > hi + 1e-4:
				bad_arm += 1
		# 2. Каждый нажатый палец — СВОЯ поза на свой вес: два пальца
		# гнутся оба, а не по половине.
		for f in poses.keys():
			var p: Array = (poses[f] as Array)[0]
			var w := float((poses[f] as Array)[1])
			var lo := 8 + (int(f) - 1) * 4
			var hi := lo + 4
			if int(f) == Hands.THUMB:
				lo = 24
				hi = 29
			for i in range(lo, hi):
				var want := lerpf(float(base[i]), float(p[i]), w)
				if absf(float(flat[i]) - want) > 1e-4:
					bad_finger += 1
		# 3. Сдвиг — СРЕДНЕЕ одиночных поправок, а не их сумма: сумма
		# уводила кисть с экрана.
		var want_off := Vector2.ZERO
		for f in poses.keys():
			var sig := String((m[f] as Array)[0])
			var one := Hands.pose_of(bs, h, rest, {h: {f: [sig, 1.0]}})
			want_off += one["shift"] as Vector2
		want_off /= float(poses.size())
		var st := Hands.pose_of(bs, h, rest, {h: m})
		var off: Vector2 = st["shift"] as Vector2
		if off.distance_to(want_off) > 0.5:
			bad_shift += 1
			if bad_shift <= 3:
				print("MULTI: %s shift %s, expected %s" % [tag, str(off),
					str(want_off)])
		# 4. Кисть не уезжает: все кончики на экране.
		for f in [Hands.THUMB, Hands.INDEX, Hands.MIDDLE, Hands.RING,
				Hands.PINKY]:
			var tip := _pad_px(rest, h, flat, off, f)
			var out := maxf(maxf(-tip.x, tip.x - view.x),
				maxf(-tip.y, tip.y - view.y))
			worst_tip = maxf(worst_tip, out)
			if not screen.has_point(tip):
				bad_tip += 1
				if bad_tip <= 3:
					print("MULTI: %s tip %.0f,%.0f off screen" % [tag,
						tip.x, tip.y])
	_check(bad_arm == 0,
		"%s: simultaneous presses keep the arm convex (%d angles)"
			% [tag, bad_arm])
	_check(bad_finger == 0,
		"%s: every pressed finger keeps its own pose (%d angles)"
			% [tag, bad_finger])
	_check(bad_shift == 0,
		"%s: the shift is the mean of the presses (%d bad)" % [tag, bad_shift])
	_check(bad_tip == 0,
		"%s: simultaneous presses keep the hand on screen (%d tips, worst %.0f)"
			% [tag, bad_tip, worst_tip])


## --------------------------------------------------- только свой палец

## Нажатие двигает ТОЛЬКО свой палец (автор 06.11.2026: при «в»/«л»
## безымянный дёргался сильнее среднего — казалось, что нажали не ту
## клавишу). Решатель в 3D подгибает соседние пальцы под клиренс
## клавиш — это верно для физики, но в проекции сверху читается как
## чужое нажатие. Правка — в ПОЗЕ (`bake_poses.gd._still_idle`), а
## здесь держится УРОВЕНЬ ДАННЫХ: в запечённой позе нажатия у всех
## остальных пальцев (и у большого, если он не цель) углы ровно как в
## покое. Перепекание без этой правки краснит каждую строку.
func _idle_checks() -> void:
	for side in ["L", "R"]:
		var home: Array = HandsPoses.HOME[side] as Array
		var presses: Dictionary = HandsPoses.PRESS[side] as Dictionary
		var hand := Hands.LEFT if side == "L" else Hands.RIGHT
		var bad := 0
		var checked := 0
		var targets := {}
		for lb in presses.keys():
			var sig := String(lb)
			var f := Hands.finger_of(sig)
			if (f[0] as int) != hand:
				continue
			var target: int = f[1]
			var p: Array = presses[lb] as Array
			checked += 1
			targets[target] = int(targets.get(target, 0)) + 1
			# Пальцы II..V — индексы 8..23 (по 4 угла на палец в порядке
			# RAY_OF: II, III, IV, V).
			for k in 4:
				if k + 1 == target:
					continue
				for j in 4:
					var i := 8 + k * 4 + j
					if absf(float(p[i]) - float(home[i])) > 1e-4:
						bad += 1
			# Большой — индексы 24..28: в покое, если он не цель.
			if target != Hands.THUMB:
				for i in range(24, 29):
					if absf(float(p[i]) - float(home[i])) > 1e-4:
						bad += 1
		_check(checked >= 20,
			"%s: idle checks cover own presses (%d)" % [side, checked])
		# Нажатия есть на КАЖДОМ пальце — иначе проверка была бы слепой
		# к целому пальцу (например, к безымянному из жалобы автора).
		_check(targets.size() == 5,
			"%s: presses cover all five digits (%s)" % [side, str(targets.keys())])
		_check(bad == 0,
			"%s: an idle finger moves in a press pose (%d angles)" % [side, bad])


## ------------------------------------------------------------- подсказка

## Демонстрация подсказки — чистая фаза: покой, выдержка, пауза,
## симметрия подъёма/спада, период.
func _hint_checks(bs: Array) -> void:
	_check(Hands.hint_depth(0.0) == 0.0, "hint demo starts at rest")
	_check(Hands.hint_depth(Hands.HINT_RISE_T
		+ Hands.HINT_HOLD_T * 0.5) == 1.0, "hint demo holds the key")
	_check(Hands.hint_depth(Hands.HINT_CYCLE_T
		- Hands.HINT_GAP_T * 0.5) == 0.0, "hint demo rests between cycles")
	_check(absf(Hands.hint_depth(Hands.HINT_RISE_T * 0.5)
		- Hands.hint_depth(Hands.HINT_CYCLE_T - Hands.HINT_GAP_T
		- Hands.HINT_FALL_T * 0.5)) < 0.02,
		"hint demo rise and fall are symmetric")
	_check(absf(Hands.hint_depth(0.3)
		- Hands.hint_depth(0.3 + Hands.HINT_CYCLE_T)) < 1e-5,
		"hint demo repeats every cycle")
	var mono := true
	var prev := -1.0
	for i in 21:
		var d := Hands.hint_depth(Hands.HINT_RISE_T * (float(i) / 20.0))
		if d < prev - 1e-6:
			mono = false
		prev = d
	_check(mono, "hint demo rises monotonically")
	# КОМБИНАЦИЯ — ПОСЛЕДОВАТЕЛЬНОСТЬ (автор 09.11.2026: «нажатие должно
	# быть не одновременным, а последовательным, надо подчёркивать их
	# последовательность в анимации»). Шифт встаёт первым и отпускается
	# последним; буква — наоборот. Одиночная подсказка остаётся прежней.
	_check(is_equal_approx(Hands.hint_cycle(1), Hands.HINT_CYCLE_T),
		"a single hint changed its period")
	_check(is_equal_approx(Hands.hint_cycle(2), Hands.HINT_CYCLE_T
			+ Hands.HINT_STAGGER_T + Hands.HINT_RELEASE_T),
		"a combo does not lengthen the cycle by its stagger")
	var half := Hands.HINT_RISE_T * 0.5
	_check(Hands.hint_depth_at(half, 0, 2) > 0.3
			and Hands.hint_depth_at(half, 1, 2) == 0.0,
		"the second key of a combo starts before the first one")
	var hold := Hands.HINT_HOLD_T \
		+ Hands.HINT_RISE_T + Hands.HINT_STAGGER_T * 0.5
	_check(Hands.hint_depth_at(hold, 0, 2) == 1.0
			and Hands.hint_depth_at(hold, 1, 2) == 1.0,
		"the combo never holds both keys together")
	var rel := Hands.HINT_RISE_T + Hands.HINT_HOLD_T + Hands.HINT_STAGGER_T \
		+ Hands.HINT_RELEASE_T * 0.5
	_check(Hands.hint_depth_at(rel, 0, 2) == 1.0
			and Hands.hint_depth_at(rel, 1, 2) < 1.0,
		"the letter does not release before the shift")
	var rel2 := Hands.HINT_RISE_T + Hands.HINT_HOLD_T + Hands.HINT_STAGGER_T \
		+ Hands.HINT_RELEASE_T + Hands.HINT_FALL_T * 0.5
	_check(Hands.hint_depth_at(rel2, 0, 2) > 0.0
			and Hands.hint_depth_at(rel2, 0, 2) < 1.0
			and Hands.hint_depth_at(rel2, 1, 2) == 0.0,
		"the shift does not release last")
	var mono2 := true
	for k in 2:
		var pr := -1.0
		for i in 21:
			var d2 := Hands.hint_depth_at(Hands.HINT_RISE_T * (float(i) / 20.0)
				+ float(k) * Hands.HINT_STAGGER_T, k, 2)
			if d2 < pr - 1e-6:
				mono2 = false
			pr = d2
	_check(mono2, "a combo key does not rise monotonically")
	# Точка подсказки — центр клавиши; половины пробела — свои половины.
	var a := Hands.hint_point(bs, "а")
	_check(a.distance_to((Hands.key_rect(bs, "а") as Rect2).get_center()) < 0.01,
		"hint point is the key centre")
	var sp := Hands.key_rect(bs, "пробел") as Rect2
	var hl := Hands.hint_point(bs, "пробел:Л")
	var hr := Hands.hint_point(bs, "пробел:П")
	_check(hl.x < hr.x, "space halves are left-to-right")
	_check(absf(hl.y - sp.get_center().y) < 0.01,
		"space halves keep the row height")
	# Граница половин — НЕ середина клавиши, а ось между кистями
	# (автор 07.11.2026). Половинки обязаны смыкаться ровно на ней.
	var split := Kbd.space_split(bs)
	var rl := Hands.sig_rect(bs, "пробел:Л")
	var rr := Hands.sig_rect(bs, "пробел:П")
	_check(absf(rl.position.x - sp.position.x) < 0.01
		and absf(rl.end.x - split) < 0.01
		and absf(rr.position.x - split) < 0.01
		and absf(rr.end.x - sp.end.x) < 0.01,
		"the space halves tile the key around the split (%.1f)" % split)
	_check(split > sp.get_center().x,
		"the split sits right of the key centre, at the hands' axis")


## ------------------------------------------------------------- контур

## Контур — ЧИСТАЯ мера: повторный вызов даёт ту же ломаную (кэш в
## main.draw_both опирается на это). Само рисование проверяется кадром
## (Painter ниже): вне _draw() CanvasItem рисовать не разрешает.
func _outline_checks(bs: Array) -> void:
	var rest := Hands.rest_both(bs)
	if rest.is_empty():
		_check(false, "outline: rest pose is built")
		return
	for h in [Hands.LEFT, Hands.RIGHT]:
		var a := Hands.hand_outline(bs, rest, {}, h)
		var b := Hands.hand_outline(bs, rest, {}, h)
		_check(_same_poly(a, b), "hand %d: contour is deterministic" % h)
		_check(a.size() >= 32, "hand %d: contour is a closed hand (%d points)"
			% [h, a.size()])
		var moved := Hands.hand_outline(bs, rest,
			{h: {Hands.INDEX: ["а", 1.0]}}, h)
		_check(not _same_poly(a, moved), "hand %d: a press moves the contour" % h)


## --------------------------------------------------------- один объект

## Кисть — ОДИН объект (автор 06.11.2026: «надо либо объединить все
## объекты каждой из кистей в один объект (причём со сглаживанием), ну,
## либо вернуть отрисовку назад»). В модели ладонь и пальцы — РАЗНЫЕ
## тела, и если рисовать контуры частей, линия стыка ложится внутрь кисти
## кругами у оснований («куча лишних линий»). Поэтому силуэт обязан быть
## ровно одним замкнутым полигоном, а каждая часть — лежать ВНУТРИ него:
## тогда линия всего одна и лишнего на кисти нет.
##
## Проверка держит три стороны правила:
##   * силуэт — ОДИН полигон (у объединения нет ни дырок, ни островов);
##   * ладонь лежит внутри и не выступает отдельной фигурой;
##   * каждый палец тоже внутри: объединение с ним НЕ меняет силуэт,
##     то есть его контур уже вошёл в общий и своей линии не требует.
func _one_object_checks(bs: Array) -> void:
	var rest := Hands.rest_both(bs)
	if rest.is_empty():
		_check(false, "one object: rest pose is built")
		return
	var map: Dictionary = rest["map"] as Dictionary
	for h in [Hands.LEFT, Hands.RIGHT]:
		var side := Hands.side_name(h)
		var poly := Hands.hand_outline(bs, rest, {}, h)
		var palm := Hands.hand_palm(bs, rest, {}, h)
		_check(poly.size() >= 32 and palm.size() >= 32,
			"hand %d: silhouette (%d points) and palm (%d points) are built"
			% [h, poly.size(), palm.size()])
		if poly.size() < 3 or palm.size() < 3:
			continue
		var pa := absf(Hands._poly_area(poly))
		var ma := absf(Hands._poly_area(palm))
		var uni := Geometry2D.merge_polygons(poly, palm)
		_check(uni.size() == 1,
			"hand %d: palm and silhouette are ONE piece (%d pieces)"
			% [h, uni.size()])
		_check(pa > ma * 1.02,
			"hand %d: fingers are inside the silhouette (%.0f vs palm %.0f px²)"
			% [h, pa, ma])
		var flat: Array = rest[h] as Array
		var rx := float(HandsPoses.ROOT_MM[side])
		var xf := Hands3D.hand_xf(Hands3D.arm_of(flat))
		var off: Vector2 = (rest["shift"] as Dictionary)[h] as Vector2
		for ray in Hands3D.FINGERS:
			var band := Hands.finger_band(flat, side, rx, ray, map, xf, off)
			_check(_inside_contour(poly, band, pa),
				"hand %d: finger %s is inside the ONE contour — no part stroke"
				% [h, ray])
		var th := Hands.thumb_band(flat, side, rx, map, xf, off)
		_check(_inside_contour(poly, th, pa),
			"hand %d: thumb is inside the ONE contour — no part stroke" % h)


## Часть целиком лежит внутри силуэта: объединение с ней не добавляет
## площади (в пределах допуска на округление Clipper).
func _inside_contour(poly: PackedVector2Array, part: PackedVector2Array,
		poly_area: float) -> bool:
	if part.size() < 3:
		return false
	var uni := Geometry2D.merge_polygons(poly, part)
	if uni.size() != 1:
		return false
	return absf(Hands._poly_area(uni[0]) - poly_area) < 1.0


## ------------------------------------------------- клавиши по пальцам

## Цвет клавиши — по пальцу, который её жмёт (автор 08.11.2026: «фоны
## клавиш едва заметно раскрашивались по цветам, отличающим разные
## пальцы»). Держим:
##   * у КАЖДОЙ клавиши доски есть цвет (новая клавиша без пальца
##     краснит — иначе она молча осталась бы нейтральной);
##   * цвет берётся из круга по `Ui.FINGER_SLOT`: в каждом ряду букв и
##     цифр соседние пальцы стоят на ≥ 3 шага круга (108°), значит цвет —
##     спутник места, а не случайный набор, и ряд не читается радугой
##     (автор 08.11.2026: «цвета должны выбираться так, чтобы максимально
##     контрастировать друг с другом, а у тебя наоборот — наблюдается
##     плавный градиент»);
##   * между указательными — такой же прыжок: граница их зон видна
##     (автор: «Зеркально значит границ между зонами двух указательных
##     пальцев видно не будет, а это крайне важно»);
##   * системные клавиши низа получают СТОРОНУ по месту: подпись у них
##     одна, а клавиши две;
##   * заливки строятся один раз и перекрашиваются темой НА МЕСТЕ;
##   * у пробела две половины, скруглены только внешние углы;
##   * вспышка нажатия, подсказка и зажатый шифт заливку вытесняют.
##
## Headless картинку не рисует — меряем чистые меры: зоны пальцев,
## панели и правило выбора (Kbd.key_box).
func _tint_checks(bs: Array) -> void:
	for b in bs:
		var s0 := String(b["s"])
		_check(Hands.tint_index(s0) >= 0, "key '%s' has a finger tint" % s0)
	for pair in [["ё", 0], ["ф", 0], ["ы", 1], ["в", 2], ["а", 3], ["п", 3],
			["пробел", 4], ["глобус", 5], ["р", 6], ["о", 6], ["л", 7],
			["д", 8], ["ж", 9], ["э", 9], ["0", 9], ["ShiftR", 9]]:
		var want := int((pair as Array)[1])
		var got := Hands.tint_index(String((pair as Array)[0]))
		_check(got == want,
			"tint of '%s' is %d, want %d" % [(pair as Array)[0], got, want])
	# Сторона в подписи: тот же палец, но своя рука.
	_check(Hands.tint_index("Ctrl:Л") == 0 and Hands.tint_index("Ctrl:П") == 9,
		"Ctrl gets a side: left pinky / right pinky")
	_check(Hands.tint_index("Win:Л") == 0 and Hands.tint_index("Win:П") == 9,
		"Win gets a side too")
	_check(Hands.tint_index("Alt:Л") == 0 and Hands.tint_index("Alt:П") == 9,
		"Alt gets a side too")
	_check(Hands.tint_index("пробел:Л") == 4 and Hands.tint_index("пробел:П") == 5,
		"space halves are the two thumbs")
	_check(Hands.tint_index("нет-такой") == -1, "an unknown key has no tint")
	# Стык указательных идёт тем же ПРЫЖКОМ, что и все соседи по доске:
	# зоны 3 и 6 стоят в таблице слотов на ≥ 3 шага круга (108°).
	var slot3 := int(Ui.FINGER_SLOT[3])
	var slot6 := int(Ui.FINGER_SLOT[6])
	var gap := mini(absi(slot6 - slot3), 10 - absi(slot6 - slot3))
	_check(gap >= 3,
		"the index|index boundary spans %d hue slots, want >= 3" % gap)

	var tints := Hands.key_tints(false, 10.0, Ui.LINE_DAY, 2.0)
	_check(not tints.has("пробел"), "the space has no whole-key tint")
	var split := Kbd.space_split(bs)
	var rows := {}
	for b in bs:
		var r0: Rect2 = b["r"]
		var key := int(round(r0.position.y))
		if not rows.has(key):
			rows[key] = []
		(rows[key] as Array).append(b)
	var ys: Array = rows.keys()
	ys.sort()
	for ri in ys.size():
		var key := int(ys[ri])
		var row: Array = rows[key]
		row.sort_custom(func(a, c):
			return (a["r"] as Rect2).position.x < (c["r"] as Rect2).position.x)
		var prev := -1
		var prev_slot := -1
		# ШАГ ЦВЕТА — ПРЫЖОК, А НЕ РАДУГА (автор 08.11.2026: «цвета должны
		# выбираться так, чтобы максимально контрастировать друг с другом,
		# а у тебя наоборот — наблюдается плавный градиент»). Держим на
		# ЧЕТЫРЁХ верхних рядах (цифры и буквы): низ — карта клавиш, а не
		# зона пальцев. Соседние клавиши РАЗНЫХ пальцев обязаны стоять на
		# круге не ближе трёх шагов (108°); одна зона на две клавиши
		# («а»/«п») цвета не меняет — это не градиент, а тот же палец.
		var top_rows := ri < 4
		for b in row:
			var s := String(b["s"])
			var tint_key := s
			if tints.has(s + ":Л"):
				var cx: float = (b["r"] as Rect2).get_center().x
				tint_key = s + (":Л" if cx < split else ":П")
			_check(tints.has(tint_key),
				"row %d: '%s' has a tint box" % [key, s])
			if not tints.has(tint_key):
				continue
			var cur := Hands.tint_index(tint_key)
			var cur_slot := -1
			if cur >= 0:
				cur_slot = int(Ui.FINGER_SLOT[cur])
			if top_rows and prev >= 0 and cur != prev:
				var hop := mini(absi(cur_slot - prev_slot),
					10 - absi(cur_slot - prev_slot))
				_check(hop >= 3,
					"row %d: tints %d and %d are %d hue slots apart at '%s' — gradient, not contrast"
					% [key, prev, cur, hop, s])
			prev = cur
			prev_slot = cur_slot

	# Заливки — из палитры, построены один раз, темой меняются на месте.
	# Номер заливки берём у `paint_index`, а не у пальца: у пробела палец
	# у каждой половины свой, а цвет ОДИН (автор 08.11.2026).
	var day_pal: Array = Ui.FINGER_DAY
	var night_pal: Array = Ui.FINGER_NIGHT
	for s in tints:
		var i := Hands.paint_index(String(s))
		_check(i >= 0, "tint box '%s' maps to a finger" % s)
		if i < 0:
			continue
		var sb: StyleBoxFlat = tints[s]
		_check(sb.bg_color == day_pal[i], "tint box '%s' is the day colour" % s)
	var first: StyleBoxFlat = tints["ф"]
	Hands.repaint_tints(tints, true)
	_check(first.bg_color == night_pal[0], "night repaint recolours the same box")
	_check(first.border_color == Ui.LINE_NIGHT, "night repaint recolours the border")
	_check(tints["ф"] == first, "night repaint keeps the same StyleBox")
	Hands.repaint_tints(tints, false)
	_check(first.bg_color == day_pal[0], "day repaint returns the day colour")
	_check(first.border_color == Ui.LINE_DAY, "day repaint returns the day border")

	# Пробел: две половины, скруглены ВНЕШНИЕ углы, внутренних рамок нет.
	var sp_l: StyleBoxFlat = tints["пробел:Л"]
	var sp_r: StyleBoxFlat = tints["пробел:П"]
	_check(sp_l.corner_radius_top_left > 0 and sp_l.corner_radius_bottom_left > 0,
		"space left half is rounded on its outer left corners")
	_check(sp_l.corner_radius_top_right == 0 and sp_l.corner_radius_bottom_right == 0,
		"space left half has square inner corners")
	_check(sp_l.border_width_right == 0, "space left half has no inner border")
	_check(sp_r.corner_radius_top_right > 0 and sp_r.corner_radius_bottom_right > 0,
		"space right half is rounded on its outer right corners")
	_check(sp_r.corner_radius_top_left == 0 and sp_r.corner_radius_bottom_left == 0,
		"space right half has square inner corners")
	_check(sp_r.border_width_left == 0, "space right half has no inner border")
	# ОДИН цвет на всю клавишу — halves красятся цветом самой клавиши, а не
	# большого (автор 08.11.2026: «пробел пусть будет одного цвета. Его
	# раскрашивать двумя цветами как-то странно»). Сторона остаётся только
	# в геометрии: внешние углы скруглены, внутренние — нет.
	_check(sp_l.bg_color == sp_r.bg_color,
		"the space halves have different colours")
	_check(sp_l.bg_color == day_pal[Hands.tint_index("пробел")],
		"the space does not carry its own single colour")
	_check(sp_l.border_color == sp_r.border_color,
		"the space halves have different borders")
	# Темой перекрашиваются тем же правилом: одна клавиша — один цвет.
	Hands.repaint_tints(tints, true)
	_check(sp_l.bg_color == night_pal[Hands.tint_index("пробел")]
			and sp_l.bg_color == sp_r.bg_color,
		"night repaint split the space into two colours")
	Hands.repaint_tints(tints, false)

	# Выбор панели: цвет пальца — обычное состояние, но «ты нажал»,
	# «жми сюда» и зажатый шифт важнее.
	var base := Ui.panel_sb(Color.WHITE, 10.0)
	var tint_sb: StyleBox = tints["ф"]
	var press := Ui.panel_sb(Color.RED, 10.0)
	var hi := Ui.panel_sb(Color.YELLOW, 10.0)
	_check(Kbd.key_box("ф", "ф", base, tints, press, "", hi, false, false) == tint_sb,
		"a plain key is painted by its finger")
	_check(Kbd.key_box("ф", "ф", base, tints, press, "ф", hi, false, false) == press,
		"a pressed key keeps the press flash")
	_check(Kbd.key_box("ф", "ф", base, tints, press, "", hi, true, false) == hi,
		"a hinted key keeps the hint")
	_check(Kbd.key_box("Shift", "Shift", base, tints, press, "", hi, false, true) == base,
		"the held shift keeps its accent")
	_check(Kbd.key_box("нет-такой", "нет-такой", base, tints, press, "", hi, false, false) == base,
		"an unknown key stays neutral")

	# ЗОНА ПОДСКАЗКИ (автор 08.11.2026: «при подсказке всю секцию делать
	# ещё заметнее. Чтобы было понято в какой зоне и каким пальцем надо
	# нажимать»). Те же клавиши доски, но свои панели: заливка горячее,
	# рамка — ЦВЕТОМ ПАЛЬЦА (общий `LINE_*` у всех зон не дал бы секции).
	var hot := Hands.key_tints(false, 10.0, Ui.LINE_DAY, 2.0, true)
	var hot_day: Array = Ui.FINGER_HOT_DAY
	var hot_night: Array = Ui.FINGER_HOT_NIGHT
	var edge_day: Array = Ui.FINGER_EDGE_DAY
	var edge_night: Array = Ui.FINGER_EDGE_NIGHT
	_check(hot.size() == tints.size(),
		"hot tints cover the board (%d vs %d)" % [hot.size(), tints.size()])
	var differ := 0
	for s in tints:
		if hot.get(s) == tints[s]:
			differ += 1
	_check(differ == 0, "%d hot keys reuse the calm panel" % differ)
	for s in hot:
		var i := Hands.tint_index(String(s))
		_check(i >= 0, "hot box '%s' maps to a finger" % s)
		if i < 0:
			continue
		var hs: StyleBoxFlat = hot[s]
		_check(hs.bg_color == hot_day[i],
			"hot box '%s' is the hot day colour" % s)
		_check(hs.border_color == edge_day[i],
			"hot box '%s' carries its finger edge in day" % s)
		_check((tints[s] as StyleBoxFlat).bg_color == day_pal[Hands.paint_index(String(s))],
			"hot panel left the calm box alone at '%s'" % s)
	# Горячие половины пробела — цвета СВОИХ больших: подсказка красит
	# именно ту половину, которой жать (обычная заливка у пробела одна).
	_check((hot["пробел:Л"] as StyleBoxFlat).bg_color == hot_day[4]
			and (hot["пробел:П"] as StyleBoxFlat).bg_color == hot_day[5],
		"hot space halves carry the two thumbs")
	_check((hot["пробел:Л"] as StyleBoxFlat).bg_color != (tints["пробел:Л"] as StyleBoxFlat).bg_color
			and (hot["пробел:П"] as StyleBoxFlat).bg_color != (tints["пробел:П"] as StyleBoxFlat).bg_color,
		"a hot space half did not differ from the calm one")
	_check((hot["пробел:Л"] as StyleBoxFlat).border_width_right == 0
			and (hot["пробел:П"] as StyleBoxFlat).border_width_left == 0,
		"hot space halves keep their inner edges bare")
	var hfirst: StyleBoxFlat = hot["ф"]
	Hands.repaint_tints(hot, true, true)
	_check(hfirst.bg_color == hot_night[0], "hot night repaint recolours the fill")
	_check(hfirst.border_color == edge_night[0], "hot night repaint recolours the edge by finger")
	_check(hot["ф"] == hfirst, "hot night repaint keeps the same StyleBox")
	_check(first.bg_color == day_pal[0],
		"hot repaint did not touch the calm panel")
	Hands.repaint_tints(hot, false, true)
	_check(hfirst.bg_color == hot_day[0], "hot day repaint returns the hot fill")
	_check(hfirst.border_color == edge_day[0], "hot day repaint returns the finger edge")
	# Порядок: нажатие > подсказка > шифт > ЗОНА > цвет пальца. Подсказка
	# и вспышка говорят «что сейчас», зона — «каким пальцем», цвет —
	# «какой рукой»; спорить с верхними им нельзя. В игре приходит ТОЛЬКО
	# зона (`_hot_zone`), поэтому чужая клавиша остаётся обычной.
	var zone := {}
	for s in hot:
		if Hands.tint_index(String(s)) == 0:
			zone[s] = hot[s]
	_check(zone.has("ф") and not zone.has("ы"), "the zone is one finger wide")
	_check(Kbd.key_box("ф", "ф", base, tints, press, "", hi, false, false, zone) == hot["ф"],
		"a key of the hinted finger is painted hot")
	_check(Kbd.key_box("ф", "ф", base, tints, press, "", hi, true, false, zone) == hi,
		"the hinted key itself stays above its hot zone")
	_check(Kbd.key_box("ф", "ф", base, tints, press, "ф", hi, false, false, zone) == press,
		"the press flash stays above the hot zone")
	_check(Kbd.key_box("Shift", "Shift", base, tints, press, "", hi, false, true, zone) == base,
		"the held shift stays above the hot zone")
	_check(Kbd.key_box("ы", "ы", base, tints, press, "", hi, false, false, zone) == tints["ы"],
		"a key of another finger keeps its calm tint")
	_check(Kbd.space_half_box(hot, tints, "пробел:Л") == hot["пробел:Л"],
		"the hot half of the space wins over the calm one")
	_check(Kbd.space_half_box({}, tints, "пробел:П") == tints["пробел:П"],
		"without a zone the space half keeps its calm tint")

	# ДОРОЖКИ ЗОН — подложка под клавишами (автор 09.11.2026: «либо ещё
	# заметнее цвета, либо вообще менять способ разделения на сектора»).
	# У КАЖДОЙ клавиши доски своя дорожка, у одного пальца — ОДИН цвет,
	# пробел — одна дорожка одного цвета. Дорожки смыкаются: подложка
	# растёт на ползазора, поэтому соседи одного пальца дают сплошную
	# полосу, а не две плитки.
	var lanes := Hands.key_lanes(false)
	var lane_night: Array = Ui.FINGER_LANE_NIGHT
	var lane_day: Array = Ui.FINGER_LANE_DAY
	var split_l := Kbd.space_split(bs)
	for b in bs:
		var s1 := String(b["s"])
		var lk := s1
		if lanes.has(s1 + ":Л"):
			var cx1: float = (b["r"] as Rect2).get_center().x
			lk = s1 + (":Л" if cx1 < split_l else ":П")
		_check(lanes.has(lk), "key '%s' has a zone lane" % s1)
		if not lanes.has(lk):
			continue
		var li := Hands.paint_index(lk)
		_check(li >= 0, "lane '%s' maps to a finger" % lk)
		if li >= 0:
			_check((lanes[lk] as Color) == lane_day[li],
				"lane '%s' is the day colour of its finger" % lk)
	_check(lanes.has("пробел"), "the space has one whole-key lane")
	_check((lanes["пробел"] as Color) == lane_day[Hands.tint_index("пробел")],
		"the space lane is not its single calm colour")
	# Соседи одного пальца: подложки перекрываются — зазор доски
	# закрыт, сплошная дорожка (мера та же, что у рисования).
	var ra := Hands.key_rect(bs, "а") as Rect2
	var rp := Hands.key_rect(bs, "п") as Rect2
	var area0 := Rect2(ra.position, Vector2.ZERO)
	for b in bs:
		area0 = area0.merge(b["r"] as Rect2)
	var la := Kbd.lane_rect(ra, area0)
	var lp := Kbd.lane_rect(rp, area0)
	_check(la.end.x > lp.position.x or lp.end.x > la.position.x,
		"two keys of one finger do not share a lane")
	_check(absf(la.position.y - lp.position.y) < 0.01,
		"a lane changes height along its finger")
	# Дорожка не вылезает за доску: радужной рамки по краю нет.
	var lfl := Kbd.lane_rect(Hands.key_rect(bs, "ф") as Rect2, area0)
	_check(lfl.position.x >= area0.position.x - 0.01
		and lfl.end.x <= area0.end.x + 0.01,
		"a lane spills outside the board")
	# Темой перекрашивается НА МЕСТЕ: словарь тот же, цвета ночные.
	Hands.repaint_lanes(lanes, true)
	_check((lanes["ф"] as Color) == lane_night[0],
		"night repaint does not recolour the lanes")
	_check(Hands.key_lanes(true)["глобус"] == lane_night[5],
		"a fresh night lane set is not the night palette")
	Hands.repaint_lanes(lanes, false)
	_check((lanes["ф"] as Color) == lane_day[0],
		"day repaint does not return the lane colour")


## Рисование ОБЕИХ кистей — только из _draw(): CanvasItem иначе ругается
## «Drawing is only allowed inside this node's _draw()». Узел делает три
## вызова подряд (покой, повтор, нажатие) и складывает ключи кэша.
class Painter extends Node2D:
	var bs: Array = []
	var rest := {}
	var keys1: Array = []
	var keys2: Array = []
	var keys3: Array = []
	var done := false

	func _draw() -> void:
		if rest.is_empty():
			return
		var cache := {}
		Hands.draw_both(self, bs, rest, {}, Ui.INK_DAY, cache)
		keys1 = cache.keys().duplicate()
		Hands.draw_both(self, bs, rest, {}, Ui.INK_DAY, cache)
		keys2 = cache.keys().duplicate()
		Hands.draw_both(self, bs, rest,
			{Hands.LEFT: {Hands.INDEX: ["а", 1.0]}}, Ui.INK_DAY, cache)
		keys3 = cache.keys().duplicate()
		done = true


## Одинаковы ли контуры (порядок вершин у Clipper устойчив: изменилась
## поза — изменились и точки).
func _same_poly(a: PackedVector2Array, b: PackedVector2Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if a[i].distance_to(b[i]) > 0.01:
			return false
	return true


## Расстояние от точки ВНУТРИ контура до его границы (мера «радиус кожи»:
## у ленты пальца оно равно радиусу капсулы в этом суставе).
func _dist_to_boundary(p: Vector2, poly: PackedVector2Array) -> float:
	var n := poly.size()
	if n < 3:
		return 0.0
	var best := INF
	for i in n:
		var q := Geometry2D.get_closest_point_to_segment(
			p, poly[i], poly[(i + 1) % n])
		best = minf(best, p.distance_to(q))
	return best


## Расстояние от точки до контура (0 — внутри). Мера «контур дошёл до
## клавиши»: подушечка прощает пиксели, поэтому сравниваем близость.
func _dist_to_poly(p: Vector2, poly: PackedVector2Array) -> float:
	if poly.size() < 3:
		return INF
	if Geometry2D.is_point_in_polygon(p, poly):
		return 0.0
	var best := INF
	var n := poly.size()
	for i in n:
		var q := Geometry2D.get_closest_point_to_segment(
			p, poly[i], poly[(i + 1) % n])
		best = minf(best, p.distance_to(q))
	return best
