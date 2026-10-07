extends Node2D
## Меню игроков: список профилей, поле ввода имени, гостевой режим.
##
## Поведение перенесено из pygame-прототипа (git show 1a097c0:main.py):
##   ↑ / ↓      прокрутка списка, с перехватом через конец
##   Enter      в поле ввода — создать профиль (или войти, если имя есть),
##              без поля — войти выбранным
##   Tab        показать / спрятать поле ввода
##   A          все клавиши у выбранного профиля (взрослый режим:
##              активны все знаки сразу). Работает только при неактивном
##              поле ввода, поэтому не мешает набору имени
##   Delete     удалить выбранный профиль
##   Backspace  стереть символ в поле ввода
##   Esc        гость — играть без профиля, прогресс не сохраняется
##   Системная клавиатура Android шлёт события без keycode: Enter ловим
##   ещё и по unicode 10/13, Backspace — по unicode 8 (игру см. в main.gd).
##
## Сигналы: chosen(name) — пустое имя означает гостя.

const S := preload("res://scripts/save.gd")

signal chosen(user_name: String)

const BASE_W := 1100.0
const BASE_H := 650.0
const ROW_H := 62.0
const FONT_TITLE := 40
const FONT_ROW := 30
const FONT_SMALL := 20
const PAPER := Color("#f7f3e8")
const INK := Color("#1c1a16")
const UI_TEXT := Color("#4a4438")
const DIM := Color("#8d8778")
const HERO_TEX: Texture2D = preload("res://assets/hero.png")

var users: Array[String] = []
var sel := 0
var input_active := false
var input_text := ""
## Флаг «все клавиши» для имени, которое прямо сейчас вводится (списка
## ещё нет — применять не к кому). При создании профиля переносится
## в него, затем сбрасывается.
var input_all_keys := false
## То же для строгой ё (колонка «Ё»): ждёт создания профиля.
var input_yo_strict := true
## Выбранная колонка флагов: 0 — «Про», 1 — «Ё». Стрелки ←/→ двигают,
## пробел переключает. Видна подсветкой заголовка.
var sel_col := 0
## Подсказка по заголовку колонки («pro»/«yo»): тап по заголовку
## объясняет, что за галка. Пусто — молчим.
var hint_header := ""
## Игрок, ради которого меню открыли: F2 возвращает в игру с ним.
var resume_user := ""
## Удаление на подтверждении: имя профиля, ждущего «Да». Пусто — модалки
## нет, меню живёт как обычно. Пока висит — весь остальной ввод глушим.
var confirm_name := ""
var view_w := BASE_W
var view_h := BASE_H
var k := 1.0
## Высота клавиатуры в пикселях канваса (ставит игра из своего kb_h —
## см. main._relayout/_open_menu; 0 — скрыта). Низ, занятый клавиатурой,
## не наш: блок строк и подсказка считаются от эффективной высоты,
## иначе поле ввода и кнопки уезжают под Gboard на живом телефоне.
## На стенде keyboard не вызывается (гейт движка), проверяется
## симуляцией через игру (F4 в дебажной сборке) + profiles_test.
var kb_h := 0.0
var mono: Font
## Оформление (только картинка): скруглённые чипсы под строками,
## рамка поля ввода и пилюля подсказки. Строки и тексты не меняются —
## их проверяют тесты, поэтому здесь лишь рамки вокруг тех же слов.
var row_sb: StyleBoxFlat
var row_idle_sb: StyleBoxFlat
var box_sb: StyleBoxFlat
var hint_sb: StyleBoxFlat
## Ночь (S.resolve_night: ручной выбор или система). Краски берутся
## из хелперов _ink/_uitext/_dim, панели мутируют в _apply_night.
var night := false
var _meadow: Meadow = null


func _ready() -> void:
	mono = load("res://fonts/DejaVuSansMono.ttf")
	if mono == null:
		var fallback := SystemFont.new()
		fallback.font_names = PackedStringArray(["monospace"])
		mono = fallback
	row_sb = _panel_sb(Color("#f0d98a"), 12.0)
	row_idle_sb = _panel_sb(Color(1, 1, 1, 0.45), 12.0)
	box_sb = _panel_sb(Color("#ffffff"), 10.0, INK, 2.0, false)
	hint_sb = _panel_sb(Color(1, 1, 1, 0.72), 14.0, Color("#e0d5bd"), 1.5, false)
	_meadow = Meadow.new()
	add_child(_meadow)
	_apply_night()
	get_tree().root.size_changed.connect(_relayout)
	_relayout()
	_reload()


func _relayout() -> void:
	var s := get_viewport_rect().size
	if s.x <= 0.0 or s.y <= 0.0:
		return
	view_w = s.x
	view_h = s.y
	# Масштаб — от эффективной высоты (минус клавиатура), как в игре:
	# иначе в альбомной с клавиатурой блок меню не влезает над ней.
	k = clampf(minf(view_w / BASE_W, _menu_eff_h() / BASE_H), 0.5, 2.5)
	queue_redraw()


