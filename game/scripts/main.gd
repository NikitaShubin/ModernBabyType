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

const INK := Color("#1c1a16")
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
## Регистр важен тогда и только тогда, когда взрослый режим.
## Было хранимым флагом — сносилось _new_level и врало читателю;
## теперь чистая функция от _all_keys().
func _exact() -> bool:
	return _all_keys()

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

## Построчных лейблов с запасом: строк после вёрстки под узкий экран
## бывает до 15 (chunk 6 × перенос 2–3), а лишние строки просто
## не рисовались — «последние строки пусты» (жалоба 10.2026).
const MAX_TEXT_LABELS := 16
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
## Своя экранная клавиатура (модуль Kbd, решение автора 10.2026): вместо
## системной IME, которая коверкает ввод composing-перепиской. Видна
## в партии на сенсорных устройствах (на десктопе есть железная).
## Слой клавиатуры держит kb_layer ("ru"/"sym"/"en"). Системную не вызываем вообще.
var kb_layer := "ru"
var kb_lang := "ru"
var kb_shift := false
var kb_key_sb: StyleBoxFlat
var kb_on_sb: StyleBoxFlat
## Высота своей клавиатуры в пикселях канваса (0 — скрыта). Только
## раскладка: всё позиционируется от эффективной высоты _eff_h().
var kb_h := 0.0
## Отступ от верха под вырез камеры (капля). Ставит _relayout из
## Ui.top_inset; верхняя группа (бейдж, имя, кнопка, текст) едет вниз.
var top_safe := 0.0
## Системная клавиатура (галка в меню, борьба с автозаменой — comp-буфер):
## показана прямо сейчас, момент запроса, была видна, пере-показ использован,
## сырая высота в экранных пикселях. Живут только при включённой галке.
var _kb_shown := false
var _kb_request_t := -100.0
var _kb_seen := false
var _kb_reshown := false
var _kb_raw := 0.0
## Ручной вызов системной тапом по рабочей области (при её галке).
var _kb_manual := false
## Пере-поднять системную клавиатуру после старта нового уровня: сессия
## IME рвётся, когда уровень начат нажатием клавиши (Godot съедает её), и
## буквы уходят в никуда, пока игрок не тапнёт по тексту. Живой лог
## 10.2026: LEVEL, затем 2.5 с тишины (только Backspace'ы), TAP — и
## только затем пошли EV. Обратный отсчёт кадров до показа.
var _kb_refocus := 0
## Салют победы: частицы [pos, vel, age, life, color_idx]. Живут только
## на модалке победы, Enter гасит вместе с ней.
var fw_parts: Array = []
var fw_cd := 0.0
const FW_COLORS := [Color("#ffd94d"), Color("#7fb069"), Color("#6bb8e8"), Color("#ef8fb0")]
## Кнопка тач-интерфейса: прямоугольник из _draw для хит-теста в _input.
var _players_rect := Rect2()
## Кружок уровня: тап по нему включает/выключает дебаг (на телефоне
## клавиши F3 нет, а цифры клавиатуры для настройки нужны).
var _badge_rect := Rect2()
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
	# Модалка и табло — выше букв (буквы z=-10, панели z=-15, лейблы z=2).
	overlay_label.z_index = 2
	add_child(overlay_label)

	# Оформление — отдельными узлами позади текста (z_index = -15):
	# сами буквы живут в text_labels (z_index = -10), а _draw() рисует
	# поверх них (z_index = 0), так что панели из _draw() текст бы
	# перекрыли. Геометрию панелей считает _layout_card().
	card_sb = Ui.panel_sb(Ui.CARD_DAY, 20.0, Color("#e0d5bd"), 2.0, true)
	pill_sb = Ui.panel_sb(Color(1, 1, 1, 0.72), 14.0, Color("#e0d5bd"), 1.5, false)
	over_sb = Ui.panel_sb(Color(0, 0, 0, 0), 22.0)
	cursor_sb = Ui.panel_sb(Color(1.0, 0.82, 0.25, 0.5), 8.0)
	badge_sb = Ui.panel_sb(Color("#7fb069"), 12.0, Color("#6a955a"), 2.0, false)
	cap_sb = Ui.panel_sb(Color("#fffdf6"), 10.0, Color("#4a4438"), 2.0, false)
	bar_track_sb = Ui.panel_sb(Color("#e6dcc4"), 5.0)
	bar_fill_sb = Ui.panel_sb(Color("#7fb069"), 5.0)
	kb_key_sb = Ui.panel_sb(Color("#fffdf6"), 10.0, Color("#4a4438"), 2.0, false)
	kb_on_sb = Ui.panel_sb(Color("#a9c6ec"), 10.0, Color("#4a4438"), 2.0, false)
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
	Ui.force_touch = _force_touch
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
		card_sb.bg_color = Ui.CARD_NIGHT
		card_sb.border_color = Color("#3a4a6b")
		card_sb.shadow_color = Color(0, 0, 0, 0.35)
		pill_sb.bg_color = Color(0.10, 0.12, 0.20, 0.80)
		pill_sb.border_color = Color("#3a4a6b")
		bar_track_sb.bg_color = Color("#3a4a6b")
		hud_label.add_theme_color_override("font_color", Color("#e8e4d8"))
		cap_sb.bg_color = Color("#232c44")
		cap_sb.border_color = Color("#8b93a8")
		kb_key_sb.bg_color = Color("#232c44")
		kb_key_sb.border_color = Color("#8b93a8")
		kb_on_sb.bg_color = Color("#8ab4e0")
		kb_on_sb.border_color = Color("#8b93a8")
		# Ночью буквы светлые, а заяц и ёж — белые спрайты: без контура
		# буква, попавшая на спрайт, терялась (видел на эмуляторе).
		for tl in text_labels:
			tl.add_theme_constant_override("outline_size", maxi(2, int(3.0 * k)))
			tl.add_theme_color_override("font_outline_color", Color("#141a2c"))
	else:
		card_sb.bg_color = Ui.CARD_DAY
		card_sb.border_color = Color("#e0d5bd")
		card_sb.shadow_color = Color(0.25, 0.20, 0.12, 0.18)
		pill_sb.bg_color = Color(1, 1, 1, 0.72)
		pill_sb.border_color = Color("#e0d5bd")
		bar_track_sb.bg_color = Color("#e6dcc4")
		hud_label.add_theme_color_override("font_color", UI_TEXT)
		cap_sb.bg_color = Color("#fffdf6")
		cap_sb.border_color = Color("#4a4438")
		kb_key_sb.bg_color = Color("#fffdf6")
		kb_key_sb.border_color = Color("#4a4438")
		kb_on_sb.bg_color = Color("#a9c6ec")
		kb_on_sb.border_color = Color("#4a4438")
		# Днём буквы тёмные на светлой карточке — контур не нужен.
		for tl in text_labels:
			tl.add_theme_constant_override("outline_size", 0)
	if meadow != null:
		meadow.night = night
		meadow._apply_sky()
	_refresh()
	queue_redraw()


## Модуляция героев ночью — см. Ui.NIGHT_TINT: светлый мех
## не должен светиться на тёмном фоне. Спрайты те же, перерисовки нет.

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
		elif a == "--touch-kb":
			# Стенд мобильной раскладки на десктопе: своя клавиатура
			# видна, как на телефоне (для скриншотов и проверки тапов).
			_force_touch = true


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
	if _max_chars() >= 36:
		return raw
	return B.fit_lines(raw, _max_chars())


