extends SceneTree
## Детерминированный тест геймплея: ввод, кумулятивный откат,
## Backspace (стереть метку / починить впереди / откат назад, упор в
## начало текста, откат по серым пропускам), подсказка, ёж на строку выше.
## Запуск: godot --headless --path game --script res://tests/logic_test.gd
## Код выхода 0 — всё сошлось.

var _frame := 0
var _main: Node = null
var _failures: Array[String] = []
var _d0 := 0.0
var _ex := 0.0
var _ex0 := 0.0
var _hx := 0.0
var _hx0 := 0.0
var _hy := 0.0


func _check(cond: bool, what: String) -> void:
	if not cond:
		_failures.append(what)


func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	_main = scene.instantiate()
	# Тест гоняет механику, а не интерфейс: сразу в игру, гостем, без
	# меню игроков и без сохранения. Все знаки активны, регистр важен —
	# как в старой отладочной сборке.
	_main.skip_menu = true
	_main.all_keys_override = 1
	root.add_child(_main)


func _process(_dt: float) -> bool:
	_frame += 1
	if _frame == 2:
		_run_part1()
	elif _frame == 4:
		# Догон сзади на одной строке: ёж вплотную за героем.
		_main.grace_t = 0.0
		_main.cursor_line = 0
		_main.cursor_pos = 8
		_main.hedge_active = true
		_main.enemy_line = 0
		_main.enemy_x = _main._cursor_cx() - _main.char_w * 0.5 - 10.0
	elif _frame == 6:
		_check(_main.state == "lost", "behind catch on same line")
		_check(_main._last_reason == "behind", "behind reason recorded")
		# Новый уровень, герой сразу на строке 1 → ёж выходит на строку 0.
		_main._new_level()
		_main.grace_t = 0.0
		_main.cursor_line = 1
		_main.cursor_pos = 0
	elif _frame == 8:
		_check(_main.hedge_active, "hedge enters when hero reaches line 1")
		_check(_main.enemy_line == 0, "hedgehog appears on the line above")
		# Герой уходит на строку 2: ёж НЕ телепортируется, остаётся на 0.
		_main.cursor_line = 2
		_main.cursor_pos = 0
	elif _frame == 10:
		_check(_main.enemy_line == 0, "no line-skipping teleport")
		# Ёж только что пересёк край строки 0 (с учётом убега POST),
		# герой на строке 2: прыжка нет, ёж просто идёт дальше по следу.
		_main.enemy_x = _main.margin + (float(_main.display_lines[0].length()) + _main.ENEMY_POST_CHARS) * _main.char_w + 1.0
	elif _frame == 12:
		_check(_main.enemy_line == 1, "hedgehog travels lines continuously")
		_check(_main.state == "playing", "no catch across different lines")
		# Курсор телепортирован (эмуляция отката через строки):
		# картинка героя обязана догонять логику.
		_main._new_level()
		_main.grace_t = 0.0
		_main.cursor_line = 1
		_main.cursor_pos = 3
		_d0 = _main.hero_r.distance_to(_main._hero_pos())
	elif _frame == 60:
		var d1: float = _main.hero_r.distance_to(_main._hero_pos())
		_check(d1 < _d0 * 0.5, "hero render chases cursor")
	elif _frame == 62:
		# Ёж впереди: по правилу это уже конец — игра прерывается сразу.
		_main._new_level()
		_main.grace_t = 0.0
		_main.cursor_line = 1
		_main.cursor_pos = 5
		_main.hedge_active = true
		_main.enemy_line = 1
		var hl: float = _main._cursor_cx() - _main.char_w * 0.5
		_main.enemy_x = hl + 140.0
	elif _frame == 64:
		_check(_main.state == "lost", "ahead states terminate immediately")
	elif _frame == 66:
		# Догон сзади на одной строке. Заяц стоит, картинка на месте,
		# ёж далеко (5 символов), а его шаг выключен (enemy_cps = 0) —
		# тогда любое изменение enemy_x на кадре укола означало бы, что
		# позицию ежа трогают (авторская придирка: «ёж плавный, менять
		# его положение не надо»).
		_main._new_level()
		_main.grace_t = 0.0
		_main.enemy_cps = 0.0
		_main.cursor_line = 1
		_main.cursor_pos = 15
		_main.hedge_active = true
		_main.enemy_line = 1
		_main.enemy_x = _main.margin + 5.0 * _main.char_w
		_main.hero_r = _main._hero_pos()
	elif _frame == 68:
		_check(_main.state == "playing", "far behind is safe")
		# Ёж подходит ровно до касания шаров: правый край зайца (он же
		# левый край клетки) вплотную к левому краю ежа.
		_ex0 = _main.margin + 15.0 * _main.char_w - _main._touch_chars() * _main.char_w
		_main.enemy_x = _ex0
	elif _frame == 70:
		_check(_main.state == "lost", "hedge touching the hare is a prick")
		_check(_main._last_reason == "behind", "prick reason recorded")
		_check(absf(_main.enemy_x - _ex0) < 0.01, "hedgehog position untouched at contact")
		# Ровно дистанция контакта: левый край зайца в правый край ежа.
		# Не «пара ежей целиком поместилась» — ради этого всё затевалось.
		_check(absf(_main.hero_r.x - (_main.enemy_x + _main._hedge_half())) < 0.5,
			"hare exactly at contact distance (no hedge-sized gap)")
		_check(absf(_main.hero_r.y - _main._track_cy(1)) < 0.5, "hare keeps its row")
	elif _frame == 72:
		# Заяц влетел в ёжа прыжком назад (ёж ровно на его правом краю).
		# Выталкивание вперёд обязано быть коротким (кап), а не
		# телепортом через пол-экрана.
		_main._new_level()
		_main.grace_t = 0.0
		_main.enemy_cps = 0.0
		_main.cursor_line = 1
		_main.cursor_pos = 3
		_main.hedge_active = true
		_main.enemy_line = 1
		_main.enemy_x = _main.margin + 3.0 * _main.char_w
		_hx0 = _main.hero_r.x
	elif _frame == 74:
		_check(_main.state == "lost", "hare jumping back onto the hedge is a prick")
		var cap: float = _main.SNAP_CAP_CHARS * _main.char_w
		var moved: float = _main.hero_r.x - _hx0
		_check(moved > 0.0, "hare pushed out of the hedgehog forward")
		_check(moved <= cap + 1.0, "push-out capped, no screen-crossing throw")
		_check(_main.hero_r.x < _main.enemy_x + _main._hedge_half(),
			"deep penetration not snapped to contact across half a line")
		# Жалоба (дважды): ёж в КОНЦЕ строки 0, даже за её край
		# (post-туннель +2), заяц в начале строки 1. Укола нет: строка
		# ежа меньше строки зайца, ёжу до зайца ещё целая строка миль,
		# и на экране они у противоположных краёв. Это ровно тот случай,
		# что раньше ловился как «вперёд».
		_main._new_level()
		_main.grace_t = 0.0
		_main.cursor_line = 1
		_main.cursor_pos = 0
		_main.hedge_active = true
		_main.enemy_line = 0
		_main.enemy_x = _main.margin + (float(_main.display_lines[0].length()) + _main.ENEMY_POST_CHARS) * _main.char_w
	elif _frame == 76:
		_check(_main.state == "playing", "no prick while hedge is still on its own line")
		# Случай 1, но со стороны pre-туннеля: ёж только что перешёл на
		# строку 1 (отступ ENEMY_PRE_CHARS слева), заяц стоит в начале
		# этой строки. Отступ нужен именно для этого — d = −5 символов,
		# полоса детекции не достигнута: ёж сначала подходит, а не
		# укалывает на входе в строку.
		_main._new_level()
		_main.grace_t = 0.0
		_main.enemy_cps = 0.0
		_main.cursor_line = 1
		_main.cursor_pos = 0
		_main.hedge_active = true
		_main.enemy_line = 1
		_main.enemy_x = _main.margin - _main.ENEMY_PRE_CHARS * _main.char_w
		_main.hero_r = _main._hero_pos()
	elif _frame == 78:
		_check(_main.state == "playing", "pre-tunnel indent spares the hare at the row start")
		# На 0.1 символа левее порога полосы детекции (d = −D − 0.1).
		_main.enemy_x = _main.margin - (_band() + 0.1) * _main.char_w
	elif _frame == 80:
		_check(_main.state == "playing", "just outside the detection band in the pre-tunnel")
		# Ровно на пороге (d = −D + 0.05 символа) — укол обязан быть.
		_main.enemy_x = _main.margin - (_band() - 0.05) * _main.char_w
	elif _frame == 82:
		_check(_main.state == "lost", "pre-tunnel edge of the detection band is a prick")
		_check(absf(_main.hero_r.x - (_main.enemy_x + _main._hedge_half())) < 0.5,
			"balls exactly touching at the pre-tunnel edge of the band")
		# Случай 3 (жалоба автора), вариант «вход в строку»: ёж стоит в
		# pre-туннеле строки 1, заяц — в конце этой же строки, по оси
		# он впереди на всю строку, укола нет. Через кадр откатываем
		# зайца на строку назад — как кумулятивная опечатка в начале
		# строки. Это обязано стать уколом.
		_main._new_level()
		_main.grace_t = 0.0
		_main.enemy_cps = 0.0
		_main.cursor_line = 1
		_main.cursor_pos = _main.display_lines[1].length() - 1
		_main.hedge_active = true
		_main.enemy_line = 1
		_main.enemy_x = _main.margin - _main.ENEMY_PRE_CHARS * _main.char_w
		_main.hero_r = _main._hero_pos()
		_hx = _main.hero_r.x
	elif _frame == 84:
		_check(_main.state == "playing", "hedge in the pre-tunnel, no prick on the same row")
		# Откат через угол: опечатка в начале строки 1 уносит зайца на
		# последний символ строки 0 — туда, где ежа уже нет.
		_main.cursor_line = 0
		_main.cursor_pos = _main.display_lines[0].length() - 1
		_ex0 = _main.enemy_x
	elif _frame == 86:
		_check(_main.state == "lost", "prick when hedge row is ahead of hero row")
		_check(_main._last_reason == "behind", "corner prick reason recorded")
		_check(absf(_main.enemy_x - _ex0) < 0.01, "hedgehog position untouched at corner prick")
		# Табло укола честное: заяц ровно в Д от ежа (шары касаются), а
		# не там, где его оставил откат.
		_check(absf(_main.hero_r.x - (_main.enemy_x + _main._hedge_half())) < 0.5,
			"corner prick: hare exactly at contact distance")
		_check(_main.hero_r.x < _hx, "corner prick: hare pulled back onto the hedgehog")
		# Тот же откат, но ёж уже глубоко в строке 1 (на 8 символов впереди
		# зайца по оси). Расстояние не важно — важна строка.
		_main._new_level()
		_main.grace_t = 0.0
		_main.enemy_cps = 0.0
		_main.cursor_line = 0
		_main.cursor_pos = _main.display_lines[0].length() - 1
		_main.hedge_active = true
		_main.enemy_line = 1
		_main.enemy_x = _main.margin + 8.0 * _main.char_w
		_main.hero_r = _main._hero_pos()
		_hy = _main.hero_r.y
		_ex0 = _main.enemy_x
	elif _frame == 88:
		_check(_main.state == "lost", "corner prick ignores axis distance")
		_check(absf(_main.enemy_x - _ex0) < 0.01, "hedgehog position untouched (far corner prick)")
		_check(absf(_main.hero_r.y - _main._track_cy(1)) < 0.5,
			"far corner prick: hare pulled onto the hedgehog's row")
		_check(_main.hero_r.y > _hy, "far corner prick: hare really moved down to the hedgehog's line")
		_check(absf(_main.hero_r.x - (_main.enemy_x + _main._hedge_half())) < 0.5,
			"far corner prick: hare exactly at contact distance")
		# Ёж упёрся в дальнюю границу допуска детекции (d = -D + 0.05
		# символа), заяц стоит, картинка на месте. Укол обязан случиться
		# РОВНО здесь: если допуск (CONTACT_SLACK) раздуть, между шарами
		# останется щель в пару ежей — исходная жалоба автора.
		_main._new_level()
		_main.grace_t = 0.0
		_main.enemy_cps = 0.0
		_main.cursor_line = 1
		_main.cursor_pos = 15
		_main.hedge_active = true
		_main.enemy_line = 1
		_main.enemy_x = _main.margin + 15.0 * _main.char_w \
			- (_band() - 0.05) * _main.char_w
		# Логика только что откатилась на ошибке, картинка ещё не доехала:
		# спрайт на символ впереди курсора. Подтянуть его к касанию —
		# можно (откат на символ), но не телепортом.
		_main.hero_r = _main._hero_pos()
		_main.hero_r.x += 1.0 * _main.char_w
	elif _frame == 90:
		_check(_main.state == "lost", "hedge at the edge of the detection band is a prick")
		_check(absf(_main.hero_r.x - (_main.enemy_x + _main._hedge_half())) < 0.5,
			"balls exactly touching at the far edge of the detection band")
		# Одна строка, ёж впереди на 2 символа: заяц оказался ПОЗАДИ
		# ежа (он всегда идёт) — по правилу это укол.
		_main._new_level()
		_main.grace_t = 0.0
		_main.cursor_line = 1
		_main.cursor_pos = 6
		_main.hedge_active = true
		_main.enemy_line = 1
		_main.enemy_x = _main.margin + 8.0 * _main.char_w
	elif _frame == 92:
		_check(_main.state == "lost", "hare behind hedge on one line is a prick")
		# А вот ёж далеко сзади на своей строке — честно мимо.
		_main._new_level()
		_main.grace_t = 0.0
		_main.cursor_line = 1
		_main.cursor_pos = 15
		_main.hedge_active = true
		_main.enemy_line = 1
		_main.enemy_x = _main.margin + 3.0 * _main.char_w
	elif _frame == 94:
		_check(_main.state == "playing", "no catch from far behind")
		_run_part2()
		_report()
		return true
	return false


