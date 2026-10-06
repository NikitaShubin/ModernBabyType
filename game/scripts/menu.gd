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
const B := preload("res://scripts/balance.gd")

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
const ALL_KEYS_BADGE := "⌨ все клавиши"
const HERO_TEX: Texture2D = preload("res://assets/hero.png")

var users: Array[String] = []
var sel := 0
var input_active := false
var input_text := ""
## Флаг «все клавиши» для имени, которое прямо сейчас вводится (списка
## ещё нет — применять не к кому). При создании профиля переносится
## в него, затем сбрасывается.
var input_all_keys := false
## Игрок, ради которого меню открыли: F2 возвращает в игру с ним.
var resume_user := ""
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
	# RU-клавиатура — той же механикой, что A для «всех клавиш»:
	# клавиша R при неактивном поле, иначе — вторая галочка мышью.
	if not input_active and ke.keycode == KEY_R:
		_toggle_ru()
		_eaten()
		return
	if not input_active or ke.unicode == 0:
		return
	var ch := _menu_char(ke)
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
	# Прямоугольники — из тех же хелперов, что рисует _draw: единый
	# источник геометрии, работает и без отрисовки (тесты headless).
	for i in users.size():
		if _row_tap_rect(i).has_point(pos):
			chosen.emit(users[i])
			get_viewport().set_input_as_handled()
			return
	if _check_tap_rect().has_point(pos):
		_toggle_all_keys()
		get_viewport().set_input_as_handled()
		return
	if _ru_tap_rect().has_point(pos):
		_toggle_ru()
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
	if _mkb_tap_rect().has_point(pos):
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
		# Новое имя — создать, существующее — просто войти. Флаг
		# вводимого имени переезжает в созданный профиль.
		if not S.user_exists(name):
			S.create_user(name)
			S.set_all_keys(name, input_all_keys)
		else:
			S.touch(name)
		input_text = ""
		input_active = false
		input_all_keys = false
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
	S.delete_user(users[sel])
	_reload()


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


## RU-клавиатура: печатать русское с латинской (глобально, как ночь —
## это про устройство, а не про игрока).
func _toggle_ru() -> void:
	S.set_ru_kb(not S.get_ru_kb())
	queue_redraw()


## Символ из клавиши (та же механика, что _key_char в main.gd).
func _menu_char(ke: InputEventKey) -> String:
	if S.get_ru_kb():
		var mapped := B.latin_to_ru(ke.keycode, ke.shift_pressed)
		if mapped != "":
			return mapped
	return String.chr(ke.unicode)


func _guest() -> void:
	S.set_last_user(S.GUEST)
	chosen.emit(S.GUEST)


## Подпись строки профиля: кто, сколько играл, все ли клавиши открыты.
func _row_caption(name: String) -> String:
	var p := S.load_profile(name)
	var games := int(p.get("total_games", 0))
	var wins := int(p.get("total_wins", 0))
	# На узком экране — ужатая подпись: полная в чипс не влезает.
	# Победы/игры пакуются как «побед из игр».
	if view_w < 700.0:
		var short := "%s · ур.%d · %d/%d" % [
			name, int(p.get("difficulty", 0)), wins, games
		]
		if bool(p.get("all_keys", false)):
			short += "   " + ALL_KEYS_BADGE
		return short
	var line := "%s   уровень %d · игр %d · побед %d" % [
		name, int(p.get("difficulty", 0)), games, wins
	]
	if bool(p.get("all_keys", false)):
		line += "   " + ALL_KEYS_BADGE
	return line


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
		var need := 170.0 * k + float(maxi(users.size(), 1)) * ROW_H * k + 320.0 * k
		y += maxf(0.0, (eff - need) * 0.22)
	return y


## Строка поля ввода: после заголовка, строк и отступа. Ниже ещё
## галочка «все клавиши» — она есть ВСЕГДА (на пустом списке
## относится к вводимому имени), поэтому запас под неё не зависит от
## наличия игроков. Раньше на пустом списке запаса не было, и рамка
## поля накрывала подпись галочки (видел на эмуляторе).
## Под галочкой — вторая, «RU-клавиатура»: поле едет ещё ниже.
func _field_line_y() -> float:
	return (
		_rows_top()
		+ float(maxi(users.size(), 1)) * ROW_H * k
		+ 30.0 * k
		+ 78.0 * k
		+ 48.0 * k
	)


