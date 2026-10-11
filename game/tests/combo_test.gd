extends SceneTree
## Тест комбинаций событий. marks_test держит «как правильно» (шаг,
## стопка, цвет буквы), этот — «а что будет, если события идут
## не по одному»: пачками от IME, с автозаменой, с DEL-сериями,
## цепочками Backspace, штормом ошибок, на границе строк и в конце
## уровня. Именно такие связки приходят с телефона (Gboard/Яндекс
## шлют слово целиком, автозамена — DEL + переписанный регион), и
## именно на них жаловался автор: «стек красных букв перескакивает».
##
## Инварианты общие с marks_test, ко��орые проверяются на каждом шаге:
##  * откат за ошибку — ровно один символ по сквозной оси;
##  * меток не больше, чем ошибок, и они не вылезают за набранное;
##  * стопка ошибок сплошная: метки идут символ в символ;
##  * буква под зайцем нарисована так же, как буква, которую игра ждёт;
##  * счётчики набора честные: Backspace их не трогает;
##  * уровень проходим: набирая подсказанное, ребёнок доходит до конца.
##
## Запуск: godot --headless --path game --script res://tests/combo_test.gd

const DT := 1.0 / 60.0
const S := preload("res://scripts/save.gd")
const Kbd := preload("res://scripts/kbd.gd")
const B := preload("res://scripts/balance.gd")
## Пять заведомо неверных букв для пачки от IME. Разные — иначе это
## машинный дубль клавиши, который фильтр DUP_MS глотает по замыслу.
const IME_WRONG := ["ы", "ж", "ц", "щ", "э"]

var _main: Node = null
var _frame := 0
var _failures: Array[String] = []
var _cases := 0
var _steps := 0


func _check(cond: bool, what: String) -> void:
	if not cond:
		_failures.append(what)


func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	_main = scene.instantiate()
	_main.skip_menu = true
	_main.all_keys_override = 1
	root.add_child(_main)
	_main.process_mode = Node.PROCESS_MODE_DISABLED


# --- ввод моделью ----------------------------------------------------

## Клавиша без кода — как даёт своя экранная клавиатура: в игру доходит
## чистый символ, без машины вокруг. Ввод в игру один (прямой путь).
func _soft(ch: String) -> void:
	var ke := InputEventKey.new()
	ke.pressed = true
	ke.keycode = KEY_UNKNOWN
	ke.unicode = ch.unicode_at(0)
	_main._unhandled_key_input(ke)


## Настоящая клавиша (keycode есть) — как с железной клавиатуры.
func _hard(ch: String, code: int = KEY_A) -> void:
	var ke := InputEventKey.new()
	ke.pressed = true
	ke.keycode = code
	ke.unicode = ch.unicode_at(0)
	_main._unhandled_key_input(ke)


func _back() -> void:
	var ke := InputEventKey.new()
	ke.pressed = true
	ke.keycode = KEY_BACKSPACE
	ke.unicode = 8
	_main._unhandled_key_input(ke)


## Key-событие с настоящим keycode (F2, Enter, точка автопунктуации).
func _key(code: int, uni := 0) -> InputEventKey:
	var ke := InputEventKey.new()
	ke.pressed = true
	ke.keycode = code
	ke.unicode = uni
	return ke


func _enter() -> void:
	var ke := InputEventKey.new()
	ke.pressed = true
	ke.keycode = KEY_ENTER
	ke.unicode = 13
	_main._unhandled_key_input(ke)


## Кадр: едет заяц, идёт ёж.
func _tick(tag: String) -> void:
	_frame += 1
	_steps += 1
	_main._process(DT)
	_common(tag)


func _ax() -> float:
	return _main._lin(int(_main.cursor_line), float(_main.cursor_pos))


## Правило отрисовки (как в marks_test): заяц не выходит за полосу строк.
func _drawed(tag: String) -> void:
	var rows: int = _main.display_lines.size()
	if rows == 0:
		return
	var top: float = _main._track_cy(0) - _main._unit_h() * 0.5
	var bottom: float = _main._track_cy(rows - 1) + _main._unit_h() * 0.5
	# Куда заяц СТОИТ (логическая позиция) — всегда. Нарисованную позицию
	# проверяем, только когда он довез: между строками заяц летит по дуге
	# и на кадре смены раскладки (появилась клавиатура) едет к новой
	# высоте текста — это нормальная анимация, а не брак.
	var want_y: float = _main._hero_pos().y
	_check(
		want_y >= top - 1.0 and want_y <= bottom + 1.0,
		"%s: the hare stands outside the text lines (y=%.0f, band %.0f..%.0f, row %d/%d)"
			% [tag, want_y, top, bottom, _main.cursor_line, rows]
	)
	if absf(_main.hero_r.y - want_y) < 1.0:
		_check(
			_main.hero_r.y >= top - 1.0 and _main.hero_r.y <= bottom + 1.0,
			"%s: the hare is drawn outside the text lines (y=%.0f, band %.0f..%.0f)"
				% [tag, _main.hero_r.y, top, bottom]
		)


## Общие инварианты: состояние обязано быть связным после ЛЮБОГО ввода.
func _common(tag: String) -> void:
	_drawed(tag)
	if _main.state != "playing":
		return
	_check(
		_main.errors.size() <= _main.typed_bad,
		"%s: marks %d > mistakes %d" % [tag, _main.errors.size(), _main.typed_bad]
	)
	var hare := _ax()
	var hi := hare
	for k in _main.typed_cells.keys():
		var parts: PackedStringArray = String(k).split(":")
		hi = maxf(hi, _main._lin(int(parts[0]), float(parts[1])))
	for k in _main.errors.keys():
		var parts2: PackedStringArray = String(k).split(":")
		var ax: float = _main._lin(int(parts2[0]), float(parts2[1]))
		_check(
			ax >= hare - 0.001 and ax <= hi + 0.001,
			"%s: a mark at %.1f is outside the typed area (hare %.1f, typed to %.1f)"
				% [tag, ax, hare, hi]
		)
	# Буква, которую игра ждёт, нарисована как активная.
	var l := int(_main.cursor_line)
	var p := int(_main.cursor_pos)
	var line: String = _main.display_lines[l] if l < _main.display_lines.size() else ""
	if p >= 0 and p < line.length() and not _main.hints.has(_main._key(l, p)):
		var ch := line.substr(p, 1)
		if not _main._is_active(ch):
			var probe := _active_probe(l, p)
			if probe.size() == 3:
				_check(
					_main._cell_color(l, p, ch, _main._key(l, p))
						== _main._cell_color(int(probe[0]), int(probe[1]), String(probe[2]), _main._key(int(probe[0]), int(probe[1]))),
					"%s: grey «%s» under the hare is not shown as wanted" % [tag, ch]
				)


func _active_probe(l: int, p: int) -> Array:
	for step in range(1, 60):
		var q := p + step
		if q >= _main.display_lines[l].length():
			break
		var ch: String = _main.display_lines[l].substr(q, 1)
		var kk: String = _main._key(l, q)
		if _main._is_active(ch) and not _main.hints.has(kk) and not _main.passed.has(kk):
			return [l, q, ch]
	for step in range(1, 60):
		var q := p - step
		if q < 0:
			break
		var ch: String = _main.display_lines[l].substr(q, 1)
		var kk: String = _main._key(l, q)
		if _main._is_active(ch) and not _main.hints.has(kk) and not _main.passed.has(kk):
			return [l, q, ch]
	return []


func _fresh(difficulty: int, all_keys: int) -> void:
	_main.all_keys_override = all_keys
	_main.difficulty = difficulty
	_main._new_level()


func _wrong() -> String:
	var cur: String = _main._current()
	return "ы" if cur.to_lower() != "ы" else "ж"


func _spots() -> Array[float]:
	# Оси всех меток, по возрастанию — для проверки сплошности стопки.
	var out: Array[float] = []
	for k in _main.errors.keys():
		var parts: PackedStringArray = String(k).split(":")
		out.append(_main._lin(int(parts[0]), float(parts[1])))
	out.sort()
	return out


## Метки образуют сплошную стопку: между соседними — ровно один символ.
## Метки копятся НАЗАД, поэтому по оси текста они идут по убыванию;
## после сортировки по возрастанию шаг между соседними равен +1.
func _stack_is_solid(tag: String) -> void:
	var s := _spots()
	for i in range(1, s.size()):
		_check(
			absf(s[i] - s[i - 1] - 1.0) <= 0.001,
			"%s: the stack has a hole between %.0f and %.0f (gap %.1f)"
				% [tag, s[i - 1], s[i], s[i] - s[i - 1]]
		)


## Набираем верные буквы, пока заяц не уйдёт на долю текста. Нужно для
## шторма ошибок: отступать есть куда, иначе откат упирается в начало
## текста и метки копятся на одной клетке (это отдельный сценарий).
func _advance_to(frac: float) -> bool:
	var total := 0.0
	for line in _main.display_lines:
		total += float((line as String).length())
	var want := total * frac
	var guard := 0
	while _ax() < want and guard < 2000:
		guard += 1
		var cur: String = _main._current()
		if cur == "":
			return false
		_main._type_char(cur)
		_tick("advance")
		if _main.state != "playing":
			return false
	return _ax() >= want


# --- сценарии --------------------------------------------------------

## 1. Слово целиком от IME: пять неверных символов одним куском.
func _case_ime_word() -> void:
	_fresh(0, 0)
	_check(_advance_to(0.35), "ime word: could not advance into the text (coverage)")
	var tag := "ime word"
	var before := _ax()
	# Пять РАЗНЫХ букв (пять одинаковых — машинный дубль, его фильтр
	# DUP_MS глотает) и каждая не та, что ждёт игра: иначе «ошибка»
	# окажется верной, меток выйдет меньше пяти, и сценарий валится в
	# зависимости от выпавшего текста (ловил на CI 10.2026).
	var pool := ["ы", "ж", "ц", "щ", "э", "ф", "ъ", "б", "д", "к"]
	var prev := ""
	for i in 5:
		var cur: String = _main._current().to_lower()
		var pick := ""
		for c in pool:
			if c != cur and c != prev:
				pick = c
				break
		if pick == "":
			pick = "ы"
		prev = pick
		_soft(pick)
	_tick(tag)
	_check(_main.errors.size() == 5, "%s: 5 soft mistakes gave %d marks" % [tag, _main.errors.size()])
	_check(
		absf(_ax() - (before - 5.0)) <= 0.001,
		"%s: the hare retreated %.1f chars instead of 5" % [tag, before - _ax()]
	)
	_stack_is_solid(tag)
	_common(tag)


