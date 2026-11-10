extends SceneTree
## ПАЛИТРА ИЗ ФОНОВ (ревизия 17.10.2026). Словарь ролей лежит в ui.gd,
## этот тест проверяет его числами, без единого кадра. Три группы:
##
##   1. КОНТРАСТ (WCAG 1.4.3 текст 4.5:1, 1.4.11 рамка/заливка 3:1) —
##      и не на бумаге роли, а на НАСТОЯЩЕМ фоне: карточка полупро-
##      зрачная и лежит поверх неба, поэтому кладём её на ОБА края
##      градиента meadow (#8fd0ee..#f7f3e8 днём, #0d1526..#2a3a5e ночью).
##   2. ПРАВИЛА СЕМЕЙСТВА (это и есть смысл палитры, а не вкус):
##      один hue на семью, отклонение ≤12° от якоря;
##      hue не меняется при смене темы (≤10°) — иначе «ошибка» днём
##      была бы одним цветом, а ночью другим;
##      светлота заливок состояний одна в обеих темах;
##      насыщенность нейтралей ≤0.06 (серый должен быть серым).
##   3. У каждой парной роли обе темы — иначе забытая половина молча
##      рисуется чужим цветом.
##
## Откуда якоря: hue фонов meadow.gd в OKLCH — небо день 187, горизонт
## 35, солнце 47, холм 133, ночное небо 209. Интерфейс выводится из
## них (см. шапку словаря в ui.gd), а не выбирается отдельно.
##
## Тест чистый: чтение констант и арифметика, поэтому быстрый и не
## зависит ни от машины, ни от шрифтов.

const U := preload("res://scripts/ui.gd")

var _failures: Array[String] = []


func _check(cond: bool, what: String) -> void:
	if not cond:
		_failures.append(what)


## Относительная яркость по WCAG.
func _lum(c: Color) -> float:
	var f := func(v: float) -> float:
		return v / 12.92 if v <= 0.04045 else pow((v + 0.055) / 1.055, 2.4)
	return (
		0.2126 * f.call(c.r)
		+ 0.7152 * f.call(c.g)
		+ 0.0722 * f.call(c.b)
	)


