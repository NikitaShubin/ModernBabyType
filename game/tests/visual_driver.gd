extends SceneTree
## Визуальный драйвер партии: играет НАСТОЯЩУЮ сцену (без X11-ввода) и
## снимает экран в ключевые события, печатая рядом состояние модели —
## координаты зайца и ежа, клетки меток, букву, которую игра ждёт. Дальше
## эти два ряда сравниваются: что на экране против того, что предсказала
## логика.
##
## Запуск (НЕ headless — нужен настоящий рендер):
##   DISPLAY=:99 tools/docker/build-game.sh --visual
## Кадры: /tmp/opencode/vis-*.png

const SAVE_DIR := "/tmp/opencode/"
const Kbd := preload("res://scripts/kbd.gd")

var _main: Node = null
var _frame := 0
var _shot_i := 0
## Очередь шагов: [имя кадра, действие, сколько кадров ждать].
var _steps: Array = []
var _wait := 0
var _tag := ""
## Счётчики для отчёта.
var _mistakes := 0


func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	_main = scene.instantiate()
	_main.skip_menu = true
	root.add_child(_main)


func _cell_ch(l: int, p: int) -> String:
	if l < 0 or l >= _main.display_lines.size():
		return ""
	var line: String = _main.display_lines[l]
	if p < 0 or p >= line.length():
		return ""
	return line.substr(p, 1)


## Состояние модели одной строкой: где заяц, где ёж, какие метки.
func _model(tag: String) -> String:
	var l := int(_main.cursor_line)
	var p := int(_main.cursor_pos)
	var spots: Array[String] = []
	for k in _main.errors.keys():
		var parts: PackedStringArray = String(k).split(":")
		spots.append("%d:%d" % [int(parts[0]), int(parts[1])])
	spots.sort()
	var want := _cell_ch(l, p)
	var marked: bool = _main.errors.has(_main._key(l, p))
	# Какие строки текста сейчас видны: длинный уровень едет за курсором,
	# и метки на ушедших строках рисовать НЕЛЬЗЯ — сверка это учитывает.
	var vis: int = _main._vis_lines()
	var rows: int = _main.display_lines.size()
	var first: int = clampi(int(_main.cursor_line) - vis + 1, 0, maxi(0, rows - vis))
	var line := "МОДЕЛЬ %s: курсор=%d:%d ждёт=%s%s меток=%d [%s] заяц.x=%.0f клетка.x=%.0f ёж.x=%.0f %s ошибок=%d строки=%d..%d" % [
		tag, l, p, want,
		"" if _main._is_active(want) or marked or want == "" else "(серая)",
		_main.errors.size(), " ".join(spots),
		_main.hero_r.x, _main._cursor_cx(), _main.enemy_x, _main.state,
		_main.typed_bad, first, mini(rows - 1, first + vis - 1),
	]
	# Где стоят сами герои и каким кругом их закрывать: на табло укола
	# спрайты накрывают метку прямо в точке касания — сверка это знает.
	var hr: float = 0.5 * _main.HERO_TEX.get_width() * _main._spr_scale(_main.HERO_TEX, _main._unit_h()).x
	var er: float = 0.5 * _main.HEDGE_TEX.get_width() * _main._spr_scale(_main.HEDGE_TEX, _main._unit_h()).x
	line += "\nГЕРОИ заяц=%.0f,%.0f,%.0f ёж=%.0f,%.0f,%.0f" % [
		_main.hero_r.x, _main.hero_r.y, hr,
		_main.enemy_x + _main._hedge_half(), _main._track_cy(_main.enemy_line), er,
	]
	# Где именно каждая метка должна оказаться на экране: та же формула,
	# что у маркера курсора и у раскладки текста. Проверяющий скрипт ищет
	# красные пиксели ровно в этих прямоугольниках.
	for k in _main.errors.keys():
		var parts: PackedStringArray = String(k).split(":")
		var ml := int(parts[0])
		var line_txt: String = _main.display_lines[ml]
		var w: float = _main._glyph_w(line_txt)
		var cx: float = _cell_x(ml, int(parts[1]))
		var yy: float = _main._line_y(ml)
		var hh: float = _main.mono.get_height(_main.font_size)
		line += "\nМЕТКА %s rect=%.0f,%.0f,%.0f,%.0f" % [
			k, cx - w * 0.5 - 2.0, yy - 3.0, cx + w * 0.5 + 2.0, yy + hh + 3.0,
		]
	return line


