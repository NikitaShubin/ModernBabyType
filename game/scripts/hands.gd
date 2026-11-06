class_name Hands
extends RefCounted

## Кисти обеих рук над доской — ПРОЕКЦИЯ ТЕХ САМЫХ 3D-КИСТЕЙ.
##
## Автор 04.11.2026: «это должны быть те самые руки из 3д». Прежняя
## редакция рисовала свою 2D-модель со своим IK, и она читалась
## пародией: палец шириной 12 мм против настоящих 20, ладонь-обрубок
## 48 мм против 74. Теперь модель ОДНА — tools/hand3d (скелет, углы
## покоя, кожа, плечо), а игра её только проецирует.
##
## ЧТО ЗДЕСЬ ПРОИСХОДИТ (и чего здесь нет):
##   1. Поз нажатий игра НЕ решает: они запечены в hands_poses.gd тем же
##      решателем исследования, что и просмотрщик доски (нажатие стоило
##      бы 0.5–3.4 с — в кадр это не влезает). Поза кадра — покой,
##      подтянутый к позе нажатия на его ход; плечо — средневзвешенное
##      по нажатиям (сумма весов не больше 1).
##   2. СИЛУЭТ тоже запечён — с ПОЛЯ 3D-модели (hands_shape.gd). В игре
##      его не собирают из примитивов: объединение проекций — не
##      проекция объединения, и smin-скругление выносит настоящую
##      поверхность на 5.8 мм наружу. Отсюда были ступеньки и «шишах» у
##      большого пальца (автор 05.11.2026). Контур снят лучами из центра
##      ладони вдоль ЛОКАЛЬНОЙ z кисти (той же осью, которой игра кладёт
##      пальцы на клавиши), с предплечьем в том же контуре.
##   3. Поза кадра смешивает РАДИУСЫ контура теми же весами, что и углы:
##      топология у всех поз одна, поэтому промежуточная поза — тоже
##      честный контур модели.
##   4. Рисуется контур линией и лёгкой заливкой (автор 27.10.2026:
##      «только контуры рук»), чтобы подписи клавиш читались.
##
## Модуль ЧИСТЫЙ: нет сцены и состояния, все меры — статические функции
## (headless не рисует, а тесты меряют их числом).

## Запечённый силуэт модели (генерируется tools/hand3d/bake_outline.gd).
## Берём preload'ом, а не глобальным именем: кэш глобальных классов в
## .godot обновляется импортом, и свежий файл в нём ещё не числится.
const Shape := preload("res://scripts/hands_shape.gd")

const THUMB := 0
const INDEX := 1
const MIDDLE := 2
const RING := 3
const PINKY := 4

const LEFT := 0
const RIGHT := 1

## Питч ANSI и шаг ряда — те же, что у доски исследования: по ним
## миллиметры кисти ложатся на пиксели доски игры.
const PITCH_MM := 19.05
const ROW_STEP_MM := 21.7575
const HOME_Y := 152.0

## Дом-клавиша пальца. Указательные закрывают по две колонки: покой у
## ПЕРВОЙ (а/о), вторая достаётся при нажатии.
const HOME_KEY := {
	LEFT: {INDEX: "а", MIDDLE: "в", RING: "ы", PINKY: "ф"},
	RIGHT: {INDEX: "о", MIDDLE: "л", RING: "д", PINKY: "ж"},
}

