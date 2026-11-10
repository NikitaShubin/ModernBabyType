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
	# Стрелки — кластер правее правого Ctrl, под правой кистью. В наборе
	# они пока НЕ участвуют (Kbd._is_blocked), палец нужен карте, чтобы
	# доска оставалась покрытой целиком.
	"◀": [RIGHT, PINKY], "↕": [RIGHT, PINKY], "▶": [RIGHT, PINKY],
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


## Номер палитры пальца (`Ui.FINGER_KEY_*`): зона пальца — это индекс
## в массивах, а сам цвет берётся из круга по `Ui.FINGER_SLOT` (шаг по
## доске — прыжок на 108°, см. шапку палитры в ui.gd). Зона подсказки
## индекс больше не использует (цвет один на все пальцы), но заливки
## клавиш красятся им. У левой руки пальцы в карте обратны
## порядку (мизинец 4 … большой 0), у правой — совпадают, поэтому зоны
## идут вдоль доски слева направо.
## Подпись может нести сторону («пробел:Л» / «пробел:П»): половины пробела
## — большие разных рук. Служебных клавиш в зоне больше нет, сторону им
## нести нечему (см. key_tints). −1 — пальца нет.
static func tint_index(s: String) -> int:
	var side := ""
	var base := s
	if s.ends_with(":Л") or s.ends_with(":П"):
		side = s.right(1)
		base = s.left(s.length() - 2)
	var f := finger_of(base)
	if (f[0] as int) < 0:
		return -1
	var finger: int = f[1]
	var hand: int = f[0]
	if side == "Л":
		hand = LEFT
	elif side == "П":
		hand = RIGHT
	return (4 - finger) if hand == LEFT else (5 + finger)


## Шифт любой стороны — модификатор, а не «клавиша пальца»: в зоне
## подсказки он горит ТОЛЬКО когда сам входит в набор (см. main._hot_zones).
## Иначе зона левого мизинца зажигала бы левый шифт рядом с настоящим
## правым, и на доске горели бы оба сразу (автор 10.11.2026: «и левые, и
## правые шифты… и с двух сторон!»).
static func is_shift(s: String) -> bool:
	return s == "Shift" or s == "ShiftR"


## Панели ЗОНЫ ПОДСКАЗКИ — единственная заливка клавиши «по пальцу».
## В покое доска нейтральна (цвет приходит только с подсказкой), поэтому
## строятся только горячие панели. ЦВЕТ ОДИН НА ВСЕ ПАЛЬЦЫ (автор
## 10.11.2026): горит всегда один палец, различать hue нечего. Строится
## раз при создании экрана (в кадре новых панелей нет), меняется темой
## на месте (`repaint_tints`).
##
## МЁРТВЫЕ КЛАВИШИ ПАНЕЛИ НЕ ПОЛУЧАЮТ (автор 10.11.2026: «при подсветке
## секции кнопок почему-то выделяются сразу и левые, и правые шифты,
## контролы и прочее… мизинцем не нажимают вроде бы и шифт, и контрл, и
## альт и прочее, да ещё и с двух сторон!»). Причина была в подписи:
## «Ctrl»/«Alt»/«Win» стоят в низу ДВАЖДЫ, а в карте пальцев записаны за
## правым мизинцем — панель на голую подпись попадала в зону правого
## мизинца, и `Kbd.draw` красил по ней ОБЕ клавиши сразу. В наборе эти
## клавиши всё равно не участвуют, поэтому зону им не красим вовсе: в
## зоне остаются только живые клавиши ОДНОГО пальца ОДНОЙ руки.
##
## Пробел здесь ДВУМЯ половинами («пробел:Л»/«пробел:П») — подсказка
## красит именно ту половину, которой жать, хотя цвет у обеих один.
static func key_tints(night: bool, radius: float, bw: float) -> Dictionary:
	var out := {}
	for row in Kbd.all_rows(true):
		for label in row:
			var s := String(label)
			# У пробела заливка не целая, а двумя половинами (ниже):
			# голая запись «пробел» в словаре только мешала бы.
			if s == "пробел":
				continue
			# Мёртвой клавише панель не нужна вовсе: её тап мимо, и в
			# зону пальца она попадать не должна.
			if tint_index(s) < 0 or dead_key(s):
				continue
			out[s] = Ui.finger_sb(night, radius, bw)
	out["пробел:Л"] = Ui.finger_half_sb("Л", night, radius, bw)
	out["пробел:П"] = Ui.finger_half_sb("П", night, radius, bw)
	return out


