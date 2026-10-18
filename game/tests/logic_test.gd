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
		# Гонка началась: разогрев пройден (17.10.2026 — ёж выезжает
		# только после первого ввода человека, сам сценарий его ждёт).
		_main.warm_done = true
		_main.hedge_active = true
		_main.enemy_line = 0
		_main.enemy_x = _main._cursor_cx() - _main.char_w * 0.5 - 10.0
	elif _frame == 6:
		_check(_main.state == "lost", "behind catch on same line")
		_check(_main._last_reason == "behind", "behind reason recorded")
		# Новый уровень, герой сразу на строке 1 → ёж выходит на строку 0.
		_main._new_level()
		_main.grace_t = 0.0
		_main.warm_done = true  # гонка пошла (разогрев, 17.10.2026)
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
		_main.warm_done = true  # гонка пошла (разогрев, 17.10.2026)
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
		_main.warm_done = true  # гонка пошла (разогрев, 17.10.2026)
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
		_main.warm_done = true  # гонка пошла (разогрев, 17.10.2026)
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
		_main.warm_done = true  # гонка пошла (разогрев, 17.10.2026)
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
		_main.warm_done = true  # гонка пошла (разогрев, 17.10.2026)
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
		_main.warm_done = true  # гонка пошла (разогрев, 17.10.2026)
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
		_main.warm_done = true  # гонка пошла (разогрев, 17.10.2026)
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
		_main.warm_done = true  # гонка пошла (разогрев, 17.10.2026)
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
		_main.warm_done = true  # гонка пошла (разогрев, 17.10.2026)
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
		_main.warm_done = true  # гонка пошла (разогрев, 17.10.2026)
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
		_main.warm_done = true  # гонка пошла (разогрев, 17.10.2026)
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
		_text_normalize()
		_text_bases()
		_text_breaks()
		_text_geometry()
		_reflow_wrap_space()
		_lin_stable()
		_marker_cells()
		_legend_roundtrip()
		_layout_positions()
		_legends_fit_homes()
		_bar_floors()
		_report()
		return true
	return false


## Нецентральная подпись влезает в свой дом (автор 18.10.2026:
## «неактивные знаки слишком большие, вылезают за границы кнопки и
## переплетаются с центральным»). Меряют не зеркало draw(), а сам
## источник рисования — _rest: его презентации в покое совпадают с
## концами перелёта, а влезание меряется зоной дома (`home_rect`).
## Кегли взяты С щедростью (верх хода draw(): лютые экраны, большие
## знаки) — влезавший должен ужиматься сам, а не краснеть.
func _legends_fit_homes() -> void:
	var mono: Font = _main.mono
	_check(mono != null, "the mono font exists for home fitting")
	if mono == null:
		return
	for area in [Rect2(0, 0, 788, 384), Rect2(0, 0, 2340, 1076), Rect2(0, 0, 560, 900)]:
		var a: Rect2 = area
		var tag := "%dx%d" % [int(a.size.x), int(a.size.y)]
		var rh := (a.size.y - 32.0) / 5.0
		var f := maxi(16, int(rh * 0.40))
		var sub := maxi(int(float(f) * 0.66), int(rh * 0.24))
		for b in K.buttons(a, false, false):
			var r: Rect2 = b["r"]
			var key := String(b["s"])
			if K.legends(key).is_empty():
				continue
			for lg in K.legends(key):
				var sym := String(lg)
				# main заведомо другой: проверяем только не-центральные
				# дома (центральная — набираемая, она с главным кеглем).
				# Сентинел многосимвольный: легенды всегда из одного
				# знака, совпасть с ним не может.
				var pr: Array = K._rest(key, r, mono, sym, "не-центр", f, sub)
				var zr: Rect2 = K.home_rect(r, key, sym)
				var ts: Vector2 = Ui.text_size(mono, sym, int(float(pr[1])))
				_check(ts.x <= zr.size.x * 0.92 + 0.5,
					"%s: «%s» on «%s» is %.1f wide in a %.1f room" % [
						tag, sym, key, ts.x, zr.size.x])
				_check(ts.y <= zr.size.y * 0.98 + 0.5,
					"%s: «%s» on «%s» is %.1f tall in a %.1f room" % [
						tag, sym, key, ts.y, zr.size.y])
				_check(float(pr[1]) >= 8.0,
					"%s: «%s» on «%s» shrunk to nothing (%.0f)" % [
						tag, sym, key, float(pr[1])])


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
	# Проверяем ровно то, что набирает игра: нормализованные предложения
	# (файлы хранят оригиналы, правит парсер — автор 10.2026). Знак без
	# клавиши — дыра в нормализации (тест падает); буква без клавиши —
	# работа фильтра (предложение пропускается, см. playable).
	var missing := {}
	for sub in ["kids", "pro"]:
		var dir := DirAccess.open("res://texts/" + sub)
		if dir == null:
			continue
		dir.list_dir_begin()
		var f := dir.get_next()
		while f != "":
			if not dir.current_is_dir() and f.ends_with(".txt"):
				for sent in T.file_sentences("res://texts/" + sub + "/" + f):
					for i in String(sent).length():
						var ch := String(sent).substr(i, 1)
						if ch == "" or ch == " " or T.is_letter_char(ch) or (ch >= "0" and ch <= "9"):
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
## Маркер стоит в клетках: центр = margin + (pos + 0.5) × char_w, где
## char_w — предельный advance в строке. Раньше центр считался замером
## префикса целой строкой, а одиночный замер давал другой шаг: целый
## против суммы расходились на ~пиксель/знак (замерено 720 против 687 на
## 60 знаках) — маркер уползал от букв с накоплением к концу строки
## (жалоба автора 13.10.2026). Теперь второго пути измерения нет:
## вёрстка, маркер, заяц и отрисовка считают одно и то же.
func _marker_cells() -> void:
	_main._relayout()
	var fs: int = _main.font_size
	var mono: Font = _main.mono
	# 1) char_w — это внутристрочный шаг на любом кегле: целый(N) ≈
	# целый(1) + (N-1)×char_w. Одиночный замер округляется наружу и для
	# шага не годится (см. комментарий в _relayout).
	var one: float = mono.get_string_size("н", HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs).x
	for n in [2, 8, 64]:
		var whole: float = mono.get_string_size(
			"н".repeat(n), HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs).x
		_check(
			absf(whole - (one + float(n - 1) * _main.char_w)) <= 1.0,
			"char_w is not the in-run advance at N=%d (whole %.1f)" % [n, whole]
		)
	for sz in [Vector2i(520, 900), Vector2i(1560, 1040)]:
		DisplayServer.window_set_size(sz)
		root.size = sz
		_main._relayout()
		var fs2: int = _main.font_size
		var one2: float = mono.get_string_size("н", HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs2).x
		var whole64: float = mono.get_string_size(
			"н".repeat(64), HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs2).x
		_check(
			absf(whole64 - (one2 + 63.0 * _main.char_w)) <= 1.0,
			"char_w is not the in-run advance at %dx%d (whole %.1f, char %.2f)"
				% [sz.x, sz.y, whole64, _main.char_w]
		)
	DisplayServer.window_set_size(Vector2i(1100, 650))
	root.size = Vector2i(1100, 650)
	_main._relayout()
	# 2) Центр маркера — ровно клетка, на нескольких позициях.
	_main.display_lines = ["мама мыла раму"] as Array[String]
	_main.line_drops = []
	var hard: Array[bool] = [true]
	_main.line_hard = hard
	var noglue: Array[bool] = [false]
	_main.line_glue = noglue
	_main._reindex_lines()
	for p in [0, 1, 7, 13]:
		_main.cursor_line = 0
		_main.cursor_pos = p
		_main.state = "playing"
		_check(
			absf(_main._cursor_cx() - (_main.margin + (float(p) + 0.5) * _main.char_w)) <= 0.001,
			"marker center is not on its cell at %d (%.2f)" % [p, _main._cursor_cx()]
		)
		var r: Rect2 = _main._cursor_rect()
		_check(
			absf(r.position.x - (_main.margin + float(p) * _main.char_w - 2.0 * _main.k)) <= 0.001
				and absf(r.size.x - (_main.char_w + 4.0 * _main.k)) <= 0.001,
			"marker box is not on its cell at %d (%s)" % [p, str(r)]
		)