## Экранный центр символа в строке l, позиции p — та же формула, что
## в _draw_cursor_marker.
func _cell_x(l: int, p: int) -> float:
	var line: String = _main.display_lines[l]
	var pre: float = _main.mono.get_string_size(
		line.left(p), HORIZONTAL_ALIGNMENT_LEFT, -1.0, _main.font_size
	).x
	return _main.margin + pre + _main._glyph_w(line) * 0.5


func _snap() -> void:
	_shot_i += 1
	var img := root.get_texture().get_image()
	var name := "vis-%02d-%s" % [_shot_i, _tag]
	print("КАДР_РАЗМЕР %d %d игровой вид %.0fx%.0f k=%.3f" % [img.get_width(), img.get_height(), _main.view_w, _main.view_h, _main.k])
	img.save_png(SAVE_DIR + name + ".png")
	print(_model(_tag))
	print("КАДР ", SAVE_DIR + name + ".png")


func _fresh(difficulty: int, all_keys: int) -> void:
	_main.all_keys_override = all_keys
	_main.difficulty = difficulty
	_main._new_level()
	# Ёж в начале партии не выкатывается (в живой игре он появляется,
	# когда заяц уходит на вторую строку). Держать его на margin
	# бессмысленно: он наезжает на первые буквы и портит кадр.
	_main.grace_t = 9999.0
	_main.enemy_cps = 0.0
	_main.hedge_active = false
	_main.enemy_line = 0
	_main.enemy_x = _main.margin
	_main.hero_r = _main._hero_pos()


func _wrong() -> String:
	var cur: String = _main._current()
	return "ы" if cur.to_lower() != "ы" else "ж"


# --- действия сценария ----------------------------------------------

func _a_fresh_kid() -> void:
	_fresh(0, 0)


## Экранная клавиатура: телефонная раскладка, заяц уходит вперёд.
func _a_touch_on() -> void:
	# Новый уровень: предыдущий кадр — проигрыш, а своя клавиатура на
	# модалке не показывается (там ввод не нужен).
	_win(Vector2i(820, 1180))
	_main._force_touch = true
	_fresh(0, 0)
	for i in 8:
		_main._type_char(_main._current())
	_main._relayout()


func _a_touch_press() -> void:
	# Жмём клавишу, которую игра ждёт, и сразу следом — неверную: так
	# видно и принятую букву, и красную метку на экране.
	var want: String = _main._current()
	var btns := {}
	for b in Kbd.buttons(_main._own_rect(), _main.kb_layer, _main.kb_lang, _main.kb_shift):
		var rect: Rect2 = b["r"]
		btns[String(b["s"])] = rect.get_center()
		if String(b["s"]) == "пробел":
			btns[" "] = rect.get_center()
	if want != want.to_lower() and btns.has("⇧"):
		_main._own_press(btns["⇧"])
	if btns.has(want):
		_main._own_press(btns[want])
	# Одна буква: допечатывать уровень не надо — на экране победы своей
	# клавиатуры нет, и кадры после него показывали бы не то.


func _a_touch_wrong() -> void:
	var cur: String = _main._current()
	_main._type_char("ы" if cur.to_lower() != "ы" else "ж")


## Долгое нажатие е→ё: ставим зайца перед «е» или «ь», жмём и отпускаем
## позже порога.
func _a_long_press() -> void:
	for l in _main.display_lines.size():
		var line: String = _main.display_lines[l]
		for p in line.length():
			if line.substr(p, 1) in ["е", "ь"] and (l > 0 or p > 0):
				_main.cursor_line = l
				_main.cursor_pos = p
				_main.hero_r = _main._hero_pos()
				var btns := {}
				for b in Kbd.buttons(_main._own_rect(), _main.kb_layer, _main.kb_lang, _main.kb_shift):
					btns[String(b["s"])] = (b["r"] as Rect2).get_center()
				var ch: String = _main._current()
				if not btns.has(ch):
					return
				_main._own_press(btns[ch])
				_main._lp_t0 = Time.get_ticks_msec() - int(_main.LONG_PRESS_MS) - 60
				_main._own_release(btns[ch])
				return


