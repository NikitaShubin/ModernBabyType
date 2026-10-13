extends SceneTree
## Детерминированный тест геймплея: ввод, кумулятивный откат,
## Backspace (стереть метку / починить впереди / откат назад, упор в
## начало текста, откат по серым пропускам), подсказка, ёж на строку выше.
## Запуск: godot --headless --path game --script res://tests/logic_test.gd
## Код выхода 0 — всё сошлось.

const BB := preload("res://scripts/balance.gd")
const S := preload("res://scripts/save.gd")
const K := preload("res://scripts/kbd.gd")
const T := preload("res://scripts/texts.gd")

var _frame := 0
var _main: Node = null
var _failures: Array[String] = []
var _d0 := 0.0
var _ex0 := 0.0
var _hx := 0.0
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
		# Кадры погони — в реалистичном окне: в headless-умолчании 64x64
		# своя клавиатура (она видна везде, включая десктоп) даёт
		# вырожденную геометрию, и правило укола проверять не на чем.
		DisplayServer.window_set_size(Vector2i(1100, 650))
		root.size = Vector2i(1100, 650)
		_main._relayout()
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
		# На кадре укола заяц встаёт ровно в касание — никакого зазора
		# (жалоба 10.2026: «останавливается сильно до, а игре уже конец»).
		_main._new_level()
		_main.grace_t = 0.0
		_main.enemy_cps = 0.0
		_main.cursor_line = 1
		_main.cursor_pos = 3
		_main.hedge_active = true
		_main.enemy_line = 1
		_main.enemy_x = _main.margin + 3.0 * _main.char_w
	elif _frame == 74:
		_check(_main.state == "lost", "hare jumping back onto the hedge is a prick")
		_check(absf(_main.hero_r.x - (_main.enemy_x + _main._hedge_half())) < 0.5,
			"hare exactly at contact, no shortfall gap")
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
		_text_coverage()
		_text_fragments()
		_marker_linear()
		_legend_roundtrip()
		_layout_positions()
		_report()
		return true
	return false


## Полоса детекции укола на одной строке (в символах оси).
func _band() -> float:
	return _main._touch_chars() + _main.CONTACT_SLACK


## Каждый знак из текстов уровней обязан набираться с доски: прямо
## клавишей (с учётом шифта) или шифтом с другой. Иначе игра попросит
## то, что нечем нажать (слой ?123 убит, запасного пути нет).
func _text_coverage() -> void:
	# Прямо клавишей, заглавной через шифт или знаком через шифт
	# (Shift+6 даёт «:», Shift+. — запятую).
	var direct := {}
	# Всё, что вообще вводится доской: обе раскладки, оба состояния
	# шифта. Раньше здесь считали только «цифра + один знак», а на
	# клавише знаков больше трёх (требование автора 10.2026).
	for b in K.buttons(Rect2(0, 0, 1200, 500), false):
		for lang in ["ru", "en"]:
			for sh in [false, true]:
				var out := K.press_out(String(b["s"]), lang, sh)
				if out != "":
					direct[out] = true
	direct[" "] = true
	var missing := {}
	var dir := DirAccess.open("res://texts")
	if dir != null:
		dir.list_dir_begin()
		var f := dir.get_next()
		while f != "":
			if not dir.current_is_dir() and f.ends_with(".txt"):
				var fa := FileAccess.open("res://texts/" + f, FileAccess.READ)
				if fa != null:
					while not fa.eof_reached():
						var line := fa.get_line()
						for i in line.length():
							var ch := line.substr(i, 1)
							if ch == "":
								continue
							if not direct.has(ch):
								missing[ch] = true
			f = dir.get_next()
		dir.list_dir_end()
	_check(missing.is_empty(), "untypable characters in texts: %s" % str(missing.keys()))
	# Пары двуязычных подписей (позиционное соответствие ЙЦУКЕН–QWERTY).
	_check(K.pair_of("й") == "q" and K.pair_of("q") == "й", "yo-q pair both ways")
	_check(K.pair_of("э") == "'" and K.pair_of(";") == "ж", "edge pairs")
	_check(K.pair_of("ё") == "`" and K.pair_of("5") == "", "digits have no language pair")