## Сколько знаков влезает в строку. Один счёт для всех: и разбивки
## при старте уровня, и пересборки при смене ширины экрана.
func _max_chars() -> int:
	return maxi(14, int((view_w - margin * 2.0) / maxf(1.0, char_w)) - 1)


## Ширина экрана может поменяться ПО ХОДУ уровня: на телефоне выезжает
## клавиатура (окно становится ниже и уже), телефон поворачивают. Тогда
## строки, собранные при старте, перестают влезать — текст уезжает за
## правый край, и игрок не видит, что набирать (жалоба автора,
## 07.10.2026: «в мобильной версии не могу закончить уровень»).
## Пересобираем строки и переносим курсор, «пройдено» и красные метки
## по логической оси текста (без пробелов на местах разрыва, см.
## B.reflow): заяц остаётся на той же букве.
func _reflow_text() -> void:
	if display_lines.is_empty():
		return
	var rf: Dictionary = B.reflow(display_lines, cursor_line, cursor_pos, _max_chars())
	var fresh: Array = rf["lines"]
	if fresh == display_lines:
		return  # вёрстка не изменилась — курсор и метки трогать нельзя
	var table: Dictionary = rf["table"]
	# В лог: вёрстка поменялась. Ширина, число строк, где встал курсор и
	# какая буква под ним — по этому видно, если текст «поехал» (жалоба
	# автора 10.2026 на отображение).
	var nl := int(rf["line"])
	var np := int(rf["pos"])
	var under := ""
	if nl < fresh.size() and np < String(fresh[nl]).length():
		under = String(fresh[nl]).substr(np, 1)

	display_lines = fresh
	cursor_line = int(rf["line"])
	cursor_pos = int(rf["pos"])
	_undo.clear()
	_reindex_lines()
	_remap_cells(passed, table, rf)
	_remap_cells(errors, table, rf)
	# Надписи перерисовать ЗДЕСЬ: иначе на экране остаётся старая
	# вёрстка, обрезанная краем окна, — игрок видит не тот текст, который
	# в игре (жалоба автора: строка «пустая», а набирать надо другое).
	_refresh()
	# Всё набрано, а перенос выкинул курсор за последнюю строку (смена
	# ширины ровно на последней букве): уровень закончен.
	if cursor_line >= display_lines.size() and state == "playing":
		_finish(true)


## Пересчитать смещения строк и длину уровня после сборки строк.
func _reindex_lines() -> void:
	line_base = B.line_bases(display_lines)
	level_total = 0
	if not line_base.is_empty():
		level_total = (
			int(line_base[line_base.size() - 1])
			+ display_lines[display_lines.size() - 1].length()
		)


## Перенести отметки «пройдено»/«ошибка» на те же буквы после пересборки
## строк: ключ «строка:позиция» меняет смысл, буква — нет. Таблица
## переводит логическое смещение старой сборки в клетку новой.
func _remap_cells(src: Dictionary, table: Dictionary, rf: Dictionary) -> void:
	if src.is_empty():
		return
	var old_lines: Array = rf["old"]
	var out := {}
	for k in src.keys():
		var parts := String(k).split(":")
		if parts.size() != 2:
			continue
		var li := int(parts[0])
		if li >= old_lines.size():
			continue
		var off := int(parts[1])
		for i in li:
			off += String(old_lines[i]).length()
		var c: Vector2i = table.get(off, Vector2i(-1, -1))
		if c.x >= 0:
			out["%d:%d" % [c.x, c.y]] = src[k]
	src.clear()
	src.merge(out)


func _start_game() -> void:
	# Профиль могли снести, пока меню было открыто (или resume протух):
	# призраков не воскрешаем — играем гостем.
	if profile_name != S.GUEST and not S.user_exists(profile_name):
		profile_name = S.GUEST
		S.set_last_user(S.GUEST)
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
		# Сиблинг под корнем, а не ребёнок игры: экраны рядом,
		# а не вложены. Порядок детей даёт меню верх и первый ввод.
		# Отложенно: _open_menu зовут и из _ready (стартовый роутинг),
		# где родитель ещё монтирует детей и прямой add_child падает.
		if get_parent().is_node_ready():
			get_parent().add_child(menu)
		else:
			get_parent().add_child.call_deferred(menu)
	menu.open(profile_name)
	menu_open = true
	_players_hover = false
	_set_play_ui(false)


func _close_menu() -> void:
	if menu != null:
		menu.close()
	menu_open = false

	_set_play_ui(true)


## Игровой слой (текст, карточка, табло, подсказка) — вкл или выкл.
## На время меню всё это выключено: сквозь вуаль подписи меню и буквы
## уровня наезжали друг на друга. Небо остаётся видимым.
## Порядок важен: сначала пересчёт (_layout_text_lines включает буквы
## обратно), и только потом гашение. Иначе меню открывается поверх
## полупогашенного слоя — каша.
## Граница слоёв «игра/меню»: всё игровое (текст, герои, модалка,
## кнопки, табло-дебаг) принадлежит игре и гаснет целиком, когда
## открыто меню. Меню рисует только своё поверх вуали. Правило одно:
## видимостью игрового слоя владеет только эта функция — иначе
## модалка победы просвечивает сквозь меню (так и было: over_p
## здесь не гасили).
func _set_play_ui(on: bool) -> void:
	_layout_text_lines()
	_refresh_hud()
	for tl in text_labels:
		tl.visible = on and tl.visible
	card_p.visible = on and not display_lines.is_empty()
	hud_label.visible = on
	hud_p.visible = on
	over_p.visible = on and (state == "won" or state == "lost")
	overlay_label.visible = over_p.visible
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
	top_safe = Ui.top_inset(view_h)
	# Своя клавиатура занимает низ — раскладка едет от остатка.
	# Высота от view_h (не от k): разрываем цикл k↔kb_h. При системной
	# галке высоту ставит её замер (poll), здесь не трогаем.
	if not S.get_sys_kb():
		kb_h = _own_h()
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
	text_y = 80.0 * k + top_safe
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
	# Метрики букв поменялись — строки могут перестать влезать, а на
	# ходу уровня их пересобирает _reflow_text (зайца не сбивает).
	_reflow_text()
	_layout_text_lines()
	# Табло-дебаг якорится к низу ЭФФЕКТИВНОЙ области: иначе
	# клавиатура его перекрывает. В обычной игре оно скрыто.
	hud_label.position = Vector2(margin, _eff_h() - 95.0 * k)
	hud_label.add_theme_font_size_override("font_size", int(18.0 * k))
	# Подсказка рисуется в _draw_hint (позиция и пилюля — там же).
	# Геометрия модалки — в _layout_text_lines (каждый кадр): позиция
	# зависит от скролла. Здесь только кнопки и панели.
	hud_label.size = Vector2(view_w - margin * 2.0, 70.0 * k)
	# Кнопка ≡ — справа вверху, на всех платформах одинаково. Отдельной
	# кнопки вызова клавиатуры нет: её вызывает тап по полю ввода
	# в меню и по рабочей области в игре (решение автора 10.2026).
	_players_rect = Rect2(view_w - 72.0 * k, 16.0 * k + top_safe, 56.0 * k, 48.0 * k)
	_layout_card()
	_layout_pills()
	# Панель модалки обновляется в _layout_text_lines (каждый кадр),
	# не здесь: см. комментарий там.
	# Меню живёт своей геометрией (свою клавиатуру считает само).
	# При системной галке игре отдаёт ей свой замер высоты — иначе поле
	# ввода и кнопки уезжают под клавиатуру.
	if menu != null:
		if S.get_sys_kb():
			menu.set("sys_kb_h", kb_h)
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
		text_y = 80.0 * k + top_safe
	else:
		text_y = maxf(40.0 * k, (_eff_h() - 200.0 * k - block_h) * 0.5) + top_safe
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
	# Панель модалки — здесь же, каждый кадр, а не в релэяуте: иначе
	# при скролле лейбл уезжает, а панель (и подсказка звёздочек,
	# которая считается от панели) остаётся и ложится на текст.
	over_p.position = overlay_label.position + Vector2(-24.0 * k, -16.0 * k)
	over_p.size = overlay_label.size + Vector2(48.0 * k, 32.0 * k)
	over_p.visible = overlay_label.visible
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
	# Клавиатуру пере-поднимаем: если уровень начат нажатием клавиши,
	# сессия IME рвётся и буквы уходят в никуда (жалоба автора 10.2026:
	# «после смены уровня нажимал правильную букву, реакции не было»).
	_kb_refocus_now()

	# Слой и шифт своей клавиатуры сбрасываем: новый уровень — чистые буквы.
	kb_layer = "ru"
	kb_lang = "ru"
	kb_shift = false
	# И предупреждение о CapsLock: новый текст — новая жизнь.
	_caps_warn = false
	# И подсказка звёздочки: модалки больше нет.
	_star_tip = 0
	_reindex_lines()
	# Взрослый режим: набирается всё, что видно. Регистр важен —
	# но это вывод из _all_keys() (см. _exact()), а не состояние:
	# хранить его отдельно значило бы рассинхрон.
	if _all_keys():
		active.clear()
		for line in display_lines:
			for i in line.length():
				active[line.substr(i, 1)] = true
	else:
		active = B.active_chars(difficulty)
	typed_cells.clear()
	passed.clear()
	errors.clear()
	_undo.clear()
	_comp_active = false
	_comp_dels = 0
	_comp_chars = ""
	_comp_region = ""
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
	return ch == " " or active.has(ch if _exact() else ch.to_lower())