## 2. Автозамена: DEL-серия и переписанный регион одним куском.
func _case_autocorrect() -> void:
	_fresh(0, 0)
	_check(_advance_to(0.3), "autocorrect: could not advance (coverage)")
	var tag := "autocorrect"
	# Слово из трёх букв, автозамена переписывает последние две.
	var word: String = _main._current() + _main._current()
	for i in word.length():
		_soft(word.substr(i, 1))
	# «ё» вместо ожидаемой буквы: если игра сама ждёт «ё», сценарий
	# теряет смысл (и был случайно нестабилен).
	for i in 3:
		_back()
		if _main._current().to_lower() == "ё":
			_soft("ж")
		else:
			_soft("ё")
	_tick(tag)
	_common(tag)
	# Дальше уровень обязан проходиться: набираем подсказанное до конца.
	_finish_level(tag)


## 3. Backspace-цепочка: после шторма ошибок каждое нажатие снимает
## ровно одну метку и не двигает счётчики.
func _case_backspace_chain() -> void:
	_fresh(0, 0)
	_check(_advance_to(0.4), "backspace chain: could not advance (coverage)")
	var tag := "backspace chain"
	for i in 6:
		_main._type_char(_wrong())
	_tick(tag)
	var marks: int = _main.errors.size()
	var ok0: int = _main.typed_ok
	var bad0: int = _main.typed_bad
	for i in marks:
		_back()
		_tick(tag)
		_check(
			_main.errors.size() == marks - i - 1,
			"%s: after %d backspaces %d marks are left (expected %d)"
				% [tag, i + 1, _main.errors.size(), marks - i - 1]
		)
		_check(
			_main.typed_ok == ok0 and _main.typed_bad == bad0,
			"%s: backspace moved the typing counters" % tag
		)


## 4. Backspace в самом начале текста: сдвигать нечего.
func _case_backspace_at_start() -> void:
	_fresh(0, 0)
	var tag := "backspace at start"
	var cur := Vector2i(int(_main.cursor_line), int(_main.cursor_pos))
	var ok0: int = _main.typed_ok
	var bad0: int = _main.typed_bad
	for i in 3:
		_back()
		_tick(tag)
	_check(
		Vector2i(int(_main.cursor_line), int(_main.cursor_pos)) == cur,
		"%s: the hare moved at the start of the level" % tag
	)
	_check(
		_main.typed_ok == ok0 and _main.typed_bad == bad0,
		"%s: backspace at the start moved the counters" % tag
	)


## 5. Ошибка на самой первой клетке: откатываться некуда, метка стоит.
func _case_mistake_at_start() -> void:
	# Именно первая клетка уровня: за ней откатываться некуда.
	_fresh(0, 1)
	_main.cursor_line = 0
	_main.cursor_pos = 0
	_main.hero_r = _main._hero_pos()
	var tag := "mistake at start"
	_check(_ax() <= 0.001, "%s: could not put the hare at the very first cell" % tag)
	var start := _ax()
	_main._type_char(_wrong())
	_tick(tag)
	_check(absf(_ax() - start) <= 0.001, "%s: the hare retreated at the start" % tag)
	_check(_main.errors.size() == 1, "%s: no mark at the start" % tag)
	# Вторая ошибка на том же месте: метка одна (перезапись), заяц на месте.
	_main._type_char(_wrong())
	_tick(tag)
	_check(_main.errors.size() == 1, "%s: two mistakes at the start made %d marks" % [tag, _main.errors.size()])
	_check(_main.typed_bad == 2, "%s: the mistakes were not counted" % tag)
	# Верная буква обязана снимать метку.
	_hard(_main._current())
	_tick(tag)
	_check(_main.errors.is_empty(), "%s: the right letter did not clear the mark" % tag)


## 6. Шторм: двадцать ошибок подряд. Заяц уходит на 20 символов назад,
## стопка сплошная, уровень остаётся проходимым.
func _case_error_storm() -> void:
	_fresh(2, 1)
	var tag := "error storm"
	_check(_advance_to(0.55), "error storm: could not advance (coverage)")
	var before := _ax()
	for i in 20:
		_main._type_char(_wrong())
	_tick(tag)
	_check(_main.errors.size() == 20, "%s: 20 mistakes gave %d marks" % [tag, _main.errors.size()])
	_check(
		absf(before - _ax() - 20.0) <= 0.001,
		"%s: the storm moved the hare %.1f chars instead of 20" % [tag, before - _ax()]
	)
	_stack_is_solid(tag)
	_finish_level(tag)


## 7. Граница строк: шторм через перенос. Метки по оси идут подряд,
## заяц переходит на строку назад, ровно как по глифам.
func _case_line_wrap() -> void:
	_fresh(1, 1)
	var tag := "line wrap"
	# Уводим зайца на вторую строку.
	while int(_main.cursor_line) < 1:
		_hard(_main._current())
		_tick(tag)
		if _main.state != "playing":
			return
	var line_before := int(_main.cursor_line)
	var stepped := 0
	# Откат ровно на глиф — пока есть куда: упор в самое начало текста
	# (строка уровня бывает короче пяти символов, и там откатываться
	# некуда — это правило игры, а не ошибка).
	for i in 5:
		if _main._behind().x < 0:
			break
		var before := _ax()
		_main._type_char(_wrong())
		_tick(tag)
		_check(
			absf(before - _ax() - 1.0) <= 0.001,
			"%s: across a line break the hare moved %.1f chars instead of 1" % [tag, before - _ax()]
		)
		stepped += 1
	_check(stepped >= 1, "%s: no retreat happened (coverage)" % tag)
	_stack_is_solid(tag)
	_check(
		int(_main.cursor_line) <= line_before,
		"%s: the retreat moved the hare forward across lines" % tag
	)
	_common(tag)
	_finish_level(tag)


## 8. Конец уровня с метками: Enter продолжает, новый уровень чист.
func _case_level_end() -> void:
	_fresh(0, 1)
	var tag := "level end"
	for i in 4:
		_hard(_main._current())
		_tick(tag)
	for i in 3:
		_main._type_char(_wrong())
	_tick(tag)
	_finish_level(tag)
	if _main.state == "won":
		_enter()
		_tick(tag)
		_check(_main.state == "playing", "%s: Enter after the win did not start a level" % tag)
		_check(_main.errors.is_empty(), "%s: the new level kept the old marks" % tag)
		_check(_main.typed_bad == 0, "%s: the new level kept the old mistake counter" % tag)


## 9. Строгий регистр («все клавиши»): заглавная буква требует точной
## буквы, строчная — ошибка с честной меткой, и верная буква её гасит.
func _case_exact_case() -> void:
	_fresh(0, 1)
	var tag := "exact case"
	var found: bool = false
	for l in _main.display_lines.size():
		var line: String = _main.display_lines[l]
		for p in line.length():
			var ch := line.substr(p, 1)
			# Не первая клетка уровня: у первой откатываться некуда.
			if ch != ch.to_lower() and ch != " " and ch.to_upper() == ch and _main._is_active(ch) and (l > 0 or p > 0):
				found = true
				# Заяц ровно на этой заглавной букве.
				_main.cursor_line = l
				_main.cursor_pos = p
				_main.hero_r = _main._hero_pos()
				var before := _ax()
				# Строчная вместо заглавной — ошибка: метка и откат на символ.
				_main._type_char(ch.to_lower())
				_tick(tag)
				var mk: String = _main._key(l, p)
				_check(_main.errors.has(mk), "%s: a wrong case was accepted" % tag)
				_check(
					absf(before - _ax() - 1.0) <= 0.001,
					"%s: the hare did not step back one symbol on a wrong case" % tag
				)
				# Возвращаемся к отмеченной клетке: игра не должна её
				# перешагнуть (она ждёт верной буквы).
				var guard := 0
				while guard < 6 and _main.state == "playing":
					guard += 1
					if Vector2i(int(_main.cursor_line), int(_main.cursor_pos)) == Vector2i(l, p):
						break
					var want: String = _main._current()
					if want == "":
						break
					_main._type_char(want)
					_tick(tag)
				_check(
					_main.errors.has(mk),
					"%s: the game stepped over the marked cell" % tag
				)
				# Заглавная — верно: метка гаснет.
				_main._type_char(ch)
				_tick(tag)
				_check(not _main.errors.has(mk), "%s: the right case did not clear the mark" % tag)
				break
		if found:
			break
	_check(found, "%s: no uppercase letter to test (coverage)" % tag)


## 10. Ночная тема: та же связность, цвета живые.
func _case_night() -> void:
	_fresh(1, 0)
	_main.night = true
	var tag := "night"
	_check(_advance_to(0.3), "night: could not advance (coverage)")
	for i in 2:
		_main._type_char(_wrong())
	_tick(tag)
	_stack_is_solid(tag)
	_common(tag)
	# Буква под зайцем светлее автопропущенной и в ночной теме.
	var l := int(_main.cursor_line)
	var p := int(_main.cursor_pos)
	if l < _main.display_lines.size() and p < (_main.display_lines[l] as String).length():
		var ch := (_main.display_lines[l] as String).substr(p, 1)
		if not _main._is_active(ch):
			var probe := _active_probe(l, p)
			if probe.size() == 3:
				_check(
					_main._cell_color(l, p, ch, _main._key(l, p))
						== _main._cell_color(int(probe[0]), int(probe[1]), String(probe[2]), _main._key(int(probe[0]), int(probe[1]))),
					"%s: the wanted letter is not highlighted in the night theme" % tag
				)
	_main.night = false


## 11. Долгий хаос: кадр за кадром случайный ввод (верно/ошибка/
## Backspace/софт-символ/Enter), инварианты держатся каждый кадр.
func _case_chaos(frames: int) -> void:
	_fresh(2, 0)
	var tag := "chaos"
	var seed_v := 12345
	for i in frames:
		seed_v = (seed_v * 1103515245 + 12345) % 2147483648
		var roll := float(seed_v % 1000) / 1000.0
		if _main.state == "won" or _main.state == "lost":
			_enter()
		elif roll < 0.55:
			_hard(_main._current())
		elif roll < 0.78:
			_soft(_wrong())
		elif roll < 0.9:
			_back()
		else:
			_main._type_char(_wrong())
		_tick("%s %d" % [tag, i])


## 12. Дубль клавиши от IME: одна и та же буква дважды подряд — вторую
## игра глотит (живой лог 10.2026: «FLUSH;0;оо;о»). Меток от неё нет.
func _case_ime_duplicate() -> void:
	# Быстрые двойные буквы через прямой путь: фильтр дублей клавиши убит
	# вместе с системной клавиатурой (машинным дублям неоткуда взяться,
	# а человек вправе жать быстро). Две одинаковые буквы подряд — два
	# засчитанных знака, меток нет.
	_fresh(6, 1)
	_set_level_text(["Следы невиданных зверей!", "Они всё видели."])
	var tag := "ime duplicate"
	var cell := _find_double_letter()
	if cell.x < 0:
		_check(false, "%s: the test level lost its doubled letter" % tag)
		return
	_soft(_main._current())
	_soft(_main._current())
	_tick(tag)
	_check(_main.errors.is_empty(), "%s: the doubled letter left a mark" % tag)


