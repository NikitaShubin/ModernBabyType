extends SceneTree
## Детерминированный тест геймплея: ввод, кумулятивный откат,
## Backspace (стереть метку / починить впереди / откат назад, упор в
## начало текста, откат по серым пропускам), подсказка, ёж на строку выше.
## Запуск: godot --headless --path game --script res://tests/logic_test.gd
## Код выхода 0 — всё сошлось.

const BB := preload("res://scripts/balance.gd")
const S := preload("res://scripts/save.gd")

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
	_check(_main._hint_text() == "Жми: [⌫] Стереть", "hint shows how to erase")
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
	_check(_main.errors.is_empty(), "unicode backspace erases the mark")
	_check(_main.cursor_pos == pu, "unicode backspace steps onto the cell")
	_main._unhandled_key_input(_softkey(13))
	_check(_main.errors.is_empty(), "unicode enter is not typed as a letter")
	_check(_main.cursor_pos == pu, "unicode enter moves nothing while playing")
	_main.state = "won"
	_main._unhandled_key_input(_softkey(13))
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
	_check(_main.errors.has(_cell_key(1, pw)), "soft cyrillic letter leaves a mark")

	# --- Пере-показ клавиатуры: чистое решение, матрица сочетаний. ---
	# want/shown/height/elapsed/seen/reshown: показать заново — один раз
	# и только если клавиатура так и не выехала. Смахнутую пользователем
	# (была видна) не трогаем никогда.
	var rs: Callable = _main.kb_need_reshow
	_check(rs.call(true, true, 0.0, 4.0, false, false), "reshow when wanted, shown, flat, expired")
	_check(not rs.call(true, true, 0.0, 0.5, false, false), "no reshow while gliding in")
	_check(not rs.call(true, true, 120.0, 9.0, true, false), "no reshow when visible")
	_check(not rs.call(false, true, 0.0, 9.0, false, false), "no reshow when not wanted")
	_check(not rs.call(true, false, 0.0, 9.0, false, false), "initial show is a separate path")
	_check(not rs.call(true, true, 0.0, 9.0, true, false), "no reshow after user dismissed")
	_check(not rs.call(true, true, 0.0, 9.0, false, true), "reshow is one-shot")

	# --- Раскладка уезжает вверх от клавиатуры. ---
	# В headless вьюпорт крошечный (64×64), поэтому сначала ставим
	# реалистичный размер окна, иначе пол эффективной высоты всё скроет.
	root.size = Vector2i(1100, 650)
	_main.kb_h = 0.0
	_main._relayout()
	var hy0: float = _main.hud_label.position.y
	var k0: float = _main.k
	_main.kb_h = 300.0
	_main._relayout()
	_check(_main.hud_label.position.y < hy0, "layout moves up over the keyboard")
	_check(_main.k <= k0, "scale shrinks to fit the free area")
	_check(
		_main.card_p.position.y + _main.card_p.size.y <= _main.view_h - 300.0 + 1.0,
		"text card stays above the keyboard"
	)
	_main.kb_h = 0.0
	_main._relayout()

	# --- Политика клавиатуры: имя — всегда, партия — только портрет. ---
	# В альбоме в игре только внешняя клавиатура, системную зовём
	# кнопкой ⌨. Чистая функция от view и меню (тут меню нет).
	_main.view_w = 2000.0
	_main.view_h = 1000.0
	_check(not _main._kb_want(), "no auto keyboard in landscape game")
	_main.view_w = 1000.0
	_main.view_h = 2000.0
	_check(_main._kb_want(), "auto keyboard in portrait game")
	# Ручной вызов кнопкой ⌨ держит клавиатуру и в альбоме: без флага
	# _sync_keyboard прятал её на следующем кадре (кнопка молчала).
	_main.view_w = 2000.0
	_main.view_h = 1000.0
	_main._kb_manual = true
	_check(_main._kb_want(), "manual summon keeps keyboard in landscape")
	_main._new_level()
	_check(not _main._kb_manual, "new level clears the manual flag")
	_check(not _main._kb_want(), "landscape is quiet again after new level")
	_main.view_w = 1100.0
	_main.view_h = 650.0

	# --- Разбивка строк под узкий экран: слова целы, символы не теряются.
	# Пробел-разделитель уезжает в конец куска, поэтому склейка кусков
	# сравнивается без пробелов. Массивы типизированные: нетипизированный
	# литерал в Array[String]-параметр 4.3 не принимает (молча error).
	var fl: Callable = BB.fit_lines
	var raw1: Array[String] = ["мама мыла раму", "папа"]
	var fit1: Array = fl.call(raw1, 10)
	_check(fit1 == ["мама мыла ", "раму", "папа"], "long line wraps by words")
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
	_check(fit2 == ["раз два ", "три"], "wrap point is exact")
	var raw4: Array[String] = ["супердлинноеслово", "а"]
	_check(
		fl.call(raw4, 5)[0].length() == 5,
		"monster word is hard-split"
	)

	# --- Скролл длинного текста: окно едет за курсором, уехавшие прячем.
	# Карточка — окно, а не весь текст. Самосогласовано через _vis_lines.
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
	_main.call("_input", _tap(_main._star_cell_rect(2).get_center()))
	_check(_main._star_tip == 3, "star tap explains the score")
	_check(_main.state == "won", "star tap does not start a new level")
	# Наведение мыши на первую звезду меняет подсказку без клика.
	var mm := InputEventMouseMotion.new()
	mm.position = _main._star_cell_rect(0).get_center()
	_main.call("_input", mm)
	_check(_main._star_tip == 1, "star hover explains the score")
	_main.call("_input", _tap(Rect2(_main.card_p.position, _main.card_p.size).get_center()))
	_check(_main.state == "playing", "tap on the work area starts a new level")
	_check(
		_main.cursor_line == 0 and _main.cursor_pos == 0,
		"new level starts at the beginning"
	)
	# На десктопе кнопки ⌨ нет и тап по её месту — это тап по ≡:
	# угол принадлежит одной кнопке. Мобильная ветка ниже — только
	# с _force_touch (в headless иначе не проверить).
	_main._finish(true)
	_check(_main.state == "won", "setup: level won again")
	_main._force_touch = true
	_main._relayout()
	_main.call("_input", _tap(_main._kb_rect.get_center()))
	_check(_main._kb_manual, "kb tap summons the keyboard on touch layouts")
	_check(_main.state == "won", "kb tap does not advance past the modal")
	_main._force_touch = false
	_main._relayout()
	# Слои: модалка принадлежит игре — с открытым меню гаснет,
	# с закрытым возвращается (партия всё ещё выиграна).
	_check(_main.over_p.visible, "modal is up before the menu opens")
	_main._open_menu()
	_check(not _main.over_p.visible, "modal hides with the open menu")
	_check(not _main.overlay_label.visible, "modal label hides with the menu")
	_main._close_menu()
	_check(_main.over_p.visible, "modal returns when the menu closes")
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


## Клавиша по коду (без символа): модификаторы, стрелки, F-клавиши.
func _key(code: int) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = code
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
func _tap(pos: Vector2) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = pos
	return ev


## Первая не-пробельная буква строки 0: с неё можно запустить автопропуск
## (пробелы активны всегда, на них пропуск останавливается сам).
func _first_grey() -> int:
	var l0: String = _main.display_lines[0]
	for i in l0.length():
		if l0.substr(i, 1) != " ":
			return i
	return 0