## Строка галочки «RU-клавиатура»: под первой галочкой.
func _ru_line_y() -> float:
	return _check_line_y() + 48.0 * k


## Строка галочки «все клавиши»: под списком, над полем ввода.
func _check_line_y() -> float:
	return _rows_top() + float(maxi(users.size(), 1)) * ROW_H * k + 6.0 * k


## Строка кнопок: под полем ввода.
func _buttons_y() -> float:
	return _field_line_y() + 64.0 * k


## Чипс строки: та же геометрия, что рисует _draw.
func _row_tap_rect(i: int) -> Rect2:
	var row_y := _rows_top() + float(i) * ROW_H * k
	return Rect2(
		44.0 * k, row_y - 36.0 * k,
		_text_size(_row_caption(users[i]), FONT_ROW).x + 32.0 * k,
		ROW_H * k - 10.0 * k
	)


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


## Галочка «все клавиши» для выбранного профиля: тот же переключатель,
## что клавиша A, но пальцем/мышью (на телефоне буквы A нет в нужный
## момент). Нет игроков — нет и галочки.
func _check_tap_rect() -> Rect2:
	var y := _check_line_y()
	var w := _text_size("Все клавиши", FONT_ROW).x
	return Rect2(48.0 * k, y - 36.0 * k, w + 84.0 * k, 48.0 * k)


## Галочка «RU-клавиатура»: печатать русское с латинской (тот же
## переключатель, что клавиша R, но пальцем/мышью).
func _ru_tap_rect() -> Rect2:
	var y := _ru_line_y()
	var w := _text_size("RU-клавиатура", FONT_ROW).x
	return Rect2(48.0 * k, y - 36.0 * k, w + 84.0 * k, 48.0 * k)


## Квадратик галочки с птичкой (один хелпер на обе галочки).
func _draw_checkbox(cy: float, on: bool) -> void:
	draw_style_box(box_sb, Rect2(60.0 * k, cy - 32.0 * k, 32.0 * k, 32.0 * k))
	if on:
		draw_line(
			Vector2(66.0 * k, cy - 12.0 * k), Vector2(76.0 * k, cy - 2.0 * k),
			_ink(), 4.0 * k
		)
		draw_line(
			Vector2(76.0 * k, cy - 2.0 * k), Vector2(92.0 * k, cy - 26.0 * k),
			_ink(), 4.0 * k
		)


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


## Кнопка день/ночь: солнце (круг + лучи) или луна (диск с кратерами).
## Иконка показывает, ВО ЧТО переключит: днём — луну, ночью — солнце.
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
		# Луна на светлой дневной пилюле — тёмная, иначе не видно.
		var mr := 11.0 * k
		draw_circle(c, mr, Color("#5a6a8a"))
		draw_circle(c + Vector2(-mr * 0.25, -mr * 0.15), mr * 0.45, Color("#3a4a6b"))


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
	# Каждая строка — отдельным «чипсом» по ширине текста: выбранный
	# жёлтый, остальные белые. Тап по чипсу сразу играет этим игроком.
	for i in users.size():
		var row_y := y + float(i) * ROW_H * k
		var chip := _row_tap_rect(i)
		draw_style_box(row_sb if i == sel else row_idle_sb, chip)
		# Выбранная строка всегда на жёлтом — тёмным текстом.
		_text(
			_row_caption(users[i]), Vector2(60.0 * k, row_y), FONT_ROW,
			INK if i == sel else _ink()
		)
	y = _field_line_y()
	# Галочка «все клавиши»: на пустом списке относится к вводимому
	# имени, иначе — к выбранному профилю.
	var cy := _check_line_y()
	_draw_checkbox(cy, _check_on())
	_text("Все клавиши", Vector2(104.0 * k, cy), FONT_ROW, _ink())
	# Галочка «RU-клавиатура»: глобально, как ночь.
	var ry := _ru_line_y()
	_draw_checkbox(ry, S.get_ru_kb())
	_text("RU-клавиатура", Vector2(104.0 * k, ry), FONT_ROW, _ink())
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
	draw_style_box(hint_sb, _mkb_tap_rect())
	for ix in 3:
		for iy in 2:
			draw_circle(
				_mkb_tap_rect().position + Vector2((14.0 + 14.0 * float(ix)) * k, (17.0 + 12.0 * float(iy)) * k),
				2.5 * k, UI_TEXT
			)
		# Подсказка — в пилюле по центру низа (геометрия в _hint_rect()).
		draw_style_box(hint_sb, _hint_rect())
	var lines := _hint_lines()
	var hy := _hint_rect().position.y + 30.0 * k
	for li in lines.size():
		var lw := _text_size(lines[li], FONT_SMALL).x
		_text(lines[li], Vector2(cx - lw * 0.5, hy + 30.0 * k * float(li)), FONT_SMALL, _uitext())