## Перечитать список с диска и встать на разумную позицию.
func _reload() -> void:
	users = S.user_list()
	if sel >= users.size():
		sel = maxi(0, users.size() - 1)
	# Модалка список не переживает: ушли из меню через F2 посреди
	# подтверждения — при следующем открытии чистый список, а не
	# вчерашний вопрос.
	confirm_name = ""
	# Пустой список — это первый запуск: курсор сразу в поле имени.
	# Иначе буквы уходят в никуда, и кажется, что игра не реагирует.
	# Набирать имя при пустом списке больше нечем, так что неактивное
	# поле здесь — просто ловушка.
	if users.is_empty():
		input_active = true
		input_text = ""
	queue_redraw()


func _unhandled_key_input(event: InputEvent) -> void:
	var ke := event as InputEventKey
	if ke == null or not ke.pressed or ke.echo:
		return
	# Скрытое меню клавиш не видит: иначе оно перехватывает ввод раньше
	# игры (оно добавлено позже и получает _unhandled_key_input первым).
	# Без этого F2 во время игры не открывал меню, а молча перезапускал
	# гостя, буква Ф на русской раскладке (тот же keycode, что и A)
	# переключала «все клавиши», а Tab уводил буквы в невидимое поле.
	if not visible:
		return
	# Модалка подтверждения — только свои клавиши, остальное мимо:
	# Enter/Д — «Да», Esc/N — «Нет». Д — та же физическая клавиша,
	# что L (раскладка не важна, смотрим keycode), N — KEY_N.
	if confirm_name != "":
		if (
			ke.keycode == KEY_ENTER or ke.keycode == KEY_KP_ENTER
			or ke.unicode == 10 or ke.unicode == 13
			or ke.keycode == KEY_L
		):
			_confirm_delete()
		elif ke.keycode == KEY_ESCAPE or ke.keycode == KEY_N:
			_cancel_confirm()
		_eaten()
		return
	# F2 — вернуться в игру тем же игроком, кого открыли меню.
	if ke.keycode == KEY_F2:
		chosen.emit(resume_user)
		_eaten()
		return
	if ke.keycode == KEY_UP:
		_nav(-1)
		_eaten()
		return
	if ke.keycode == KEY_DOWN:
		_nav(1)
		_eaten()
		return
	# Стрелки ←/→ — выбор колонки флагов (Про/Ё), пробел — переключить
	# флаг у выбранной строки. В поле ввода пробел молчит (имени
	# с пробелами не бывает), модалку стрелки не трогают (она выше).
	if ke.keycode == KEY_LEFT:
		sel_col = (sel_col + 1) % 2
		queue_redraw()
		_eaten()
		return
	if ke.keycode == KEY_RIGHT:
		sel_col = (sel_col + 1) % 2
		queue_redraw()
		_eaten()
		return
	if ke.keycode == KEY_SPACE:
		_toggle_flag()
		_eaten()
		return
	if ke.keycode == KEY_ENTER or ke.keycode == KEY_KP_ENTER or ke.unicode == 10 or ke.unicode == 13:
		_enter()
		_eaten()
		return
	if ke.keycode == KEY_TAB:
		_toggle_input()
		_eaten()
		return
	if ke.keycode == KEY_DELETE:
		_delete()
		_eaten()
		return
	if ke.keycode == KEY_ESCAPE:
		_guest()
		_eaten()
		return
	if ke.keycode == KEY_BACKSPACE or ke.unicode == 8:
		if not input_active:
			return
		input_text = input_text.left(maxi(0, input_text.length() - 1))
		queue_redraw()
		_eaten()
		return
	# Взрослый режим — только когда поле ввода неактивно, иначе это буква.
	if not input_active and _letter(ke) == "a":
		_toggle_all_keys()
		_eaten()
		return
	if not input_active or ke.unicode == 0:
		return
	var ch := String.chr(ke.unicode)
	# Пропускаем управляющие символы (меньше пробела) и пробелы: в имени
	# их быть не должно, а имя всё равно обрежется по краям.
	if ke.unicode < 32 or ch == " " or input_text.length() >= S.MAX_NAME_LENGTH:
		return
	input_text += ch
	queue_redraw()
	_eaten()


## Клавиша обслужена меню: игре её не отдавать, иначе Backspace
## в поле имени заодно откатывал бы зайца, а A-переключатель —
## печатался. Остальное (F3, F11) меню не трогает — их разбирает игра.
func _eaten() -> void:
	get_viewport().set_input_as_handled()