## Клавиши по пальцам — как на ФИЗИЧЕСКОЙ клавиатуре (доска игры —
## физическая раскладка: те же клавиши для РУ/EN). По русской школе
## И, Т, Ь относят правому указательному — но клавиши b/n/m физически
## стоят под ЛЕВОЙ ладонью, и тянуть их правым пальцем против физики
## нельзя: и → левый указательный, т/ь → правый (n/m — правая ладонь).
## Служебные — крайние мизинцы своей стороны: Tab/Caps/левый шифт —
## левый мизинец, стереть/ввод/правый шифт — правый. Глобус — большой
## правой (по другую сторону пробела от системных). Пробел —
## динамический: большой СВОБОДНОЙ руки; его подпись несёт руку
## («пробел:Л» / «пробел:П»), см. finger_of.
const FINGER_MAP := {
	# Левая рука.
	"ё": [LEFT, PINKY], "1": [LEFT, PINKY], "й": [LEFT, PINKY],
	"ф": [LEFT, PINKY], "я": [LEFT, PINKY],
	"Tab": [LEFT, PINKY], "Caps": [LEFT, PINKY], "Shift": [LEFT, PINKY],
	"2": [LEFT, RING], "ц": [LEFT, RING], "ы": [LEFT, RING], "ч": [LEFT, RING],
	"3": [LEFT, MIDDLE], "у": [LEFT, MIDDLE], "в": [LEFT, MIDDLE],
	"с": [LEFT, MIDDLE],
	"4": [LEFT, INDEX], "5": [LEFT, INDEX], "к": [LEFT, INDEX],
	"е": [LEFT, INDEX], "а": [LEFT, INDEX], "п": [LEFT, INDEX],
	"м": [LEFT, INDEX], "и": [LEFT, INDEX],
	# Правая рука.
	"6": [RIGHT, INDEX], "7": [RIGHT, INDEX], "н": [RIGHT, INDEX],
	"г": [RIGHT, INDEX], "р": [RIGHT, INDEX], "о": [RIGHT, INDEX],
	"т": [RIGHT, INDEX], "ь": [RIGHT, INDEX],
	"8": [RIGHT, MIDDLE], "ш": [RIGHT, MIDDLE], "л": [RIGHT, MIDDLE],
	"б": [RIGHT, MIDDLE],
	"9": [RIGHT, RING], "щ": [RIGHT, RING], "д": [RIGHT, RING],
	"ю": [RIGHT, RING],
	"0": [RIGHT, PINKY], "-": [RIGHT, PINKY], "=": [RIGHT, PINKY],
	"з": [RIGHT, PINKY], "х": [RIGHT, PINKY], "ъ": [RIGHT, PINKY],
	"\\": [RIGHT, PINKY], "ж": [RIGHT, PINKY], "э": [RIGHT, PINKY],
	".": [RIGHT, PINKY], "ShiftR": [RIGHT, PINKY], "←": [RIGHT, PINKY],
	"↵": [RIGHT, PINKY], "Ctrl": [RIGHT, PINKY], "Win": [RIGHT, PINKY],
	"Alt": [RIGHT, PINKY], "глобус": [RIGHT, THUMB],
	# голый пробел: в игре рука большого несёт подпись («пробел:Л» /
	# «пробел:П»); это дефолт — покоящийся большой левой.
	"пробел": [LEFT, THUMB],
}

## Рука клавиши: +1 у левой, −1 у правой (знак живёт в зеркалировании
## x смещений и азимутов).
static func side_of(h: int) -> float:
	return 1.0 if h == LEFT else -1.0


static func side_name(h: int) -> String:
	return "L" if h == LEFT else "R"


## [рука, палец] клавиши; [-1, -1] если клавиши нет в карте.
## Пробел поддержан подписями «пробел:Л» / «пробел:П» (большой СВОБОД-
## ной руки); латиница мапится в свою русскую клавишу (физически одна).
static func finger_of(s: String) -> Array:
	var e: Variant = FINGER_MAP.get(s)
	if e != null:
		return [(e as Array)[0] as int, (e as Array)[1] as int]
	if s.begins_with("пробел:"):
		return [(LEFT if s.ends_with("Л") else RIGHT), THUMB]
	if s.length() == 1:
		var lo := s.to_lower()
		if lo != s:
			e = FINGER_MAP.get(lo)
			if e != null:
				return [(e as Array)[0] as int, (e as Array)[1] as int]
		# Латиница: у той же клавиши русская пара (Kbd.RU_EN двусторонняя).
		for ru in Kbd.RU_EN.keys():
			if String(Kbd.RU_EN[ru]) == lo:
				e = FINGER_MAP.get(String(ru))
				if e != null:
					return [(e as Array)[0] as int,
						(e as Array)[1] as int]
	return [-1, -1]