## Поворот экрана: узкое окно, перераскладка на лету.
func _a_rotate() -> void:
	_win(Vector2i(1180, 560))
	_main._relayout()


func _a_rotate_back() -> void:
	_win(Vector2i(820, 1180))
	_main._relayout()


## Размер окна — И через DisplayServer, И у корня: get_viewport_rect()
## берёт размер окна, и под полноэкранным режимом один вызов не
## срабатывает (кадры «landscape» приезжали старого размера).
## Кадры с новыми подсказками: «Долго жми е → ё» (на своей клавиатуре
## клавиши «ё» нет вовсе) и «Жми: ?123 → :» (символ живёт только на
## слое знаков). Текст уровня задаём сами — иначе кадр зависит от того,
## выпал ли такой символ из случайного фрагмента.
func _a_yo_hint() -> void:
	_win(Vector2i(820, 1180))
	_main._force_touch = true
	_set_text("Ёжик идёт по лугу:", "дом был тут.", 0)
	_main._relayout()


func _a_sym_hint() -> void:
	_win(Vector2i(820, 1180))
	_main._force_touch = true
	_set_text("Дверь: открыта -", "тихо.", 5)
	_main._relayout()


## Свой текст уровня и курсор на указанной позиции первой строки.
func _set_text(first: String, second: String, pos: int) -> void:
	var lines: Array[String] = [first, second]
	_main.display_lines = lines
	_main._reindex_lines()
	_main.active.clear()
	for line in _main.display_lines:
		for i in line.length():
			_main.active[line.substr(i, 1)] = true
	_main.cursor_line = 0
	_main.cursor_pos = pos
	_main.hero_r = _main._hero_pos()
	_main.state = "playing"
	_main.typed_cells.clear()
	_main.passed.clear()
	_main.errors.clear()
	# Текст на экране — это Label-ы: их наполняет _refresh, а _relayout
	# двигает только геометрию. Без _refresh кадр снял бы старый текст.
	_main._refresh()


func _win(wh: Vector2i) -> void:
	DisplayServer.window_set_size(wh)
	root.size = wh
	_main._relayout()


func _a_fresh_all() -> void:
	_fresh(2, 1)


func _a_type_one() -> void:
	_main._type_char(_main._current())


func _a_type_9() -> void:
	for i in 9:
		_main._type_char(_main._current())


func _a_mistake() -> void:
	_main._type_char(_wrong())
	_mistakes += 1


func _a_mistake4() -> void:
	for i in 4:
		_main._type_char(_wrong())
	_mistakes += 4


func _a_mistake2() -> void:
	for i in 2:
		_main._type_char(_wrong())
	_mistakes += 2


func _a_clear_one() -> void:
	_main._type_char(_main._current())


func _a_clear_all() -> void:
	for i in 8:
		_main._type_char(_main._current())


func _a_to_second_line() -> void:
	while int(_main.cursor_line) < 1 and _main.state == "playing":
		_main._type_char(_main._current())


## Довести зайца до самого начала второй строки: оттуда откат назад
## перескакивает через перенос (проверка «откат через угол строк» глазами).
func _a_to_line_start() -> void:
	var guard := 0
	while guard < 4000 and _main.state == "playing":
		guard += 1
		if int(_main.cursor_line) >= 1 and int(_main.cursor_pos) == 0:
			return
		_main._type_char(_main._current())


func _a_night() -> void:
	_main.night = true
	_main._apply_night()
	_main._refresh()


func _a_day() -> void:
	_main.night = false
	_main._apply_night()
	_main._refresh()


func _a_win() -> void:
	while _main.state == "playing":
		var cur: String = _main._current()
		if cur == "":
			break
		_main._type_char(cur)


