extends SceneTree
## Тест меток и координат. Правила, которые он держит (жалобы автора
## 10.2026 и ответ на них):
##
##  1. Откат за ошибку — РОВНО ОДИН символ. Текст моноширинный, шаг
##     обязан быть точным: «вроде у нас моноширинный текст и можно всегда
##     отступать на 1 символ ровно». Каждая ошибка — минус один глиф по
##     сквозной оси, независимо от того, активная буква или серая.
##  2. Пачка ошибок без верного ввода даёт СПЛОШНУЮ стопку меток, без
##     разрывов и без прыжков по тексту — это и было «весь стек красных
##     букв перескакивает от одной печатной буквы к куче других».
##  3. Буква, на которой стоит заяц, нарисована как буква, которую игра
##     ЖДЁТ: тот же цвет, что у активной. Рамка под текущей клеткой и
##     раньше была всегда, но сама буква рисовалась тусклым цветом
##     автопропущенной — заяц после отката встаёт на серый символ, игра
##     там ждёт нажатия, а ребёнок читает это как «буква не считается».
##  4. Меток не больше, чем ошибок, и они не вылезают за пределы набранного
##     по оси текста.
##  5. Заяц доезжает до своей клетки; пока ввод молчит, отставание только
##     убывает — иначе картинка врёт о позиции.
##  6. Стек меток всегда разбирается набором подсказанных букв: уровень
##     непроходимым быть не может.
##  7. Заяц нарисован внутри карточки текста и на своей строке: после
##     победы курсор уходит за конец текста, и без зажима заяц уезжал
##     вниз экрана на полосу прогресса (визуальный прогон 10.2026).
##
## Партии моделируются с фиксированным временем и живым вводом (скорость,
## частота ошибок, Backspace), инварианты проверяются на КАЖДОМ кадре.
##
## Запуск: godot --headless --path game --script res://tests/marks_test.gd

const DT := 1.0 / 60.0

var _main: Node = null
var _frame := 0
var _failures: Array[String] = []
## Статистика замера.
var _marks_checked := 0
var _worst_lag := 0.0
var _lag := 0.0
var _prev_lag := 0.0
var _burst_errors := 0
var _burst_marks := 0
var _worst_burst_span := 0
var _worst_burst_tag := ""
var _sessions := 0
var _wins := 0
var _errors_total := 0


func _check(cond: bool, what: String) -> void:
	if not cond:
		_failures.append(what)


func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	_main = scene.instantiate()
	_main.skip_menu = true
	_main.all_keys_override = 1
	root.add_child(_main)
	# Время ведём сами: иначе кадры headless идут быстрее, чем ёж едет,
	# и замер координат вырождается в ноль.
	_main.process_mode = Node.PROCESS_MODE_DISABLED


## Одна клетка символа по строкам и позиции.
func _cell_ch(l: int, p: int) -> String:
	if l < 0 or l >= _main.display_lines.size():
		return ""
	var line: String = _main.display_lines[l]
	if p < 0 or p >= line.length():
		return ""
	return line.substr(p, 1)


## Все инварианты кадра. Вызывается на КАЖДЫЙ кадр каждой партии.
## coords=true только там, где кадры реально идут: в сценариях без
## кадров заяц физически не успевает доехать до своей клетки, и это не
## дефект, а свойство сценария.
func _invariants(tag: String, coords := false) -> void:
	_drawn(tag)
	if _main.state != "playing":
		return
	var l := int(_main.cursor_line)
	var p := int(_main.cursor_pos)
	var cur := _cell_ch(l, p)
	if cur != "" and not _main._is_active(cur) and not _main.hints.has(_main._key(l, p)):
		# Правило 3: серая буква под зайцем — это буква, которую игра
		# ЖДЁТ, и рисуется она ровно как активная. Иначе откат на серый
		# сим��ол выглядит как «игра просит клавишу, которой не видно».
		var probe := _active_probe(l, p)
		if probe.size() == 3:
			_check(
				_main._cell_color(l, p, cur, _main._key(l, p))
					== _main._cell_color(
						int(probe[0]), int(probe[1]), String(probe[2]), _main._key(int(probe[0]), int(probe[1]))
					),
				"%s: grey «%s» under the hare is not shown as the letter the game waits for"
					% [tag, cur]
			)
	_marks_checked += _main.errors.size()
	_check(
		_main.errors.size() <= _main.typed_bad,
		"%s: more marks (%d) than mistakes (%d)" % [tag, _main.errors.size(), _main.typed_bad]
	)
	_mark_axis_check(tag)
	if coords:
		# Заяц нарисован там, где игра его ждёт: hero_r едет к _hero_pos()
		# (спрайт центрируется на левом краю клетки, поэтому сравниваем с
		# логической позицией, а не с центром буквы). Само отставание не
		# дефект: после пачки ошибок зайца сносит на несколько глифов, и
		# он доезжает прыжками. Дефект — когда он НЕ доезжает: пока ввод
		# молчит, отставание обязано только убывать (см. _session).
		_lag = absf(_main.hero_r.x - _main._hero_pos().x) / _main.char_w
		_worst_lag = maxf(_worst_lag, _lag)