## Сравнение ввода: в дебаге регистр важен, иначе — без учёта.
func _eq(a: String, b: String) -> bool:
	# Нeстрогая ё: ё и е — одна буква в обе стороны. Обе сводим
	# к строчной е, потом обычный регистровый разбор (ошибочный
	# регистр при строгом режиме всё равно не проходит).
	if not profile_yo:
		a = a.replace("ё", "е").replace("Ё", "е")
		b = b.replace("ё", "е").replace("Ё", "е")
	if _exact():
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
	if ke == null:
		return
	if not ke.pressed or ke.echo:
		return
	if ke.keycode == KEY_ESCAPE:
		if menu_open:
			# Открыто меню — ввод его: сюда попадаем, только если меню
			# клавишу не забрало (страховка). Там Esc тоже выход.
			return
		# Esc — всегда выход сразу, даже из полноэкранного.
		# Полноэкранный переключается только Alt+Enter и F11.
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
		# F4 свободна: симуляция клавиатуры для стенда убрана вместе
		# с системной клавиатурой (своя рисуется всегда).
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
		# Дальше — только видимый символ (буква, цифра, знак, пробел)
		# или Enter. Вспомогательные и функциональные клавиши
		# (модификаторы, стрелки, Tab, Backspace, Delete, F-клавиши)
		# модалку не листают: случайный задев не перелистывает дальше.
		var code := ke.unicode
		if ke.keycode == KEY_ENTER or ke.keycode == KEY_KP_ENTER:
			code = 13
		if code == 10 or code == 13 or (code >= 32 and code != 127):
			_new_level()
		return
	if state != "playing":
		return
	# ПОРЯДОК ВВОДА. Пока в буфере лежат софт-символы (keycode
	# KEY_UNKNOWN — так шлёт Яндекс), следующий ввод обязан ждать своей
	# очереди, даже если у него настоящий keycode: пробел с клавиатуры
	# приходит как KEY_SPACE и раньше применялся напрямую, перепрыгивая
	# букву, нажатую за 6 мс до него. Живой лог 10.2026: «а» ушла в буфер,
	# пробел применился первым — две красные метки на ровном месте, и всё
	# выглядело как «букву не считает». Сбрасываем буфер (он применит всё
	# накопленное по порядку) и только потом берёмся за это событие.
	if _comp_active and _comp_chars != "" and not _is_soft(ke):
		_comp_flush()
	# Backspace с системной клавиатуры — тоже без keycode (unicode 8).
	# Софт-серии (DEL + перепись региона) копятся в composing-буфер:
	# разбираются во flush в начале _process, задержка ≤ кадр.
	if ke.keycode == KEY_BACKSPACE or ke.unicode == 8:
		if _is_soft(ke):
			_comp_del()
		else:
			_backspace()
		return
	# Управляющие символы — не буквы: иначе Enter с системной прямо во
	# время партии рисовал бы красную метку перевода строки.
	if ke.unicode < 32:
		return
	if _is_soft(ke):
		# Софт-клавиатура капслока не имеет: предупреждение о CapsLock
		# для её заглавных — ложное (раньше орало на каждую букву).
		# Одиночный символ без серии — тоже серия (из одного): flush
		# разберёт его обычным путём, задержка ≤ кадр незаметна.
		if not _comp_active:
			_comp_active = true
			_comp_origin = Vector2i(cursor_line, cursor_pos)
			_comp_dels = 0
			_comp_chars = ""
			_comp_undo_mark = _undo.size()
		_comp_chars += String.chr(ke.unicode)
		return
	# АВТОПУНКТУАЦИЯ IME. Яндекс (и Gboard) сами вставляют точку после
	# пробела, а ещё и по второму нажатию пробела. Приходит она с
	# НАСТОЯЩИМ keycode (KEY_PERIOD = 46 и т.п.), поэтому composing-буфер
	# её не задерживает: точка выползает сразу, в обход очереди, и если
	# игра её НЕ ЖДЁТ — встаёт красной меткой и уносит курсор. Живой лог
	# 10.2026: TYPE;.; ;mark;(1, 5) сразу после BACK;rollback — игрок
	# такой точки не нажимал. Наказывать за автопунктуацию нельзя:
	# если знак не тот, что ждёт игра, молча пропускаем.
	var want_ch := _current()
	var got_ch := String.chr(ke.unicode)
	if (
		S.get_sys_kb()
		and (
			ke.keycode == KEY_PERIOD or ke.keycode == KEY_COMMA
			or ke.keycode == KEY_SEMICOLON or ke.keycode == KEY_QUESTION
		)
		and not _eq(got_ch, want_ch)
	):

		return
	if _exact():
		_caps_check(ke)
	_type_char(got_ch)


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


