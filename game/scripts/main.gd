extends Node2D
## ModernBabyType — Godot 4 (десктоп Windows/Linux/macOS, Android).
## Заяц-герой убегает от ежа-колобка, поедая активные буквы.
## Управление: печать активных букв, Backspace чинит ошибку (или
## откатывает назад), Enter — дальше после победы/поражения,
## F2 — меню игроков, F11 — полный экран, Esc — выход.
## Раскладка полностью относительная: _relayout() пересчитывает
## шрифт, метрики и позиции под текущий размер окна.

const B := preload("res://scripts/balance.gd")
const S := preload("res://scripts/save.gd")
const MENU_SCENE := preload("res://scenes/menu.tscn")

## Заяц-герой: один целый рисунок. Анимация — только трансформация
## (выпад на букву, дыхание, дрожь), поэтому фликеру неоткуда взяться:
## на все фазы один и тот же пиксель.
const HERO_TEX: Texture2D = preload("res://assets/hero.png")
## Ёж-колобок: один целый рисунок, ног нет — катится (покачивание +
## прыжки со сплющиванием), фликеру неоткуда взяться.
const HEDGE_TEX: Texture2D = preload("res://assets/hedge.png")
## Качение: угловая частота покачивания и высота прыжка (пиксели до множителя k).
## Ёж маленький: частота высокая, амплитуда скромная — походка весёлая.
const HEDGE_WOB_W := 8.0
const HEDGE_BOB_H := 6.0
## Длительности анимаций (с): еда буквы, испуг.
## Выпад ежа убран (укол — не удар); LUNGE_T оставлен для драйвера кадров.
const CHOMP_T := 0.32
const SHAKE_T := 0.3
const LUNGE_T := 0.4

## Лишние мили ежа на каждой строке (в символах): заход слева из-за
## края и убег за конец. Заяц эти участки проскакивает быстро, ёж идёт
## полностью — поэтому всегда подходит сзади. Остановок у ежа нет вообще.
const ENEMY_PRE_CHARS := 5.0
const ENEMY_POST_CHARS := 2.0
## Видимая ширина шара ежа: hedge.png — альфа-бокс 145 px из 160,
## остальное прозрачное поле (замерено в PIL, см. CREDITS.md).
const HEDGE_BALL_FRAC := 145.0 / 160.0
## Запас сверх контакта (в символах): на столько ёж имеет право
## подойти вплотную, прежде чем укол засчитан. Действует только когда
## заяц на одной строке с ежом (см. правило укола в _process). Держим
## малым: запас — это видимая щель между шарами в момент укола, а автору
## нужно ровно расстояние контакта.
const CONTACT_SLACK := 0.15
## Кап выталкивания зайца вперёд при уколе (в символах). Выталкиваем
## только если заяц влетел в ёжа (прыжок назад через него, откат после
## ошибки) — это один-два символа. Кап нужен на выброс большого отката,
## чтобы бросок не унёс зайца через пол-экрана.
const SNAP_CAP_CHARS := 2.0
## Кап подтягивания зайца НАЗАД к касанию (в символах). Обычно заяц уже
## стоит вплотную и подтягивать нечего (тогда срабатывает крошечный
## CONTACT_SLACK). Разница побольше бывает, когда логика откатилась на
## ошибке или Backspace, а картинка ещё не доехала: это откат на символ.
## Кап держим шире отката, иначе между ним и допуском детекции остаётся
## дырка, где заяц замирает с щелью. Дальше капа не тянем: это уже не
## «встать в касание», а прыжок назад. Оба капа — только на одной строке;
## через угол строк заяц встаёт ровно в касание, без капов.
const SNAP_BACK_CHARS := 1.5
const BASE_W := 1100.0
const BASE_H := 650.0
const START_DELAY := 3.0
const TEXT_CHUNK_LINES := 3

const PAPER := Color("#f7f3e8")
const INK := Color("#1c1a16")
const GREY_PASSED := Color("#b7b0a1")
const GREY_IDLE := Color("#8d8778")
const RED := Color("#c02727")
const UI_TEXT := Color("#4a4438")
const GREEN := Color("#1e7a34")
const DARK_RED := Color("#b02323")

var display_lines: Array[String] = []
var active: Dictionary = {}
var passed: Dictionary = {}
var errors: Dictionary = {}
var cursor_line := 0
var cursor_pos := 0
var state := "playing"
# Точное сравнение с учётом регистра (взрослый режим, _all_keys).
var exact_case := false

var difficulty := 0
var wins_in_row := 0
var ema_cpm := 0.0
var ema_acc := 1.0
var enemy_cps := 2.0

var enemy_x := 0.0
var enemy_line := 0
var hedge_active := false
var grace_t := 0.0
# Линейные координаты уровня: line_base[l] — номер первого символа строки.
var line_base: Array = []

# Метрики раскладки, пересчитываются в _relayout().
var view_w := BASE_W
var view_h := BASE_H
var k := 1.0
var font_size := 32
var char_w := 20.0
var line_h := 56.0
var sep_h := 18.0
var margin := 60.0
var text_y := 80.0
## Свой шрифт из game/fonts (DejaVu Sans Mono): на всех устройствах один
## и тот же, запасным шрифтам с другой шириной глифов неоткуда взяться.
## Иначе подсветка текущей буквы (позиция × ширина «н») плыла к концу
## строки — автор так и видел на телефоне.
var mono: Font

var typed_ok := 0
var typed_bad := 0
var elapsed := 0.0
var time := 0.0
var chomp_t := 0.0
var bounce_t := 0.0

const MAX_TEXT_LABELS := 6
var text_labels: Array[RichTextLabel] = []
var hud_label: Label
var overlay_label: Label
var show_dbg := false
var _last_reason := ""

# Сглаженная позиция героя: логика (курсор) прыгает, картинка догоняет.
var hero_r := Vector2.ZERO
# Фаза прыжков зайца: идёт от пройденного картинкой расстояния.
var hop_ph := 0.0
var shake_t := 0.0
var lunge_t := 0.0
# Моргание зайца: раз в несколько секунд (веки — две чёрточки поверх глаз).
var blink_cd := 2.0
var blink_t := 0.0
# Пыль из-под задней лапы: позади-ниже шара, а не под пузом —
# под пузом она рассеивается, не выходя за спрайт.
var puffs: Array = []
var puff_cd := 0.0

## Кто играет: пусто — гость, его прогресс никуда не пишется.
var profile_name := S.GUEST
## Взрослый режим профиля из меню игроков (клавиша A).
var profile_all_keys := false
## Строгая ё профиля: различать ё и е. Гость и молчуны — строго.
var profile_yo := true
## Ручное «все клавиши»: -1 не задано, 1 да, 0 нет. Ставится тестами и
## аргументами запуска --all-keys / --no-all-keys. Итоговый приоритет в
## _all_keys(): ручной флаг, потом флаг профиля, потом debug-сборка.
## Флаг профиля выше debug: иначе прогрессию нельзя проверять из редактора.
var all_keys_override := -1
## Тесты стартуют сразу в игру, минуя меню игроков.
var skip_menu := false
var menu: Node = null
var menu_open := false
## Ночь прямо сейчас (из S.resolve_night: ручной выбор или система).
var night := false
var meadow: Meadow = null
## Виртуальная клавиатура показана прямо сейчас (чтобы не дёргать
## DisplayServer каждый кадр, только на смене состояния).
var _kb_shown := false
## Высота системной клавиатуры в пикселях канваса (0 — скрыта). Только
## раскладка: всё позиционируется от эффективной высоты _eff_h().
var kb_h := 0.0
## Салют победы: частицы [pos, vel, age, life, color_idx]. Живут только
## на модалке победы, Enter гасит вместе с ней.
var fw_parts: Array = []
var fw_cd := 0.0
const FW_COLORS := [Color("#ffd94d"), Color("#7fb069"), Color("#6bb8e8"), Color("#ef8fb0")]
## Момент последнего запроса показать клавиатуру (для пере-показа,
## если система спрятала её сама, например кнопкой «назад»).
var _kb_request_t := -100.0
## Ручной вызов кнопкой ⌨: в альбоме автоматики нет (_kb_want=false),
## и без этого флага _sync_keyboard прятал вызванную клавиатуру уже
## на следующем кадре — кнопка «ничего не делала». Сбрасывается новым
## уровнем: каждый уровень начинается чисто, зовём заново.
var _kb_manual := false
## Клавиатура была видна после последнего запроса (высота > 0).
var _kb_seen := false
## Разовый добровольный пере-показ уже использован.
var _kb_reshown := false
## Кнопки тач-интерфейса: прямоугольники из _draw для хит-теста в _input.
var _kb_rect := Rect2()
var _players_rect := Rect2()
## Кружок уровня: тап по нему включает/выключает дебаг (на телефоне
## клавиши F3 нет, а цифры клавиатуры для настройки нужны).
var _badge_rect := Rect2()
## Сырая высота клавиатуры в экранных пикселях (до деления на масштаб).
var _kb_raw := 0.0
## Симуляция клавиатуры для стенда (только дебажная сборка, клавиша F4):
## настоящую клавиатуру на эмуляторе вызвать нельзя (гейт движка,
## см. AGENTS.md §6), а баги перекрытия чинить надо. Подменяет высоту
## в _kb_height_px — дальше идёт штатный путь (kb_h → _relayout →
## _eff_h), как с живой клавиатурой. В релизе ветка мертва
## (is_debug_build), в прод не утекает.
var _kb_fake := false
## Оформление (только картинка, логику не трогает): скруглённые панели
## под карточкой текста, табло и подсказкой. Стили создаются раз в
## _ready, геометрию считает _layout_card().
var card_sb: StyleBoxFlat
var pill_sb: StyleBoxFlat
var over_sb: StyleBoxFlat
var cursor_sb: StyleBoxFlat
var badge_sb: StyleBoxFlat
var bar_track_sb: StyleBoxFlat
var bar_fill_sb: StyleBoxFlat
## Рамка-«кнопка» под буквой в подсказке (п.6): скруглённая, с обводкой.
var cap_sb: StyleBoxFlat
## Подозрение на включённый CapsLock в строгом режиме: буква пришла
## заглавной без шифта (или строчной с шифтом). Снимается первой верной
## буквой, новым уровнем и выходом из строгого режима.
var _caps_warn := false
var card_p: Panel
var hud_p: Panel
var hint_p: Panel
var over_p: Panel
## Кегль модалки (считает _layout_text_lines): нужен для зон звёздочек.
var _over_fs := 30
## Подсказка звёздочки (1..3, 0 — нет): наведение и тап по звезде
## объясняют, за что она. Сбрасывается новым уровнем.
var _star_tip := 0
## Скролл текста в пикселях: длинные уровни не влезают в карточку —
## окно едет за курсором построчно. Логика (ось _lin) его не видит:
## _line_y зовут только отрисовки.
var scroll_y := 0.0
## Сколько букв в уровне всего: знаменатель полосы прогресса.
## Считается в _new_level, числитель — passed.size().
var level_total := 0