func _cr(a: Color, b: Color) -> float:
	var la: float = _lum(a)
	var lb: float = _lum(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


## Полупрозрачная панель на подложке.
func _flat(c: Color, under: Color) -> Color:
	return Color(
		c.r * c.a + under.r * (1.0 - c.a),
		c.g * c.a + under.g * (1.0 - c.a),
		c.b * c.a + under.b * (1.0 - c.a),
		1.0
	)


## sRGB → OKLab (Bottosson) → L, C, hue. Нужна для правил семейства:
## в HSL одинаково «насыщенные» цвета имеют разную светлоту, и там
## сравнивать нечего.
func _oklch(c: Color) -> Vector3:
	var f := func(v: float) -> float:
		return v / 12.92 if v <= 0.04045 else pow((v + 0.055) / 1.055, 2.4)
	var lin := Vector3(f.call(c.r), f.call(c.g), f.call(c.b))
	var lms := Vector3(
		0.8189330101 * lin.x + 0.3618667424 * lin.y - 0.1288597137 * lin.z,
		0.0329845436 * lin.x + 0.9293118715 * lin.y + 0.0361456387 * lin.z,
		0.0482003018 * lin.x + 0.2643662691 * lin.y + 0.6338517070 * lin.z
	)
	lms = Vector3(
		signf(lms.x) * pow(absf(lms.x), 1.0 / 3.0),
		signf(lms.y) * pow(absf(lms.y), 1.0 / 3.0),
		signf(lms.z) * pow(absf(lms.z), 1.0 / 3.0)
	)
	var lab := Vector3(
		0.2104542553 * lms.x + 0.7936177850 * lms.y - 0.0040720468 * lms.z,
		1.9779984951 * lms.x - 2.4285922050 * lms.y + 0.4505937099 * lms.z,
		0.0259040371 * lms.x + 0.7827717662 * lms.y - 0.8086757660 * lms.z
	)
	var hue := rad_to_deg(atan2(lab.z, lab.y))
	if hue < 0.0:
		hue += 360.0
	return Vector3(lab.x, sqrt(lab.y * lab.y + lab.z * lab.z), hue)


## Расстояние между hue по кругу.
func _hdiff(a: float, b: float) -> float:
	var d: float = fmod(absf(a - b), 360.0)
	if d < 0.0:
		d += 360.0
	return minf(d, 360.0 - d)


func _initialize() -> void:
	# Фоны игры (meadow.gd) — настоящие, не выдуманные для теста.
	var sky_day_top := Color("#8fd0ee")
	var sky_day_hor := Color("#f7f3e8")
	var sky_night_top := Color("#0d1526")
	var sky_night_hor := Color("#2a3a5e")

	# --- 1. Контраст на настоящем фоне.
	var card_day := _flat(U.CARD_DAY, sky_day_hor)
	var card_day_worst := _flat(U.CARD_DAY, sky_day_top)
	var card_night := _flat(U.CARD_NIGHT, sky_night_top)
	var card_night_worst := _flat(U.CARD_NIGHT, sky_night_hor)

	_text(U.UI_TEXT_DAY, card_day, card_day_worst, "текст на карточке, день")
	_text(U.INK_DAY, card_day, card_day_worst, "буква на карточке, день")
	_text(U.DIM_DAY, card_day, card_day_worst, "второстепенный текст, день")
	_text(U.GREY_CHAR_DAY, card_day, card_day_worst, "серая буква, день")
	_text(U.UI_TEXT_NIGHT, card_night, card_night_worst, "текст на карточке, ночь")
	_text(U.INK_NIGHT, card_night, card_night_worst, "буква на карточке, ночь")
	_text(U.DIM_NIGHT, card_night, card_night_worst, "второстепенный текст, ночь")
	_text(U.GREY_CHAR_NIGHT, card_night, card_night_worst, "серая буква, ночь")
	_text(U.UI_TEXT_DAY, U.SURFACE_ALT_DAY, U.SURFACE_ALT_DAY, "текст на кнопке, день")
	_text(U.UI_TEXT_NIGHT, U.SURFACE_ALT_NIGHT, U.SURFACE_ALT_NIGHT, "текст на кнопке, ночь")
	_text(U.SELECT_TEXT_DAY, U.SELECT_DAY, U.SELECT_DAY, "имя на выделенной строке, день")
	_text(U.SELECT_TEXT_NIGHT, U.SELECT_NIGHT, U.SELECT_NIGHT, "имя на выделенной строке, ночь")
	_text(U.ACCENT_INK, U.ACCENT_DAY, U.ACCENT_DAY, "подпись на включённом чипе, день")
	_text(U.ACCENT_INK_NIGHT, U.ACCENT_NIGHT, U.ACCENT_NIGHT, "подпись на включённом чипе, ночь")
	_text(U.DANGER_TEXT_DAY, U.SURFACE_ALT_DAY, U.SURFACE_ALT_DAY, "крестик, день")
	_text(U.DANGER_TEXT_NIGHT, U.SURFACE_ALT_NIGHT, U.SURFACE_ALT_NIGHT, "крестик, ночь")
	_text(U.OK_TEXT_DAY, U.SURFACE_ALT_DAY, U.SURFACE_ALT_DAY, "«верно» на кнопке, день")
	_text(U.OK_TEXT_NIGHT, U.SURFACE_ALT_NIGHT, U.SURFACE_ALT_NIGHT, "«верно» на кнопке, ночь")
	_text(U.STAR_DAY, card_day, card_day_worst, "звезда, день")
	_text(U.STAR_NIGHT, card_night, card_night_worst, "звезда, ночь")
	# Панель подсказки НЕПРОЗРАЧНАЯ (см. ui.gd): её заливка и есть фон
	# подписи, поэтому «худшее небо» тут неуместно — проверяем на ней самой.
	# Полупрозрачный жёлтый давал 2.21:1 ночью и коричневое пятно на
	# насыщенной заливке клавиши днём (кадр 41).
	_text(U.UI_TEXT_DAY, U.HINT_KEY_DAY, U.HINT_KEY_DAY, "подпись подсказки, день")
	_text(U.UI_TEXT_NIGHT, U.HINT_KEY_NIGHT, U.HINT_KEY_NIGHT, "подпись подсказки, ночь")

	# Метка опечатки — элемент, не текст: 3:1, но всё равно по-настоящему.
	_edge(U.ERR_DAY, card_day, card_day_worst, "метка опечатки, день")
	_edge(U.ERR_NIGHT, card_night, card_night_worst, "метка опечатки, ночь")

	# Рамка на своей заливке.
	_edge(U.LINE_DAY, U.SURFACE_ALT_DAY, U.SURFACE_ALT_DAY, "рамка кнопки, день")
	_edge(U.LINE_NIGHT, U.SURFACE_ALT_NIGHT, U.SURFACE_ALT_NIGHT, "рамка кнопки, ночь")
	_edge(U.OK_EDGE_DAY, U.OK_DAY, U.OK_DAY, "рамка «верно», день")
	_edge(U.OK_EDGE_NIGHT, U.OK_NIGHT, U.OK_NIGHT, "рамка «верно», ночь")
	_edge(U.DANGER_EDGE_DAY, U.DANGER_DAY, U.DANGER_DAY, "рамка «ошибка», день")
	_edge(U.DANGER_EDGE_NIGHT, U.DANGER_NIGHT, U.DANGER_NIGHT, "рамка «ошибка», ночь")
	_edge(U.ACCENT_EDGE_DAY, U.ACCENT_DAY, U.ACCENT_DAY, "рамка включённого чипа, день")
	_edge(U.ACCENT_EDGE_NIGHT, U.ACCENT_NIGHT, U.ACCENT_NIGHT, "рамка включённого чипа, ночь")
	_edge(U.PROGRESS_DAY, U.TRACK_DAY, U.TRACK_DAY, "прогресс: заливка на треке, день")
	_edge(U.PROGRESS_NIGHT, U.TRACK_NIGHT, U.TRACK_NIGHT, "прогресс: заливка на треке, ночь")
	_edge(U.BADGE_EDGE_DAY, U.BADGE_DAY, U.BADGE_DAY, "бейдж, день")
	_edge(U.BADGE_EDGE_NIGHT, U.BADGE_NIGHT, U.BADGE_NIGHT, "бейдж, ночь")

	# Фокус: ободок по подложке. Тёмный — на светлом (пустая рамка,
	# включённый чип, жёлтая строка), светлый — на тёмной ночной рамке.
	_edge(U.FOCUS_DARK, U.SURFACE_ALT_DAY, U.SURFACE_ALT_DAY, "фокус на рамке, день")
	_edge(U.FOCUS_DARK, U.ACCENT_DAY, U.ACCENT_DAY, "фокус на включённом чипе, день")
	_edge(U.FOCUS_DARK, U.SELECT_DAY, U.SELECT_DAY, "фокус на выделенной строке, день")
	_edge(U.FOCUS_DARK, U.ACCENT_NIGHT, U.ACCENT_NIGHT, "фокус на включённом чипе, ночь")
	_edge(U.FOCUS_DARK, U.SELECT_NIGHT, U.SELECT_NIGHT, "фокус на выделенной строке, ночь")
	_edge(U.FOCUS_LIGHT, U.SURFACE_ALT_NIGHT, U.SURFACE_ALT_NIGHT, "фокус на ночной рамке")
	_edge(U.FOCUS_LIGHT, card_night, card_night_worst, "фокус на ночной карточке")

	# --- 2. Правила семейства.
	# Тёплые нейтрали дня — от горизонта (40). Насыщенность ≤0.06: серый
	# должен быть серым, иначе он спорит с состояниями.
	_family(U.PAPER_DAY, 40.0, 0.075, "бумага, день")
	_family(U.SURFACE_DAY, 40.0, 0.06, "поверхность, день")
	_family(U.SURFACE_ALT_DAY, 40.0, 0.06, "клавиша, день")
	_family(U.INK_DAY, 40.0, 0.06, "чернила, день")
	_family(U.UI_TEXT_DAY, 40.0, 0.06, "текст, день")
	_family(U.DIM_DAY, 40.0, 0.06, "второстепенный, день")
	_family(U.GREY_CHAR_DAY, 40.0, 0.06, "серая буква, день")
	_family(U.LINE_DAY, 40.0, 0.06, "рамка, день")
	_family(U.LINE_SOFT_DAY, 40.0, 0.08, "тихая рамка, день")
	_family(U.TRACK_DAY, 40.0, 0.08, "трек, день")
	# Ночные поверхности — от ночного неба (210).
	_family(U.PAPER_NIGHT, 210.0, 0.08, "бумага, ночь")
	_family(U.SURFACE_NIGHT, 210.0, 0.08, "поверхность, ночь")
	_family(U.SURFACE_ALT_NIGHT, 210.0, 0.09, "клавиша, ночь")
	_family(U.DIM_NIGHT, 210.0, 0.06, "второстепенный, ночь")
	_family(U.GREY_CHAR_NIGHT, 210.0, 0.06, "серая буква, ночь")
	_family(U.LINE_NIGHT, 210.0, 0.06, "рамка, ночь")
	_family(U.LINE_SOFT_NIGHT, 210.0, 0.09, "тихая рамка, ночь")
	_family(U.TRACK_NIGHT, 210.0, 0.09, "трек, ночь")

	# Hue состояния не едетет при смене темы: значение цвета не зависит
	# от того, день сейчас или ночь.
	_same_hue(U.ACCENT_DAY, U.ACCENT_NIGHT, "акцент")
	_same_hue(U.OK_DAY, U.OK_NIGHT, "верно")
	_same_hue(U.OK_EDGE_DAY, U.OK_EDGE_NIGHT, "рамка «верно»")
	_same_hue(U.OK_TEXT_DAY, U.OK_TEXT_NIGHT, "текст «верно»")
	_same_hue(U.DANGER_DAY, U.DANGER_NIGHT, "ошибка")
	_same_hue(U.DANGER_EDGE_DAY, U.DANGER_EDGE_NIGHT, "рамка «ошибка»")
	_same_hue(U.DANGER_TEXT_DAY, U.DANGER_TEXT_NIGHT, "текст «ошибка»")
	_same_hue(U.ERR_DAY, U.ERR_NIGHT, "метка опечатки")
	_same_hue(U.SELECT_DAY, U.SELECT_NIGHT, "выбор строки")
	_same_hue(U.STAR_DAY, U.STAR_NIGHT, "звезда")
	_same_hue(U.PROGRESS_DAY, U.PROGRESS_NIGHT, "прогресс")
	_same_hue(U.BADGE_DAY, U.BADGE_NIGHT, "бейдж")

	# Светлота заливок состояний одна в обеих темах: «верно» и днём, и
	# ночью — одна и та же зелень по весу (раньше ночью было тёмное
	# зелёное #3f6b3a — тот же смысл, другой цвет).
	_same_light(U.OK_DAY, U.OK_NIGHT, 0.04, "заливка «верно»")
	_same_light(U.DANGER_DAY, U.DANGER_NIGHT, 0.04, "заливка «ошибка»")

	# --- 2б. Заливки лиц клавиш по пальцам (см. FINGER_KEY_* в ui.gd).
	_finger_palette()

	# --- 3. Обе темы у каждой парной роли.
	_pair(U.SELECT_DAY, U.SELECT_NIGHT, "выбор строки")
	_pair(U.SELECT_TEXT_DAY, U.SELECT_TEXT_NIGHT, "текст выбранной строки")
	_pair(U.ACCENT_DAY, U.ACCENT_NIGHT, "акцент")
	_pair(U.ACCENT_EDGE_DAY, U.ACCENT_EDGE_NIGHT, "рамка включённого чипа")
	_pair(U.OK_DAY, U.OK_NIGHT, "верно")
	_pair(U.OK_EDGE_DAY, U.OK_EDGE_NIGHT, "рамка «верно»")
	_pair(U.OK_TEXT_DAY, U.OK_TEXT_NIGHT, "текст «верно»")
	_pair(U.DANGER_DAY, U.DANGER_NIGHT, "ошибка")
	_pair(U.DANGER_EDGE_DAY, U.DANGER_EDGE_NIGHT, "рамка «ошибка»")
	_pair(U.DANGER_TEXT_DAY, U.DANGER_TEXT_NIGHT, "текст «ошибка»")
	_pair(U.ERR_DAY, U.ERR_NIGHT, "метка опечатки")
	_pair(U.PRESS_DAY, U.PRESS_NIGHT, "нажатая клавиша")
	_pair(U.HINT_KEY_DAY, U.HINT_KEY_NIGHT, "подсветка подсказки")
	_pair(U.PROGRESS_DAY, U.PROGRESS_NIGHT, "прогресс")
	_pair(U.TRACK_DAY, U.TRACK_NIGHT, "трек")
	_pair(U.BADGE_DAY, U.BADGE_NIGHT, "бейдж")
	_pair(U.BADGE_EDGE_DAY, U.BADGE_EDGE_NIGHT, "рамка бейджа")
	_pair(U.STAR_DAY, U.STAR_NIGHT, "звезда")
	# Курсор намеренно полупрозрачный (мягкое пятно под буквой) —
	# пара с альфой в этой проверке неуместна.

	if _failures.is_empty():
		print("THEME_TEST: PASS")
	else:
		for f in _failures:
			print("THEME_TEST: FAIL: ", f)
	quit(1 if not _failures.is_empty() else 0)


func _text(fg: Color, bg: Color, worst: Color, what: String) -> void:
	var r := _cr(fg, bg)
	_check(r >= 4.5, "%s: контраст %.2f:1 < 4.5" % [what, r])
	# Панель полупрозрачная и гуляет по небу — худший край тоже обязан
	# читаться, иначе в игре текст пропадёт на закате.
	var rw := _cr(fg, worst)
	_check(rw >= 4.5, "%s: на худшем небе %.2f:1 < 4.5" % [what, rw])


func _edge(fg: Color, bg: Color, worst: Color, what: String) -> void:
	var r := _cr(fg, bg)
	_check(r >= 3.0, "%s: контраст %.2f:1 < 3.0" % [what, r])
	var rw := _cr(fg, worst)
	_check(rw >= 3.0, "%s: на худшем небе %.2f:1 < 3.0" % [what, rw])


func _family(c: Color, hue: float, c_max: float, what: String) -> void:
	var v := _oklch(c)
	# У почти серых (C < 0.02) hue численно шумный — сравнивать нечего.
	if v.y >= 0.02:
		var d := _hdiff(v.z, hue)
		_check(d <= 12.0, "%s: hue %.0f, семейство %.0f (расход %.0f)" % [what, v.z, hue, d])
	_check(
		v.y <= c_max,
		"%s: насыщенность %.3f > %.2f — это уже не нейтраль" % [what, v.y, c_max]
	)


func _same_hue(day: Color, night: Color, what: String) -> void:
	var d := _hdiff(_oklch(day).z, _oklch(night).z)
	_check(d <= 10.0, "%s: hue едетет по теме (день %.0f, ночь %.0f)" % [what, _oklch(day).z, _oklch(night).z])


func _same_light(day: Color, night: Color, tol: float, what: String) -> void:
	var ld := _oklch(day).x
	var ln := _oklch(night).x
	_check(
		absf(ld - ln) <= tol,
		"%s: светлота едетет по теме (день %.2f, ночь %.2f)" % [what, ld, ln]
	)


func _pair(day: Color, night: Color, what: String) -> void:
	# Обе половины роли — настоящие цвета. Забытая ночная роль в GDScript
	# не ошибка: это Color(0, 0, 0, 0), и в тёмной теме она рисуется
	# чёрным, а в дневной — нормально. Ловим числом.
	for c in [day, night]:
		var col: Color = c as Color
		_check(col.a >= 1.0, "%s: тема без альфы (%.2f)" % [what, col.a])
		_check(col.get_luminance() > 0.0, "%s: тема чёрная" % what)


## Расстояние в OKLab между двумя цветами: ΔE, по которому автор выбирал
## «едва заметно». Считается по L, a, b (C и hue — те же координаты в
## полярной записи, поэтому переводим обратно).
func _okdist(a: Color, b: Color) -> float:
	var x := _oklab(a)
	var y := _oklab(b)
	var ax := x.y * cos(deg_to_rad(x.z))
	var ay := x.y * sin(deg_to_rad(x.z))
	var bx := y.y * cos(deg_to_rad(y.z))
	var by := y.y * sin(deg_to_rad(y.z))
	return sqrt(pow(x.x - y.x, 2.0) + pow(ax - bx, 2.0) + pow(ay - by, 2.0))


## sRGB → OKLab ПО BOTTOSSON, без подмены матриц: sRGB → линейный →
## LMS → кубический корень → Lab. Это НАСТОЯЩАЯ мера цвета, и по ней
## подобраны заливки клавиш (`FINGER_KEY_*`: десять hue круга, соседи
## по доске — через 108°, светлота чередуется через палец).
##
## Почему отдельно от `_oklch` выше, а не вместо него: там в линейные
## sRGB подставлена матрица XYZ→LMS (первый шаг OKLab по статье
## Боттоссона идёт от XYZ, а не от sRGB). Семейные правила ui.gd —
## «тёплый 40, синий 200, ночные 210» — калиброваны ИМЕННО по ней, и
## честная замена требует заново вывести все якоря и переписать 50
## пометок `# L.. C.. H..` в словаре ролей. Это отдельная задача; здесь
## важно, что цвет палитры пальцев выбран по правильной мере, иначе
## «36°» и «ΔE 0.03» ничего не значили бы (аудит 08.11.2026: та же
## палитра в матрице `_oklch` читается как hue 3°..352° с C до 0.11).
func _oklab(c: Color) -> Vector3:
	var f := func(v: float) -> float:
		return v / 12.92 if v <= 0.04045 else pow((v + 0.055) / 1.055, 2.4)
	var lin := Vector3(f.call(c.r), f.call(c.g), f.call(c.b))
	var lms := Vector3(
		0.4122214708 * lin.x + 0.5363325363 * lin.y + 0.0514459929 * lin.z,
		0.2119034982 * lin.x + 0.6806995451 * lin.y + 0.1073969566 * lin.z,
		0.0883024619 * lin.x + 0.2817188376 * lin.y + 0.6299787005 * lin.z
	)
	lms = Vector3(
		signf(lms.x) * pow(absf(lms.x), 1.0 / 3.0),
		signf(lms.y) * pow(absf(lms.y), 1.0 / 3.0),
		signf(lms.z) * pow(absf(lms.z), 1.0 / 3.0)
	)
	return _lab_from_lms(lms)


## OKLab из УЖЕ возведённых в куб LMS: общий хвост настоящей меры и
## симуляции дейтеранопии (см. `_deut_lab`).
func _lab_from_lms(lms: Vector3) -> Vector3:
	var lab := Vector3(
		0.2104542553 * lms.x + 0.7936177850 * lms.y - 0.0040720468 * lms.z,
		1.9779984951 * lms.x - 2.4285922050 * lms.y + 0.4505937099 * lms.z,
		0.0259040371 * lms.x + 0.7827717662 * lms.y - 0.8086757660 * lms.z
	)
	var hue := rad_to_deg(atan2(lab.z, lab.y))
	if hue < 0.0:
		hue += 360.0
	return Vector3(lab.x, sqrt(lab.y * lab.y + lab.z * lab.z), hue)


## Как этот цвет видит человек с ДЕЙТЕРАНОПИЕЙ (Мачадо 2009, тяжесть 1.0):
## матрица в линейном sRGB, дальше честный OKLab. Вторая мера контраста
## секций: цвет пальца при таком зрении схлопывается у соседних пар,
## и границу обязана держать разница светлоты.
func _deut_lab(c: Color) -> Vector3:
	var f := func(v: float) -> float:
		return v / 12.92 if v <= 0.04045 else pow((v + 0.055) / 1.055, 2.4)
	var r: float = f.call(c.r)
	var g: float = f.call(c.g)
	var b: float = f.call(c.b)
	var lms := Vector3(
		0.367322 * r + 0.860646 * g - 0.227968 * b,
		0.280085 * r + 0.672501 * g + 0.047413 * b,
		-0.011820 * r + 0.042940 * g + 0.968881 * b
	)
	lms = Vector3(
		signf(lms.x) * pow(absf(lms.x), 1.0 / 3.0),
		signf(lms.y) * pow(absf(lms.y), 1.0 / 3.0),
		signf(lms.z) * pow(absf(lms.z), 1.0 / 3.0)
	)
	return _lab_from_lms(lms)


func _deut_dist(a: Color, b: Color) -> float:
	var x := _deut_lab(a)
	var y := _deut_lab(b)
	var ax := x.y * cos(deg_to_rad(x.z))
	var ay := x.y * sin(deg_to_rad(x.z))
	var bx := y.y * cos(deg_to_rad(y.z))
	var by := y.y * sin(deg_to_rad(y.z))
	return sqrt(pow(x.x - y.x, 2.0) + pow(ax - bx, 2.0) + pow(ay - by, 2.0))


## ЗАЛИВКИ КЛАВИШ ПО ПАЛЬЦАМ И ЗОНА ПОДСКАЗКИ (автор 08.11.2026, ревизия
## 10.11.2026: цвет переехал с дорожек В САМУ КЛАВИШУ — «в мобильном
## приложении виртуальная клавиатура раскрашивает фон вокруг кнопок, а не
## сами кнопки. Это делает линию границ нечитаемой»).
## Тест держит ровно то, ради чего палитра заведена:
##   * цветов ДЕСЯТЬ, по одному на палец, и все десять hue круга заняты
##     РАЗНЫМИ слотами (`FINGER_SLOT` — перестановка 0..9) — иначе «у
##     каждого пальца свой цвет» превращается в случайный набор (и
##     зеркальные пять цветов на две руки проходят мимо правила);
##   * СОСЕДИ ПО ДОСКЕ прыгают по кругу на ≥ 90° (у нас 108°), а не идут
##     шагом: ровный шаг вдоль ряда читался плавным градиентом (автор:
##     «цвета должны... максимально контрастировать друг с другом»);
##   * указательные расходятся так же — их граница видна всегда (автор:
##     «а это крайне важно»);
##   * hue не едет по теме (иначе палец днём и ночью разного цвета);
##   * ЗАЛИВКА — ФОН ПОД БУКВОЙ, поэтому её светлота зажата контрастом:
##     чернила и приглушённые угловые легенды обязаны читаться на КАЖДОЙ
##     заливке ≥ 4.5:1, а рамка клавиши (`LINE_*`) отделять её ≥ 3:1 —
##     это и есть «читаемые границы» из жалобы автора;
##   * соседние пальцы чередуют светлоту: при дейтеранопии парные hue
##     схлопываются, и границу держит перепад (порог 0.08);
##   * цвет приходит ТОЛЬКО по галочке «Зоны»: в покое клавиша бумажная,
##     поэтому заливка обязана отличаться от бумаги (ΔE ≥ 0.05);
##   * ПЛИТА доски нейтральна и отлична от бумаги клавиши — в зазоры
##     смотрит она, а не луг;
##   * зона подсказки — ОДИН цвет на все пальцы (10.11.2026): лиловый,
##     дополнительный к жёлтой клавише, и она отлична от бумаги клавиши.
func _finger_palette() -> void:
	var slot: Array = U.FINGER_SLOT
	# Слот — перестановка 0..9: цвет круга у каждого пальца свой. Сбитая
	# таблица иначе дала бы двум пальцам один hue, а доску — разрыв.
	_check(slot.size() == 10, "FINGER_SLOT: %d слотов вместо 10" % slot.size())
	var seen := {}
	for s in slot:
		seen[int(s)] = true
	_check(seen.size() == 10, "FINGER_SLOT — перестановка 0..9 (уникальных %d)" % seen.size())
	var key_d: Array = U.FINGER_KEY_DAY
	var key_n: Array = U.FINGER_KEY_NIGHT
	for arr in [key_d, key_n]:
		_check((arr as Array).size() == 10,
			"заливки клавиш: %d цветов вместо 10" % (arr as Array).size())
	if key_d.size() != 10 or key_n.size() != 10 or slot.size() != 10:
		return

	# ЦВЕТ ПАЛЬЦА — ЗАЛИВКА ЛИЦА КЛАВИШИ. Тот же круг и порядок
	# `FINGER_SLOT` (прыжок 108°), светлота ЧЕРЕДУЕТСЯ через палец: при
	# дейтеранопии парные hue схлопываются, и границу держит перепад.
	var dhue: Array = []
	var nhue: Array = []
	for i in 10:
		var d: Color = key_d[i]
		var n: Color = key_n[i]
		var od := _oklab(d)
		var on := _oklab(n)
		dhue.append(od.z)
		nhue.append(on.z)
		_check(d.a >= 1.0 and n.a >= 1.0, "заливка %d: цвет без альфы" % i)
		var want := float(slot[i]) * 36.0
		_check(absf(_hdiff(od.z, want)) <= 8.0,
			"заливка %d, день: hue %.0f, ждали %.0f (слот %d)" % [
				i, od.z, want, int(slot[i])])
		_check(absf(_hdiff(on.z, want)) <= 8.0,
			"заливка %d, ночь: hue %.0f, ждали %.0f (слот %d)" % [
				i, on.z, want, int(slot[i])])
		_check(_hdiff(od.z, on.z) <= 10.0,
			"заливка %d: hue едет по теме (день %.0f, ночь %.0f)" % [i, od.z, on.z])
		var want_d := 0.910 if i % 2 == 0 else 0.819
		var want_n := 0.360 if i % 2 == 0 else 0.269
		_check(absf(od.x - want_d) <= 0.008,
			"заливка %d, день: светлота %.3f, ждали %.3f" % [i, od.x, want_d])
		_check(absf(on.x - want_n) <= 0.008,
			"заливка %d, ночь: светлота %.3f, ждали %.3f" % [i, on.x, want_n])
		# Насыщенность — у края gamut своего hue: в sRGB у синего и
		# розового он разный, и ровнять абсолютно — сделать синий серым.
		_check(od.y >= 0.04, "заливка %d, день: насыщенность %.3f < 0.04" % [i, od.y])
		_check(on.y >= 0.04, "заливка %d, ночь: насыщенность %.3f < 0.04" % [i, on.y])
		# Иерархия темы: днём клавиша остаётся СВЕТЛОЙ (на ней тёмная
		# буква), ночью — темнее бумаги клавиши.
		_check(od.x >= 0.78,
			"заливка %d, день: %.3f — клавиша перестала быть светлой" % [i, od.x])
		_check(on.x < _oklab(U.SURFACE_ALT_NIGHT).x - 0.02,
			"заливка %d, ночь: %.3f не темнее бумаги %.3f" % [
				i, on.x, _oklab(U.SURFACE_ALT_NIGHT).x])
		# ГЛАВНОЕ ПРАВИЛО ЗАЛИВКИ: подпись читается на ней. Центральная
		# буква — чернилами своей темы, углы — `LEGEND_INK_*`.
		_check(_cr(U.INK_DAY, d) >= 4.5,
			"заливка %d, день: чернила %.2f:1 < 4.5" % [i, _cr(U.INK_DAY, d)])
		_check(_cr(U.INK_NIGHT, n) >= 4.5,
			"заливка %d, ночь: чернила %.2f:1 < 4.5" % [i, _cr(U.INK_NIGHT, n)])
		_check(_cr(U.LEGEND_INK_DAY, d) >= 4.5,
			"заливка %d, день: углы %.2f:1 < 4.5" % [i, _cr(U.LEGEND_INK_DAY, d)])
		_check(_cr(U.LEGEND_INK_NIGHT, n) >= 4.5,
			"заливка %d, ночь: углы %.2f:1 < 4.5" % [i, _cr(U.LEGEND_INK_NIGHT, n)])
		# ГРАНИЦЫ КЛАВИШ — рамка той же роли, что у бумажной клавиши.
		_check(_cr(U.LINE_DAY, d) >= 3.0,
			"заливка %d, день: рамка %.2f:1 < 3.0" % [i, _cr(U.LINE_DAY, d)])
		_check(_cr(U.LINE_NIGHT, n) >= 3.0,
			"заливка %d, ночь: рамка %.2f:1 < 3.0" % [i, _cr(U.LINE_NIGHT, n)])
		# Смена состояния обязана быть видна от бумаги: «Зоны» выключены —
		# клавиша просто бумага, и заливка не имеет права на неё походить.
		_check(_okdist(U.SURFACE_DAY, d) >= 0.05,
			"заливка %d, день: ΔE %.3f < 0.05 от бумаги" % [i, _okdist(U.SURFACE_DAY, d)])
		_check(_okdist(U.SURFACE_ALT_NIGHT, n) >= 0.05,
			"заливка %d, ночь: ΔE %.3f < 0.05 от бумаги" % [
				i, _okdist(U.SURFACE_ALT_NIGHT, n)])

	# СОСЕДИ ПО ДОСКЕ — ПРЫЖКОМ. Пары, которые стоят вплотную: 0-1, 1-2,
	# 2-3 (левая), 3↔6 (стык указательных), 6-7, 7-8, 8-9 (правая),
	# 4-5 (две половинки низа: левый и правый большие). 108° — максимум
	# при десяти разных цветах.
	for pair in [[0, 1], [1, 2], [2, 3], [3, 6], [6, 7], [7, 8], [8, 9], [4, 5]]:
		var a := int((pair as Array)[0])
		var b := int((pair as Array)[1])
		var dd := _hdiff(float(dhue[a]), float(dhue[b]))
		var dn := _hdiff(float(nhue[a]), float(nhue[b]))
		_check(dd >= 90.0,
			"соседи %d-%d, день: %.0f° < 90 — рядом стоящие зоны сливаются" % [a, b, dd])
		_check(dn >= 90.0,
			"соседи %d-%d, ночь: %.0f° < 90 — рядом стоящие зоны сливаются" % [a, b, dn])
		# Вторая мера: расстояние в OKLab (светлота + цвет) — видно ли
		# границу «с одного взгляда», а не только по номеру hue.
		var de_d := _okdist(key_d[a], key_d[b])
		var de_n := _okdist(key_n[a], key_n[b])
		_check(de_d >= 0.12,
			"соседи %d-%d, день: ΔE %.3f < 0.12" % [a, b, de_d])
		_check(de_n >= 0.12,
			"соседи %d-%d, ночь: ΔE %.3f < 0.12" % [a, b, de_n])
		# Дейтеранопия: парные hue схлопываются, но границу держит
		# чередование светлоты. Порог 0.08 — «не слиплись».
		var du_d := _deut_dist(key_d[a], key_d[b])
		var du_n := _deut_dist(key_n[a], key_n[b])
		_check(du_d >= 0.08,
			"соседи %d-%d, день: при дейтеранопии ΔE %.3f < 0.08" % [a, b, du_d])
		_check(du_n >= 0.08,
			"соседи %d-%d, ночь: при дейтеранопии ΔE %.3f < 0.08" % [a, b, du_n])
	var idx := _hdiff(float(dhue[3]), float(dhue[6]))
	_check(idx >= 90.0,
		"указательный|указательный: %.0f° < 90 — границы зон не видно" % idx)

	# ПЛИТА ДОСКИ — нейтральная поверхность В ЗАЗОРАХ (см. Kbd.plate_rect).
	# Она обязана читаться поверхностью, а не краской, и отличаться от
	# бумаги клавиши — иначе клавиша сольётся с зазором.
	var pd: Color = U.KEY_PLATE_DAY
	var pn: Color = U.KEY_PLATE_NIGHT
	var opd := _oklab(pd)
	var opn := _oklab(pn)
	_check(pd.a >= 1.0 and pn.a >= 1.0, "плита: цвет без альфы")
	_check(opd.y <= 0.03 and opn.y <= 0.03,
		"плита: насыщенность %.3f/%.3f > 0.03 — это краска, а не поверхность" % [
			opd.y, opn.y])
	_check(absf(opd.x - 0.893) <= 0.01,
		"плита, день: светлота %.3f вне 0.883..0.903" % opd.x)
	_check(absf(opn.x - 0.255) <= 0.01,
		"плита, ночь: светлота %.3f вне 0.245..0.265" % opn.x)
	_check(_okdist(U.SURFACE_DAY, pd) >= 0.04,
		"плита, день: ΔE %.3f < 0.04 от бумаги" % _okdist(U.SURFACE_DAY, pd))
	_check(_okdist(U.SURFACE_ALT_NIGHT, pn) >= 0.04,
		"плита, ночь: ΔE %.3f < 0.04 от бумаги" % _okdist(U.SURFACE_ALT_NIGHT, pn))

	# ЗОНА ПОДСКАЗКИ — ОДИН ЦВЕТ НА ВСЕ ПАЛЬЦЫ (автор 10.11.2026: «пусть
	# подсказки разбиения зон будут одноцветными, т.к. они всё равно
	# никогда не окажутся рядом»). Различать hue нечем: одновременно
	# горит один палец. Цвет — ЛИЛОВЫЙ, дополнительный к жёлтой клавише
	# подсказки: зона и клавиша не сливаются, а с синим акцентом
	# («включено») и зелёным/красным лиловый не спорит вовсе.
	var hz_d: Color = U.HINT_ZONE_DAY
	var hz_n: Color = U.HINT_ZONE_NIGHT
	var hz_ed: Color = U.HINT_ZONE_EDGE_DAY
	var hz_en: Color = U.HINT_ZONE_EDGE_NIGHT
	for col in [hz_d, hz_n, hz_ed, hz_en]:
		_check((col as Color).a >= 1.0, "зона подсказки: цвет без альфы (%.2f)" % (col as Color).a)
	var ohd := _oklab(hz_d)
	var ohn := _oklab(hz_n)
	var oed := _oklab(hz_ed)
	var oen := _oklab(hz_en)
	# Hue один на обе темы и совпадает у заливки с рамкой: это один цвет,
	# а не два разных.
	for pair in [[ohd, "заливка дня"], [ohn, "заливка ночи"],
			[oed, "рамка дня"], [oen, "рамка ночи"]]:
		var oc: Vector3 = pair[0]
		_check(absf(_hdiff(oc.z, 295.0)) <= 8.0,
			"зона, %s: hue %.0f, ждали 295 (лиловый)" % [pair[1], oc.z])
	_check(_hdiff(ohd.z, ohn.z) <= 8.0,
		"зона: hue едет по теме (день %.0f, ночь %.0f)" % [ohd.z, ohn.z])
	_check(_hdiff(oed.z, ohd.z) <= 8.0 and _hdiff(oen.z, ohn.z) <= 8.0,
		"зона: рамка не того же hue, что заливка")
	# Светлота: зона горит на НЕЙТРАЛЬНОЙ доске (подсказка погасила краску
	# в бумагу), поэтому мерило одно — бумага клавиши. Ночь — ТЕМНЕЕ
	# клавиши, иначе сектор держится одной рамкой (было ΔE 0.041).
	_check(ohd.x >= 0.85 and ohd.x <= 0.87,
		"зона, день: светлота %.3f вне 0.85..0.87" % ohd.x)
	_check(ohn.x >= 0.25 and ohn.x <= 0.27,
		"зона, ночь: светлота %.3f вне 0.25..0.27" % ohn.x)
	_check(ohn.x < _oklab(U.SURFACE_ALT_NIGHT).x - 0.05,
		"зона, ночь: %.3f не темнее клавиши %.3f" % [
			ohn.x, _oklab(U.SURFACE_ALT_NIGHT).x])
	# Насыщенность: это оттенок, а не нейтраль, но и не крик — заливка
	# лежит под подписями.
	_check(ohd.y >= 0.05 and ohd.y <= 0.09,
		"зона, день: насыщенность %.3f вне 0.05..0.09" % ohd.y)
	_check(ohn.y >= 0.07 and ohn.y <= 0.11,
		"зона, ночь: насыщенность %.3f вне 0.07..0.11" % ohn.y)
	# Подписи клавиш: и чернила, и приглушённые угловые легенды.
	_check(_cr(U.INK_DAY, hz_d) >= 4.5,
		"зона, день: чернила %.2f:1 < 4.5" % _cr(U.INK_DAY, hz_d))
	_check(_cr(U.LEGEND_INK_DAY, hz_d) >= 4.5,
		"зона, день: вторая раскладка %.2f:1 < 4.5" % _cr(U.LEGEND_INK_DAY, hz_d))
	_check(_cr(U.INK_NIGHT, hz_n) >= 4.5,
		"зона, ночь: чернила %.2f:1 < 4.5" % _cr(U.INK_NIGHT, hz_n))
	_check(_cr(U.LEGEND_INK_NIGHT, hz_n) >= 4.5,
		"зона, ночь: вторая раскладка %.2f:1 < 4.5" % _cr(U.LEGEND_INK_NIGHT, hz_n))
	# Смена состояния обязана быть ВИДНА от бумаги клавиши.
	_check(_okdist(U.SURFACE_DAY, hz_d) >= 0.12,
		"зона, день: ΔE %.3f < 0.12 от бумаги" % _okdist(U.SURFACE_DAY, hz_d))
	_check(_okdist(U.SURFACE_ALT_NIGHT, hz_n) >= 0.12,
		"зона, ночь: ΔE %.3f < 0.12 от бумаги" % _okdist(U.SURFACE_ALT_NIGHT, hz_n))
	# И от ЖЁЛТОЙ клавиши подсказки: зона и цель — разные вещи, цвета
	# не имеют права слиться (это и есть причина лилового).
	_check(_okdist(U.HINT_KEY_DAY, hz_d) >= 0.12,
		"зона, день: ΔE %.3f < 0.12 к подсказке" % _okdist(U.HINT_KEY_DAY, hz_d))
	_check(_okdist(U.HINT_KEY_NIGHT, hz_n) >= 0.12,
		"зона, ночь: ΔE %.3f < 0.12 к подсказке" % _okdist(U.HINT_KEY_NIGHT, hz_n))
	# Рамка — вторая мера «секции»: клавиши пальца читаются блоком.
	_check(_cr(hz_ed, hz_d) >= 3.0,
		"рамка зоны, день: %.2f:1 < 3.0 к заливке" % _cr(hz_ed, hz_d))
	_check(_cr(hz_en, hz_n) >= 3.0,
		"рамка зоны, ночь: %.2f:1 < 3.0 к заливке" % _cr(hz_en, hz_n))
	_check(oed.x >= 0.50 and oed.x <= 0.62,
		"рамка зоны, день: светлота %.3f вне 0.50..0.62" % oed.x)
	_check(oen.x >= 0.68 and oen.x <= 0.80,
		"рамка зоны, ночь: светлота %.3f вне 0.68..0.80" % oen.x)