## 13. Ошибка на последней букве уровня: уровень не должен завершиться,
## пока метка не снята, и обязан завершиться после её снятия.
func _case_last_cell() -> void:
	_fresh(0, 1)
	var tag := "last cell"
	# Идём до предпоследней клетки.
	var last := Vector2i(-1, -1)
	for l in _main.display_lines.size():
		last = Vector2i(l, (_main.display_lines[l] as String).length() - 1)
	while int(_main.cursor_line) != last.x or int(_main.cursor_pos) < last.y:
		var cur: String = _main._current()
		if cur == "":
			break
		_main._type_char(cur)
		_tick(tag)
		if _main.state != "playing":
			return
	var before_cell := Vector2i(int(_main.cursor_line), int(_main.cursor_pos))
	_main._type_char(_wrong())
	_tick(tag)
	_check(_main.state == "playing", "%s: the level finished with a mark on the last cell" % tag)
	# Метка остаётся там, где ребёнок споткнулся, а заяц отступает на
	# символ назад — как при любой другой ошибке.
	var mark: String = _main._key(before_cell.x, before_cell.y)
	_check(_main.errors.has(mark), "%s: no mark on the last cell" % tag)
	_check(
		Vector2i(int(_main.cursor_line), int(_main.cursor_pos)) == before_cell + Vector2i(0, -1),
		"%s: the hare did not step back one symbol from the last cell"
			% tag
	)
	# Первая верная буква проходит клетку ПОЗАДИ метки и упирается в
	# метку: игра не имеет права перешагнуть помеченную клетку.
	_main._type_char(_main._current())
	_tick(tag)
	_check(_main.state == "playing", "%s: the level finished while a mark was left" % tag)
	_check(_main.errors.has(mark), "%s: the mark was skipped without being typed" % tag)
	# Вторая верная буква — уже метка: уровень должен завершиться.
	_main._type_char(_main._current())
	_tick(tag)
	_check(_main.errors.is_empty(), "%s: the last mark survived the right letter" % tag)
	_check(_main.state == "won", "%s: the level did not finish after the fix (state %s)" % [tag, _main.state])


## 14. Проигрыш с метками на экране: табло застывает, Enter продолжает.
func _case_loss_with_marks() -> void:
	_fresh(3, 0)
	var tag := "loss"
	_check(_advance_to(0.25), "loss: could not advance (coverage)")
	for i in 3:
		_main._type_char(_wrong())
	_tick(tag)
	# Подгоняем ёжа вплотную: укол должен случиться по правилу.
	_main.grace_t = 0.0
	_main.hedge_active = true
	_main.enemy_line = int(_main.cursor_line)
	_main.enemy_x = _main.margin + (_ax() + _main._touch_chars() - 0.05) * _main.char_w
	var marks: int = _main.errors.size()
	_tick(tag)
	_tick(tag)
	_check(_main.state == "lost", "%s: no prick with the hedgehog at contact (state %s)" % [tag, _main.state])
	_check(_main.errors.size() == marks, "%s: the prick changed the marks" % tag)
	var ex: float = _main.enemy_x
	var hero: Vector2 = _main.hero_r
	for i in 10:
		_tick(tag)
	_check(
		absf(_main.enemy_x - ex) < 0.01 and _main.hero_r.distance_to(hero) < 0.01,
		"%s: the prick tableau is not frozen" % tag
	)
	# Enter после проигрыша начинает новый уровень, меток в нём нет.
	_enter()
	_tick(tag)
	_check(_main.state == "playing", "%s: Enter after the loss did not start a level" % tag)
	_check(_main.errors.is_empty(), "%s: the new level kept the marks" % tag)


## 15. Экранная клавиатура: тап по букве, по «стереть», мимо клавиатуры
## и на модалке. Это ввод, которым ребёнок играет на телефоне, и он идёт
## мимо key-событий (см. _own_press), поэтому проверять его отдельно.
func _kbd_on() -> void:
	_main._force_touch = true
	_main.kb_layer = _main.kb_lang


## Центры клавиш своей клавиатуры: «буква → точка».
func _kbd_buttons() -> Dictionary:
	var out := {}
	for b in Kbd.buttons(_main._own_rect(), _main.kb_layer, _main.kb_lang, _main.kb_shift):
		var rect: Rect2 = b["r"]
		var label := String(b["s"])
		out[label] = rect.get_center()
		if label == "пробел":
			out[" "] = rect.get_center()
	return out


func _case_touch_keyboard() -> void:
	_fresh(1, 0)
	_kbd_on()
	var tag := "touch kb"
	_check(_main._own_shown(), "%s: the own keyboard is not shown on a touch device" % tag)
	var want: String = _main._current()
	var btns := _kbd_buttons()
	# Заглавная — через шифт, ровно как жмёт ребёнок (в подсказке игры
	# для таких клеток так и написано). Сначала шифт, потом уже ищем
	# клавишу: на не сдвинутой раскладке заглавной просто нет.
	if want != want.to_lower() and btns.has("Shift"):
		_main._own_press(btns["Shift"])
		_tick(tag)
		btns = _kbd_buttons()
	_check(btns.has(want), "%s: the keyboard has no key «%s»" % [tag, want])
	var before := _ax()
	var ok0: int = _main.typed_ok
	if btns.has(want):
		_main._own_press(btns[want])
		_tick(tag)
	# Принятая буква двигает зайца дальше (серые символы проходятся сами),
	# поэтому мерим не расстояние, а честный приход: счётчик вырос на 1,
	# меток нет, курсор уехал вперёд.
	_check(_main.typed_ok == ok0 + 1, "%s: the tap was not accepted (%d → %d)" % [tag, ok0, _main.typed_ok])
	_check(_ax() > before, "%s: the tap did not advance the hare" % tag)
	_check(_main.errors.is_empty(), "%s: a correct tap left a mark" % tag)
	# Тап по неверной букве: метка и откат ровно на символ.
	var cur: String = _main._current()
	var wrong := "ы" if cur.to_lower() != "ы" else "ж"
	if btns.has(wrong):
		var b2 := _ax()
		_main._own_press(btns[wrong])
		_tick(tag)
		_common(tag)
		_check(absf(b2 - _ax() - 1.0) <= 0.001, "%s: a wrong tap moved the hare %.2f chars" % [tag, b2 - _ax()])
		_check(_main.errors.size() == 1, "%s: a wrong tap left %d marks" % [tag, _main.errors.size()])
		if btns.has("←"):
			_main._own_press(btns["←"])
			_tick(tag)
			_common(tag)
	# Тап мимо клавиатуры — не наш ввод.
	var marks0: int = _main.errors.size()
	_main._own_press(Vector2(4.0, 4.0))
	_tick(tag)
	_check(_main.errors.size() == marks0, "%s: a tap outside the keyboard changed the marks" % tag)


## 16. Шифт и язык на своей клавиатуре: регистр и переключение языка не
## должны терять курсор и метки.
func _case_kbd_shift_layer() -> void:
	_fresh(1, 1)   # «все клавиши»: регистр важен, иначе «А» вместо «а» — не ошибка
	_kbd_on()
	var tag := "shift/layer"
	var btns := _kbd_buttons()
	var base: String = _main._current().to_lower()
	if btns.has("Shift"):
		_main._own_press(btns["Shift"])
		_tick(tag)
		_check(_main.kb_shift, "%s: shift did not turn on" % tag)
		var up := _kbd_buttons()
		_check(up.has(base.to_upper()), "%s: no capital key after shift" % tag)
		# Проверять имеет смысл, только когда игра ждёт СТРОЧНУЮ: над
		# заглавной капитал верный и ошибкой не будет.
		if up.has(base.to_upper()) and _main._current() == base:
			_main._own_press(up[base.to_upper()])
			_tick(tag)
			_common(tag)
			_check(_main.errors.size() == 1, "%s: a wrong case over the keyboard was accepted" % tag)
			_main._own_press(_kbd_buttons()["←"])
			_tick(tag)
			_common(tag)
		_main.kb_shift = false
	# Язык туда-обратно: переключение не двигает зайца и не плодит метки.
	var before := _ax()
	var marks0: int = _main.errors.size()
	for i in 2:
		var bts := _kbd_buttons()
		_main._own_press(bts["глобус"])
		_tick(tag)
	_check(absf(_ax() - before) <= 0.001, "%s: switching the layer moved the hare" % tag)
	_check(_main.errors.size() == marks0, "%s: switching the layer made marks" % tag)


## 17. Свои клавиши «ё» и «ъ» (как на настоящей клавиатуре): жмутся
## напрямую, без долгого нажатия. Тап вводит букву, меток нет.
func _case_long_press() -> void:
	_kbd_on()
	var tag := "long press"
	var placed := false
	for attempt in 12:
		_fresh(2 + attempt / 4, 1)
		placed = _find_soft_letter(["ё", "ъ"])
		if placed:
			break
	if not placed:
		_check(false, "%s: no ё/ъ in the level (coverage)" % tag)
		return
	var btns := _kbd_buttons()
	var pressed: String = _main._current()
	_check(btns.has(pressed), "%s: the keyboard has no key «%s»" % [tag, pressed])
	if not btns.has(pressed):
		return
	var ok0: int = _main.typed_ok
	_main._own_press(btns[pressed])
	_tick(tag)
	_common(tag)
	_check(_main.typed_ok == ok0 + 1, "%s: the tap was not accepted (%d → %d)" % [tag, ok0, _main.typed_ok])
	_check(_main.errors.is_empty(), "%s: a direct key left a mark" % tag)


func _find_soft_letter(letters := ["е", "ь"]) -> bool:
	for l in _main.display_lines.size():
		var line: String = _main.display_lines[l]
		for p in line.length():
			if line.substr(p, 1) in letters and (l > 0 or p > 0):
				_main.cursor_line = l
				_main.cursor_pos = p
				_main.hero_r = _main._hero_pos()
				return true
	return false


## 26. Перераскладка посреди партии (поворот экрана, системная
## клавиатура выехала): оба героя обязаны остаться на своих местах по
## оси текста. Раньше ёж пересчитывался, а заяц нет — ёж уезжал один.
func _case_relayout() -> void:
	_fresh(2, 0)
	var tag := "relayout"
	_check(_advance_to(0.3), "%s: could not advance (coverage)" % tag)
	_main.grace_t = 0.0
	_main.hedge_active = true
	_main.enemy_line = int(_main.cursor_line)
	# Ставим ёжа на расстоянии 6 глифов позади: погоня идёт.
	_main.enemy_x = _main.margin + (_ax() - 6.0) * _main.char_w
	for i in 20:
		_main._process(DT)
	var d_before := _screen_gap()
	var cw_before: float = _main.char_w
	# Ужимаем окно: k, char_w и поля меняются — это и есть перераскладка.
	DisplayServer.window_set_size(Vector2i(520, 900))
	root.size = Vector2i(520, 900)
	_main._relayout()
	_tick(tag)
	_check(
		_main.char_w != cw_before,
		"%s: the relayout did not change the glyph width" % tag
	)
	var d_after := _screen_gap()
	_common(tag)
	_check(
		absf(d_after - d_before) < 1.5,
		"%s: the chase broke on the screen — gap %.1f → %.1f px" % [tag, d_before, d_after]
	)
	# Возвращаем окно и проверяем ещё раз: туда-обратно без разрыва.
	DisplayServer.window_set_size(Vector2i(820, 1180))
	_main._relayout()
	_tick(tag)
	_check(
		absf(_screen_gap() - d_before) < 1.5,
		"%s: the chase broke after the relayout back (gap %.1f → %.1f)"
			% [tag, d_before, _screen_gap()]
	)
	_common(tag)