func _ready() -> void:
	mono = load("res://fonts/DejaVuSansMono.ttf")
	if mono == null:
		# Без импорта (голый checkout) шрифта нет — системный моноширинный,
		# чтобы не падать. В сборке импорт всегда прогнан.
		var fallback := SystemFont.new()
		fallback.font_names = PackedStringArray(["monospace"])
		mono = fallback

	for i in MAX_TEXT_LABELS:
		var tl := RichTextLabel.new()
		tl.bbcode_enabled = true
		tl.autowrap_mode = TextServer.AUTOWRAP_OFF
		tl.scroll_active = false
		tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# Текст — на заднем плане: герои рисуются поверх букв.
		tl.z_index = -10
		tl.add_theme_font_override("normal_font", mono)
		tl.visible = false
		add_child(tl)
		text_labels.append(tl)

	# Табло-дебаг (F3): в обычной игре пусто и скрыто, пилюля видна
	# только с техническими цифрами. clip_text обязателен: без него
	# Label расширяется под самую длинную строку, и пилюля уезжает
	# за правый край вместе с обрезанным текстом.
	hud_label = Label.new()
	hud_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud_label.add_theme_color_override("font_color", UI_TEXT)
	hud_label.clip_text = true
	hud_label.z_index = 2
	add_child(hud_label)

	overlay_label = Label.new()
	overlay_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	overlay_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	overlay_label.visible = false
	# Модалка и табло — выше букв (теперь буквы z = 1).
	overlay_label.z_index = 2
	add_child(overlay_label)

	# Оформление — отдельными узлами позади текста (z_index = -15):
	# сами буквы живут в text_labels (z_index = -10), а _draw() рисует
	# поверх них (z_index = 0), так что панели из _draw() текст бы
	# перекрыли. Геометрию панелей считает _layout_card().
	card_sb = _panel_sb(Color("#fffdf6"), 20.0, Color("#e0d5bd"), 2.0, true)
	pill_sb = _panel_sb(Color(1, 1, 1, 0.72), 14.0, Color("#e0d5bd"), 1.5, false)
	over_sb = _panel_sb(Color("#fffdf6"), 22.0, Color("#e0d5bd"), 2.0, true)
	cursor_sb = _panel_sb(Color(1.0, 0.82, 0.25, 0.5), 8.0)
	badge_sb = _panel_sb(Color("#7fb069"), 12.0, Color("#6a955a"), 2.0, false)
	cap_sb = _panel_sb(Color("#fffdf6"), 10.0, Color("#4a4438"), 2.0, false)
	bar_track_sb = _panel_sb(Color("#e6dcc4"), 5.0)
	bar_fill_sb = _panel_sb(Color("#7fb069"), 5.0)
	card_p = _panel_node(card_sb)
	hud_p = _panel_node(pill_sb)
	hint_p = _panel_node(pill_sb)
	over_p = _panel_node(over_sb)
	for p in [card_p, hud_p, hint_p, over_p]:
		add_child(p)
	meadow = Meadow.new()
	meadow.night = night
	add_child(meadow)
	_apply_night()

	get_tree().root.size_changed.connect(_relayout)

	# Аргументы запуска решают режим на старте, до чтения профиля.
	_cmdline_mode()
	if not skip_menu:
		S.drop_legacy_guest()

	if skip_menu:
		profile_name = S.GUEST
		_start_game()
	elif S.has_valid_last_user():
		profile_name = S.get_last_user()
		_start_game()
	else:
		# Профилей ещё нет — сразу показываем меню выбора.
		profile_name = S.GUEST
		_open_menu()


## Ночь: ручной выбор из файла важнее системы (S.resolve_night).
func _night_resolve() -> void:
	night = S.resolve_night(S.get_night_mode(), true, S.system_dark())


## Применить ночь ко всем краскам: панели мутируют на месте (узлы держат
## те же StyleBox), тексты перекрашиваются, фон переключается.
func _apply_night() -> void:
	_night_resolve()
	if night:
		card_sb.bg_color = Color("#232c44")
		card_sb.border_color = Color("#3a4a6b")
		card_sb.shadow_color = Color(0, 0, 0, 0.35)
		pill_sb.bg_color = Color(0.10, 0.12, 0.20, 0.80)
		pill_sb.border_color = Color("#3a4a6b")
		over_sb.bg_color = Color("#232c44")
		over_sb.border_color = Color("#3a4a6b")
		over_sb.shadow_color = Color(0, 0, 0, 0.35)
		bar_track_sb.bg_color = Color("#3a4a6b")
		hud_label.add_theme_color_override("font_color", Color("#e8e4d8"))
		cap_sb.bg_color = Color("#232c44")
		cap_sb.border_color = Color("#8b93a8")
		# Ночью буквы светлые, а заяц и ёж — белые спрайты: без контура
		# буква, попавшая на спрайт, терялась (видел на эмуляторе).
		for tl in text_labels:
			tl.add_theme_constant_override("outline_size", maxi(2, int(3.0 * k)))
			tl.add_theme_color_override("font_outline_color", Color("#141a2c"))
	else:
		card_sb.bg_color = Color("#fffdf6")
		card_sb.border_color = Color("#e0d5bd")
		card_sb.shadow_color = Color(0.25, 0.20, 0.12, 0.18)
		pill_sb.bg_color = Color(1, 1, 1, 0.72)
		pill_sb.border_color = Color("#e0d5bd")
		over_sb.bg_color = Color("#fffdf6")
		over_sb.border_color = Color("#e0d5bd")
		over_sb.shadow_color = Color(0.25, 0.20, 0.12, 0.18)
		bar_track_sb.bg_color = Color("#e6dcc4")
		hud_label.add_theme_color_override("font_color", UI_TEXT)
		cap_sb.bg_color = Color("#fffdf6")
		cap_sb.border_color = Color("#4a4438")
		# Днём буквы тёмные на светлой карточке — контур не нужен.
		for tl in text_labels:
			tl.add_theme_constant_override("outline_size", 0)
	if meadow != null:
		meadow.night = night
		meadow._apply_sky()
	_refresh()
	queue_redraw()


## Модуляция героев ночью: притемнить и охладить, чтобы светлый мех
## не светился на тёмном фоне. Спрайты те же, перерисовки нет.
func _hero_tint() -> Color:
	if night:
		return Color(0.72, 0.76, 0.90)
	return Color.WHITE
## Стиль скруглённой панели. Тень — только у больших карточек: у
## мелких пилюль она даёт грязь вместо глубины. Радиусы в пикселях, не
## в k: на большом окне чуть менее кругло, зато без пересоздания
## стилей при каждом ресайзе.
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


## Панель-подложка: видна, только когда её покажет раскладка.
func _panel_node(sb: StyleBoxFlat) -> Panel:
	var p := Panel.new()
	p.add_theme_stylebox_override("panel", sb)
	p.z_index = -15
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.visible = false
	return p


## Все клавиши активны?
func _all_keys() -> bool:
	return all_keys_on(all_keys_override, profile_all_keys, OS.is_debug_build())


## Приоритет «все клавиши»: ручной флаг важнее флага профиля, флаг
## профиля важнее debug-сборки. Вынесено отдельно и без сайд-эффектов,
## чтобы тест перебрал все восемь сочетаний — иначе пришлось бы гадать,
## собрана ли тестовая копия движка как debug или как релиз.
static func all_keys_on(override: int, profile_flag: bool, is_debug: bool) -> bool:
	if override >= 0:
		return override == 1
	return profile_flag or is_debug


func _cmdline_mode() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "--all-keys":
			all_keys_override = 1
		elif a == "--no-all-keys":
			all_keys_override = 0


## Уместить строки уровня в ширину экрана. На широких экранах и в
## тестах (1100) все строки короче лимита — возвращается как было.
## Порог 36 — между телефоном (~25) и десктопом (~39): десктопную
## вёрстку не трогаем вообще.
func _fit_to_width(raw: Array[String]) -> Array[String]:
	# Headless-тесты и самое начало жизни сцены: вьюпорта ещё нет
	# (64px или нули) — считаем широким экраном и не режем. Алгоритм
	# покрыт чистыми тестами fit_lines, интеграция тривиальна.
	if view_w < 100.0:
		return raw
	var max_chars := maxi(14, int((view_w - margin * 2.0) / maxf(1.0, char_w)) - 1)
	if max_chars >= 36:
		return raw
	return B.fit_lines(raw, max_chars)


func _start_game() -> void:
	# Метрики (k, char_w, margin) должны быть посчитаны ДО разбивки
	# строк: _fit_to_width режет по ним.
	_relayout()
	var prof: Dictionary = S.load_profile(profile_name)
	profile_all_keys = bool(prof.get("all_keys", false))
	profile_yo = bool(prof.get("yo_strict", true))
	difficulty = int(prof.get("difficulty", 0))
	wins_in_row = int(prof.get("wins_in_row", 0))
	ema_cpm = float(prof.get("ema_cpm", 0.0))
	ema_acc = float(prof.get("ema_acc", 1.0))
	enemy_cps = float(prof.get("enemy_cps", B.BASE_CPS))
	_relayout()
	_new_level()


func _open_menu() -> void:
	if menu == null:
		menu = MENU_SCENE.instantiate()
		menu.chosen.connect(_menu_chosen)
		add_child(menu)
	menu.visible = true
	menu_open = true
	_set_play_ui(false)
	# Свежая высота клавиатуры — в меню сразу, не дожидаясь релэяута.
	menu.set("kb_h", kb_h)
	menu.queue_redraw()
	# F2 из меню возвращает в игру тем же игроком, кого открыли.
	menu.resume_user = profile_name
	# Ночь могла переключить в меню: забираем свежую.
	menu.set("night", night)
	menu.call("_apply_night")
	menu.call("_reload")


func _close_menu() -> void:
	if menu != null:
		menu.visible = false
	menu_open = false
	_set_play_ui(true)


## Игровой слой (текст, карточка, табло, подсказка) — вкл или выкл.
## На время меню всё это выключено: сквозь вуаль подписи меню и буквы
## уровня наезжали друг на друга. Небо остаётся видимым.
## Порядок важен: сначала пересчёт (_layout_text_lines включает буквы
## обратно), и только потом гашение. Иначе меню открывается поверх
## полупогашенного слоя — каша.
func _set_play_ui(on: bool) -> void:
	_layout_text_lines()
	_refresh_hud()
	for tl in text_labels:
		tl.visible = on and tl.visible
	card_p.visible = on and not display_lines.is_empty()
	hud_label.visible = on
	hud_p.visible = on
	# Подсказка рисуется в _draw каждый кадр и сама решает, видна ли:
	# здесь только гасим пилюлю, следующий кадр всё расставит.
	hint_p.visible = false


func _menu_chosen(user_name: String) -> void:
	profile_name = user_name
	if user_name == S.GUEST:
		S.set_last_user(S.GUEST)
	else:
		S.touch(user_name)
	_close_menu()
	# Ночь могли переключить в меню: перечитать перед стартом.
	_apply_night()
	_start_game()


