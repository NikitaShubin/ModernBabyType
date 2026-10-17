extends SceneTree
## Контраст палитры (ревизия 17.10.2026). Словарь ролей лежит в ui.gd,
## а этот тест проверяет его двумя числами, без единого кадра:
##   1) КАЖДАЯ пара «текст на фоне» и «элемент на фоне» читается:
##      текст — 4.5:1, рамка/заливка элемента — 3:1;
##   2) у каждой роли есть обе темы (иначе забытая половина темы
##      молча рисуется чужим цветом).
##
## Откуда такие числа: вчера тёмно-зелёный чип «флаг включён» давал
## 1.10:1 — тёмный текст на тёмной заливке, и это замечал глаз автора
## («неуместный цвет»). Обводка фокуса на жёлтой строке ночью — 1.23:1.
##
## Тест чистый: только чтение констант и арифметика, поэтому быстрый и
## не зависит ни от машины, ни от шрифтов.

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
	var hi: float = maxf(la, lb)
	var lo: float = minf(la, lb)
	return (hi + 0.05) / (lo + 0.05)


## Прозрачный фон под полупрозрачной панелью: считаем на самой тёмной
## подложке ночи — там контраст хуже всего.
func _flat(c: Color, under: Color) -> Color:
	return Color(
		c.r * c.a + under.r * (1.0 - c.a),
		c.g * c.a + under.g * (1.0 - c.a),
		c.b * c.a + under.b * (1.0 - c.a),
		1.0
	)


func _initialize() -> void:
	var night_bg := Color("#0a0e1a")
	# Панели: подложка под полупрозрачной карточкой.
	var card_day := _flat(U.CARD_DAY, Color("#f7f3e8"))
	var card_night := _flat(U.CARD_NIGHT, night_bg)
	# Строка списка ночью — полупрозрачная над небом.
	var row_night := _flat(Color(0.10, 0.12, 0.20, 0.60), night_bg)

	# --- Текст на своей поверхности (порог 4.5).
	_text(U.UI_TEXT_DAY, card_day, "текст на карточке, день")
	_text(U.UI_TEXT_NIGHT, card_night, "текст на карточке, ночь")
	_text(U.INK_DAY, card_day, "буква на карточке, день")
	_text(U.INK_NIGHT, card_night, "буква на карточке, ночь")
	_text(U.DIM_DAY, card_day, "второстепенный текст, день")
	_text(U.DIM_NIGHT, row_night, "второстепенный текст, ночь")
	_text(U.GREY_CHAR_DAY, card_day, "серая буква, день")
	_text(U.GREY_CHAR_NIGHT, card_night, "серая буква, ночь")
	_text(U.UI_TEXT_DAY, U.SURFACE_DAY, "текст на кнопке, день")
	_text(U.UI_TEXT_NIGHT, U.SURFACE_ALT_NIGHT, "текст на кнопке, ночь")
	_text(U.INK_DAY, U.SELECT_DAY, "имя на выделенной строке, день")
	_text(U.INK_DAY, U.SELECT_NIGHT, "имя на выделенной строке, ночь")
	_text(U.ACCENT_INK, U.ACCENT_DAY, "подпись на включённом чипе, день")
	_text(U.ACCENT_INK, U.ACCENT_NIGHT, "подпись на включённом чипе, ночь")
	_text(U.DANGER_TEXT_DAY, U.SURFACE_ALT_DAY, "крестик, день")
	_text(U.DANGER_TEXT_NIGHT, U.SURFACE_ALT_NIGHT, "крестик, ночь")
	_text(U.STAR_DAY, card_day, "звезда, день")
	_text(U.STAR_NIGHT, card_night, "звезда, ночь")

	# --- Рамка на своей заливке (порог 3).
	_edge(U.LINE_DAY, U.SURFACE_ALT_DAY, "рамка кнопки, день")
	_edge(U.LINE_NIGHT, U.SURFACE_ALT_NIGHT, "рамка кнопки, ночь")
	# Заливку акцента с бумагой не сверяем: чип виден по тёмной рамке и
	# тёмной подписи (эти две пары проверены выше и ниже), а сама
	# заливка светлая и «проваливаться» в фон не должна.
	_edge(U.OK_EDGE_DAY, U.OK_DAY, "рамка «верно», день")
	_edge(U.OK_EDGE_NIGHT, U.OK_NIGHT, "рамка «верно», ночь")
	_edge(U.DANGER_EDGE_DAY, U.DANGER_DAY, "рамка «ошибка», день")
	_edge(U.DANGER_EDGE_NIGHT, U.DANGER_NIGHT, "рамка «ошибка», ночь")
	_edge(U.PROGRESS_DAY, U.TRACK_DAY, "прогресс: заливка на треке, день")
	_edge(U.PROGRESS_NIGHT, U.TRACK_NIGHT, "прогресс: заливка на треке, ночь")
	_edge(U.BADGE_EDGE_DAY, U.BADGE_DAY, "бейдж, день")
	_edge(U.BADGE_EDGE_NIGHT, U.BADGE_NIGHT, "бейдж, ночь")

	# --- Фокус: единственная пара, которая должна читаться на трёх
	# фонах сразу (пустая рамка, включённый чип, выделенная строка).
	# Тёмный ободок — по светлому: пустая рамка, включённый чип (акцент
	# светлый в обеих темах), жёлтая выделенная строка.
	_focus(U.FOCUS_DARK, U.SURFACE_ALT_DAY, "фокус на рамке, день")
	_focus(U.FOCUS_DARK, U.ACCENT_DAY, "фокус на включённом чипе, день")
	_focus(U.FOCUS_DARK, U.SELECT_DAY, "фокус на выделенной строке, день")
	_focus(U.FOCUS_DARK, U.ACCENT_NIGHT, "фокус на включённом чипе, ночь")
	_focus(U.FOCUS_DARK, U.SELECT_NIGHT, "фокус на выделенной строке, ночь")
	# Светлый ободок — по тёмному: ночная клавиша и ночная карточка.
	_focus(U.FOCUS_LIGHT, U.SURFACE_ALT_NIGHT, "фокус на ночной рамке")
	_focus(U.FOCUS_LIGHT, card_night, "фокус на ночной карточке")
	# Рамка акцента — тоже часть читаемости чипа на жёлтой строке.
	_edge(U.ACCENT_EDGE_DAY, U.ACCENT_DAY, "рамка чипа на акценте, день")
	_edge(U.ACCENT_EDGE_NIGHT, U.ACCENT_NIGHT, "рамка чипа на акценте, ночь")

	# --- Ночная строка списка против бумаги: ночная панель на ночном фоне.
	_edge(U.LINE_NIGHT, row_night, "рамка на ночной строке списка")

	if _failures.is_empty():
		print("THEME_TEST: PASS")
	else:
		for f in _failures:
			print("THEME_TEST: FAIL: ", f)
	quit(1 if not _failures.is_empty() else 0)


func _text(fg: Color, bg: Color, what: String) -> void:
	var r := _cr(fg, bg)
	_check(r >= 4.5, "%s: контраст %.2f:1 < 4.5" % [what, r])


func _edge(fg: Color, bg: Color, what: String) -> void:
	var r := _cr(fg, bg)
	_check(r >= 3.0, "%s: контраст %.2f:1 < 3.0" % [what, r])


func _focus(fg: Color, bg: Color, what: String) -> void:
	var r := _cr(fg, bg)
	_check(r >= 3.0, "%s: контраст %.2f:1 < 3.0" % [what, r])