## Полоса детекции укола на одной строке (в символах оси).
func _band() -> float:
	return _main._touch_chars() + _main.CONTACT_SLACK


func _report() -> void:
	if _failures.is_empty():
		print("LOGIC_TEST: PASS")
	else:
		for f in _failures:
			print("LOGIC_TEST: FAIL: ", f)
	quit(1 if not _failures.is_empty() else 0)


func _kb_target(l: int, p: int) -> Array:
	if p > 0:
		return [l, p - 1]
	if l > 0:
		return [l - 1, _main.display_lines[l - 1].length() - 1]
	return [0, 0]


func _expected_hint(ch: String) -> String:
	if ch == " ":
		return "Жми: Пробел"
	if ch == "":
		return ""
	return "Жми: " + ch.to_upper()


func _run_part1() -> void:
	_check(_main.display_lines.size() == 3, "three text lines loaded")
	# Старт: курсор на активной букве (фрагмент случайный — вычисляем).
	var ch0: String = _main._current()
	_check(ch0 != "" and _main._is_active(ch0), "cursor starts on active")
	_check(_main.hint_label.text == _expected_hint(ch0), "hint matches cursor")
	_check(_main.enemy_line == 0, "hedgehog starts on line 0")
	_check(not _main.hedge_active, "hedgehog waits until hero leaves line 0")
	# Верный ввод символа под курсором: клетка пройдена, курсор ушёл вперёд.
	var k0 := "%d:%d" % [_main.cursor_line, _main.cursor_pos]
	_main._type_char(ch0)
	_check(_main.typed_ok == 1, "typed_ok counted")
	_check(_main.passed.has(k0), "typed cell marked passed")
	# Опечатка 1 заведомо неверным символом: метка, откат, тряска.
	var exp1: String = _main._current()
	var wrong1 := "ы" if exp1.to_lower() != "ы" else "ж"
	var b1 := [_main.cursor_line, _main.cursor_pos]
	_main._type_char(wrong1)
	_check(_main.errors.size() == 1, "one error overlay")
	_check(_main.shake_t > 0.0, "shake on typo")
	_check(_main.hint_label.text == "Жми: ⌫ Backspace", "hint shows Backspace")
	var t1 := _kb_target(b1[0], b1[1])
	_check(_main.cursor_line == t1[0] and _main.cursor_pos == t1[1], "knockback one step")
	# Опечатка 2 подряд: откат ЕЩЁ дальше, вторая метка.
	var exp2: String = _main._current()
	var wrong2 := "ы" if exp2.to_lower() != "ы" else "ж"
	_main._type_char(wrong2)
	_check(_main.errors.size() == 2, "two error overlays")
	var t2 := _kb_target(t1[0], t1[1])
	_check(_main.cursor_line == t2[0] and _main.cursor_pos == t2[1], "cumulative knockback")
	# Backspace ×2: всё чисто.
	_main._backspace()
	_check(_main.errors.size() == 1, "first error erased")
	_main._backspace()
	_check(_main.errors.is_empty(), "all errors erased")
	# Совпавшая буква (даже серая) — не опечатка, меток не добавляет.
	var exp3: String = _main._current()
	var ok_before: int = _main.typed_ok
	_main._type_char(exp3)
	_check(_main.errors.is_empty(), "matching letter adds no error")
	_check(_main.typed_ok == ok_before + 1, "matching letter counted")
	# Ошибочный пробел виден: красная метка ␣ вместо пустоты.
	var exp4: String = _main._current()
	if exp4 != "" and exp4 != " ":
		_main._type_char(" ")
		var found := false
		for i in _main.display_lines.size():
			if "␣" in _main.text_labels[i].text:
				found = true
		_check(found, "wrong space shows visible marker")
		_main._backspace()
		_check(_main.errors.is_empty(), "space error erased")