func _relayout() -> void:
	var s := get_viewport_rect().size
	if s.x <= 0.0 or s.y <= 0.0:
		return
	view_w = s.x
	view_h = s.y
	# Масштаб — от эффективной высоты (экран минус клавиатура): в портрете
	# с выездом клавиатуры остаток альбомный, и вся сцена честно в него
	# вписывается. На узком экране за базу ширины берём 560, а не 1100:
	# иначе k упирается в пол 0.5 и всё мелкое. Метрики букв при этом
	# меняются, поэтому позицию ежа пересчитываем в тех же символах оси
	# (см. _lin): визуально он стоит.
	var old_margin := margin
	var old_cw := char_w
	var base_w := BASE_W
	if view_h > view_w:
		base_w = 560.0
	k = clampf(minf(view_w / base_w, _eff_h() / BASE_H), 0.5, 2.5)
	font_size = int(36.0 * k)
	# Левое поле широкое: героям нужен воздух в начале строки,
	# а ёж заходит слева из-за края — ему нельзя за край экрана.
	# На узком экране поля жмутся до 8%: иначе съедают пол-экрана.
	margin = 120.0 * k
	if view_w < 700.0:
		margin = view_w * 0.08
	text_y = 80.0 * k
	char_w = mono.get_string_size("н", HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
	if old_cw > 0.0 and char_w > 0.0 and hedge_active:
		enemy_x = margin + (enemy_x - old_margin) / old_cw * char_w
	# Зазор высотой в строку текста: пустая полоса для качения ежа.
	# Текст при этом никогда не сдвигается.
	sep_h = mono.get_height(font_size)
	line_h = mono.get_height(font_size) + sep_h
	for tl in text_labels:
		tl.position = Vector2(margin, text_y)
		tl.size = Vector2(view_w - margin * 2.0, line_h + 8.0 * k)
		tl.add_theme_font_size_override("normal_font_size", font_size)
	_layout_text_lines()
	# Табло-дебаг якорится к низу ЭФФЕКТИВНОЙ области: иначе
	# клавиатура его перекрывает. В обычной игре оно скрыто.
	hud_label.position = Vector2(margin, _eff_h() - 95.0 * k)
	hud_label.add_theme_font_size_override("font_size", int(18.0 * k))
	# Подсказка рисуется в _draw_hint (позиция и пилюля — там же).
	# Геометрия модалки — в _layout_text_lines (каждый кадр): позиция
	# зависит от скролла. Здесь только кнопки и панели.
	hud_label.size = Vector2(view_w - margin * 2.0, 70.0 * k)
	# Кнопки тач-интерфейса: справа вверху, друг под другом.
	_kb_rect = Rect2(view_w - 72.0 * k, 16.0 * k, 56.0 * k, 56.0 * k)
	_players_rect = Rect2(view_w - 72.0 * k, 84.0 * k, 56.0 * k, 48.0 * k)
	_layout_card()
	_layout_pills()
	_layout_overlay_panel()
	# Меню живёт своей геометрией, но высоту клавиатуры берёт у игры:
	# иначе поле ввода и кнопки на телефоне уезжают под Gboard.
	if menu != null:
		menu.set("kb_h", kb_h)
		menu.queue_redraw()
	queue_redraw()


## Пустая полоса ежа — это межстрочный зазор высотой в строку.
## Текст стоит неподвижно: никаких сдвигов при смене строк.
## Экранный верх текстовой строки (всегда статичен).
func _line_y(line_idx: int) -> float:
	# Экранный верх текстовой строки с учётом скролла. Логика погони
	# сюда не смотрит (у неё ось _lin) — только отрисовки.
	return text_y + float(line_idx) * line_h - scroll_y


## Сколько строк влезает в карточку: минимум две, больше текста не надо.
## С открытой клавиатурой строки обязаны влезть ВЫШЕ подсказки:
## счётчик прогресса и пилюля «Жми» иначе печатаются друг на друге
## (поймано на стенде симуляцией клавиатуры, F4 в дебажной сборке).
func _vis_lines() -> int:
	if line_h <= 0.0:
		return 3
	if kb_h > 0.0:
		var hint_top := _eff_h() - 165.0 * k - 8.0 * k
		var bar_space := (14.0 + 12.0 + 6.0 + 26.0) * k
		var room := hint_top - text_y - 40.0 * k - bar_space
		return maxi(1, mini(maxi(display_lines.size(), 1), int(room / line_h)))
	return maxi(2, mini(maxi(display_lines.size(), 1), int((_eff_h() - 240.0 * k) / line_h)))


## Расставить построчные лэйблы. Окно карточки едет за курсором:
## курсор всегда в последней видимой строке, уехавшие прячем.
func _layout_text_lines() -> void:
	# Блок текста — по центру свободной зоны ЭФФЕКТИВНОЙ высоты: сверху
	# пусто, снизу HUD и подсказка (или клавиатура). Левый край прежний.
	# С открытой клавиатурой — якорь кверху, а не центр: места мало,
	# центрированный блок съезжает вниз на прогресс и подсказку.
	var block_h := float(maxi(display_lines.size(), 1)) * line_h
	if kb_h > 0.0:
		text_y = 80.0 * k
	else:
		text_y = maxf(40.0 * k, (_eff_h() - 200.0 * k - block_h) * 0.5)
	var vis := _vis_lines()
	var first := clampi(cursor_line - vis + 1, 0, maxi(0, display_lines.size() - vis))
	scroll_y = float(first) * line_h
	# Модалка победы/поражения — под карточкой, а не поверх букв.
	# Не шире экрана, шрифт под ширину (на телефоне 980px не влезают).
	var ow := minf(980.0 * k, view_w - 32.0 * k)
	var ofs := int(minf(40.0 * k, (view_w - 64.0 * k) / 17.0))
	_over_fs = ofs
	overlay_label.position = Vector2((view_w - ow) * 0.5, text_y + float(vis) * line_h + 24.0 * k)
	overlay_label.size = Vector2(ow, 150.0 * k)
	overlay_label.add_theme_font_size_override("font_size", ofs)
	for i in text_labels.size():
		if i < display_lines.size() and i >= first and i < first + vis:
			text_labels[i].position = Vector2(margin, _line_y(i))
			text_labels[i].visible = true
		else:
			text_labels[i].visible = false


## Карточка под текстом: собирает буквы в одно «поле для чтения», чтобы
## они не выглядели разбросанными по полотну. Только картинка: позиции
## букв, курсора и героев не трогает, геометрию берёт из тех же
## переменных, что и текст.
func _layout_card() -> void:
	if display_lines.is_empty() or line_h <= 0.0:
		card_p.visible = false
		return
	# Карточка — окно видимых строк, а не весь текст: длинные уровни
	# под ней едут скроллом.
	var pad := 24.0 * k
	var r := Rect2(
		margin - pad, text_y - 20.0 * k,
		view_w - (margin - pad) * 2.0,
		float(_vis_lines()) * line_h + 40.0 * k
	)
	card_p.position = r.position
	card_p.size = r.size
	card_p.visible = true


## Пилюля под табло: тёмный текст читается и на небе. Пилюля подсказки
## считается в _draw_hint (жмётся по содержимому), не здесь.
func _layout_pills() -> void:
	hud_p.position = hud_label.position + Vector2(-14.0 * k, -8.0 * k)
	hud_p.size = hud_label.size + Vector2(28.0 * k, 16.0 * k)


func _toggle_fullscreen() -> void:
	var root := get_tree().root
	if root.mode == Window.MODE_FULLSCREEN:
		root.mode = Window.MODE_WINDOWED
	else:
		root.mode = Window.MODE_FULLSCREEN


## Панель под модалкой победы/поражения: тот же картон, что и у текста.
## Кнопки «Дальше» больше нет: дальше — тап по любому месту рабочей
## области или любая незарезервированная клавиша (см. _input,
## _unhandled_key_input). Зарезервированы: меню (F2), выход (Esc),
## дебаг (F3/F4/F11) и полноэкранный (Alt+Enter).
func _layout_overlay_panel() -> void:
	over_p.position = overlay_label.position + Vector2(-24.0 * k, -16.0 * k)
	over_p.size = overlay_label.size + Vector2(48.0 * k, 32.0 * k)
	over_p.visible = overlay_label.visible


func _key(l: int, p: int) -> String:
	return "%d:%d" % [l, p]


func _load_text() -> Array[String]:
	var lines: Array[String] = []
	for path in _text_files():
		var fa := FileAccess.open(path, FileAccess.READ)
		if fa == null:
			continue
		while not fa.eof_reached():
			var line := fa.get_line().strip_edges()
			if line != "":
				lines.append(line)
		if not lines.is_empty():
			break
	if lines.is_empty():
		lines.append("мама мыла раму.")
		lines.append("папа читал газету!")
		lines.append("солнце светило ярко?")
	# Объём растёт со сложностью: 3 строки на старте, до 6 на высоких
	# уровнях. Длинные уровни едут скроллом (см. scroll_y).
	var chunk := mini(TEXT_CHUNK_LINES + difficulty / 2, 6)
	var n := mini(chunk, lines.size())
	var start := 0
	if lines.size() > n:
		start = randi() % (lines.size() - n + 1)
	return lines.slice(start, start + n)


## Текстовые файлы в случайном порядке (как в оригинале: каждый попытка —
## новый случайный фрагмент из банка текстов).
func _text_files() -> Array[String]:
	var paths: Array[String] = []
	var dir := DirAccess.open("res://texts")
	if dir == null:
		return ["res://texts/demo.txt"]
	var files: Array[String] = []
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.ends_with(".txt"):
			files.append("res://texts/" + fname)
		fname = dir.get_next()
	dir.list_dir_end()
	while not files.is_empty():
		var i := randi() % files.size()
		paths.append(files[i])
		files.remove_at(i)
	return paths if not paths.is_empty() else ["res://texts/demo.txt"]


func _new_level() -> void:
	display_lines = _fit_to_width(_load_text())
	# Новый уровень — чистый ручной флаг клавиатуры: в альбоме игрок
	# зовёт её кнопкой ⌨ сам, само прошлое не тянется.
	_kb_manual = false
	# И предупреждение о CapsLock: новый текст — новая жизнь.
	_caps_warn = false
	# И подсказка звёздочки: модалки больше нет.
	_star_tip = 0
	line_base.clear()
	var acc := 0.0
	for line in display_lines:
		line_base.append(acc)
		acc += float(line.length())
	level_total = int(acc)
	if _all_keys():
		# Взрослый режим: набирается всё, что видно, регистр важен.
		exact_case = true
		active.clear()
		for line in display_lines:
			for i in line.length():
				active[line.substr(i, 1)] = true
	else:
		exact_case = false
		active = B.active_chars(difficulty)
	passed.clear()
	errors.clear()
	cursor_line = 0
	cursor_pos = 0
	typed_ok = 0
	typed_bad = 0
	elapsed = 0.0
	grace_t = START_DELAY
	# Ёж выкатывается позже: когда герой уйдёт на вторую строку,
	# ёж появится строкой выше (enemy_line = 0) и покатится по следу.
	hedge_active = false
	enemy_x = margin
	enemy_line = 0
	state = "playing"
	overlay_label.visible = false
	over_p.visible = false
	fw_parts.clear()
	fw_cd = 0.0
	scroll_y = 0.0
	_skip_inactive()
	hero_r = _hero_pos()
	shake_t = 0.0
	lunge_t = 0.0
	_refresh()


func _current() -> String:
	if cursor_line >= display_lines.size():
		return ""
	var line := display_lines[cursor_line]
	if cursor_pos >= line.length():
		return ""
	return line.substr(cursor_pos, 1)


func _is_active(ch: String) -> bool:
	return ch == " " or active.has(ch if exact_case else ch.to_lower())


## Сравнение ввода: в дебаге регистр важен, иначе — без учёта.
func _eq(a: String, b: String) -> bool:
	# Нeстрогая ё: ё и е — одна буква в обе стороны. Обе сводим
	# к строчной е, потом обычный регистровый разбор (ошибочный
	# регистр при строгом режиме всё равно не проходит).
	if not profile_yo:
		a = a.replace("ё", "е").replace("Ё", "е")
		b = b.replace("ё", "е").replace("Ё", "е")
	if exact_case:
		return a == b
	return a.to_lower() == b.to_lower()


func _advance() -> void:
	cursor_pos += 1
	if cursor_line < display_lines.size():
		if cursor_pos >= display_lines[cursor_line].length():
			cursor_line += 1
			cursor_pos = 0
	if cursor_line >= display_lines.size():
		_finish(true)


## Серые (неактивные) буквы проходятся сами, ждать их не нужно.
func _skip_inactive() -> void:
	while state == "playing":
		var ch := _current()
		if ch == "":
			_finish(true)
			return
		if _is_active(ch) or errors.has(_key(cursor_line, cursor_pos)):
			return
		passed[_key(cursor_line, cursor_pos)] = true
		_advance()


func _unhandled_key_input(event: InputEvent) -> void:
	var ke := event as InputEventKey
	if ke == null or not ke.pressed or ke.echo:
		return
	if ke.keycode == KEY_ESCAPE:
		if menu_open:
			# Esc в меню — гость; сюда попадаем, только если меню не
			# забрало клавишу (страховка).
			_menu_chosen(S.GUEST)
			return
		if get_tree().root.mode == Window.MODE_FULLSCREEN:
			get_tree().root.mode = Window.MODE_WINDOWED
		else:
			get_tree().quit()
		return
	if (
		(ke.keycode == KEY_ENTER or ke.keycode == KEY_KP_ENTER)
		and ke.alt_pressed
	):
		_toggle_fullscreen()
		return
	if ke.keycode == KEY_F3:
		# Отладка — только из редактора/дебажной сборки: в релизе игроку
		# нечего делать с кучей переменных, а тап по бейджу там молчит.
		if OS.is_debug_build():
			show_dbg = not show_dbg
		return
	if ke.keycode == KEY_F4:
		# Симуляция клавиатуры для стенда (только дебаг, см. _kb_fake).
		if OS.is_debug_build():
			_kb_fake = not _kb_fake
		return
	if ke.keycode == KEY_F11:
		_toggle_fullscreen()
		return
	if ke.keycode == KEY_F2:
		# Меню игроков: сменить профиль прямо в игре. Из гостя — выбрать.
		if menu_open:
			_close_menu()
			_start_game()
		else:
			_open_menu()
		return
	if menu_open:
		# Остальные клавиши обрабатывает меню.
		return
	if state == "won" or state == "lost":
		# Модалка: дальше — любая незарезервированная клавиша.
		# Зарезервированные разобраны выше (F2 — меню, Esc — выход,
		# F3/F4/F11 — дебаг, Alt+Enter — полноэкранный): сюда они
		# не доходят. Отдельный Enter не нужен — он тоже «любая».
		_new_level()
		return
	if state != "playing":
		return
	# Backspace с системной клавиатуры — тоже без keycode (unicode 8).
	if ke.keycode == KEY_BACKSPACE or ke.unicode == 8:
		_backspace()
		return
	# Управляющие символы — не буквы: иначе Enter с системной прямо во
	# время партии рисовал бы красную метку перевода строки.
	if ke.unicode < 32:
		return
	if exact_case:
		_caps_check(ke)
	_type_char(String.chr(ke.unicode))


## CapsLock-детект для строгого режима («все клавиши»): движок отдаёт
## готовую букву в unicode, а keycode — физическую клавишу, отдельного
## API состояния CapsLock в 4.3 нет. Буква заглавная без шифта (или
## строчная с шифтом) — значит, lock включён: поднимаем предупреждение
## в подсказке. Не-буквы (цифры, знаки) пропускаем: у них верхний
## и нижний регистр совпадают, судить не о чем.
func _caps_check(ke: InputEventKey) -> void:
	if ke.unicode < 32:
		return
	var ch := String.chr(ke.unicode)
	if ch.to_lower() == ch.to_upper():
		return
	if (ch == ch.to_upper()) != ke.shift_pressed:
		_caps_warn = true


func _type_char(ch: String) -> void:
	var expected := _current()
	if expected == "":
		return
	# Нажата именно та буква, что написана (хоть активная, хоть серая) —
	# это не опечатка: клетка становится пройденной (серой), идём дальше.
	if _eq(ch, expected):
		var kk := _key(cursor_line, cursor_pos)
		# Верная буква гасит и предупреждение о CapsLock: раз сошлось,
		# регистр в порядке (или строгий режим уже выключен).
		_caps_warn = false
		# Верный набор стирает и старую красную метку: иначе опечатка,
		# на которую заяц вернулся позже (откат, Backspace мимо соседней
		# метки), висела бы вечно, хотя буква уже набрана. Именно так
		# автор и застрял с «ложным пробелом»: текст набрался, а красное
		# подчёркивание осталось.
		errors.erase(kk)
		passed[kk] = true
		typed_ok += 1
		chomp_t = CHOMP_T
		_advance()
		_skip_inactive()
	else:
		# Опечатка: красная метка на месте курсора и шаг назад.
		# Каждая следующая неверная клавиша отбрасывает ещё дальше.
		errors[_key(cursor_line, cursor_pos)] = ch
		typed_bad += 1
		shake_t = SHAKE_T
		_knockback()
	_refresh()


## Клетка на шаг назад по сквозной оси текста: конец строки = начало
## следующей, разрывов нет. (-1, -1) — откатываться некуда, это самое
## начало уровня. Общая точка для опечатки и для Backspace: откат у них
## одинаковый, различается только то, что происходит с клеткой.
func _behind() -> Vector2i:
	if cursor_pos > 0:
		return Vector2i(cursor_line, cursor_pos - 1)
	if cursor_line > 0:
		return Vector2i(cursor_line - 1, display_lines[cursor_line - 1].length() - 1)
	return Vector2i(-1, -1)


## Шаг назад: cumulative — каждая опечатка отбрасывает ещё на шаг,
## через пройденные буквы и через переносы строк (упор в начало текста).
func _knockback() -> void:
	var b := _behind()
	if b.x >= 0:
		cursor_line = b.x
		cursor_pos = b.y


## Backspace. Три дела, строго по порядку — «лишнее» нажатие (когда
## стирать нечего) не должно быть пустым:
##  1) красная метка ПОД курсором — стираем её, заяц на месте (иначе
##     красные буквы застревают позади и их уже не убрать);
##  2) метка сразу ВПЕРЕДИ — стираем её и встаём на это место: ребёнок
##     сразу набирает правильную букву заново, без ходьбы туда-обратно;
##  3) а когда стирать нечего — ОТКАТ НАЗАД на одну клетку. Заяц
##     возвращается на букву, которую уже успел набрать, и она снова
##     становится ненабранной (появляется перед зайцем). Счётчики
##     набора НЕ трогаем: клавиши-то были нажаты, честность и CPM
##     показывают фактический ввод. Клетка, на которую сели, возвращается
##     в исходное состояние целиком: с неё снимается и «пройдена», и
##     красная метка, если она там осталась от прежней опечатки.
##     Механика пропусков учтена: серые символы — тоже клетки, откат
##     идёт и по ним, по одному нажатию на символ. Упор в начало текста:
##     с самой первой клетки откатываться некуда. Автопропуск после
##     отката НЕ делаем: заяц обязан стоять перед той буквой, на которую
##     откатился, иначе откат тут же проскочит мимо неё.
func _backspace() -> void:
	var k := _key(cursor_line, cursor_pos)
	if errors.has(k):
		errors.erase(k)
		_skip_inactive()
		_refresh()
		return
	var fwd_l := cursor_line
	var fwd_p := cursor_pos + 1
	if fwd_l < display_lines.size():
		if fwd_p >= display_lines[fwd_l].length():
			fwd_l += 1
			fwd_p = 0
	var fk := _key(fwd_l, fwd_p)
	if errors.has(fk):
		errors.erase(fk)
		cursor_line = fwd_l
		cursor_pos = fwd_p
		_skip_inactive()
		_refresh()
		return
	var b := _behind()
	if b.x < 0:
		return  # самое начало текста
	cursor_line = b.x
	cursor_pos = b.y
	var bk := _key(cursor_line, cursor_pos)
	passed.erase(bk)
	errors.erase(bk)
	_refresh()


func _live_cpm() -> float:
	if elapsed < 3.0:
		return 0.0
	return float(typed_ok) / (elapsed / 60.0)


## Статус ежа для HUD: до выхода на след он ждёт.
## Склонение числительных: 1 знак, 3 знака, 12 знаков; 1 ошибка,
## 3 ошибки, 12 ошибок. Модалка показывает только цифры со словами.
static func _plural(n: int, one: String, few: String, many: String) -> String:
	var m := absi(n) % 100
	var d := m % 10
	if m >= 11 and m <= 14:
		return many
	if d == 1:
		return one
	if d >= 2 and d <= 4:
		return few
	return many


## «168 знаков в минуту» — со склонением.
func _speed_word(v: int) -> String:
	return "%d %s в минуту" % [v, _plural(v, "знак", "знака", "знаков")]


## «0 ошибок», «1 ошибка», «3 ошибки» — со склонением.
func _err_word(v: int) -> String:
	return "%d %s" % [v, _plural(v, "ошибка", "ошибки", "ошибок")]


func _finish(won: bool, reason := "") -> void:
	if state != "playing":
		return
	_last_reason = "" if won else reason
	var total := typed_ok + typed_bad
	var acc := 1.0
	if total > 0:
		acc = float(typed_ok) / float(total)
	ema_acc = ema_acc * 0.7 + acc * 0.3
	var cpm := 0.0
	if elapsed > 1.0:
		cpm = float(typed_ok) / (elapsed / 60.0)
	if ema_cpm > 0.0:
		ema_cpm = ema_cpm * 0.6 + cpm * 0.4
	else:
		ema_cpm = cpm
	if won:
		state = "won"
		wins_in_row += 1
		bounce_t = 0.6
		enemy_cps = B.adapt_cps(true, enemy_cps, acc)
		if wins_in_row >= B.WINS_TO_LEVEL_UP:
			difficulty += 1
			wins_in_row = 0
	else:
		state = "lost"
		wins_in_row = 0
		# Выпада нет: ёж остаётся в точке контакта (укол — не удар).
		enemy_cps = B.adapt_cps(false, enemy_cps, acc)
	var stars := B.stars_for_result(won, acc, typed_bad)
	var prof: Dictionary = S.load_profile(profile_name)
	prof["total_games"] = int(prof.get("total_games", 0)) + 1
	if won:
		prof["total_wins"] = int(prof.get("total_wins", 0)) + 1
	S.save_profile(profile_name, {
		"difficulty": difficulty,
		"wins_in_row": wins_in_row,
		"ema_cpm": ema_cpm,
		"ema_acc": ema_acc,
		"enemy_cps": enemy_cps,
		"all_keys": profile_all_keys,
		"yo_strict": profile_yo,
		"total_games": prof.get("total_games", 0),
		"total_wins": prof.get("total_wins", 0),
	})
	if won:
		overlay_label.add_theme_color_override("font_color", GREEN if not night else Color("#8fd07f"))
		overlay_label.text = "%s\n%s · %s" % [
			"★".repeat(stars) + "☆".repeat(3 - stars),
			_speed_word(int(round(cpm))), _err_word(typed_bad)
		]
		_fw_burst(true)
	else:
		overlay_label.add_theme_color_override("font_color", DARK_RED if not night else Color("#ff7a6b"))
		overlay_label.text = "%s · %s" % [
			_speed_word(int(round(cpm))), _err_word(typed_bad)
		]
	overlay_label.visible = true
	over_p.visible = true
	_refresh()


func _process(dt: float) -> void:
	time += dt
	_sync_keyboard()
	_poll_keyboard()
	if menu_open:
		# Меню открыто — геймплей стоит: ёж не догоняет, таймер не идёт.
		# Отрисовка героев продолжается, но без игровых проверок.
		queue_redraw()
		return
	_layout_text_lines()
	_layout_card()
	_fw_process(dt)
	if chomp_t > 0.0:
		chomp_t -= dt
	if bounce_t > 0.0:
		bounce_t -= dt
	if shake_t > 0.0:
		shake_t -= dt
	if lunge_t > 0.0:
		lunge_t -= dt
	# Моргание зайца: раз в несколько секунд.
	if blink_t > 0.0:
		blink_t -= dt
	else:
		blink_cd -= dt
		if blink_cd <= 0.0:
			blink_t = 0.12
			blink_cd = 2.0 + randf() * 2.5
	# Пыль из-под задней лапы: позади-ниже шара.
	if hedge_active and state == "playing" and grace_t <= 0.0:
		puff_cd -= dt
		if puff_cd <= 0.0:
			puff_cd = 0.14
			puffs.append([Vector2(enemy_x - 22.0 * k + randf_range(-5.0, 5.0) * k, _track_cy(enemy_line) + 14.0 * k), 0.0])
			if puffs.size() > 16:
				puffs.pop_front()
	for i in range(puffs.size() - 1, -1, -1):
		puffs[i][1] += dt
		if puffs[i][1] > 0.45:
			puffs.remove_at(i)
	if state == "playing":
		elapsed += dt
		if grace_t > 0.0:
			grace_t -= dt
		# Ёж выкатывается на след, когда герой уходит на вторую строку,
		# и дальше катится строго по пройденному пути — без прыжков.
		if not hedge_active and cursor_line >= 1:
			hedge_active = true
			enemy_line = 0
			enemy_x = margin
		if hedge_active and grace_t <= 0.0:
			# Геометрия укола. Обе координаты — на общей сквозной оси
			# (номер символа от начала уровня), разрывов нет: конец строки
			# = начало следующей. Ёж всегда идёт (остановок нет), заяц —
			# шагами вперёд или прыжками назад.
			# D = touch + CONTACT_SLACK: геометрическая дистанция
			# контакта в символах плюс крошечный запас (видимая щель
			# между шарами в момент укола). Короткая строка 1 (< D)
			# дала бы укол сразу при выходе ежа — таких строк нет (мин. 9).
			# Проверка ДО шага: укол детерминирован, без гонки со свёрткой.
			var h_lin := _lin(cursor_line, float(cursor_pos))
			var e_lin := _lin(enemy_line, (enemy_x - margin) / char_w)
			var D := _touch_chars() + CONTACT_SLACK
			# Ось склеивает строки: конец строки N и начало N+1 — одна и
			# та же точка. Поэтому «рядом на оси» ≠ «рядом на экране», и
			# правило домоделируется по строкам. Ровно три случая:
			#  1) Одна строка — укол, как только заяц не правее ежа на D.
			#     Если ёж впереди на любом расстоянии — это тоже укол: ёж
			#     всегда идёт, так что заяц мог оказаться позади только
			#     прыжком назад через него, и это ровно «перепрыгнул ёжа».
			#     Плавный догон ловится на границе сам (непрерывность).
			#  2) Строка ежа МЕНЬШЕ строки зайца — укола нет: ёж ещё в
			#     своей строке (середина или post-туннель за её краем),
			#     до зайца ему целая строка миль. Ровно ради этого у
			#     каждой строки свой отступ ENEMY_PRE_CHARS: ёж входит в
			#     новую строку слева, и заяц в её начале успевает отойти,
			#     вход в строку сам по себе укола не даёт.
			#  3) Строка ежа БОЛЬШЕ строки зайца — это укол сразу, без
			#     проверки расстояния. При нормальной игре так быть не
			#     может: строку ежа он прошёл целиком (случай 2), значит
			#     её прошёл и заяц, а назад его отбросила только опечатка
			#     (кумулятивный откат через угол строк). Ловим ровно
			#     это. По оси случай часто выглядит как «заяц впереди»
			#     (ёж стоит в pre-туннеле своей строки, d < 0), но это не
			#     «стояние рядом», а побег: без укола заяц ушёл бы из
			#     погони навсегда.
			var d := e_lin - h_lin
			var same_row := enemy_line == cursor_line
			var contact := enemy_line > cursor_line or (same_row and d >= -D)
			if contact:
				# Позиции спрайтов на этом кадре ещё не обновлялись, так
				# что переоцениваем зайца здесь — до отрисовки. Позицию
				# ежа НЕ трогаем: он катится плавно, его координата в
				# кадре касания и так верна.
				if same_row:
					# Одна строка: ровно на дистанцию контакта, с капами
					# против прыжка через него (см. _settle_contact).
					_settle_contact(cursor_line)
				else:
					# Откат через угол строк: табло укола показываем
					# честное — заяц СТРОГО на строке ежа, координата
					# ежа + Д, шары в касании. Капов здесь нет: прыжок
					# между строками уже случился, это его честная цена.
					_settle_contact(enemy_line, true)
				_finish(false, "behind")
			if state == "playing":
				var llen := 1.0
				if enemy_line < display_lines.size():
					llen = maxf(1.0, float(display_lines[enemy_line].length()))
				var pace := (llen + ENEMY_PRE_CHARS + ENEMY_POST_CHARS) / llen
				enemy_x += enemy_cps * char_w * dt * pace
				if enemy_line < display_lines.size():
					var e_end := margin + (float(display_lines[enemy_line].length()) + ENEMY_POST_CHARS) * char_w
					if enemy_x > e_end:
						if enemy_line + 1 < display_lines.size():
							enemy_line += 1
							enemy_x = margin - ENEMY_PRE_CHARS * char_w
						else:
							enemy_x = e_end  # конец света: дальше идти некуда
			# Резиновая лента: враг тянется к целевому темпу игрока, погоня
			# остаётся напряжённой, но честной.
			var target := B.target_cps(difficulty, _live_cpm())
			enemy_cps = lerpf(enemy_cps, target, clampf(dt * 0.2, 0.0, 1.0))
	# Картинка героя догоняет логический курсор бодрыми прыжками: фаза
	# идёт от пройденного расстояния, на стоянке — мягкая посадка.
	# ВНИМАНИЕ: блок стоит ПОСЛЕ догона и детекции укола. На уколе
	# позиция зайца уже переоценена (_settle_contact), и общий лерп её
	# тут же стёр бы обратно к курсору. Порядок кадра: детекция →
	# переоценка позиций → отрисовка. На проигрыше не двигаем ничего:
	# табло укола (заяц справа от ежа) должно держаться.
	var hero_prev := hero_r
	if state != "lost":
		hero_r = hero_r.lerp(_hero_pos(), clampf(dt * 12.0, 0.0, 1.0))
		var moved := (hero_r - hero_prev).length() / maxf(k, 0.01)
		if moved > 0.02:
			hop_ph += moved / 16.0 * PI
		else:
			hop_ph = lerpf(hop_ph, roundf(hop_ph / PI) * PI, clampf(dt * 10.0, 0.0, 1.0))
	queue_redraw()
	_refresh_hud()


## Системная виртуальная клавиатура (Android): ей владеет игра целиком.
## Нужна всегда, кроме открытого меню без поля ввода: во время партии
## ею печатают буквы, на модалке победы/поражения — Enter, в меню —
## имя игрока. Никакой своей клавиатуры не рисуем — только просим
## систему показать/убрать её штатную. Вызывается каждый кадр, но
## дёргает DisplayServer только на смене состояния. На десктопе и в
## headless-тестах no-op: там нет FEATURE_VIRTUAL_KEYBOARD.
func _sync_keyboard() -> void:
	var want := _kb_want()
	if want == _kb_shown:
		return
	_kb_shown = want
	if not DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD):
		return
	_kb_request_t = time
	_kb_seen = false
	_kb_reshown = false
	if want:
		# existing_text — что уже введено (поле ввода своё, рисованное,
		# поэтому отдаём пусто: клавиатуре нечего подхватывать).
		DisplayServer.virtual_keyboard_show("")
	else:
		DisplayServer.virtual_keyboard_hide()