## Стек снятий Backspace: [{pos, ch, passed, error}]. Нужен composing-буферу
## ниже: молча вернуть снятое, если серия оказалась перепиской слова.
var _undo: Array = []
const UNDO_CAP := 64

## Вспышка клетки: ответ на действия, которые иначе не видны. Живой лог
## 10.2026 показал два таких случая, и оба выглядели как «игра не считает»:
##  * откат Backspace встал на серую клетку — стирать нечего, отклика нет;
##  * повтор той же буквы (перепись IME) проглочен молча — буква на месте,
##    но игрок thinks не засчиталось, и он жал снова по кругу.
## Клетка вспыхивает на HINT_T — видно, где игра видит набранное.
var hints: Dictionary = {}
const HINT_T := 1.4


func _hint_at(l: int, p: int) -> void:
	if l < 0 or l >= display_lines.size():
		return
	if p < 0 or p >= display_lines[l].length():
		return
	hints[_key(l, p)] = HINT_T
	# В лог: клетка, которая вспыхнула синим. По нему видно, откуда
	# мерцание — откат, дубль клавиши или ещё что (жалоба автора 10.2026).



## Ближайшая клетка позади курсора, которую НАБРАЛ ИГРОК (а не серый
## автопропуск). Откат Backspace обязан вставать на такую клетку: раньше
## он искал «хоть что-то пройденное» и попадал на серые символы, которые
## игра проскочила сама, — Backspace вставал на букву, которой игрок не
## печатал, и повторный набор давал метку (выглядело как автозамена,
## живой лог 10.2026: TYPE;о;с;mark после BACK;rollback;0:2).
func _last_filled_behind() -> Vector2i:
	var l := cursor_line
	var p := cursor_pos
	for _n in 4000:
		if p > 0:
			p -= 1
		elif l > 0:
			l -= 1
			p = display_lines[l].length() - 1
		else:
			return Vector2i(-1, -1)
		var k := _key(l, p)
		if typed_cells.has(k) or errors.has(k):
			return Vector2i(l, p)
	return Vector2i(-1, -1)


func _undo_push(l: int, p: int, had_passed: bool, had_error: String) -> void:
	if _undo.size() >= UNDO_CAP:
		_undo.clear()
		return
	if l < 0 or l >= display_lines.size():
		return
	if p < 0 or p >= display_lines[l].length():
		return
	_undo.append({
		"pos": Vector2i(l, p),
		"ch": display_lines[l].substr(p, 1),
		"passed": had_passed,
		"error": had_error,
	})


## Composing-буфер IME. Экранная клавиатура со словарём (Яндекс, Gboard —
## русский) набирает через composing-регион: каждый тап стирает и вводит
## заново всё слово (серии DEL + дубли; keycode KEY_UNKNOWN/0, живой лог
## с телефона 10.2026). Без буфера каждый дубль — «опечатка»: красная
## метка, откат, врущие счётчики; кириллица «не набирается», хотя события
## доходят. Правило: серия [DEL×k + символы], чей префикс повторяет прошлый
## регион, — переписка: снятое возвращается молча, вводится только новый
## хвост. Всё остальное — обычный ввод (десктоп не меняется вообще).
## Софт-события разбираются во flush в начале _process: задержка ≤ кадр.
var _comp_active := false
var _comp_origin := Vector2i(-1, -1)
var _comp_dels := 0
var _comp_chars := ""
var _comp_region := ""
var _comp_undo_mark := 0
# Счётчики composing-серий: сколько схлопнулось в переписку,
# сколько отменено как машинный мусор.
var _comp_hits := 0
var _comp_drops := 0


## Событие с экранной клавиатуры: движок отдаёт keycode KEY_UNKNOWN
## (Яндекс, живой лог) или KEY_NONE (Gboard). Железная клавиатура шлёт
## физические keycode — её не буферизуем: серий там нет, задержка ни к чему.
func _is_soft(ke: InputEventKey) -> bool:
	return ke.keycode == KEY_UNKNOWN or ke.keycode == KEY_NONE


## DEL из серии: запоминаем и выполняем как обычно (откат + стек снятий).
## Висящие DEL (символы ещё не пришли — серия размазалась по кадрам,
## автозамена после пробела) ждут продолжения до дедлайна, а не
## сбрасываются в том же flush: иначе откаты уже применены, а слово
## придёт следующим циклом и встанет красными метками.
var _comp_deadline := 0
func _comp_del() -> void:
	if not _comp_active:
		_comp_active = true
		_comp_origin = Vector2i(cursor_line, cursor_pos)
		_comp_dels = 0
		_comp_chars = ""
		_comp_undo_mark = _undo.size()
	_comp_dels += 1
	_comp_deadline = Time.get_ticks_msec() + 150
	_backspace()


## Разобрать накопленное. Софт-серия [DEL×k + символы] в одном межкадровом
## цикле — всегда машинная: ручной ввод разбит кадрами (между стиранием
## и следующей буквой всегда есть flush с пустыми символами). Живой лог
## Яндекса 10.2026 знает три потока: одиночки без DEL (медленный набор),
## пары [DEL + буква] (быстрый набор, дифф-режим), серии с перепиской
## всего региона и автозамены слова после пробела. Обычный путь для серий
## с DEL — это откаты и красные метки на каждую букву («после пробела
## отбрасывает назад»). Поэтому: снятое серией возвращается молча всегда
## (DEL в цикле — машинные), курсор — на начало серии, а дальше:
##  - префикс повторяет регион (m≥2) — переписка: ввести только хвост;
##  - пара [DEL + буква] (m==1) — ввести букву обычным путём: верная
##    засчитается, неверная честно встанет меткой, как любая опечатка;
##  - чужая замена целиком (m≥2, префикс чужой — автозамена слова) —
##    отменить: иначе откаты и красные метки на каждую букву.
## Одиночки без DEL и разделённые кадрами идут обычным путём.
func _comp_flush() -> void:
	if not _comp_active:
		return
	if state != "playing":
		# Уровень кончился, а пачка ещё летела: сбрасываем её молча,
		# иначе буква дописывается после победы и сбивает счётчик.
		_comp_active = false
		_comp_region = ""
		_comp_dels = 0
		_comp_chars = ""

		return
	var tail := _comp_chars
	if tail == "":
		# Символов нет — либо настоящие ручные стирания, либо серия
		# размазалась (автозамена: DEL сейчас, слово следующим циклом).
		# DEL уже применены; если дедлайн не вышел — ждём символы,
		# иначе цикл закрыт (стирания настоящие).
		if _comp_dels > 0 and Time.get_ticks_msec() < _comp_deadline:
			return
		_comp_active = false
		_comp_region = ""
		_comp_dels = 0
		_comp_chars = ""
		return
	_comp_active = false

	if _comp_dels > 0:
		# Снятое серией возвращается молча всегда (DEL в цикле машинные),
		# курсор — на начало серии. Дальше три ветки:
		_comp_restore()
		if tail.length() >= 2:
			if tail.left(tail.length() - 1) == _comp_region.left(tail.length() - 1):
				# Переписка региона — ввести только новый хвост.
				tail = tail.right(1)
				_comp_hits += 1

			else:
				# Чужая замена (автозамена слова) — отменить целиком:
				# иначе откаты и красные метки на каждую букву.
				tail = ""
				_comp_drops += 1

		# Пара [DEL + буква] (m==1): ввести букву обычным путём с начала
		# серии — верная засчитается, неверная честно встанет меткой.
	_comp_region = _comp_chars
	_comp_dels = 0
	_comp_chars = ""
	for i in tail.length():
		_type_char_comp(tail.substr(i, 1))