## Легенды доски: у клавиши бывает до четырёх знаков (требование автора
## 10.2026 — «на некоторых кнопках не 2, а 3 знака, а слева от правого
## шифта вообще 4»), и каждый напечатанный знак обязан набираться. Если
## знак напечатан, но не набирается — игра требует невозможного.
func _legend_roundtrip() -> void:
	for b in K.buttons(Rect2(0, 0, 1200, 500), false):
		var key := String(b["s"])
		for lg in K.legends(key):
			var sym := String(lg)
			_check(sym != "", "empty legend on %s" % key)
			if sym == "":
				continue
			var combo := K.combo_for(sym, "ru")
			_check(
				not combo.is_empty()
				and K.press_out(String(combo[0]), String(combo[2]), bool(combo[1])) == sym,
				"«%s» (on %s) is reachable: %s" % [sym, key, str(combo)]
			)
	# Что лежит на конкретных клавишах — настоящая раскладка.
	# Таблица /usr/share/X11/xkb/symbols/ru, «Русская»: точка и запятая —
	# на клавише слева от правого шифта, прямой и обратный слеш — на
	# ОТДЕЛЬНОЙ клавиши слева от ввода (автор 10.2026: «ты неправильно
	# разместил прямой и обратный слеши на одной кнопке»).
	_check(
		K.legends(".") == [".", ",", "/", "?"],
		"the key left of the right shift is the dot"
	)
	# Клавиша слеша во всю ширину ряда; в русской с шифтом даёт косой
	# слеш (автор 10.2026), угол — правый верхний, как у русского шифта.
	_check(
		K.legends("\\") == ["\\", "/", "\\", "|"],
		"the backslash key holds backslash, slash and bar"
	)
	_check(
		K.corner_for("\\", "/") == 1,
		"the russian slash sits top-right"
	)
	_check(K.legends("2") == ["2", "\"", "2", "@"], "digit 2 carries both layouts' signs")
	_check(K.legends("ю") == ["ю", "Ю", ".", ">"], "ю keeps its capital next to its latin dot")
	_check(
		K.legends("ё") == ["ё", "Ё", "`", "~"],
		"ё carries its own pair plus the latin backquote and tilde"
	)
	_check(
		K.legends("х") == ["х", "Х", "[", "{"] and K.legends("э") == ["э", "Э", "'", "\""],
		"keys whose latin pair is punctuation carry the us shift sign"
	)
	# Одна клавиша — две буквы: по центру та, что язык сейчас даёт.
	_check(
		K.press_out("ф", "ru", false) == "ф" and K.press_out("ф", "en", false) == "a",
		"the same key types its own letter in each layout"
	)
	_check(
		K.small_legends("ф", "ru", false) == ["a"],
		"the other layout's letter is shown small"
	)
	_check(
		K.small_legends("ф", "en", false) == ["ф"],
		"switching the language swaps which letter stands in the middle"
	)
	# На «ё» вторая раскладка — не буква, а знаки: и кавычка, и тильда
	# видны в углах (автор 10.2026: «я просил добавить ~ в ё, а не
	# удалить»).
	_check(
		K.small_legends("ё", "ru", false) == ["`", "~"],
		"the tilde on ё is visible, not just listed (%s)" % [str(K.small_legends("ё", "ru", false))]
	)
	_check(
		K.small_legends("ё", "en", false) == ["ё", "~"]
			and K.press_out("ё", "en", false) == "`",
		"in english ё itself goes small and the backquote stands in the middle (%s)"
		% [str(K.small_legends("ё", "en", false))]
	)
	_check(K.combo_for(".") == [".", false, "ru"], "the dot is its own key, no shift")
	_check(K.combo_for(",") == [".", true, "ru"], "the comma is shift on that key")
	_check(K.combo_for("\\") == ["\\", false, "ru"], "the backslash is typed without shift")
	_check(K.combo_for("?") == ["7", true, "ru"], "the question mark is shift+7")
	_check(K.combo_for(":") == ["6", true, "ru"], "the colon is shift+6")
	_check(K.combo_for("a") == ["ф", false, "en"], "latin is taught through its own key")
	# Низ доски: слева Ctrl/Win/Alt, справа от пробела — Alt и Ctrl
	# (требование автора 10.2026), знаков там больше нет.
	var bottom := K.bottom_row(false)
	var bi := bottom.find("пробел")
	# Глобус — по другую сторону пробела, слева от него только системные
	# (автор 10.2026: пробел был не по центру).
	# Глобус — между правыми Alt и Ctrl (автор 10.2026).
	_check(
		bottom[bi + 1] == "Alt" and bottom[bi + 2] == "глобус" and bottom[bi + 3] == "Ctrl",
		"the globe sits between the right alt and ctrl: %s" % [str(bottom)]
	)
	_check(
		bottom.rfind("Alt") > bi and bottom.rfind("Ctrl") > bi,
		"alt and ctrl sit to the right of space"
	)
	for gone in ["-", "\\"]:
		_check(not bottom.has(gone), "«%s» left the bottom row" % gone)