## Нужна ли системная клавиатура прямо сейчас. Имя вводится — в любой
## ориентации; партия идёт — только в портрете: в альбоме в игре только
## внешняя клавиатура (системную зовём кнопкой ⌨). Чистая функция от
## состояния — матрица в logic_test.
func _kb_want() -> bool:
	if menu_open:
		return menu != null and bool(menu.get("input_active"))
	if _kb_manual:
		return true
	if view_w > view_h:
		return false
	return true


## Эффективная высота экрана: низ, занятый клавиатурой, не наш.
## Вся раскладка считается от неё — и в портрете с клавиатурой, и в
## альбоме с внешней. Пол под ногами не проваливается: минимум 220 px.
func _eff_h() -> float:
	return maxf(view_h - kb_h, 220.0)


## Высота системной клавиатуры в пикселях канваса: экранные пиксели
## делим на масштаб экрана (на телефоне он 2–3). Без фичи — всегда ноль.
func _kb_height_px() -> float:
	# Симуляция для стенда (только дебаг, см. _kb_fake): высота как доля
	# экрана — как у живой Gboard (~40%). _kb_raw для честности в
	# дебаг-строке приводим к экранным пикселям тем же масштабом.
	if OS.is_debug_build() and _kb_fake:
		var scr0 := DisplayServer.window_get_current_screen()
		var scale0 := maxf(1.0, DisplayServer.screen_get_scale(scr0))
		_kb_raw = view_h * 0.42 * scale0
		return view_h * 0.42
	if not DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD):
		_kb_raw = 0.0
		return 0.0
	_kb_raw = float(DisplayServer.virtual_keyboard_get_height())
	var scr := DisplayServer.window_get_current_screen()
	var scale := maxf(1.0, DisplayServer.screen_get_scale(scr))
	return _kb_raw / scale


