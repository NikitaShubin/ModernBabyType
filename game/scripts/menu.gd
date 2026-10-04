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
const ALL_KEYS_BADGE := "⌨ все клавиши"
const HERO_TEX: Texture2D = preload("res://assets/hero.png")

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
## Оформление (только картинка): скруглённые чипсы под строками,
## рамка поля ввода и пилюля подсказки. Строки и тексты не меняются —
## их проверяют тесты, поэтому здесь лишь рамки вокруг тех же слов.
var row_sb: StyleBoxFlat
var row_idle_sb: StyleBoxFlat
var box_sb: StyleBoxFlat
var hint_sb: StyleBoxFlat


func _ready() -> void:
	mono = SystemFont.new()
	mono.font_names = PackedStringArray(
		["DejaVu Sans Mono", "Consolas", "Courier New", "monospace"]
	)
	row_sb = _panel_sb(Color("#f0d98a"), 12.0)
	row_idle_sb = _panel_sb(Color(1, 1, 1, 0.45), 12.0)
	box_sb = _panel_sb(Color("#ffffff"), 10.0, INK, 2.0, false)
	hint_sb = _panel_sb(Color(1, 1, 1, 0.72), 14.0, Color("#e0d5bd"), 1.5, false)
	add_child(Meadow.new())
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


func _draw() -> void:
	# Вуаль вместо глухой заливки: игра позади чуть видна, и понятно,
	# что меню — пауза, а не другой экран. Строки и тексты те же, что
	# были, вокруг них лишь карточки.
	var veil := PAPER
	veil.a = 0.94
	draw_rect(Rect2(Vector2.ZERO, Vector2(view_w, view_h)), veil)
	var cx := view_w * 0.5
	var top := 90.0 * k
	var title := "Кто играет?"
	var title_w := _text_size(title, FONT_TITLE).x
	_draw_bunny(Vector2(cx - title_w * 0.5 - 78.0 * k, top - 20.0 * k))
	_text(
		title,
		Vector2(cx - title_w * 0.5, top),
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
	# Каждая строка — отдельным «чипсом» по ширине текста: выбранный
	# жёлтый, остальные белые. Сплошная плита на всю ширину сливалась
	# с выделением в один жёлтый slab.
	for i in users.size():
		var row_y := y + float(i) * ROW_H * k
		var cap := _row_caption(users[i])
		var chip := Rect2(
			44.0 * k, row_y - 36.0 * k,
			_text_size(cap, FONT_ROW).x + 32.0 * k, ROW_H * k - 10.0 * k
		)
		draw_style_box(row_sb if i == sel else row_idle_sb, chip)
		_text(cap, Vector2(60.0 * k, row_y), FONT_ROW, INK)
	y += float(maxi(users.size(), 1)) * ROW_H * k + 30.0 * k
	# Поле ввода нового имени.
	var field := "Имя: " + input_text + ("|" if input_active else "")
	var field_txt := ("> " if input_active else "  ") + field
	if input_active:
		var fw := _text_size(field_txt, FONT_ROW).x
		draw_style_box(
			box_sb,
			Rect2(48.0 * k, y - 38.0 * k, maxf(fw + 48.0 * k, 420.0 * k), 54.0 * k)
		)
	_text(
		field_txt,
		Vector2(60.0 * k, y),
		FONT_ROW,
		INK if input_active else DIM
	)
	y += 60.0 * k
	# Подсказка — в пилюле по центру низа, в две строки: в одну она
	# не влезает в окно. Делим только для показа, сама строка та же.
	var lines := _hint_lines()
	var hy := minf(y, view_h - 60.0 * k - 30.0 * k * float(lines.size() - 1))
	var widest := 0.0
	for ln in lines:
		widest = maxf(widest, _text_size(ln, FONT_SMALL).x)
	# Замер шрифта чуть уже отрисовки: запас, чтобы текст не торчал.
	widest += 20.0 * k
	draw_style_box(
		hint_sb,
		Rect2(
			cx - widest * 0.5 - 24.0 * k, hy - 30.0 * k,
			widest + 48.0 * k, 30.0 * k * float(lines.size()) + 22.0 * k
		)
	)
	for li in lines.size():
		var lw := _text_size(lines[li], FONT_SMALL).x
		_text(lines[li], Vector2(cx - lw * 0.5, hy + 30.0 * k * float(li)), FONT_SMALL, UI_TEXT)


## Зайчик рядом с заголовком: тот же спрайт, что в игре.
func _draw_bunny(c: Vector2) -> void:
	var s := 76.0 * k / HERO_TEX.get_height()
	draw_set_transform(c, 0.0, Vector2(s, s))
	draw_texture(HERO_TEX, -HERO_TEX.get_size() * 0.5)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


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


## Подсказка для показа: та же строка, но разложенная в две строчки —
## в одну она не влезает в окно. Делим жадно пополам по «·», саму
## строку не трогаем (её проверяют тесты).
func _hint_lines() -> Array[String]:
	var hint := _hint()
	var parts := hint.split(" · ")
	if parts.size() <= 1:
		return [hint]
	var lines: Array[String] = []
	var cur := ""
	var budget := float(hint.length()) / 2.0
	for p in parts:
		var add := p if cur == "" else " · " + p
		if cur != "" and lines.is_empty() and float((cur + add).length()) > budget:
			lines.append(cur)
			cur = p
		else:
			cur += add
	if cur != "":
		lines.append(cur)
	return lines