## Тач и мышь: строки, поле, кнопки. Скрытое меню тычков не видит —
## тот же урок, что с клавишами.
func _input(event: InputEvent) -> void:
	if not visible:
		return
	# Координаты тычка могут быть и отрицательными (узкое окно, край
	# экрана), поэтому признак «тычка не было» — отдельный флаг,
	# а не сентинел в координатах. Слушаем только мышь: палец на
	# Android сам превращается в клик, а двойная обработка касания
	# и клика давала бы двойные срабатывания (галочка вкл-выкл
	# за один палец). На десктопе касаний нет — ничего не меняется.
	var has_pos := false
	var pos := Vector2.ZERO
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			pos = mb.position
			has_pos = true
	if not has_pos:
		return
	# Модалка — только свои две кнопки, остальное мимо.
	if confirm_name != "":
		if _confirm_yes_rect().has_point(pos):
			_confirm_delete()
			get_viewport().set_input_as_handled()
		elif _confirm_no_rect().has_point(pos):
			_cancel_confirm()
			get_viewport().set_input_as_handled()
		return
	# Прямоугольники — из тех же хелперов, что рисует _draw: единый
	# источник геометрии, работает и без отрисовки (тесты headless).
	# Внутри строки сначала точечные цели (галочка, крестик), потом
	# сама строка: иначе тап по галочке играл бы этим профилем.
	for i in users.size():
		if _pro_tap_rect(i).has_point(pos):
			_toggle_pro(i)
			get_viewport().set_input_as_handled()
			return
		if _yo_tap_rect(i).has_point(pos):
			_toggle_yo(i)
			get_viewport().set_input_as_handled()
			return
		if _del_tap_rect(i).has_point(pos):
			confirm_name = users[i]
			queue_redraw()
			get_viewport().set_input_as_handled()
			return
	for i in users.size():
		if _row_tap_rect(i).has_point(pos):
			chosen.emit(users[i])
			get_viewport().set_input_as_handled()
			return
	# Заголовки «Про»/«Ё» — подсказка, что за галка. Повторный тап гасит.
	if not users.is_empty() and _pro_head_rect().has_point(pos):
		hint_header = "" if hint_header == "pro" else "pro"
		queue_redraw()
		get_viewport().set_input_as_handled()
		return
	if not users.is_empty() and _yo_head_rect().has_point(pos):
		hint_header = "" if hint_header == "yo" else "yo"
		queue_redraw()
		get_viewport().set_input_as_handled()
		return
	if users.is_empty() and _check_tap_rect().has_point(pos):
		_toggle_all_keys()
		get_viewport().set_input_as_handled()
		return
	if users.is_empty() and _yocheck_tap_rect().has_point(pos):
		input_yo_strict = not input_yo_strict
		queue_redraw()
		get_viewport().set_input_as_handled()
		return
	if _field_tap_rect().has_point(pos):
		if not input_active:
			_toggle_input()
		_kb_show()
		get_viewport().set_input_as_handled()
		return
	if _play_tap_rect().has_point(pos):
		_enter()
		get_viewport().set_input_as_handled()
		return
	if _guest_tap_rect().has_point(pos):
		_guest()
		get_viewport().set_input_as_handled()
		return
	if _night_tap_rect().has_point(pos):
		_toggle_night()
		get_viewport().set_input_as_handled()
		return
	# Кнопка ⌨ — только там, где есть системная клавиатура (телефон):
	# на десктопе она ничего не делала и только путала.
	if not _is_desktop() and _mkb_tap_rect().has_point(pos):
		if not input_active:
			_toggle_input()
		_kb_show()
		get_viewport().set_input_as_handled()
		return


## Показать системную клавиатуру прямо отсюда (тап по полю/кнопке ⌨):
## ждать кадра игры незачем, а на десктопе это no-op.
func _kb_show() -> void:
	if DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD):
		DisplayServer.virtual_keyboard_show("")


## Десктоп — там, где нет системной клавиатуры: кнопка ⌨ там
## ничего не делала и только путала, поэтому её нет (и тычка тоже).
func _is_desktop() -> bool:
	return not DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD)


## Буква по коду клавиши: «A» без физической раскладки (в латинице на
## русской раскладке KeyA тоже проходит). Ручная раскладка не важна:
## клавиша одна и та же.
func _letter(ke: InputEventKey) -> String:
	if ke.keycode == KEY_A:
		return "a"
	return ""


func _nav(direction: int) -> void:
	if users.is_empty():
		return
	sel = (sel + direction + users.size()) % users.size()
	queue_redraw()


func _toggle_input() -> void:
	input_active = not input_active
	if not input_active:
		input_text = ""
	queue_redraw()


## Стиль скруглённой панели (тот же приём, что в main.gd).
func _panel_sb(bg: Color, radius: float, border := Color(0, 0, 0, 0), bw := 0.0, shadow := false) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(int(radius))
	if bw > 0.0:
		sb.set_border_width_all(int(bw))
		sb.border_color = border
	if shadow:
		sb.shadow_color = Color(0.25, 0.20, 0.12, 0.18)
		sb.shadow_size = 6
		sb.shadow_offset = Vector2(0, 3)
	return sb


func _enter() -> void:
	if input_active and not input_text.strip_edges().is_empty():
		var name := S.clean_name(input_text)
		# Новое имя — создать, существующее — просто войти. Флаги
		# вводимого имени переезжают в созданный профиль.
		if not S.user_exists(name):
			S.create_user(name)
			S.set_all_keys(name, input_all_keys)
			S.set_yo_strict(name, input_yo_strict)
		else:
			S.touch(name)
		input_text = ""
		input_active = false
		input_all_keys = false
		input_yo_strict = true
		chosen.emit(name)
		return
	if not users.is_empty():
		chosen.emit(users[sel])
		return
	# Список пуст и ввод выключен — единственный выход, гость.
	_guest()


func _delete() -> void:
	if input_active or users.is_empty():
		return
	# Удаление непоправимо — только через подтверждение.
	confirm_name = users[sel]
	queue_redraw()


## Подтверждено: снести и вернуться в список.
func _confirm_delete() -> void:
	if confirm_name != "":
		S.delete_user(confirm_name)
	confirm_name = ""
	_reload()


## Отмена: профиль цел, модалка гаснет.
func _cancel_confirm() -> void:
	confirm_name = ""
	queue_redraw()


