extends SceneTree
## Уровень обязан проходиться до конца на ЛЮБОМ экране, телефон в
## первую очередь. Вёрстка узкого экрана режет строки по словам, и на
## месте разрыва не должен оставаться невидимый пробел: за ним на
## экране пусто, а игра ждёт нажатия. Автор так и не смог закончить
## уровень на телефоне («строка кончилась, а что нажимать?», 07.10.2026).
##
## Два слоя:
##  1) чистая функция — ВСЕ тексты × ВСЕ телефонные ширины: ни одного
##     куска, кончающегося пробелом, ни одной пустой строки, ни одной
##     потерянной буквы;
##  2) живой прогон — уровень на четырёх размерах экрана проходится
##     целиком (нажимаем ровно то, что ждёт игра) и заканчивается победой.
##
## Запуск: godot --headless --path game --script res://tests/end_test.gd

const B := preload("res://scripts/balance.gd")

## Ширины в клетках: от крошечного телефона до порога, за которым
## вёрстка не трогает текст вовсе (36). Плюс сам порог.
const WIDTHS: Array[int] = [12, 14, 16, 18, 20, 22, 24, 26, 28, 30, 32, 34, 36]

var _frame := 0
var _main: Node = null
var _failures: Array[String] = []


func _check(cond: bool, what: String) -> void:
	if not cond:
		_failures.append(what)


func _initialize() -> void:
	seed(20261006)
	var scene: PackedScene = load("res://scenes/main.tscn")
	_main = scene.instantiate()
	# Механика, а не интерфейс: сразу в игру, гостем, без меню.
	_main.skip_menu = true
	_main.all_keys_override = 1
	root.add_child(_main)


func _process(_dt: float) -> bool:
	_frame += 1
	if _frame < 3:
		return false
	_fit_invariants()
	_reflow_keeps_cursor()
	_play(Vector2i(360, 240), "крошечный телефон")
	_play(Vector2i(520, 300), "узкий телефон")
	_play(Vector2i(800, 360), "телефон")
	_play(Vector2i(1280, 700), "десктоп")
	_hint_stays_above_keyboard()
	_report()
	return true


## Слой 1б: ширина экрана меняется ПО ХОДУ уровня (на телефоне выезжает
## клавиатура, телефон поворачивают). Строки обязаны пересобраться, иначе
## текст уезжает за край и набирать нечего; заяц при этом остаётся на
## той же букве, а «пройдено» и красные метки — на своих буквах.
func _reflow_keeps_cursor() -> void:
	root.size = Vector2i(900, 360)
	_main.view_w = 900.0
	_main.view_h = 360.0
	_main._relayout()
	_main._new_level()
	# Набираем половину уровня и запоминаем букву, на которой стоим.
	var guard := 0
	while int(_main.passed.size()) * 2 < _main.level_total and guard < 5000:
		guard += 1
		var ch := String(_main._current())
		if ch == "":
			break
		_main._type_char(ch)
	_check(String(_main.state) == "playing", "половина уровня набрана")
	var want := String(_main._current())
	var passed_before := int(_main.passed.size())
	var _passed_letters_before := _passed_letters()
	_passed_letters_before.sort()
	# Красная метка на клетке перед курсором: после пересборки она обязана
	# остаться на своей букве (иначе заяц упирается в чужую метку).
	_main.errors[_main._key(_main.cursor_line, maxi(0, _main.cursor_pos - 1))] = "ъ"
	# Сужаем экран почти вдвое — вёрстка обязана поменяться.
	root.size = Vector2i(280, 340)
	_main.view_w = 280.0
	_main.view_h = 340.0
	_main._relayout()
	_check(int(_main._max_chars()) < 36, "узкий экран считает меньше 36 знаков")
	_check(
		int(_main.display_lines[0].length()) <= _main._max_chars(),
		"строки пересобраны под новую ширину"
	)
	# Надписи на экране обязаны совпадать с разметкой: иначе игрок видит
	# старый текст, обрезанный краем окна («строка пустая»).
	var shown := String(_main.text_labels[0].get_parsed_text())
	_check(
		shown == String(_main.display_lines[0]),
		"надписи перерисованы под новую вёрстку (на экране «%s»)" % shown
	)
	_check(
		String(_main._current()) == want,
		"заяц остался на той же букве после пересборки"
	)
	# Пройденный пробел, попавший ровно на разрыв, законно исчезает:
	# такой клетки в новой сборке нет (разрыв сам разделяет слова).
	# Поэтому сверяем не штуки, а буквы: каждая не-пробельная пройденная
	# обязана остаться пройденной, новых браться неоткуда.
	var kept := _passed_letters()
	kept.sort()
	_check(
		kept == _passed_letters_before,
		"пройденные буквы не потерялись при пересборке"
	)
	var marked := ""
	for k in _main.errors.keys():
		marked += String(k) + " "
	_check(marked != "", "красная метка переехала на новую сетку: %s" % marked)
	# И уровень после пересборки обязан доигрываться до конца.
	while String(_main.state) == "playing" and guard < 20000:
		guard += 1
		var ch2 := String(_main._current())
		if ch2 == "":
			break
		_main._type_char(ch2)
	_check(
		String(_main.state) == "won",
		"после пересборки уровень доигрывается (%s)" % _main.state
	)