## Ввод софт-символа из буфера. Глушим ТОЛЬКО настоящий дубль клавиши:
## Яндекс (и другие IME с словарём) присылают одну и ту же букву дважды
## подряд, миллисекунда в миллисекунду (живой лог 10.2026: `FLUSH;0;оо;о`).
##
## Раньше правило было шире: глушилась любая буква, совпавшая с ЧЕМ-ЛИБО
## пройденным раньше в тексте. Это было ошибкой: игра требует набирать
## «Прибежала», а потом «внучка» — и «л» из «внучка» глушилась тем, что
## «л» уже встречалась в «Прибежала». Автор видел «нажал, а не считает»
## и ходил по кругу (живой лог 10.2026: `TYPE;л;ч;dup-ignore;...;0:7`).
## Теперь глушится только повтор той же буквы в том же нажатии; всё
## остальное — обычным путём, с честной меткой при настоящей опечатке.
## Окно «дубля клавиши». Дубли от IME приходят в ОДНУ миллисекунду
## (живой лог 10.2026: два «о» с одной отметкой времени), поэтому окно
## можно держать очень узким. Было 60 мс — и намеренное двойное нажатие
## пробела (два слова подряд, «а» и «а») попадало под фильтр: второй
## символ молча съедался (жалоба автора 10.2026: «если жму пробел дважды
## быстро, второй не засчитывается»). Человек дважды не жмёт быстрее
## ~120 мс, так что 25 мс ловит только машинальные дубли.
const DUP_MS := 25
var _dup_ch := ""
var _dup_t := 0
var _dup_cell_key := ""



func _type_char_comp(ch: String) -> void:
	var now := Time.get_ticks_msec()
	if (
		ch == _dup_ch
		and _dup_t > 0
		and now - _dup_t <= DUP_MS
		and not _eq(ch, _current())
	):
		_comp_drops += 1
		if _dup_cell_key != "":
			var parts := _dup_cell_key.split(":")
			if parts.size() == 2:
				_hint_at(int(parts[0]), int(parts[1]))

		return
	var ok_before := typed_ok
	var cur_before := _key(cursor_line, cursor_pos)
	_type_char(ch)
	if typed_ok > ok_before:
		# Запоминаем принятую букву: следующая такая же подряд — дубль
		# клавиши, её глушим (с подсказкой ГДЕ она стоит).
		_dup_ch = ch
		_dup_t = now
		_dup_cell_key = cur_before


## Вернуть снятое серией DEL: снимаем их из undo-стека обратно.
func _comp_restore() -> void:
	while _undo.size() > _comp_undo_mark:
		var v: Dictionary = _undo.pop_back()
		var kk := "%d:%d" % [v["pos"].x, v["pos"].y]
		if String(v["error"]) != "":
			errors[kk] = String(v["error"])
		if bool(v["passed"]):
			passed[kk] = true
	cursor_line = _comp_origin.x
	cursor_pos = _comp_origin.y


## Клетки, набранные нажатием (не серые автопропуски). Нужны откату
## Backspace: он отменяет последнюю НАБРАННУЮ букву, а не последнюю
## пройденную клетку (серые символы проскочила сама игра).
var typed_cells: Dictionary = {}


func _type_char(ch: String) -> void:
	if state != "playing":
		return  # уровень окончен: ввод ниже не считается
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
		typed_cells[kk] = true
		typed_ok += 1
		chomp_t = CHOMP_T
		var cur_before := Vector2i(cursor_line, cursor_pos)
		_advance()
		_skip_inactive()

	else:
		# Опечатка: красная метка на месте курсора и шаг назад —
		# механика 0.0.10. Каждая следующая неверная клавиша отбрасывает
		# ещё дальше: неверные копятся назад, Backspace снимает их по
		# одной. Заглушка diag21 («в пачке без отката») ломала это на
		# всём телефонном вводе: метки затирали друг друга на месте,
		# курсор стоял, снимать было нечего.
		errors[_key(cursor_line, cursor_pos)] = ch
		typed_cells[_key(cursor_line, cursor_pos)] = true
		typed_bad += 1
		shake_t = SHAKE_T
		var kb_before := Vector2i(cursor_line, cursor_pos)
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
##     Механика пропусков учтена: серые символы — это клетки, но откат
##     через них ПЕРЕПРЫГИВАЕТ (живой лог 10.2026: откат на серую клетку
##     делал повторный набор красной меткой — выглядело как автозамена).
##     Каждое нажатие отменяет ровно одну набранную букву. Упор в начало
##     текста: если за курсором ничего не набрано, откатываться некуда.
##     Автопропуск после отката НЕ делаем: заяц обязан стоять перед той
##     буквой, на которую откатился, иначе откат тут же проскочит мимо.
func _backspace() -> void:
	var k := _key(cursor_line, cursor_pos)
	if errors.has(k):
		_undo_push(cursor_line, cursor_pos, passed.has(k), String(errors[k]))
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
		_undo_push(fwd_l, fwd_p, passed.has(fk), String(errors[fk]))
		errors.erase(fk)
		cursor_line = fwd_l
		cursor_pos = fwd_p
		_skip_inactive()
		_refresh()

		return
	# 3) ОТКАТ НАЗАД — на последнюю НАБРАННУЮ клетку, перепрыгивая серые.
	# Раньше откат шёл ровно на одну клетку, и это ломало игру: между
	# набранными буквами лежат серые символы («о» в «Посадил», дальше
	# «с», «а»), Backspace вставал на серую клетку, где его букве не
	# место, и повторный набор давал красную метку. Живой лог 10.2026:
	#   TYPE;о;о;ok;(0,1)->(0,3)   ← «о» принята
	#   BACK;rollback;0:2          ← откат на СЕРУЮ «с»
	#   TYPE;о;с;mark;(0,2)        ← «о» на месте «с» — метка
	# Автор описывал это как автозамену: игра будто сама переставляла
	# буквы. Теперь каждое нажатие Backspace отменяет ровно одну
	# набранную букву и всегда что-то видно.
	if S.get_sys_kb():
		# Системная клавиатура: откат НЕ отменяет набранные буквы. Её
		# собственное поле короче игрового (IME схлопывает дубли), и
		# после отката она пришлёт меньше символов, чем снято: игрок
		# набирает одно и то же по кругу, ёж догоняет (живой лог
		# 10.2026: 6 откатов подряд, затем пачки короче — зацикливание).
		# Но совсем молча нельзя: клетка под курсором вспыхивает, видно,
		# что нажатие дошло (иначе Backspace «не работает»).
		_hint_at(cursor_line, cursor_pos)
		_refresh()
		return
	var b := _last_filled_behind()
	if b.x < 0:
		return  # за курсором нет ничего набранного
	cursor_line = b.x
	cursor_pos = b.y
	var bk := _key(cursor_line, cursor_pos)
	var had := passed.has(bk) or errors.has(bk)
	_undo_push(cursor_line, cursor_pos, passed.has(bk), String(errors.get(bk, "")))
	passed.erase(bk)
	errors.erase(bk)
	typed_cells.erase(bk)
	_refresh()
	if had:
		pass
	else:
		# Серая клетка: откат есть, а стирать нечего. Молчание выглядело
		# как «игра не считает» (живой лог 10.2026) — показываем, где
		# игра видит последнюю набранную букву.
		var last := _last_filled_behind()
		if last.x >= 0:
			_hint_at(last.x, last.y)



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
	# В лог: конец уровня. По нему видно, что игра перестала принимать
	# буквы из-за победы/проигрыша, а не из-за поломки ввода (жалоба
	# автора 10.2026: «перестала реагировать на правильную кнопку» —
	# в логе не было ни LEVEL, ни END, и концовку нельзя было отличить).

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
	# Флаги — свежие из файла, а не из памяти начала уровня: их могло
	# сменить меню (файл — источник правды, см. save.gd).
	S.save_profile(profile_name, {
		"difficulty": difficulty,
		"wins_in_row": wins_in_row,
		"ema_cpm": ema_cpm,
		"ema_acc": ema_acc,
		"enemy_cps": enemy_cps,
		"all_keys": bool(prof.get("all_keys", false)),
		"yo_strict": bool(prof.get("yo_strict", true)),
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
	# Composing-буфер IME (софт-клавиатура) разбираем первым: ввод
	# применяется до движения ежа и таймеров того же кадра.
	_comp_flush()
	if _kb_refocus > 0:
		_kb_refocus -= 1
		if _kb_refocus == 1:
			# Первый кадр: скрыть — иначе show ничего не пересоздаст.
			if DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD):
				DisplayServer.virtual_keyboard_hide()
				_kb_shown = false
				_kb_reshown = false
				_kb_request_t = time
		elif _kb_refocus == 0:
			# Второй: показать заново — сессия IME встанет как надо.
			if DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD):
				DisplayServer.virtual_keyboard_show("")
				_kb_shown = true
				_kb_reshown = false
				_kb_request_t = time
	if S.get_sys_kb():
		_sync_keyboard()
		_poll_keyboard()
	else:
		# Своя клавиатура показалась/скрылась (смена состояния) —
		# пересчитать раскладку. Высота от view_h, без циклов.
		var oh := _own_h()
		if not is_equal_approx(oh, kb_h):
			kb_h = oh

			_relayout()
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
	if not hints.is_empty():
		var still := false
		for hk in hints.keys():
			var left := float(hints[hk]) - dt
			if left > 0.0:
				hints[hk] = left
				still = true
			else:
				hints.erase(hk)
				# В лог: клетка перестала вспыхивать. Автор видел мерцающую
				# «а» и не мог понять, откуда оно (жалоба 10.2026).

		if not still:
			hints.clear()
		_refresh()
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
## Своя клавиатура: видна в партии на сенсорных устройствах. На десктопе
## есть железная — своя не нужна. Под открытым меню — скрыта (меню
## показывает свою, если вводит имя). На модалке победы/поражения —
## скрыта: там ввод не нужен, тапы листают дальше.
func _own_shown() -> bool:
	if S.get_sys_kb():
		return false
	if menu_open:
		return false
	if state != "playing":
		return false
	return not _is_desktop()