## Рука клавиши (int): LEFT/RIGHT, из карты пальцев.
static func hand_of(s: String) -> int:
	return finger_of(s)[0] as int


## Подпись клавиши ДОСКИ по подписи события: строчная буква (латиница —
## через свою русскую пару), «пробел:Л/П» как есть. По ней ищется и
## прямоугольник клавиши, и запечённая поза нажатия.
##
## Кириллица возвращается САМА СОБОЙ и раньше обратного поиска: таблица
## RU_EN двусторонняя, и «м» находила в ней латинскую «v» (там есть пара
## v→м) — подсказка руки на «м» тогда искала позу «v», не находила её и
## молчала (ловил combo_test 05.11.2026).
static func key_label(sig: String) -> String:
	if sig.begins_with("пробел:"):
		return sig
	if sig.length() == 1:
		var lo := sig.to_lower()
		var cp := lo.unicode_at(0)
		if cp >= 0x0400 and cp <= 0x04FF:
			return lo
		for ru in Kbd.RU_EN.keys():
			if String(Kbd.RU_EN[ru]) == lo:
				return String(ru)
		return lo
	return sig


## Палец подсказки: [рука, палец] или [-1, -1] (чужая подпись не двигает
## руку). Регистр буквы палец не меняет, латиница — та же клавиша.
static func hint_finger(sig: String) -> Array:
	return finger_of(sig)


## Точка подсказки по подписи: центр ПЛОЩАДИ клавиши; половины пробела —
## по своей стороне, на высоте ряда.
static func hint_point(bs: Array, sig: String) -> Vector2:
	var r := sig_rect(bs, sig)
	if r.size == Vector2.ZERO:
		return Vector2.ZERO
	return r.get_center()


## Прямоугольник подписи: половины пробела («пробел:Л»/«пробел:П») —
## своя половина; остальное — клавиша доски по подписи.
static func sig_rect(bs: Array, sig: String) -> Rect2:
	if sig.begins_with("пробел:") and not sig.ends_with(":"):
		var sp := key_rect(bs, "пробел")
		if sp.size == Vector2.ZERO:
			return Rect2()
		var half_l := sig.ends_with("Л")
		return Rect2(sp.position.x + sp.size.x * (0.0 if half_l else 0.5),
			sp.position.y, sp.size.x * 0.5, sp.size.y)
	return key_rect(bs, sig)


## Прямоугольник клавиши по подписи — мера самого списка buttons().
static func key_rect(bs: Array, s: String) -> Rect2:
	for b in bs:
		if String(b["s"]) == s:
			return b["r"] as Rect2
	return Rect2()


## Шаг доски (питч) — ШАГ колонок буквенного ряда, не ширина клавиши:
## клавиши стоят с зазором; веер кончиков кисти идёт по клавишам с их
## зазорами.
static func pitch_of(bs: Array) -> float:
	var best := 0.0
	for b0 in bs:
		var r0 := b0["r"] as Rect2
		if not Kbd.is_plain_letter(String(b0["s"])):
			continue
		for b1 in bs:
			var r1 := b1["r"] as Rect2
			if not Kbd.is_plain_letter(String(b1["s"])):
				continue
			if r0.position.y != r1.position.y:
				continue
			var dx := absf(r1.position.x - r0.position.x)
			if dx > 0.01 and (best == 0.0 or dx < best):
				best = dx
	if best > 0.0:
		return best
	for b0 in bs:
		if Kbd.is_plain_letter(String(b0["s"])):
			return (b0["r"] as Rect2).size.x
	return 0.0