## Раскладка взята с настоящей таблицы (скомпилированная карта этой
## машины, pc+ru(winkeys)). Клавиша прямого слеша — третья в верхнем
## буквенном ряду, сразу после «ъ»; точка с запятой — последняя перед
## правым шифтом. Ни на одной клавише двух слешей быть не может
## (автор 10.2026: «ещё осталась клавиша, имеющая оба слеша»).
func _layout_positions() -> void:
	var rows := K.all_rows(false)
	# Tab — левее й, как настоящий Tab левее Q (автор 10.2026: «таб
	# находится левее q, а не ё»).
	_check(rows[1][0] == "Tab" and rows[1][1] == "й", "tab sits left of q")
	_check(rows[1][13] == "\\", "the backslash key follows х/ъ in the top letter row")
	_check(rows[1].size() == 14, "the top letter row holds tab + 12 letters + the backslash")
	# Ряд «фыва»: слева Caps, 11 букв, справа ввод (автор 10.2026:
	# «добавь кнопки таб и капс», Tab — левее цифр, Caps — левее «ф»).
	_check(rows[2].size() == 13, "the home row is caps + 11 letters + enter")
	_check(rows[2][0] == "Caps" and rows[2][12] == "↵", "caps sits left, enter right")
	# Нижний ряд одинаков в игре и в меню: справа от Alt — Ctrl. Второго
	# ввода снизу больше нет (автор 10.2026: «у тебя 2 энтера на клаве,
	# второй не к месту — правее альта должен быть контрл»).
	var rows_m := K.all_rows(true)
	for ri in 5:
		if rows[ri] != rows_m[ri]:
			_check(false, "the bottom row differs in the menu: %s vs %s" % [str(rows[ri]), str(rows_m[ri])])

	var enters := 0
	for ri2 in 5:
		enters += rows[ri2].count("↵")
	_check(enters == 1, "exactly one enter key on the whole board (%d)" % enters)
	_check(rows[0][0] == "ё", "the digit row starts with ё, no tab there")
	_check(rows[3][10] == ".", "the dot key sits left of the right shift")
	# Обратного слеша больше ни на какой клавише нет: он живёт только на
	# своей (автор 10.2026: «ещё осталась клавиша, имеющая оба слеша»).
	var with_bs := ""
	for b in K.buttons(Rect2(0, 0, 1200, 500), false):
		for lg in K.legends(String(b["s"])):
			if String(lg) == "\\":
				with_bs = String(b["s"])
	_check(with_bs == "\\", "the backslash lives only on its own key")
	_check(
		K.legends(".") == [".", ",", "/", "?"],
		"the dot key carries dot, comma, slash and question — no backslash"
	)
	# Угол у знака — дом из девяти мест (автор 10.2026: «у каждой кнопки
	# своё место… пусть 9»): латинская основа — левый верхний, кириллица —
	# правый нижний; знаки цифр и точки — строкой автора (CORNERS), «-_»
	# и «+=» — краями t/b (EDGE). Дом зависит только от самого знака.
	_check(K.corner_for("ф", "a") == 0, "the latin letter sits top-left")
	_check(K.corner_for("ф", "ф") == 2, "the cyrillic letter sits bottom-right")
	_check(K.corner_for("2", "2") == 3, "the digit keeps the bottom-left corner")
	_check(K.corner_for("2", "\"") == 2, "the russian sign keeps the bottom-right corner")
	_check(K.corner_for("2", "@") == 0, "the english sign keeps the top-left corner")
	# Ступенька — стандарт ANSI в единицах питча (автор 10.2026: «все
	# цифры … выверены относительно буквенных клавиш» и «ревизия сдвига
	# букв»). Цифры 1..0,-,= — того же размера, что буквы; «1» на полпитча
	# левее «й», «ф» на четверть правее «й», «я» на полпитча правее «ф».
	_stagger()
	# Перелёт: смена раскладки — все клавиши; щипок шифта — только знаки
	# (автор: между большой и малой буквой мягкого перехода нет).
	_check(K.animates("ф", "en", false, "ru", false), "a letter animates on a layout switch")
	_check(not K.animates("ф", "ru", false, "ru", true), "a letter does not animate on shift")
	_check(K.animates("2", "ru", false, "ru", true), "a sign animates on shift")
	_check(K.animates(".", "ru", false, "ru", true), "the dot key animates on shift")
	_check(K.animates("-", "ru", false, "ru", true), "a stacked key animates on shift")
	_check(not K.animates("ф", "", false, "ru", false), "no morph source means no animation")
	# А в английской пара знаков на буквенной клавише летит, а не скачет.
	_check(
		K.animates("х", "en", false, "en", true) and K.animates("ё", "en", false, "en", true),
		"sign pairs on letter keys animate on shift in english"
	)
	_shift_edges_static()