## Ближайшая ещё не набранная активная клетка без вспышки-подсказки:
## эталон «буква, которую игра просит». Пройденные не берём — их цвет
## серый по уговор��нке. Возвращает [строка, позиция, символ] или пусто.
func _active_probe(l: int, p: int) -> Array:
	for step in range(1, 60):
		var q := p + step
		if q >= _main.display_lines[l].length():
			break
		var ch := _cell_ch(l, q)
		var kk: String = _main._key(l, q)
		if _main._is_active(ch) and not _main.hints.has(kk) and not _main.passed.has(kk):
			return [l, q, ch]
	for step in range(1, 60):
		var q := p - step
		if q < 0:
			break
		var ch := _cell_ch(l, q)
		var kk: String = _main._key(l, q)
		if _main._is_active(ch) and not _main.hints.has(kk) and not _main.passed.has(kk):
			return [l, q, ch]
	return []


## Правило 7: заяц нарисован внутри полосы строк текста. Проверяется в
## ЛЮБОМ состоянии, включая экраны победы и проигрыша: там курсор стоит
## за концом текста, и без зажима заяц уезжал вниз, на полосу прогресса
## (визуальный прогон 10.2026, кадр «11-win»).
func _drawn(tag: String) -> void:
	var rows: int = _main.display_lines.size()
	if rows == 0:
		return
	var top: float = _main._track_cy(0) - _main._unit_h() * 0.5
	var bottom: float = _main._track_cy(rows - 1) + _main._unit_h() * 0.5
	_check(
		_main.hero_r.y >= top - 1.0 and _main.hero_r.y <= bottom + 1.0,
		"%s: the hare is drawn outside the text lines (y=%.0f, band %.0f..%.0f, state %s)"
			% [tag, _main.hero_r.y, top, bottom, _main.state]
	)


## Метки по оси текста: не впереди всего набранного и не позади зайца.
func _mark_axis_check(tag: String) -> void:
	var hare: float = _main._lin(int(_main.cursor_line), float(_main.cursor_pos))
	var hi := hare
	for k in _main.typed_cells.keys():
		var parts: PackedStringArray = String(k).split(":")
		hi = maxf(hi, _main._lin(int(parts[0]), float(parts[1])))
	for k in _main.errors.keys():
		var parts2: PackedStringArray = String(k).split(":")
		var ax: float = _main._lin(int(parts2[0]), float(parts2[1]))
		_check(
			ax >= hare - 0.001 and ax <= hi + 0.001,
			"%s: a mark landed outside the typed area (mark %.1f, hare %.1f, typed up to %.1f)"
				% [tag, ax, hare, hi]
		)


## Кадр партии: гоним и логику, и замер.
func _tick(tag := "") -> void:
	_frame += 1
	_main._process(DT)
	_invariants(tag if tag != "" else "frame %d" % _frame, true)


