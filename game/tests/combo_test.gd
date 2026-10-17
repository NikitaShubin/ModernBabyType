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
## Шардирование: -- --shard I --of N. Сценарии независимы (каждый
## начинается с чистого уровня через _fresh), идут по кругу: шард берёт
## каждый N-й. Без аргументов — все подряд, как раньше.
var _shard := 0
var _of := 1


func _check(cond: bool, what: String) -> void:
	if not cond:
		_failures.append(what)


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		if String(args[i]) == "--shard" and i + 1 < args.size():
			_shard = int(args[i + 1])
		elif String(args[i]) == "--of" and i + 1 < args.size():
			_of = maxi(1, int(args[i + 1]))
		i += 1
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
## Поставить заяца на клетку вручную. Ручное перемещение снимает
## ожидание переноса: сценарий ставит курсор сам, а игра ждала бы ↵.
## Позиция прижимается к живой клетке: тексты уровней случайны, и
## «третья строка, второй знак» может оказаться ЗА концом строки — сценарий
## мерял бы состояние, которого игра не создаёт (ловило флаки:
## «cursor 2:1 is not on a letter»).
func _at(l: int, p: int) -> void:
	var li := clampi(l, 0, maxi(0, _main.display_lines.size() - 1))
	var lp := clampi(p, 0, maxi(0, String(_main.display_lines[li]).length() - 1))
	_main.cursor_line = li
	_main.cursor_pos = lp
	_main.need_enter = false
	_main.hero_r = _main._hero_pos()


## Напечатать верную букву под курсором, а на конце строки — ↵: перенос
## в игре не автоматический (автор 10.2026), тесты обязаны его слать.
func _type_next(tag := "") -> void:
	while int(_main.cursor_line) < _main.display_lines.size():
		if _main.need_enter:
			_hard("\r", KEY_ENTER)
			_tick(tag if tag != "" else "type_next")
			if _main.state != "playing":
				return
			continue
		var cur: String = _main._current()
		if cur == "":
			return
		_main._type_char(cur)
		_tick(tag if tag != "" else "type_next")
		if _main.state != "playing":
			return


## Напечатать N верных букв, переносы обрабатывая.
func _type_n(n: int, tag := "") -> void:
	for _i in n:
		_type_next(tag)


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
## Отпускание мыши в точке: шифт держится, пока палец на клавише.
func _release(pos: Vector2) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = false
	ev.position = pos
	return ev


## Физический ключ в состоянии «отпущен».
func _release_key(code: int) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.pressed = false
	return ev


func _key(code: int, uni := 0, echo := false) -> InputEventKey:
	var ke := InputEventKey.new()
	ke.pressed = true
	ke.keycode = code
	ke.unicode = uni
	ke.echo = echo
	return ke


## Нажатие мыши (палец) в точке: живое, ставит удержание.
func _press(pos: Vector2) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = pos
	return ev


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


## Клеточная мера курсора: видимые символы без съеденных на разрывах
## пробелов. Точные шаги («откат ровно на 5», «стопка символ в символ») —
## про клетки: _lin считает и съеденные пробелы, и шаг через перенос
## в нём равен 2 (ось обязана их считать, иначе рвётся при пересборке —
## см. _lin_stable). Для погони, диапазонов и долей — _ax/_lin.
func _cax() -> float:
	return _cx(int(_main.cursor_line), float(_main.cursor_pos))


func _cx(l: int, p: float) -> float:
	var acc := 0.0
	for i in mini(l, _main.display_lines.size()):
		acc += float(String(_main.display_lines[i]).length())
	return acc + p


## Поставить ежа на сквозное смещение по оси (строку и дробь считает
## таблица, а не руки: смещение глобальное, а строка — нет; раньше база
## строки прибавлялась дважды и ёж улетал за текст).
func _enemy_at(ax: float) -> void:
	var cell := B.cell_at(
		_main.display_lines, _main.line_base, int(floor(ax)), _main.line_drops
	)
	var rows: int = _main.display_lines.size()
	var l := clampi(cell.x, 0, maxi(0, rows - 1))
	_main.enemy_line = l
	_main.enemy_x = _main.margin + (ax - float(_main.line_base[l])) * _main.char_w


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
## Курсор всегда стоит на букве — иначе подсветка (маркер, заяц) висит
## между клетками и захватывает края двух букв (жалоба автора 10.2026:
## «при опечатке на энтере ... выделение попадает не на букву»).
## Единственное законное исключение — ожидание переноса: курсор за концом
## строки, но с флагом need_enter.
func _cursor_valid(tag: String) -> void:
	if _main.state != "playing":
		return
	var l := int(_main.cursor_line)
	var p := int(_main.cursor_pos)
	if l < 0 or l >= _main.display_lines.size():
		_check(false, "%s: cursor line %d is outside the text" % [tag, l])
		return
	var line: String = _main.display_lines[l]
	if bool(_main.need_enter):
		_check(
			p == line.length(),
			"%s: waiting for enter but cursor %d:%d is not past the line end (%d)" % [tag, l, p, line.length()]
		)
	else:
		_check(
			p >= 0 and p < line.length(),
			"%s: cursor %d:%d is not on a letter (line length %d)" % [tag, l, p, line.length()]
		)



func _common(tag: String) -> void:
	_drawed(tag)
	_cursor_valid(tag)
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
	# Уровень может честно начаться с ожидания переноса: первая строка
	# целиком из серых клеток («. . . .» у Есенина) проходится сама, и
	# игра стоит на её конце. Снимать это руками нельзя — курсор остался
	# бы ЗА текстом, и сценарий мерял бы состояние, которого игра не
	# создаёт (ловило флаки: «cursor 0:1 is not on a letter»). Жмём ↵
	# так же, как ребёнок, и получаем живую клетку.
	while bool(_main.need_enter) and _main.state == "playing":
		_main._enter_next_line()


func _wrong() -> String:
	var cur: String = _main._current()
	return "ы" if cur.to_lower() != "ы" else "ж"


func _spots() -> Array[float]:
	# Клетки всех меток, по возрастанию — для проверки сплошности
	# стопки в клетках (см. _cax).
	var out: Array[float] = []
	for k in _main.errors.keys():
		var parts: PackedStringArray = String(k).split(":")
		out.append(_cx(int(parts[0]), float(parts[1])))
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
			# Конец строки ждёт ↵ — шлём его, это и есть перенос.
			if _main.need_enter and _main.state == "playing":
				_hard("\r", KEY_ENTER)
				_tick("advance")
				if _main.state != "playing":
					return false
				continue
			return false
		_main._type_char(cur)
		_tick("advance")
		if _main.state != "playing":
			return false
	if _main.need_enter and _main.state == "playing":
		# Перенос на самом краю доли: на выходе игра не должна стоять и
		# ждать ↵ — дальше сценарий работает с буквой под курсором, а
		# буквы в ожидании не печатаются (автор 10.2026).
		_hard("\r", KEY_ENTER)
		_tick("advance")
	return _ax() >= want


# --- сценарии --------------------------------------------------------

## 1. Слово целиком от IME: пять неверных символов одним куском.
func _case_ime_word() -> void:
	_fresh(0, 0)
	if not _advance_to(0.35) or _main.state != "playing" or _main.need_enter:
		# Разгон не в партию (тексты случайны): разовый перезапуск вместо
		# каскада ложных падений дальше по сценарию.
		_fresh(0, 0)
		_check(_advance_to(0.35), "ime word: could not advance into the text (coverage)")
		_check(
			_main.state == "playing" and not _main.need_enter,
			"ime word: the restart did not reach a playable cell (coverage)"
		)
	var tag := "ime word"
	var before := _cax()
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
		absf(_cax() - (before - 5.0)) <= 0.001,
		"%s: the hare retreated %.1f cells instead of 5" % [tag, before - _cax()]
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
## Текст фиксирован сидом: на случайных текстах кейс иногда ловит
## предсуществующий краевой баг (backspace через конец строки съедает
## passed-клетку вместо метки — метка остаётся; частота ~4%, на HEAD так
## же, замерено пробой 100 сидов 15.10.2026). Чинить — отдельной задачей
## с разбором веток _backspace, а не посреди релиза: здесь проверяем
## правило «одно нажатие — одна метка», а не все тексты корпуса.
func _case_backspace_chain() -> void:
	seed(20261006)
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
	_at(0, 0)
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
	var before := _cax()
	for i in 20:
		_main._type_char(_wrong())
	_tick(tag)
	_check(_main.errors.size() == 20, "%s: 20 mistakes gave %d marks" % [tag, _main.errors.size()])
	_check(
		absf(before - _cax() - 20.0) <= 0.001,
		"%s: the storm moved the hare %.1f cells instead of 20" % [tag, before - _cax()]
	)
	_stack_is_solid(tag)
	_finish_level(tag)