## Скачком меняется ТОЛЬКО буква в центре; краевые подписи стоят: ни
## положение, ни начертание не меняются (автор 10.2026). Движение через
## анимацию допускается, но меняться домами запрещено: уходящий из центра
## не занимает дом входящего в центр.
func _shift_edges_static() -> void:
	var keys: Array = []
	for rows in [K.all_rows(false), K.all_rows(true)]:
		for row in rows:
			for label in row:
				var s := String(label)
				if s.length() == 1 and not K.legends(s).is_empty() and not keys.has(s):
					keys.append(s)
	for s in keys:
		for lang in ["ru", "en"]:
			var a0 := _home_map(s, lang, false)
			var a1 := _home_map(s, lang, true)
			var act0 := String(K.press_out(s, lang, false))
			var act1 := String(K.press_out(s, lang, true))
			if act0 == act1:
				_check(
					_same_map(a0, a1),
					"%s/%s: nothing types different, yet corners moved" % [s, lang]
				)
				continue
			if not K.animates(s, lang, false, lang, true):
				# Буква: перелёта нет, центр меняется скачком — и ТОЛЬКО он.
				_check(
					_same_map(a0, a1),
					"%s/%s: only the centered letter may jump" % [s, lang]
				)
				_check(
					act1 == act0.to_upper() or act0 == act1.to_upper(),
					"%s/%s: the instant swap is a case change %s -> %s" % [s, lang, act0, act1]
				)
				continue
			# Знак: летит пара центр↔дом, остальные стоят.
			var rest0 := _home_map_minus(a0, act1)
			var rest1 := _home_map_minus(a1, act0)
			_check(
				_same_map(rest0, rest1),
				"%s/%s: only the flying pair moves" % [s, lang]
				)
			# Домами не меняются: уходящий не занимает дом входящего.
			_check(
				int(K.corner_for(s, act0)) != int(K.corner_for(s, act1)),
				"%s/%s: the movers must not swap homes" % [s, lang]
				)


## Подпись -> дом для мелких подписей клавиши в данном состоянии.
func _home_map(s: String, lang: String, shift: bool) -> Dictionary:
	var out := {}
	for v in K.small_legends(s, lang, shift):
		var t := String(v)
		out[t] = int(K.corner_for(s, t))
	return out


## Та же карта без одной подписи.
func _home_map_minus(m: Dictionary, drop: String) -> Dictionary:
	var out := {}
	for k in m.keys():
		if String(k) != drop:
			out[k] = int(m[k])
	return out