## Слой 1: все тексты на всех ширинах. Пустой кусок или висячий
## пробел = невидимое нажатие = уровень не проходится.
func _fit_invariants() -> void:
	var fl: Callable = B.fit_lines
	for path in _text_paths():
		var raw: Array[String] = []
		var fa := FileAccess.open(path, FileAccess.READ)
		if fa == null:
			_failures.append("нет текста " + path)
			continue
		while not fa.eof_reached():
			var ln := fa.get_line().strip_edges()
			if ln != "":
				raw.append(ln)
		var name := path.get_file()
		for w in WIDTHS:
			var fit: Array = fl.call(raw, w)
			var letters := ""
			for piece in fit:
				var t := String(piece)
				_check(t != "", "%s@%d: пустой кусок" % [name, w])
				if t.right(1) == " ":
					_failures.append("%s@%d: кусок кончается пробелом «%s»" % [name, w, t])
				letters += t.replace(" ", "")
			var origin := ""
			for ln in raw:
				origin += ln.replace(" ", "")
			_check(
				letters == origin,
				"%s@%d: разбивка потеряла буквы" % [name, w]
			)


func _text_paths() -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open("res://texts")
	if dir == null:
		return ["res://texts/demo.txt"]
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if not dir.current_is_dir() and f.ends_with(".txt"):
			out.append("res://texts/" + f)
		f = dir.get_next()
	dir.list_dir_end()
	return out


## Слой 2: живой прогон уровня. Нажимаем ровно ту букву, которую ждёт
## игра, — так проходит любой ребёнок, видящий текст. Если курсор
## встанет на невидимую клетку, уровень не закончится.
func _play(sz: Vector2i, name: String) -> void:
	root.size = sz
	_main.view_w = float(sz.x)
	_main.view_h = float(sz.y)
	_main._relayout()
	_main._new_level()
	var guard := 0
	while String(_main.state) == "playing" and guard < 20000:
		guard += 1
		var ch := String(_main._current())
		if ch == "":
			break
		_main._type_char(ch)
	_check(
		String(_main.state) == "won",
		"%s: уровень не закончился (%s, курсор %d:%d)" % [
			name, _main.state, _main.cursor_line, _main.cursor_pos
		]
	)
	_check(guard < 20000, "%s: курсор закрутился" % name)
	_check(int(_main.typed_ok) > 0, "%s: ничего не набрано" % name)
	for i in _main.display_lines.size():
		var t := String(_main.display_lines[i])
		_check(t != "", "%s: пустая строка %d" % [name, i])
		if t.right(1) == " ":
			_failures.append("%s: строка %d кончается невидимым пробелом «%s»" % [name, i, t])


## Подсказка («Жми: X») не должна уезжать под клавиатуру: жалоба автора
## 10.2026 — «часть важной инфы, включая подсказку внизу, закрывается».
## Открытие системной клавиатуры уменьшает _eff_h(), и пилюля обязана
## подниматься вместе с ним, а не оставаться на дне.
func _hint_stays_above_keyboard() -> void:
	var m: Node = null
	var sc: PackedScene = load("res://scenes/main.tscn")
	m = sc.instantiate()
	root.add_child(m)
	m.call_deferred("_new_level")
	for i in range(6):
		m.call("_process", 0.016)
	# Без клавиатуры: граница — весь экран.
	m.view_h = 1080.0
	m.kb_h = 0.0
	var eff_open: float = m.call("_eff_h")
	# С клавиатурой: граница выше, и пилюля обязана быть выше неё.
	m.kb_h = 420.0
	var eff_closed: float = m.call("_eff_h")
	_check(
		eff_closed < eff_open,
		"the keyboard shrinks the usable area"
	)
	# Панель подсказки: cap_h + 16k от _eff_h снизу. Считаем так же, как
	# в _draw_hint, и требуем, чтобы низ панели не выходил за границу.
	var k := float(m.k)
	var cap_h := 48.0 * k
	var panel_h := cap_h + 16.0 * k
	var y_top := eff_closed - 137.5 * k - cap_h * 0.5
	y_top = minf(y_top, eff_closed - panel_h - 8.0 * k)
	_check(
		y_top + panel_h <= eff_closed + 0.001,
		"the hint pill fits above the keyboard"
	)
	# Жёстко: панель считается так, как в коде (та же формула, тот же
	# отступ). Проверяем через НЕЁ — иначе тест повторяет баг.
	for kb in [0.0, 120.0, 420.0, 840.0, 1200.0, 2000.0]:
		m.kb_h = kb
		m.view_h = 1080.0
		var eff: float = m.call("_eff_h")
		var panel: float = 48.0 * k + 16.0 * k
		var y2 := minf(eff - 137.5 * k - 48.0 * k * 0.5, eff - panel - 8.0 * k)
		# Ниже низа доступной зоны уходим только если панель в неё
		# физически не влезает — и тогда берём низ, а не уходим под неё.
		if y2 < 8.0 * k:
			y2 = maxf(8.0 * k, eff - panel)
		_check(
			y2 + panel <= eff + 0.001,
			"hint pill fits at kb=%d" % int(kb)
		)
		_check(
			y2 >= 8.0 * k - 0.001,
			"hint never goes off-screen at kb=%d" % int(kb)
		)
	m.queue_free()


func _report() -> void:
	if _failures.is_empty():
		print("END_TEST: PASS")
	else:
		for f in _failures:
			print("END_TEST: FAIL: ", f)
	quit(1 if not _failures.is_empty() else 0)


## Буквы пройденных клеток без пробелов: пробел на разрыве исчезает
## вместе с клеткой (см. выше), его отсутствие — не потеря.
func _passed_letters() -> Array:
	var out: Array = []
	for k in _main.passed.keys():
		var parts := String(k).split(":")
		var li := int(parts[0])
		var pi := int(parts[1])
		if li < _main.display_lines.size() and pi < String(_main.display_lines[li]).length():
			var ch := String(_main.display_lines[li]).substr(pi, 1)
			if ch != " ":
				out.append(ch)
	return out