## Центр точки нажатия клавиши.
static func key_center(bs: Array, s: String) -> Vector2:
	var r := key_rect(bs, s)
	if r.size == Vector2.ZERO:
		return Vector2.ZERO
	return r.position + r.size * 0.5


## Высота ряда — у буквенной клавиши (все ряды одной высоты).
static func _row_h(bs: Array, pitch: float) -> float:
	for b in bs:
		if Kbd.is_plain_letter(String(b["s"])):
			return (b["r"] as Rect2).size.y
	return pitch


## Малая клавиша — буквенного шага ширина (клавиши одного ряда одной
## высоты, малость меряется шириной).
static func _is_small(r: Rect2, pitch: float, bs: Array) -> bool:
	return r.size.x <= pitch * 1.05 + 0.01 \
		and r.size.y <= _row_h(bs, pitch) * 1.05 + 0.01


## ---------- доска → миллиметры кисти ----------
##
## Доска исследования симметрична относительно x = 0, а доска игры
## заполняет область целиком — значит центр доски и есть x = 0.
## Масштабы меряются по САМОЙ доске игры: sx — по девяти шагам дом-ряда
## «ф»…«ж» (в мм это 9·PITCH), sy — по шагу ряда «й»→«ф» (в мм это
## ROW_STEP). Так раскладка игры ложится на модель без выдуманных
## констант; остаток (у игры зазор 8 px против 1 мм) добирается сдвигом
## кисти к нажимаемой клавише.
static func board_map(bs: Array) -> Dictionary:
	var row := ["ф", "ы", "в", "а", "п", "р", "о", "л", "д", "ж"]
	var first := key_rect(bs, row[0]).get_center()
	var last := key_rect(bs, row[row.size() - 1]).get_center()
	var q := key_rect(bs, "й").get_center()
	if first == Vector2.ZERO or last == Vector2.ZERO or q == Vector2.ZERO:
		return {}
	var sx := (last.x - first.x) / (float(row.size() - 1) * PITCH_MM)
	var sy := (first.y - q.y) / ROW_STEP_MM
	if sx <= 0.0 or sy <= 0.0:
		return {}
	var lo := INF
	var hi := -INF
	for b in bs:
		var r: Rect2 = b["r"]
		lo = minf(lo, r.position.x)
		hi = maxf(hi, r.end.x)
	return {"sx": sx, "sy": sy, "sr": (sx + sy) * 0.5,
		"ox": (lo + hi) * 0.5, "oy": first.y}


## Глубина кисти на экране: доля честной проекции сверху (1.0 — как
## сверху, 0.5 — как из-под 30°, как в самом исследовании). На телефоне
## клавиатура прижата к низу, и честная проекция оставляет от кисти одни
## пальцы: ладонь (85 мм) в 60 мм не влезает. Ужимаем ТОЛЬКО глубину —
## размах пальцев по x остаётся точным, подушечки садятся на клавиши
## сдвигом кисти.
static var depth_k := 1.0


## Мировые мм исследования → пиксели доски.
static func to_px(map: Dictionary, p: Vector3) -> Vector2:
	return Vector2(float(map["ox"]) + p.x * float(map["sx"]),
		float(map["oy"]) - (p.y - HOME_Y) * float(map["sy"]) * depth_k)


## ---------- поза кадра ----------

## Покой обеих кистей НА ЭТОЙ доске: плоские позы из запечённых данных
## плюс карта доски и поправка покоя (чтобы подушечки легли на дом-
## клавиши игры). Пересчитывается только на смену доски.
static func rest_both(bs: Array) -> Dictionary:
	var map := board_map(bs)
	if map.is_empty():
		return {}
	var out := {"map": map, "shift": {}}
	for h in [LEFT, RIGHT]:
		var side := side_name(h)
		var flat: Array = (HandsPoses.HOME[side] as Array).duplicate()
		out[h] = flat
		(out["shift"] as Dictionary)[h] = _rest_shift(bs, h, flat, map)
	return out