## Базы текстов: детская и взрослая классика. Про-аккаунт берёт
## взрослые тексты тем же тумблером «Про» (автор 10.2026: «не вижу
## взрослых текстов в своём про аккаунте»).
## Перенос строки ИСХОДНИКА — там игра ждёт ↵, обычный перенос едет сам
## (автор 13.10.2026: «где в оригинальном файле был перенос строки —
## диалоги, концы абзацев, стихи»). Признак рождается в Texts (конец
## физической строки файла) и едет по вёрстке в balance.gd.
func _text_breaks() -> void:
	var units := T.file_units("res://texts/kids/krylov_vorona_i_lisitsa.txt")
	var texts: Array = units["texts"]
	var hard: Array = units["hard"]
	_check(texts.size() == hard.size() and not texts.is_empty(), "units and flags must pair up")
	# У басни каждая строка — строка стиха, значит признак есть и он
	# встречается чаще, чем раз в пять строк.
	var n := 0
	for f in hard:
		if bool(f):
			n += 1
	_check(n >= 1, "no source line breaks in a fable")
	_check(
		T.file_sentences("res://texts/kids/krylov_vorona_i_lisitsa.txt").size() == texts.size(),
		"file_sentences must match file_units"
	)
	# В прозе перенос строки — конец абзаца, то есть подряд идущие
	# предложения внутри абзаца признака не имеют.
	var chekhov := T.file_units("res://texts/pro/chehov_tolstyi_i_tonkii.txt")
	var soft := 0
	for f in chekhov["hard"]:
		if not bool(f):
			soft += 1
	_check(soft > 0, "every prose sentence claimed a line break")
	# Вёрстка: предложения внутри абзаца СКЛЕИВАЮТСЯ в сплошной текст,
	# как в Word (автор 13.10.2026: переносы «не надо ни исключать, ни
	# добавлять»). Видимый разрыв — либо перенос по ширине (мягкий,
	# курсор едет сам), либо конец абзаца (жёсткий, ждёт ↵).
	var m := BB.fit_marked(
		["Он пошёл домой.", "Потом вернулся."], 40, [false, true]
	)
	_check(
		(m["lines"] as Array) == ["Он пошёл домой. Потом вернулся."],
		"one paragraph flows as one wrapped line: %s" % str(m["lines"])
	)
	_check(
		(m["hard"] as Array) == [true],
		"the paragraph end asks for enter: %s" % str(m["hard"])
	)
	var both := BB.fit_marked(["Он пошёл домой.", "Потом вернулся."], 40, [true, true])
	_check(
		(both["lines"] as Array) == ["Он пошёл домой.", "Потом вернулся."],
		"source line breaks are kept, not merged: %s" % str(both["lines"])
	)
	_check(
		(both["hard"] as Array) == [true, true],
		"both lines end where the source breaks: %s" % str(both["hard"])
	)
	# Без флагов каждая единица — свой абзац: прямые вызовы со строками
	# файла ничего не склеивают.
	var plain := BB.fit_marked(["Он пошёл домой.", "Потом вернулся."], 40)
	_check(
		(plain["lines"] as Array) == ["Он пошёл домой.", "Потом вернулся."],
		"units without flags stay separate: %s" % str(plain["lines"])
	)
	var narrow := BB.fit_marked(
		["Ёжик ел ёжика и ёл ёршик.", "А потом спал."], 12, [false, true]
	)
	var nl: Array = narrow["lines"]
	var nh: Array = narrow["hard"]
	# Один абзац «Ёжик ел ёжика и ёл ёршик. А потом спал.» режется по
	# словам: куски мягкие и кончаются пробелом-КЛЕТКОЙ (автор 14.10.2026:
	# пробел на переносе набирается, как в редакторе), последний кончает
	# абзац и пробелом не кончается.
	_check(nl.size() > 2, "the narrow layout must split the paragraph")
	_check(nh.size() == nl.size(), "flags must follow the lines")
	for i in nh.size() - 1:
		_check(
			not bool(nh[i]),
			"a width wrap must stay soft (line %d «%s»)" % [i, nl[i]]
		)
		_check(
			String(nl[i]).ends_with(" ") and not String(nl[i]).ends_with("  "),
			"a soft row must end with exactly one typed space (line %d «%s»)" % [i, nl[i]]
		)
	_check(bool(nh[nh.size() - 1]), "the paragraph keeps the source break on its last line")
	_check(
		not String(nl[nl.size() - 1]).ends_with(" "),
		"the paragraph end has no trailing space: «%s»" % nl[nl.size() - 1]
	)
	var letters := ""
	for piece in nl:
		letters += String(piece)
	_check(
		letters == "Ёжик ел ёжика и ёл ёршик. А потом спал.",
		"wrapping must not lose characters: %s" % letters
	)
	# reflow склеивает мягкие строки обратно в абзац: сузили-расширили —
	# вернулись к тем же строкам, курсор на той же букве.
	var wide := BB.fit_marked(["Ёжик ел.", "Ёл ёршик.", "А потом спал."], 40, [false, false, true])
	var rf := BB.reflow(wide["lines"] as Array[String], 0, 3, 12, wide["drops"], wide["hard"])
	_check(
		(rf["lines"] as Array).size() > 1,
		"reflow must rewrap rows that no longer fit: %s" % str(rf["lines"])
	)
	_check(
		int(rf["line"]) == 0 and int(rf["pos"]) == 3,
		"the cursor letter must survive the rewrap (got %d:%d)" % [int(rf["line"]), int(rf["pos"])]
	)
	var back := BB.reflow(rf["lines"] as Array[String], 0, 0, 40, rf["drops"], rf["hard"])
	_check(
		(back["lines"] as Array) == (wide["lines"] as Array),
		"widening back must restore the rows: %s" % str(back["lines"])
	)
	# Фрагмент уровня несёт те же признаки, разрывов по ширине в нём нет.
	for base in ["kids", "pro"]:
		var frag := T.load_fragment(1, base)
		var ts: Array = frag["texts"]
		var fs: Array = frag["hard"]
		_check(
			ts.size() == fs.size() and not ts.is_empty() and frag.has("drops"),
			"%s fragment must carry lines, breaks and drops (%d/%d)"
				% [base, ts.size(), fs.size()]
		)
	# ↵ должен встречаться: в каждой базе есть файлы, где перенос строки
	# есть (диалоги, стихи, абзацы). Проверка по корпусу, а не по одному
	# случайному фрагменту — иначе она мигала бы.
	for sub in ["kids", "pro"]:
		var breaks := 0
		for path in T.list_files(sub):
			for f4 in (T.file_units(String(path))["hard"] as Array):
				if bool(f4):
					breaks += 1
		_check(breaks > 0, "%s: no source line breaks in the whole base" % sub)