func _toggle_all_keys() -> void:
	if users.is_empty():
		# Пустой список (первый запуск): переключаем флаг для вводимого
		# имени — при создании он переедет в профиль (см. _enter).
		input_all_keys = not input_all_keys
		queue_redraw()
		return
	var name := users[sel]
	S.set_all_keys(name, not S.get_all_keys(name))
	_reload()


## Про-режим строке: все клавиши сразу именно этому игроку.
func _toggle_pro(i: int) -> void:
	if i < 0 or i >= users.size():
		return
	var name := users[i]
	S.set_all_keys(name, not S.get_all_keys(name))
	_reload()


## Строгая ё строке: различать ё и е именно этому игроку.
func _toggle_yo(i: int) -> void:
	if i < 0 or i >= users.size():
		return
	var name := users[i]
	S.set_yo_strict(name, not S.get_yo_strict(name))
	_reload()


## Пробел по флагам: выбранная стрелками колонка (sel_col) у выбранной
## строки — или у вводимого имени, если список пуст.
func _toggle_flag() -> void:
	if input_active or confirm_name != "":
		return
	if users.is_empty():
		if sel_col == 0:
			input_all_keys = not input_all_keys
		else:
			input_yo_strict = not input_yo_strict
		queue_redraw()
		return
	if sel_col == 0:
		_toggle_pro(sel)
	else:
		_toggle_yo(sel)


func _guest() -> void:
	S.set_last_user(S.GUEST)
	chosen.emit(S.GUEST)


## Ячейки строки таблицы: уровень и счёт «побед из игр». Шапка
## объясняет колонки, поэтому в ячейках только цифры.
func _cell_texts(name: String) -> Array[String]:
	var p := S.load_profile(name)
	var res: Array[String] = [
		"ур.%d" % int(p.get("difficulty", 0)),
		"%d/%d" % [int(p.get("total_wins", 0)), int(p.get("total_games", 0))],
	]
	return res


## Колонки таблицы [имя, уровень, счёт, Про, Ё, ✕]: левые края
## и правый край. Имя занимает остаток (длинные режем с многоточием),
## остальные — по самой широкой ячейке. Та же геометрия у отрисовки,
## хит-теста и тестов: мимо не бьёт.
func _table_cols() -> Array[float]:
	var left := 48.0 * k
	var right := view_w - 48.0 * k
	var gap := 12.0 * k
	var del_w := 44.0 * k
	var pro_w := _text_size("Про", FONT_SMALL).x + 44.0 * k
	var yo_w := _text_size("Ё", FONT_SMALL).x + 44.0 * k
	var lvl_w := _text_size("Ур", FONT_SMALL).x + 16.0 * k
	var rec_w := _text_size("Победы", FONT_SMALL).x + 16.0 * k
	for u in users:
		var cells := _cell_texts(u)
		lvl_w = maxf(lvl_w, _text_size(cells[0], FONT_ROW).x + 16.0 * k)
		rec_w = maxf(rec_w, _text_size(cells[1], FONT_ROW).x + 16.0 * k)
	var fixed := lvl_w + rec_w + pro_w + yo_w + del_w + gap * 5.0
	var name_w := maxf(80.0 * k, right - left - fixed)
	var name_x := left
	var lvl_x := left + name_w + gap
	var rec_x := lvl_x + lvl_w + gap
	var pro_x := rec_x + rec_w + gap
	var yo_x := pro_x + pro_w + gap
	var del_x := yo_x + yo_w + gap
	var cols: Array[float] = [name_x, lvl_x, rec_x, pro_x, yo_x, del_x, right]
	return cols


## Имя в ширину колонки: длинное режем с многоточием, иначе таблица
## разъезжается (имена до 15 знаков).
func _short_name(name: String) -> String:
	var cols := _table_cols()
	var cap := cols[1] - cols[0] - 8.0 * k
	if _text_size(name, FONT_ROW).x <= cap:
		return name
	var out := name
	while out.length() > 1 and _text_size(out + "…", FONT_ROW).x > cap:
		out = out.left(out.length() - 1)
	return out + "…"


func _text_size(txt: String, size_px: int) -> Vector2:
	# Тот же кегль, что в _text: иначе рамки вокруг строк (чипсы,
	# пилюля подсказки) меряются в одном масштабе, а рисуются в другом.
	return mono.get_string_size(
		txt, HORIZONTAL_ALIGNMENT_LEFT, -1.0, int(float(size_px) * k)
	)


func _text(txt: String, pos: Vector2, size_px: int, col: Color) -> void:
	var fs := int(float(size_px) * k)
	draw_string(
		mono, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs, col
	)


## Строка поля ввода как текст (рамка и хит-тест строятся от неё).
func _field_text() -> String:
	var field := "Имя: " + input_text + ("|" if input_active else "")
	return ("> " if input_active else "  ") + field


## Базовая строка меню: заголовок + строки. Дальше всё считается от неё.
## В портрете блок опускаем, чтобы не кучковался сверху (низ пустой);
## альбом не трогаем. Тапы идут через те же хелперы — мимо не бьют.
## Центрирование — от эффективной высоты (минус клавиатура): иначе
## на телефоне с выездом клавиатуры блок остаётся под ней.
func _menu_eff_h() -> float:
	return maxf(view_h - kb_h, 220.0)