## Индекс ЗАЛИВКИ клавиши. У пробела заливка ОДНА на всю клавишу (автор
## 08.11.2026: «пробел пусть будет одного цвета. Его раскрашивать двумя
## цветами как-то странно»): обе половины красятся цветом самой клавиши —
## левого большого (в карте «пробел» → LEFT/THUMB), хотя жмут её любым.
## Половины остались только геометрией подсказки.
static func paint_index(s: String) -> int:
	if s.begins_with("пробел"):
		return tint_index("пробел")
	return tint_index(s)


## ЗАЛИВКИ ЛИЦ КЛАВИШ по пальцу (автор 10.11.2026: «виртуальная
## клавиатура раскрашивает фон вокруг кнопок, а не сами кнопки. Это
## делает линию границ нечитаемой»). Цвет лежит В клавише (`Ui.FINGER_KEY_*`),
## зазоры показывает нейтральная плита доски (`Ui.KEY_PLATE_*`).
##
## Панель ОДНА НА ПАЛЕЦ: клавиши пальца делят один StyleBox, поэтому
## темой и переходом глоу они перекрашиваются НА МЕСТЕ, а в кадре новых
## объектов нет. Мёртвые клавиши (Tab/Caps/Ctrl/Win/Alt, стрелки) заливки
## не получают вовсе — их палец ничему не учит, они остаются бумагой
## базовой панели. Пробел — одна клавиша и одна заливка (левый большой).
static func key_fills(night: bool, radius: float, bw: float) -> Dictionary:
	var out := {}
	var by_finger := {}
	for row in Kbd.all_rows(true):
		for label in row:
			var s := String(label)
			if s == "пробел":
				continue
			var i := tint_index(s)
			if i < 0 or dead_key(s):
				continue
			out[s] = _fill_box(by_finger, i, night, radius, bw)
	out["пробел"] = _fill_box(by_finger, paint_index("пробел"), night, radius, bw)
	return out


## Панель пальца из набора `key_fills` (строится при первом обращении).
static func _fill_box(by_finger: Dictionary, i: int, night: bool,
		radius: float, bw: float) -> StyleBoxFlat:
	if not by_finger.has(i):
		var pal: Array = Ui.FINGER_KEY_NIGHT if night else Ui.FINGER_KEY_DAY
		var col: Color = pal[clampi(i, 0, pal.size() - 1)]
		by_finger[i] = Ui.key_fill_sb(col, night, radius, bw)
	return by_finger[i] as StyleBoxFlat


## Мёртвая (заблокированная) клавиша; подпись может нести сторону.
static func dead_key(s: String) -> bool:
	var base := s
	if s.ends_with(":Л") or s.ends_with(":П"):
		base = s.left(s.length() - 2)
	return Kbd.is_dead(base)


## Цвет заливки пальца по теме.
static func fill_colour(i: int, night: bool) -> Color:
	var pal: Array = Ui.FINGER_KEY_NIGHT if night else Ui.FINGER_KEY_DAY
	return pal[clampi(i, 0, pal.size() - 1)] as Color


## Перекрасить заливки на переходе «бумага ↔ цвет пальца» и при смене
## темы. `glow` 0 — клавиша бумажная, 1 — полный цвет пальца. Концы
## ставятся ТОЧНЫМИ цветами палитры: lerp с весом 1.0 оставляет в младших
## битах мусор, и «вернулось в покой» перестало бы быть равенством
## (ловил combo_test). Ночь меняет и рамку — она тоже общая с бумагой.
static func paint_fills(fills: Dictionary, night: bool, glow: float) -> void:
	var paper: Color = Ui.SURFACE_ALT_NIGHT if night else Ui.SURFACE_DAY
	var edge: Color = Ui.LINE_NIGHT if night else Ui.LINE_DAY
	for s in fills:
		var i := paint_index(String(s))
		if i < 0:
			continue
		var sb: StyleBoxFlat = fills[s]
		sb.border_color = edge
		if glow >= 1.0:
			sb.bg_color = fill_colour(i, night)
		elif glow <= 0.0:
			sb.bg_color = paper
		else:
			sb.bg_color = paper.lerp(fill_colour(i, night), glow)