## Пиксельный зазор между шарами: 0 = ровно касание (табло укола).
func _contact_px() -> float:
	return _main.hero_r.x - (_main.enemy_x + _main._hedge_half())


## Экранная дистанция между зайцем и ежом в символах оси: столько же,
## сколько по логике (_lin). Её разрыв = ёж уехал один, без зайца.
func _screen_gap() -> float:
	var h: float = _main._lin(int(_main.cursor_line), float(_main.cursor_pos))
	var e: float = _main._lin(int(_main.enemy_line), (_main.enemy_x - _main.margin) / _main.char_w)
	return (_main.hero_r.x - (_main.enemy_x + _main._hedge_half())) / _main.char_w - (h - e)


## 27. Своя клавиатура обязана помещаться на экране при ЛЮБОЙ ориентации:
## в альбомной она по ширине выходит выше экрана и съедает раскладку
## (визуальный прогон 10.2026). Проверяем на телефонах обеих ориентаций:
## клавиатура занимает меньше половины экрана, стоит внутри окна, клавиши
## не плоские и все попадают в палец.
func _case_own_kbd_fits() -> void:
	_kbd_on()
	var tag := "own kbd fit"
	var old := root.size
	# Портрет телефона, альбом телефона, маленький телефон в альбоме.
	for wh in [Vector2i(1080, 2340), Vector2i(2340, 1080), Vector2i(1280, 720), Vector2i(960, 540)]:
		DisplayServer.window_set_size(wh)
		root.size = wh
		_main._relayout()
		_tick(tag)
		var r: Rect2 = _main._own_rect()
		_check(r.size.y <= _main.view_h * 0.5, "%s: the keyboard takes %.0f%% of a %s screen" % [tag, 100.0 * r.size.y / maxf(1.0, _main.view_h), str(wh)])
		_check(r.size.y > 100.0, "%s: the keyboard vanished on %s (h=%.0f)" % [tag, str(wh), r.size.y])
		_check(
			r.position.y + r.size.y <= _main.view_h + 1.0,
			"%s: the keyboard hangs off the bottom on %s (bottom=%.0f of %.0f)" % [tag, str(wh), r.position.y + r.size.y, _main.view_h]
		)
		_check(r.position.x >= 0.0 and r.position.x + r.size.x <= _main.view_w + 1.0, "%s: the keyboard hangs off the side on %s" % [tag, str(wh)])
		# Текст обязан остаться: под клавиатурой — минимум половина экрана.
		_check(
			_main._eff_h() >= _main.view_h * 0.45,
			"%s: only %.0f px of text left on %s" % [tag, _main._eff_h(), str(wh)]
		)
		# Физическая раскладка: у буквенных клавиш (включая ё/ъ)
		# одинаковая ширина на всех рядах; стереть — двойное сверху
		# справа (как настоящий Backspace); ввод справа от «э» (как
		# настоящий Enter); два шифта по бокам нижнего ряда. Ступеньки
		# ф/я идут от ширины шифтов (1:2, как Tab→Caps→Shift).
		var letter_w := -1.0
		var row_x := {}
		var shift_xs := []
		var bs_w := -1.0
		var bs_y := -1.0
		var enter_w := -1.0
		var enter_y := -1.0
		var digit_w := -1.0
		var yo_w := -1.0
		for b in Kbd.buttons(r, _main.kb_layer, _main.kb_lang, _main.kb_shift):
			var kr: Rect2 = b["r"]
			var lab := String(b["s"])
			# «ё» живёт в цифровом ряду своим калибром — меряем отдельно.
			var is_letter := lab.length() == 1 and ((lab >= "а" and lab <= "я") or (lab >= "А" and lab <= "Я")) and lab != "ё" and lab != "Ё"
			if is_letter:
				if letter_w < 0.0:
					letter_w = kr.size.x
				else:
					_check(
						absf(kr.size.x - letter_w) <= 1.0,
						"%s: the key «%s» is %.0fpx, expected %.0f like the rest on %s"
							% [tag, lab, kr.size.x, letter_w, str(wh)]
					)
				var key := int(kr.get_center().y)
				if not row_x.has(key):
					row_x[key] = kr.position.x
				else:
					row_x[key] = minf(float(row_x[key]), kr.position.x)
			elif lab == "Shift" or lab == "ShiftR":
				shift_xs.append(kr.size.x)
				_check(
					absf(kr.position.x - r.position.x) <= 1.0 or absf(kr.end.x - r.end.x) <= 1.0,
					"%s: a shift hangs off the keyboard edges on %s" % [tag, str(wh)]
				)
			elif lab == "←":
				bs_w = kr.size.x
				bs_y = kr.get_center().y
			elif lab == "↵":
				enter_w = kr.size.x
				enter_y = kr.get_center().y
			elif lab.length() == 1 and ((lab >= "0" and lab <= "9") or lab in ["ё", "-", "="]):
				if lab == "ё" or lab == "Ё":
					yo_w = kr.size.x
				elif digit_w < 0.0:
					digit_w = kr.size.x
		# Стереть сверху справа, не меньше 48px. Цифры (включая ё) —
		# тем же питчем, что буквы.
		_check(bs_w >= 32.0, "%s: erase is %.0fpx on %s" % [tag, bs_w, str(wh)])
		_check(yo_w <= 0.0 or absf(yo_w - digit_w) <= 1.0, "%s: yo is %.0fpx, expected digit pitch %.0f on %s" % [tag, yo_w, digit_w, str(wh)])
		if digit_w > 0.0 and bs_w > 0.0:
			_check(
				absf(bs_w - 2.0 * digit_w) <= 2.0,
				"%s: erase is %.0fpx, expected double digit (%.0f) on %s" % [tag, bs_w, digit_w, str(wh)]
			)
		# Правая колонка как на настоящей: стереть сверху, ввод
		# посередине (справа от «э»), оба у правого края. Ввод не меньше
		# 1.2 питча — маленький не нажать.
		_check(enter_w >= 32.0, "%s: no usable enter key on %s" % [tag, str(wh)])
		if letter_w > 0.0:
			_check(
				enter_w >= 1.2 * letter_w - 1.0,
				"%s: enter is %.0fpx, expected at least 1.2 keys (%.0f) on %s"
					% [tag, enter_w, letter_w, str(wh)]
			)
		if bs_y >= 0.0 and enter_y >= 0.0:
			_check(bs_y < enter_y, "%s: erase is not above enter on %s" % [tag, str(wh)])
		# Два шифта (как на настоящей: левый и правый разной ширины)
		# и оба не меньше пальца.
		_check(shift_xs.size() == 2, "%s: expected two shifts, got %d on %s" % [tag, shift_xs.size(), str(wh)])
		for shw in shift_xs:
			_check(float(shw) >= 32.0, "%s: a shift is %.0fpx on %s" % [tag, float(shw), str(wh)])
		var ys := row_x.keys()
		ys.sort()
		# Буквенные ряды — второй, третий и четвёртый сверху.
		if ys.size() >= 4:
			var x0 := float(row_x[ys[1]])
			var x1 := float(row_x[ys[2]])
			var x2 := float(row_x[ys[3]])
			_check(x1 > x0, "%s: the second letter row is not stepped right (%.0f vs %.0f) on %s" % [tag, x1, x0, str(wh)])
			_check(x2 > x1, "%s: the third letter row is not stepped right (%.0f vs %.0f) on %s" % [tag, x2, x1, str(wh)])
			_check(
				absf((x2 - x1) - 2.0 * (x1 - x0)) <= 8.0,
				"%s: steps %.0f/%.0f, expected 1:2 like the reference" % [tag, x1 - x0, x2 - x1]
			)
		# Клавиши: квадратные (палец), внутри своей области, все на месте.
		var btns := _kbd_buttons()
		_check(btns.size() >= 40, "%s: only %d keys on %s" % [tag, btns.size(), str(wh)])
		for b in Kbd.buttons(r, _main.kb_layer, _main.kb_lang, _main.kb_shift):
			var kr: Rect2 = b["r"]
			var lab := String(b["s"])
			# Широкие по замыслу (пробел, глобус, шифт, стрелки) — их
			# пропускаем в проверке пропорций: там не клетка, а полоса.
			if lab.length() > 1:
				continue
			_check(
				kr.size.x > 24.0 and kr.size.y > 24.0,
				"%s: the key «%s» is %.0fx%.0f on %s — finger won't hit it" % [tag, lab, kr.size.x, kr.size.y, str(wh)]
			)
			_check(
				kr.size.x / maxf(1.0, kr.size.y) < 2.2,
				"%s: the key «%s» is flat (%.2f) on %s" % [tag, lab, kr.size.x / maxf(1.0, kr.size.y), str(wh)]
			)
			_check(r.encloses(kr), "%s: the key «%s» is outside the keyboard on %s" % [tag, lab, str(wh)])
	_common(tag)
	DisplayServer.window_set_size(old)
	root.size = old
	_main._relayout()


## 28. Свои клавиши «ё» и «ъ» (как на настоящей клавиатуре): игра их
## ждёт, клавиши есть, подсказка про долгое нажатие больше не нужна —
## буква печатается прямым нажатием, как любая другая.
func _case_yo_hint() -> void:
	_kbd_on()
	var tag := "yo hint"
	# «ё» и «ъ» — обычные буквы на высокой ступени. Уровень задаём свой,
	# чтобы сценарий не зависел от фрагмента.
	_fresh(24, 1)
	_set_level_text(["Ёжик ел ёжика и ёл ёршик."])
	if not _find_soft_letter(["ё", "ъ"]):
		_check(false, "%s: the test level lost its ё/ъ" % tag)
		return
	var cur: String = _main._current()
	var btns := _kbd_buttons()
	_check(btns.has(cur), "%s: the keyboard has no key «%s»" % [tag, cur])
	if not btns.has(cur):
		return
	# Подсказка молчит про долгое нажатие: его больше нет.
	var hint: String = _main._hint_text()
	_check(not hint.contains("Долго"), "%s: the dead long-press hint is back (%s)" % [tag, hint])
	# А прямое нажатие вводит букву без меток.
	var ok0: int = _main.typed_ok
	_main._own_press(btns[cur])
	_tick(tag)
	_common(tag)
	_check(_main.typed_ok == ok0 + 1, "%s: the tap was not accepted" % tag)
	_check(_main.errors.is_empty(), "%s: a direct key left a mark" % tag)