## Поправка покоя: средняя невязка подушечек четырёх пальцев до их
## дом-клавиш (одна на кисть — жёсткий сдвиг, форма кисти не меняется).
static func _rest_shift(bs: Array, h: int, flat: Array,
		map: Dictionary) -> Vector2:
	var side := side_name(h)
	var root_x := float(HandsPoses.ROOT_MM[side])
	var acc := Vector2.ZERO
	var n := 0
	var homes: Dictionary = HOME_KEY[h] as Dictionary
	for f in [INDEX, MIDDLE, RING, PINKY]:
		var r := key_rect(bs, String(homes[f]))
		if r.size == Vector2.ZERO:
			continue
		var pad := Hands3D.pad(flat, side, root_x, Hands3D.RAY_OF[f])
		acc += r.get_center() - to_px(map, pad)
		n += 1
	return acc / float(n) if n > 0 else Vector2.ZERO


## Поза кисти на кадр: покой + нажатия. presses = {рука: {палец:
## [подпись клавиши, ход 0..1, ...]}} (лишние поля — фаза и действие
## удержания, руки они не касаются).
##
## Каждый палец берёт СВОИ четыре угла из своей запечённой позы, плечо —
## средневзвешенное (сумма весов ≤ 1), сдвиг — туда, где подушечка этой
## позы оказывается на клавише игры (у широких клавиш — ближайшая точка
## с отступом, а не центр: иначе большой уезжал бы на середину пробела).
static func pose_of(bs: Array, h: int, rest: Dictionary,
		presses: Dictionary) -> Dictionary:
	if rest.is_empty() or not rest.has(h):
		return {}
	var side := side_name(h)
	var root_x := float(HandsPoses.ROOT_MM[side])
	var map: Dictionary = rest["map"] as Dictionary
	var base: Array = rest[h] as Array
	var pitch := pitch_of(bs)
	var per: Dictionary = presses.get(h, {}) as Dictionary
	var poses := {}
	var wsum := 0.0
	var shift := Vector2.ZERO
	var sw := 0.0
	for f in per.keys():
		var e: Array = per[f] as Array
		if e.size() < 2:
			continue
		var label := String(e[0])
		var w := clampf(float(e[1]), 0.0, 1.0)
		if w <= 0.0001:
			continue
		var pd: Dictionary = HandsPoses.PRESS[side] as Dictionary
		if not pd.has(label):
			continue
		var p: Array = pd[label] as Array
		poses[f] = [p, w]
		wsum += w
		var r := sig_rect(bs, label)
		if r.size == Vector2.ZERO:
			continue
		var ray: String = Hands3D.RAY_OF[f] if f != THUMB else "I"
		var at := to_px(map, Hands3D.pad(p, side, root_x, ray))
		shift += (pad_target(bs, r, at, pitch) - at) * w
		sw += w
	var rest_shift: Vector2 = (rest["shift"] as Dictionary).get(h, Vector2.ZERO)
	var total := clampf(sw, 0.0, 1.0)
	var off := rest_shift * (1.0 - total) + shift
	return {"flat": Hands3D.blend_many(base, poses), "shift": off,
		"map": map}


## Точка посадки на клавишу: малая — центр; широкая — ближайшая к
## подушечке точка с отступом в полклавиши (палец остаётся там, где его
## поставила модель, а не едет в середину пробела).
static func pad_target(bs: Array, r: Rect2, at: Vector2,
		pitch: float) -> Vector2:
	if pitch <= 0.0 or _is_small(r, pitch, bs):
		return r.get_center()
	var iy := minf(0.5 * _row_h(bs, pitch), r.size.y * 0.5)
	var ix := minf(0.5 * pitch, r.size.x * 0.5)
	return Vector2(clampf(at.x, r.position.x + ix, r.end.x - ix),
		clampf(at.y, r.position.y + iy, r.end.y - iy))


## ---------- РИСОВАНИЕ ----------