## Следим за клавиатурой каждый кадр: выехала/уехала — пересчитать
## раскладку. А если система спрятала её сама (кнопка «назад»), а она
## нужна, — просим показать снова, но не раньше чем через полторы
## секунды после прошлого запроса (иначе спамим, пока она выезжает).
func _poll_keyboard() -> void:
	if not DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD):
		return
	var kh := _kb_height_px()
	if not is_equal_approx(kh, kb_h):
		kb_h = kh
		_relayout()
	if kh > 0.0:
		_kb_seen = true
	var want := _kb_want()
	if kb_need_reshow(want, _kb_shown, kh, time - _kb_request_t, _kb_seen, _kb_reshown):
		_kb_request_t = time
		_kb_reshown = true
		DisplayServer.virtual_keyboard_show("")


## Чистое решение «пора ли пере-показать»: пере-показ разовый и только
## если клавиатура так и не выехала (надёжность появления). Смахнутую
## пользователем (была видна — стала 0) не трогаем: её вернут тап по
## тексту, кнопка ⌨ или новый контекст. Матрица в logic_test.
static func kb_need_reshow(want: bool, shown: bool, height: float, elapsed: float, seen: bool, reshown: bool) -> bool:
	return want and shown and height <= 0.0 and elapsed > 3.0 and not seen and not reshown


## Все буквы — одно начертание и кегль. Состояние только оттенком:
## активная — чернила, будущая — средний серый, пройденная — светлый.
func _refresh() -> void:
	for l in display_lines.size():
		if l >= text_labels.size():
			break
		var line := display_lines[l]
		var out := ""
		for p in line.length():
			var ch := line.substr(p, 1)
			var esc := ch
			if ch == "[":
				esc = "[lb]"
			elif ch == "]":
				esc = "[rb]"
			var kk := _key(l, p)
			if errors.has(kk):
				# Затирание, а не вставка: красная нажатая буква ВМЕСТО
				# буквы в клетке. Красные копятся назад по ходу отката.
				# Нажатый по ошибке пробел невидим — показываем знак ␣.
				var shown: String = errors[kk]
				if shown == " ":
					shown = "␣"
				elif shown == "[":
					shown = "[lb]"
				elif shown == "]":
					shown = "[rb]"
				out += "[color=#ff7a6b]" + shown + "[/color]" if night else "[color=#c02727]" + shown + "[/color]"
				continue
			# Пройденное (съеденное или пропущенное) — серым.
			var col := "#6f6a5e" if not night else "#7a86a0"
			if passed.has(kk):
				# Съеденное серым, но ночное #4a5468 давало 1.9:1 к
				# карточке — буквы пропадали, строка шла дырами.
				col = "#b3a996" if not night else "#6f7b99"
			elif _is_active(ch):
				col = "#1c1a16" if not night else "#f2ede0"
			out += "[color=" + col + "]" + esc + "[/color]"
		text_labels[l].text = out
		text_labels[l].visible = true
	for i in range(display_lines.size(), text_labels.size()):
		text_labels[i].visible = false