## Геометрия строк и маркера — числом, а не глазом (автор 13.10.2026:
## «строка выходит за рамку» и «выделитель захватывает конец одной
## строки и начало другой»). На четырёх ширинах — от узкого телефона до
## широкого десктопа — каждая строка обязана влезть в карточку (в знаках
## И в пикселях), а рамка маркера — лежать внутри своей строки и
## карточки в трёх точках строки и в ожидании переноса.
func _text_geometry() -> void:
	var sizes := [Vector2i(520, 900), Vector2i(820, 1180), Vector2i(1560, 1040), Vector2i(2000, 1200)]
	for sz in sizes:
		DisplayServer.window_set_size(sz)
		root.size = sz
		_main._relayout()
		for d in [0, 3, 7]:
			_main.all_keys_override = 1
			_main.difficulty = d
			_main._new_level()
			_geo_level("geo %dx%d d%d" % [sz.x, sz.y, d])
	# Окно обратно в реалистичное для остальных частей.
	DisplayServer.window_set_size(Vector2i(1100, 650))
	root.size = Vector2i(1100, 650)
	_main._relayout()


func _geo_level(tag: String) -> void:
	_check(not _main.display_lines.is_empty(), "%s: no lines" % tag)
	print("ГЕО %s: margin=%.1f char_w=%.1f max=%d rows=%d kb_h=%.0f" % [
		tag, _main.margin, _main.char_w, _main._max_chars(),
		_main.display_lines.size(), _main.kb_h])
	_geo_fill(tag)