## Обе кисти на доске. presses — как у pose_of; кисть рисуется ОДНИМ
## замкнутым контуром (запечённый силуэт модели), линией и лёгкой
## заливкой. Кэш — по состоянию позы: в покое контур не пересобирается.
static func draw_both(ci: CanvasItem, bs: Array, rest: Dictionary,
		presses: Dictionary, ink: Color, cache: Variant = null) -> void:
	if rest.is_empty():
		return
	var pitch := pitch_of(bs)
	if pitch <= 0.0:
		return
	var polys: Dictionary
	var key := "%.3f|%s" % [pitch, str(presses)]
	if cache is Dictionary:
		var cd: Dictionary = cache
		if cd.has(key) and cd[key] is Dictionary:
			polys = cd[key] as Dictionary
		else:
			polys = _outlines(bs, rest, presses)
			cd.clear()
			cd[key] = polys
	else:
		polys = _outlines(bs, rest, presses)
	for h in polys.keys():
		var poly: PackedVector2Array = polys[h]
		if poly.size() >= 3:
			_draw_contour(ci, poly, pitch, ink)


## Контуры обеих кистей: {рука: PackedVector2Array}.
static func _outlines(bs: Array, rest: Dictionary,
		presses: Dictionary) -> Dictionary:
	var polys := {}
	for h in [LEFT, RIGHT]:
		var poly := hand_outline(bs, rest, presses, h)
		if poly.size() >= 3:
			polys[h] = poly
	return polys


## Контур ОДНОЙ кисти — ЧИСТАЯ МЕРА: ею рисует draw_both, её же меряют
## тесты (headless картинку не рисует, а геометрию проверяет числом).
##
## Силуэт НЕ собирается в игре: он запечён с ПОЛЯ 3D-модели
## (tools/hand3d/bake_outline.gd → hands_shape.gd) вдоль локальной z, то
## есть ровно той осью, которой смотрит игра. Здесь остаётся проекция:
## луч полярной меры → точка в системе кисти → мир → пиксели доски.
##
## Почему запечено, а не собрано: объединение проекций примитивов — не
## проекция объединения. Сглаживание smin выносит настоящую поверхность
## на 5.8 мм наружу, и объединение теней этого не знает — на контуре
## появлялись ступеньки и «шишах» у большого пальца (автор 05.11.2026).
static func hand_outline(bs: Array, rest: Dictionary, presses: Dictionary,
		h: int) -> PackedVector2Array:
	var st := pose_of(bs, h, rest, presses)
	if st.is_empty():
		return PackedVector2Array()
	var side := side_name(h)
	var root_x := float(HandsPoses.ROOT_MM[side])
	var map: Dictionary = st["map"] as Dictionary
	var off: Vector2 = st["shift"] as Vector2
	var flat: Array = st["flat"] as Array
	var radii := shape_radii(h, presses)
	if radii.is_empty():
		return PackedVector2Array()
	var xf := Hands3D.hand_xf(Hands3D.arm_of(flat))
	var c: Vector2 = Shape.CENTER
	var n := radii.size()
	var palm := PackedVector2Array()
	palm.resize(n)
	for k in n:
		var a := TAU * float(k) / float(n)
		var q := c + Vector2(cos(a), sin(a)) * float(radii[k])
		palm[k] = to_px(map, Hands3D.to_world(side, root_x,
			xf * Vector3(q.x, q.y, 0.0))) + off
	# Пальцы в полярную меру не влезают (они торчат от ладони радиально,
	# каждый занимает ~10°, и щели между ними становятся широкими
	# клиньями), поэтому ладонь запечена ОТДЕЛЬНО, а каждый палец —
	# лента из своей цепи и своих радиусов кожи (SKIN_R / THUMB_R).
	var acc := palm
	for ray in Hands3D.FINGERS:
		var band := finger_band(flat, side, root_x, ray, map, xf, off)
		if band.size() < 3:
			continue
		acc = _biggest(Geometry2D.merge_polygons(acc, band))
	var th := thumb_band(flat, side, root_x, map, xf, off)
	if th.size() >= 3:
		acc = _biggest(Geometry2D.merge_polygons(acc, th))
	return acc