## Подсказка следующей клавиши частями: обычный текст (cap=false)
## и «кнопки» (cap=true) — буква в скруглённой рамке, пробел — словом
## «Пробел», заглавная в строгом режиме — парой Shift + буква.
## Пустой список — подсказку прятать.
func _hint_parts() -> Array:
	if state != "playing":
		return []
	if _caps_warn and exact_case:
		return [{"s": "Выключи CapsLock!", "cap": false}]
	if not errors.is_empty():
		return [
			{"s": "Жми:", "cap": false},
			{"s": "⌫", "cap": true},
			{"s": "Стереть", "cap": false},
		]
	var cur := _current()
	if cur == "":
		return []
	if cur == " ":
		return [{"s": "Жми:", "cap": false}, {"s": "Пробел", "cap": true}]
	if exact_case and cur == cur.to_upper() and cur != cur.to_lower():
		# Заглавная в строгом режиме одной клавишей не берётся —
		# показываем обе части кнопками.
		return [
			{"s": "Жми:", "cap": false},
			{"s": "Shift", "cap": true},
			{"s": "+", "cap": false},
			{"s": cur, "cap": true},
		]
	return [
		{"s": "Жми:", "cap": false},
		{"s": cur if exact_case else cur.to_upper(), "cap": true},
	]


## Та же подсказка одной строкой: для тестов и дебага. Кнопки — в [].
func _hint_text() -> String:
	var out: Array = []
	for p in _hint_parts():
		var s := String(p["s"])
		out.append(("[" + s + "]") if bool(p["cap"]) else s)
	return " ".join(out)


## Зона i-й звёздочки (0..2) в модалке: верхняя половина лейбла
## третями. Звёзды центрированы, трети широкие — пальцем попасть легко.
func _star_cell_rect(i: int) -> Rect2:
	var r := Rect2(
		overlay_label.position,
		Vector2(overlay_label.size.x, overlay_label.size.y * 0.5)
	)
	var w := r.size.x / 3.0
	return Rect2(r.position + Vector2(w * float(i), 0.0), Vector2(w, r.size.y))


## Объяснение звёздочки: минимальная расшифровка балла.
static func _star_tip_text(i: int) -> String:
	match i:
		1:
			return "★ — уровень пройден"
		2:
			return "★★ — точность от 94%"
		_:
			return "★★★ — точность от 98% без ошибок"


## Рисуем подсказку звёздочки под модалкой (только победа — только
## там есть звёзды).
func _draw_star_tip() -> void:
	if not over_p.visible or state != "won" or _star_tip < 1 or _star_tip > 3:
		return
	var fs := int(20.0 * k)
	var t := _star_tip_text(_star_tip)
	var tw := mono.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs).x
	draw_string(
		mono,
		Vector2(view_w * 0.5 - tw * 0.5, over_p.position.y + over_p.size.y + 30.0 * k),
		t, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs, _ui_ink()
	)
## Рисуем подсказку по центру низа: текст словами, кнопки — в рамках.
## Пилюля жмётся по содержимому: пустая плашка во всю ширину экрана
## под двумя буквами выглядела ошибкой (ловили на эмуляторе).
func _draw_hint() -> void:
	var parts := _hint_parts()
	if parts.is_empty():
		hint_p.visible = false
		return
	var fs := int(30.0 * k)
	var gap := 12.0 * k
	var cap_pad := 16.0 * k
	var cap_h := 48.0 * k
	var widths: Array[float] = []
	var total := 0.0
	for p in parts:
		var w := mono.get_string_size(
			String(p["s"]), HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs
		).x
		if bool(p["cap"]):
			w += cap_pad * 2.0
		widths.append(w)
		total += w
	total += gap * float(maxi(parts.size() - 1, 0))
	# Центр строки — на месте старого лейбла (низ минус 137.5k).
	var y_top := _eff_h() - 137.5 * k - cap_h * 0.5
	var x := (view_w - total) * 0.5
	hint_p.position = Vector2(x - 14.0 * k, y_top - 8.0 * k)
	hint_p.size = Vector2(total + 28.0 * k, cap_h + 16.0 * k)
	hint_p.visible = true
	for i in parts.size():
		var s := String(parts[i]["s"])
		var w: float = widths[i]
		var ty := y_top + cap_h * 0.5 + float(fs) * 0.36
		if bool(parts[i]["cap"]):
			draw_style_box(cap_sb, Rect2(Vector2(x, y_top), Vector2(w, cap_h)))
			var tw := mono.get_string_size(
				s, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs
			).x
			draw_string(
				mono, Vector2(x + w * 0.5 - tw * 0.5, ty),
				s, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs, _ui_ink()
			)
		else:
			draw_string(
				mono, Vector2(x, ty),
				s, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs, _ui_ink()
			)
		x += w + gap


## Обратный отсчёт старта — крупно по центру карточки. Раньше жил
## в табло, которого больше нет: три секунды висит, потом исчезает.
func _draw_countdown() -> void:
	if state != "playing" or grace_t <= 0.0:
		return
	var fs := int(44.0 * k)
	var t := "Старт через %d" % int(ceil(grace_t))
	var tw := mono.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs).x
	var c := card_p.get_rect().get_center()
	draw_string(
		mono, Vector2(c.x - tw * 0.5, c.y - 6.0 * k),
		t, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs, _ui_ink()
	)
	var fs2 := int(28.0 * k)
	var sub := "печатай %s буквы!" % ("светлые" if night else "чёрные")
	var sw := mono.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs2).x
	# Подложка-пилюля: без неё крупные буквы ложатся прямо на текст
	# уровня и строка не читается.
	var bw := maxf(tw, sw) + 56.0 * k
	var bh := 44.0 * k + 12.0 * k + 34.0 * k + 28.0 * k
	draw_style_box(
		pill_sb,
		Rect2(c.x - bw * 0.5, c.y - 6.0 * k - 44.0 * k - 14.0 * k, bw, bh)
	)
	draw_string(
		mono, Vector2(c.x - sw * 0.5, c.y + 38.0 * k),
		sub, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs2, _ui_ink()
	)


## Ширина, доступная строке табло: от поля до поля.
func _hud_avail() -> float:
	return view_w - margin * 2.0


## Первая строка-кандидат, которая реально влезает в avail. Раньше
## выбор был по ширине экрана в пикселях (view_w < 700), но кегль
## умножается на k: телефон 1080px с k=1.93 даёт 21 знак в строке и
## при view_w = 1080 считался «широким», а строка уезжала за край.
## Теперь меряем текст — критерий тот же, а ответ верный на любом
## экране. Пустая строка-кандидат означает «не влезает ничего».
func _first_fit(cands: Array[String], fs: int, avail: float) -> String:
	for c in cands:
		if c.is_empty():
			return ""
		if mono.get_string_size(c, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs).x <= avail:
			return c
	return ""


## Табло — только дебаг (F3): игровую статистику автор убрал,
## остался технический readout для настройки (сдвиг клавиатуры,
## позиции, масштаб). В обычной игре пилюля скрыта.
func _refresh_hud() -> void:
	if not show_dbg:
		hud_label.text = ""
		hud_label.visible = false
		hud_p.visible = false
		return
	var fs := int(18.0 * k)
	var avail := _hud_avail()
	# kb — сдвиг раскладки в пикселях канваса, kh — сырая высота
	# клавиатуры в экранных пикселях, sc — масштаб экрана, vw/vh —
	# вьюпорт. Нужно для настройки сдвига на живых телефонах.
	var sc := 1.0
	if DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD):
		sc = DisplayServer.screen_get_scale(DisplayServer.window_get_current_screen())
	var txt := "[dbg ex=%.0f eln=%d cur=%d:%d cw=%.1f k=%.2f ok=%d bad=%d kb=%.0f kh=%.0f sc=%.2f vw=%.0f vh=%.0f%s]" % [
		enemy_x, enemy_line, cursor_line, cursor_pos, char_w, k, typed_ok, typed_bad,
		kb_h, _kb_raw, sc, view_w, view_h,
		" FAKEKB" if _kb_fake else "",
	]
	hud_label.text = txt
	# Лейблу задаём свою ширину: он не должен раздуваться под текст
	# (clip_text), а пилюля — вылезать за поле.
	hud_label.size = Vector2(avail, (23.0 + 14.0) * k)
	hud_p.size = hud_label.size + Vector2(28.0 * k, 16.0 * k)
	hud_p.visible = true
	hud_label.visible = true


## Герои бегут ПО строке, вместе с буквами: герой съедает букву
## на своей клетке (клетка пустеет), при откате буква появляется снова.
func _track_cy(line_idx: int) -> float:
	return _line_y(line_idx) + mono.get_height(font_size) * 0.5


## Начало строки в линейных координатах (за край — экстраполяция).
func _line_base(l: int) -> float:
	if line_base.is_empty():
		return 0.0
	if l < line_base.size():
		return line_base[l]
	return line_base.back() + float(display_lines.back().length())


## Однозначная координата: символ от начала уровня. Строки склеены
## подряд, конец строки = начало следующей — разрывов нет.
func _lin(l: int, pos_chars: float) -> float:
	return _line_base(l) + pos_chars


## Видимая ширина шара зайца: шар заполняет текстуру целиком
## (139 px из 160 высоты), поэтому это ширина спрайта.
func _hero_ball_w() -> float:
	return _unit_h() * k * float(HERO_TEX.get_width()) / float(HERO_TEX.get_height())


## Видимая ширина шара ежа: спрайт квадратный, но шар уже альфа-бокса.
func _hedge_ball_w() -> float:
	return _unit_h() * k * float(HEDGE_TEX.get_width()) / float(HEDGE_TEX.get_height()) * HEDGE_BALL_FRAC


## Половина видимого шара ежа — от центра до края иголок.
func _hedge_half() -> float:
	return _hedge_ball_w() * 0.5


## Дистанция контакта в символах оси. На оси у зайца — ЛЕВЫЙ край
## клетки буквы, а сам спрайт зайца центрируется на нём (см. _hero_pos),
## то есть его правый край торчит на пол-шара в клетку. У ежа на оси —
## ЦЕНТР шара. Шары соприкасаются, когда правый край зайца доходит до
## левого края ежа, поэтому дистанция контакта — «пол-шара зайца +
## полушара ежа». Ничего «на глаз»: считаем по альфа-боксам спрайтов.
func _touch_chars() -> float:
	return (_hero_ball_w() * 0.5 + _hedge_half()) / char_w