## Карты равны: те же подписи в тех же домах.
func _same_map(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for k in a.keys():
		if not b.has(k) or int(b[k]) != int(a[k]):
			return false
	return true


## Ступенька рядов — стандарт ANSI: буквы верхнего ряда на 1.5 питча
## (Tab), среднего — на 1.75 (Caps), нижнего — на 2.25 (Shift); цифры тем
## же питчем, «1» на 0.5 левее «й».
func _stagger() -> void:
	var area := Rect2(0, 0, 788, 384)
	var at := {}
	for b in K.buttons(area, false, false):
		at[String(b["s"])] = b["r"] as Rect2
	var p: float = (at["й"] as Rect2).size.x
	var step: float = p + 8.0
	for d in ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "="]:
		_check(
			is_equal_approx((at[d] as Rect2).size.x, p),
			"digit %s is not letter-sized (%.1f vs %.1f)" % [d, (at[d] as Rect2).size.x, p]
		)
	_check(
		is_equal_approx(((at["й"] as Rect2).position.x - (at["1"] as Rect2).position.x) / step, 0.5),
		"the digit sits half a pitch left of its letter"
	)
	_check(
		is_equal_approx(((at["ф"] as Rect2).position.x - (at["й"] as Rect2).position.x) / step, 0.25),
		"the home row sits a quarter pitch right of the top row"
	)
	_check(
		is_equal_approx(((at["я"] as Rect2).position.x - (at["ф"] as Rect2).position.x) / step, 0.5),
		"the bottom row sits half a pitch right of the home row"
	)


## Фрагмент уровня: 1+ целых предложений подряд на нужное число
## знаков. Начинать с середины предложения и обрывать фразу нельзя
## (автор 10.2026); объём плавно растёт со сложностью.
func _text_fragments() -> void:
	# Границы: обычные концы предложений.
	_check(
		T.split_sentences("Мама мыла раму. Папа читал газету! А кот спал?") == ["Мама мыла раму.", "Папа читал газету!", "А кот спал?"],
		"plain sentences split"
	)
	# Многоточие и ёлочки — тоже концы, кавычки висят на своём.
	_check(
		T.split_sentences("Он думал… Потом сказал: «Иди!» И ушёл.") == ["Он думал…", "Потом сказал: «Иди!»", "И ушёл."],
		"ellipsis and quotes split"
	)
	# Сокращения, инициалы, десятичные и нумерация НЕ режут: лучше
	# склеить два предложения, чем порвать фразу.
	_check(
		T.split_sentences("Пришёл т.е. Иванов, т.д. Петрова нет. Было 7.5 кг.") == ["Пришёл т.е. Иванов, т.д. Петрова нет.", "Было 7.5 кг."],
		"abbreviations do not split"
	)
	_check(
		T.split_sentences("Писал А. С. Пушкин. Читай вслух.") == ["Писал А. С. Пушкин.", "Читай вслух."],
		"initials do not split"
	)
	# Хвост без терминатора — тоже предложение (конец файла целый).
	_check(
		T.split_sentences("Начало. Хвост без точки") == ["Начало.", "Хвост без точки"],
		"tail without a terminator counts"
	)
	# Пустые строки и мусор фильтр выкидывает, файлы править не надо.
	_check(
		T.split_sentences("   \n\n  Мама.  \n") == ["Мама."],
		"whitespace-only input cleans up"
	)
	# Объём: минимум одно предложение, дальше добираем до цели.
	var two: Array[String] = ["Коротко.", "Тоже коротко."]
	_check(not T.pick_fragment(two, 5).is_empty(), "at least one sentence")
	_check(T.pick_fragment(two, 100) == two, "short pool always gives both")
	# Цель растёт со сложностью и упирается в потолок.
	_check(T.target_for(0) == 130, "base volume is about three old lines")
	_check(T.target_for(5) > T.target_for(0), "volume grows with difficulty")
	_check(T.target_for(1000) == 450, "volume caps out")
	# Целостность run: начинается с начала предложения, кончается концом.
	var pool := T.split_sentences("Раз. Два! Три? Четыре. Пять. Шесть.")
	for _i in 20:
		var got := " ".join(PackedStringArray(T.pick_fragment(pool, 15)))
		var head_ok := false
		var tail_ok := false
		for sent in pool:
			if got.begins_with(String(sent)):
				head_ok = true
			if got.ends_with(String(sent)):
				tail_ok = true
		_check(head_ok, "run starts at a boundary (%s)" % got)
		_check(tail_ok, "run ends at a boundary (%s)" % got)