## Заполнение карточки (автор 14.10.2026: «текст точно мелкий, а место
## пустует — и в горизонтальной, и в вертикальной»). Проверяем числами:
##   — кегль никогда не меньше прежних 36k и не крупнее 72k;
##   — интерлиньяж в границах 1.8..2.4 высоты глифа: ниже — ёж впритык
##     к чернилам, выше — «слишком большой межстрочный интервал»;
##   — видимые строки занимают свободную высоту без пустой полосы
##     снизу (остаток меньше одной строки).
func _geo_fill(tag: String) -> void:
	var k: float = _main.k
	var glyph: float = _main.mono.get_height(_main.font_size)
	_check(
		_main.font_size >= int(36.0 * k) and _main.font_size <= int(72.0 * k) + 1,
		"%s: font %d out of [36k, 72k]" % [tag, _main.font_size]
	)
	var dens: float = _main.line_h / maxf(1.0, glyph)
	_check(
		dens >= 1.8 and dens <= 2.4,
		"%s: line spacing %.2f glyphs is out of [1.8, 2.4]" % [tag, dens]
	)
	var free: float = _main._text_free_h() - 40.0 * k
	var vis: int = maxi(1, _main._vis_lines())
	var used: float = float(vis) * _main.line_h
	_check(
		used >= free - _main.line_h - 1.0,
		"%s: %d rows take %.0f px of %.0f — a whole row of air below" % [
			tag, vis, used, free]
	)
	# ГЛАВНОЕ правило: текст при ЕСТЕСТВЕННОМ шаге (строка = две высоты
	# глифа) должен занимать почти всю карточку. Иначе кегль мал, а
	# разницу съедает растянутый интерлиньяж — ровно то, на что жаловался
	# автор 14.10.2026 («текст точно мелкий»). Меряем строками: сколько
	# строк влезает в строку кеглем — столько и берём.
	var per_line: float = (
		(_main.view_w - _main.margin * 2.0) / maxf(1.0, _main.char_w) - 1.0
	)
	var rows: float = maxf(1.0, ceil(float(_main._chars_now()) / maxf(8.0, per_line)))
	var nat_used: float = rows * glyph * 2.0
	_check(
		nat_used >= free * 0.7,
		"%s: the text fills only %.0f px of %.0f at natural spacing" % [
			tag, nat_used, free]
	)
	# Короткий уровень на САМОЙ МЕЛКОЙ строке: растягивать нечего и некуда
	# (потолок интерлиньяжа 2.4 высоты глифа, автор 14.10.2026: «слишком
	# большой межстрочный интервал»). Кегль ужимаем вдвое, чтобы потолок
	# точно упирался, иначе проверка была бы вхолостую.
	var was_lines: Array[String] = _main.display_lines.duplicate()
	var was_drops: Array = _main.line_drops.duplicate()
	var was_hard: Array[bool] = []
	for hb in _main.line_hard:
		was_hard.append(bool(hb))
	var was_fs: int = _main.font_size
	_main.display_lines = ["Короткий."] as Array[String]
	_main.line_drops = [] as Array
	_main.line_hard = [false] as Array[bool]
	_main.font_size = maxi(10, int(float(was_fs) * 0.5))
	_main.char_w = _main._marginal_adv(_main.font_size)
	_main._layout_text_lines()
	var short_glyph: float = _main.mono.get_height(_main.font_size)
	var short_dens: float = _main.line_h / maxf(1.0, short_glyph)
	print("КОРОТКИЙ %s: glyph=%.1f line_h=%.1f плотность=%.2f free=%.0f text_y=%.0f карточка=%.0f" % [
		tag, short_glyph, _main.line_h, short_dens, free, _main.text_y,
		_main.card_p.size.y])
	_check(
		short_dens <= 2.4,
		"%s: a one-line level gets %.2f glyph spacing" % [tag, short_dens]
	)
	_check(
		_main.text_y > _main.card_p.position.y,
		"%s: a one-line level is not stuck to the card top" % tag
	)
	_main.display_lines = was_lines
	_main.line_drops = was_drops
	_main.line_hard = was_hard
	_main.font_size = was_fs
	_main.char_w = _main._marginal_adv(was_fs)
	_main._layout_text_lines()
	# Подсказка — в своей полосе под полосой прогресса и выше края.
	# Проверяем всегда (не только когда панель видима): геометрия живёт в
	# _hint_top, headless её иначе не увидеть.
	var hint_y: float = _main._hint_top()
	var hint_h: float = 64.0 * k
	_check(
		hint_y >= _main.card_p.position.y + _main.card_p.size.y + 26.0 * k - 1.0,
		"%s: the hint overlaps the progress bar (%.0f)" % [tag, hint_y]
	)
	_check(
		hint_y + hint_h <= _main._eff_h() + 1.0,
		"%s: the hint goes below the effective area (%.0f)" % [tag, hint_y + hint_h]
	)
	var card_right: float = float(_main.view_w - _main.margin)
	for l in _main.display_lines.size():
		var line: String = _main.display_lines[l]
		_check(line.length() > 0, "%s: empty row %d" % [tag, l])
		# В знаках: строка не шире лимита (с концевым пробелом-клеткой
		# мягкого переноса — на знак шире, см. _wrap_para).
		var lim: int = _main._max_chars() + (1 if line.ends_with(" ") else 0)
		_check(
			line.length() <= lim,
			"%s: row %d has %d chars, fits %d" % [tag, l, line.length(), lim]
		)
		# В пикселях: строка не вылезает за карточку. Ширина — клетки
		# (len × char_w): так рисуются глифы, целый замер шейпера врёт
		# на округлении (см. _marker_cells).
		var w: float = float(line.length()) * _main.char_w
		_check(
			_main.margin + w <= card_right + 1.0,
			"%s: row %d is %.0f px wide, card ends at %.0f" % [tag, l, _main.margin + w, card_right]
		)
		# Маркер в трёх точках строки — внутри своей полосы и карточки.
		for cp in [0, line.length() / 2, line.length() - 1]:
			_geo_marker(tag, l, cp, false)
		# И в ожидании переноса (курсор за концом строки): тоже внутри
		# своей полосы — иначе «захват» соседней строки. Ждать игра
		# может только на жёсткой строке (конец абзаца); на мягкой
		# курсор едет сам, такого состояния игра не создаёт.
		if l < _main.line_hard.size() and bool(_main.line_hard[l]):
			_geo_marker(tag, l, line.length(), true)


func _geo_marker(tag: String, l: int, cp: int, wait: bool) -> void:
	_main.cursor_line = l
	_main.cursor_pos = cp
	_main.need_enter = wait
	_main.state = "playing"
	_main._layout_text_lines()
	var r: Rect2 = _main._cursor_rect()
	_check(r.size.x > 0.0, "%s: no marker at %d:%d" % [tag, l, cp])
	var top: float = float(_main._line_y(l))
	_check(
		r.position.y >= top - 1.0 and r.end.y <= top + _main.line_h + 1.0,
		"%s: marker at %d:%d leaves its row band (%.0f..%.0f vs %.0f..%.0f)"
			% [tag, l, cp, r.position.y, r.end.y, top, top + _main.line_h]
	)
	_check(
		r.position.x >= _main.margin - 8.0 and r.end.x <= _main.view_w - _main.margin + 8.0,
		"%s: marker at %d:%d leaves the card (%.0f..%.0f)" % [tag, l, cp, r.position.x, r.end.x]
	)
	if wait:
		var hint: Dictionary = _main._enter_hint()
		_check(not hint.is_empty(), "%s: no chevron while waiting at %d:%d" % [tag, l, cp])


## Пробел на переносе — клетка: курсор стоит НА нём, метки на нём
## держатся, пересборка строк его не ест (автор 14.10.2026: пробел
## набирается, как в редакторе).
func _reflow_wrap_space() -> void:
	# Абзац «ab cd ef» шириной 6: «ab cd », «ef» — пробел клетка.
	var m := BB.fit_marked(["ab cd ef"], 6, [true])
	_check(
		(m["lines"] as Array) == ["ab cd ", "ef"],
		"wrap spaces must stay cells: %s" % str(m["lines"])
	)
	# Курсор на пробеле переживает сужение: тот же пробел, новая строка.
	var rf := BB.reflow(["ab cd ", "ef"], 0, 5, 4, [0, 0], [false, true], [false, false])
	_check(
		(rf["lines"] as Array) == ["ab ", "cd ", "ef"],
		"narrowing must rewrap, keeping the space: %s" % str(rf["lines"])
	)
	_check(
		int(rf["line"]) == 1 and int(rf["pos"]) == 2,
		"the cursor stays on its space (got %d:%d)" % [int(rf["line"]), int(rf["pos"])]
	)
	# Метка на том же пробеле переезжает вместе с курсором.
	var errs := {"0:5": "ж"}
	_main.line_drops = [0, 0]
	_main._remap_cells(errs, rf["table"], rf)
	_check(errs.has("1:2"), "the mark on the wrap space must survive: %s" % str(errs.keys()))
	# А конец уровня — всё равно конец: за последней строкой клеток нет.
	var rf2 := BB.reflow(["а б"], 0, 3, 8, [0], [true], [false])
	_check(
		int(rf2["line"]) == int((rf2["lines"] as Array).size()) and int(rf2["pos"]) == 0,
		"past-the-end must stay past-the-end"
	)