func _rows_top() -> float:
	var y := 90.0 * k + 70.0 * k
	if view_h > view_w:
		var eff := _menu_eff_h()
		var need := 170.0 * k + float(maxi(users.size(), 1)) * ROW_H * k + 220.0 * k
		y += maxf(0.0, (eff - need) * 0.22)
	return y


## Строка поля ввода: после заголовка, строк и отступа. Отдельной
## галочки между строками и полем больше нет: «Про» живёт в колонке
## таблицы, на пустом списке — компактной галочкой под полем.
func _field_line_y() -> float:
	return (
		_rows_top()
		+ float(maxi(users.size(), 1)) * ROW_H * k
		+ 34.0 * k
	)


## Строка галочки «Про» для вводимого имени (только пустой список):
## под полем ввода.
func _check_line_y() -> float:
	return _field_line_y() + 56.0 * k


## Галочка «Про» для вводимого имени: тот же флаг, что у профилей,
## но до создания — переедет в профиль (см. _enter).
func _check_tap_rect() -> Rect2:
	var y := _check_line_y()
	var w := _text_size("Про", FONT_ROW).x
	return Rect2(48.0 * k, y - 36.0 * k, w + 84.0 * k, 48.0 * k)


## Компактная галка «Ё» на пустом списке: та же строка, правее.
func _yocheck_tap_rect() -> Rect2:
	var y := _check_line_y()
	var w := _text_size("Ё", FONT_ROW).x
	return Rect2(198.0 * k, y - 36.0 * k, w + 84.0 * k, 48.0 * k)


## Строка кнопок: под полем ввода, на пустом списке — под галочкой
## «Про» для вводимого имени.
func _buttons_y() -> float:
	return _field_line_y() + 64.0 * k + (56.0 * k if users.is_empty() else 0.0)


## Чипс строки: во всю ширину таблицы. Та же геометрия, что _draw.
func _row_tap_rect(i: int) -> Rect2:
	var cols := _table_cols()
	var row_y := _rows_top() + float(i) * ROW_H * k
	return Rect2(
		cols[0] - 16.0 * k, row_y - 38.0 * k,
		cols[6] - cols[0] + 32.0 * k, ROW_H * k - 6.0 * k
	)


## Галочка «Про» в строке: тот же переключатель, что клавиша A,
## но пальцем/мышью. Тап по ней не играет профилем, только флагом.
func _pro_tap_rect(i: int) -> Rect2:
	var cols := _table_cols()
	var row_y := _rows_top() + float(i) * ROW_H * k
	var cx := (cols[3] + cols[4]) * 0.5
	return Rect2(cx - 26.0 * k, row_y - 26.0 * k, 52.0 * k, 52.0 * k)


## Галочка «Ё» в строке: строгая ё именно этому игроку.
## Тап не играет профилем, только флагом.
func _yo_tap_rect(i: int) -> Rect2:
	var cols := _table_cols()
	var row_y := _rows_top() + float(i) * ROW_H * k
	var cx := (cols[4] + cols[5]) * 0.5
	return Rect2(cx - 26.0 * k, row_y - 26.0 * k, 52.0 * k, 52.0 * k)


## Крестик удаления в строке: открывает модалку подтверждения.
func _del_tap_rect(i: int) -> Rect2:
	var cols := _table_cols()
	var row_y := _rows_top() + float(i) * ROW_H * k
	var cx := (cols[5] + cols[6]) * 0.5
	return Rect2(cx - 24.0 * k, row_y - 24.0 * k, 48.0 * k, 48.0 * k)


## Заголовки «Про»/«Ё»: тап показывает, что за галка (hint_header).
func _pro_head_rect() -> Rect2:
	var cols := _table_cols()
	var cx := (cols[3] + cols[4]) * 0.5
	var y := _rows_top() - 44.0 * k
	return Rect2(cx - 48.0 * k, y - 28.0 * k, 96.0 * k, 40.0 * k)


func _yo_head_rect() -> Rect2:
	var cols := _table_cols()
	var cx := (cols[4] + cols[5]) * 0.5
	var y := _rows_top() - 44.0 * k
	return Rect2(cx - 48.0 * k, y - 28.0 * k, 96.0 * k, 40.0 * k)


## Рамка поля ввода (рисуется только когда активно, тыкается всегда).
func _field_tap_rect() -> Rect2:
	var y := _field_line_y()
	var fw := _text_size(_field_text(), FONT_ROW).x
	return Rect2(48.0 * k, y - 38.0 * k, maxf(fw + 48.0 * k, 420.0 * k), 54.0 * k)


## Краски текста под режим: днём константы, ночью светлые.
func _ink() -> Color:
	if night:
		return Color("#f2ede0")
	return INK


func _uitext() -> Color:
	if night:
		return Color("#cfd6e4")
	return UI_TEXT


func _dim() -> Color:
	if night:
		return Color("#8b93a8")
	return DIM


## Спрайт ночью темнее и холоднее (как в игре).
func _sprite_tint() -> Color:
	if night:
		return Color(0.72, 0.76, 0.90)
	return Color.WHITE


## Ночь: ручной выбор из файла важнее системы.
func _night_resolve() -> void:
	night = S.resolve_night(S.get_night_mode(), true, S.system_dark())


