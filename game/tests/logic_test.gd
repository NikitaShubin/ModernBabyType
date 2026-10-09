extends SceneTree
## Детерминированный тест геймплея: ввод, кумулятивный откат,
## Backspace (стереть метку / починить впереди / откат назад, упор в
## начало текста, откат по серым пропускам), подсказка, ёж на строку выше.
## Запуск: godot --headless --path game --script res://tests/logic_test.gd
## Код выхода 0 — всё сошлось.

const BB := preload("res://scripts/balance.gd")
const S := preload("res://scripts/save.gd")
const K := preload("res://scripts/kbd.gd")

var _frame := 0
var _main: Node = null
var _failures: Array[String] = []
var _d0 := 0.0
var _ex0 := 0.0
var _hx := 0.0
var _hx0 := 0.0
var _hy := 0.0


func _check(cond: bool, what: String) -> void:
	if not cond:
		_failures.append(what)


func _initialize() -> void:
	# Фиксированный сид: _load_text берёт случайный кусок уровня, и без
	# сида абсолютные позиции сценариев (строка 1, символ 15) то влезают
	# в строку, то нет — тест валился в CI, дома проходил. Как seed
	# у chase_test, только глобальный (таблицы в _load_text на нём).
	seed(20261006)
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
		# Догон картинки — детерминированно: крутим _process фиксированным
		# шагом, а не ждём стену. На быстрой машине 48 кадров пролетают
		# быстрее, чем lerp сходится (падало в CI, дома проходило).
		var d1 := _d0
		for i in 120:
			if d1 < _d0 * 0.5:
				break
			_main._process(1.0 / 60.0)
			d1 = _main.hero_r.distance_to(_main._hero_pos())
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
		return "Жми: [Пробел]"
	if ch == "":
		return ""
	if _main._exact() and ch == ch.to_upper() and ch != ch.to_lower():
		# Заглавная в строгом режиме: парой Shift + буква.
		return "Жми: [Shift] + [" + ch + "]"
	# В строгом режиме показываем букву как есть (регистр важен),
	# в обычном — для удобства заглавную.
	return "Жми: [" + (ch if _main._exact() else ch.to_upper()) + "]"