## Ось текста не рвётся при пересборке строк: та же буква — та же
## координата (ловил _case_relayout: зазор 46 → 76 при зайце на той же
## букве — съеденных пробелов до курсора стало меньше, а _lin их не
## считал). Детерминированная миниатюра релэута: широкая вёрстка, курсор
## на пробеле, сузить окно — буква и координата те же.
func _lin_stable() -> void:
	DisplayServer.window_set_size(Vector2i(820, 1180))
	root.size = Vector2i(820, 1180)
	_main._relayout()
	var typed: Array[String] = ["танец маму.", "А отец танцевать не умел."]
	_main.display_lines = typed
	var hard: Array[bool] = [true, true]
	_main.line_hard = hard
	var noglue: Array[bool] = [false, false]
	_main.line_glue = noglue
	_main.line_drops = [0, 0]
	_main._reindex_lines()
	_main.cursor_line = 0
	_main.cursor_pos = 5
	_main.need_enter = false
	_main.state = "playing"
	var letter := String(_main._current())
	var ax0: float = _main._lin(0, 5.0)
	DisplayServer.window_set_size(Vector2i(520, 900))
	root.size = Vector2i(520, 900)
	_main._relayout()
	_check(
		String(_main._current()) == letter,
		"the same letter after reflow (was «%s», got «%s»)" % [letter, String(_main._current())]
	)
	_check(
		absf(_main._lin(int(_main.cursor_line), float(_main.cursor_pos)) - ax0) <= 0.001,
		"the axis must not move under the hare (%.1f → %.1f)"
			% [ax0, _main._lin(int(_main.cursor_line), float(_main.cursor_pos))]
	)
	DisplayServer.window_set_size(Vector2i(1100, 650))
	root.size = Vector2i(1100, 650)
	_main._relayout()


