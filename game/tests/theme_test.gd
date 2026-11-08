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

	# --- 2б. Клавиши по пальцам (см. FINGER_DAY/FINGER_NIGHT в ui.gd).
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
## подбиралась палитра пальцев (`FINGER_DAY/NIGHT`: шаг hue 36°, ΔE 0.03
## от бумаги клавиши).
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
	var lab := Vector3(
		0.2104542553 * lms.x + 0.7936177850 * lms.y - 0.0040720468 * lms.z,
		1.9779984951 * lms.x - 2.4285922050 * lms.y + 0.4505937099 * lms.z,
		0.0259040371 * lms.x + 0.7827717662 * lms.y - 0.8086757660 * lms.z
	)
	var hue := rad_to_deg(atan2(lab.z, lab.y))
	if hue < 0.0:
		hue += 360.0
	return Vector3(lab.x, sqrt(lab.y * lab.y + lab.z * lab.z), hue)


## КЛАВИШИ ПО ПАЛЬЦАМ (автор 08.11.2026). Тест держит ровно то, ради
## чего палитра заведена:
##   * цветов ДЕСЯТЬ, по одному на палец, и hue идут ровным шагом 36° —
##     иначе «у каждого пальца свой цвет» превращается в случайный набор
##     (и зеркальные пять цветов на две руки проходят мимо правила);
##   * указательные расходятся на ТРИ шага: граница их зон — самая
##     заметная на доске (автор: «а это крайне важно»);
##   * hue не едет по теме (иначе палец днём и ночью разного цвета);
##   * насыщенность в потолке — это и есть «ещё серее, или прозрачнее»:
##     заливка читается как оттенок бумаги, а не как краска;
##   * чернила и приглушённые подписи второй раскладки читаются на
##     КАЖДОЙ заливке (4.5:1) — цвет клавиши не имеет права съесть букву;
##   * ΔE от бумаги в коридоре: меньше 0.02 — не видно, больше 0.08 —
##     уже не «едва заметно».
func _finger_palette() -> void:
	var day: Array = U.FINGER_DAY
	var night: Array = U.FINGER_NIGHT
	_check(day.size() == 10, "палитра пальцев, день: %d цветов вместо 10" % day.size())
	_check(night.size() == 10, "палитра пальцев, ночь: %d цветов вместо 10" % night.size())
	if day.size() != 10 or night.size() != 10:
		return
	var dhue: Array = []
	var nhue: Array = []
	for i in 10:
		var d: Color = day[i]
		var n: Color = night[i]
		var od := _oklab(d)
		var on := _oklab(n)
		dhue.append(od.z)
		nhue.append(on.z)
		_check(d.a >= 1.0 and n.a >= 1.0, "палец %d: заливка без альфы" % i)
		# Шаг по кругу: палец i — это i-й цвет круга.
		_check(absf(_hdiff(od.z, float(i) * 36.0)) <= 8.0,
			"палец %d: hue дня %.0f, ждали %.0f" % [i, od.z, float(i) * 36.0])
		_check(absf(_hdiff(on.z, float(i) * 36.0)) <= 8.0,
			"палец %d: hue ночи %.0f, ждали %.0f" % [i, on.z, float(i) * 36.0])
		_check(_hdiff(od.z, on.z) <= 10.0,
			"палец %d: hue едет по теме (день %.0f, ночь %.0f)" % [i, od.z, on.z])
		# «Серее»: насыщенность в потолке для каждой темы.
		_check(od.y <= 0.035, "палец %d, день: насыщенность %.3f > 0.035" % [i, od.y])
		_check(on.y <= 0.030, "палец %d, ночь: насыщенность %.3f > 0.030" % [i, on.y])
		# Светлота общая на тему: зоны различает hue, а не яркость.
		_check(od.x >= 0.94 and od.x <= 0.97,
			"палец %d, день: светлота %.3f вне 0.94..0.97" % [i, od.x])
		_check(on.x >= 0.35 and on.x <= 0.39,
			"палец %d, ночь: светлота %.3f вне 0.35..0.39" % [i, on.x])
		# Подписи: буква (INK) и вторая раскладка (DIM).
		var ink_d := _cr(U.INK_DAY, d)
		var dim_d := _cr(U.DIM_DAY, d)
		var ink_n := _cr(U.INK_NIGHT, n)
		var dim_n := _cr(U.DIM_NIGHT, n)
		_check(ink_d >= 4.5, "палец %d, день: чернила %.2f:1 < 4.5" % [i, ink_d])
		_check(dim_d >= 4.5, "палец %d, день: вторая раскладка %.2f:1 < 4.5" % [i, dim_d])
		_check(ink_n >= 4.5, "палец %d, ночь: чернила %.2f:1 < 4.5" % [i, ink_n])
		_check(dim_n >= 4.5, "палец %d, ночь: вторая раскладка %.2f:1 < 4.5" % [i, dim_n])
		# «Едва заметно»: мера от прежней бумаги клавиши.
		var de_d := _okdist(d, U.SURFACE_DAY)
		var de_n := _okdist(n, U.SURFACE_ALT_NIGHT)
		_check(de_d >= 0.02 and de_d <= 0.07,
			"палец %d, день: ΔE %.3f вне 0.02..0.07" % [i, de_d])
		_check(de_n >= 0.02 and de_n <= 0.08,
			"палец %d, ночь: ΔE %.3f вне 0.02..0.08" % [i, de_n])
	# Соседние зоны — ровно один шаг, не больше и не меньше: иначе
	# «отличаются разные пальцы» превращается в два цвета на всю доску.
	for i in 9:
		var step := _hdiff(float(dhue[i]), float(dhue[i + 1]))
		_check(step >= 20.0 and step <= 55.0,
			"зоны %d и %d: шаг %.0f° вне 20..55" % [i, i + 1, step])
	# Указательные — три шага: это и есть та граница, которую видно.
	var idx := _hdiff(float(dhue[3]), float(dhue[6]))
	_check(idx >= 90.0,
		"указательный|указательный: %.0f° < 90 — границы зон не видно" % idx)
	var idx_n := _hdiff(float(nhue[3]), float(nhue[6]))
	_check(idx_n >= 90.0,
		"указательный|указательный, ночь: %.0f° < 90" % idx_n)