## Перекрасить панели зон в другую тему на месте: узлы держат те же
## StyleBox, поэтому день↔ночь не рождает ни одной новой панели.
static func repaint_tints(boxes: Dictionary, night: bool) -> void:
	var bg: Color = Ui.HINT_ZONE_NIGHT if night else Ui.HINT_ZONE_DAY
	var edge: Color = Ui.HINT_ZONE_EDGE_NIGHT if night else Ui.HINT_ZONE_EDGE_DAY
	for s in boxes:
		var sb: StyleBoxFlat = boxes[s]
		sb.bg_color = bg
		sb.border_color = edge


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
## своя половина; остальное — клавиша доски по подписи. Граница половин —
## `Kbd.space_split` (середина между ладонями), а не середина клавиши:
## правая подушечка большого стоит на ~0.8 ширины пробела.
static func sig_rect(bs: Array, sig: String) -> Rect2:
	if sig.begins_with("пробел:") and not sig.ends_with(":"):
		var sp := key_rect(bs, "пробел")
		if sp.size == Vector2.ZERO:
			return Rect2()
		var split := Kbd.space_split(bs)
		var half_l := sig.ends_with("Л")
		var x0 := sp.position.x if half_l else split
		var x1 := split if half_l else sp.end.x
		return Rect2(x0, sp.position.y, x1 - x0, sp.size.y)
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
## средневзвешенное (сумма весов ≤ 1), сдвиг — СРЕДНЕЕ по нажатиям (не
## сумма: иначе две клавиши сразу складывали поправки и кисть уезжала за
## экран), каждая поправка — туда, где подушечка этой позы оказывается на
## клавише игры (у широких клавиш — ближайшая точка с отступом, а не
## центр: иначе большой уезжал бы на середину пробела).
##
## ПРОБЕЛ — исключение (автор 07.11.2026: «при нажатии пробела правым
## пальцем перемещается вся рука, хотя это бессмысленно»): подушечка
## большого уже лежит на пробеле, и кисть не едет вовсе — сдвиг остаётся
## покойным (`rest_shift`), ход несёт только сам палец. Половины пробела
## (`sig_rect`) нужны подсказке, а не позе. Клавиша берётся ЦЕЛАЯ, без
## отступа от края: отступ в полпитча у половины пробела (а она уже
## клавиши) выталкивал кисть.
static func pose_of(bs: Array, h: int, rest: Dictionary,
		presses: Dictionary) -> Dictionary:
	if rest.is_empty() or not rest.has(h):
		return {}
	var side := side_name(h)
	var root_x := float(HandsPoses.ROOT_MM[side])
	var map: Dictionary = rest["map"] as Dictionary
	var base: Array = rest[h] as Array
	var pitch := pitch_of(bs)
	var rest_shift: Vector2 = (rest["shift"] as Dictionary).get(h, Vector2.ZERO)
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
		if label.begins_with("пробел:"):
			# Кисть на пробеле НЕ едет: подушечка большого уже на клавише,
			# и «поправка» увела бы всю руку (замер до правки: правая —
			# на 77 px при 1600 и на 166 px при 3120). Движется только
			# сам палец — позой нажатия и подрагиванием (_tap_pose).
			shift += rest_shift * w
			sw += w
			continue
		var r := sig_rect(bs, label)
		if r.size == Vector2.ZERO:
			continue
		var ray: String = Hands3D.RAY_OF[f] if f != THUMB else "I"
		var at := to_px(map, Hands3D.pad(p, side, root_x, ray))
		shift += (pad_target(bs, r, at, pitch) - at) * w
		sw += w
	var total := clampf(sw, 0.0, 1.0)
	# Сдвиг кисти — СРЕДНЕЕ по нажатиям, а не сумма: два одновременных
	# нажатия складывали поправки и уводили кисть с экрана (автор
	# 07.11.2026). При одном нажатии среднее равно самой поправке — прежнее
	# поведение не меняется.
	var avg := rest_shift if sw <= 0.0001 else shift / sw
	var off := rest_shift * (1.0 - total) + avg * total
	return {"flat": _tap_pose(Hands3D.blend_many(base, poses), per),
		"shift": off, "map": map}