## Область своей клавиатуры: низ экрана, высота от ширины (кнопки —
## почти квадраты, см. height_for). От view_h не зависит: разрываем цикл
## с раскладкой (высота входит в eff_h).
func _own_rect() -> Rect2:
	var h := Kbd.height_for(view_w)
	return Rect2(16.0, view_h - h - 16.0, view_w - 32.0, h)


## Высота своей клавиатуры в пикселях канваса (0 — скрыта). Ставится
## в _relayout: раскладка едет от неё через _eff_h, как раньше от системной.
func _own_h() -> float:
	if not _own_shown():
		return 0.0
	return _own_rect().size.y


## Системная клавиатура (только при её галке в меню): ей владеет игра
## целиком, борьба с автозаменой — composing-буфер (_comp_*). Вызывается
## каждый кадр, но дёргает DisplayServer только на смене состояния.
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
		DisplayServer.virtual_keyboard_show("")
	else:
		DisplayServer.virtual_keyboard_hide()


## Пере-поднять системную клавиатуру: hide сейчас, show через два кадра.
## Простой show не помогает — сессия IME уже мертва, нужен цикл.
## Само решение отделено от платформы: на десктопе счётчик тоже идёт,
## но ничего не происходит (фичи виртуальной клавиатуры нет).
func _kb_refocus_now() -> void:

	if not S.get_sys_kb():
		return
	_kb_refocus = 2


## Нужна ли системная клавиатура прямо сейчас. Имя вводится — в любой
## ориентации; партия идёт — только в портрете, в альбоме её зовёт тап
## по рабочей области. Чистая функция от состояния — матрица в logic_test.
func _kb_want() -> bool:
	if menu_open:
		return menu != null and bool(menu.get("input_active"))
	if _kb_manual:
		return true
	if view_w > view_h:
		return false
	return true


## Эффективная высота экрана: низ, занятый клавиатурой, не наш.
## Вся раскладка считается от неё. Пол под ногами не проваливается:
## минимум 220 px.
func _eff_h() -> float:
	return Ui.eff_h(view_h, kb_h)


## Высота системной клавиатуры в пикселях канваса: экранные пиксели
## делим на масштаб экрана (на телефоне он 2–3). Без фичи — всегда ноль.
func _kb_height_px() -> float:
	if not DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD):
		_kb_raw = 0.0
		return 0.0
	_kb_raw = float(DisplayServer.virtual_keyboard_get_height())
	var scr := DisplayServer.window_get_current_screen()
	var scale := maxf(1.0, DisplayServer.screen_get_scale(scr))
	return _kb_raw / scale


## Следим за системной каждый кадр: выехала/уехала — пересчитать раскладку.
## Смахнутую пользователем вернёт тап по тексту, по рабочей области или
## новый контекст (разовый пере-показ — только если так и не выехала).
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
## если клавиатура так и не выехала (надёжность появления). Матрица в
## logic_test.
static func kb_need_reshow(want: bool, shown: bool, height: float, elapsed: float, seen: bool, reshown: bool) -> bool:
	return want and shown and height <= 0.0 and elapsed > 3.0 and not seen and not reshown


## Тап по рабочей области при системной галке: показать её прямо сейчас.
func _kb_summon() -> void:
	_kb_manual = true
	if not DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD):
		return
	_kb_request_t = time
	_kb_seen = false
	_kb_reshown = false
	_kb_shown = true
	DisplayServer.virtual_keyboard_show("")