## Математический контроль выделителя (автор 10.2026: «к концу
## накапливается сдвиг», а для тестов нужен математический контроль).
## Два абсолютных свойства моноширинного тракта (без накопления!):
## 1) шейпинг целой строки совпадает с замером префиксов — иначе метки
##    (шейпинг RichText) и маркер (замер префикса) разъезжаются, и ошибка
##    растёт к концу строки. Проверено вручную: 0 расхождений на 47 знаках.
## 2) шаг одинаков у любых знаков (буквы, цифра, запятая, пробел, Ё) —
##    иначе подмена шрифта на пропорциональный прошла бы тихо.
## Одиночные замеры округляются (±1 px), поэтому допуски абсолютные, а не
## наклонные: округление — не дрейф (маркер и метки меряют run'ами и
## сходятся, сверено попиксельно).
func _marker_linear() -> void:
	_main._relayout()
	var fs: int = _main.font_size
	# 2) Шаг одинаков у любых знаков.
	var probes := ["а", "м", ",", "7", "Ё", " ", "н"]
	var first_w := -1.0
	for g in probes:
		var w: float = _main.mono.get_string_size(
			String(g), HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs).x
		if first_w < 0.0:
			first_w = w
		_check(
			absf(w - first_w) <= 1.0,
			"glyph «%s» breaks the monospace step (%.1f vs %.1f)" % [String(g), w, first_w]
		)
	# 1) Шейпинг строки совпадает с замерами префиксов.
	var line := "Мама мыла раму у окна долго, папа: 7 гусей!"
	var ts := TextServerManager.get_primary_interface()
	var rid := ts.create_shaped_text(TextServer.DIRECTION_LTR)
	ts.shaped_text_add_string(rid, line, _main.mono.get_rids(), fs)
	var x := 0.0
	for g in ts.shaped_text_get_glyphs(rid):
		var d: Dictionary = g
		var pp := int(d.get("start", -1))
		if pp >= 0 and pp % 5 == 0:
			var pre: float = _main.mono.get_string_size(
				line.left(pp), HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs).x
			_check(
				absf(x - pre) <= 1.0,
				"shaping drifts from prefixes at cell %d (%.1f vs %.1f)" % [pp, x, pre]
			)
		x += float(d.get("advance", 0.0))
	ts.free_rid(rid)


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


## Какие клавиши должна подсветить клавиатура для буквы под курсором:
## пробел — своей клавишей, заглавная в строгом режиме — парой
## [Shift, буква], обычная — собой. Текстовых «Нажми К» больше нет:
## подсказка живёт на самой клавиатуре (решение 10.2026).
func _expected_keys(ch: String) -> Array:
	if ch == "":
		return []
	if ch == " ":
		return ["пробел:Л" if _main.last_hand == "П" else "пробел:П"]
	if _main._exact() and ch == ch.to_upper() and ch != ch.to_lower():
		# Шифт противоположной руки (правило быстрого набора).
		return [("ShiftR" if K.hand_of(ch) == "Л" else "Shift"), ch.to_lower()]
	return [ch]