func _a_type6() -> void:
	for i in 6:
		_main._type_char(_main._current())


func _a_prick() -> void:
	_main.grace_t = 0.0
	_main.hedge_active = true
	_main.enemy_line = int(_main.cursor_line)
	_main.enemy_x = _main.margin + (
		_main._lin(int(_main.cursor_line), float(_main.cursor_pos))
		+ _main._touch_chars() - 0.02
	) * _main.char_w


func _process(_dt: float) -> bool:
	_frame += 1
	# Первые кадры — сцене на _ready и первому рендеру. Пока сценарий
	# не собран (_frame < 3), выходить рано: список шагов ещё пуст, и
	# пустой список означает «сценарий кончился».
	if _frame < 3:
		return false
	if _frame == 3:
		_plan()
	# Выходим только когда список пуст И последний кадр доснят: иначе
	# последний шаг выпадал — список кончался, а таймер кадра ещё тикал
	# (кадр 23 и все, что добавляли после, молча не снимались).
	if _steps.is_empty() and _wait <= 0:
		return true
	if _wait > 0:
		_wait -= 1
		if _wait == 0:
			# Состояние шага отрисовалось — снимаем и печатаем модель.
			_snap()
		return false
	var step: Array = _steps.pop_front()
	_tag = String(step[0])
	step[1].call()
	_wait = int(step[2])
	return false


## Сценарий: события и что должно быть видно на экране в этот момент.
func _plan() -> void:
	# 1. Старт уровня, обычный режим (буквы серые, игра проходит их сама).
	_steps = [
		["01-start", _a_fresh_kid, 20],
		# 2. Вглубь текста верными буквами.
		["02-typed", _a_type_9, 30],
		# 3. Одна ошибка: метка на букве, заяц на символ назад.
		["03-mistake", _a_mistake, 30],
		# 4. Пачка: четыре ошибки подряд — сплошная стопка меток.
		["04-burst", _a_mistake4, 40],
		# 5. Разбор стека: одна верная буква гасит ровно одну метку.
		["05-clear-one", _a_clear_one, 30],
		# 6. Стек разобран целиком.
		["06-cleared", _a_clear_all, 30],
		# 7. Перенос строки: откат через угол — заяц идёт на строку назад.
		["07-wrap", _a_to_second_line, 30],
		["08-wrap-back", _a_mistake2, 40],
		# 8б. Откат ЧЕРЕЗ перенос: заяц стоит в начале второй строки,
		#     ошибка уводит его на конец первой — проверяем, что он
		#     действительно перепрыгнул на строку назад.
		["08b-wrap-to-line", _a_to_line_start, 20],
		["08c-wrap-retreat", _a_mistake, 40],
		# 9. Та же сцена в ночной теме.
		["09-night", _a_night, 20],
		["10-day", _a_day, 20],
		# 10. Победа: допечатываем уровень верно.
		["11-win", _a_win, 40],
		# 11. Проигрыш: ёж вплотную, табло укола.
		["12-prick-prep", _a_fresh_all, 10],
		["13-prick-marks", _a_type6, 20],
		["14-prick-marks2", _a_mistake2, 20],
		["15-prick", _a_prick, 6],
		["16-prick-held", _a_clear_one, 30],
		# 12. Экранная клавиатура (телефонный портрет + тач-ввод).
		["17-touch-on", _a_touch_on, 30],
		["18-touch-typed", _a_touch_press, 30],
		["19-touch-mistake", _a_touch_wrong, 30],
		# 13. Долгое нажатие е→ё на своей клавиатуре.
		["20-long-press", _a_long_press, 30],
		# 14. Поворот экрана: перераскладка посреди партии.
		["21-landscape", _a_rotate, 30],
		["22-landscape-mistake", _a_touch_wrong, 30],
		["23-back-portrait", _a_rotate_back, 30],
		# 15. Подсказки для букв без клавиши и для символов со слоя знаков.
		["24-yo-hint", _a_yo_hint, 30],
		["25-sym-hint", _a_sym_hint, 30],
	]