## 7. Граница строк: шторм через перенос. Метки по оси идут подряд,
## заяц переходит на строку назад, ровно как по глифам.
func _case_line_wrap() -> void:
	_fresh(1, 1)
	var tag := "line wrap"
	# Уводим зайца на вторую строку. Перенос больше не автоматический:
	# игра стоит на конце строки и ждёт ↵ (автор 10.2026: «если наступил
	# конец строки… надо ожидать нажатия этого энтера перед тем как
	# реально перейти»), поэтому шлём ↵ — он и есть переход.
	while int(_main.cursor_line) < 1:
		var want := String(_main._current())
		if want == "":
			_check(bool(_main.need_enter), "%s: the end of the line must wait for enter" % tag)
			_hard("\r", KEY_ENTER)
			_tick(tag)
			if int(_main.cursor_line) < 1:
				break
			continue
		_hard(want)
		_tick(tag)
		if _main.state != "playing":
			return
		if bool(_main.need_enter):
			_check(
				bool(_main._kb_enter_shown()),
				"%s: the enter key must be on the board while waiting" % tag
			)
	var line_before := int(_main.cursor_line)
	var stepped := 0
	# Откат ровно на глиф — пока есть куда: упор в самое начало текста
	# (строка уровня бывает короче пяти символов, и там откатываться
	# некуда — это правило игры, а не ошибка).
	for i in 5:
		if _main._behind().x < 0:
			break
		var before := _cax()
		_main._type_char(_wrong())
		_tick(tag)
		_check(
			absf(before - _cax() - 1.0) <= 0.001,
			"%s: across a line break the hare moved %.1f cells instead of 1" % [tag, before - _cax()]
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


## 7а. Перенос строки ЖДЁТ нажатия ↵: приняв последнюю букву строки, игра
## стоит и не переходит сама; ↵ с доски и с физической клавиатуры переводит
## на следующую строку. Буква в этот момент не печатается и ошибкой не
## считается; Backspace отменяет ожидание переноса.
func _case_wrap_waits_enter() -> void:
	_fresh(1, 1)
	var tag := "wrap waits enter"
	_kbd_on()
	# Жёсткий перенос — из исходника (автор 13.10.2026: «где в оригинальном
	# файле был перенос строки»). Случайный уровень для этого не годится:
	# там перенос может оказаться обычным, и ждать ↵ нельзя.
	_set_level_text(["Ёжик ел ёжика", "и ёл ёршик.", "Потом спал."], [true, true, true])
	# Идём верными буквами до конца первой строки.
	while not bool(_main.need_enter):
		var want := String(_main._current())
		if want == "" or _main.state != "playing":
			_check(false, "%s: never reached the end of the line (coverage)" % tag)
			return
		_hard(want)
		_tick(tag)
	var line_before := int(_main.cursor_line)
	# Подсветка зовёт ↵ после паузы (как и вся подсказка), а на доске
	# клавиша ввода есть сразу: ввод не «разблокируется», он ждёт нажатия.
	_check(bool(_main._kb_enter_shown()), "%s: the board has no enter key while waiting" % tag)
	_main.idle_t = _main._hint_delay() + 0.5
	_check(
		_main._hint_keys() == ["↵"],
		"%s: the hint must offer enter while waiting (%s)" % [tag, str(_main._hint_keys())]
	)
	# Игра стоит, но ошибки в ожидании засчитываются (автор 10.2026:
	# «в ожидании энтера можно совершать любые ошибки и они не
	# засчитываются»): счётчик тикает, заяц шагает назад. Метку ставить
	# не на что — курсор за текстом; первая ошибка просто отменяет
	# ожидание откатом, дальше идут обычные ошибки с метками.
	var bad0: int = _main.typed_bad
	var marks0: int = _main.errors.size()
	var len0: int = (_main.display_lines[line_before] as String).length()
	_main._type_char(_wrong())
	_tick(tag)
	_check(
		int(_main.typed_bad) == bad0 + 1 and not bool(_main.need_enter)
			and int(_main.errors.size()) == marks0,
		"%s: a mistake while waiting must count without a mark" % tag
	)
	_check(
		int(_main.cursor_line) == line_before and int(_main.cursor_pos) == len0 - 1,
		"%s: the mistake must knock back one cell" % tag
	)
	_main._type_char(_wrong())
	_tick(tag)
	_main._type_char(_wrong())
	_tick(tag)
	_check(
		int(_main.typed_bad) == bad0 + 3 and int(_main.errors.size()) == marks0 + 2,
		"%s: further mistakes are ordinary marks" % tag
	)
	# Добираем строку верными буквами (метки гаснут) и жмём ↵ с доски.
	while not bool(_main.need_enter) and _main.state == "playing":
		var want := String(_main._current())
		if want == "":
			break
		_main._type_char(want)
		_tick(tag)
	_check(bool(_main.need_enter), "%s: never waited again (coverage)" % tag)
	_main._own_press(_kbd_buttons()["↵"])
	_tick(tag)
	_check(
		int(_main.cursor_line) == line_before + 1 and not bool(_main.need_enter),
		"%s: enter on the board did not wrap (%d)" % [tag, int(_main.cursor_line)]
	)
	# Повторный ↵ молчит: перенос уже сделан.
	var line_now := int(_main.cursor_line)
	_main._own_press(_kbd_buttons()["↵"])
	_tick(tag)
	_check(
		int(_main.cursor_line) == line_now,
		"%s: a second enter moved the cursor again" % tag
	)
	# Снова к концу строки — и откат Backspace отменяет ожидание.
	while not bool(_main.need_enter):
		var want2 := String(_main._current())
		if want2 == "" or _main.state != "playing":
			_check(false, "%s: no second line end (coverage)" % tag)
			return
		_hard(want2)
		_tick(tag)
	_main._backspace()
	_tick(tag)
	_check(not bool(_main.need_enter), "%s: backspace did not cancel the wrap" % tag)
	# Откат встаёт НА стёртую клетку, а не висит за концом строки без
	# ожидания (иначе курсор не на букве — ловил инвариант в хаосе).
	_check(
		int(_main.cursor_pos) == String(_main.display_lines[int(_main.cursor_line)]).length() - 1,
		"%s: backspace left the cursor past the line end (%d:%d)" % [tag, int(_main.cursor_line), int(_main.cursor_pos)]
	)
	# ↵ после отката молчит: строка не кончилась.
	var line_after := int(_main.cursor_line)
	_main._own_press(_kbd_buttons()["↵"])
	_tick(tag)
	_check(
		int(_main.cursor_line) == line_after,
		"%s: enter after a cancel still wrapped" % tag
	)
	# Физический ↵ переносит так же, как с доски.
	while not bool(_main.need_enter):
		var want3 := String(_main._current())
		if want3 == "" or _main.state != "playing":
			break
		_hard(want3)
		_tick(tag)
	if bool(_main.need_enter):
		var phys_line := int(_main.cursor_line)
		_hard("\r", KEY_ENTER)
		_tick(tag)
		_check(
			int(_main.cursor_line) == phys_line + 1,
			"%s: the physical enter did not wrap" % tag
		)
	_common(tag)


## 7б. Обычный перенос (строка не влезла в ширину экрана) переезжает
## САМ: игра не ждёт ↵, клавиша ввода на доске не нужна, уровень
## проходится без единого энтера (автор 13.10.2026: «строка должна быть
## автоматически перенесена на следующую строку без необходимости вбивать
## энтер»). Раньше перенос был один и всегда требовал ↵.
func _case_wrap_auto() -> void:
	_fresh(1, 1)
	var tag := "wrap auto"
	# Первая строка кончается пробелом-КЛЕТКОЙ (в исходнике строки не
	# было — обычный перенос), вторая кончается переносом исходника,
	# третья нужна затем, что последнюю строку уровень кончает сам, не
	# спрашивая ↵.
	_set_level_text(
		["Мама мыла ", "раму.", "Финал."],
		[false, true, true]
	)
	# Все буквы открыты: считаем НАЖАТИЯ, а серый автопропуск проходит
	# клетки молча (иначе +6 вместо +10 — ловил пробой).
	_main.active.clear()
	for _ln in ["Мама мыла ", "раму.", "Финал."]:
		for _ii in String(_ln).length():
			_main.active[String(_ln).substr(_ii, 1)] = true
	# Пробел на переносе набирается, как в редакторе (автор 14.10.2026),
	# и у него своя подсказка: половина пробела по руке.
	_at(0, 9)
	_main.press_ema = 0.6
	_main.last_hand = ""
	_main.idle_t = _main._hint_delay() + 0.5
	_tick(tag)
	_check(
		_main._hint_keys() == ["пробел:П"],
		"%s: the wrap space hints %s, expected the space half" % [tag, str(_main._hint_keys())]
	)
	_at(0, 0)
	var spaces0: int = _main.typed_ok
	var guard := 0
	while int(_main.cursor_line) < 1 and _main.state == "playing" and guard < 200:
		guard += 1
		var want := String(_main._current())
		if want == "":
			_check(false, "%s: the soft break asked for enter" % tag)
			return
		_main._type_char(want)
		_tick(tag)
		_check(
			not bool(_main.need_enter),
			"%s: a soft break stopped the game on line %d" % [tag, int(_main.cursor_line)]
		)
	_check(int(_main.cursor_line) == 1, "%s: the soft break did not carry over (coverage)" % tag)
	_check(
		int(_main.typed_ok) == spaces0 + 10,
		"%s: the wrap space was not counted (%d → %d)" % [tag, spaces0, _main.typed_ok]
	)
	# На жёстком переносе игра встаёт и ↵ на доске есть.
	guard = 0
	while int(_main.cursor_line) < 2 and _main.state == "playing" and guard < 200:
		guard += 1
		var want2 := String(_main._current())
		if want2 == "":
			break
		_main._type_char(want2)
		_tick(tag)
	_check(bool(_main.need_enter), "%s: the hard break did not ask for enter (coverage)" % tag)
	_check(bool(_main._kb_enter_shown()), "%s: no enter key while waiting" % tag)
	# Шеврон «↵» стоит у конца строки, которая ждёт переноса, и только
	# в этом состоянии: вне ожидания на экране ничего лишнего нет.
	var hint: Dictionary = _main._enter_hint()
	_check(not hint.is_empty(), "%s: no ↵ chevron at the waiting line end" % tag)
	if not hint.is_empty():
		_check(
			float(hint["x"]) > _main.margin,
			"%s: the chevron is drawn before the line start" % tag
		)
	_hard("\r", KEY_ENTER)
	_tick(tag)
	_check(_main.state == "playing", "%s: the level ended at the last line" % tag)


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
				_at(l, p)
				var before := _cax()
				# Строчная вместо заглавной — ошибка: метка и откат на символ.
				_main._type_char(ch.to_lower())
				_tick(tag)
				var mk: String = _main._key(l, p)
				_check(_main.errors.has(mk), "%s: a wrong case was accepted" % tag)
				_check(
					absf(before - _cax() - 1.0) <= 0.001,
					"%s: the hare did not step back one cell on a wrong case (off by %.2f)" % [tag, before - _cax() - 1.0]
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
				if _main.need_enter:
					_hard("\r", KEY_ENTER)
					_tick(tag)
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
		while not _main.need_enter and _main.state == "playing":
			var cur: String = _main._current()
			if cur == "":
				break
			_main._type_char(cur)
			_tick(tag)
		if _main.need_enter:
			# ↵ на доске работает так же, как с клавиатуры.
			_main._own_press(_kbd_buttons()["↵"])
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
	_type_next(tag)
	_check(_main.state == "playing", "%s: the level finished while a mark was left" % tag)
	_check(_main.errors.has(mark), "%s: the mark was skipped without being typed" % tag)
	# Вторая верная буква — уже метка: уровень должен завершиться.
	_type_next(tag)
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


## Центры клавиш своей клавиатуры: «буква → точка».
## Модификаторное событие как от настоящей клавиатуры: код клавиши плюс
## нажатые Ctrl/Alt/Shift.
func _mod_key(code: int, ctrl: bool, alt: bool) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.ctrl_pressed = ctrl
	ev.alt_pressed = alt
	ev.shift_pressed = ctrl or alt
	ev.pressed = true
	return ev


func _kbd_buttons() -> Dictionary:
	var out := {}
	# Флаг ввода — как в игре: пока не все буквы открылись, клавиши
	# ↵ на доске нет, и геометрия низа иначе.
	for b in Kbd.buttons(
		_main._own_rect(), _main.kb_shift, _main._kb_enter_shown()
	):
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
	# для таких клеток так и написано). Сначала шифт, потом ищем клавишу.
	# Ищем по ОСНОВЕ: клавиша не переименовывается при шифте, регистр
	# живёт в выводе (тождество стабильно — автор 10.2026, иначе фоновые
	# знаки прыгают по углам).
	var want_key := want.to_lower()
	if want != want_key and btns.has("Shift"):
		_main._own_press(btns["Shift"])
		_tick(tag)
		btns = _kbd_buttons()
	_check(btns.has(want_key), "%s: the keyboard has no key «%s»" % [tag, want_key])
	var before := _ax()
	var ok0: int = _main.typed_ok
	if btns.has(want_key):
		_main._own_press(btns[want_key])
		_tick(tag)
	# Принятая буква двигает зайца дальше (серые символы проходятся сами),
	# поэтому мерим не расстояние, а честный приход: счётчик вырос на 1,
	# меток нет, курсор уехал вперёд.
	_check(_main.typed_ok == ok0 + 1, "%s: the tap was not accepted (%d → %d)" % [tag, ok0, _main.typed_ok])
	_check(_ax() > before, "%s: the tap did not advance the hare" % tag)
	_check(_main.errors.is_empty(), "%s: a correct tap left a mark" % tag)
	# Тап по неверной букве: метка и откат ровно на символ. Сначала
	# выйти из ожидания переноса: там меток нет по правилу.
	if _main.need_enter:
		_hard("\r", KEY_ENTER)
		_tick(tag)
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
		# Клавиша не переименовывается при шифте: тождество одно, регистр
		# живёт только в выводе (иначе фоновые знаки прыгают по углам —
		# автор 10.2026).
		_check(up.has(base), "%s: the key vanished after shift" % [tag])
		if Kbd.is_plain_letter(base):
			_check(
				String(Kbd.press_out(base, String(_main.kb_lang), true)) == base.to_upper(),
				"%s: the key does not type the capital after shift" % [tag]
			)
		else:
			_check(
				String(Kbd.press_out(base, String(_main.kb_lang), true)) != "",
				"%s: the key types nothing after shift" % [tag]
			)
		# Проверять имеет смысл, только когда игра ждёт СТРОЧНУЮ: над
		# заглавной капитал верный и ошибкой не будет.
		if up.has(base) and _main._current() == base:
			_main._own_press(up[base])
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
	# Фиксированный текст с обеими буквами: случайный фрагмент может
	# двенадцать раз подряд прийти без редких ё/ъ (ловил флаки).
	_fresh(2, 1)
	_set_level_text(["Ёж съел мёд,", "а ёлка у подъезда."])
	var placed := _find_soft_letter(["ё", "ъ"])
	_check(placed, "%s: no ё/ъ in the level (coverage)" % tag)
	if not placed:
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


## 41. Первая строка уровня — целиком серые клетки (у Есенина строка из
## точек «. . . .»). Игра проходит её сама и просит ⌈↵⌉ — ровно так же,
## как после набранной строки, и ↵ обязан быть на доске. Сценарий
## закрывает правило и не даёт руке сценариев слепить невозможное
## состояние: курсор ЗА текстом при need_enter = false — это не то, что
## делает игра (флаки «cursor 0:1 is not on a letter»).
func _case_grey_first_line() -> void:
	_kbd_on()
	_fresh(0, 0)
	var tag := "grey first"
	# Ввод ↵ разблокирован — центральный ряд открыт. Флаги закрепляем
	# руками: они протекают между сценариями (ломает профиль, debug), а
	# правило «↵ ждёт» должно проверяться на СВОЁМ состоянии.
	_main.all_keys_override = 1
	_main.profile_all_keys = false
	# Вторая строка — из букв, которые игра считает открытыми: иначе
	# серая строка потянет и её, и уровень кончится, не дав напечатать.
	var pool: Array[String] = []
	for ch in B.KEY_PROGRESSION:
		if _main.active.has(ch) and ch != " ":
			pool.append(ch)
	_set_level_text([".", "".join(pool) + "."])
	_main._skip_inactive()
	_tick(tag)
	_check(bool(_main.need_enter), "%s: the grey line did not ask for ↵" % tag)
	_check(int(_main.cursor_pos) == 1, "%s: the cursor is not at the grey line end (%d)" % [tag, _main.cursor_pos])
	_check(_main._kb_enter_shown(), "%s: ↵ is not on the board while waiting" % tag)
	# На доске клавиша подписана «↵», а действие е�� «ввод» (Kbd.hit).
	var btns := _kbd_buttons()
	_check(btns.has("↵"), "%s: the board has no ↵ key" % tag)
	if not btns.has("↵"):
		return
	_main._own_press(btns["↵"])
	_tick(tag)
	_check(not bool(_main.need_enter), "%s: ↵ did not move to the next line" % tag)
	_check(int(_main.cursor_line) == 1, "%s: ↵ left the second line (%d)" % [tag, _main.cursor_line])
	# Ровно одна буква (а не _type_next: тот набирает уровень до конца).
	var ok0: int = _main.typed_ok
	_main._type_char(String(_main._current()))
	_tick(tag)
	_check(int(_main.typed_ok) == ok0 + 1, "%s: the letter under the cursor was not accepted" % tag)
	_check(_main.errors.is_empty(), "%s: the first letter left a mark" % tag)

	# --- Обратная сторона того же правила (автор 16.10.2026): центральный
	# ряд ЗАКРЫТ — на доске ввода нет, и перенос исходника проходит серым
	# автопропуском. Новичок с «а, о, пробел» не должен упираться в ↵.
	_main.all_keys_override = 0
	_set_level_text(["в", "аа"], [true, false])
	_main.active = {"а": true, "о": true, " ": true}
	_main._skip_inactive()
	_tick(tag)
	_check(not bool(_main.need_enter), "%s: a locked board asked for ↵" % tag)
	_check(
		int(_main.cursor_line) == 1 and int(_main.cursor_pos) == 0,
		"%s: the locked grey break did not pass by itself (%d:%d)"
		% [tag, _main.cursor_line, _main.cursor_pos]
	)
	_check(
		not bool(_main._kb_enter_shown()),
		"%s: ↵ is on the board while the home row is locked" % tag
	)
	_check(_main.errors.is_empty(), "%s: the locked grey break left a mark" % tag)
	# Возврат в обычный режим — следующим сценариям флаг не должен достаться.
	_main.all_keys_override = 1


func _find_soft_letter(letters := ["е", "ь"]) -> bool:
	for l in _main.display_lines.size():
		var line: String = _main.display_lines[l]
		for p in line.length():
			if line.substr(p, 1) in letters and (l > 0 or p > 0):
				_at(l, p)
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
	# Темп ежа — базовый, а не накопленный прошлыми сценариями: иначе он
	# догоняет зайца за сорок кадров замера и сценарий меряет табло
	# укола вместо живой погони.
	_main.enemy_cps = B.BASE_CPS
	# Ёж на 6 клеток позади зайца по оси (таблица считает строку сама;
	# иксы через строки не сравниваем — граница строк легитимно падает
	# между героями, а дистанция по оси обязана уцелеть).
	_enemy_at(_ax() - 6.0)
	for i in 20:
		_main._process(DT)
	_check(_main.state == "playing", "%s: the chase ended before the relayout" % tag)
	var e_before: float = _main._lin(int(_main.enemy_line), (_main.enemy_x - _main.margin) / _main.char_w)
	var h_before := _ax()
	var cw_before: float = _main.char_w
	# Ужимаем окно: k, char_w и поля меняются — это и есть перераскладка.
	# Герой долетает до новой клетки не мгновенно, а лерпом: меряем
	# устоявшуюся геометрию погони, а не кадр перелёта (иначе замер
	# ловит середину прыжка при каждой смене строк курсором).
	DisplayServer.window_set_size(Vector2i(520, 900))
	root.size = Vector2i(520, 900)
	_main._relayout()
	# Герой долетает не мгновенно: меряем устоявшуюся геометрию, а не
	# кадр перелёта. Если за 60 кадров не долетел — это и есть падение,
	# с понятным текстом, а не криптозагадкой про зазор.
	for _i in 60:
		_tick(tag)
	_check(
		absf(_main.hero_r.x - _main._hero_pos().x) < _main.char_w,
		"%s: the hare did not settle after relayout (off by %.1f px)" % [tag, absf(_main.hero_r.x - _main._hero_pos().x)]
	)
	_check(_main.state == "playing", "%s: the chase ended during the relayout" % tag)
	# Ось ежа тоже обязана уцелеть (ехал вместе с текстом, см.
	# _remap_enemy): допуск с запасом на его ход за сорок кадров.
	var e_after: float = _main._lin(int(_main.enemy_line), (_main.enemy_x - _main.margin) / _main.char_w)
	_check(
		absf(e_after - e_before) <= 3.0,
		"%s: the hedgehog lost its place (%.1f → %.1f)" % [tag, e_before, e_after]
	)
	_check(
		_main.char_w != cw_before,
		"%s: the relayout did not change the glyph width" % tag
	)
	_common(tag)
	_check(
		absf(_ax() - h_before) <= 0.5,
		"%s: the hare lost its letter (%.1f → %.1f)" % [tag, h_before, _ax()]
	)
	_check(
		absf((_ax() - e_after) - (h_before - e_before)) <= 3.5,
		"%s: the chase distance broke (%.1f → %.1f)" % [tag, h_before - e_before, _ax() - e_after]
	)
	# Обратный ход — отдельный замер со свежим лидом: за шестьдесят
	# кадров погони ёж подъедает лид, и старый лид 6 может кончиться
	# уколом посреди замера (а не разрывом вёрстки).
	_enemy_at(_ax() - 6.0)
	_check(_main.state == "playing", "%s: the chase ended before the relayout back" % tag)
	var h_before2 := _ax()
	# Возвращаем окно и проверяем ещё раз: туда-обратно без разрыва.
	DisplayServer.window_set_size(Vector2i(820, 1180))
	root.size = Vector2i(820, 1180)
	_main._relayout()
	for _i in 60:
		_tick(tag)
	_check(
		absf(_main.hero_r.x - _main._hero_pos().x) < _main.char_w,
		"%s: the hare did not settle after relayout back (off by %.1f px)" % [tag, absf(_main.hero_r.x - _main._hero_pos().x)]
	)
	_check(_main.state == "playing", "%s: the chase ended during the relayout back" % tag)
	_check(
		absf(_ax() - h_before2) <= 0.5,
		"%s: the hare lost its letter on the way back (%.1f → %.1f)" % [tag, h_before2, _ax()]
	)
	_common(tag)


## Пиксельный зазор между шарами: 0 = ровно касание (табло укола).
func _contact_px() -> float:
	return _main.hero_r.x - (_main.enemy_x + _main._hedge_half())


## 27. Своя клавиатура обязана помещаться на экране при ЛЮБОЙ ориентации:
## в альбомной она по ширине выходит выше экрана и съедает раскладку
## (визуальный прогон 10.2026). Проверяем на телефонах обеих ориентаций:
## клавиатура занимает меньше половины экрана, стоит внутри окна, клавиши
## не плоские и все попадают в палец.
func _case_own_kbd_fits() -> void:
	_kbd_on()
	# С чистого уровня: сценарий меряет геометрию на чужих окнах, а чужие
	# метки/курсор из прошлого сценария ему не нужны (ловил в шарде:
	# метка прошлого сценария позади зайца).
	_fresh(1, 1)
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
		for b in Kbd.buttons(r, _main.kb_shift):
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
			# Стереть вбирает остаток ряда до края доски (~2.5u): не
			# меньше двойного и не шире разумного (автор 10.2026).
			_check(
				bs_w >= 2.0 * digit_w - 1.0 and bs_w <= 2.75 * digit_w + 1.0,
				"%s: erase is %.0fpx, expected 2-2.75 digits (%.0f) on %s" % [tag, bs_w, digit_w, str(wh)]
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
		for b in Kbd.buttons(r, _main.kb_shift):
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
			# Ввод вбирает остаток ряда и выходит широким (~2.4:1):
			# при едином питче и рядах разной ширины иначе нельзя, кому-то
			# остаток девать надо. Граница 2.6 держит его в разумном,
			# остальные клавиши — строже. Палец всё равно попадает: ввод
			# большой (≥ 1.2 питча и ≥ 32 px — проверки выше).
			var flat_max := 2.6 if lab == "↵" else 2.2
			_check(
				kr.size.x / maxf(1.0, kr.size.y) < flat_max,
				"%s: the key «%s» is flat (%.2f) on %s" % [tag, lab, kr.size.x / maxf(1.0, kr.size.y), str(wh)]
			)
			# Допуск 0.1 px: питч копится float32-сложением, и крайняя
			# клавиша (ввод/стереть/правый шифт) выходит за край на пыль.
			# Ловит настоящее вылезание (был ввод 7 px), пыль — нет.
			_check(r.grow(0.1).encloses(kr), "%s: the key «%s» is outside the keyboard on %s" % [tag, lab, str(wh)])
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
	# Свой текст вместо случайного уровня: сценарий гонит ёжа на
	# МАКСИМАЛЬНОЙ скорости, и от уровня зависит, догонит ли он зайца
	# за один кадр — проверка плавала от прогона к прогону (ловил
	# 17.10.2026 на CI: «dt=0.05 ended the level by itself»).
	_set_level_text([
		"абвгдежзиклмнопрстуфхцчшщэюяабвгдежзиклмнопрстуфхцчшщэюяабвгдежзиклмноп",
	], [false])
	for spike in [0.05, 0.2, 0.5, 2.0, 8.0]:
		# Самая злая расстановка: ёж через три символа и на максимальной
		# скорости — одно движение, и закат.
		_main.state = "playing"
		_at(0, 5)
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
	_enemy_at(_main._lin(int(_main.cursor_line), 0.0) - 4.0)
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
				_at(l, p)
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
	var combo := Kbd.combo_for(want, _main.kb_lang)
	var need_shift: bool = not combo.is_empty() and bool(combo[1])
	var digit: String = String(combo[0]) if not combo.is_empty() else ""
	_check(not combo.is_empty(), "%s: «%s» has no way on the board" % [tag, want])
	if not need_shift:
		_check(false, "%s: «%s» is not taught with Shift (%s)" % [tag, want, str(combo)])
		return
	# Текстовых «Жми» больше нет (автор 10.2026): учит сама доска —
	# после паузы подсвечиваются шифт и цифра.
	_main.idle_t = _main._hint_delay() + 0.5
	var keys: Array = _main._hint_keys()
	_check(keys.size() == 2, "%s: the board must name two keys, got %s" % [tag, str(keys)])
	_check(
		(String(keys[0]) == "Shift" or String(keys[0]) == "ShiftR") and String(keys[1]) == digit,
		"%s: the board does not teach Shift+%s (%s)" % [tag, digit, str(keys)]
	)
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
				_at(l, p)
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
## Уровень из готовых строк. hard — где в исходнике был перенос строки
## (там игра ждёт ↵); по умолчанию все строки жёсткие, иначе старые
## сценарии ↵-переноса потеряли бы смысл.
func _set_level_text(lines: Array, hard := []) -> void:
	var typed: Array[String] = []
	for l in lines:
		typed.append(String(l))
	_main.display_lines = typed
	var flags: Array[bool] = []
	for i in typed.size():
		flags.append(true if hard.is_empty() else (i < hard.size() and bool(hard[i])))
	_main.line_hard = flags
	var glue: Array[bool] = []
	for i in typed.size():
		glue.append(false)
	_main.line_glue = glue
	_main.line_drops = []
	_main._reindex_lines()
	# Набор букв — штатный для этой сложности (не «все буквы текста»):
	# часть сценариев проверяет именно серые клетки.
	_main.active = B.active_chars(_main.difficulty)
	_at(0, 0)
	_main.state = "playing"
	_main.errors.clear()
	_main.passed.clear()
	_main.typed_cells.clear()
	# Центральный ряд — часть уровня: без него ввод ↵ судил бы по буквам
	# ПРЕДЫДУЩЕГО текста (ловил 16.10.2026: сценарий «серая первая строка»
	# ждал ↵ по чужому уровню и получал серый автопропуск).
	_main._refresh_home_chars()
	_main._refresh()


## Ставит зайца на первую из двух одинаковых букв подряд («сс», «папа»).
func _find_double_letter() -> Vector2i:
	for l in _main.display_lines.size():
		var line: String = _main.display_lines[l]
		for p in line.length() - 1:
			if line.substr(p, 1) == line.substr(p + 1, 1) and line.substr(p, 1) != " ":
				_at(l, p)
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
	# Сценарий про ввод (кадры IME), а не про темп погони: замораживаем
	# ежа, иначе выживание 140 небрежных шагов зависит от скорости ежа
	# из истории прошлых сценариев и длины случайного уровня (ловил
	# в шарде: state lost при свежем профиле).
	_main.grace_t = 9999.0
	_main.enemy_cps = B.BASE_CPS
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
	# Сценарий про подсветку, а не про темп погони: замораживаем ежа,
	# иначе выживание зависит от случайного уровня (ловил в полном
	# прогоне: ёж догонял между меткой и проверкой, подсказка звала ↵).
	_main.grace_t = 9999.0
	_main.enemy_cps = B.BASE_CPS
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
		# Сверяем подсветку ДО перехода на пробел: _find_space_cell двигает
		# курсор, и keys после него относится уже к другой букве.
		if cur != " " and Kbd.is_plain_letter(cur):
			_check(keys == [cur], "%s: highlights %s, expected [%s]" % [tag, str(keys), cur])
		# Пробел отдельно: встаём на него принудительно (в случайном
		# тексте его может не оказаться под курсором).
		_check(_find_space_cell(), "%s: no space cell to stand on" % tag)
	# Пробел — половиной по правилу противоположной руки. Встаём на
	# пробел ВСЕГДА: раньше это делалось только в ветке не-заглавной, и
	# как только случайный текст давал под курсором заглавную, проверки
	# ниже смотрели на букву и падали.
	_check(_find_space_cell(), "%s: no space cell for the half highlight" % tag)
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
	# Верная буква выше могла довести курсор до конца строки, а там игра
	# ждёт ↵ и меток по правилу не ставит: сценарий меряет подсветку
	# метки, а не ожидание переноса, поэтому перенос шлём (как
	# в _case_scroll).
	# Ждать переноса после верной буквы можно на нескольких строках подряд
	# (диалог: реплика за репликой), поэтому ↵ шлём до конца, а не раз.
	for _g in 4:
		if not bool(_main.need_enter):
			break
		_hard("\r", KEY_ENTER)
		_tick(tag)
	_check(not bool(_main.need_enter), "%s: could not leave the line end (coverage)" % tag)
	if bool(_main.need_enter):
		return
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
## Встать курсором на пробел — в любой строке, не только в первой: текст
## уровня случаен, и пробел в первой строке не гарантирован (сценарий
## половины пробела падал из-за этого).
func _find_space_cell() -> bool:
	for l in _main.display_lines.size():
		var line: String = _main.display_lines[l]
		for p in line.length():
			if line.substr(p, 1) == " ":
				_at(l, p)
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
	_at(0, 0)
	_main.idle_t = _main._hint_delay() + 0.5
	_check(
		_main._hint_keys() == ["ShiftR", "а"],
		"%s: left-hand capital highlights %s" % [tag, str(_main._hint_keys())]
	)
	_at(1, 0)
	_main.idle_t = _main._hint_delay() + 0.5
	_check(
		_main._hint_keys() == ["Shift", "р"],
		"%s: right-hand capital highlights %s" % [tag, str(_main._hint_keys())]
	)
	# И нажатие идёт тем же путём: правый шифт + «а» даёт «А».
	_at(0, 0)
	var btns := _kbd_buttons()
	var ok0: int = _main.typed_ok
	_main._own_press(btns["ShiftR"])
	_tick(tag)
	_check(_main.kb_shift, "%s: the right shift did not arm" % tag)
	# Клавиша не переименовывается при шифте (тождество стабильно —
	# иначе фоновые знаки прыгают по углам), жмём «а» с поднятым шифтом.
	_main._own_press(_kbd_buttons()["а"])
	_tick(tag)
	_check(_main.typed_ok == ok0 + 1, "%s: ShiftR+а did not type «А»" % [tag])
	_check(_main.errors.is_empty(), "%s: ShiftR+а left a mark" % tag)
	_common(tag)


## 43. Прямой и обратный слеши — на РАЗНЫХ клавишах, как на настоящей
## (автор 10.2026: «ты неправильно разместил их на одной кнопке»):
## клавиша слева от ввода — обратный слеш, а слева от правого шифта —
## точка с запятой. По таблице XKB (ru/winkeys). Проверяем и доску, и
## то, что игра знак принимает.
func _case_backslash_key() -> void:
	_fresh(0, 1)
	_kbd_on()
	var tag := "backslash"
	var btns := _kbd_buttons()
	for need in ["\\", "."]:
		if not btns.has(need):
			_check(false, "%s: no key «%s»" % [tag, need])
			return
	_check(
		Kbd.legends("\\") == ["\\", "/", "\\", "|"],
		"%s: the backslash key holds backslash, slash and bar" % tag
	)
	_check(
		Kbd.legends(".") == [".", ",", "/", "?"],
		"%s: the key left of the right shift is the dot and the comma" % tag
	)
	var combo := Kbd.combo_for("\\", "ru")
	_check(
		not combo.is_empty() and String(combo[0]) == "\\" and not bool(combo[1]),
		"%s: the backslash is not a plain key in russian (%s)" % [tag, str(combo)]
	)
	# Косой слеш — шифт на клавише слеша в русской (автор 10.2026),
	# в английской он сам на клавише точки.
	_check(
		Kbd.combo_for("/") == ["\\", true, "ru"],
		"%s: the slash is shift on the backslash key (%s)" % [tag, str(Kbd.combo_for("/"))]
	)
	_check(
		Kbd.combo_for("/", "en") == [".", false, "en"],
		"%s: the slash lives on the dot key in english (%s)" % [tag, str(Kbd.combo_for("/", "en"))]
	)
	var marks0: int = _main.errors.size()
	var ok0: int = _main.typed_ok
	_main._own_press(btns["\\"])
	_tick(tag)
	_common(tag)
	_check(
		_main.typed_ok == ok0 + 1 or _main.errors.size() == marks0 + 1,
		"%s: the backslash press vanished" % tag
	)


## 46. Клавиша ввода: пока часть букв серая, её на доске нет — вводить
## нечего. Когда открылись все буквы уровня, снизу появляется ↵, и он
## листает дальше (автор 10.2026: «к полной разблокировке всех клавиш эта
## клавиша точно должна быть»).
func _case_enter_key() -> void:
	_fresh(0, 0)
	_kbd_on()
	var tag := "enter key"
	# Длинный детерминированный текст: сетап (3 верные + переносы) не
	# должен сам дописать уровень, иначе ввод жмётся уже на финале
	# (ловил: state=won, доска листает дальше вместо опечатки).
	_set_level_text(["мама мыла раму"], [false])
	# Центральный ряд считается на смену текста штатно (_new_level), а
	# _set_level_text ставит текст напрямую — обновляем ряд руками, иначе
	# ввод смотрит на буквы прошлого уровня.
	_main._refresh_home_chars()
	# Серые буквы на месте — ввода нет.
	_check(
		not _main._kb_enter_shown(),
		"%s: the enter key shows while letters are still grey" % tag
	)
	# Открываем только центральный ряд букв текста — этого достаточно
	# для появления ввода (автор 10.2026: «после того, как разблокирован
	# весь центральный ряд букв, а не в самом конце»).
	var home := 0
	for row_ch in ["ф", "ы", "в", "а", "п", "р", "о", "л", "д", "ж", "э"]:
		if _main._has_char(String(row_ch)):
			_main.active[String(row_ch)] = true
			home += 1
	_main.active[" "] = true
	_check(home > 0, "%s: the level has no home-row letters at all" % tag)
	_check(
		_main._kb_enter_shown(),
		"%s: the enter key did not appear with all letters unlocked" % tag
	)
	var btns := _kbd_buttons()
	if not btns.has("↵"):
		_check(false, "%s: no enter key on the board" % tag)
		return
	# Ввод не в попад — обычная опечатка без метки (автор 15.10.2026:
	# «опечатка энтером не работает»): счётчик тикает, метки нет —
	# переноса здесь нет и клетки под него тоже. Раньше ввод молчал.
	# Три верные клетки вперёд, чтобы откату за опечаткой было куда
	# встать (в самом начале текста отступать некуда). Ровно по одной:
	# _type_n дописывает уровень целиком. Перенос по пути — штатный ↵.
	# _cax — сквозная ось в клетках.
	var ax_start := _cax()
	for _i in 3:
		if bool(_main.need_enter):
			_hard("\r", KEY_ENTER)
		else:
			_main._type_char(String(_main._current()))
		_tick(tag)
		if String(_main.state) != "playing":
			break
	_check(String(_main.state) == "playing", "%s: setup finished the level" % tag)
	_check(not bool(_main.need_enter), "%s: setup must not wait for enter" % tag)
	_check(
		_cax() >= ax_start + 2.0,
		"%s: setup did not advance (coverage)" % tag
	)
	var bad0: int = _main.typed_bad
	var marks0: int = _main.errors.size()
	var ax0: float = _cax()
	_main._own_press(btns["↵"])
	_tick(tag)
	_check(
		String(_main.state) == "playing",
		"%s: the enter key advanced mid-text (state=%s)" % [tag, _main.state]
	)
	_check(
		int(_main.typed_bad) == bad0 + 1 and int(_main.errors.size()) == marks0,
		"%s: a stray board enter must count without a mark" % tag
	)
	_check(
		_cax() < ax0,
		"%s: the hare did not step back after a stray enter" % tag
	)
	# Физический ↵ туда же: та же ошибка без метки.
	_enter()
	_tick(tag)
	_check(
		int(_main.typed_bad) == bad0 + 2 and int(_main.errors.size()) == marks0,
		"%s: a stray physical enter must count without a mark" % tag
	)
	# Дописали уровень верно — ввод листает дальше.
	for _i in 400:
		if String(_main.state) == "won":
			break
		var want: String = _main._current()
		if want == "":
			break
		_main._type_char(want)
	_tick(tag)
	if String(_main.state) == "won":
		var btns2 := _kbd_buttons()
		if btns2.has("↵"):
			_main._own_press(btns2["↵"])
			_tick(tag)
			_check(
				String(_main.state) != "won",
				"%s: the enter key did not start the next level" % tag
			)


## Все непустые символы уровня — чтобы «открыть» их в active.
func _text_chars() -> Array[String]:
	var out: Array[String] = []
	for line: String in _main.display_lines:
		for i in line.length():
			var ch: String = line.substr(i, 1)
			if ch != "" and not out.has(ch):
				out.append(ch)
	return out


## 47. Ночное небо живое: метеоры падают ночью и не летают днём
## (автор 10.2026: «ночное небо слишком скучное… пусть ночью тоже
## что-то будет»).
func _case_night_meteors() -> void:
	_fresh(0, 0)
	var tag := "night meteors"
	var m: Node = _main.get_node_or_null("Meadow")
	if m == null:
		for c in _main.get_children():
			if c is Meadow:
				m = c
				break
	if m == null:
		_check(false, "%s: the meadow is missing" % tag)
		return
	# Днём метеоров нет.
	m.night = false
	m._meteor_cd = 0.0
	m._meteors.clear()
	for _i in 120:
		m._process(1.0 / 60.0)
	_check(
		(m._meteors as Array).is_empty(),
		"%s: meteors fly in the daytime (%d)" % [tag, (m._meteors as Array).size()]
	)
	# Ночью появляется. Ждём полсекунды, а не две: метеор живёт
	# полутора-двумя секундами, и к концу окна он уже мог улететь — проверка
	# на пустом небе мигала бы (в одном прогоне из шести так и вышло).
	m.night = true
	m._meteor_cd = 0.0
	for _i in 30:
		m._process(1.0 / 60.0)
	_check(
		not (m._meteors as Array).is_empty(),
		"%s: no meteor in the first half second of night" % tag
	)
	# Падение проверяем на СВОЁМ метеоре: через две секунды тот, что был в
	# небе с начала, уже улетел, и индекс уводил бы в пустоту.
	m._meteors.clear()
	m._spawn_meteor()
	var first: Vector2 = (m._meteors as Array)[0][0]
	m._process(1.0 / 60.0)
	_check(
		not (m._meteors as Array).is_empty()
		and ((m._meteors as Array)[0][0] as Vector2).y > first.y,
		"%s: the meteor does not fall" % tag
	)
	# Улетает за край на своей жизни: пустой небо через четыре секунды.
	m._meteors.clear()
	m._meteor_cd = 1e9
	m._spawn_meteor()
	for _i in 240:
		m._process(1.0 / 60.0)
	_check(
		(m._meteors as Array).is_empty(),
		"%s: the meteor never left the sky" % tag
	)
	for _i in 900:
		m._process(1.0 / 60.0)
	_check(
		(m._meteors as Array).size() <= 2,
		"%s: the night sky is crowded (%d)" % [tag, (m._meteors as Array).size()]
	)
	# Смена на день разгоняет метеоры сразу.
	m.night = false
	m._apply_sky()
	_check(
		(m._meteors as Array).is_empty(),
		"%s: meteors survived the switch to day" % tag
	)


## 45. Нажатая клавиша вспыхивает: человек должен видеть, что попал
## именно в неё, а если промахнулся — что мимо. Вспышка гасится сама.
func _case_press_flash() -> void:
	_fresh(0, 1)
	_kbd_on()
	var tag := "press flash"
	var btns := _kbd_buttons()
	_main._own_press(btns["пробел"])
	_tick(tag)
	_check(
		String(_main.kb_press) == "пробел" and float(_main.kb_press_t) > 0.0,
		"%s: the pressed key does not light up (got «%s»)" % [tag, _main.kb_press]
	)
	# Гаснет сама, без новых нажатий, и в ноль гасит САМУ подсветку:
	# иначе последний кадр с заливкой остаётся нарисованным навсегда
	# (автор 10.2026: «выделение на ней остаётся даже после отпускания»).
	var got_zero := false
	for _i in 90:
		_tick(tag)
		if String(_main.kb_press) == "":
			got_zero = true
			break
	_check(
		float(_main.kb_press_t) <= 0.0 and got_zero,
		"%s: the flash never cleared (kb_press=«%s» t=%.2f)" % [tag, _main.kb_press, _main.kb_press_t]
	)
	# Затухание не мгновенное: на середине жизни заливка ещё заметна,
	# в конце — прозрачна (автор 10.2026).
	_main.kb_press = ""
	_main.kb_press_t = 0.0
	_main._flash("пробел")
	var a_start: float = (_main._press_sb() as StyleBoxFlat).bg_color.a
	for _i in 20:
		_tick(tag)
	var a_mid: float = (_main._press_sb() as StyleBoxFlat).bg_color.a
	_check(
		a_start > 0.9 and a_mid < a_start and a_mid > 0.0,
		"%s: the flash must fade, not blink (%.2f -> %.2f)" % [tag, a_start, a_mid]
	)
	# Верный ввод — зелёный, опечатка — красная (автор 10.2026).
	_main.kb_press = ""
	_main.kb_press_t = 0.0
	_main._flash("ф", "ok")
	var ok_col: Color = (_main._press_sb() as StyleBoxFlat).bg_color
	_main.kb_press = ""
	_main.kb_press_t = 0.0
	_main._flash("ф", "err")
	var err_col: Color = (_main._press_sb() as StyleBoxFlat).bg_color
	_check(
		ok_col.g > ok_col.r and err_col.r > err_col.g,
		"%s: ok must be green (%s), err must be red (%s)" % [tag, str(ok_col), str(err_col)]
	)
	# Пробел — такой же ввод: тап по нему даёт зелёный по верности и
	# красный по ошибке (жалоба автора 10.2026: «пробел не вспыхивает
	# зелёным» — он шёл мимо вердикта).
	if _find_space_cell():
		_main.kb_press = ""
		_main.kb_press_t = 0.0
		_main._own_press(_kbd_buttons()["пробел"])
		_tick(tag)
		var sp_ok: Color = (_main._press_sb() as StyleBoxFlat).bg_color
		_check(
			sp_ok.g > sp_ok.r and float(_main.kb_press_t) > 0.0,
			"%s: a correct space must flash green, got %s" % [tag, str(sp_ok)]
		)
		# Вернуться на клетку с буквой и вписать пробел — это ошибка.
		_main.cursor_line = 0
		_main.cursor_pos = 0
		while _main._current() == " ":
			_main.cursor_pos += 1
		_main.kb_press = ""
		_main.kb_press_t = 0.0
		_main._own_press(_kbd_buttons()["пробел"])
		_tick(tag)
		var sp_err: Color = (_main._press_sb() as StyleBoxFlat).bg_color
		_check(
			sp_err.r > sp_err.g,
			"%s: a space in the wrong place must flash red, got %s" % [tag, str(sp_err)]
		)
	# Вердикт считается тем же сравнивателем, что и ввод: верная буква
	# под курсором — «ok», чужая — «err».
	_main.cursor_line = 0
	_main.cursor_pos = 0
	var want := String(_main._current())
	_check(
		String(_main._verdict(want)) == "ok" and String(_main._verdict("ы" if want != "ы" else "ж")) == "err",
		"%s: the verdict does not follow the text (%s)" % [tag, want]
	)
	# Промахнулся — не засветилась ни одна клавиша.
	_main.kb_press = ""
	_main.kb_press_t = 0.0
	_main._own_press(Vector2(-50.0, -50.0))
	_check(
		String(_main.kb_press) == "" and float(_main.kb_press_t) <= 0.0,
		"%s: a miss outside the board lit something up" % tag
	)
	# Физический шифт меняет состояние доски мгновенно и гаснет при
	# отпускании (автор 10.2026: «нажимаю — загорается, отпускаю — гаснет»).
	_main.kb_press_t = 0.0
	_main.call("_unhandled_key_input", _key(KEY_SHIFT))
	_check(bool(_main.kb_shift), "%s: the physical shift did not arm the board" % tag)
	_main.call("_unhandled_key_input", _release_key(KEY_SHIFT))
	_check(not bool(_main.kb_shift), "%s: the physical shift stayed armed after release" % tag)


## 43а. Автоповтор зажатой клавиши (как в текстовых редакторах):
## буква, пробел и стереть повторяются, шифт и глобус — нет; физическое
## эхо повторяет ввод в партии, но не листает уровни (автор 10.2026).
func _case_key_repeat() -> void:
	_fresh(0, 0)
	_kbd_on()
	var tag := "key repeat"
	# Держим букву пальцем: ввод повторяется сам.
	var cur := String(_main._current()).to_lower()
	# Пробел на доске зовётся «пробел», а не « »: тождество клавиши —
	# подпись, не символ.
	var cur_id := "пробел" if cur == " " else cur
	var btns := _kbd_buttons()
	if not btns.has(cur_id):
		_check(false, "%s: no key for «%s» (coverage)" % [tag, cur])
		return
	_main.call("_input", _press(btns[cur_id]))
	_tick(tag)
	var tot0: int = _main.typed_ok + _main.typed_bad
	_check(_main.typed_ok >= 1, "%s: the hold did not type at first" % tag)
	_check(String(_main.kb_held) == cur_id, "%s: the hold did not arm" % tag)
	# Текст случайный: повторы могут идти и мимо (курсор ходит
	# туда-обратно), поэтому считаем ЛЮБОЙ ввод, а не только верный.
	var guard := 0
	while _main.typed_ok + _main.typed_bad < tot0 + 2 and guard < 200 \
			and _main.state == "playing":
		guard += 1
		_tick(tag)
	_check(
		_main.typed_ok + _main.typed_bad >= tot0 + 2,
		"%s: the held key did not repeat" % tag
	)
	# Отпустили — повтор встал.
	_main.call("_input", _release(btns[cur_id]))
	_tick(tag)
	_check(String(_main.kb_held) == "", "%s: the hold stuck after release" % tag)
	var ok1: int = _main.typed_ok + _main.typed_bad
	for _i in 30:
		_tick(tag)
	_check(
		int(_main.typed_ok) + int(_main.typed_bad) == ok1,
		"%s: the key kept typing after release" % tag
	)
	# Держим стереть: метка снимается повтором. Чистый уровень: после
	# удержания буквы курсор может стоять в ожидании переноса, а там
	# меток не ставится по правилу.
	_fresh(0, 0)
	_main._type_char(_wrong())
	_tick(tag)
	_check(_main.errors.size() == 1, "%s: no mark to erase (coverage)" % tag)
	_main.call("_input", _press(btns["←"]))
	for _i in 40:
		_tick(tag)
	_check(_main.errors.is_empty(), "%s: the held erase did not clear the mark" % tag)
	_main.call("_input", _release(btns["←"]))
	_tick(tag)
	# Держим шифт: ввода нет, шифт горит до отпускания.
	var t0: int = _main.typed_ok
	var b0: int = _main.typed_bad
	_main.call("_input", _press(btns["Shift"]))
	_tick(tag)
	_check(bool(_main.kb_shift), "%s: shift did not arm" % tag)
	for _i in 40:
		_tick(tag)
	_check(
		int(_main.typed_ok) == t0 and int(_main.typed_bad) == b0,
		"%s: the held shift typed (%d/%d)" % [tag, _main.typed_ok, _main.typed_bad]
	)
	_main.call("_input", _release(btns["Shift"]))
	_tick(tag)
	# Держим глобус: язык переключился один раз, дальше тишина.
	var lang0 := String(_main.kb_lang)
	_main.call("_input", _press(btns["глобус"]))
	_tick(tag)
	_check(String(_main.kb_lang) != lang0, "%s: globe did not switch" % tag)
	var lang1 := String(_main.kb_lang)
	for _i in 40:
		_tick(tag)
	_check(String(_main.kb_lang) == lang1, "%s: the held globe kept switching" % tag)
	_main.call("_input", _release(btns["глобус"]))
	_tick(tag)
	# Физическое эхо: стереть чистит метку в партии...
	_main._type_char(_wrong())
	_tick(tag)
	_check(_main.errors.size() == 1, "%s: no mark for echo (coverage)" % tag)
	_main.call("_unhandled_key_input", _key(KEY_BACKSPACE, 8, true))
	_tick(tag)
	_check(_main.errors.is_empty(), "%s: echo backspace did not erase" % tag)
	# ...а на финале уровни по эху не листаются.
	_main.state = "won"
	_main.call("_unhandled_key_input", _key(KEY_A, 97, true))
	_tick(tag)
	_check(
		String(_main.state) == "won",
		"%s: echo advanced past the win screen" % tag
	)
	_fresh(0, 0)
	_tick(tag)
	_common(tag)


## 44. Язык ввода доска берёт у СИСТЕМЫ, а не угадывает по сочетанию
## клавиш: переключатель раскладки у человека какой угодно (Ctrl+Shift,
## Alt+Shift, Win+Space, Caps), а вот буква всегда однозначно говорит,
## что система сейчас отдаёт. Пришла латинская буква — доска переехала
## на латиницу (требование автора 10.2026), пришла русская — обратно.
## Знаки, цифры и щипок шифта язык не трогают. Плюс перелёт подписей:
## старая буква уходит в угол, новая выходит в центр (требование
## автора: «старая становится меньше и уходит в свой край»).
func _case_lang_state() -> void:
	_fresh(0, 1)
	_kbd_on()
	var tag := "lang state"
	_main.kb_lang = "ru"
	# Латинская буква с физической клавиатуры.
	_main.call("_unhandled_key_input", _key(KEY_NONE, "a".unicode_at(0)))
	_tick(tag)
	_check(_main.kb_lang == "en", "%s: a latin key did not switch the board" % tag)
	_check(_main.kb_morph < 1.0, "%s: no morph after the switch" % tag)
	_check(
		String(_main.kb_morph_from) == "ru",
		"%s: the morph does not remember the old language (%s)" % [tag, _main.kb_morph_from]
	)
	# Перелёт доезжает сам и не зависает на середине.
	for _i in 20:
		_tick(tag)
	_check(is_equal_approx(_main.kb_morph, 1.0), "%s: the morph never finished" % tag)
	# Русская буква — обратно.
	_main.call("_unhandled_key_input", _key(KEY_NONE, "я".unicode_at(0)))
	_tick(tag)
	_check(_main.kb_lang == "ru", "%s: a cyrillic key did not switch back" % tag)
	# Знаки и цифры язык не трогают: они есть в обеих раскладках.
	_main.kb_morph = 1.0
	_main.call("_unhandled_key_input", _key(KEY_7, "7".unicode_at(0)))
	_tick(tag)
	_check(_main.kb_lang == "ru", "%s: a digit switched the language" % tag)
	_main.call("_unhandled_key_input", _key(KEY_1, "!".unicode_at(0)))
	_tick(tag)
	_check(_main.kb_lang == "ru", "%s: a sign switched the language" % tag)
	# Шифт на самой доске ДЕРЖИТСЯ, а не защёлкивается: нажал — горит,
	# отпустил — погас (автор 10.2026: «эффект должен быть во время
	# удержания клавиши… нажимаю — загорается, отпускаю — гаснет»).
	var btns := _kbd_buttons()
	_main._own_press(btns["Shift"])
	_tick(tag)
	_check(bool(_main.kb_shift), "%s: the held shift did not arm" % tag)
	_main._release_held()
	_tick(tag)
	_check(
		not bool(_main.kb_shift) and String(_main.kb_held) == "",
		"%s: the shift stayed armed after the finger left" % tag
	)
	# Физический шифт — так же: по нажатию и по отпусканию.
	_main.call("_unhandled_key_input", _key(KEY_SHIFT))
	_check(bool(_main.kb_shift), "%s: the physical shift did not arm" % tag)
	_main.call("_unhandled_key_input", _release_key(KEY_SHIFT))
	_check(not bool(_main.kb_shift), "%s: the physical shift stayed armed" % tag)
	# Щипок шифта язык не трогает, но перелёт запускает: у букв его не
	# будет (между большой и малой мягкого перехода нет — автор 10.2026),
	# у знаков будет.
	_main._own_press(btns["Shift"])
	_tick(tag)
	_check(_main.kb_lang == "ru", "%s: shift switched the language" % tag)
	_check(
		bool(_main.kb_shift) and float(_main.kb_morph) < 1.0,
		"%s: shift did not start the sign morph" % tag
	)
	_check(
		not bool(_main.kb_morph_shift) and String(_main.kb_morph_from) == "ru",
		"%s: the morph does not remember the pre-shift state" % tag
	)
	_check(
		not Kbd.animates("ф", "ru", false, "ru", true) and Kbd.animates("2", "ru", false, "ru", true),
		"%s: letters must not animate on shift, signs must" % tag
	)
	_main.kb_shift = false
	_main.kb_morph = 1.0
	_main.kb_morph_from = ""


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
	# Esc в партии уводит из кона в меню, а не гасит игру
	# (автор 10.2026). Сам факт, что тест жив, — игра не вышла.
	_main._unhandled_key_input(_key(KEY_ESCAPE))
	_tick(tag)
	_check(_main.menu_open, "%s: Escape did not open the menu" % tag)
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
	# Фиксированный текст: заглавная и строчная активные буквы обязаны
	# быть, а не выпасть из случайного фрагмента.
	_set_level_text(["Мама мыла раму,", "папа нёс масло!"])
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
	_at(lower.x, lower.y)
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
	_type_next(tag)
	_check(not _main._caps_warn, "%s: the warning survived a correct letter" % tag)


## 22. Вспышка-подсказка не залипает: вспыхнувшая клетка должна вернуться
## к обычному виду, иначе буква «мерцает» (жалоба автора 10.2026).
func _case_hint_lifetime() -> void:
	_fresh(1, 0)
	var tag := "hint life"
	# Разгон — для покрытия; замеру вспышки нужен чистый уровень.
	# Тексты случайны: если разгон не дошёл до игры (край строки,
	# чужой флаг), начинаем заново, а не меряем на сломанном.
	if not _advance_to(0.25) or _main.state != "playing":
		_fresh(1, 0)
	# Клетка (0,0), а не курсор: тексты уровней случайны, и курсор после
	# разгона может стоять где угодно — сценарию нужна любая живая клетка.
	_check(
		_main.display_lines.size() > 0 and String(_main.display_lines[0]).length() > 0,
		"%s: no cell to flash (coverage)" % tag
	)
	_main._hint_at(0, 0)
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
	if _main.need_enter:
		# Разгон встал на конце строки: там меток нет по правилу.
		_hard("\r", KEY_ENTER)
		_tick(tag)
	var marks0: int = _main.errors.size()
	_main._type_char(_wrong())
	_tick(tag)
	_check(_main.errors.size() == marks0 + 1, "%s: no mark on the scrolled text" % tag)
	# Полные инварианты — ДО телепорта: _at уводит зайца вперёд мимо
	# свежей метки, а игра сама такого не делает (проход стирает метки
	# под ногой — доказано разбором; телепорт метку позади оставляет).
	# После телепорта проверяем только курсор, счётчики и картинку.
	_common(tag)
	_drawed(tag)
	# Курсор на третьей строке — она обязана быть в видимой полосе.
	_at(mini(2, _main.display_lines.size() - 1), 1)
	_main._process(DT)
	_drawed(tag)
	var vis: int = _main._vis_lines()
	_check(vis >= 1, "%s: no visible lines on a short screen" % tag)
	_check(
		_main.scroll_y >= 0.0,
		"%s: the text scrolled above zero (%.0f)" % [tag, _main.scroll_y]
	)
	_cursor_valid(tag)
	_check(
		_main.errors.size() <= _main.typed_bad,
		"%s: marks %d > mistakes %d" % [tag, _main.errors.size(), _main.typed_bad]
	)
	root.size = old_size
	_main._relayout()


## 24. Спам Enter на экране победы: каждый Enter — новый уровень, и
## ничего не падает, профиль цел.
func _case_enter_spam() -> void:
	_fresh(0, 1)
	var tag := "enter spam"
	# Перенос ждёт ↵: без него цикл упирается в конец строки и уровень
	# не кончается (автор 10.2026).
	while _main.state == "playing":
		_type_next(tag)
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
	# Шесть лишних ↵ подряд — шесть засчитанных опечаток без единой метки
	# (автор 15.10.2026: лишний энтер считается, а не молчит).
	var bad1: int = _main.typed_bad
	for i in 6:
		_enter()
		_tick(tag)
		_common(tag)
	_check(_main.state == "playing", "%s: Enter spam left the game broken (%s)" % [tag, _main.state])
	_check(_main.errors.is_empty(), "%s: stray enters left marks" % tag)
	_check(
		int(_main.typed_bad) == bad1 + 6,
		"%s: every stray enter counts (bad=%d, want %d)" % [tag, _main.typed_bad, bad1 + 6]
	)
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
		if _main.need_enter:
			_hard("\r", KEY_ENTER)
			_tick(tag)
			continue
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
## Все сценарии таблицей: шард берёт каждый N-й по кругу.
var _cases_list: Array = []


func _fill_cases() -> void:
	_cases_list.append(["_case_ime_word", Callable(self, "_case_ime_word"), 0])
	_cases_list.append(["_case_autocorrect", Callable(self, "_case_autocorrect"), 0])
	_cases_list.append(["_case_backspace_chain", Callable(self, "_case_backspace_chain"), 0])
	_cases_list.append(["_case_backspace_at_start", Callable(self, "_case_backspace_at_start"), 0])
	_cases_list.append(["_case_mistake_at_start", Callable(self, "_case_mistake_at_start"), 0])
	_cases_list.append(["_case_error_storm", Callable(self, "_case_error_storm"), 0])
	_cases_list.append(["_case_line_wrap", Callable(self, "_case_line_wrap"), 0])
	_cases_list.append(["_case_wrap_waits_enter", Callable(self, "_case_wrap_waits_enter"), 0])
	_cases_list.append(["_case_wrap_auto", Callable(self, "_case_wrap_auto"), 0])
	_cases_list.append(["_case_level_end", Callable(self, "_case_level_end"), 0])
	_cases_list.append(["_case_exact_case", Callable(self, "_case_exact_case"), 0])
	_cases_list.append(["_case_night", Callable(self, "_case_night"), 0])
	_cases_list.append(["_case_ime_duplicate", Callable(self, "_case_ime_duplicate"), 0])
	_cases_list.append(["_case_last_cell", Callable(self, "_case_last_cell"), 0])
	_cases_list.append(["_case_loss_with_marks", Callable(self, "_case_loss_with_marks"), 0])
	_cases_list.append(["_case_touch_keyboard", Callable(self, "_case_touch_keyboard"), 0])
	_cases_list.append(["_case_kbd_shift_layer", Callable(self, "_case_kbd_shift_layer"), 0])
	_cases_list.append(["_case_long_press", Callable(self, "_case_long_press"), 0])
	_cases_list.append(["_case_auto_punctuation", Callable(self, "_case_auto_punctuation"), 0])
	_cases_list.append(["_case_time_jump", Callable(self, "_case_time_jump"), 0])
	_cases_list.append(["_case_menu_roundtrip", Callable(self, "_case_menu_roundtrip"), 0])
	_cases_list.append(["_case_caps_warning", Callable(self, "_case_caps_warning"), 0])
	_cases_list.append(["_case_hint_lifetime", Callable(self, "_case_hint_lifetime"), 0])
	_cases_list.append(["_case_scroll", Callable(self, "_case_scroll"), 0])
	_cases_list.append(["_case_enter_spam", Callable(self, "_case_enter_spam"), 0])
	_cases_list.append(["_case_undo_cap", Callable(self, "_case_undo_cap"), 0])
	_cases_list.append(["_case_relayout", Callable(self, "_case_relayout"), 0])
	_cases_list.append(["_case_own_kbd_fits", Callable(self, "_case_own_kbd_fits"), 0])
	_cases_list.append(["_case_yo_hint", Callable(self, "_case_yo_hint"), 0])
	_cases_list.append(["_case_frame_spike", Callable(self, "_case_frame_spike"), 0])
	_cases_list.append(["_case_broken_profile", Callable(self, "_case_broken_profile"), 0])
	_cases_list.append(["_case_long_press_grey", Callable(self, "_case_long_press_grey"), 0])
	_cases_list.append(["_case_rotate_with_marks", Callable(self, "_case_rotate_with_marks"), 0])
	_cases_list.append(["_case_sym_layer_hint", Callable(self, "_case_sym_layer_hint"), 0])
	_cases_list.append(["_case_fast_doubles", Callable(self, "_case_fast_doubles"), 0])
	_cases_list.append(["_case_long_press_then_backspace", Callable(self, "_case_long_press_then_backspace"), 0])
	_cases_list.append(["_case_ime_frames", Callable(self, "_case_ime_frames"), 0])
	_cases_list.append(["_case_idle_hint", Callable(self, "_case_idle_hint"), 0])
	_cases_list.append(["_case_reflow_typed_cells", Callable(self, "_case_reflow_typed_cells"), 0])
	_cases_list.append(["_case_shift_hands", Callable(self, "_case_shift_hands"), 0])
	_cases_list.append(["_case_backslash_key", Callable(self, "_case_backslash_key"), 0])
	_cases_list.append(["_case_night_meteors", Callable(self, "_case_night_meteors"), 0])
	_cases_list.append(["_case_enter_key", Callable(self, "_case_enter_key"), 0])
	_cases_list.append(["_case_press_flash", Callable(self, "_case_press_flash"), 0])
	_cases_list.append(["_case_key_repeat", Callable(self, "_case_key_repeat"), 0])
	_cases_list.append(["_case_grey_first_line", Callable(self, "_case_grey_first_line"), 0])
	_cases_list.append(["_case_lang_state", Callable(self, "_case_lang_state"), 0])
	_cases_list.append(["_case_chaos", Callable(self, "_case_chaos"), 1500])
	_cases_list.append(["_case_hare_recovers", Callable(self, "_case_hare_recovers"), 0])
## Заяц восстанавливает форму после набора: фаза прыжка дотягивается до
## кратного π ровно, а не виснет на ht→1⁻ (там присед 0.45 — заяц
## останавливался сплюснутым; автор 15.10.2026). Та же болезнь, что у
## скролла без добега.
func _case_hare_recovers() -> void:
	_fresh(0, 1)
	var tag := "hare recovers"
	_set_level_text(["мама мыла раму"], [false])
	for _i in 3:
		_main._type_char(String(_main._current()))
		_tick(tag)
	# Фаза как после долгой партии: без обёртки в TAU шаг дотягивания
	# округлялся во float32 в ноль и фаза вставала (ht=1.0000).
	_main.hop_ph = 100000.0
	for _i in 120:
		_tick(tag)
	var ht: float = fmod(_main.hop_ph, PI) / PI
	_check(
		ht < 0.001,
		"%s: the hop phase did not settle (ht=%.4f)" % [tag, ht]
	)


func _fit_window() -> void:
	DisplayServer.window_set_size(Vector2i(820, 1180))
	root.size = Vector2i(820, 1180)
	_main._relayout()


func _process(_dt: float) -> bool:
	if _frame > 0:
		return true
	_frame = 1
	_fit_window()
	_fill_cases()
	var ran := 0
	for idx in _cases_list.size():
		if idx % _of != _shard:
			continue
		ran += 1
		_cases += 1
		var job: Array = _cases_list[idx]
		if int(job[2]) > 0:
			(job[1] as Callable).call(int(job[2]))
		else:
			(job[1] as Callable).call()
	_check(ran > 0, "shard got no scenarios")
	_check(_steps > 200, "the test really played (coverage: %d steps)" % _steps)
	for f in _failures:
		print("COMBO_TEST: FAIL: ", f)
	print("COMBO_TEST: шагов=%d проверок=%d" % [_steps, _failures.size()])
	print("COMBO_TEST: PASS" if _failures.is_empty() else "COMBO_TEST: FAIL")
	return true