## Ширина строки подсказки в пикселях — та же сумма, что рисует _draw_hint.
func _hint_width() -> float:
	var fs: int = int(30.0 * _main.k)
	var gap: float = 12.0 * _main.k
	var total := 0.0
	for p in _main._hint_parts():
		var s := String(p["s"])
		total += _main.mono.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs).x
		if bool(p["cap"]):
			total += 32.0 * _main.k
	total += gap * float(maxi(0, _main._hint_parts().size() - 1))
	return total


## 29. Телефон подвис: уход в фон, звонок, тяжёлый кадр — движок отдаёт
## дельту в секунды. За один такой кадр ёж проезжал десятки символов, и
## ребёнок возвращался к «Ёж догнал!», ни на что не нажимая. Игровое
## время обязано жить по ограниченной дельте: партия продолжается, а
## часы партии не прыгают.
func _case_frame_spike() -> void:
	_fresh(3, 1)
	var tag := "frame spike"
	for spike in [0.05, 0.2, 0.5, 2.0, 8.0]:
		# Самая злая расстановка: ёж через три символа и на максимальной
		# скорости — одно движение, и закат.
		_main.state = "playing"
		_main.cursor_line = 0
		_main.cursor_pos = 5
		_main.hero_r = _main._hero_pos()
		_main.grace_t = 0.0
		_main.hedge_active = true
		_main.enemy_line = 0
		_main.enemy_cps = B.MAX_CPS
		_main.enemy_x = _main.margin + 2.0 * _main.char_w
		_main.elapsed = 30.0
		var t0: float = _main.elapsed
		_main._process(spike)
		var t1: float = _main.elapsed
		_check(
			_main.state == "playing",
			"%s: dt=%.2f ended the level by itself (%s)" % [tag, spike, _main.state]
		)
		_check(
			t1 - t0 <= _main.MAX_FRAME_DT + 0.001,
			"%s: dt=%.2f jumped the level clock by %.2f s" % [tag, spike, t1 - t0]
		)
		# И ёж за кадр проезжает столько же, сколько за обычный медленный
		# кадр — не десятки символов.
		var h0: float = _main._lin(0, (_main.enemy_x - _main.margin) / _main.char_w)
		_main._process(_main.MAX_FRAME_DT)
		var h1: float = _main._lin(int(_main.enemy_line), (_main.enemy_x - _main.margin) / _main.char_w)
		_check(
			h1 - h0 <= 4.0,
			"%s: dt=%.2f sent the hedgehog %.1f chars in one frame" % [tag, spike, h1 - h0]
		)
		_tick(tag)
		_common(tag)


## 30. Испорченный (или руками правленый) профиль. Игра доверяет файлу
## всему: enemy_cps = 1000000 — и ёж убивает на первом же кадре, а
## значение переписывается обратно при каждом конце уровня. Игрок
## оказывается в тупике, из которого нельзя выйти ни одной победой.
## Проверяем, что игра сама приводит мусор к допустимому виду.
func _case_broken_profile() -> void:
	var tag := "broken profile"
	var who := "битый-профиль"
	S.create_user(who)
	var cfg := ConfigFile.new()
	cfg.load(S.PATH)
	cfg.set_value(
		S.SECTION_PROFILES,
		who,
		{
			"all_keys": true,
			"yo_strict": false,
			"difficulty": 99999,
			"wins_in_row": 1000000,
			"ema_cpm": -5.0,
			"ema_acc": 42.0,
			"enemy_cps": 1000000.0,
			"last_played": 0,
		}
	)
	cfg.save(S.PATH)
	# Загрузка профиля живёт в _start_game (там же релэут и новый уровень).
	_main.profile_name = who
	_main._start_game()
	_tick(tag)
	_check(
		_main.enemy_cps >= B.MIN_CPS and _main.enemy_cps <= B.MAX_CPS,
		"%s: the hedgehog speed %.0f cps is outside the playable range" % [tag, _main.enemy_cps]
	)
	_check(
		_main.difficulty <= B.KEY_PROGRESSION.length(),
		"%s: the difficulty %d is beyond the key set" % [tag, _main.difficulty]
	)
	_check(
		_main.wins_in_row < B.WINS_TO_LEVEL_UP,
		"%s: the win streak %d jumps a level on the first win" % [tag, _main.wins_in_row]
	)
	_check(
		_main.ema_acc >= 0.0 and _main.ema_acc <= 1.0,
		"%s: the accuracy %.1f is not a share" % [tag, _main.ema_acc]
	)
	_check(_main.ema_cpm >= 0.0, "%s: the speed %.1f is negative" % [tag, _main.ema_cpm])
	# Уровень должен быть играбельным: первый кадр не убивает.
	_check(_main.state == "playing", "%s: the level did not start (%s)" % [tag, _main.state])
	_check(not _main.display_lines.is_empty(), "%s: the level is empty" % tag)
	_main.hedge_active = true
	_main.grace_t = 0.0
	_main.enemy_line = int(_main.cursor_line)
	_main.enemy_x = _main.margin + (_main._lin(int(_main.cursor_line), 0.0) - 4.0) * _main.char_w
	_main._process(_main.MAX_FRAME_DT)
	_check(
		_main.state == "playing",
		"%s: the hedgehog killed on the first frame after loading" % tag
	)
	# Мусор не должен утечь в тексты: ни «nan», ни «inf» в подсказке или
	# табло (счётчики форматируются из профиля).
	var shown := "%s | %s" % [_main._hint_text(), _main._speed_word(int(_main.ema_cpm))]
	_check(
		not shown.contains("nan") and not shown.contains("inf"),
		"%s: the garbage leaked into the screen text (%s)" % [tag, shown]
	)
	_common(tag)
	S.delete_user(who)
	_main.profile_name = S.GUEST
	_main._start_game()


## 31. Своя клавиша рядом с серыми клетками: игра ждёт «е», а сразу
## за ним серая клетка. Нажатие вводит букву напрямую, заяц уходит
## дальше через автопропуск — чисто, без меток и лишних событий.
func _case_long_press_grey() -> void:
	_kbd_on()
	var tag := "long press grey"
	# «е» входит в набор букв на девятой ступени (КЛЮЧИ идут по
	# прогрессии), а дальше по строке идут серые клетки — их и требуем.
	_fresh(9, 0)
	_set_level_text(["Он ест еду и ест мёд."])
	if not _find_active_soft_before_grey():
		_check(false, "%s: no active е/ь before a grey cell in the test level" % tag)
		return
	var btns := _kbd_buttons()
	var ch: String = _main._current()
	if not btns.has(ch):
		_check(false, "%s: no key «%s»" % [tag, ch])
		return
	var marks0: int = _main.errors.size()
	var ok0: int = _main.typed_ok
	var bad0: int = _main.typed_bad
	_main._own_press(btns[ch])
	_tick(tag)
	_common(tag)
	_check(
		_main.errors.size() == marks0,
		"%s: a direct key next to grey cells left %d marks" % [tag, _main.errors.size() - marks0]
	)
	_check(
		_main.typed_ok == ok0 + 1 and _main.typed_bad == bad0,
		"%s: the tap counted oddly (%d+%d → %d+%d)"
			% [tag, ok0, bad0, _main.typed_ok, _main.typed_bad]
	)


## Ставит зайца перед «е»/«ь», которую игра ЖДЁТ, а сразу после неё —
## серая клетка (её автопропуск и сбивал откат).
func _find_active_soft_before_grey() -> bool:
	for l in _main.display_lines.size():
		var line: String = _main.display_lines[l]
		for p in line.length() - 1:
			var ch := line.substr(p, 1)
			if not (ch in ["е", "ь"]):
				continue
			if not _main._is_active(ch):
				continue
			var next := line.substr(p + 1, 1)
			if next != " " and not _main._is_active(next):
				_main.cursor_line = l
				_main.cursor_pos = p
				_main.hero_r = _main._hero_pos()
				return true
	return false


## 32. Поворот экрана с метками на экране. Вёрстка пересобирается, и
## клетки едут; метка обязана остаться на ТОЙ ЖЕ букве. Молча пропасть
## нельзя: метка — это «здесь ошибка», и исчезновение ошибки в момент
## поворота телефона выглядит как баг (жалоба автора на «текст поехал»).
func _case_rotate_with_marks() -> void:
	_fresh(5, 1)
	var tag := "rotate marks"
	_check(_advance_to(0.35), "%s: could not advance (coverage)" % tag)
	# Четыре ошибки подряд в разных местах текста.
	var was := {}
	for i in 4:
		_main._type_char(_wrong())
		_tick(tag)
		was[_main._key(int(_main.cursor_line), int(_main.cursor_pos))] = ""
	for k in was.keys():
		if _main.errors.has(k):
			var parts := String(k).split(":")
			was[k] = String(_main.display_lines[int(parts[0])]).substr(int(parts[1]), 1)
	_check(_main.errors.size() >= 3, "%s: only %d marks to check" % [tag, _main.errors.size()])
	var old_size := root.size
	DisplayServer.window_set_size(Vector2i(560, 900))
	root.size = Vector2i(560, 900)
	_main._relayout()
	_tick(tag)
	var lost := 0
	var moved := 0
	for k in was.keys():
		var parts := String(k).split(":")
		var letter := String(was[k])
		if letter == "":
			continue
		# Метка после переноса обязана стоять на той же букве.
		var found := ""
		for k2 in _main.errors.keys():
			var p2 := String(k2).split(":")
			if (
				int(p2[0]) < _main.display_lines.size()
				and int(p2[1]) < String(_main.display_lines[int(p2[0])]).length()
				and String(_main.display_lines[int(p2[0])]).substr(int(p2[1]), 1) == letter
			):
				found = k2
				break
		if found == "":
			lost += 1
		elif found != k:
			moved += 1
	_common(tag)
	_check(
		lost == 0,
		"%s: %d marks vanished on the screen rotation" % [tag, lost]
	)
	DisplayServer.window_set_size(old_size)
	root.size = old_size
	_main._relayout()