## МЕЛКОЕ ПОДРАГИВАНИЕ НАЖАТОГО ПАЛЬЦА (автор 07.11.2026: «при нажатии на
## любую клавишу, которая уже находится под пальцем, желательно видеть
## мелкое подрагивание этого пальца. Иначе нет ощущения нажатия»).
##
## У дом-клавиш запечённая поза нажатия почти совпадает с покоем, и кадр
## не меняется — нажатие не видно. Правило ОДНО и на все клавиши: к
## сгибу нажимающего пальца добавляется маленькая добавка по его же ходу.
## На дальней клавише палец и так едет на десятки градусов — добавка в
## ней тонет; на дом-клавише она и есть весь ход. Так «подрагивание»
## включается ровно там, где без него нечего смотреть, и не требует
## отдельного признака «клавиша под пальцем».
const TAP_MCP := 2.6
const TAP_PIP := 1.6


static func _tap_pose(flat: Array, per: Dictionary) -> Array:
	var out := flat.duplicate()
	for f in per.keys():
		var e: Array = per[f] as Array
		if e.size() < 2:
			continue
		var w := clampf(float(e[1]), 0.0, 1.0)
		if w <= 0.0001:
			continue
		var finger := int(f)
		if finger == THUMB:
			out[27] = float(out[27]) + TAP_MCP * w
			out[28] = float(out[28]) + TAP_PIP * w
			continue
		if finger < INDEX or finger > PINKY:
			continue
		var i := 8 + (finger - 1) * 4
		out[i] = float(out[i]) + TAP_MCP * w
		out[i + 1] = float(out[i + 1]) + TAP_PIP * w
	return out


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

## Обе кисти на доске. presses — как у pose_of. Кисть рисуется ОДНИМ
## замкнутым контуром (объединение запечённой ладони, четырёх пальцев и
## большого), линией и лёгкой заливкой. Кэш — по состоянию позы: в покое
## контур не пересобирается.
##
## ПОЧЕМУ ОДИН контур, а не линии каждой части (автор 06.11.2026:
## «пальцы физически отделены от остальной части кисти? В результате в
## кадре куча лишних линий… надо объединить все объекты каждой из кистей
## в один объект»): ладонь и пальцы в модели — РАЗНЫЕ тела, и линия их
## стыка ложится внутрь кисти кругами у оснований. Кисть — один объект,
## как её и видит глаз: внешняя граница руки. Пальцы при этом читаются
## выемками силуэта (они в проекции идут вплотную, 1–6 px щели).
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
	var palm := _palm_px(st, h, presses)
	if palm.is_empty():
		return PackedVector2Array()
	var xf := Hands3D.hand_xf(Hands3D.arm_of(flat))
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
	# Кисть — ОДИН объект (автор 06.11.2026: «надо объединить все объекты
	# каждой из кистей в один объект»): ладонь и пальцы в модели — разные
	# тела, и линия их стыка ложилась внутрь кисти мусором. Сглаживание
	# замыканием пробовано и отвергнуто: на пальце шириной 10–30 px оно
	# рвёт кончик (проверено кадром), а выемки силуэта и так скруглены.
	return acc


## Ладонь с предплечьем в пикселях доски — ЧИСТАЯ МЕРА без пальцев.
## Запечена с ПОЛЯ 3D-модели (`tools/hand3d/bake_outline.gd` →
## `hands_shape.gd`) вдоль локальной z, то есть ровно той осью, которой
## смотрит игра. Отдаётся и `hand_outline`, и тестам: те меряют, что
## силуэт кисти — ОДИН объект, а ладонь лежит внутри него.
static func hand_palm(bs: Array, rest: Dictionary, presses: Dictionary,
		h: int) -> PackedVector2Array:
	var st := pose_of(bs, h, rest, presses)
	if st.is_empty():
		return PackedVector2Array()
	return _palm_px(st, h, presses)