## Модель ребёнка: жмёт подсказанную букву, изредка ошибается, иногда
## жмёт Backspace. Возвращает true, если на этом кадре было нажатие.
func _child(key_gap: float, err_rate: float, back_rate: float, gap: float) -> bool:
	if _main.state == "won" or _main.state == "lost":
		# Дальше — Enter, как в жизни.
		_main._unhandled_key_input(_enter())
		return true
	gap -= DT
	if gap > 0.0:
		return false
	gap = key_gap
	var cur: String = _main._current()
	if cur == "":
		return false
	var roll := randf()
	if roll < back_rate:
		_main._backspace()
		return true
	if roll < back_rate + err_rate:
		var bad := "ы" if cur.to_lower() != "ы" else "ж"
		_main._type_char(bad)
		_errors_total += 1
		return true
	_main._type_char(cur)
	return true


func _enter() -> InputEventKey:
	var ke := InputEventKey.new()
	ke.pressed = true
	ke.keycode = KEY_ENTER
	ke.unicode = 13
	return ke


## Одна партия до конца (победа/проигрыш) с проверкой на каждом кадре.
func _session(tag: String, difficulty: int, all_keys: int, key_gap: float, err_rate: float, back_rate: float) -> void:
	_sessions += 1
	_main.all_keys_override = all_keys
	_main.difficulty = difficulty
	_main._new_level()
	var gap := 0.0
	var guard := 0
	while guard < 60 * 60 * 8:
		guard += 1
		_tick("%s f%d" % [tag, guard])
		var pressed := _child(key_gap, err_rate, back_rate, gap)
		_invariants("%s after a key" % tag)
		# Пока ребёнок молчит, заяц обязан догонять свою клетку: иначе
		# на экране он навсегда отстаёт, и картинка врёт о позиции.
		if not pressed and _main.state == "playing":
			_check(
				_lag <= _prev_lag + 0.02,
				"%s f%d: the hare drifts away while the input is quiet (%.2f → %.2f chars)"
					% [tag, guard, _prev_lag, _lag]
			)
		_prev_lag = _lag
		if _main.state == "won" or _main.state == "lost":
			if _main.state == "won":
				_wins += 1
			break
	_settle(tag)


## Ввод молчит — заяц встаёт ровно на своё место.
func _settle(tag: String) -> void:
	for i in 90:
		_tick("%s settle %d" % [tag, i])
	_check(
		absf(_main.hero_r.x - _main._hero_pos().x) < 0.5,
		"%s: the hare never reached its place (off by %.1f px)"
			% [tag, absf(_main.hero_r.x - _main._hero_pos().x)]
	)


## Ошибка моделем. Откат обязан быть РОВНО на один символ назад по
## сквозной оси (правило 1) — это и есть моноширинный «шаг назад».
func _mistake(tag: String) -> float:
	var before: float = _main._lin(int(_main.cursor_line), float(_main.cursor_pos))
	var cur: String = _main._current()
	if cur == "":
		return before
	var behind: Vector2i = _main._behind()
	_errors_total += 1
	_main._type_char("ы" if cur.to_lower() != "ы" else "ж")
	var after: float = _main._lin(int(_main.cursor_line), float(_main.cursor_pos))
	if behind.x >= 0:
		_check(
			absf(after - (before - 1.0)) <= 0.001,
			"%s: a mistake moved the hare %.2f chars back, expected exactly 1"
				% [tag, before - after]
		)
	else:
		# Самое начало текста: откатываться некуда, заяц стоит.
		_check(
			absf(after - before) <= 0.001,
			"%s: the hare left the start of the level (moved %.1f chars)"
				% [tag, after - before]
		)
	_invariants("%s after a mistake" % tag)
	return before