## Пилюля подсказки: та же геометрия, что рисует _draw. Низ пилюли —
## якорь от эффективной высоты, чтобы с клавиатурой не уехать под неё.
func _hint_rect() -> Rect2:
	var cx := view_w * 0.5
	var y := _buttons_y() + 52.0 * k + 30.0 * k
	var lines := _hint_lines()
	var hy := minf(y, _menu_eff_h() - 60.0 * k - 30.0 * k * float(lines.size() - 1))
	var widest := 0.0
	for ln in lines:
		widest = maxf(widest, _text_size(ln, FONT_SMALL).x)
	# Замер шрифта чуть уже отрисовки: запас, чтобы текст не торчал.
	widest += 20.0 * k
	return Rect2(
		cx - widest * 0.5 - 24.0 * k, hy - 30.0 * k,
		widest + 48.0 * k, 30.0 * k * float(lines.size()) + 22.0 * k
	)


## Зайчик рядом с заголовком: тот же спрайт, что в игре.
func _draw_bunny(c: Vector2) -> void:
	var s := 76.0 * k / HERO_TEX.get_height()
	draw_set_transform(c, 0.0, Vector2(s, s))
	draw_texture(HERO_TEX, -HERO_TEX.get_size() * 0.5, _sprite_tint())
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _hint() -> String:
	if users.is_empty():
		# Поле ввода на пустом списке уже открыто (_reload его включает),
		# поэтому совет «нажми Tab» здесь был бы неверным. Гостя ведёт
		# кнопка «Без профиля», Esc для неё не нужен.
		return "Введите имя и нажмите Enter"
	var tail := ""
	if bool(S.load_profile(users[sel]).get("all_keys", false)):
		tail = " (вкл.)"
	elif not input_active:
		tail = " (выкл.)"
	# Сначала действия (тап/клик), потом горячие клавиши вторым рядом.
	# Вторая строка умышленно телеграфная: подробно всё объясняют
	# кнопки, а длинная строка не влезала в окно.
	return (
		"Тап по игроку — играть   ·   Тап по полю — новое имя"
		+ "   ·   ↑↓ выбор   ·   Enter   ·   A — все клавиши" + tail
		+ "   ·   Del   ·   Esc   ·   F2"
	)


## Подсказка для показа: та же строка, но разложенная в столько строчек,
## чтобы каждая влезла в окно (меряем, а не гадаем по символам). На
## десктопе выходят те же две строки, на телефоне — три. Саму строку
## не трогаем (её проверяют тесты).
func _hint_lines() -> Array[String]:
	var hint := _hint()
	var parts := hint.split(" · ")
	if parts.size() <= 1:
		return [hint]
	var max_w := view_w - 144.0 * k
	var lines: Array[String] = []
	var cur := ""
	for p in parts:
		var add := p if cur == "" else " · " + p
		var w := _text_size(cur + add, FONT_SMALL).x
		if cur != "" and w > max_w:
			lines.append(cur)
			cur = p
		else:
			cur += add
	if cur != "":
		lines.append(cur)
	return lines
