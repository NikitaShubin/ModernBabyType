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
##      обрубком внутри. Радиусы гладкие (шишах — это скачок радиуса).
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
	_press_checks(bs)
	_idle_checks()
	_hint_checks(bs)
	_outline_checks(bs)
	_one_object_checks(bs)


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
		var bump := 0
		var bump_pose := ""
		var worst := 0.0
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
			# ШИШАХ (автор 05.11.2026) — ЛОКАЛЬНЫЙ выступ или вмятина на
			# ладони: радиус вырос и тут же упал. Такого нет ни в одной
			# запечённой позе — иначе дефект вернулся бы в большинстве
			# поз, как и было до правки модели.
			var b := 0
			for i in Shape.N:
				var x := float(a[(i - 1 + Shape.N) % Shape.N])
				var y := float(a[i])
				var z := float(a[(i + 1) % Shape.N])
				if maxf(maxf(x, y), z) >= 95.0:
					continue
				if (y > x + 1.5 and y > z + 1.5) or (y < x - 1.5 and y < z - 1.5):
					b += 1
			if b > 0:
				bump += 1
				if bump_pose == "":
					bump_pose = String(k)
		_check(bump == 0,
			"%s: no bump or notch on the palm in any baked pose (%d poses, e.g. '%s')"
			% [side, bump, bump_pose])
		_check(bad == 0, "%s: every baked ray is a positive number (%d bad)"
			% [side, bad])
		_check(worst > 300.0,
			"%s: the forearm reaches far past the wrist (%.0f mm)" % [side, worst])


## ------------------------------------------------------- ладонь и предплечье

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
		# наоборот — вмятина). Соседние лучи на ладони (r < 95 мм, до
		# перехода в предплечье) обязаны идти плавно; обрыв к предплечью
		# законный — там стенка трубы почти радиальна (скачок 79 мм на
		# переходе), и мерить его гладкостью бессмысленно.
		var bad := 0
		var bump := 0
		var jump := 0.0
		for i in radii.size():
			var a := float(radii[(i - 1 + radii.size()) % radii.size()])
			var b := float(radii[i])
			var c := float(radii[(i + 1) % radii.size()])
			if maxf(maxf(a, b), c) >= 95.0:
				continue
			jump = maxf(jump, absf(b - c))
			if absf(b - c) > 8.0:
				bad += 1
			if (b > a + 1.5 and b > c + 1.5) or (b < a - 1.5 and b < c - 1.5):
				bump += 1
		_check(bad == 0, "%s %s: palm radii are smooth (%d jumps, max %.1f mm)"
			% [tag, side, bad, jump])
		_check(bump == 0,
			"%s %s: no bump or notch on the palm contour (%d)" % [tag, side, bump])
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
		var st := Hands.pose_of(bs, h, rest, {})
		var flat: Array = st["flat"] as Array
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
	# Точка подсказки — центр клавиши; половины пробела — свои половины.
	var a := Hands.hint_point(bs, "а")
	_check(a.distance_to((Hands.key_rect(bs, "а") as Rect2).get_center()) < 0.01,
		"hint point is the key centre")
	var sp := Hands.key_rect(bs, "пробел") as Rect2
	var hl := Hands.hint_point(bs, "пробел:Л")
	var hr := Hands.hint_point(bs, "пробел:П")
	_check(hl.x < hr.x, "space halves are left-to-right")
	_check(absf((hl.x + hr.x) * 0.5 - sp.get_center().x) < 0.01,
		"space halves are centred on the space bar")
	_check(absf(hl.y - sp.get_center().y) < 0.01,
		"space halves keep the row height")


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