## Лента ОДНОГО пальца: проекция его кожи — три усечённых конуса вдоль
## цепи (Hands3D.finger_fk + SKIN_R). Проекция конуса — выпуклая оболочка
## двух спроецированных кругов, и оболочка считается УЖЕ в пикселях:
## доска растянута по y (sx ≈ 1.78, sy ≈ 1.94), поэтому круг модели
## становится эллипсом, и оболочка в мм дала бы косые бока.
static func finger_band(flat: Array, side: String, root_x: float,
		ray: String, map: Dictionary, xf: Transform3D,
		off: Vector2 = Vector2.ZERO) -> PackedVector2Array:
	var pts := Hands3D.finger_fk(ray, Hands3D.finger_angles(flat, ray))
	return _chain_band(pts, Hands3D.SKIN_R[ray] as Array, side, root_x,
		map, xf, off)


## Лента большого: та же мера, что у пальцев, но цепь своя (thumb_fk:
## [CMC, MCP, IP, кончик]) и радиусы свои (THUMB_R). Из полярной ладони
## большой выведен: он торчит от ладони, и полярный контур превращал его
## в тонкий шип — а «шишах» на его стороне и был жалобой автора.
static func thumb_band(flat: Array, side: String, root_x: float,
		map: Dictionary, xf: Transform3D,
		off: Vector2 = Vector2.ZERO) -> PackedVector2Array:
	var fk := Hands3D.thumb_fk(Hands3D.thumb_angles(flat))
	var pts: PackedVector3Array = fk["pts"] as PackedVector3Array
	return _chain_band(pts, Hands3D.THUMB_R as Array, side, root_x,
		map, xf, off)


static func _chain_band(pts: PackedVector3Array, rs: Array, side: String,
		root_x: float, map: Dictionary, xf: Transform3D,
		off: Vector2) -> PackedVector2Array:
	var acc := PackedVector2Array()
	for i in 3:
		var cap := _cap_px(xf * pts[i], float(rs[i]),
			xf * pts[i + 1], float(rs[i + 1]), side, root_x, map, off)
		if cap.size() < 3:
			continue
		acc = cap if acc.is_empty() else _biggest(
			Geometry2D.merge_polygons(acc, cap))
	return acc


## Проекция усечённого конуса: выпуклая оболочка двух кругов.
const CAP_SEG := 24


static func _cap_px(a: Vector3, ra: float, b: Vector3, rb: float,
		side: String, root_x: float, map: Dictionary,
		off: Vector2 = Vector2.ZERO) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for v in [[a, ra], [b, rb]]:
		var q: Vector3 = v[0] as Vector3
		var r := float(v[1])
		for j in CAP_SEG:
			var t := TAU * float(j) / float(CAP_SEG)
			pts.append(to_px(map, Hands3D.to_world(side, root_x,
				Vector3(q.x + cos(t) * r, q.y + sin(t) * r, 0.0))) + off)
	return Geometry2D.convex_hull(pts)


## Самый крупный кусок объединения (Clipper отдаёт и дырки отдельными
## полигонами; у кисти дырок нет — берём тело).
static func _biggest(polys: Array) -> PackedVector2Array:
	var best := PackedVector2Array()
	var ba := 0.0
	for p in polys:
		var poly: PackedVector2Array = p
		var a := absf(_poly_area(poly))
		if a > ba:
			ba = a
			best = poly
	return best