## Верхняя панель — палец даже в альбоме (автор 17.10.2026: «в
## горизонтальном... еле читаемые и кликабельные — слишком мелкие»).
## k в альбоме ужимается эффективной высотой (≈0.9), и хром на k сыпался:
## кегль 26k ≈ 23 px, кнопка ≡ 50×43. Пол по dpr: телефон получает
## минимум 22dp текста и 44dp кнопку, десктоп (dpr=1) не меняется.
## Панель обязана не наезжать сама на себя в обеих ориентациях.
func _bar_floors() -> void:
	var was_dpr := Ui.dpr_override
	var was_ft := bool(_main._force_touch)
	# Альбомный телефон: канвас 2280×1080 (физические пиксели), dpr=2,
	# сенсор принудительно. k в игре меряет от физических размеров,
	# поэтому «полу-канвасом» как в menu пробы не равны.
	DisplayServer.window_set_size(Vector2i(2280, 1080))
	root.size = Vector2i(2280, 1080)
	Ui.dpr_override = 2.0
	_main._force_touch = true
	Ui.force_touch = true
	_main._relayout()
	var fs: int = _main.call("_bar_fs")
	_check(fs >= int(22.0 * 2.0), "landscape phone badge kegl keeps the 22dp floor (%d)" % fs)
	var pr: Rect2 = _main._players_rect
	_check(pr.size.x >= 44.0 * 2.0 - 0.5 and pr.size.y >= 44.0 * 2.0 - 0.5,
		"landscape ≡ button keeps the 44dp finger floor (%dx%d)" % [pr.size.x, pr.size.y])
	# Бейдж, заголовок и ≡ попарно не пересекаются и не выше карты.
	# Ректы — из чистых калк-функций: headless не рисует, хранимые
	# _badge_rect/_title_rect ставит только _draw.
	var bd: Rect2 = _main.call("_badge_rect_calc")
	var te: Rect2 = _main.call("_title_rect_calc", _main.call("_title_text"), fs)
	_check(not bd.intersects(te), "landscape: badge does not overlap the title")
	_check(not te.intersects(pr) and not bd.intersects(pr),
		"landscape: top bar does not overlap ≡")
	_check(te.end.y < bd.position.y + 2.0 * bd.size.y, "landscape: top bar in its band")
	# Портретный телефон: канвас 1080×2280, тот же dpr.
	DisplayServer.window_set_size(Vector2i(1080, 2280))
	root.size = Vector2i(1080, 2280)
	_main._relayout()
	var fs_p: int = _main.call("_bar_fs")
	_check(fs_p >= fs - 1, "portrait badge kegl is not smaller than landscape (%d < %d)" % [fs_p, fs])
	var prp: Rect2 = _main._players_rect
	_check(prp.size.x >= 44.0 * 2.0 - 0.5 and prp.size.y >= 44.0 * 2.0 - 0.5,
		"portrait ≡ button keeps the floor (%dx%d)" % [prp.size.x, prp.size.y])
	var tbd: Rect2 = _main.call("_badge_rect_calc")
	var tit: Rect2 = _main.call("_title_rect_calc", _main.call("_title_text"), fs_p)
	_check(not tbd.intersects(tit) and not tit.intersects(prp),
		"portrait: top bar does not overlap itself")
	# Матрица плотностей и ориентаций: полы держатся на ЛЮБОМ dpr, не
	# только на круглом 2.0 (телефоны 1.35–3.0), и в ОБЕИХ ориентациях —
	# в портрете пол 22dp раздувал бейдж до половины ширины, и он налезал
	# на заголовок (скрин автора 18.10.2026). Там же — правило
	# НЕИЗМЕННОСТИ видимых размеров: бейдж ≤ 45% ширины, глиф ≡ по центру
	# своей кнопки, dp-полы прогресса, подсказка ниже строки счёта.
	# Уровень фикстуры короткий и центрируется — перекрытие полосы не
	# ловит; подсовываем длинный (упирается в верх, как настоящий
	# альбомный) и после матрицы возвращаем. Ректы бейджа/заголовка
	# ставит _draw — в headless зовём его сами.
	var saved_lines: Array = _main.display_lines
	_main.display_lines = saved_lines + saved_lines + saved_lines
	for d in [1.35, 1.8, 2.5, 3.0]:
		for orient in [[2280, 1080], [1080, 2340]]:
			Ui.dpr_override = float(d)
			DisplayServer.window_set_size(Vector2i(orient[0], orient[1]))
			root.size = Vector2i(orient[0], orient[1])
			_main._force_touch = true
			Ui.force_touch = true
			_main._relayout()
			_main._process(1.0 / 60.0)
			var side: String = "portrait" if orient[0] == 1080 else "landscape"
			var vw: float = float(orient[0])
			var kk: float = float(_main.k)
			var fsm: int = _main.call("_bar_fs")
			_check(fsm >= int(22.0 * float(d)),
				"dpr %.2f %s: kegl keeps 22dp (%d)" % [d, side, fsm])
			var prm: Rect2 = _main._players_rect
			_check(prm.size.x >= 44.0 * float(d) - 0.5
				and prm.size.y >= 44.0 * float(d) - 0.5,
				"dpr %.2f %s: ≡ keeps 44dp (%.0fx%.0f)" % [
					d, side, prm.size.x, prm.size.y])
			# Бейдж не шире 45% экрана (иначе капсула съедает заголовок).
			var bdm: Rect2 = _main.call("_badge_rect_calc")
			var tem: Rect2 = _main.call("_title_rect_calc",
				_main.call("_title_text"), fsm)
			_check(bdm.size.x <= vw * 0.45 + 1.0,
				"dpr %.2f %s: badge within 45%% of width (%.0f)" % [
					d, side, bdm.size.x])
			_check(not bdm.intersects(tem),
				"dpr %.2f %s: badge overlaps the title" % [d, side])
			_check(tem.position.x >= bdm.end.x - 0.5
				and tem.end.x <= prm.position.x + 0.5,
				"dpr %.2f %s: title leaves the badge/≡ zone" % [d, side])
			_check(not tem.intersects(prm) and not bdm.intersects(prm),
				"dpr %.2f %s: top bar overlaps ≡" % [d, side])
			# Глиф ≡ — по центру кнопки, а не в её верхнем углу.
			var bb: Rect2 = _main.call("_burger_box")
			_check(absf(bb.get_center().y - prm.get_center().y) < 0.6
				and bb.position.x >= prm.position.x - 0.5
				and bb.end.x <= prm.end.x + 0.5,
				"dpr %.2f %s: ≡ glyph not centered in the button" % [d, side])
			# Карточка текста начинается НИЖЕ полосы (бейдж+≡).
			var band: float = float(_main.call("_bar_band_h"))
			var ctop: float = float(_main.text_y) - 20.0 * kk
			_check(ctop >= band - 0.5,
				"dpr %.2f %s: card top hits the top bar (%.0f < %.0f)" % [
					d, side, ctop, band])
			# Прогресс со счётом: dp-полы (в альбоме 12k/16k — это 4dp/6dp,
			# неразличимо) и при большом k прежние k-значения.
			var pm: Vector2 = _main.call("_progress_metrics")
			_check(pm.x >= 8.0 * float(d) - 0.5 and pm.y >= 14.0 * float(d) - 1.0,
				"dpr %.2f %s: progress loses dp floors (%.0f/%.0f)" % [
					d, side, pm.x, pm.y])
			_check(pm.x >= 12.0 * kk - 0.5 and pm.y >= 16.0 * kk - 1.0,
				"dpr %.2f %s: progress loses k sizes (%.0f/%.0f)" % [
					d, side, pm.x, pm.y])
			# Подсказка не налезает на строку счёта.
			var pend: float = float(_main.card_p.position.y) \
				+ float(_main.card_p.size.y)
			var htop: float = float(_main.call("_hint_top"))
			_check(htop >= pend + 14.0 * kk
				+ float(_main.call("_progress_line_h")) + 8.0 * kk - 0.5,
				"dpr %.2f %s: hint crosses the progress line" % [d, side])
	_main.display_lines = saved_lines
	# Десктоп: полы бездействуют (не сенсорный экран) — прежнее поведение.
	DisplayServer.window_set_size(Vector2i(1100, 650))
	root.size = Vector2i(1100, 650)
	Ui.dpr_override = 0.0
	var was_ft2 := bool(_main._force_touch)
	_main._force_touch = false
	Ui.force_touch = false
	_main._relayout()
	var fs_d: int = _main.call("_bar_fs")
	_check(fs_d == int(26.0 * float(_main.k)),
		"desktop kegl stays 26k (%d vs %d)" % [fs_d, int(26.0 * float(_main.k))])
	var prd: Rect2 = _main._players_rect
	_check(absf(prd.size.x - 56.0 * float(_main.k)) < 0.5,
		"desktop ≡ button keeps its old size (%.0f)" % prd.size.x)
	_main._force_touch = was_ft2
	Ui.force_touch = was_ft2
	Ui.dpr_override = was_dpr
	# Чистая арифметика dpr_from — суть фикса dpr(): dpi спасает упавший
	# движковый scale. window_get_current_screen() на Android = −1
	# (SCREEN_OF_MAIN_WINDOW), прежний гвард «scr < 0 → 1.0» обнулял dpr()
	# на всех телефонах — dp-полы v0.0.31/32 не работали вовсе. А движковый
	# scale и честной плотностью не бывает: он зажат размером окна
	# (MIN(scaledDensity, w/800, h/600), сырец 4.3), в альбоме 1.8 из 2.6.
	_check(absf(Ui.dpr_from(1.8, 420.0) - 2.625) < 0.001,
		"dpr_from: honest dpi beats the window-clamped scale")
	_check(absf(Ui.dpr_from(1.0, 420.0) - 2.625) < 0.001,
		"dpr_from: collapsed scale (the old guard bug) is rescued by dpi")
	_check(absf(Ui.dpr_from(1.0, 160.0) - 1.0) < 0.001, "dpr_from: 160dpi is density 1")
	_check(absf(Ui.dpr_from(0.0, 0.0) - 1.0) < 0.001, "dpr_from: zero readings fall back to 1")
	_check(absf(Ui.dpr_from(9.0, 960.0) - 3.5) < 0.001, "dpr_from: ceiling 3.5 holds")