## Все буквы — одно начертание и кегль. Состояние только оттенком:
## активная — чернила, будущая — средний серый, пройденная — светлый.
func _refresh() -> void:
	# Гасим все строки разом: иначе при переносе старый текст остаётся
	# на старых позициях, пока новый уже нарисован (жалоба автора
	# 10.2026 про «старое не стирается, новое поверх»). Перерисовка
	# должна быть атомарной в пределах кадра, а не «когда получится».
	for tl in text_labels:
		tl.visible = false
		tl.text = ""
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
				var ecol := Ui.ERR_NIGHT_HEX if night else Ui.ERR_DAY_HEX
				if hints.has(kk):
					ecol = Ui.HINT_NIGHT_HEX if night else Ui.HINT_DAY_HEX
				out += "[color=" + ecol + "]" + shown + "[/color]"
				continue
			# Пройденное (съеденное или пропущенное) — серым.
			var col := "#6f6a5e" if not night else "#7a86a0"
			if passed.has(kk):
				# Съеденное серым, но ночное #4a5468 давало 1.9:1 к
				# карточке — буквы пропадали, строка шла дырами.
				col = "#b3a996" if not night else "#6f7b99"
			elif _is_active(ch):
				col = "#1c1a16" if not night else "#f2ede0"
			if hints.has(kk):
				# Вспышка: видно, что нажатие принято (буква не изменилась).
				col = Ui.HINT_DAY_HEX if not night else Ui.HINT_NIGHT_HEX
			out += "[color=" + col + "]" + esc + "[/color]"
		text_labels[l].text = out
		text_labels[l].visible = true
	# Позиции и видимость окна скролла — сразу здесь же, тем же проходом:
	# иначе между _refresh и _layout_text_lines кадр показывает старые
	# строки на новых местах.
	_layout_text_lines()
	for i in range(display_lines.size(), text_labels.size()):
		text_labels[i].visible = false


## Подсказка следующей клавиши частями: обычный текст (cap=false)
## и «кнопки» (cap=true) — буква в скруглённой рамке, пробел — словом
## «Пробел», заглавная в строгом режиме — парой Shift + буква.
## Пустой список — подсказку прятать.
## Латиница ли буква (для варнинга о чужом слое клавиатуры).
static func _is_latin(ch: String) -> bool:
	return (ch >= "A" and ch <= "Z") or (ch >= "a" and ch <= "z")


func _hint_parts() -> Array:
	if state != "playing":
		return []
	if _caps_warn and _exact():
		return [{"s": "Выключи CapsLock!", "cap": false}]
	if not errors.is_empty():
		return [
			{"s": "Жми:", "cap": false},
			{"s": "←", "cap": true},
			{"s": "Стереть", "cap": false},
		]
	var cur := _current()
	if cur == "":
		return []
	if cur == " ":
		return [{"s": "Жми:", "cap": false}, {"s": "Пробел", "cap": true}]
	# Чужая раскладка: буква латиницей, а слой русский (и наоборот) —
	# предупреждаем, как о CapsLock: иначе жмёшь не ту клавиатуру
	# (требование автора 10.2026: взрослые тексты с латиницей).
	if _is_latin(cur) and kb_layer != "en":
		return [
			{"s": "Жми:", "cap": false},
			{"s": "EN", "cap": true},
			{"s": "+", "cap": false},
			{"s": cur, "cap": true},
		]
	if not _is_latin(cur) and kb_layer == "en":
		return [
			{"s": "Жми:", "cap": false},
			{"s": "РУ", "cap": true},
			{"s": "+", "cap": false},
			{"s": cur, "cap": true},
		]
	if _exact() and cur == cur.to_upper() and cur != cur.to_lower():
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
		{"s": cur if _exact() else cur.to_upper(), "cap": true},
	]


## Та же подсказка одной строкой: для тестов и дебага. Кнопки — в [].
func _hint_text() -> String:
	var out: Array = []
	for p in _hint_parts():
		var s := String(p["s"])
		out.append(("[" + s + "]") if bool(p["cap"]) else s)
	return " ".join(out)


## Центр i-й звёздочки (0..2): строка центрирована в лейбле,
## шаг — advance глифа (моноширинный шрифт: ★ и ☆ одинаковы).
func _star_center(i: int) -> Vector2:
	var pitch := mono.get_string_size(
		"★", HORIZONTAL_ALIGNMENT_LEFT, -1.0, _over_fs
	).x
	var cx := overlay_label.position.x + overlay_label.size.x * 0.5
	return Vector2(
		cx + (float(i) - 1.0) * pitch,
		overlay_label.position.y + overlay_label.size.y * 0.25
	)