## Серия ошибок подряд на настоящем тексте: главный сценарий жалобы.
## Проверяем и сплошную стопку меток, и путь выхода из неё.
func _burst(tag: String, difficulty: int, all_keys: int) -> void:
	_main.all_keys_override = all_keys
	_main.difficulty = difficulty
	_main._new_level()
	# Десять верных букв, чтобы увести зайца от начала текста.
	for i in 10:
		var ch: String = _main._current()
		if ch == "":
			break
		_main._type_char(ch)
	var errs := 5
	var spots: Array[float] = []
	for i in errs:
		var before := _mistake(tag)
		if spots.is_empty() or before < spots[spots.size() - 1]:
			spots.append(before)
	# Правило 2: каждая следующая метка — ровно на символ дальше от
	# зайца, стопка без разрывов. Прыжок метки = «красные буквы
	# перескакивают по тексту» (жалоба автора 10.2026).
	for i in range(1, spots.size()):
		_check(
			absf(spots[i - 1] - spots[i] - 1.0) <= 0.001,
			"%s: mistake %d marked %.1f chars further back than 1 (the stack jumps)"
				% [tag, i + 1, spots[i - 1] - spots[i]]
		)
	_burst_errors += errs
	_burst_marks += _main.errors.size()
	# Разброс стопки по оси: пять ошибок — пять глифов, не пол-экрана.
	var lo := INF
	var hi := -INF
	for k in _main.errors.keys():
		var parts: PackedStringArray = String(k).split(":")
		var ax: float = _main._lin(int(parts[0]), float(parts[1]))
		lo = minf(lo, ax)
		hi = maxf(hi, ax)
	if hi > -INF:
		var span: float = hi - lo
		if span > float(_worst_burst_span):
			_worst_burst_span = int(span)
			_worst_burst_tag = "%s: метки с %.0f по %.0f" % [tag, lo, hi]
	_check(
		float(_worst_burst_span) <= errs - 1 + 0.001 or _burst_marks < errs,
		"%s: the stack is scattered over %d glyphs for %d mistakes"
			% [tag, _worst_burst_span, errs]
	)
	# Выход из стека: набираем подсказанное — метки обязаны кончиться,
	# и каждое нажатие должно быть буквой, которую игра просит.
	var steps := 0
	while not _main.errors.is_empty() and steps < 400:
		steps += 1
		var cur2: String = _main._current()
		if cur2 == "":
			break
		_main._type_char(cur2)
		_invariants("%s while clearing the stack" % tag)
	_check(
		_main.errors.is_empty(),
		"%s: the stack of %d marks is not clearable by typing (marks=%d)"
			% [tag, errs, _main.errors.size()]
	)
	# Пачка кончилась, ввод молчит: заяц обязан доехать до своей клетки.
	for i in 60:
		_tick("%s settle %d" % [tag, i])
	_check(
		absf(_main.hero_r.x - _main._hero_pos().x) < 0.5,
		"%s: the hare did not reach its place after the burst (off by %.1f px)"
			% [tag, absf(_main.hero_r.x - _main._hero_pos().x)]
	)


func _report() -> void:
	print("MARKS_TEST: партий=%d побед=%d ошибок=%d проверок меток=%d"
		% [_sessions, _wins, _errors_total, _marks_checked])
	print("MARKS_TEST: худшее отставание зайца от своей клетки=%.2f симв." % _worst_lag)
	print("MARKS_TEST: пачки по %d ошибок → меток %d, худший разброс стека=%d глиф. (%s)"
		% [_burst_errors, _burst_marks, _worst_burst_span, _worst_burst_tag])


func _process(_dt: float) -> bool:
	if _frame > 0:
		return true
	# Пачки ошибок на разных режимах и текстах.
	for d in [0, 2, 5]:
		_burst("burst d=%d all" % d, d, 1)
		_burst("burst d=%d own" % d, d, 0)
	# Живые партии: ребёнок с разной скоростью, частотой ошибок и любовью
	# к Backspace. Здесь и ловится рассинхрон, который не видно глазами.
	_session("slow child", 0, 0, 0.66, 0.05, 0.02)
	_session("medium child", 1, 0, 0.33, 0.03, 0.01)
	_session("fast child, backspace", 3, 0, 0.20, 0.02, 0.15)
	_session("all keys, fast", 4, 1, 0.20, 0.02, 0.05)
	_session("clumsy child", 0, 0, 0.80, 0.14, 0.05)
	_session("clumsy, all keys", 6, 1, 0.25, 0.12, 0.10)
	_session("medium, hard", 5, 0, 0.25, 0.06, 0.05)
	_report()
	_check(_marks_checked > 100, "the marks were actually checked (coverage)")
	_check(_burst_marks > 0, "mistakes did produce marks (coverage)")
	_check(_sessions == 7, "all sessions ran")
	_check(_errors_total > 30, "the child made enough mistakes (coverage)")
	for f in _failures:
		print("MARKS_TEST: FAIL: ", f)
	print("MARKS_TEST: PASS" if _failures.is_empty() else "MARKS_TEST: FAIL")
	return true