## Применить ночь: панели мутируют на месте, фон переключается.
func _apply_night() -> void:
	_night_resolve()
	if night:
		row_idle_sb.bg_color = Color(0.10, 0.12, 0.20, 0.60)
		box_sb.bg_color = Color("#232c44")
		box_sb.border_color = Color("#8b93a8")
		hint_sb.bg_color = Color(0.10, 0.12, 0.20, 0.80)
		hint_sb.border_color = Color("#3a4a6b")
	else:
		row_idle_sb.bg_color = Color(1, 1, 1, 0.45)
		box_sb.bg_color = Color("#ffffff")
		box_sb.border_color = INK
		hint_sb.bg_color = Color(1, 1, 1, 0.72)
		hint_sb.border_color = Color("#e0d5bd")
	if _meadow != null:
		_meadow.night = night
		_meadow._apply_sky()
	queue_redraw()


## Переключатель ночи (кнопка «Ночь»/«День»): выбор запоминается.
func _toggle_night() -> void:
	night = not night
	S.set_night_mode(S.NIGHT_ON if night else S.NIGHT_DAY)
	_apply_night()


## Кнопки «Играть», «Без профиля» и «Ночь»/«День»: тройка по центру.
func _play_tap_rect() -> Rect2:
	var y := _buttons_y()
	return Rect2(cx_of() - 337.0 * k, y, 230.0 * k, 52.0 * k)


func _guest_tap_rect() -> Rect2:
	var y := _buttons_y()
	return Rect2(cx_of() - 337.0 * k + 246.0 * k, y, 262.0 * k, 52.0 * k)


func _night_tap_rect() -> Rect2:
	var y := _buttons_y()
	return Rect2(cx_of() - 337.0 * k + 524.0 * k, y, 150.0 * k, 52.0 * k)


func cx_of() -> float:
	return view_w * 0.5


## Кнопка ⌨ справа вверху.
func _mkb_tap_rect() -> Rect2:
	return Rect2(view_w - 72.0 * k, 16.0 * k, 56.0 * k, 56.0 * k)


## Кнопки модалки подтверждения: «Да» и «Нет» по центру карточки.
func _confirm_yes_rect() -> Rect2:
	var c := _confirm_card_rect().get_center()
	return Rect2(c + Vector2(-190.0 * k, 24.0 * k), Vector2(170.0 * k, 56.0 * k))


func _confirm_no_rect() -> Rect2:
	var c := _confirm_card_rect().get_center()
	return Rect2(c + Vector2(20.0 * k, 24.0 * k), Vector2(170.0 * k, 56.0 * k))


## Карточка модалки: по центру экрана, по ширине текста вопроса.
func _confirm_card_rect() -> Rect2:
	var t := "Удалить «%s»?" % confirm_name
	var w := maxf(_text_size(t, FONT_ROW).x + 96.0 * k, 420.0 * k)
	var h := 210.0 * k
	return Rect2((view_w - w) * 0.5, (view_h - h) * 0.5, w, h)


## Опасное действие (крестик удаления): красный в обеих темах.
func _danger() -> Color:
	if night:
		return Color("#ff7a6b")
	return Color("#b02323")


## Включён ли взрослый режим: у выбранного — его флаг, на пустом
## списке — флаг вводимого имени.
func _check_on() -> bool:
	if users.is_empty():
		return input_all_keys
	return bool(S.load_profile(users[sel]).get("all_keys", false))


## Кнопка-пилюля с подписью по центру.
func _button(r: Rect2, label: String) -> void:
	draw_style_box(hint_sb, r)
	var fs := int(26.0 * k)
	var w := _text_size(label, 26).x
	_text(label, Vector2(r.get_center().x - w * 0.5, r.position.y + 36.0 * k), 26, _ink())


## Кнопка день/ночь: солнце (круг + лучи) или светящийся месяц.
## Иконка показывает, ВО ЧТО переключит: днём — месяц, ночью — солнце.
func _draw_daynight(r: Rect2) -> void:
	draw_style_box(hint_sb, r)
	var c := r.get_center()
	if night:
		var sr := 13.0 * k
		draw_line(c + Vector2(-sr, 0), c + Vector2(sr, 0), _ink(), 3.0 * k)
		draw_line(c + Vector2(0, -sr), c + Vector2(0, sr), _ink(), 3.0 * k)
		var d := Vector2(sr * 0.7, sr * 0.7)
		draw_line(c - d, c + d, _ink(), 3.0 * k)
		draw_line(c + Vector2(-d.x, d.y), c + Vector2(d.x, -d.y), _ink(), 3.0 * k)
		draw_circle(c, 7.0 * k, Color("#e8a13a"))
	else:
		# Светящийся месяц: бледный диск с тёплым ореолом и кратерами.
		# Виден и на светлой, и на тёмной пилюле — не «чёрная дыра».
		var mr := 10.0 * k
		draw_circle(c, mr * 2.1, Color(1.0, 0.95, 0.75, 0.18))
		draw_circle(c, mr * 1.5, Color(1.0, 0.96, 0.80, 0.25))
		draw_circle(c, mr, Color("#f4f1de"))
		draw_circle(c + Vector2(-mr * 0.3, -mr * 0.2), mr * 0.22, Color("#d9d4bd"))
		draw_circle(c + Vector2(mr * 0.25, mr * 0.3), mr * 0.15, Color("#d9d4bd"))