func _text_bases() -> void:
	_check(not T.list_files("kids").is_empty(), "kids base is empty")
	_check(not T.list_files("pro").is_empty(), "pro base is empty")
	# Проза с диалогами бьётся на целые предложения.
	for path in T.list_files("pro"):
		var ss := T.file_sentences(path)
		_check(ss.size() >= 3, "pro file has too few sentences: %s" % path)
	# Фрагмент собирается из обеих баз.
	_check(not T.load_fragment(0, "kids").is_empty(), "no kids fragment")
	_check(not T.load_fragment(0, "pro").is_empty(), "no pro fragment")
	_check(not T.load_fragment(20, "pro").is_empty(), "no pro fragment at high difficulty")
	# База следует за тумблером.
	_main.all_keys_override = 1
	_check(String(_main._text_base()) == "pro", "pro toggle must select the adult base")
	_main.all_keys_override = 0
	_check(String(_main._text_base()) == "kids", "kids toggle must select the kids base")


## Фильтры знаков: файлы хранят оригиналы, правит парсер (автор 10.2026).
## Каждое правило — отдельным чеком, чтобы было видно, что именно
## отвалилось, когда издание принесёт новый знак.
func _text_normalize() -> void:
	# Тире нет на клавиатуре — дефис.
	_check(T.normalize_text("а—б") == "а-б", "em dash maps to hyphen")
	_check(T.normalize_text("а–б") == "а-б", "en dash maps to hyphen")
	# Ёлочек нет на клавиатуре — долой (диалоги остаются понятны).
	_check(T.normalize_text("«а»") == "а", "guillemets drop out")
	# Немецкие кавычки туда же (через коды: канал правит их при вводе).
	_check(
		T.normalize_text("а" + String.chr(0x201E) + "б" + String.chr(0x201C) + "в") == "абв",
		"german quotes drop out"
	)
	# Многоточие набирается тремя точками.
	_check(T.normalize_text("а…б") == "а...б", "ellipsis becomes three dots")
	# Типографский апостроф — в обычный (он на клавише).
	_check(T.normalize_text("д’о") == "д'о", "curly apostrophe straightens")
	# Неразрывные пробелы — обычные.
	_check(
		T.normalize_text("а" + String.chr(0xA0) + "б" + String.chr(0x202F) + "в") == "а б в",
		"nbsp becomes a space"
	)
	# Ударения изданий — типографика, не текст: снять, иначе знак
	# нечем набрать и покрытие падает.
	_check(
		T.normalize_text("а" + String.chr(0x301) + "б") == "аб",
		"combining accents drop out"
	)
	# Тонкие пробелы — обычные.
	_check(
		T.normalize_text("а б в") == "а б в",
		"thin spaces become plain ones"
	)
	# Фильтр пропускает предложения с бесклавишными буквами целиком.
	var mix: Array[String] = ["Мама мыла.", "Там всє гуляют."]
	var kept := T.playable(mix)
	_check(kept == ["Мама мыла."], "untypable sentences drop out whole (%s)" % str(kept))
	# Фильтр идемпотентен: повторный прогон ничего не меняет.
	var sample := "«Эх!» — думал… д’о а б"
	_check(
		T.normalize_text(T.normalize_text(sample)) == T.normalize_text(sample),
		"normalize is idempotent"
	)
	# Всё, что вышло из-под фильтра, обязано набираться доской.
	var out := T.normalize_text(sample + "—–„“" + String.chr(0x201D))
	for i in out.length():
		var ch := out.substr(i, 1)
		if ch == " ":
			continue
		_check(
			not K.combo_for(ch, "ru").is_empty() or not K.combo_for(ch, "en").is_empty(),
			"filtered char has no key: «%s»" % ch
		)


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
	# Уровень — run целых предложений (1+, обычно 3+), а не ровно три
	# строки: объём теперь в знаках (автор 10.2026).
	_check(not _main.display_lines.is_empty(), "level text loaded")
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
		for l in _main.display_lines.size():
			for q in String(_main.display_lines[l]).length():
				if _main._shown_char(l, q) == "␣":
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
	# Все буквы серые (active пуст), пробелы активны всегда. Сетап не
	# «герметизируем» обходами: строка БЕЗ пробела после серого run —
	# законный случай, и игра обязана его держать (см. проверку
	# «no-space grey line» ниже — 18.10.2026).
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
	# Ожидание переноса на строке, которую игра прошла САМА: серый run
	# без единого пробела доводит автопропуск до жёсткого конца, курсор
	# встаёт в ожидание ↵ — и Backspace там НИЧЕГО не делает: откатывать
	# можно только набранное. Здесь же планировалась редкая CI-поломка
	# 18.10.2026 (два разных тега краснели на этом только изредка, потому
	# что случайная строка без пробела почти не выпадала): строка руками,
	# детерминированно.
	_main._new_level()
	_main.state = "playing"
	_main.need_enter = false
	_main.cursor_line = 0
	_main.display_lines = ["ёжик", "дальше"] as Array[String]
	var hard_a: Array[bool] = [true, false]
	_main.line_hard = hard_a
	_main.line_drops = []
	var noglue_a: Array[bool] = [false, false]
	_main.line_glue = noglue_a
	_main._reindex_lines()
	_main.active = {}  # всё серое: «ёжик» игра проходит сама, до конца
	_main.cursor_pos = 0
	_main._skip_inactive()
	var waited := Vector2i(_main.cursor_line, _main.cursor_pos)
	_check(_main.need_enter, "a no-space grey line ends in the enter wait")
	var pass_a: int = _main.passed.size()
	_main._backspace()
	_check(_main.need_enter, "backspace keeps waiting on a line nobody typed")
	_check(
		Vector2i(_main.cursor_line, _main.cursor_pos) == waited,
		"the untyped wait is not cancelled by Backspace"
	)
	_check(_main.passed.size() == pass_a, "the wait keeps the skipped cells passed")
	# Та же пара «ожидание ↵», но заработанная НАБОРОМ: только «к»
	# активна — игра сама прошла «ё ж и», игрок набрал «к», курсор ждёт
	# ↵; отмена возвращает ровно на набранную клетку (правило 10.2026).
	_main._new_level()
	_main.state = "playing"
	_main.need_enter = false
	_main.cursor_line = 0
	_main.cursor_pos = 0
	_main.display_lines = ["ёжик", "дальше"] as Array[String]
	var hard_b: Array[bool] = [true, false]
	_main.line_hard = hard_b
	_main.line_drops = []
	var noglue_b: Array[bool] = [false, false]
	_main.line_glue = noglue_b
	_main._reindex_lines()
	_main.active = {"к": true}
	_main.cursor_line = 0
	_main.cursor_pos = 0
	_main._skip_inactive()  # серые «ё ж и» проходит, встаёт на «к»
	_check(_main.cursor_pos == 3, "the skip stops at the active letter")
	_main._type_char(_main._current())  # игрок набрал «к» — ждём ↵
	_check(_main.need_enter, "typing the last letter earns the enter wait")
	var bk := _cell_key(0, 3)
	_main._backspace()
	_check(not _main.need_enter, "a typed wait is cancelled by Backspace")
	_check(
		Vector2i(_main.cursor_line, _main.cursor_pos) == Vector2i(0, 3),
		"the typed wait retreats to the typed letter"
	)
	_check(
		not _main.passed.has(bk) and not _main.typed_cells.has(bk),
		"the typed wait erases the typed cell completely"
	)
	_check(
		_main.passed.has(_cell_key(0, 0)) and _main.passed.has(_cell_key(0, 2)),
		"the retreat keeps the auto-skipped prefix passed"
	)
	# А откат настоящей набранной буквы работает: сначала набираем
	# активную букву, потом откатываемся — встаём ровно на неё.
	# Герметичность: редкий уровень мог начаться строкой ЦЕЛИКОМ из
	# серых букв — набирать в серое нельзя (typed_cells не заводится,
	# откат честно не находит набранного: CI 18.10.2026, второй
	# прогон). Ищем строку, где есть активная буква.
	var guard2 := 0
	while guard2 < 24:
		_main._new_level()
		_main.active = BB.active_chars(0)
		_main.cursor_line = 0
		var fa_try := _first_active()
		if _main._is_active(_main.display_lines[0].substr(fa_try, 1)):
			break
		guard2 += 1
	if guard2 >= 24:
		print("ACTIVE-FAIL: line=[%s]" % [String(_main.display_lines[0])])
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
	# Пробел на месте разрыва — клетка: набирается, как в редакторе
	# (автор 14.10.2026; раньше его убирали — и на телефоне уровень не
	# проходился: «строка кончилась, а что нажимать?»). Массивы
	# типизированные: нетипизированный литерал в Array[String]-параметр
	# 4.3 не принимает (молча error).
	var fl: Callable = BB.fit_lines
	var raw1: Array[String] = ["мама мыла раму", "папа"]
	var fit1: Array = fl.call(raw1, 10)
	_check(fit1 == ["мама мыла ", "раму", "папа"], "long line wraps by words")
	_check(
		String(fit1[0]) + String(fit1[1]) == "мама мыла раму" and String(fit1[2]) == "папа",
		"wrap loses no characters"
	)
	var raw2: Array[String] = ["а б в"]
	_check(
		fl.call(raw2, 10) == ["а б в"], "short lines untouched"
	)
	var raw3: Array[String] = ["раз два три"]
	var fit2: Array = fl.call(raw3, 7)
	_check(fit2 == ["раз два ", "три"], "wrap point is exact")
	_check(
		String(fit2[0]).right(1) == " ", "the wrap space stays a cell"
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
			_main._row_visible(i) == (i >= 6 - vis),
			"visibility follows the window"
		)
	# Скролл едет плавно (анимация в _process), поэтому после прямой
	# раскладки дотягиваем его до цели — как если бы кадры прошли.
	_main.scroll_y = _main.scroll_target
	_check(
		_main.scroll_y == float(6 - vis) * _main.line_h,
		"scroll offset is exact"
	)
	_check(
		_main.card_p.size.y < 6.0 * _main.line_h + 40.0 * _main.k,
		"card is a window, not the whole text"
	)
	# Заранее видно следующую строку: курсор в середине текста, а строка
	# под ним — уже в окне (автор 15.10.2026). Раньше курсор всегда стоял
	# в последней видимой строке и следующая открывалась только по факту.
	_main.cursor_line = 3
	_main.cursor_pos = 0
	_main._layout_text_lines()
	_check(
		_main._row_visible(4),
		"the next line is visible before the cursor gets there"
	)
	_check(
		_main._row_visible(3),
		"the cursor line itself stays visible"
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
	# Повторный тап по той же звезде — идёт дальше (иначе большая звезда
	# по центру поля съедала бы главный тап «следующий уровень»).
	_main.call("_input", _tap(_main._star_center(2)))
	_check(_main.state == "playing", "a repeated star tap moves on")
	# Снова победа — дальше тест ждёт модалку под карточкой.
	_main._finish(true)
	_check(_main.state == "won", "setup: won for the work-area tap")
	# Тап по углу карточки (не по звезде — та показывает расшифровку).
	var corner := Rect2(
		_main.card_p.position + Vector2(20.0 * _main.k, _main.card_p.size.y - 40.0 * _main.k),
		Vector2(40.0, 20.0)
	).get_center()
	_main.call("_input", _tap(corner))
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

	_check(_main.stars_label.text == "★★☆", "missing star is hollow")
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
	_main.line_hard = [false] as Array[bool]
	_main.line_glue = [false] as Array[bool]
	_main.cursor_line = 0
	_main.cursor_pos = 0
	_main.need_enter = false
	_main.passed.clear()
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
	_main.line_hard = [false] as Array[bool]
	_main.line_glue = [false] as Array[bool]
	_main.cursor_line = 0
	_main.cursor_pos = 0
	_main.need_enter = false
	_main.passed.clear()
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
	_main.line_hard = [false] as Array[bool]
	_main.line_glue = [false] as Array[bool]
	_main.cursor_line = 0
	_main.cursor_pos = 0
	_main.need_enter = false
	_main.passed.clear()
	_main.errors.clear()
	_main._type_char("е")
	# Флаки-охота 15.10.2026: дважды падало только в полных прогонах
	# (соло 14+ зелёных) — при повторе этот принт покажет состояние.
	if _main.errors.is_empty():
		printerr("YO-FAIL state=", _main.state, " need_enter=", _main.need_enter,
			" cur=", _main._current(), " yo=", _main.profile_yo,
			" exact=", _main._exact(), " active=", _main.active,
			" pos=", _main.cursor_line, ":", _main.cursor_pos,
			" hard=", _main.line_hard, " glue=", _main.line_glue,
			" passed=", _main.passed.size())
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