func _run_part1() -> void:
	_check(_main.display_lines.size() == 3, "three text lines loaded")
	# Старт: курсор на активной букве (фрагмент случайный — вычисляем).
	var ch0: String = _main._current()
	_check(ch0 != "" and _main._is_active(ch0), "cursor starts on active")
	_check(_main._hint_text() == _expected_hint(ch0), "hint matches cursor")
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
	_check(_main._hint_text() == "Жми: [←] Стереть", "hint shows how to erase")
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
	# Откат идёт к последней НАБРАННОЙ клетке (перепрыгивая серые), а не
	# к соседней: иначе Backspace вставал на серую клетку, где букве
	# не место, и повторный набор давал метку (живой лог 10.2026).
	_main.cursor_line = 2
	_main.cursor_pos = 0
	# Последняя набранная клетка перед (2,0) — конец строки 1: кладём её.
	var edge: int = _main.display_lines[1].length() - 1
	_main.passed[_cell_key(1, edge)] = true
	_main.typed_cells[_cell_key(1, edge)] = true
	_main._backspace()
	_check(
		_main.cursor_line == 1 and _main.cursor_pos == edge,
		"retreat crosses the line boundary"
	)
	_check(
		_main.passed.has(_cell_key(1, edge)) == false,
		"retreat landed on the last filled cell and cleared it"
	)
	_main._backspace()
	_check(
		Vector2i(_main.cursor_line, _main.cursor_pos)
			!= Vector2i(1, _main.display_lines[1].length() - 1),
		"repeated retreat walks further back"
	)

	# --- Откат в серую клетку и дубль: игра обязана ответить визуально.
	# Живой лог с телефона 10.2026: Backspace встал на серую клетку (стирать
	# нечего), затем та же буква уходила в dup-ignore — на экране обе
	# ситуации выглядели как «не считает», ребёнок крутил букву по кругу.
	_main._new_level()
	# Набираем первую активную букву и уходим на пассивную клетку после неё.
	var first_active := -1
	for i in _main.display_lines[0].length():
		if _main._is_active(_main.display_lines[0].substr(i, 1)):
			first_active = i
			break
	_check(first_active >= 0, "level has an active letter to type")
	_main.cursor_line = 0
	_main.cursor_pos = first_active
	_main._type_char(_main._current())
	var after_ok := Vector2i(_main.cursor_line, _main.cursor_pos)
	_check(after_ok != Vector2i(0, first_active), "cursor moved past the typed letter")
	# Откат перепрыгивает серые клетки и отменяет последнюю набранную
	# букву (а не встаёт на серую клетку). Сценарий строится явно:
	# пройденная буква, за ней серая полоса, курсор за ней.
	_main.hints.clear()
	var filled: Vector2i = _main._last_filled_behind()
	_check(filled.x == 0 and filled.y == first_active,
		"last filled cell behind the cursor is the typed letter")
	var line0: String = _main.display_lines[0]
	# Ищем серию серых клеток сразу за набранной буквой.
	var grey_run := 0
	for i in range(first_active + 1, line0.length()):
		if _main._is_active(line0.substr(i, 1)):
			break
		grey_run += 1
	# Серая полоса есть не в каждом уровне (в «Вертит» все буквы активны).
	# Строим её явно: убираем буквы из активных на несколько клеток.
	if grey_run == 0 and line0.length() >= first_active + 4:
		grey_run = 2
		var hidden: Array[String] = []
		for i in range(first_active + 1, first_active + 3):
			var hc: String = line0.substr(i, 1)
			if not hidden.has(hc):
				hidden.append(hc)
		for hc in hidden:
			_main.active.erase(hc)
		_main._new_level()
		_main.active = BB.active_chars(0)
		for hc in hidden:
			_main.active.erase(hc)
		first_active = -1
		for i in _main.display_lines[0].length():
			if _main._is_active(_main.display_lines[0].substr(i, 1)):
				first_active = i
				break
		_main.cursor_line = 0
		_main.cursor_pos = first_active
		_main._type_char(_main._current())
		line0 = _main.display_lines[0]
		grey_run = 0
		for i in range(first_active + 1, line0.length()):
			if _main._is_active(line0.substr(i, 1)):
				break
			grey_run += 1
	_check(grey_run > 0, "level has a grey run after the typed letter")
	if grey_run > 0:
		_main.cursor_line = 0
		_main.cursor_pos = first_active + grey_run
		var ok_pre: int = _main.typed_ok
		_main._backspace()
		_check(
			Vector2i(_main.cursor_line, _main.cursor_pos) == Vector2i(0, first_active),
			"retreat jumps the grey run back to the typed letter"
		)
		_check(
			not _main.passed.has(_cell_key(0, first_active)),
			"the typed letter is untyped again"
		)
		_check(
			_main.typed_ok == ok_pre,
			"retreat does not touch the counters"
		)
		# Повторный набор той же буквы — верный, без всяких меток.
		_main._type_char_comp(_main._current())
		_check(
			_main.typed_bad == 0 and _main.errors.is_empty(),
			"retyping after the retreat makes no mistake"
		)
	# Дубль КЛАВИШИ (та же буква дважды подряд от IME): вторая вспыхивает
	# на клетке принятой и курсор не двигает — нажатие не выглядит
	# проигнорированным (автор 10.2026 крутил букву по кругу).
	_main.hints.clear()
	_main.cursor_line = after_ok.x
	_main.cursor_pos = after_ok.y
	var behind_ch: String = _main.display_lines[0].substr(first_active, 1)
	var wanted: String = _main._current()
	_check(
		not _main._eq(behind_ch, wanted),
		"the letter behind differs from the expected one"
	)
	# Сначала принимаем «л» (она нужна в этом слове), потом сразу ту же
	# ещё раз — это дубль клавиши.
	_main._type_char_comp(wanted)
	_main.hints.clear()
	var cur_after: Vector2i = Vector2i(_main.cursor_line, _main.cursor_pos)
	_main._type_char_comp(wanted)
	_check(
		Vector2i(_main.cursor_line, _main.cursor_pos) == cur_after,
		"a doubled key does not move the cursor"
	)
	_main.hints.clear()

	# --- ПОРЯДОК ВВОДА: софт-буква, затем пробел с настоящим keycode.
	# Живой лог с телефона 10.2026: Яндекс шлёт букву с keycode
	# KEY_UNKNOWN (она копится в буфер), а пробел приходит сразу с
	# KEY_SPACE и раньше применялся напрямую — то есть ПЕРЕПРЫГИВАЛ
	# букву, нажатую на 6 мс раньше. На экране это выглядело как
	# «букву не считает»: пробел давал метку на месте буквы, откат
	# уносил курсор назад, и буква приходила уже не туда.
	_main._new_level()
	# Находим активную букву, за которой идёт пробел (как в «Снесла
	# курочка»: «а», потом пробел) — на нём порядок и ломается.
	# Ищем активную букву, за которой (через серые клетки) идёт пробел, —
	# как в «Снесла курочка». Подойдёт любая: нас интересует сам порядок.
	var a_at := -1
	var sp_at := -1
	var letter: String = ""
	var line_a: String = _main.display_lines[0]
	for i in range(1, line_a.length()):
		if line_a.substr(i, 1) != " ":
			continue
		var j := i - 1
		while j >= 0 and not _main._is_active(line_a.substr(j, 1)):
			j -= 1
		if j >= 0:
			a_at = j
			sp_at = i
			letter = line_a.substr(j, 1)
			break
	_check(a_at >= 0, "level has an active letter right before a space")
	if a_at >= 0 and sp_at > a_at:
		_main.cursor_line = 0
		_main.cursor_pos = a_at
		var bad_pre: int = _main.typed_bad
		# Буква с KEY_UNKNOWN — уходит в буфер, как от Яндекса.
		_main.call("_unhandled_key_input", _soft_key(letter))
		_check(bool(_main._comp_active), "soft letter is buffered")
		# Пробел с настоящим keycode KEY_SPACE — идёт следом, без буфера.
		_main.call("_unhandled_key_input", _space_key())
		# Пробел обязан примениться ПОСЛЕ буквы, а не вместо неё.
		_check(
			_main.passed.has(_cell_key(0, a_at)),
			"space waits for the queued letter: the letter is still counted"
		)
		_check(
			Vector2i(_main.cursor_line, _main.cursor_pos) > Vector2i(0, a_at),
			"cursor is past the letter when the space lands"
		)
		_check(
			_main.typed_bad == bad_pre,
			"letter-then-space makes no mistake (order kept)"
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

	# --- Откат на клетку с остатками опечатки: верный набор стирает метку.
	# Баг автора: ложный пробел пережил Backspace мимо и остался красным,
	# хотя буква потом набралась верно. Метка — про «здесь ошиблись»,
	# а не клеймо навсегда: верная буква её закрывает.
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
		not _main.errors.has(_cell_key(1, pm)) and _main.passed.has(_cell_key(1, pm)),
		"correct typing erases the stale mark: the cell is passed and clean"
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
	# Backspace по серым автопропускам НИЧЕГО не делает: их проскочила
	# игра, игрок их не печатал, откатывать нечего. Раньше откат вставал
	# на такую клетку — и это выглядело как «игра не считает» (живой
	# лог 10.2026: BACK;rollback;0:2 на серую «с» после принятой «о»).
	var cur_keep := Vector2i(_main.cursor_line, _main.cursor_pos)
	_main._backspace()
	_check(
		Vector2i(_main.cursor_line, _main.cursor_pos) == cur_keep,
		"retreat over auto-skipped grey cells does nothing"
	)
	_check(
		_main.passed.has(_cell_key(last.x, last.y)),
		"auto-skipped cells stay passed after Backspace"
	)
	# А откат настоящей набранной буквы работает: сначала набираем
	# активную букву, потом откатываемся — встаём ровно на неё.
	_main._new_level()
	_main.active = BB.active_chars(0)
	_main.cursor_line = 0
	_main.cursor_pos = _first_active()
	var fa := _first_active()
	_main._type_char(_main._current())
	var typed_at := Vector2i(_main.cursor_line, _main.cursor_pos)
	var ok_t: int = _main.typed_ok
	_check(
		_main.passed.has(_cell_key(0, fa)),
		"the typed letter is passed before the retreat"
	)
	_main._backspace()
	_check(
		Vector2i(_main.cursor_line, _main.cursor_pos) == Vector2i(0, fa),
		"retreat lands exactly on the typed letter, jumping the grey run"
	)
	_check(
		not _main.passed.has(_cell_key(0, fa)),
		"the typed letter is untyped again"
	)
	_check(
		_main.typed_ok == ok_t, "retreat does not touch the counters"
	)
	# И повторный набор той же буквы — верный, без меток.
	_main._type_char_comp(_main._current())
	_check(
		_main.typed_bad == 0 and _main.errors.is_empty(),
		"retyping after the retreat makes no mistake"
	)
	_check(
		typed_at.y > 0 or typed_at.x > 0,
		"the auto-skip had actually moved the cursor on"
	)

	# --- Системная клавиатура Android: события без keycode, один unicode.
	# Backspace приходит как unicode 8, Enter — как 10/13. Без фолбэков
	# с ней нельзя ни стереть, ни продолжить после победы, а Enter прямо
	# во время партии рисовал бы красную метку перевода строки.
	_main._new_level()
	_main.cursor_line = 1
	_main.cursor_pos = _safe_pos(1, 6)
	var pu: int = _main.cursor_pos
	_main._type_char("ы" if _main._current().to_lower() != "ы" else "ж")
	_check(_main.errors.has(_cell_key(1, pu)), "soft typo left a mark")
	_main._unhandled_key_input(_softkey(8))
	_main._comp_flush()
	_check(_main.errors.is_empty(), "unicode backspace erases the mark")
	_check(_main.cursor_pos == pu, "unicode backspace steps onto the cell")
	_main._unhandled_key_input(_softkey(13))
	_main._comp_flush()
	_check(_main.errors.is_empty(), "unicode enter is not typed as a letter")
	_check(_main.cursor_pos == pu, "unicode enter moves nothing while playing")
	_main.state = "won"
	_main._unhandled_key_input(_softkey(13))
	_main._comp_flush()
	_check(_main.state == "playing", "unicode enter continues after winning")

	# --- Софтовая кириллица (commitText без keycode, как шлёт Gboard):
	# буква обязана дойти до игры, а не потеряться. Регресс живого
	# телефона: там меню кириллицу ест, а игра молчала.
	_main._new_level()
	_main.cursor_line = 1
	_main.cursor_pos = _safe_pos(1, 6)
	var pw: int = _main.cursor_pos
	var wc := "ф"
	if _main._current().to_lower() == "ф":
		wc = "ж"
	_main._unhandled_key_input(_softkey(wc.unicode_at(0)))
	_main._comp_flush()
	# Промах с системной клавиатуры — тоже опечатка: красная метка и счёт.
	# Заглушка 10.2026 («мягкий промах» без метки) прятала настоящие
	# ошибки вместе с фантомными — так делать нельзя.
	_check(_main.errors.has(_cell_key(1, pw)),
		"a soft-letter miss leaves a red mark like any other typo")
	_check(_main.typed_bad > 0, "a soft-letter miss counts the mistake")

	# --- Composing-перепись IME (Яндекс/Gboard, русский): каждый тап
	# стирает и вводит заново всё слово (серии DEL + дубли, keycode
	# KEY_UNKNOWN/0 — живой лог с телефона 10.2026; раньше там же была
	# своя RU-клавиатура, её убрали в 0.0.9). Без буфера каждый дубль —
	# «опечатка»: красные метки, откат, врущие счётчики. Гость тапает
	# только активные буквы (по подсказке «Жми»): после каждого тапа
	# ровно +1 верная буква, ни одной метки, курсор только вперёд.
	_main._new_level()
	# Гость вручную: в дебажной сборке _all_keys() всегда true, а для
	# composing-каши нужны серые буквы. Флаг не трогаем (протечёт
	# в соседние части), только набор активных.
	_main.active = BB.active_chars(0)
	var taps := ""
	var ok0: int = _main.typed_ok
	for t in 6:
		var want := String(_main._current())
		if want == "":
			break
		taps += want
		for _j in taps.length() - 1:
			_main._unhandled_key_input(_unknownkey(8))
		for j in taps.length():
			_main._unhandled_key_input(_unknownkey(taps.unicode_at(j)))
		_main._comp_flush()
	_check(_main.typed_bad == 0, "compose flow leaves no typos")
	_check(_main.errors.is_empty(), "compose flow leaves no marks")
	_check(
		int(_main.typed_ok) == ok0 + 6,
		"compose flow counts only new letters"
	)

	# --- Дифф-пары IME (Яндекс при быстром наборе: каждый тап — пара
	# [DEL + буква], живой лог 10.2026). Пара вводит свою букву обычным
	# путём с начала серии: верная засчитывается, счётчик честный.
	_main._new_level()
	_main.active = BB.active_chars(0)
	var ok1: int = _main.typed_ok
	var cur0 := Vector2i(_main.cursor_line, _main.cursor_pos)
	for t in 6:
		var want2 := String(_main._current())
		if want2 == "":
			break
		_main._unhandled_key_input(_unknownkey(8))
		_main._unhandled_key_input(_unknownkey(want2.unicode_at(0)))
		_main._comp_flush()
	_check(_main.typed_bad == 0, "diff pairs leave no typos")
	_check(_main.errors.is_empty(), "diff pairs leave no marks")
	_check(
		int(_main.typed_ok) == ok1 + 6,
		"diff pairs count every letter"
	)
	_check(
		Vector2i(_main.cursor_line, _main.cursor_pos) != cur0,
		"diff pairs move the cursor forward"
	)

	# --- Автозамена слова (Яндекс после пробела: DEL-серия + чужое слово,
	# жалоба автора «после пробела отбрасывает назад»). Чужая замена
	# отменяется целиком: курсор на месте, меток нет, счётчики стоят.
	var cur1 := Vector2i(_main.cursor_line, _main.cursor_pos)
	var ok2: int = _main.typed_ok
	for _j in 3:
		_main._unhandled_key_input(_unknownkey(8))
	for j in "xyz".length():
		_main._unhandled_key_input(_unknownkey("xyz".unicode_at(j)))
	_main._comp_flush()
	_check(
		Vector2i(_main.cursor_line, _main.cursor_pos) == cur1,
		"foreign replacement moves nothing"
	)
	_check(_main.errors.is_empty(), "foreign replacement leaves no marks")
	_check(
		int(_main.typed_ok) == ok2 and _main.typed_bad == 0,
		"foreign replacement touches no counters"
	)

	# --- Дубль без DEL (Яндекс шлёт повторы одиночками, живой лог
	# 10.2026: красные «ама» при сериях DELx0+1). Символ, совпавший
	# с пройденной клеткой позади, — повтор IME: игнорируется молча.
	# Верный ввод и настоящие опечатки идут обычным путём.
	_main._new_level()
	_main.active = BB.active_chars(0)
	# 1) Настоящий дубль клавиши: та же буква дважды подряд миллисекунда
	# в миллисекунду (так шлёт IME с словарём) — вторая глушится молча.
	var first: String = _main._current()
	_main._type_char(first)
	_main._type_char_comp(first)
	_main._comp_flush()
	var dup_ok: int = _main.typed_ok
	var dup_bad: int = _main.typed_bad
	_check(
		int(_main.typed_ok) == dup_ok and int(_main.typed_bad) == dup_bad,
		"doubled key is dropped: no counters move"
	)
	# 2) ТА ЖЕ буква, но НЕ дубль клавиши: она просто встречалась раньше
	# в тексте. Именно это ломало игру: «л» из «Прибежала» глушила «л» в
	# «внучка» (живой лог 10.2026: TYPE;л;ч;dup-ignore;...;0:7). Теперь
	# такой ввод судится как обычный — верный идёт, неверный даёт метку.
	_main._new_level()
	_main.active = BB.active_chars(0)
	# Набираем две разные буквы, чтобы в passed было из чего выбрать.
	_main._type_char(_main._current())
	_main._type_char(_main._current())
	var seen: Array[String] = []
	for kk in _main.passed.keys():
		var pp := String(kk).split(":")
		var cj: String = _main.display_lines[int(pp[0])].substr(int(pp[1]), 1)
		if not seen.has(cj):
			seen.append(cj)
	_check(seen.size() >= 2, "level gives two different typed letters")
	# Ставим курсор на клетку, где нужна ДРУГАЯ буква, и набираем ту, что
	# уже встречалась. Старое правило молчало; теперь — честная метка.
	var l0: String = _main.display_lines[0]
	var tried := 0
	for a in seen.size():
		for b in seen.size():
			if a == b:
				continue
			var pos: int = l0.find(seen[b])
			if pos < 0 or _main._eq(seen[a], seen[b]):
				continue
			if pos >= _main.passed.size():
				continue
			_main.cursor_line = 0
			_main.cursor_pos = pos
			var want_here: String = _main._current()
			if _main._eq(want_here, seen[a]):
				continue
			var ok_pre: int = _main.typed_ok
			var bad_pre: int = _main.typed_bad
			_main.hints.clear()
			_main._type_char_comp(seen[a])
			# Не та буква там, где её не ждут: честная метка, без проглота.
			# Узкое правило дублей глушит только повтор клавиши подряд.
			_check(
				int(_main.typed_ok) == ok_pre and int(_main.typed_bad) == bad_pre + 1,
				"a letter seen earlier is judged, not swallowed"
			)
			_main._new_level()
			_main.active = BB.active_chars(0)
			# А теперь та же буква там, где она НУЖНА: проходит.
			_main._type_char(_main._current())
			var ok_pre2: int = _main.typed_ok
			_main._type_char_comp(_main._current())
			_check(
				int(_main.typed_ok) == ok_pre2 + 1,
				"a letter seen earlier is still accepted where it is needed"
			)
			tried += 1
			break
		if tried > 0:
			break
	_check(tried > 0, "test exercised a letter seen earlier")
	# 3) Дубль не глушится, если буква как раз нужная: он засчитывается.
	_main._new_level()
	_main._type_char_comp(_main._current())
	_main._type_char_comp(_main._current())
	_check(int(_main.typed_ok) >= 1, "a needed letter is never treated as a double key")

	# --- Перерисовка атомарна: _refresh() САМ применяет окно скролла.
	# Раньше текст обновлялся сразу, а позиции и видимость — только на
	# следующем кадре _process. Между ними на экране старые строки на
	# старых местах (жалоба автора 10.2026: «старое положение текста не
	# стирается, но поверх него уже рисуется новое»). Проверяем без
	# _process: после _refresh() за пределами окна скролла ничего нет.
	_main._new_level()
	while _main.display_lines.size() < 8:
		_main.display_lines.append("Длинная строка для прокрутки текста")
	_main._refresh()
	var vis_n: int = _main._vis_lines()
	_check(vis_n < _main.display_lines.size(), "the level scrolls on a small window")
	_main.cursor_line = _main.display_lines.size() - 1
	_main._refresh()  # без _process!
	var first_n: int = maxi(_main.display_lines.size() - vis_n, 0)
	var outside := 0
	for l in _main.text_labels.size():
		var tl: RichTextLabel = _main.text_labels[l]
		if not tl.visible:
			continue
		if l < first_n or l >= _main.display_lines.size():
			outside += 1
	_check(outside == 0, "the scroll window is applied inside the redraw itself")
	# И содержимое видимых лейблов — именно те строки, что на своих местах.
	var mismatched := 0
	for l in range(first_n, mini(_main.display_lines.size(), first_n + vis_n)):
		if l >= _main.text_labels.size():
			break
		var tl2: RichTextLabel = _main.text_labels[l]
		if not tl2.visible:
			mismatched += 1
			continue
		# Длина «голого» текста (без bbcode) равна длине строки.
		var plain: String = tl2.text.replace("[color=#6f6a5e]", "").replace("[color=#b3a996]", "")
		plain = plain.replace("[color=#1c1a16]", "").replace("[/color]", "")
		if plain.length() != _main.display_lines[l].length():
			mismatched += 1
	_check(mismatched == 0, "each visible label holds its own line's letters")
	_main._new_level()

	# --- Пачка от IME: одна опечатка НЕ должна уносить курсор и плодить
	# ошибки на всю пачку. Живой лог 10.2026: TYPE;о; ;mark; Type; ;а;mark —
	# две красные метки из одного нажатия (автор: «после пробела сразу
	# несколько ошибок»). В пачке курсор стоит, ошибается только своя
	# клетка, следующая буква встаёт по логике текста.
	_main._new_level()
	# Ищем место «активная буква, ПРОБЕЛ, активная буква» — как «о»,
	# пробел, «о» в «Посадил дед». Ошибка будет на пробеле.
	var l0b: String = _main.display_lines[0]
	var gap_at := -1
	for i in range(1, l0b.length() - 1):
		if l0b.substr(i, 1) == " " and _main._is_active(l0b.substr(i, 1)):
			if l0b.substr(i - 1, 1) != " " and l0b.substr(i + 1, 1) != " ":
				gap_at = i
				break
	_check(gap_at >= 0, "level has an active letter, a space, a letter")
	if gap_at >= 0:
		# Набираем букву перед пробелом — верно, курсор встаёт на пробел.
		_main.cursor_line = 0
		_main.cursor_pos = gap_at - 1
		_main._type_char_comp(l0b.substr(gap_at - 1, 1))
		_check(
			Vector2i(_main.cursor_line, _main.cursor_pos) == Vector2i(0, gap_at),
			"cursor stands on the space after a correct letter"
		)
		var bad_pre: int = _main.typed_bad
		# Пачка от IME: неверная клавиша даёт ровно одну метку — и всё.
		# Откат внутри пачки отменён, иначе одна ошибка уносила курсор
		# и валила всю пачку каскадом.
		_main.cursor_line = 0
		_main.cursor_pos = gap_at
		_main.hints.clear()
		_main._type_char("ь", true)  # мусор: ждали пробел
		_check(
			_main.typed_bad == bad_pre + 1,
			"the wrong key in a batch makes exactly one mistake"
		)
		_check(
			_main.errors.has(_cell_key(0, gap_at)),
			"the batch mistake marks its own cell"
		)
		_check(
			Vector2i(_main.cursor_line, _main.cursor_pos) == Vector2i(0, gap_at),
			"a mistake inside a batch does not drag the cursor back"
		)
		# Следующая буква пачки встаёт туда, где стоит по тексту.
		_main._type_char(" ", true)
		_check(
			Vector2i(_main.cursor_line, _main.cursor_pos) == Vector2i(0, gap_at + 1),
			"the rest of the batch is applied in place, not as a cascade"
		)
		_check(
			_main.typed_bad == bad_pre + 1,
			"the batch holds exactly the one mistake, no cascade"
		)
		# С железной клавишей откат сохраняется: ребёнок может перебить
		# опечатку (там одиночная клавиша, а не пачка).
		_main._new_level()
		_main.cursor_line = 0
		_main.cursor_pos = 0
		_main._type_char(_main._current())
		var kb_to: Vector2i = Vector2i(_main.cursor_line, _main.cursor_pos)
		_main._type_char("ь")
		_check(
			Vector2i(_main.cursor_line, _main.cursor_pos) != kb_to,
			"a hard key mistake still knocks the cursor back"
		)

	# --- Автопунктуация IME: точка с настоящим keycode, когда игра ждёт
	# другого, — не ошибка игрока. Живой лог 10.2026: TYPE;.; ;mark;(1, 5)
	# сразу после BACK;rollback — автор такие точки не нажимал.
	_main._new_level()
	_main.active = BB.active_chars(0)
	S.set_sys_kb(true)
	var want_here: String = _main._current()
	var bad_pre2: int = _main.typed_bad
	_main.call("_unhandled_key_input", _hardkey(KEY_PERIOD, ".".unicode_at(0)))
	_check(
		_main.typed_bad == bad_pre2,
		"an IME-inserted period is not counted as a mistake"
	)
	_check(
		_main.errors.is_empty(),
		"an IME-inserted period leaves no red mark"
	)
	# А вот когда игра точку ЖДЁТ — она проходит какusually.
	_main.cursor_line = 0
	_main.cursor_pos = 0
	while _main._current() != "." and _main.cursor_pos < 40:
		_main.cursor_pos += 1
		if _main._current() == " " or _main._current() == "":
			_main.cursor_pos += 1
	if _main._current() == ".":
		var ok_pre3: int = _main.typed_ok
		_main.call("_unhandled_key_input", _hardkey(KEY_PERIOD, ".".unicode_at(0)))
		_check(
			_main.typed_ok == ok_pre3 + 1,
			"an expected period is typed normally"
		)
	S.set_sys_kb(false)

	# --- Два пробела подряд, между ними только серые буквы: режим
	# ограниченного набора, где игрок обязан жать пробел дважды. Жалоба
	# автора 10.2026: «если жму пробел дважды быстро, второй не
	# засчитывается». Оба пробела должны приниматься.
	_main._new_level()
	_main.active = {" ": true}
	var sp1 := -1
	var sp2 := -1
	var l0s: String = _main.display_lines[0]
	for i in l0s.length():
		if l0s.substr(i, 1) == " " and sp1 < 0:
			sp1 = i
		elif l0s.substr(i, 1) == " " and sp1 >= 0 and sp2 < 0:
			if i > sp1 + 1:
				sp2 = i
				break
	_check(sp1 >= 0 and sp2 > sp1, "the level has two spaces with greys between")
	if sp2 > sp1:
		_main.cursor_line = 0
		_main.cursor_pos = sp1
		_main._type_char(" ", true)
		_check(
			Vector2i(_main.cursor_line, _main.cursor_pos) == Vector2i(0, sp2),
			"the first space walks the cursor to the second one"
		)
		# Второй пробел сразу, в том же такте: он НЕ дубль клавиши.
		var ok_b4: int = _main.typed_ok
		_main._type_char_comp(" ")
		_check(
			int(_main.typed_ok) == ok_b4 + 1,
			"the second space is counted, not swallowed as a double key"
		)
		# И третий подряд, тоже быстро: дубля клавиши тут нет — игра
		# каждый пробел ждёт отдельно.
		var ok_b5: int = _main.typed_ok
		_main._type_char_comp(" ")
		_check(
			int(_main.typed_ok) > ok_b5,
			"a third space in the same tick is judged on its own"
		)

	# --- После победы ввод не принимается: последняя пачка от IME не
	# должна дописываться после END (живой лог 10.2026: END;win, а через
	# 10 мс TYPE;а;а;ok — счётчик рос, игрок видел «пробел съелся»).
	_main._new_level()
	_main.active = BB.active_chars(0)
	var ok_b6: int = _main.typed_ok
	_main._finish(true, "")
	_main._type_char(_main._current())
	_main._type_char_comp("а")
	_main._comp_flush()
	_check(
		int(_main.typed_ok) == ok_b6,
		"no input is counted after the level is over"
	)

	# --- Backspace при системной клавиатуре НЕ откатывает набранные буквы:
	# IME пришлёт меньше, чем снято, и игрок зациклится (живой лог
	# 10.2026: 109 набранных при 55 нужных, ёж догнал).
	_main._new_level()
	_main.active = BB.active_chars(0)
	_main._type_char(_main._current())
	var filled_before: int = _main.typed_cells.size()
	S.set_sys_kb(true)
	_main._backspace()
	_check(
		_main.typed_cells.size() == filled_before,
		"backspace keeps typed letters while the system keyboard is on"
	)
	_check(true, "the skipped rollback keeps the typed letters (checked above)")
	# А со своей клавиатурой откат работает как обычно.
	S.set_sys_kb(false)
	_main._backspace()
	_check(
		_main.typed_cells.size() < filled_before,
		"backspace still rolls back with the own keyboard"
	)

	# --- Новый уровень пере-поднимает системную клавиатуру: иначе сессия
	# IME рвётся (уровень начат нажатием клавиши) и буквы уходят в никуда,
	# пока игрок не тапнёт по тексту. Жалоба автора 10.2026: «после смены
	# уровня нажимал правильную букву, реакции не было».
	S.set_sys_kb(true)
	var before_refocus := int(_main._kb_refocus)
	_main._new_level()
	_check(int(_main._kb_refocus) > before_refocus,
		"a new level re-focuses the system keyboard")
	# Обратный отсчёт кадров: до показа клавиатура скрыта.
	_check(int(_main._kb_refocus) > 0, "the keyboard re-show is scheduled")
	var frames := 0
	while int(_main._kb_refocus) > 0 and frames < 10:
		_main.call("_process", 0.016)
		frames += 1
	_check(int(_main._kb_refocus) == 0, "the keyboard comes back within a few frames")
	_check(frames < 10, "the re-show does not hang")
	# Без системной клавиатуры пере-показ не нужен (десктоп).
	S.set_sys_kb(false)
	var after_refocus := int(_main._kb_refocus)
	_main._new_level()
	_check(int(_main._kb_refocus) == after_refocus,
		"without the system keyboard there is nothing to re-focus")

	# --- Низ верхнего выреза экрана (камера-капля): чистая функция.
	_check(Ui.cutout_bottom([], 2340.0) == 0.0, "no cutouts means no inset")
	_check(
		Ui.cutout_bottom([Rect2(500, 0, 100, 80)], 2340.0) == 80.0,
		"top cutout pushes content down"
	)
	_check(
		Ui.cutout_bottom([Rect2(0, 2000, 100, 80)], 2340.0) == 0.0,
		"bottom cutout is ignored"
	)

	# --- Серия размазалась по кадрам (автозамена: DEL сейчас, слово
	# следующим циклом). Висящие DEL ждут символы до дедлайна, а не
	# сбрасываются: иначе откаты применены, а слово встанет метками.
	_main._new_level()
	_main.active = BB.active_chars(0)
	_main._type_char(_main._current())
	_main._type_char(_main._current())
	var cur2 := Vector2i(_main.cursor_line, _main.cursor_pos)
	var ok3: int = _main.typed_ok
	for _j in 2:
		_main._unhandled_key_input(_unknownkey(8))
	_main._comp_flush()
	_check(
		Vector2i(_main.cursor_line, _main.cursor_pos) != cur2,
		"hanging DELs applied (cursor moved back)"
	)
	for j in "xyz".length():
		_main._unhandled_key_input(_unknownkey("xyz".unicode_at(j)))
	_main._comp_flush()
	_check(
		Vector2i(_main.cursor_line, _main.cursor_pos) == cur2,
		"late word joins the hanging DELs and is dropped"
	)
	_check(_main.errors.is_empty(), "late word leaves no marks")
	_check(
		int(_main.typed_ok) == ok3 and _main.typed_bad == 0,
		"late word touches no counters"
	)
	# А протухшие DEL (дедлайн вышел, символов не было) — настоящие
	# ручные стирания: цикл закрыт, курсор остаётся откаченным.
	_main._unhandled_key_input(_unknownkey(8))
	_main._comp_deadline = 0
	_main._comp_flush()
	_check(not _main._comp_active, "expired DELs close the cycle")

	# --- Пере-показ клавиатуры: чистое решение, матрица сочетаний. ---
	# want/shown/height/elapsed/seen/reshown: показать заново — один раз
	# и только если клавиатура так и не выехала. Смахнутую пользователем
	# (была видна) не трогаем никогда.
	# Своя клавиатура вместо системной (решение автора 10.2026).
	# Видна в партии на сенсорных устройствах (в headless — через
	# _force_touch), на десктопе её нет (есть железная). Тап по клавише
	# даёт символ напрямую, без IME: composing-переписям неоткуда взяться.
	_main._new_level()
	_touch(true)
	root.size = Vector2i(1100, 650)
	_main._relayout()
	_check(_main._own_shown(), "own keyboard shows while playing on touch")
	_check(_main.kb_h > 0.0, "own keyboard takes layout height")
	var kb_area: Rect2 = _main._own_rect()
	_check(
		kb_area.position.y + kb_area.size.y <= _main.view_h + 1.0,
		"own keyboard fits on screen"
	)
	var kb0: int = _main.typed_ok
	var want_kb := String(_main._current())
	# Заглавную ищем в шифт-рядах (начала предложений в текстах).
	var kb_shift_need := want_kb != want_kb.to_lower()
	var hit_pos := Vector2(-1.0, -1.0)
	for b in K.buttons(kb_area, "ru", "ru", kb_shift_need, false):
		if String(b["s"]) == want_kb:
			hit_pos = (b["r"] as Rect2).get_center()
			break
	_check(hit_pos.x >= 0.0, "wanted letter is on the keyboard")
	if kb_shift_need:
		_main.call("_input", _tap(_kb_center(kb_area, "ru", "⇧")))
		_check(bool(_main.kb_shift), "shift arms uppercase")
	_main.call("_input", _tap(hit_pos))
	_check(int(_main.typed_ok) == kb0 + 1, "tap on own key types the letter")
	_check(_main.errors.is_empty(), "own key makes no marks")
	_main.call("_input", _tap(_kb_center(kb_area, "ru", "?123")))
	_check(String(_main.kb_layer) == "sym", "layer key switches to symbols")
	_main.call("_input", _tap(_kb_center(kb_area, "sym", "РУ")))
	_check(String(_main.kb_layer) == "ru", "symbols return to russian")
	_main.call("_input", _tap(_kb_center(kb_area, "ru", "глобус")))
	_check(String(_main.kb_layer) == "en", "globe switches to latin")
	_check(String(_main.kb_lang) == "en", "globe remembers the language")
	_main.call("_input", _tap(_kb_center(kb_area, "en", "глобус")))
	_check(String(_main.kb_layer) == "ru", "globe switches back to russian")
	# Долгое нажатие е→ё: press вводит «е», долгое release меняет на «ё».
	_check(K.long_alt("е") == "ё", "long e gives yo")
	_check(K.long_alt("ь") == "ъ", "long soft gives hard")
	_check(K.long_alt("Е") == "Ё", "long shift works too")
	_check(K.long_alt("а") == "", "plain letters have no long pair")
	_main.call("_input", _tap(_kb_center(kb_area, "ru", "е")))
	var sum_before: int = int(_main.typed_ok) + int(_main.typed_bad)
	_main._lp_t0 = Time.get_ticks_msec() - 600
	_main.call("_input", _up(_kb_center(kb_area, "ru", "е")))
	_check(String(_main._lp_act) == "", "release closes the long cycle")
	_check(
		int(_main.typed_ok) + int(_main.typed_bad) == sum_before + 1,
		"long release swaps the letter (erase is free, type counts)"
	)
	# Короткое отпускание ничего не меняет.
	_main.call("_input", _tap(_kb_center(kb_area, "ru", "е")))
	var sum_short: int = int(_main.typed_ok) + int(_main.typed_bad)
	_main.call("_input", _up(_kb_center(kb_area, "ru", "е")))
	_check(
		int(_main.typed_ok) + int(_main.typed_bad) == sum_short,
		"short release changes nothing"
	)
	# Стереть своей кнопкой.
	_main.call("_input", _tap(_kb_center(kb_area, "ru", "←")))
	# Модалка: клавиатуры нет (ввод не нужен), тапы листают дальше.
	_main._finish(true)
	_main._relayout()
	_check(not _main._own_shown(), "no own keyboard on the modal")
	_touch(false)
	_main._relayout()
	_check(not _main._own_shown(), "no own keyboard on desktop")
	_main._new_level()

	# --- Раскладка уезжает вверх от клавиатуры. ---
	# В headless вьюпорт крошечный (64×64), поэтому сначала ставим
	# реалистичный размер окна, иначе пол эффективной высоты всё скроет.
	root.size = Vector2i(1100, 650)
	# Своя клавиатура занимает низ: раскладка едет от остатка.
	# В headless-десктопе её нет (kb_h=0) — включаем сенсорный режим.
	_touch(true)
	root.size = Vector2i(1100, 650)
	_main._relayout()
	var hy1: float = _main.hud_label.position.y
	var k1: float = _main.k
	_check(_main.kb_h > 0.0, "touch layout reserves keyboard height")
	_check(_main.hud_label.position.y < 650.0, "hud stays above the keyboard")
	_check(_main.k <= k1 + 0.001, "scale fits the free area")
	_check(
		_main.card_p.position.y + _main.card_p.size.y <= _main.view_h - _main.kb_h + 1.0,
		"text card stays above the keyboard"
	)
	_touch(false)
	_main._relayout()
	_check(_main.kb_h == 0.0, "desktop layout has no keyboard height")

	# --- Галка системной клавиатуры: своя прячется, системный путь
	# (показ/замер/пере-показ) работает, борьба с автозаменой — comp-буфер.
	S.set_sys_kb(true)
	_main._relayout()
	_check(not _main._own_shown(), "system keyboard hides the own one")
	_main.view_w = 2000.0
	_main.view_h = 1000.0
	_check(not _main._kb_want(), "no system keyboard in landscape game")
	_main.view_w = 1000.0
	_main.view_h = 2000.0
	_check(_main._kb_want(), "system keyboard in portrait game")
	var rs: Callable = _main.kb_need_reshow
	_check(rs.call(true, true, 0.0, 4.0, false, false), "reshow when wanted, shown, flat, expired")
	_check(not rs.call(true, true, 0.0, 0.5, false, false), "no reshow while gliding in")
	_check(not rs.call(true, true, 120.0, 9.0, true, false), "no reshow when visible")
	_check(not rs.call(false, true, 0.0, 9.0, false, false), "no reshow when not wanted")
	_check(not rs.call(true, false, 0.0, 9.0, false, false), "initial show is a separate path")
	_check(not rs.call(true, true, 0.0, 9.0, true, false), "no reshow after user dismissed")
	_check(not rs.call(true, true, 0.0, 9.0, false, true), "reshow is one-shot")
	S.set_sys_kb(false)
	_main._relayout()

	# --- Политика клавиатуры: своя видна в партии везде. ---
	# В альбоме в игре только внешняя клавиатура, системную зовёт тап
	# по рабочей области. Чистая функция от view и меню (тут меню нет).
	_touch(true)
	_main.view_w = 2000.0
	_main.view_h = 1000.0
	_main._relayout()
	_check(_main._own_shown(), "own keyboard shows in landscape too")
	_main.view_w = 1000.0
	_main.view_h = 2000.0
	_main._relayout()
	_check(_main._own_shown(), "own keyboard shows in portrait")
	_touch(false)
	# Ручной вызов тапом держит клавиатуру и в альбоме: без флага
	# _sync_keyboard прятал её на следующем кадре.
	_main.view_w = 2000.0
	_main.view_h = 1000.0
	_main._new_level()
	_main.view_w = 1100.0
	_main.view_h = 650.0

	# --- Разбивка строк под узкий экран: слова целы, символы не теряются.
	# Пробел на месте разрыва убираем: он невидим, а игра ждёт нажатия
	# (жалоба автора: на телефоне уровень не проходился). Склейка кусков
	# сравнивается без пробелов. Массивы типизированные: нетипизированный
	# литерал в Array[String]-параметр 4.3 не принимает (молча error).
	var fl: Callable = BB.fit_lines
	var raw1: Array[String] = ["мама мыла раму", "папа"]
	var fit1: Array = fl.call(raw1, 10)
	_check(fit1 == ["мама мыла", "раму", "папа"], "long line wraps by words")
	_check(
		"".join(fit1).replace(" ", "") == "мамамыларамупапа",
		"wrap loses no characters"
	)
	var raw2: Array[String] = ["а б в"]
	_check(
		fl.call(raw2, 10) == ["а б в"], "short lines untouched"
	)
	var raw3: Array[String] = ["раз два три"]
	var fit2: Array = fl.call(raw3, 7)
	_check(fit2 == ["раз два", "три"], "wrap point is exact")
	_check(
		fit2[0].right(1) != " ", "no invisible space at the wrap point"
	)
	var raw4: Array[String] = ["супердлинноеслово", "а"]
	_check(
		fl.call(raw4, 5)[0].length() == 5,
		"monster word is hard-split"
	)

	# --- Скролл длинного текста: окно едет за курсором, уехавшие прячем.
	# Карточка — окно, а не весь текст. Самосогласовано через _vis_lines.
	# kb_h сбрасываем релэутом (своя клавиатура из прошлых частей).
	root.size = Vector2i(1100, 650)
	_main._relayout()
	var six: Array[String] = ["раз", "два", "три", "четыре", "пять", "шесть"]
	_main.display_lines = six
	_main.cursor_line = 5
	_main.cursor_pos = 0
	_main._layout_text_lines()
	_main._layout_card()
	var vis: int = _main._vis_lines()
	_check(vis >= 2 and vis < 6, "window smaller than the text")
	for i in 6:
		_check(
			_main.text_labels[i].visible == (i >= 6 - vis),
			"visibility follows the window"
		)
	_check(
		_main.scroll_y == float(6 - vis) * _main.line_h,
		"scroll offset is exact"
	)
	_check(
		_main.card_p.size.y < 6.0 * _main.line_h + 40.0 * _main.k,
		"card is a window, not the whole text"
	)

	# --- Тач и мышь в игре: кнопка игроков открывает меню, а дальше
	# с модалки — тап по любому месту рабочей области (кнопки «Дальше»
	# больше нет). Тап по звезде только объясняет балл, уровень
	# при этом не начинается.
	_main.call("_input", _tap(_main._players_rect.get_center()))
	_check(_main.menu_open, "players button opens the menu")
	_check(
		_main.menu.process_mode == Node.PROCESS_MODE_INHERIT,
		"open menu runs its process"
	)
	_main._close_menu()
	_check(
		_main.menu.process_mode == Node.PROCESS_MODE_DISABLED,
		"hidden menu process is disabled"
	)
	_main._new_level()
	_main._finish(true)
	_check(_main.state == "won", "setup: level won")
	_main._relayout()
	_main.call("_input", _tap(_main._star_center(2)))
	_check(_main._star_tip == 3, "star tap explains the score")
	_check(_main.state == "won", "star tap does not start a new level")
	# Наведение мыши на первую звезду меняет подсказку без клика.
	# Каждая звезда даёт СВОЮ подсказку (зоны — по глифам строки,
	# а не третями лейбла: иначе боковые недостижимы).
	for si in 3:
		var sme := InputEventMouseMotion.new()
		sme.position = _main._star_center(si)
		_main.call("_input", sme)
		_check(_main._star_tip == si + 1, "star %d has its own hint" % (si + 1))
	_main.call("_input", _tap(Rect2(_main.card_p.position, _main.card_p.size).get_center()))
	_check(_main.state == "playing", "tap on the work area starts a new level")
	_check(
		_main.cursor_line == 0 and _main.cursor_pos == 0,
		"new level starts at the beginning"
	)
	# Тап по рабочей области вызывает клавиатуру (автовызов вместо кнопки
	# тексту). Своя клавиатура всегда видна в партии — вызывать нечего.
	# тексту). Мобильная ветка — только с _force_touch (в headless иначе
	# не проверить).
	_main._finish(true)
	_check(_main.state == "won", "setup: level won again")
	# Слои: модалка принадлежит игре — с открытым меню гаснет,
	# с закрытым возвращается (партия всё ещё выиграна).
	_check(_main.over_p.visible, "modal is up before the menu opens")
	_main._open_menu()
	_check(not _main.over_p.visible, "modal hides with the open menu")
	_check(not _main.overlay_label.visible, "modal label hides with the menu")
	_main._close_menu()
	_check(_main.over_p.visible, "modal returns when the menu closes")
	# Своя клавиатура в партии видна всегда — вызывать тапом нечего:
	# тап по карточке партию не трогает.
	_main._new_level()
	_touch(true)
	root.size = Vector2i(1100, 650)
	_main._relayout()
	_main.call("_input", _tap(Rect2(_main.card_p.position, _main.card_p.size).get_center()))
	_check(_main._own_shown(), "own keyboard stays up while playing")
	_check(_main.state == "playing", "work area tap does not disturb playing")
	_touch(false)
	_main._relayout()
	# Полые звёзды: недобранный балл виден (2 из 3).
	_main._new_level()
	_main.typed_ok = 94
	_main.typed_bad = 6
	_main._finish(true)
	var stars_line: String = _main.overlay_label.text.split("\n")[0]
	_check(stars_line == "★★☆", "missing star is hollow")
	# Дальше по тесту идёт ввод букв — вернуть партию.
	_main._new_level()
	# Модалку листают только видимые символы и Enter; служебные нет.
	_main._finish(true)
	_check(_main.state == "won", "setup: won for key filtering")
	for kc in [KEY_CTRL, KEY_ALT, KEY_SHIFT, KEY_TAB, KEY_BACKSPACE, KEY_DELETE, KEY_UP, KEY_F1]:
		_main.call("_unhandled_key_input", _key(kc))
		_check(_main.state == "won", "aux key does not advance past the modal")
	_main.call("_unhandled_key_input", _softkey(32))
	_check(_main.state == "playing", "space advances past the modal")

	# --- Бейдж, заголовок, склонения, десктоп-кнопка (п.2 автора). ---
	_main.difficulty = 2
	_main.wins_in_row = 2
	_check(_main._badge_text() == "УР 2 · 2/3", "badge shows level and progress")
	_main.profile_name = "Петя"
	_check(_main._title_text() == "Петя", "title shows the player name")
	_main.profile_name = S.GUEST
	_check(_main._title_text() == "гость", "guest is titled as guest")
	_check(_main._plural(1, "знак", "знака", "знаков") == "знак", "plural one")
	_check(_main._plural(3, "знак", "знака", "знаков") == "знака", "plural few")
	_check(_main._plural(12, "знак", "знака", "знаков") == "знаков", "plural many")
	_check(_main._plural(21, "ошибка", "ошибки", "ошибок") == "ошибка", "plural 21")
	_check(_main._plural(0, "ошибка", "ошибки", "ошибок") == "ошибок", "plural zero")
	_check(_main._is_desktop(), "headless counts as desktop")
	_check(_main._players_hint() == "Меню (F2)", "desktop hints the menu key")
	# Подсказка видна только по наведению, а не постоянно.
	var mmin := InputEventMouseMotion.new()
	mmin.position = _main._players_rect.get_center()
	_main.call("_input", mmin)
	_check(_main._players_hover, "hover arms the menu hint")
	var mmout := InputEventMouseMotion.new()
	mmout.position = Vector2.ZERO
	_main.call("_input", mmout)
	_check(not _main._players_hover, "hover away hides the menu hint")

	# --- CapsLock и подсказка-«кнопка» (п.6): строгий режим. ---
	_main.grace_t = 0.0
	_main.cursor_line = 0
	_main.cursor_pos = 0
	_main.errors.clear()
	_main._caps_warn = false
	# Детектор чистой функцией: есть регистр — судим, нет — молчим.
	_main._caps_check(_hardkey(KEY_A, "А".unicode_at(0), false))
	_check(_main._caps_warn, "uppercase without shift arms the caps warning")
	_main._caps_warn = false
	_main._caps_check(_hardkey(KEY_A, "а".unicode_at(0), false))
	_check(not _main._caps_warn, "lowercase without shift is fine")
	_main._caps_warn = false
	_main._caps_check(_hardkey(KEY_A, "А".unicode_at(0), true))
	_check(not _main._caps_warn, "uppercase with shift is fine")
	_main._caps_warn = false
	_main._caps_check(_hardkey(KEY_5, "5".unicode_at(0), false))
	_check(not _main._caps_warn, "digits have no case to police")
	# Тот же путь, что у игрока: буква пришла через ввод, не напрямую.
	var exp_c: String = _main._current()
	var wrong_up := "Ы" if exp_c != "Ы" else "Ж"
	_main._unhandled_key_input(_hardkey(KEY_A, wrong_up.unicode_at(0), false))
	_check(_main._caps_warn, "game input path arms the caps warning")
	_check(
		_main._hint_text() == "Выключи CapsLock!",
		"caps warning beats the erase hint"
	)
	# Верная буква гасит предупреждение: регистр сошёлся.
	_main._type_char(_main._current())
	_check(not _main._caps_warn, "correct letter clears the caps warning")
	# Новый уровень сбрасывает всё прошлое.
	_main._caps_warn = true
	_main._new_level()
	_check(not _main._caps_warn, "new level clears the caps warning")
	# Заглавная под курсором: подсказка парой «Shift + буква», обе — кнопками.
	var up_l := -1
	var up_p := -1
	for li in _main.display_lines.size():
		var ln: String = _main.display_lines[li]
		for pi in ln.length():
			var cc: String = ln.substr(pi, 1)
			if cc == cc.to_upper() and cc.to_lower() != cc.to_upper():
				up_l = li
				up_p = pi
				break
		if up_l >= 0:
			break
	_check(up_l >= 0, "level has an uppercase letter to hint")
	if up_l >= 0:
		_main.errors.clear()
		_main._caps_warn = false
		_main.cursor_line = up_l
		_main.cursor_pos = up_p
		_check(
			_main._hint_text() == "Жми: [Shift] + [" + _main._current() + "]",
			"uppercase hint is shift plus the letter"
		)
	# Строчная под курсором: одна кнопка, и строгий режим показывает
	# букву как есть (регистр важен), не зеркалит в верхний.
	_main.errors.clear()
	_main._caps_warn = false
	_main._new_level()
	var low_l := -1
	var low_p := -1
	for li2 in _main.display_lines.size():
		var ln2: String = _main.display_lines[li2]
		for pi2 in ln2.length():
			var cc2: String = ln2.substr(pi2, 1)
			if cc2 == cc2.to_lower() and cc2.to_upper() != cc2.to_lower():
				low_l = li2
				low_p = pi2
				break
		if low_l >= 0:
			break
	_check(low_l >= 0, "level has a lowercase letter to hint")
	if low_l >= 0:
		_main.cursor_line = low_l
		_main.cursor_pos = low_p
		_check(
			_main._hint_text() == "Жми: [" + _main._current() + "]",
			"lowercase hint keeps its case in strict mode"
		)

	# --- Нeстрогая ё: е засчитывается за ё и обратно. ---
	_main._new_level()
	_main.grace_t = 0.0
	_main.all_keys_override = 0
	_main.profile_all_keys = false
	_main.profile_yo = false
	_main.active = {"е": true, "ё": true, "ж": true, " ": true}
	var yo1: Array[String] = ["ёж"]
	_main.display_lines = yo1
	_main.cursor_line = 0
	_main.cursor_pos = 0
	_main.errors.clear()
	_main._type_char("е")
	_check(
		_main.cursor_pos == 1 and _main.errors.is_empty(),
		"lenient yo accepts е for ё"
	)
	# И обратно: ё за е.
	_main._new_level()
	_main.grace_t = 0.0
	_main.all_keys_override = 0
	_main.profile_all_keys = false
	_main.profile_yo = false
	_main.active = {"е": true, "ё": true, "ж": true, " ": true}
	var yo2: Array[String] = ["еж"]
	_main.display_lines = yo2
	_main.cursor_line = 0
	_main.cursor_pos = 0
	_main.errors.clear()
	_main._type_char("ё")
	_check(
		_main.cursor_pos == 1 and _main.errors.is_empty(),
		"lenient yo accepts ё for е"
	)
	# Строгая (по умолчанию): е за ё не идёт.
	_main._new_level()
	_main.grace_t = 0.0
	_main.all_keys_override = 0
	_main.profile_all_keys = false
	_main.profile_yo = true
	_main.active = {"е": true, "ё": true, "ж": true, " ": true}
	var yo4: Array[String] = ["ёж"]
	_main.display_lines = yo4
	_main.cursor_line = 0
	_main.cursor_pos = 0
	_main.errors.clear()
	_main._type_char("е")
	_check(
		not _main.errors.is_empty(),
		"strict yo rejects е for ё"
	)
	# Строгий регистр + нестрогая ё: ортогональны (е за ё идёт,
	# но регистр всё равно важен).
	_main._new_level()
	_main.grace_t = 0.0
	_main.all_keys_override = 1
	_main.profile_all_keys = true
	_main.profile_yo = false
	_main.active = {"е": true, "Ё": true, " ": true}
	var yo3: Array[String] = ["Ё"]
	_main.display_lines = yo3
	_main.cursor_line = 0
	_main.cursor_pos = 0
	_main.errors.clear()
	_main._type_char("е")
	_check(
		_main.errors.is_empty(),
		"strict case still accepts е for ё when yo is lenient"
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


## Событие с системной клавиатуры Android: кода клавиши нет, только символ.
func _softkey(code: int) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.unicode = code
	ev.pressed = true
	return ev


## Клавиша системной клавиатуры со словарём: keycode неизвестен
## (Яндекс шлёт KEY_UNKNOWN, Gboard — KEY_NONE), только unicode.
func _unknownkey(code: int) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = KEY_UNKNOWN
	ev.unicode = code
	ev.pressed = true
	return ev


## Клавиша по коду (без символа): модификаторы, стрелки, F-клавиши.
func _key(code: int) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.pressed = true
	return ev


## Событие как от IME с словарём: keycode KEY_UNKNOWN, символ в unicode
## (так шлёт Яндекс — из-за этого буквы копятся в буфере).
func _soft_key(ch: String) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = KEY_UNKNOWN
	ev.unicode = ch.unicode_at(0)
	ev.pressed = true
	return ev


## Пробел с настоящим keycode — как с экранной клавиатуры (Яндекс шлёт
## его не с KEY_UNKNOWN, и раньше он перепрыгивал буфер).
func _space_key() -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = KEY_SPACE
	ev.unicode = 32
	ev.pressed = true
	return ev


## Событие с физической клавиатуры: код клавиши, готовый символ и шифт.
func _hardkey(code: int, uni: int, shift := false) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.unicode = uni
	ev.shift_pressed = shift
	ev.pressed = true
	return ev


## Клик мыши с координатами.
## Центр клавиши со знаком на своей клавиатуре (для тапов в тестах).
func _kb_center(area: Rect2, layer: String, label: String) -> Vector2:
	for b in K.buttons(area, layer, "ru", false, false):
		if String(b["s"]) == label:
			return (b["r"] as Rect2).get_center()
	return Vector2(-1.0, -1.0)


## Сенсорный режим (своя клавиатура) — игре и меню сразу.
func _touch(on: bool) -> void:
	_main._force_touch = on
	Ui.force_touch = on


## Отпускание кнопки мыши (долгие нажатия своей клавиатуры).
func _up(pos: Vector2) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = false
	ev.position = pos
	return ev


func _tap(pos: Vector2) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = pos
	return ev


## Первая не-пробельная буква строки 0: с неё можно запустить автопропуск
## (пробелы активны всегда, на них пропуск останавливается сам).
## Первая активная (не серая) клетка первой строки.
func _first_active() -> int:
	for i in _main.display_lines[0].length():
		if _main._is_active(_main.display_lines[0].substr(i, 1)):
			return i
	return 0


func _first_grey() -> int:
	var l0: String = _main.display_lines[0]
	for i in l0.length():
		if l0.substr(i, 1) != " ":
			return i
	return 0
