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
const SEL_BG := Color("#f0d98a")
const ALL_KEYS_BADGE := "⌨ все клавиши"

var users: Array[String] = []
var sel := 0
var input_active := false
var input_text := ""
## Игрок, ради которого меню открыли: F2 возвращает в игру с ним.
var resume_user := ""
var view_w := BASE_W
var view_h := BASE_H
var k := 1.0
var mono: SystemFont


func _ready() -> void:
	mono = SystemFont.new()
	mono.font_names = PackedStringArray(
		["DejaVu Sans Mono", "Consolas", "Courier New", "monospace"]
	)
	get_tree().root.size_changed.connect(_relayout)
	_relayout()
	_reload()


func _relayout() -> void:
	var s := get_viewport_rect().size
	if s.x <= 0.0 or s.y <= 0.0:
		return
	view_w = s.x
	view_h = s.y
	k = clampf(minf(view_w / BASE_W, view_h / BASE_H), 0.5, 2.5)
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
	# F2 — вернуться в игру тем же игроком, кого открыли меню.
	if ke.keycode == KEY_F2:
		chosen.emit(resume_user)
		get_viewport().set_input_as_handled()
		return
	if ke.keycode == KEY_UP:
		_nav(-1)
		return
	if ke.keycode == KEY_DOWN:
		_nav(1)
		return
	if ke.keycode == KEY_ENTER or ke.keycode == KEY_KP_ENTER:
		_enter()
		return
	if ke.keycode == KEY_TAB:
		_toggle_input()
		return
	if ke.keycode == KEY_DELETE:
		_delete()
		return
	if ke.keycode == KEY_ESCAPE:
		_guest()
		return
	if ke.keycode == KEY_BACKSPACE:
		if not input_active:
			return
		input_text = input_text.left(maxi(0, input_text.length() - 1))
		queue_redraw()
		return
	# Взрослый режим — только когда поле ввода неактивно, иначе это буква.
	if not input_active and _letter(ke) == "a":
		_toggle_all_keys()
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


func _enter() -> void:
	if input_active and not input_text.strip_edges().is_empty():
		var name := S.clean_name(input_text)
		# Новое имя — создать, существующее — просто войти.
		if not S.user_exists(name):
			S.create_user(name)
		else:
			S.touch(name)
		input_text = ""
		input_active = false
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
		return
	var name := users[sel]
	S.set_all_keys(name, not S.get_all_keys(name))
	_reload()


func _guest() -> void:
	S.set_last_user(S.GUEST)
	chosen.emit(S.GUEST)


## Подпись строки профиля: кто, сколько играл, все ли клавиши открыты.
func _row_caption(name: String) -> String:
	var p := S.load_profile(name)
	var games := int(p.get("total_games", 0))
	var wins := int(p.get("total_wins", 0))
	var line := "%s   уровень %d · игр %d · побед %d" % [
		name, int(p.get("difficulty", 0)), games, wins
	]
	if bool(p.get("all_keys", false)):
		line += "   " + ALL_KEYS_BADGE
	return line


func _text_size(txt: String, size_px: int) -> Vector2:
	return mono.get_string_size(
		txt, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size_px
	)


func _text(txt: String, pos: Vector2, size_px: int, col: Color) -> void:
	var fs := int(float(size_px) * k)
	draw_string(
		mono, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs, col
	)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, Vector2(view_w, view_h)), PAPER)
	var cx := view_w * 0.5
	var top := 90.0 * k
	_text(
		"Кто играет?",
		Vector2(cx - _text_size("Кто играет?", FONT_TITLE).x * 0.5, top),
		FONT_TITLE,
		INK
	)
	var y := top + 70.0 * k
	if users.is_empty():
		_text(
			"Пока нет сохранённых игроков",
			Vector2(cx - _text_size("Пока нет сохранённых игроков", FONT_ROW).x * 0.5, y),
			FONT_ROW,
			DIM
		)
	for i in users.size():
		var row_y := y + float(i) * ROW_H * k
		if i == sel:
			var cap := _row_caption(users[i])
			var w := maxf(view_w - 80.0 * k, _text_size(cap, FONT_ROW).x)
			draw_rect(
				Rect2(40.0 * k, row_y - 34.0 * k, w, ROW_H * k), SEL_BG
			)
		_text(_row_caption(users[i]), Vector2(60.0 * k, row_y), FONT_ROW, INK)
	y += float(maxi(users.size(), 1)) * ROW_H * k + 30.0 * k
	# Поле ввода нового имени.
	var field := "Имя: " + input_text + ("|" if input_active else "")
	_text(
		("> " if input_active else "  ") + field,
		Vector2(60.0 * k, y),
		FONT_ROW,
		INK if input_active else DIM
	)
	y += 60.0 * k
	_text(
		_hint(), Vector2(60.0 * k, minf(y, view_h - 60.0 * k)), FONT_SMALL, UI_TEXT
	)


func _hint() -> String:
	if users.is_empty():
		# Поле ввода на пустом списке уже открыто (_reload его включает),
		# поэтому совет «нажми Tab» здесь был бы неверным.
		return "Введите имя и нажмите Enter   ·   Esc — играть без профиля"
	var tail := ""
	if bool(S.load_profile(users[sel]).get("all_keys", false)):
		tail = " (вкл.)"
	elif not input_active:
		tail = " (выкл.)"
	return (
		"↑ ↓ — выбрать   ·   Enter — играть   ·   Tab — новое имя"
		+ "   ·   A — все клавиши" + tail
		+ "   ·   Delete — удалить   ·   Esc — без профиля"
	)