## Какая звезда под точкой (1..3, 0 — мимо). Маппинг относительный
## (ближайший центр), а не прямоугольниками: абсолютные размеры
## плывут от кегля, а центры всегда на своих местах. Палец прощает
## полшага в стороны.
func _star_at(pos: Vector2) -> int:
	if state != "won" or not over_p.visible:
		return 0
	var top := overlay_label.position.y
	if pos.y < top or pos.y > top + overlay_label.size.y * 0.5:
		return 0
	var pitch := mono.get_string_size(
		"★", HORIZONTAL_ALIGNMENT_LEFT, -1.0, _over_fs
	).x
	if pitch <= 0.0:
		return 0
	var cx := overlay_label.position.x + overlay_label.size.x * 0.5
	var f := (pos.x - cx) / pitch + 1.0
	var i := int(floor(f + 0.5))
	if i < 0 or i > 2:
		return 0
	if absf(f - float(i)) > 0.5 + 14.0 * k / pitch:
		return 0
	return i + 1


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
## там есть звёзды). Со своей пилюлей: без неё текст сливался с фоном.
func _draw_star_tip() -> void:
	if not over_p.visible or state != "won" or _star_tip < 1 or _star_tip > 3:
		return
	var fs := int(20.0 * k)
	var t := _star_tip_text(_star_tip)
	var tw := mono.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs).x
	var ty := over_p.position.y + over_p.size.y + 30.0 * k
	draw_style_box(
		pill_sb,
		Rect2(view_w * 0.5 - tw * 0.5 - 18.0 * k, ty - float(fs) - 12.0 * k, tw + 36.0 * k, float(fs) + 26.0 * k)
	)
	draw_string(
		mono,
		Vector2(view_w * 0.5 - tw * 0.5, ty),
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
	# Центр строки — на месте бывшей подсказки-лейбла (низ минус 137.5k).
	# Панель (cap_h + 16k) должна остаться ВЫШЕ границы _eff_h(): иначе
	# при открытой клавиатуре её нижняя половина уезжает под неё и
	# подсказка «закрывается» (жалоба автора 10.2026).
	# Панель (cap_h + 16k) должна остаться ВЫШЕ границы _eff_h(): иначе
	# при открытой клавиатуре её нижняя половина уезжает под неё и
	# подсказка «закрывается» (жалоба автора 10.2026). При очень большой
	# клавиатуре (k/экран маленькие) _eff_h упирается в EFF_MIN_H — тогда
	# подсказка обязана уехать на самый низ ДО границы, а не под неё.
	var panel_h := cap_h + 16.0 * k
	var y_top := _eff_h() - 137.5 * k - cap_h * 0.5
	y_top = minf(y_top, _eff_h() - panel_h - 8.0 * k)
	var lowest := 8.0 * k + top_safe
	if y_top < lowest:
		# Текст заезжает под клавиатуру, но подсказка — нет: она уходит на
		# дно доступной зоны целиком.
		y_top = maxf(lowest, _eff_h() - panel_h - 8.0 * k)
		if y_top + panel_h > _eff_h():
			y_top = maxf(lowest, _eff_h() - panel_h)
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


## Ширина, доступная строке табло: от поля до поля.
func _hud_avail() -> float:
	return view_w - margin * 2.0


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
	var txt := "[dbg ex=%.0f eln=%d cur=%d:%d cw=%.1f k=%.2f ok=%d bad=%d kb=%.0f sc=%.2f vw=%.0f vh=%.0f]" % [
		enemy_x, enemy_line, cursor_line, cursor_pos, char_w, k, typed_ok, typed_bad,
		kb_h, sc, view_w, view_h,
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
	_draw_own_kb()
	_draw_star_tip()
	_draw_enemy()
	# Героя рисуем всегда: на проигрыше у него шок на лице (укололи),
	# съедения нет.
	_draw_hero()


## Своя клавиатура: клавиши прямо дают символы (тап → буква, без IME).
## Рисуется в _draw поверх всего нижнего (области не пересекаются).
func _draw_own_kb() -> void:
	if not _own_shown():
		return
	Kbd.draw(
		self, _own_rect(), kb_layer, kb_lang, kb_shift, false, mono,
		int(30.0 * k), kb_key_sb, kb_on_sb, _ui_ink()
	)


## Долгое нажатие (стандарт Яндекс-клавиатуры): е→ё, ь→ъ. Состояние ждёт
## отпускания: короткое — обычный ввод уже случился, долгое — откатываем
## его и вводим альтернативу. Порог — полсекунды, как у системных.
const LONG_PRESS_MS := 500
var _lp_act := ""
var _lp_t0 := 0


## Нажатие на свою клавишу: символ — в _type_char, стереть — в _backspace,
## слой — дальше по кругу, шифт — флип. Напрямую, без key-событий: IME тут
## не участвует вообще, composing-переписям неоткуда взяться.
func _own_press(pos: Vector2) -> bool:
	if not _own_shown():
		return false
	var act := Kbd.hit(_own_rect(), kb_layer, kb_lang, kb_shift, false, pos)
	if act == "":
		return false
	_lp_act = ""
	if act == "стереть":
		_backspace()
	elif act == "слой":
		# Из знаков — назад на свой язык, иначе — в знаки.
		kb_layer = kb_lang if kb_layer == "sym" else "sym"
	elif act == "язык":
		kb_lang = "en" if kb_lang == "ru" else "ru"
		kb_layer = kb_lang
	elif act == "шифт":
		kb_shift = not kb_shift
	elif act == "пробел":
		kb_shift = false
		_type_char(" ")
	elif Kbd.long_alt(act) != "":
		kb_shift = false
		_type_char(act)
		_lp_act = act
		_lp_t0 = Time.get_ticks_msec()
	else:
		kb_shift = false
		_type_char(act)
	queue_redraw()
	get_viewport().set_input_as_handled()
	return true


## Отпускание после долгого нажатия на е/ь: введённую букву меняем на
## ё/ъ (откат + ввод альтернативы). Короткое — ничего не делает.
func _own_release(pos: Vector2) -> bool:
	if _lp_act == "":
		return false
	var done := false
	if Time.get_ticks_msec() - _lp_t0 >= LONG_PRESS_MS:
		var act := Kbd.hit(_own_rect(), kb_layer, kb_lang, false, false, pos)
		if act == _lp_act:
			_backspace()
			_type_char(Kbd.long_alt(_lp_act))
			done = true
	_lp_act = ""
	if done:
		queue_redraw()
		get_viewport().set_input_as_handled()
	return done


## Чернила для рисованного текста поверх панелей и фона: днём тёмные,
## ночью светлые. Пилюли сами меняют фон (_apply_night), а рисованный
## текст за ним не следил — ночью «Дальше», чёрточки ≡ и
## подпись прогресса тонули в тёмном.
func _ui_ink() -> Color:
	return Color("#e8e4d8") if night else INK


## Десктоп — там, где нет системной клавиатуры (нет и клавиши F2
## на экране, зато есть физическая). Кнопка игроков там подписана.
## _force_touch включает мобильную раскладку принудительно — для
## headless-тестов веток с клавиатурой (там фичи нет никогда).
var _force_touch := false
func _is_desktop() -> bool:
	return not _force_touch and not DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD)


## Подсказка кнопки игроков: на десктопе словами «Меню (F2)»
## (физическая клавиша есть), на телефоне пусто — там значок ≡
## без слов, клавиши F2 нет. Показываем только по наведению мыши,
## а не постоянно: сбоку от кнопки она лезла на луну и не читалась.
func _players_hint() -> String:
	return "Меню (F2)" if _is_desktop() else ""


## Мышь наведена на кнопку игроков: подсказка видна, пока наведена.
var _players_hover := false


## Кнопка тач-интерфейса: ≡ — игроки. Рисуем всегда (и на десктопе —
## как подсказка), работает везде: тап или клик. Прямоугольник считает
## _relayout, тычки разбирает _input. Клавиатуру вызывает тап по полю
## ввода и по рабочей области — отдельной кнопки нет.
func _draw_touch_buttons() -> void:
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
	if ph != "" and _players_hover:
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
		var tip := _star_at((event as InputEventMouseMotion).position)
		if tip != _star_tip:
			_star_tip = tip
			queue_redraw()
		return
	# Наведение на кнопку игроков (десктоп): подсказка «Меню (F2)»
	# видна, пока мышь на кнопке. Пальцем наведения нет — там и клавиши
	# F2 нет, подсказка не нужна.
	if event is InputEventMouseMotion and _is_desktop() and not menu_open:
		var hov := _players_rect.has_point((event as InputEventMouseMotion).position)
		if hov != _players_hover:
			_players_hover = hov
			queue_redraw()
		return
	var has_pos := false
	var pos := Vector2.ZERO
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			pos = mb.position
			has_pos = true
		elif mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			# Отпускание после долгого нажатия (е→ё, ь→ъ): разбирает
			# _own_release, остальное — мимо.
			_own_release(mb.position)
			return
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
		# кнопок. ≡ ведёт в меню, бейдж — дебаг (только дебажная
		# сборка). Тап по звезде только показывает расшифровку
		# (следующий тап всё равно идёт дальше).
		if _players_rect.has_point(pos):
			_open_menu()
			get_viewport().set_input_as_handled()
			return
		if state == "won":
			var tip := _star_at(pos)
			if tip > 0:
				_star_tip = tip
				queue_redraw()
				get_viewport().set_input_as_handled()
				return
		_new_level()
		get_viewport().set_input_as_handled()
		return
	if _players_rect.has_point(pos):
		_open_menu()
		get_viewport().set_input_as_handled()
		return
	# Своя клавиатура: клавиши раньше карточки (области не пересекаются).
	if _own_press(pos):
		return
	# Рабочая область: при системной галке тап её вызывает, при своей
	# она и так видна — тапу здесь делать нечего. Карточка последняя.
	if card_p.visible and Rect2(card_p.position, card_p.size).has_point(pos):
		if S.get_sys_kb():
			_kb_summon()
		get_viewport().set_input_as_handled()
		return
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
	var r := Rect2(Vector2((view_w - w) * 0.5, 14.0 * k + top_safe), Vector2(w, h))
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
	var r := Rect2(Vector2(14.0 * k, 14.0 * k + top_safe), Vector2(w, h))
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
	draw_texture(HERO_TEX, -HERO_TEX.get_size() * 0.5, (Ui.NIGHT_TINT if night else Color.WHITE))
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
	draw_texture(HEDGE_TEX, -HEDGE_TEX.get_size() * 0.5, (Ui.NIGHT_TINT if night else Color.WHITE))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_draw_puffs()