func _run_part1() -> void:
	_check(_main.display_lines.size() == 3, "three text lines loaded")
	# Старт: курсор на активной букве (фрагмент случайный — вычисляем).
	var ch0: String = _main._current()
	_check(ch0 != "" and _main._is_active(ch0), "cursor starts on active")
	# Текстовой подсказки для буквы нет (пусто), а после простоя нужная
	# клавиша подсвечивается на самой клавиатуре.
	_check(_main._hint_text() == "", "no text hint for the letter")
	_check(_main._hint_keys().is_empty(), "no highlight before the idle delay")
	_main.press_ema = 0.6
	_main.idle_t = _main._hint_delay() + 0.5
	_check(
		_main._hint_keys() == _expected_keys(ch0),
		"the board highlights the wanted key"
	)
	_main.idle_t = 0.0
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
	_check(_main._hint_text() == "", "no text hint over the marks")
	_main.press_ema = 0.6
	_main.idle_t = _main._hint_delay() + 0.5
	_check(_main._hint_keys() == ["←"], "marks highlight the erase key")
	_main.idle_t = 0.0
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
	# Текст уровня случаен (файл и старт — randi, порядок файлов может
	# плавать между прогонами): добираем уровень, у которого в первой
	# строке хватит места под полосу. Иначе сценарий ловил бы форму
	# текста, а не механику отката.
	var tries := 0
	while tries < 8:
		_main._new_level()
		_main.active = BB.active_chars(0)
		# Влезет и полоса: первая строка длинная, а клетка сразу за
		# первой активной — не пробел (пробел активен всегда, из него
		# серую полосу не построить — ловил флаки 10.2026).
		var ll: String = _main.display_lines[0]
		var fa0 := -1
		for i in ll.length():
			if _main._is_active(ll.substr(i, 1)):
				fa0 = i
				break
		if ll.length() >= 6 and fa0 >= 0 and fa0 + 1 < ll.length() and ll.substr(fa0 + 1, 1) != " ":
			break
		tries += 1
	# Набираем первую активную букву и уходим на пассивную клетку после неё.
	var first_active := -1
	for i in _main.display_lines[0].length():
		if _main._is_active(_main.display_lines[0].substr(i, 1)):
			first_active = i
			break
	_check(first_active >= 0 and first_active + 1 < _main.display_lines[0].length()
		and _main.display_lines[0].substr(first_active + 1, 1) != " ",
		"level has room for a grey run (coverage)")
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
	# Серой полосы может не быть (все буквы активны). Строим её явно на
	# ТЕКУЩЕМ тексте: гасим буквы двух клеток за набранной. Раньше полоса
	# везлась через _new_level, а новый уровень — случайный фрагмент, и
	# сценарий ловил чужой текст вместо полосы.
	# Гасим буквы следующих двух НЕ-пробелов: пробел активен всегда.
	if grey_run == 0 and first_active >= 0:
		var hidden: Array[String] = []
		var taken := 0
		var j := first_active + 1
		while taken < 2 and j < line0.length():
			var hc := line0.substr(j, 1).to_lower()
			j += 1
			if hc == " ":
				continue
			taken += 1
			if not hidden.has(hc):
				hidden.append(hc)
		for hc in hidden:
			_main.active.erase(hc)
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
		_main._type_char(_main._current())
		_check(
			_main.typed_bad == 0 and _main.errors.is_empty(),
			"retyping after the retreat makes no mistake"
		)
	# Быстрые двойные буквы («сс», «нн»): вторая — тоже набор. Глушения
	# дублей больше нет: своей экранной клавиатуре машинные дубли
	# неоткуда взяться, а человек вправе жать быстро (решение 10.2026).
	_main.cursor_line = after_ok.x
	_main.cursor_pos = after_ok.y
	_main.hints.clear()
	var dup_ok: int = _main.typed_ok
	_main._type_char(_main._current())
	_main._type_char(_main._current())
	_check(
		_main.typed_ok == dup_ok + 2,
		"fast double letters both count"
	)
	_main.hints.clear()

	# --- ПОРЯДОК ВВОДА. Прямой ввод: активная буква, за которой идёт
	# пробел (как в «Снесла курочка» — найдём такую), набирается как
	# обычно, письмо идёт по порядку: буква принята, курсор ушёл дальше,
	# ошибок нет.
	_main._new_level()
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
		# Прямой ввод буквы — как с железной, так и со своей экранной
		# клавиатуры (в игру один путь).
		_main._type_char(letter)
		_check(
			_main.passed.has(_cell_key(0, a_at)),
			"the typed letter is counted"
		)
		_main._type_char(" ")
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
	_main._type_char(_main._current())
	_check(
		_main.typed_bad == 0 and _main.errors.is_empty(),
		"retyping after the retreat makes no mistake"
	)
	_check(
		typed_at.y > 0 or typed_at.x > 0,
		"the auto-skip had actually moved the cursor on"
	)

	# --- Прямой ввод клавиши: Backspace по unicode 8 (так приходит и
	# со своей экранной клавиатуры — заявительного кода клавиши там нет,
	# keycode считается заранее), Enter как 10/13. Без фолбэков нельзя ни
	# стереть, ни продолжить после победы, а Enter во время партии обязан
	# молчать, а не рисовать метку перевода строки.
	_main._new_level()
	_main.cursor_line = 1
	_main.cursor_pos = _safe_pos(1, 6)
	var pu: int = _main.cursor_pos
	_main._type_char("ы" if _main._current().to_lower() != "ы" else "ж")
	_check(_main.errors.has(_cell_key(1, pu)), "a typo left a mark")
	_main._unhandled_key_input(_softkey(8))
	_check(_main.errors.is_empty(), "unicode backspace erases the mark")
	_check(_main.cursor_pos == pu, "unicode backspace steps onto the cell")
	_main._unhandled_key_input(_softkey(13))
	_check(_main.errors.is_empty(), "unicode enter is not typed as a letter")
	_check(_main.cursor_pos == pu, "unicode enter moves nothing while playing")
	_main.state = "won"
	_main._unhandled_key_input(_softkey(13))
	_check(_main.state == "playing", "unicode enter continues after winning")

	# --- Раскладка уезжает вверх от клавиатуры. ---
	# В headless вьюпорт крошечный (64×64), поэтому сначала ставим
	# реалистичный размер окна, иначе пол эффективной высоты всё скроет.
	root.size = Vector2i(1100, 650)
	# Своя клавиатура занимает низ: раскладка едет от остатка. Видна
	# везде, включая десктоп: она и есть подсказка (вместо «Нажми К»).
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
	# На десктопе клавиатура тоже занимает низ: она и есть подсказка.
	_touch(false)
	_main._relayout()
	_check(_main.kb_h > 0.0, "desktop layout reserves keyboard height too")
	_check(_main._own_shown(), "desktop shows the own keyboard in game")

	# --- Политика клавиатуры: своя видна в партии везде, включая
	# десктоп и альбом. Физическая клавиатура при этом тоже печатает:
	# ввод один, путь один.
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
	# Раскладка больше не прыгает сама: замеров системы нет.
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
	_main.line_drops = []
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
		_main.press_ema = 0.6
		_main.idle_t = _main._hint_delay() + 0.5
		_check(
			_main._hint_keys() == [(("ShiftR" if K.hand_of(_main._current()) == "Л" else "Shift")), _main._current().to_lower()],
			"uppercase highlights the opposite shift plus the letter"
		)
		_main.idle_t = 0.0
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
		_main.press_ema = 0.6
		_main.idle_t = _main._hint_delay() + 0.5
		_check(
			_main._hint_keys() == [_main._current()],
			"lowercase highlights its own key"
		)
		_main.idle_t = 0.0

	# --- Нeстрогая ё: е засчитывается за ё и обратно. ---
	_main._new_level()
	_main.grace_t = 0.0
	_main.all_keys_override = 0
	_main.profile_all_keys = false
	_main.profile_yo = false
	_main.active = {"е": true, "ё": true, "ж": true, " ": true}
	var yo1: Array[String] = ["ёж"]
	_main.display_lines = yo1
	_main.line_drops = []
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
	_main.line_drops = []
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
	_main.line_drops = []
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
	_main.line_drops = []
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


## Клавиша без кода: чистый символ, как даёт своя экранная клавиатура.
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


## Клавиша без кода: чистый символ, как даёт своя экранная клавиатура
## (так шлёт Яндекс — из-за этого буквы копятся в буфере).
func _soft_key(ch: String) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = KEY_UNKNOWN
	ev.unicode = ch.unicode_at(0)
	ev.pressed = true
	return ev


## Пробел с настоящим keycode — как с экранной клавиатуры (Яндекс шлёт
## Клавиша без кода — обычный ввод без машины.
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