## 33. Символы, которых нет на буквенном слое (':', ';', скобки):
## подсказка обязана учить шифту с верхней цифры (как на настоящей
## клавиатуре), иначе набирать нечем. Тот же принцип, что и с «ё»:
## игра просит то, что нельзя нажать.
func _case_sym_layer_hint() -> void:
	# Знаки препинания на настоящей клавиатуре — шифт с верхней цифры
	# (Shift+6 даёт «:»), а не слой ?123: мы учим человека реальной
	# клавиатуре (требование автора 10.2026). Подсказка и подсветка
	# обязаны учить именно этому, а нажатие — давать знак.
	_kbd_on()
	var tag := "sym hint"
	_fresh(6, 1)
	_set_level_text(["Дверь: открыта - тихо."])
	if not _find_shift_symbol():
		_check(false, "%s: the test level lost its symbol" % tag)
		return
	var want: String = _main._current()
	var digit: String = Kbd.digit_for(want)
	_check(digit != "", "%s: «%s» has no Shift+digit way" % [tag, want])
	if digit == "":
		return
	var hint: String = _main._hint_text()
	_check(hint.contains("Shift"), "%s: the hint does not teach Shift (%s)" % [tag, hint])
	_check(hint.contains(digit), "%s: the hint does not name [%s] (%s)" % [tag, digit, hint])
	# Ввод по подсказке: шифт, потом цифра — знак принимается без меток,
	# а слой не переключается (он для этого не нужен).
	var btns := _kbd_buttons()
	if not btns.has("Shift") or not btns.has(digit):
		_check(false, "%s: no Shift/%s keys" % [tag, digit])
		return
	var ok0: int = _main.typed_ok
	_main._own_press(btns["Shift"])
	_tick(tag)
	_check(_main.kb_shift, "%s: shift did not arm" % tag)
	btns = _kbd_buttons()
	_main._own_press(btns[digit])
	_tick(tag)
	_check(
		_main.typed_ok == ok0 + 1,
		"%s: Shift+%s did not type «%s» (%d → %d)" % [tag, digit, want, ok0, _main.typed_ok]
	)
	_check(_main.errors.is_empty(), "%s: the symbol left a mark" % tag)
	_check(not _main.kb_shift, "%s: shift stuck after the symbol" % tag)
	_common(tag)


## Ставит зайца перед символом со сдвигом (":" и компания набираются
## шифтом с цифры (':', '-', ';', '"', "'", '(', ')').
func _find_shift_symbol() -> bool:
	var only := [":", ";", '"', "'", "(", ")"]
	for l in _main.display_lines.size():
		var line: String = _main.display_lines[l]
		for p in line.length():
			if line.substr(p, 1) in only:
				_main.cursor_line = l
				_main.cursor_pos = p
				_main.hero_r = _main._hero_pos()
				return true
	return false


## 34. Быстрые двойные буквы («сс», «лл», «баба», «папа»). Игра гасит
## ДУБЛЬ клавиши от IME: одинаковая буква, пришедшая следом за такой же
## через миг, считается повтором клавиши. Набирать надо уметь быстро —
## и двойная НЕ должна попасть под гашение. Плюс Backspace сразу после
## долгого нажатия: откат должен работать как обычно.
func _case_fast_doubles() -> void:
	_fresh(6, 1)
	var tag := "fast doubles"
	# «нн» — единственная двойная буква во всём банке текстов; ловить её
	# в случайном фрагменте бессмысленно (на CI сценарий валился по
	# coverage), поэтому уровень задаём свой. Ступень 13 — «н» там своя
	# буква: иначе игра проходит серые клетки сама и вторую «н» ждать
	# просто не на чем.
	_fresh(13, 0)
	_set_level_text(["Следы невиданных зверей!", "Они всё видели."])
	var cell := _find_double_letter()
	if cell.x < 0:
		_check(false, "%s: the test level lost its doubled letter" % tag)
		return
	var pair: String = _main._current()
	var ok0: int = _main.typed_ok
	# Две одинаковые буквы подряд, без единого кадра между ними.
	_main._type_char(pair)
	_main._type_char(pair)
	_tick(tag)
	_check(
		_main.typed_ok == ok0 + 2,
		"%s: the doubled «%s» was eaten as a duplicate key (%d → %d)"
			% [tag, pair, ok0, _main.typed_ok]
	)
	_check(_main.errors.is_empty(), "%s: the doubled letter left a mark" % tag)
	_check(
		int(_main.cursor_line) == cell.x and int(_main.cursor_pos) == cell.y + 2,
		"%s: the hare is at %d:%d, expected %d:%d"
			% [tag, _main.cursor_line, _main.cursor_pos, cell.x, cell.y + 2]
	)
	_common(tag)


## Свой текст уровня. Сценарии не должны зависеть от того, какой случайный
## фрагмент выпал: двойная буква «нн» есть ровно в одной строке банка,
## и на CI сценарий «быстрые двойные» валился по coverage (10.2026).
func _set_level_text(lines: Array) -> void:
	var typed: Array[String] = []
	for l in lines:
		typed.append(String(l))
	_main.display_lines = typed
	_main.line_drops = []
	_main._reindex_lines()
	# Набор букв — штатный для этой сложности (не «все буквы текста»):
	# часть сценариев проверяет именно серые клетки.
	_main.active = B.active_chars(_main.difficulty)
	_main.cursor_line = 0
	_main.cursor_pos = 0
	_main.hero_r = _main._hero_pos()
	_main.state = "playing"
	_main.errors.clear()
	_main.passed.clear()
	_main.typed_cells.clear()
	_main._refresh()


## Ставит зайца на первую из двух одинаковых букв подряд («сс», «папа»).
func _find_double_letter() -> Vector2i:
	for l in _main.display_lines.size():
		var line: String = _main.display_lines[l]
		for p in line.length() - 1:
			if line.substr(p, 1) == line.substr(p + 1, 1) and line.substr(p, 1) != " ":
				_main.cursor_line = l
				_main.cursor_pos = p
				_main.hero_r = _main._hero_pos()
				return Vector2i(l, p)
	return Vector2i(-1, -1)


## 35. Backspace после своей клавиши «ё»: буква убирается, заяц
## встаёт на её место, меток нет. Путь этот трогали только в одну
## сторону, когда было долгое нажатие.
func _case_long_press_then_backspace() -> void:
	_kbd_on()
	var tag := "long then backspace"
	_fresh(24, 1)
	_set_level_text(["Ёлка и ёлка, ёжик."])
	if not _find_soft_letter(["ё", "ъ"]):
		_check(false, "%s: the test level lost its ё/ъ" % tag)
		return
	var btns := _kbd_buttons()
	var ch: String = _main._current()
	if not btns.has(ch):
		_check(false, "%s: no key «%s»" % [tag, ch])
		return
	# Прямое нажатие «ё»: меток нет, заяц ушёл дальше.
	_main._own_press(btns[ch])
	_tick(tag)
	_check(_main.errors.is_empty(), "%s: the direct key left a mark" % tag)
	# Сразу Backspace: буква должна убраться, заяц — встать на её место.
	var after := Vector2i(int(_main.cursor_line), int(_main.cursor_pos))
	_main._backspace()
	_tick(tag)
	_common(tag)
	_check(
		int(_main.cursor_line) <= after.x and int(_main.cursor_pos) <= after.y,
		"%s: backspace moved the hare forward (%d:%d → %d:%d)"
			% [tag, after.x, after.y, _main.cursor_line, _main.cursor_pos]
	)
	_check(
		_main.errors.is_empty(),
		"%s: backspace after the key left marks" % tag
	)
	# И повторное нажатие снова печатает.
	var ok: int = _main.typed_ok
	_main._own_press(_kbd_buttons()[ch])
	_tick(tag)
	_check(_main.typed_ok == ok + 1, "%s: the second press did not type" % tag)


## 38. Быстрый ввод со своей клавиатуры: тапы и стереть по кадрам.
## Серий IME (DEL + перепись региона) больше нет: каждый тап — буква
## в игру напрямую. Держим инварианты честности на каждом шаге.
func _case_ime_frames() -> void:
	for seed0 in [987654321, 24681357, 13579246, 112233445]:
		_ime_frames_run(seed0)


func _ime_frames_run(seed_v: int) -> void:
	var tag := "ime frames"
	_advance_to(0.25)
	var word := ["о", "б", "с", "т", "р", "а", "х", "й", "у", "м", "к", "н"]
	for step in 140:
		seed_v = (seed_v * 1103515245 + 12345) % 2147483648
		match seed_v % 5:
			0:
				# Серия DEL, размазанная по кадрам.
				for i in 1 + (seed_v % 3):
					_back()
					_tick(tag)
			1:
				# Буква приходит отдельным кадром (обычный набор).
				_soft(word[seed_v % word.size()])
				_tick(tag)
			2:
				# Стирание и буква разными кадрами (медленный ввод).
				_back()
				_tick(tag)
				_soft(word[seed_v % word.size()])
				_tick(tag)
			3:
				# Переписка слова: DEL'ы одним куском, потом слово.
				for i in 2 + (seed_v % 3):
					_back()
				for i in 3 + (seed_v % 3):
					_soft(word[seed_v % word.size()])
					_tick(tag)
			_:
				# Дубль одной буквы (машинный).
				var ch: String = word[seed_v % word.size()]
				_soft(ch)
				_soft(ch)
				_tick(tag)
		if _main.state != "playing":
			_finish_level(tag)
			_advance_to(0.2)
		_common(tag)


## 40. Подсветка клавиши после простоя — вместо текстовых «Нажми К».
## Рано (игрок ещё думает сам) — пусто; после задержки нужная клавиша
## подсвечивается на самой клавиатуре; заглавная — парой [шифт
## противоположной руки, буква]; знак — парой [шифт, цифра]; пробел —
## половиной по правилу противоположной руки; метки зовут клавишу
## «стереть»; капслок гасится текстом. Задержка адаптивная: вдвое больше
## среднего периода нажатий игрока.
func _case_idle_hint() -> void:
	_fresh(1, 1)
	var tag := "idle hint"
	_check(_advance_to(0.3), "%s: could not advance (coverage)" % tag)
	# Рано — пусто.
	# Темп задаём сами: средний период 0.6 с → задержка 1.2 с.
	_main.press_ema = 0.6
	_main.idle_t = 0.0
	_check(_main._hint_keys().is_empty(), "%s: highlight before the delay" % tag)
	_main.idle_t = _main._hint_delay() - 0.01
	_check(_main._hint_keys().is_empty(), "%s: highlight just before the delay" % tag)
	# После задержки — клавиша под курсором.
	_main.idle_t = _main._hint_delay() + 0.5
	var cur: String = _main._current()
	var keys: Array = _main._hint_keys()
	_check(not keys.is_empty(), "%s: no highlight after the delay" % tag)
	if cur == cur.to_upper() and cur != cur.to_lower():
		var want_shift := "ShiftR" if Kbd.hand_of(cur) == "Л" else "Shift"
		_check(
			keys == [want_shift, cur.to_lower()],
			"%s: capital highlights %s, expected the opposite shift plus the letter" % [tag, str(keys)]
		)
	else:
		# Пробел отдельно: встаём на него принудительно (в случайном
		# тексте его может не оказаться под курсором).
		_check(_find_space_cell(), "%s: no space cell to stand on" % tag)
		if not Kbd.is_plain_letter(cur):
			pass
		else:
			_check(keys == [cur], "%s: highlights %s, expected [%s]" % [tag, str(keys), cur])
	# Пробел — половиной по правилу противоположной руки.
	_main.last_hand = "Л"
	_check(_main._hint_keys() == ["пробел:П"], "%s: after a left letter: %s" % [tag, str(_main._hint_keys())])
	_main.last_hand = "П"
	_check(_main._hint_keys() == ["пробел:Л"], "%s: after a right letter: %s" % [tag, str(_main._hint_keys())])
	_main.last_hand = ""
	_check(_main._hint_keys() == ["пробел:П"], "%s: with no history: %s" % [tag, str(_main._hint_keys())])
	# Любое нажатие гасит подсветку: игрок снова думает сам.
	_main._type_char(cur)
	_tick(tag)
	_check(_main._hint_keys().is_empty(), "%s: the highlight survived a keypress" % tag)
	# Метки зовут клавишу «стереть» на самой доске, а не текст.
	_main._type_char(_wrong())
	_main.idle_t = _main._hint_delay() + 5.0
	_tick(tag)
	_check(_main._hint_keys() == ["←"], "%s: marks highlight %s, expected the erase key" % [tag, str(_main._hint_keys())])
	_check(not _main._hint_text().contains("Стереть"), "%s: the old erase text is back (%s)" % [tag, _main._hint_text()])
	# Символа нет на слое — подсвечивается пара [Shift, цифра].
	_main.errors.clear()
	_main.cursor_line = 0
	for p in String(_main.display_lines[0]).length():
		if String(_main.display_lines[0]).substr(p, 1) == ":":
			_main.cursor_pos = p
			break
	if _main._current() == ":":
		_main.kb_layer = "ru"
		_main.hero_r = _main._hero_pos()
		_main.idle_t = _main._hint_delay() + 0.5
		_tick(tag)
		_check(
			_main._hint_keys() == ["Shift", "6"],
			"%s: off-layer symbol highlights %s, expected shift plus the digit"
				% [tag, str(_main._hint_keys())]
		)
	# Адаптивность: смена темпа двигает задержку (2×EMA).
	_main.press_ema = 2.0
	_check(absf(_main._hint_delay() - 4.0) < 0.01, "%s: slow pace gives %.1fs, expected 4.0" % [tag, _main._hint_delay()])
	_main.idle_t = 3.0
	_check(_main._hint_keys().is_empty(), "%s: the old delay still fires" % tag)
	_main.press_ema = 0.6
	_main.idle_t = 3.0
	_check(not _main._hint_keys().is_empty(), "%s: the faster delay does not fire" % tag)
	_common(tag)