## Ладонь по уже посчитанной позе (позу на кадр берут один раз).
static func _palm_px(st: Dictionary, h: int, presses: Dictionary) -> PackedVector2Array:
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
	return palm


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
## же весами, какими Hands3D.blend_many собирает плечо (сумма весов не
## больше единицы). Промежуточная поза — тоже честный контур: топология у
## всех поз одна, поэтому радиусы смешиваются поэлементно.
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
	var den := maxf(1.0, wsum)
	var k0 := 1.0 - wsum / den
	var out := PackedFloat32Array()
	out.resize(base.size())
	for i in out.size():
		var v := float(base[i]) * k0
		for lb in acc.keys():
			var arr: Array = table[lb] as Array
			v += float(arr[i]) * float(acc[lb]) / den
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
## ЛИНИЯМИ (кадр vis-26: внутри ладони цвет не отличался от фона).
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
##
## КОМБИНАЦИЯ — ЭТО ПОСЛЕДОВАТЕЛЬНОСТЬ, А НЕ ОДНОВРЕМЕННОЕ НАЖАТИЕ
## (автор 09.11.2026: «комбинации с шифтом и ему подобные, где на самом
## деле нажатие должно быть не одновременным, а последовательным, надо
## подчёркивать их последовательность в анимации, а не делать
## одновременным»). Шифт жмут ПЕРВЫМ и держат, пока жмут букву, а
## отпускают последним. Поэтому клавиши подсказки встают с разносом
## `HINT_STAGGER_T` в порядке подсказки (шифт/глобус, потом буква), а
## отпускаются в ОБРАТНОМ порядке с разносом `HINT_RELEASE_T`.
## Одиночная подсказка (n = 1) — прежний цикл буква в букву:
## `hint_cycle(1) == HINT_CYCLE_T`.
const HINT_RISE_T := 0.34
const HINT_HOLD_T := 0.42
const HINT_FALL_T := 0.34
const HINT_GAP_T := 0.90
const HINT_STAGGER_T := 0.24
const HINT_RELEASE_T := 0.18
const HINT_CYCLE_T := HINT_RISE_T + HINT_HOLD_T + HINT_FALL_T + HINT_GAP_T


## Период демонстрации для набора из n клавиш. Последняя клавиша встаёт
## позже всех (n−1)·STAGGER, и весь набор ждёт её площадку; отпускание
## разъезжается ещё на (n−1)·RELEASE.
static func hint_cycle(n: int) -> float:
	return HINT_CYCLE_T + float(maxi(n, 1) - 1) * (HINT_STAGGER_T + HINT_RELEASE_T)


## Ход демонстрации i-й клавиши набора из n в фазе t: подъём — стоим —
## спад — пауза, дальше цикл заново. ЧИСТАЯ МЕРА: ею ведёт руку main,
## её меряют hands_test и combo_test (порядок влёта, обратный порядок
## спада, период).
##
## Клавиша i встаёт в [i·STAGGER, i·STAGGER + RISE], стоит до общего
## конца площадки и садится в [FALL_AT + (n−1−i)·RELEASE, ... + FALL]:
## первым отпускается ПОСЛЕДНИЙ (буква), последним — первый (шифт).
static func hint_depth_at(t: float, i: int, n: int) -> float:
	var cnt := maxi(n, 1)
	var idx := clampi(i, 0, cnt - 1)
	var x := fposmod(t, hint_cycle(cnt))
	var rise_at := float(idx) * HINT_STAGGER_T
	var rise_end := rise_at + HINT_RISE_T
	var hold_end := float(cnt - 1) * HINT_STAGGER_T + HINT_RISE_T + HINT_HOLD_T
	var fall_at := hold_end + float(cnt - 1 - idx) * HINT_RELEASE_T
	var fall_end := fall_at + HINT_FALL_T
	if x < rise_at:
		return 0.0
	if x < rise_end:
		return smoothstep(0.0, 1.0, (x - rise_at) / HINT_RISE_T)
	if x < fall_at:
		return 1.0
	if x < fall_end:
		return 1.0 - smoothstep(0.0, 1.0, (x - fall_at) / HINT_FALL_T)
	return 0.0


## Ход одиночной подсказки — прежняя мера (n = 1).
static func hint_depth(t: float) -> float:
	return hint_depth_at(t, 0, 1)