## Позиция зайца в момент укола. Позицию ежа НЕ трогаем: он катится
## плавно, его координата в кадре касания и так верна (шаг ежа в этом
## кадре уже не делается — состояние стало «проигрыш»).
## row — строка, на которой заяц обязан стоять: своя (на одной строке с
## ежом) или строка ежа (откат через угол строк). Касание — это когда
## ЛЕВЫЙ край зайца встаёт в ПРАВЫЙ край ежа, то есть заяц ровно в Д
## от ежа.
## exact — поставить ровно на касание, без капов: строки разные, и
## прыжок между ними уже был, тянуть его дальше незачем.
## Иначе (одна строка): стоял — замирает как есть; влетел в ёжа (прыжок
## назад через него или откат после ошибки) — выталкиваем, но не дальше
## капа; впереди точки касания (откат логики, картинка не доехала) —
## подводим ровно до касания, тоже не дальше капа назад.
func _settle_contact(row: int, exact := false) -> void:
	var touch_x := enemy_x + _hedge_half()
	if exact:
		hero_r.x = touch_x
	elif hero_r.x < touch_x:
		hero_r.x = minf(touch_x, hero_r.x + SNAP_CAP_CHARS * char_w)
	elif hero_r.x - touch_x <= SNAP_BACK_CHARS * char_w:
		# Заяц впереди точки касания (откат логики, картинка не доехала).
		# Подводим ровно до касания — но не дальше капа назад: рывок
		# назад читается как телепорт, а заяц на уколе стоит насмерть.
		hero_r.x = touch_x
	hero_r.y = _track_cy(row)
	hop_ph = roundf(hop_ph / PI) * PI


## Экранный центр глифа под курсором: ширина — по реальной ширине уже
## пройденного куска строки тем же шрифтом, а не номер × char_w. Тогда
## маркер и заяц стоят ровно на букве даже при подменах шрифтов.
## Со своим моноширинным шрифтом совпадает с pos × char_w в точности.
func _cursor_cx() -> float:
	if cursor_line >= display_lines.size():
		return margin
	var line := display_lines[cursor_line]
	var pre := mono.get_string_size(
		line.left(cursor_pos), HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size
	).x
	return margin + pre + _glyph_w(line) * 0.5


## Ширина глифа под курсором (для центра и рамки маркера).
func _glyph_w(line: String) -> float:
	var ch := " "
	if cursor_pos < line.length():
		ch = line.substr(cursor_pos, 1)
	return mono.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x


func _hero_pos() -> Vector2:
	var bounce := 0.0
	if bounce_t > 0.0:
		bounce = -18.0 * k * bounce_t
	# Заяц стоит ПЕРЕД буквой, спрайт центрируется на левом краю её
	# клетки: буква остаётся читаемой, заяц заходит на пол-шара в клетку.
	var half := HERO_TEX.get_width() * 0.5 * _spr_scale(HERO_TEX, _unit_h()).x
	return Vector2(_cursor_cx() - char_w * 0.5 - half, _track_cy(cursor_line) + bounce)


func _draw() -> void:
	# Пока открыто меню игроков, геймплей стоит (см. _process), но
	# картинка остаётся нарисованной: вернувшись по F2, игрок видит
	# ту же позицию зайца и ежа, на которой свернул.
	# Исключение — текст, табло, подсказка и сами герои: сквозь вуаль
	# меню они налезали на его подписи («Кто играет?» поверх «Сом уснул
	# на», ночью особенно). Фон-небо остаётся: видно, что это пауза.
	if state == "won" or state == "lost":
		var dim := Color(1, 1, 1, 0.55) if not night else Color(0.05, 0.07, 0.12, 0.60)
		draw_rect(Rect2(Vector2.ZERO, Vector2(view_w, view_h)), dim)
	# Кнопки интерфейса — только в игре: под открытым меню они
	# просвечивали сквозь вуаль и ложились на шапку таблицы
	# (широкая «Меню (F2)» накрывала заголовок «Ё»). Тычки меню
	# и так разбирает само.
	if not menu_open:
		_draw_touch_buttons()
	if menu_open:
		return
	_draw_level_badge()
	_draw_title()
	_draw_fireworks()
	_draw_progress()
	_draw_cursor_marker()
	_draw_hint()
	_draw_countdown()
	_draw_star_tip()
	_draw_enemy()
	# Героя рисуем всегда: на проигрыше у него шок на лице (укололи),
	# съедения нет.
	_draw_hero()


## Чернила для рисованного текста поверх панелей и фона: днём тёмные,
## ночью светлые. Пилюли сами меняют фон (_apply_night), а рисованный
## текст за ним не следил — ночью «Дальше», точки ⌨, чёрточки ≡ и
## подпись прогресса тонули в тёмном.
func _ui_ink() -> Color:
	return Color("#e8e4d8") if night else INK


## Десктоп — там, где нет системной клавиатуры (нет и клавиши F2
## на экране, зато есть физическая). Кнопка игроков там подписана.
func _is_desktop() -> bool:
	return not DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD)


## Подсказка кнопки игроков: на десктопе словами «Меню (F2)»
## (физическая клавиша есть), на телефоне пусто — там значок ≡
## без слов, клавиши F2 нет.
func _players_hint() -> String:
	return "Меню (F2)" if _is_desktop() else ""


## Кнопки тач-интерфейса: ⌨ — вызвать системную клавиатуру, ≡ — игроки.
## Рисуем всегда (и на десктопе — как подсказка), работают везде: тап
## или клик. Прямоугольники считает _relayout, тычки разбирает _input.
func _draw_touch_buttons() -> void:
	# Клавиатура: пилюля + сетка точек 3×2. Только там, где она может
	# понадобиться (телефон): на десктопе системной клавиатуры нет,
	# кнопка ничего не делала и только путала.
	if not _is_desktop():
		draw_style_box(pill_sb, _kb_rect)
		for ix in 3:
			for iy in 2:
				var dot := _kb_rect.position + Vector2(
					(14.0 + 14.0 * float(ix)) * k, (17.0 + 12.0 * float(iy)) * k
				)
				draw_circle(dot, 2.5 * k, _ui_ink())
	# Игроки: значок ≡, на десктопе слева словами «Меню (F2)».
	draw_style_box(pill_sb, _players_rect)
	for i in 3:
		var ly := _players_rect.position.y + (14.0 + 10.0 * float(i)) * k
		draw_line(
			Vector2(_players_rect.position.x + 14.0 * k, ly),
			Vector2(_players_rect.end.x - 14.0 * k, ly),
			_ui_ink(), 3.0 * k
		)
	var ph := _players_hint()
	if ph != "":
		var pfs := int(22.0 * k)
		var ptw := mono.get_string_size(
			ph, HORIZONTAL_ALIGNMENT_LEFT, -1.0, pfs
		).x
		draw_string(
			mono,
			Vector2(_players_rect.position.x - 12.0 * k - ptw, _players_rect.get_center().y + float(pfs) * 0.36),
			ph, HORIZONTAL_ALIGNMENT_LEFT, -1.0, pfs, _ui_ink()
		)


## Тач и мышь: кнопки интерфейса. Клавиши идут другим путём
## (_unhandled_key_input), здесь только тычки. Пока меню открыто,
## тычки разбирает оно само. Слушаем ТОЛЬКО мышь: на Android тап сам
## превращается в клик (emulate_mouse_from_touch), а двойная обработка
## касания+клика давала бы двойные срабатывания (галочка вкл-выкл
## за один палец). На десктопе касаний нет — ничего не меняется.
func _input(event: InputEvent) -> void:
	if menu_open:
		return
	# Наведение на звёздочки модалки: показать расшифровку балла.
	# Только победа (там есть звёзды) и только десктопная мышь: пальцем
	# подсказку показывает тап (см. ниже), убирать её некуда — модалка
	# и так уйдёт следующим тапом.
	if event is InputEventMouseMotion and over_p.visible and state == "won":
		var mpos := (event as InputEventMouseMotion).position
		var tip := 0
		for i in 3:
			if _star_cell_rect(i).has_point(mpos):
				tip = i + 1
		if tip != _star_tip:
			_star_tip = tip
			queue_redraw()
		return
	var has_pos := false
	var pos := Vector2.ZERO
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			pos = mb.position
			has_pos = true
	if not has_pos:
		return
	if _badge_rect.has_point(pos):
		# Тап по бейджу — дебаг, но только в дебажной сборке (см. F3).
		if OS.is_debug_build():
			show_dbg = not show_dbg
		get_viewport().set_input_as_handled()
		return
	if over_p.visible:
		# Модалка победы/поражения: дальше — тап где угодно, кроме
		# кнопок. ⌨ возвращает смахнутую клавиатуру, ≡ ведёт в меню,
		# бейдж — дебаг (только дебажная сборка). Тап по звезде только
		# показывает расшифровку (следующий тап всё равно идёт дальше).
		if not _is_desktop() and _kb_rect.has_point(pos):
			_kb_summon()
			get_viewport().set_input_as_handled()
			return
		if _players_rect.has_point(pos):
			_open_menu()
			get_viewport().set_input_as_handled()
			return
		if state == "won":
			for i in 3:
				if _star_cell_rect(i).has_point(pos):
					_star_tip = i + 1
					queue_redraw()
					get_viewport().set_input_as_handled()
					return
		_new_level()
		get_viewport().set_input_as_handled()
		return
	if not _is_desktop() and _kb_rect.has_point(pos):
		_kb_summon()
		get_viewport().set_input_as_handled()
		return
	if _players_rect.has_point(pos):
		_open_menu()
		get_viewport().set_input_as_handled()
		return
	# Рабочая область (текст, заяц, ёж): тап возвращает спрятанную
	# клавиатуру. Карточка последняя — кнопки не перекрывает.
	if card_p.visible and Rect2(card_p.position, card_p.size).has_point(pos):
		_kb_summon()
		get_viewport().set_input_as_handled()
		return


## Кнопка ⌨: показать системную клавиатуру прямо сейчас, не дожидаясь
## смены состояния (ей и так положено быть видимой — исчезла системно).
func _kb_summon() -> void:
	if not DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD):
		return
	# Ручной флаг: иначе _sync_keyboard на следующем кадре решит,
	# что клавиатура не нужна (в альбоме _kb_want=false), и спрячет
	# только что показанную.
	_kb_manual = true
	_kb_request_t = time
	_kb_seen = false
	_kb_reshown = false
	_kb_shown = true
	DisplayServer.virtual_keyboard_show("")
## Залп салюта: разлёт искр из точки. Позиции — верхняя половина экрана.
func _fw_burst(first := false) -> void:
	var cx := randf_range(view_w * 0.2, view_w * 0.8)
	var cy := randf_range(_eff_h() * 0.1, _eff_h() * 0.35)
	if first:
		fw_parts.clear()
		for b in 3:
			_fw_one(Vector2(view_w * (0.25 + 0.25 * float(b)), _eff_h() * 0.22))
		return
	_fw_one(Vector2(cx, cy))


func _fw_one(center: Vector2) -> void:
	for i in 14:
		var a := randf() * TAU
		var sp := randf_range(60.0, 220.0) * k
		fw_parts.append([center, Vector2(cos(a), sin(a)) * sp, 0.0, randf_range(0.7, 1.3), randi() % FW_COLORS.size()])
		if fw_parts.size() > 90:
			fw_parts.pop_front()


## Искры живут только на модалке победы: падение с гравитацией и
## периодические новые залпы, пока игрок любуется.
func _fw_process(dt: float) -> void:
	if state != "won":
		return
	fw_cd -= dt
	if fw_cd <= 0.0:
		fw_cd = 0.9
		_fw_burst()
	for i in range(fw_parts.size() - 1, -1, -1):
		var p: Array = fw_parts[i]
		p[1] = (p[1] as Vector2) + Vector2(0, 300.0 * k * dt)
		p[0] = (p[0] as Vector2) + (p[1] as Vector2) * dt
		p[2] = float(p[2]) + dt
		if float(p[2]) > float(p[3]):
			fw_parts.remove_at(i)