## Ставит зайца на первый пробел первой строки (для проверки половин).
func _find_space_cell() -> bool:
	var line: String = _main.display_lines[0]
	for p in line.length():
		if line.substr(p, 1) == " ":
			_main.cursor_line = 0
			_main.cursor_pos = p
			_main.hero_r = _main._hero_pos()
			_main.errors.clear()
			_main.idle_t = _main._hint_delay() + 0.5
			return _main._current() == " "
	return false


## 41. Перенос строк везёт за собой ВСЕ клеточные множества — и typed_cells
## тоже. Открытие меню прячет клавиатуру, смена ширины пересобирает
## строки, а курсор, пройденное и метки едут по логической оси. Раньше
## typed_cells оставался на старых клетках: метка, поставленная секунду
## назад, оказывалась «вне набранного», а Backspace после поворота искал
## набранное не там. Ловил флаки-тестом menu_roundtrip (10.2026).
func _case_reflow_typed_cells() -> void:
	_fresh(6, 1)
	var tag := "reflow typed"
	# Длинные строки: при сужении окна переносы меняются гарантированно,
	# а не «если повезёт с фрагментом».
	_set_level_text([
		"Следы невиданных зверей на полях и на лесных тропинках!",
		"Они всё видели и всё слышали в ночной тишине.",
		"Лисица тут же придумала хитрый и коварный план.",
	])
	_check(_advance_to(0.3), "%s: could not advance (coverage)" % tag)
	var letters: Array = []
	for i in 3:
		_main._type_char(_wrong())
		_tick(tag)
		# Метка ставится на клетку курсора ДО отката — фиксируем её букву.
		# Ключи после переноса меняются, поэтому сравниваем мультимножества.
		letters.clear()
		for mk in _main.errors.keys():
			var parts := String(mk).split(":")
			letters.append(String(_main.display_lines[int(parts[0])]).substr(int(parts[1]), 1))
		letters.sort()
	_check(_main.errors.size() == 3, "%s: expected 3 marks, got %d" % [tag, _main.errors.size()])
	var old_size := root.size
	# Резкое сужение: переносы обязаны пересобраться.
	DisplayServer.window_set_size(Vector2i(400, 900))
	root.size = Vector2i(400, 900)
	_main._relayout()
	_tick(tag)
	_common(tag)
	# Каждая метка — на своей букве и внутри набранного.
	var now: Array = []
	var bad := 0
	for mk in _main.errors.keys():
		var parts := String(mk).split(":")
		var li := int(parts[0])
		var pi := int(parts[1])
		if li >= _main.display_lines.size() or pi >= String(_main.display_lines[li]).length():
			bad += 1
			continue
		now.append(String(_main.display_lines[li]).substr(pi, 1))
	now.sort()
	_check(bad == 0, "%s: %d marks point outside the lines" % [tag, bad])
	_check(now == letters, "%s: marks changed letters on reflow" % tag)
	_check(_main.errors.size() == 3, "%s: reflow ate marks (%d left)" % [tag, _main.errors.size()])
	DisplayServer.window_set_size(old_size)
	root.size = old_size
	_main._relayout()
	_tick(tag)
	_common(tag)


## 42. Шифт противоположной руки — в обе стороны (правило быстрого набора,
## подтверждено методикой: буква левой — правый шифт и наоборот). Плюс
## клавиша обратного слеша: она есть на доске и печатается.
func _case_shift_hands() -> void:
	_fresh(6, 1)
	var tag := "shift hands"
	# «А» — левая рука, «Р» — правая (зоны слепой печати).
	_set_level_text(["А роза упала.", "Роза упала."])
	_main.press_ema = 0.6
	_main.cursor_line = 0
	_main.cursor_pos = 0
	_main.hero_r = _main._hero_pos()
	_main.idle_t = _main._hint_delay() + 0.5
	_check(
		_main._hint_keys() == ["ShiftR", "а"],
		"%s: left-hand capital highlights %s" % [tag, str(_main._hint_keys())]
	)
	_main.cursor_line = 1
	_main.cursor_pos = 0
	_main.hero_r = _main._hero_pos()
	_main.idle_t = _main._hint_delay() + 0.5
	_check(
		_main._hint_keys() == ["Shift", "р"],
		"%s: right-hand capital highlights %s" % [tag, str(_main._hint_keys())]
	)
	# И нажатие идёт тем же путём: правый шифт + «а» даёт «А».
	_main.cursor_line = 0
	_main.cursor_pos = 0
	_main.hero_r = _main._hero_pos()
	var btns := _kbd_buttons()
	var ok0: int = _main.typed_ok
	_main._own_press(btns["ShiftR"])
	_tick(tag)
	_check(_main.kb_shift, "%s: the right shift did not arm" % tag)
	_main._own_press(_kbd_buttons()["А"])
	_tick(tag)
	_check(_main.typed_ok == ok0 + 1, "%s: ShiftR+а did not type «А»" % [tag])
	_check(_main.errors.is_empty(), "%s: ShiftR+а left a mark" % tag)
	_common(tag)


## 43. Обратный слеш: клавиша есть (как на настоящей) и печатается.
## В текстах его нет, поэтому просто жмём: либо принимается, либо
## ровно одна честная метка — главное, что знак доходит до игры.
func _case_backslash_key() -> void:
	_fresh(0, 1)
	_kbd_on()
	var tag := "backslash"
	var btns := _kbd_buttons()
	if not btns.has("\\"):
		_check(false, "%s: no backslash key" % tag)
		return
	var marks0: int = _main.errors.size()
	var ok0: int = _main.typed_ok
	_main._own_press(btns["\\"])
	_tick(tag)
	_common(tag)
	_check(
		_main.typed_ok == ok0 + 1 or _main.errors.size() == marks0 + 1,
		"%s: the backslash press vanished" % tag
	)


## 18. Автопунктуация IME: точка с настоящим keycode, когда игра ждёт
## другое, молча пропускается — ребёнок её не нажимал.
func _case_auto_punctuation() -> void:
	# Знак не по месту считается обычной опечаткой: автопунктуации IME
	# больше нет, молчаливый пропуск ушёл вместе с системной клавиатурой.
	# А когда игра ждёт именно «.», она принимается без меток.
	_fresh(1, 0)
	var tag := "auto punctuation"
	var bad0: int = _main.typed_bad
	if _main._current() == ".":
		_hard(".", KEY_PERIOD)
		_tick(tag)
		_check(_main.typed_bad == bad0, "%s: the wanted dot counted as a mistake" % tag)
		_check(_main.errors.is_empty(), "%s: the wanted dot left a mark" % tag)
	else:
		_hard(".", KEY_PERIOD)
		_tick(tag)
		_check(
			_main.typed_bad == bad0 + 1,
			"%s: the wrong dot was not counted (%d → %d)" % [tag, bad0, _main.typed_bad]
		)
		_check(_main.errors.size() == 1, "%s: the wrong dot left no mark" % tag)
		_common(tag)


## 19. Скачок времени (кадр завис на полсекунды): инварианты должны
## выжить, а табло укола — совпасть с правилом.
func _case_time_jump() -> void:
	_fresh(3, 0)
	var tag := "time jump"
	_advance_to(0.3)
	_main.grace_t = 0.0
	_main.hedge_active = true
	_main.enemy_line = int(_main.cursor_line)
	_main.enemy_x = _main.margin + (_ax() + 30.0) * _main.char_w
	for i in 6:
		_main._process(0.5)
		_common("%s jump %d" % [tag, i])
		if _main.state == "lost":
			break
	if _main.state == "lost":
		_check(_main._last_reason == "behind", "%s: wrong loss reason" % tag)
		var ex: float = _main.enemy_x
		var hero: Vector2 = _main.hero_r
		var cw0: float = _main.char_w
		var moved := false
		for i in 40:
			_main._process(DT)
			# Табло застывшее: шары остаются ровно в касании. Перераскладка
			# (поехала клавиатура, окно) пересчитывает ОБОИХ героев в новых
			# метриках — это не ходьба, поэтому сверяем касание в пикселях,
			# а не координаты и не ось текста (строки при этом переносятся).
			moved = moved or absf(_contact_px()) > 1.0
			_common(tag)
		_check(not moved, "%s: the frozen tableau broke after a time jump (contact %.1f px)" % [tag, _contact_px()])