## Часть 2: Backspace. Три режима по приоритету — стереть метку под
## курсором, починить метку впереди, и только потом (на «лишнее»
## нажатие) откатиться назад. Всё за один кадр: между проверками
## времени не идёт, ёж не активен и не мешает.
func _run_part2() -> void:
	# --- Режим 2: метка впереди — стираем и встаём на неё, НЕ откатом. ---
	_main._new_level()
	_main.cursor_line = 1
	_main.cursor_pos = _safe_pos(1, 4)
	var pf: int = _main.cursor_pos
	_main._type_char("ы" if _main._current().to_lower() != "ы" else "ж")
	_check(_main.cursor_pos == pf - 1, "typo knocked the hare back one cell")
	_main._backspace()
	_check(_main.cursor_pos == pf, "Backspace fixes the typo ahead instead of retreating")
	_check(_main.errors.is_empty(), "mark ahead erased")

	# --- Режим 3: стирать нечего — откат назад на клетку. ---------------
	# Позиции считаем от длины строки, а не константой: фрагмент текста
	# каждый раз случайный, иначе тест ловил бы не откат, а длину строки.
	_main._new_level()
	_main.cursor_line = 1
	_main.cursor_pos = _safe_pos(1, 6)
	var p0: int = _main.cursor_pos
	_main._type_char(_main._current())
	_main._type_char(_main._current())
	_main._type_char(_main._current())
	var p3: int = _main.cursor_pos
	_check(
		_main.cursor_line == 1 and _main.passed.has(_cell_key(1, p3 - 1)),
		"three letters typed"
	)
	var ch_ret: String = _main.display_lines[1].substr(p3 - 1, 1)
	var ok_before: int = _main.typed_ok
	var bad_before: int = _main.typed_bad
	_main._backspace()
	_check(
		_main.cursor_line == 1 and _main.cursor_pos == p3 - 1, "Backspace retreats one cell"
	)
	_check(
		not _main.passed.has(_cell_key(1, p3 - 1)),
		"retreat un-marks the cell: the letter has to be typed again"
	)
	_check(_main._current() == ch_ret, "the typed letter stands in front of the hare again")
	_check(
		_main.passed.has(_cell_key(1, p0)) and _main.passed.has(_cell_key(1, p0 + 1)),
		"retreat touches only the cell it lands on"
	)
	_check(
		_main.typed_ok == ok_before and _main.typed_bad == bad_before,
		"retreat does not touch the typing counters"
	)
	# Повторное нажатие — тот же откат: буква набирается заново и считается.
	_main._type_char(_main._current())
	_check(
		_main.cursor_pos == p3 and _main.passed.has(_cell_key(1, p3 - 1)),
		"retyped after the retreat"
	)

	# --- Откат через край строки: конец строки = начало следующей. ------
	_main.cursor_line = 2
	_main.cursor_pos = 0
	_main._backspace()
	_check(
		_main.cursor_line == 1 and _main.cursor_pos == _main.display_lines[1].length() - 1,
		"retreat crosses the line boundary"
	)
	_main._backspace()
	_check(
		_main.cursor_pos == _main.display_lines[1].length() - 2,
		"repeated retreat keeps walking back"
	)

	# --- Упор в начало текста: с первой клетки откатываться некуда. -----
	# Откат ВСТУПАЕТ на первую клетку (буква там снова не набрана — это
	# тот же откат, что и в середине текста), но дальше — пустота: курсор
	# стоит, ничего не меняется, игра жива.
	_main._new_level()
	_main.cursor_line = 0
	_main.cursor_pos = 0
	_main._type_char(_main._current())  # первая буква набрана
	_main.cursor_pos = 2
	_main._backspace()
	_main._backspace()
	_check(_main.cursor_line == 0 and _main.cursor_pos == 0, "retreat stops at the first cell")
	_check(
		not _main.passed.has("0:0"),
		"the first cell is restored like any other cell the retreat lands on"
	)
	_main._backspace()
	_main._backspace()
	_check(_main.cursor_line == 0 and _main.cursor_pos == 0, "no retreat past the very beginning")
	_check(_main.passed.is_empty(), "repeated Backspace at the start changes nothing")
	_check(_main.state == "playing", "Backspace at the very beginning is harmless")
	# Первая буква снова набирается и уровень проходится дальше.
	_main._type_char(_main._current())
	_check(_main.cursor_pos == 1, "the restored first letter can be typed again")

	# --- Откат на клетку с остатками опечатки: клетка становится целой. -
	_main._new_level()
	_main.cursor_line = 1
	_main.cursor_pos = _safe_pos(1, 10)
	var pm: int = _main.cursor_pos
	_main._type_char("ы" if _main._current().to_lower() != "ы" else "ж")
	_check(
		_main.cursor_pos == pm - 1 and _main.errors.has(_cell_key(1, pm)),
		"typo mark on a cell behind"
	)
	_main._type_char(_main._current())  # починили: курсор встал на метку
	_main._type_char(_main._current())  # и прошли её: курсор на pm+1
	_check(_main.cursor_pos == pm + 1, "the typo was fixed and passed")
	_check(
		_main.errors.has(_cell_key(1, pm)) and _main.passed.has(_cell_key(1, pm)),
		"the red mark outlives the fix and stays on the passed cell"
	)
	_main._backspace()
	_check(_main.cursor_pos == pm, "retreat lands on the marked cell")
	_check(
		not _main.passed.has(_cell_key(1, pm)) and not _main.errors.has(_cell_key(1, pm)),
		"retreat returns the cell to its pristine state"
	)

	# --- Механика пропусков: серые символы — тоже клетки, откат идёт по ним.
	# Все буквы серые (active пуст), пробелы активны всегда — автопропуск
	# встанет на первый пробел, а все буквы перед ним пройдёт сам.
	_main._new_level()
	_main.active = {}
	_main.cursor_line = 0
	_main.cursor_pos = _first_grey()
	var skip_from: float = _main._lin(0, float(_main.cursor_pos))
	_main._skip_inactive()
	var skip_to: float = _main._lin(_main.cursor_line, float(_main.cursor_pos))
	_check(_main.state == "playing", "auto-skip of grey letters stops at a space")
	_check(skip_to > skip_from, "auto-skip walked the hare forward over grey cells")
	# Последняя клетка, которую пропустил сам ход игры:
	var last := _behind()
	_check(_main.passed.has(_cell_key(last.x, last.y)), "the last auto-skipped cell is passed")
	# Откат назад обязан встать ровно на неё и вернуть букву.
	_main._backspace()
	_check(
		_main.cursor_line == last.x and _main.cursor_pos == last.y,
		"retreat from a skip lands exactly on the last skipped cell"
	)
	_check(
		not _main.passed.has(_cell_key(_main.cursor_line, _main.cursor_pos)),
		"the skipped cell is not passed anymore after the retreat"
	)
	_check(
		_main._lin(_main.cursor_line, float(_main.cursor_pos)) < skip_to - 0.001,
		"retreat over a skip goes back behind the whole skipped run"
	)


## Позиция на строке l для теста: хотела бы want, но не за концом
## строки (фрагмент текста случайный, длины плавают). Возвращает
## позицию, с которой можно безопасно набрать и откатиться.
func _safe_pos(l: int, want: int) -> int:
	var n: int = _main.display_lines[l].length()
	return mini(maxi(want, 2), maxi(n - 4, 0))


## Клетка на шаг назад от курсора по сквозной оси: (строка, позиция).
func _behind() -> Vector2i:
	if _main.cursor_pos > 0:
		return Vector2i(_main.cursor_line, _main.cursor_pos - 1)
	return Vector2i(
		_main.cursor_line - 1, _main.display_lines[_main.cursor_line - 1].length() - 1
	)


func _cell_key(l: int, p: int) -> String:
	return "%d:%d" % [l, p]


## Первая не-пробельная буква строки 0: с неё можно запустить автопропуск
## (пробелы активны всегда, на них пропуск останавливается сам).
func _first_grey() -> int:
	var l0: String = _main.display_lines[0]
	for i in l0.length():
		if l0.substr(i, 1) != " ":
			return i
	return 0