## Радиусы контура на кадр: покой, подтянутый к позам нажатий ровно теми
## же весами, какими Hands3D.blend_many собирает позу (сумма весов ≤ 1).
## Промежуточная поза — тоже честный контур: топология у всех поз одна,
## поэтому радиусы смешиваются поэлементно.
static func shape_radii(h: int, presses: Dictionary) -> PackedFloat32Array:
	var side := side_name(h)
	var table: Dictionary = Shape.RADII[side] as Dictionary
	var base: Array = table[""] as Array
	var acc := {}
	var wsum := 0.0
	var per: Dictionary = presses.get(h, {}) as Dictionary
	for f in per.keys():
		var e: Array = per[f] as Array
		if e.size() < 2:
			continue
		var label := String(e[0])
		var w := clampf(float(e[1]), 0.0, 1.0)
		if w <= 0.0001 or not table.has(label):
			continue
		acc[label] = float(acc.get(label, 0.0)) + w
		wsum += w
	var k0 := clampf(1.0 - wsum, 0.0, 1.0)
	var out := PackedFloat32Array()
	out.resize(base.size())
	for i in out.size():
		var v := float(base[i]) * k0
		for lb in acc.keys():
			var arr: Array = table[lb] as Array
			v += float(arr[i]) * float(acc[lb])
		out[i] = v
	return out


## Площадь полигона (шнурок) — мера контура для тестов и диагностики.
static func _poly_area(p: PackedVector2Array) -> float:
	var a := 0.0
	var n := p.size()
	for i in n:
		var q := p[(i + 1) % n]
		a += p[i].x * q.y - q.x * p[i].y
	return a * 0.5


## Контур руки: замкнутая линия и ЛЁГКАЯ заливка (автор 27.10.2026:
## «только контуры рук», не скелет и не 3D). Заливка не для объёма —
## без неё узкий палец читается двумя чёрточками, а не пальцем; alpha
## низкая, чтобы подписи клавиш оставались видны. Толщина линии — от
## питча (на мелкой доске не игла, на крупной не жирная).
##
## alpha 0.14, а не 0.10: на 0.10 кисть на живой доске читалась ОДНИМИ
## ЛИНИЯМИ (проверено кадром vis-26: внутри ладони цвет не отличался от
## фона), и контур выглядел каракулями. Подписи клавиш под 14% чернил
## остаются различимыми — это и был выбор автора 27.10.2026.
static var fill_a := 0.14
static var line_a := 0.75
static var line_w := 0.07


static func _draw_contour(ci: CanvasItem, poly: PackedVector2Array,
		pitch: float, ink: Color) -> void:
	var fill := ink
	fill.a = fill_a
	var line := ink
	line.a = line_a
	var loop := PackedVector2Array(poly)
	loop.append(poly[0])
	ci.draw_colored_polygon(poly, fill)
	ci.draw_polyline(loop, line, clampf(pitch * line_w, 2.0, 5.0), true)


## Демонстрация подсказки: палец идёт к клавише, стоит на ней и
## возвращается в покой. Тайминги одного цикла, секунды.
const HINT_RISE_T := 0.34
const HINT_HOLD_T := 0.42
const HINT_FALL_T := 0.34
const HINT_GAP_T := 0.90
const HINT_CYCLE_T := HINT_RISE_T + HINT_HOLD_T + HINT_FALL_T + HINT_GAP_T

## Ход демонстрации в фазе t: подъём — стоим — спад — пауза, дальше
## цикл заново. ЧИСТАЯ МЕРА: ею ведёт руку main, её меряет hands_test
## (симметрия подъёма/спада, период, покой в паузе).
static func hint_depth(t: float) -> float:
	var x := fposmod(t, HINT_CYCLE_T)
	if x < HINT_RISE_T:
		return smoothstep(0.0, 1.0, x / HINT_RISE_T)
	if x < HINT_RISE_T + HINT_HOLD_T:
		return 1.0
	if x < HINT_RISE_T + HINT_HOLD_T + HINT_FALL_T:
		return 1.0 - smoothstep(0.0, 1.0,
			(x - HINT_RISE_T - HINT_HOLD_T) / HINT_FALL_T)
	return 0.0