## 20. Меню игроков посреди партии (F2) и возврат: уровень не должен
## рассыпаться — курсор, метки и счётчики те же.
func _case_menu_roundtrip() -> void:
	_fresh(1, 0)
	var tag := "menu roundtrip"
	_check(_advance_to(0.3), "%s: could not advance (coverage)" % tag)
	_main._type_char(_wrong())
	_tick(tag)
	_main.grace_t = 0.0
	_main.hedge_active = true
	_main.enemy_x = _main.margin + 12.0 * _main.char_w
	# Меню игроков: пока оно открыто, партия стоит — ёж не идёт.
	_main._unhandled_key_input(_key(KEY_F2))
	_tick(tag)
	_check(_main.menu_open, "%s: F2 did not open the menu" % tag)
	var ex: float = _main.enemy_x
	for i in 40:
		_main._process(DT)
	_check(
		absf(_main.enemy_x - ex) < 0.01,
		"%s: the hedgehog moved while the menu was open" % tag
	)
	# Возврат по F2 в меню — тот же игрок. По замыслу это НАЧАЛО уровня
	# заново (меню выбирает игрока, а не ставит паузу), поэтому меток и
	# счётчиков в новой партии не остаётся.
	var ev := _key(KEY_F2)
	_main._unhandled_key_input(ev)
	if _main.menu != null:
		_main.menu.call("_unhandled_key_input", ev)
	_tick(tag)
	_check(not _main.menu_open, "%s: F2 did not close the menu" % tag)
	_check(_main.state == "playing", "%s: the game did not resume (%s)" % [tag, _main.state])
	_check(_main.errors.is_empty(), "%s: the new level kept the marks" % tag)
	_check(_main.typed_bad == 0, "%s: the new level kept the mistake counter" % tag)
	_common(tag)


## 21. Предупреждение о CapsLock в строгом режиме: заглавная без шифта
## (или строчная с шифтом) поднимает предупреждение, верная буква его
## гасит. Проверяем и подсказку, и то, что оно не залипает.
func _case_caps_warning() -> void:
	_fresh(3, 1)          # «все клавиши» — регистр важен
	var tag := "caps"
	if not _main._exact():
		return
	var cell := Vector2i(-1, -1)
	for l in _main.display_lines.size():
		var line: String = _main.display_lines[l]
		for p in line.length():
			if line.substr(p, 1) != line.substr(p, 1).to_lower():
				cell = Vector2i(l, p)
				break
		if cell.x >= 0:
			break
	if cell.x < 0:
		_check(false, "%s: no capital letter in the level (coverage)" % tag)
		return
	# Игра ждёт СТРОЧНУЮ букву, а приходит ЗАГЛАВНАЯ без шифта — ровно то,
	# что получается при включённом CapsLock. Предупреждение обязано
	# подняться (иначе ребёнок гадает, почему «буква не считается»), а
	# промах стать честной меткой.
	var lower := Vector2i(-1, -1)
	for l in _main.display_lines.size():
		var line: String = _main.display_lines[l]
		for p in line.length():
			var ch := line.substr(p, 1)
			if ch == ch.to_lower() and ch != " " and _main._is_active(ch) and (l > 0 or p > 0):
				lower = Vector2i(l, p)
				break
		if lower.x >= 0:
			break
	if lower.x < 0:
		_check(false, "%s: no lowercase letter in the level (coverage)" % tag)
		return
	_main.cursor_line = lower.x
	_main.cursor_pos = lower.y
	_main.hero_r = _main._hero_pos()
	var upper: String = _main._current().to_upper()
	var ev := InputEventKey.new()
	ev.pressed = true
	ev.keycode = KEY_A
	ev.unicode = upper.unicode_at(0)
	ev.shift_pressed = false
	_main._unhandled_key_input(ev)
	_tick(tag)
	_check(_main._caps_warn, "%s: the caps-lock warning did not appear" % tag)
	_check(_main.errors.size() == 1, "%s: the wrong case left no mark" % tag)
	# Верная буква гасит и предупреждение, и метку.
	_main._type_char(_main._current())
	_main._caps_warn = false
	_main._type_char(_main._current())
	_tick(tag)
	_check(not _main._caps_warn, "%s: the warning survived a correct letter" % tag)


## 22. Вспышка-подсказка не залипает: вспыхнувшая клетка должна вернуться
## к обычному виду, иначе буква «мерцает» (жалоба автора 10.2026).
func _case_hint_lifetime() -> void:
	_fresh(1, 0)
	var tag := "hint life"
	_check(_advance_to(0.25), "%s: could not advance (coverage)" % tag)
	_main._hint_at(int(_main.cursor_line), int(_main.cursor_pos))
	_tick(tag)
	_check(not _main.hints.is_empty(), "%s: the hint did not light up" % tag)
	var frames := 0
	while not _main.hints.is_empty() and frames < 60 * 12:
		frames += 1
		_main._process(DT)
	_check(
		_main.hints.is_empty(),
		"%s: the hint flash never ended (%d frames)" % [tag, frames]
	)
	_check(frames < 60 * 6, "%s: the hint lasted %d frames" % [tag, frames])


## 23. Скролл длинного текста: на низком экране в карточку влезает меньше
## строк, текст едет за курсором. Метки обязаны уехать вместе с текстом,
## а заяц — остаться в видимой полосе.
func _case_scroll() -> void:
	_fresh(2, 0)
	var tag := "scroll"
	var old_size := root.size
	root.size = Vector2i(900, 320)
	_main._relayout()
	_tick(tag)
	_check(_advance_to(0.6), "%s: could not advance on a short screen" % tag)
	_tick(tag)
	# Метка на первой строке и на текущей: первая давно уехала из вида.
	var marks0: int = _main.errors.size()
	_main._type_char(_wrong())
	_tick(tag)
	_check(_main.errors.size() == marks0 + 1, "%s: no mark on the scrolled text" % tag)
	_drawed(tag)
	# Курсор на третьей строке — она обязана быть в видимой полосе.
	_main.cursor_line = mini(2, _main.display_lines.size() - 1)
	_main.cursor_pos = 1
	_main.hero_r = _main._hero_pos()
	_main._process(DT)
	_drawed(tag)
	var vis: int = _main._vis_lines()
	_check(vis >= 1, "%s: no visible lines on a short screen" % tag)
	_check(
		_main.scroll_y >= 0.0,
		"%s: the text scrolled above zero (%.0f)" % [tag, _main.scroll_y]
	)
	_common(tag)
	root.size = old_size
	_main._relayout()


## 24. Спам Enter на экране победы: каждый Enter — новый уровень, и
## ничего не падает, профиль цел.
func _case_enter_spam() -> void:
	_fresh(0, 1)
	var tag := "enter spam"
	while _main.state == "playing":
		var cur: String = _main._current()
		if cur == "":
			break
		_main._type_char(cur)
	_tick(tag)
	_check(_main.state == "won", "%s: the level was not finished" % tag)
	# Клавиша ввода на самой доске (справа от «э», как настоящий Enter):
	# на финале она листает дальше, в партии молчит.
	var ebtns := _kbd_buttons()
	if not ebtns.has("↵"):
		_check(false, "%s: the board has no enter key" % tag)
		return
	_check(_main._own_press(ebtns["↵"]), "%s: the board enter did nothing on the won screen" % tag)
	_tick(tag)
	_check(_main.state == "playing", "%s: the board enter did not advance (%s)" % [tag, _main.state])
	for i in 6:
		_enter()
		_tick(tag)
		_common(tag)
	_check(_main.state == "playing", "%s: Enter spam left the game broken (%s)" % [tag, _main.state])
	_check(_main.errors.is_empty(), "%s: a fresh level kept the marks" % tag)
	_check(_main.typed_bad == 0, "%s: a fresh level kept the mistake counter" % tag)
	_check(not _main.menu_open, "%s: Enter spam opened the menu" % tag)


## 25. Шторм Backspace: сто нажатий подряд ничего не ломают
## ни курсор, ни метки, ни счётчики.
func _case_undo_cap() -> void:
	# Шторм Backspace: сто нажатий подряд не ломают ни курсор, ни метки,
	# ни счётчики. Стека снятий больше нет (ушёл вместе с IME).
	_fresh(2, 1)
	var tag := "undo cap"
	_check(_advance_to(0.4), "%s: could not advance (coverage)" % tag)
	for i in 4:
		_main._type_char(_wrong())
	_tick(tag)
	var ok0: int = _main.typed_ok
	var bad0: int = _main.typed_bad
	for i in 80:
		_main._backspace()
		_tick(tag)
		_common(tag)
	_check(_main.typed_ok == ok0, "%s: the backspace storm moved typed_ok" % tag)
	_check(_main.typed_bad == bad0, "%s: the backspace storm moved typed_bad" % tag)


func _finish_level(tag: String) -> void:
	var guard := 0
	while _main.state == "playing" and guard < 4000:
		guard += 1
		var cur: String = _main._current()
		if cur == "":
			break
		_main._type_char(cur)
		_tick(tag)
		_stack_is_solid(tag)
		if _main.errors.size() > 0 and guard > 2000:
			break
	_check(
		_main.state == "won",
		"%s: the level was not passed in %d steps (state %s, marks %d)"
			% [tag, guard, _main.state, _main.errors.size()]
	)
	_check(_main.errors.is_empty(), "%s: marks survived the end of the level" % tag)


## Телефонный портрет вместо headless-умолчания 64x64: карточка текста и
## своя клавиатура туда не влезают. Задавать надо на ПЕРВОМ кадре —
## в _initialize окно ещё не создано и размер запроса теряется.
func _fit_window() -> void:
	DisplayServer.window_set_size(Vector2i(820, 1180))
	root.size = Vector2i(820, 1180)
	_main._relayout()


func _process(_dt: float) -> bool:
	if _frame > 0:
		return true
	_frame = 1
	_fit_window()
	_case_ime_word()
	_case_autocorrect()
	_case_backspace_chain()
	_case_backspace_at_start()
	_case_mistake_at_start()
	_case_error_storm()
	_case_line_wrap()
	_case_level_end()
	_case_exact_case()
	_case_night()
	_case_ime_duplicate()
	_case_last_cell()
	_case_loss_with_marks()
	_case_touch_keyboard()
	_case_kbd_shift_layer()
	_case_long_press()
	_case_auto_punctuation()
	_case_time_jump()
	_case_menu_roundtrip()
	_case_caps_warning()
	_case_hint_lifetime()
	_case_scroll()
	_case_enter_spam()
	_case_undo_cap()
	_case_relayout()
	_case_own_kbd_fits()
	_case_yo_hint()
	_case_frame_spike()
	_case_broken_profile()
	_case_long_press_grey()
	_case_rotate_with_marks()
	_case_sym_layer_hint()
	_case_fast_doubles()
	_case_long_press_then_backspace()
	_case_ime_frames()
	_case_idle_hint()
	_case_reflow_typed_cells()
	_case_shift_hands()
	_case_backslash_key()
	_case_chaos(1500)
	_cases = 40
	_check(_steps > 1200, "the test really played (coverage: %d steps)" % _steps)
	for f in _failures:
		print("COMBO_TEST: FAIL: ", f)
	print("COMBO_TEST: шагов=%d проверок=%d" % [_steps, _failures.size()])
	print("COMBO_TEST: PASS" if _failures.is_empty() else "COMBO_TEST: FAIL")
	return true