func _draw_fireworks() -> void:
	if state != "won":
		return
	for p in fw_parts:
		var age: float = p[2]
		var life: float = p[3]
		var col: Color = FW_COLORS[int(p[4]) % FW_COLORS.size()]
		col.a = clampf(1.0 - age / life, 0.0, 1.0)
		var pos: Vector2 = p[0]
		draw_circle(pos, (1.0 + 3.0 * (1.0 - age / life)) * k, col)
## Пилюля с номером уровня в пустом левом верхнем углу: и красиво,
## и уровень всегда перед глазами, а не только в табло. Раньше был
## кружок с одной цифрой — на телефоне от него остаётся кружок с
## «0», и ребёнок не понимает, что это уровень. С подписью «УР» и
## в кружке-пилюле по ширине текста.
## Кто сейчас играет, для заголовка: имя или «гость».
func _title_text() -> String:
	return profile_name if profile_name != S.GUEST else "гость"


## Имя игрока заголовком сверху по центру, в рамке-пилюле.
## Длинное режем многоточием, чтобы не налезть на бейдж и кнопки.
func _draw_title() -> void:
	var who := _title_text()
	var fs := int(26.0 * k)
	var pad := 16.0 * k
	var max_w := maxf(view_w - _badge_rect.size.x - 220.0 * k, 120.0 * k)
	var t := _short_text(who, fs, max_w)
	var tw := mono.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs).x
	var w := tw + pad * 2.0
	var h := 42.0 * k
	var r := Rect2(Vector2((view_w - w) * 0.5, 14.0 * k), Vector2(w, h))
	draw_style_box(pill_sb, r)
	draw_string(
		mono, r.position + Vector2(pad, h * 0.5 + float(fs) * 0.36), t,
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs, _ui_ink()
	)


## Ужать строку в ширину: длинное режем с многоточием.
func _short_text(t: String, fs: int, max_w: float) -> String:
	if mono.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs).x <= max_w:
		return t
	var out := t
	while out.length() > 1 and mono.get_string_size(
		out + "…", HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs
	).x > max_w:
		out = out.left(out.length() - 1)
	return out + "…"


## Текст кружка уровня: уровень и счёт до него одной дробью.
func _badge_text() -> String:
	return "УР %d · %d/%d" % [difficulty, wins_in_row, B.WINS_TO_LEVEL_UP]


func _draw_level_badge() -> void:
	# Уровень и счёт до него одной дробью: «УР 2 · 2/3».
	var t := _badge_text()
	var fs := int(26.0 * k)
	var tw := mono.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs).x
	var pad := 16.0 * k
	var w := tw + pad * 2.0
	var h := 42.0 * k
	var r := Rect2(Vector2(14.0 * k, 14.0 * k), Vector2(w, h))
	_badge_rect = r.grow(4.0 * k)
	draw_style_box(badge_sb, r)
	# Тёмное на зелёном: белое давало контраст 2.5:1 и «УР» не читалось
	# (ревизия читаемости, п.5).
	draw_string(
		mono, r.position + Vector2(pad, h * 0.5 + fs * 0.36), t,
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs, INK
	)


## Полоса прогресса уровня под карточкой: съедено столько-то из стольких.
## Числитель — пройденные клетки, знаменатель — все буквы уровня.
## Отступ от краёв карточки и заметная толщина: раньше полоска шириной
## во всю карточку и высотой 10*k читалась как случайный штрих, а не
## как прогресс. Подпись — сколько букв съедено из скольких.
func _draw_progress() -> void:
	if level_total <= 0 or not card_p.visible:
		return
	var done := passed.size()
	var frac := clampf(float(done) / float(level_total), 0.0, 1.0)
	var inset := 20.0 * k
	var th := 12.0 * k
	var r := Rect2(
		card_p.position + Vector2(inset, card_p.size.y + 14.0 * k),
		Vector2(card_p.size.x - inset * 2.0, th)
	)
	draw_style_box(bar_track_sb, r)
	if frac > 0.0:
		draw_style_box(
			bar_fill_sb,
			Rect2(r.position, Vector2(maxf(r.size.x * frac, th), r.size.y))
		)
	var t := "%d / %d" % [done, level_total]
	var fs := int(16.0 * k)
	var tw := mono.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs)
	# Подпись ПОД полосой, то есть прямо по небу: старые цвета давали
	# днём 3:1 (мелкий серый на светлом) — берём общий рисованный текст.
	# Под модалкой победы/поражения подпись прячем: иначе цифры
	# налезают на звёзды. Сама полоса остаётся — контекст.
	if over_p.visible:
		return
	draw_string(
		mono,
		Vector2(r.position.x + r.size.x * 0.5 - tw.x * 0.5, r.position.y + th + 20.0 * k),
		t, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs, _ui_ink()
	)


## Маркер текущей буквы: рамка ровно по глифу (та же ширина, что в
## _cursor_cx), курсор всегда видно, даже после отката через строки.
func _draw_cursor_marker() -> void:
	if state != "playing" or cursor_line >= display_lines.size():
		return
	var line := display_lines[cursor_line]
	var pre := mono.get_string_size(
		line.left(cursor_pos), HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size
	).x
	var w := _glyph_w(line)
	var gx := margin + pre
	var gy := _line_y(cursor_line)
	draw_style_box(
		cursor_sb,
		Rect2(gx - 2.0 * k, gy, w + 4.0 * k, mono.get_height(font_size))
	)


## Заяц: один спрайт, поэтому вся анимация — трансформация. Ростом
## с букву (_unit_h). Движение — бодрые прыжки (фаза от пройденного пути).
## Выпад-укус на букву при съедении, наклон назад при отрыжке, моргание
## веками, лёгкая дрожь от страха, когда ёж близко сзади.
func _draw_hero() -> void:
	var c := hero_r
	var punch := 0.0
	if chomp_t > 0.0:
		punch = sin(PI * (1.0 - chomp_t / CHOMP_T))
		c.x += 10.0 * k * punch
		c.y -= 8.0 * k * punch
	elif shake_t > 0.0:
		var f := shake_t / SHAKE_T
		c.x += sin(shake_t * 40.0) * 6.0 * k * f - 8.0 * k * f
	if hedge_active and enemy_line == cursor_line and state == "playing":
		var gap := (_cursor_cx() - char_w * 0.5) - enemy_x
		if gap > 0.0 and gap < 130.0 * k:
			# Ёж не хищник: дрожь на подступах еле заметна. На проигрыше
			# (укололи) дрожи нет вовсе — только шок на лице.
			c.x += sin(time * 55.0) * 0.8 * k
	# Прыжок зайца: присед (гашение инерции) → парабола вверх-вниз →
	# снова присед. Цикл быстрый, наверху не висит.
	var ht := fmod(hop_ph, PI) / PI
	var hop := 0.0
	var crouch := 0.0
	if ht < 0.3:
		hop = sin(ht / 0.3 * PI * 0.5)
	elif ht < 0.55:
		hop = cos((ht - 0.3) / 0.25 * PI * 0.5)
	else:
		crouch = 1.0 - (ht - 0.55) / 0.45
	c.y -= hop * 7.0 * k
	# Дыхание, чтобы не был статуей.
	var breathe := 1.0 + 0.02 * sin(time * 2.5)
	var sq := Vector2((1.0 + 0.22 * punch) * breathe, (1.0 - 0.12 * punch) / breathe)
	sq *= Vector2(1.0 + 0.07 * crouch, 1.0 - 0.06 * crouch)
	sq *= Vector2(1.0 - 0.03 * hop, 1.0 + 0.04 * hop)
	var s := _spr_scale(HERO_TEX, _unit_h()) * sq
	draw_set_transform(c, 0.0, s)
	draw_texture(HERO_TEX, -HERO_TEX.get_size() * 0.5, _hero_tint())
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if blink_t > 0.0 and state != "lost":
		# Веки — две чёрточки поперёк глаз. Рамки глаз измерены по
		# спрайту 139x160: центры (-15, 0) и (+28, 0) от его центра.
		var e := _spr_scale(HERO_TEX, _unit_h())
		for ex in [-15.0, 28.0]:
			var p := c + Vector2(ex, 0.0) * e.x
			draw_line(
				p + Vector2(-13.0, 0.0) * e.x, p + Vector2(13.0, 0.0) * e.x,
				Color("#3a3230"), 4.0 * e.x
			)
	if state == "lost":
		# Укололи: глаза навыкате (белки + зрачки), рот раскрыт.
		# Координаты глаз — те же рамки, что у век выше.
		var e2 := _spr_scale(HERO_TEX, _unit_h())
		for ex in [-15.0, 28.0]:
			var p2 := c + Vector2(ex, 0.0) * e2.x
			draw_circle(p2, 15.0 * e2.x, Color.WHITE)
			draw_circle(p2, 7.0 * e2.x, Color("#1c1a16"))
		var m := c + Vector2(6.0, 34.0) * e2.x
		draw_set_transform(m, 0.0, Vector2(0.75, 1.1) * e2.x)
		draw_circle(Vector2.ZERO, 10.0, Color("#5a2323"))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if chomp_t > 0.0:
		for i in 4:
			var a := time * 9.0 + float(i) * 1.6
			# Крошки летят ИЗ БУКВЫ (её центр), а не изо рта героя: буква
			# съедена — из неё и брызги, иначе пятна липнут на морде.
			var from := Vector2(_cursor_cx(), _track_cy(cursor_line))
			var crumb := from + Vector2(cos(a), sin(a)) * 8.0 * k
			draw_circle(crumb, 2.0 * k, Color("#8a5a2b"))


## Пыль из-под лап: серые кружки тают за 0.45 c.
func _draw_puffs() -> void:
	for p in puffs:
		var age: float = p[1]
		var a := 1.0 - age / 0.45
		var pos: Vector2 = p[0] + Vector2(-6.0, -22.0) * age * k
		draw_circle(pos, (6.0 - 8.0 * age) * k, Color(0.6, 0.55, 0.5, 0.35 * a))


## Масштаб спрайта под целевую высоту (с учётом k окна).
func _spr_scale(tex: Texture2D, target_h: float) -> Vector2:
	var s := target_h * k / tex.get_height()
	return Vector2(s, s)


## Один размер на троих: герои ростом с букву (высота текстовой строки).
func _unit_h() -> float:
	return mono.get_height(font_size) / k


## Ёж-колобок: шара без ног походка не нужна — катится: покачивание
## из стороны в сторону + прыжки со сплющиванием в момент касания.
## В точке контакта просто остаётся, без отскока (укол — не удар).
func _draw_enemy() -> void:
	if not hedge_active or enemy_line >= display_lines.size():
		return
	var running := state == "playing" and grace_t <= 0.0
	var c := Vector2(enemy_x, _track_cy(enemy_line))
	var sq := Vector2.ONE
	var wob := 0.0
	if running:
		var ph := time * HEDGE_WOB_W
		var air := maxf(0.0, sin(ph))
		c.y -= air * HEDGE_BOB_H * k
		var flat := maxf(0.0, -sin(ph))
		sq = Vector2(1.0 + 0.06 * flat, 1.0 - 0.06 * flat)
		wob = 0.10 * sin(ph) - 0.04 * air
	# Выпада нет: укол — не удар. В точке контакта ёж просто остаётся,
	# без отскока и танцев: любое движение после укола читается как
	# «не попал» (жалоба автора).
	var s := _spr_scale(HEDGE_TEX, _unit_h()) * sq
	draw_set_transform(c, wob, s)
	draw_texture(HEDGE_TEX, -HEDGE_TEX.get_size() * 0.5, _hero_tint())
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_draw_puffs()