func _draw() -> void:
	# Вуаль вместо глухой заливки: игра позади чуть видна, и понятно,
	# что меню — пауза, а не другой экран. Строки и тексты те же, что
	# были, вокруг них лишь карточки.
	var veil := PAPER
	if night:
		veil = Color("#141a2c")
	veil.a = 0.94
	draw_rect(Rect2(Vector2.ZERO, Vector2(view_w, view_h)), veil)
	var cx := view_w * 0.5
	var y := _rows_top()
	var top := y - 70.0 * k
	var title := "Кто играет?"
	var title_w := _text_size(title, FONT_TITLE).x
	_draw_bunny(Vector2(cx - title_w * 0.5 - 78.0 * k, top - 20.0 * k))
	_text(
		title,
		Vector2(cx - title_w * 0.5, top),
		FONT_TITLE,
		_ink()
	)
	if users.is_empty():
		_text(
			"Пока нет сохранённых игроков",
			Vector2(cx - _text_size("Пока нет сохранённых игроков", FONT_ROW).x * 0.5, y),
			FONT_ROW,
			_dim()
		)
	# Таблица игроков: шапка + строки во всю ширину. Тап по строке
	# сразу играет этим игроком, тап по галочке — только флаг,
	# тап по крестику — удаление с подтверждением. Тап по заголовку
	# «Про»/«Ё» объясняет галку. Выбранная стрелками колонка подсвечена
	# в шапке (пробел переключает её флаг).
	if not users.is_empty():
		var hcols := _table_cols()
		_text("Имя", Vector2(hcols[0], y - 44.0 * k), FONT_SMALL, _dim())
		_text("Ур", Vector2(hcols[1], y - 44.0 * k), FONT_SMALL, _dim())
		_text("Победы", Vector2(hcols[2], y - 44.0 * k), FONT_SMALL, _dim())
		var pro_hw := _text_size("Про", FONT_SMALL).x
		_text(
			"Про",
			Vector2((hcols[3] + hcols[4]) * 0.5 - pro_hw * 0.5, y - 44.0 * k),
			FONT_SMALL, _ink() if sel_col == 0 else _dim()
		)
		var yo_hw := _text_size("Ё", FONT_SMALL).x
		_text(
			"Ё",
			Vector2((hcols[4] + hcols[5]) * 0.5 - yo_hw * 0.5, y - 44.0 * k),
			FONT_SMALL, _ink() if sel_col == 1 else _dim()
		)
	for i in users.size():
		var row_y := y + float(i) * ROW_H * k
		var cols := _table_cols()
		var chip := _row_tap_rect(i)
		draw_style_box(row_sb if i == sel else row_idle_sb, chip)
		# Выбранная строка всегда на жёлтом — тёмным текстом.
		var tcol := INK if i == sel else _ink()
		_text(
			_short_name(users[i]), Vector2(cols[0], row_y), FONT_ROW, tcol
		)
		var cells := _cell_texts(users[i])
		_text(cells[0], Vector2(cols[1], row_y), FONT_ROW, tcol)
		_text(cells[1], Vector2(cols[2], row_y), FONT_ROW, tcol)
		# Галочка «Про» по центру своей колонки. Цвет — от БОКСА, а не
		# от строки: бокс белый днём и тёмный ночью, а цвет строки
		# (tcol) на выбранной строке тёмный всегда — ночью галочка
		# тонула в тёмном боксе, стоило навести выделение.
		var chk_col := Color("#f2ede0") if night else INK
		var pcx := (cols[3] + cols[4]) * 0.5
		draw_style_box(box_sb, Rect2(pcx - 16.0 * k, row_y - 32.0 * k, 32.0 * k, 32.0 * k))
		if bool(S.load_profile(users[i]).get("all_keys", false)):
			draw_line(
				Vector2(pcx - 10.0 * k, row_y - 12.0 * k),
				Vector2(pcx, row_y - 2.0 * k),
				chk_col, 4.0 * k
			)
			draw_line(
				Vector2(pcx, row_y - 2.0 * k),
				Vector2(pcx + 16.0 * k, row_y - 26.0 * k),
				chk_col, 4.0 * k
			)
		# Галочка «Ё» по центру своей колонки: тот же бокс, тот же цвет.
		var ycx := (cols[4] + cols[5]) * 0.5
		draw_style_box(box_sb, Rect2(ycx - 16.0 * k, row_y - 32.0 * k, 32.0 * k, 32.0 * k))
		if bool(S.load_profile(users[i]).get("yo_strict", true)):
			draw_line(
				Vector2(ycx - 10.0 * k, row_y - 12.0 * k),
				Vector2(ycx, row_y - 2.0 * k),
				chk_col, 4.0 * k
			)
			draw_line(
				Vector2(ycx, row_y - 2.0 * k),
				Vector2(ycx + 16.0 * k, row_y - 26.0 * k),
				chk_col, 4.0 * k
			)
		# Крестик удаления по центру своей колонки.
		var dcx := (cols[5] + cols[6]) * 0.5
		# Выбранная стрелками галка подсвечена рамкой прямо на боксе:
		# заголовка в длинном списке глазами не проследить.
		if i == sel:
			var scx := pcx if sel_col == 0 else ycx
			draw_rect(
				Rect2(scx - 20.0 * k, row_y - 36.0 * k, 40.0 * k, 40.0 * k),
				_ink(), false, 2.5 * k
			)
		var dtxt := "✕"
		var dw := _text_size(dtxt, FONT_ROW)
		_text(dtxt, Vector2(dcx - dw.x * 0.5, row_y), FONT_ROW, _danger())
	y = _field_line_y()
	# Компактные галки для вводимого имени — только когда список пуст
	# (иначе флаги живут в колонках таблицы). Обе в одну строку:
	# места хватает, раскладку не двигаем. Выбранную стрелками колонку
	# обводим (пробел переключает её флаг).
	if users.is_empty():
		var cy := _check_line_y()
		var ychk_col := Color("#f2ede0") if night else INK
		draw_style_box(box_sb, Rect2(60.0 * k, cy - 32.0 * k, 32.0 * k, 32.0 * k))
		if _check_on():
			draw_line(
				Vector2(66.0 * k, cy - 12.0 * k), Vector2(76.0 * k, cy - 2.0 * k),
				ychk_col, 4.0 * k
			)
			draw_line(
				Vector2(76.0 * k, cy - 2.0 * k), Vector2(92.0 * k, cy - 26.0 * k),
				ychk_col, 4.0 * k
			)
		_text("Про", Vector2(104.0 * k, cy), FONT_ROW, _ink())
		if sel_col == 0:
			draw_rect(Rect2(56.0 * k, cy - 36.0 * k, 40.0 * k, 40.0 * k), _ink(), false, 2.0 * k)
		var yob := 210.0 * k
		draw_style_box(box_sb, Rect2(yob, cy - 32.0 * k, 32.0 * k, 32.0 * k))
		if input_yo_strict:
			draw_line(
				Vector2(yob + 6.0 * k, cy - 12.0 * k), Vector2(yob + 16.0 * k, cy - 2.0 * k),
				ychk_col, 4.0 * k
			)
			draw_line(
				Vector2(yob + 16.0 * k, cy - 2.0 * k), Vector2(yob + 32.0 * k, cy - 26.0 * k),
				ychk_col, 4.0 * k
			)
		_text("Ё", Vector2(yob + 44.0 * k, cy), FONT_ROW, _ink())
		if sel_col == 1:
			draw_rect(Rect2(yob - 4.0 * k, cy - 36.0 * k, 40.0 * k, 40.0 * k), _ink(), false, 2.0 * k)
	# Поле ввода нового имени. Рамка — только когда активно, а тыкается
	# всегда: тап включает ввод, как Tab.
	var field_txt := _field_text()
	if input_active:
		draw_style_box(box_sb, _field_tap_rect())
	_text(
		field_txt,
		Vector2(60.0 * k, y),
		FONT_ROW,
		_ink() if input_active else _dim()
	)
	# Кнопки действий: та же механика, что Enter и Esc, но пальцем.
	# Третья — ночь: иконка показывает, во что переключит.
	_button(_play_tap_rect(), "Играть")
	_button(_guest_tap_rect(), "Без профиля")
	_draw_daynight(_night_tap_rect())
	# Кнопка ⌨ справа вверху: вызвать системную клавиатуру.
	# На десктопе её нет (см. _input): нечего и рисовать.
	if not _is_desktop():
		draw_style_box(hint_sb, _mkb_tap_rect())
		for ix in 3:
			for iy in 2:
				draw_circle(
					_mkb_tap_rect().position + Vector2((14.0 + 14.0 * float(ix)) * k, (17.0 + 12.0 * float(iy)) * k),
					2.5 * k, _uitext()
				)
	# Пояснение галки по тапу на заголовок — строкой под кнопками.
	# Модалка его перекрывает (рисуется позже поверх).
	if hint_header != "" and confirm_name == "":
		var expl: Array[String] = []
		if hint_header == "pro":
			expl = ["Про: все буквы сразу,", "важен регистр."]
		else:
			expl = ["Ё: без галки", "е засчитывается за ё."]
		var ey := _buttons_y() + 52.0 * k + 30.0 * k
		for li in expl.size():
			var lw := _text_size(expl[li], FONT_SMALL).x
			_text(
				expl[li], Vector2(view_w * 0.5 - lw * 0.5, ey + 30.0 * k * float(li)),
				FONT_SMALL, _uitext()
			)
	# Модалка подтверждения удаления — поверх всего.
	if confirm_name != "":
		var dimmer := Color(0.05, 0.05, 0.08, 0.55)
		draw_rect(Rect2(Vector2.ZERO, Vector2(view_w, view_h)), dimmer)
		var card := _confirm_card_rect()
		draw_style_box(box_sb, card)
		var qt := "Удалить «%s»?" % confirm_name
		var qw := _text_size(qt, FONT_ROW).x
		_text(
			qt,
			Vector2(card.get_center().x - qw * 0.5, card.position.y + 62.0 * k),
			FONT_ROW, _ink()
		)
		_button(_confirm_yes_rect(), "Да")
		_button(_confirm_no_rect(), "Нет")


## Зайчик рядом с заголовком: тот же спрайт, что в игре.
func _draw_bunny(c: Vector2) -> void:
	var s := 76.0 * k / HERO_TEX.get_height()
	draw_set_transform(c, 0.0, Vector2(s, s))
	draw_texture(HERO_TEX, -HERO_TEX.get_size() * 0.5, _sprite_tint())
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
