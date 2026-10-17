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
const Texts := preload("res://scripts/texts.gd")
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
const BASE_W := 1100.0
const BASE_H := 650.0
## Строк текста минимум на экране: меньше — теряется контекст
## (видно только текущую строку). Переполнение уходит в скролл.
const R_MIN_ROWS := 3
const START_DELAY := 3.0

const INK := Color("#1c1a16")
const UI_TEXT := Color("#4a4438")
const GREEN := Color("#1e7a34")
const DARK_RED := Color("#b02323")

var display_lines: Array[String] = []
## Сколько пробелов выкинуто на разрывах ПЕРЕД каждой строкой (параллельно
## display_lines). Нужно рефлоу: логические смещения считаются в
## пространстве «все пробелы», иначе после поворота всё едет.
var line_drops: Array = []
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

## Строки, показанные на экране последним _refresh (для тестов: что
## нарисовано, то и лежит в display_lines — сверка без чтения пикселей).
var shown_rows: Array[String] = []
## Видимое окно скролла (считает _layout_text_lines): первая строка и
## сколько видно. Рисуем и проверяем только их.
var vis_first := 0
var vis_count := 3
## Видимость игрового слоя (меню-вуаль): текст рисуется только своим.
var play_ui := true
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
## Язык ввода ("ru"/"en"): его переключает глобус. Ряды при этом НЕ
## меняются (доска одна, русская физическая): меняется подсветка букв и
## то, какая буква вводится клавишей. Системную не вызываем вообще.
var kb_lang := "ru"
## Перелёт подписей при смене языка ввода: 0 — только начали, 1 — доехал.
## Старый язык помним, чтобы знать, откуда летел символ.
var kb_morph := 1.0
var kb_morph_from := ""
## Состояние шифта, из которого шёл перелёт.
var kb_morph_shift := false
## Клавиша под пальцем и сколько она ещё горит: человек должен видеть,
## что нажал ту самую клавишу (или промахнулся мимо всех).
## Курсор стоит на конце строки и ждёт ↵ (см. _advance).
var need_enter := false

## Признак «эта строка кончается переносом строки ИСХОДНИКА» (абзац,
## реплика диалога, строка стиха) — там игра ждёт ↵. Обычный перенос
## (строка не влезла в ширину экрана) переезжает сам (автор 13.10.2026).
## Массив параллелен display_lines, при пересборке строк едет вместе с
## ними (см. _reflow_text).
var line_hard: Array[bool] = []
## Склейка строк при пересборке: строка продолжается предыдущую БЕЗ
## пробела (кусок разрезанного посередине слова). Параллелен
## display_lines, едет вместе с ним (см. _reflow_text и B.fit_marked).
var line_glue: Array[bool] = []
var kb_press := ""
var kb_press_t := 0.0
## Оттенок вспышки: верный ввод — зелёный, опечатка — красная
## (автор 10.2026: «нажатие верных клавиш … вспихивало на них зелёным,
## а неправильное — красным»). Пусто — обычная жёлтая вспышка нажатия.
var kb_press_ok := true
## Полная длительность вспышки: затухание не мгновенное, а плавное.
const KB_FLASH_T := 0.55
## Клавиша, которую ДЕРЖАТ пальцем: шифт работает, пока его держат
## (автор 10.2026: «нажимаю — загорается, отпускаю — гаснет»).
var kb_held := ""
## Удержание для автоповтора (как в текстовых редакторах): позиция пальца
## и таймер. live-нажатия ставят, повтор и отпускание снимают.
var kb_held_pos := Vector2.ZERO
var kb_repeat_t := 0.0
## Пауза до повтора и темп повтора — как в редакторах.
const KB_REPEAT_DELAY := 0.45
const KB_REPEAT_RATE := 0.06
const KB_PRESS_T := KB_FLASH_T
var kb_shift := false
var kb_key_sb: StyleBoxFlat
var kb_on_sb: StyleBoxFlat
## Заливка нажатой клавиши: та же краска ночью.
var kb_press_sb: StyleBoxFlat
var kb_press_ok_sb: StyleBoxFlat
var kb_press_err_sb: StyleBoxFlat
var kb_hi_sb: StyleBoxFlat


## Простой, после которого клавиатура сама подсвечивает нужную клавишу
## (вместо текстовой подсказки «Нажми К»). Задержка адаптивная: вдвое
## больше среднего периода нажатий игрока — подсказка приходит в его
## темпе, но опора на неё всё равно проигрывает steady-набору (каждая
## буква стоит две паузы плюс реакция). Опечатка таймер простоя не
## сбрасывает: паузу надо выдержать честно.
var idle_t := 0.0
## Средний период нажатий (EMA, секунды) и момент последнего нажатия.
## По ним считается задержка подсказки.
var press_ema := 1.0
var last_press_t := -1.0
## Рука последней набранной буквы («Л»/«П»): пробел жмётся большим
## пальцем противоположной (классическое правило слепой печати).
var last_hand := ""


## Задержка подсказки: вдвое больше среднего периода нажатий.
func _hint_delay() -> float:
	return clampf(press_ema * 2.0, 0.5, 6.0)


## Отметить нажатие: простой в ноль, период — в среднее.
func _mark_press() -> void:
	_poke_idle()
	if last_press_t >= 0.0:
		var dt := time - last_press_t
		if dt >= 0.0 and dt < 30.0:
			press_ema = clampf(press_ema * 0.8 + dt * 0.2, 0.2, 4.0)
	last_press_t = time


## Просто шевеление (служебный тап, любая клавиша): простой в ноль,
## темп не трогаем — иначе двойной замер на одно нажатие.
func _poke_idle() -> void:
	idle_t = 0.0
## Высота своей клавиатуры в пикселях канваса (0 — скрыта). Только
## раскладка: всё позиционируется от эффективной высоты _eff_h().
var kb_h := 0.0
## Отступ от верха под вырез камеры (капля). Ставит _relayout из
## Ui.top_inset; верхняя группа (бейдж, имя, кнопка, текст) едет вниз.
var top_safe := 0.0
## Системная клавиатура (галка в меню, борьба с автозаменой — comp-буфер):
## показана прямо сейчас, момент запроса, сырая высота в экранных пикселях.
## Живут только при включённой галке.
## Ручной вызов системной тапом по рабочей области (при её галке).
## Пере-поднять системную клавиатуру после старта нового уровня: сессия
## IME рвётся, когда уровень начат нажатием клавиши (Godot съедает её), и
## буквы уходят в никуда, пока игрок не тапнёт по тексту. Живой лог
## 10.2026: LEVEL, затем 2.5 с тишины (только Backspace'ы), TAP — и
## только затем пошли EV. Обратный отсчёт кадров до показа.
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
## Крупные звёзды победы: свой лейбл поверх игровой области (автор
## 15.10.2026: в модалке они лезли на текст). Кегль — от высоты карточки.
var stars_label: Label
var _star_fs := 30
## Звёзды последнего финала (0..3): модалка показывает статистику, а сами
## звёзды живут на поле — счёт нужен и раскладке (_layout_stars).
var _last_stars := 0
## Подсказка звёздочки (1..3, 0 — нет): наведение и тап по звезде
## объясняют, за что она. Сбрасывается новым уровнем.
var _star_tip := 0
## Скролл текста в пикселях: длинные уровни не влезают в карточку —
## окно едет за курсором построчно. Логика (ось _lin) его не видит:
## _line_y зовут только отрисовки.
var scroll_y := 0.0
## Куда едет окно: scroll_y догоняет цель плавно каждый кадр (см.
## _process), а не прыгает построчно — иначе текст дёргается под пальцем
## (автор 15.10.2026: «более плавная прокрутка, причём заранее»).
var scroll_target := 0.0
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
	# Звёзды — поверх карточки с текстом (z выше букв и панелей),
	# по центру игровой области.
	stars_label = Label.new()
	stars_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stars_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	stars_label.visible = false
	stars_label.z_index = 3
	stars_label.add_theme_color_override("font_color", Color("#e8a93d"))
	add_child(stars_label)

	# Оформление — отдельными узлами позади текста (z_index = -15):
	# сами буквы рисует _draw_rows() первым делом в _draw(), а маркер,
	# герои и панели — после, поверх букв. Геометрию панелей считает
	# _layout_card().
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
	# Нажатая клавиша — заметная заливка: попал или промахнулся.
	kb_press_sb = Ui.panel_sb(Color("#ffd98a"), 10.0, Color("#4a4438"), 2.5, false)
	# Верный ввод — зелёным, опечатка — красным (автор 10.2026).
	kb_press_ok_sb = Ui.panel_sb(Color("#8fd66a"), 10.0, Color("#3f6b2c"), 2.5, false)
	kb_press_err_sb = Ui.panel_sb(Color("#ff8a80"), 10.0, Color("#8e2f26"), 2.5, false)
	kb_hi_sb = Ui.panel_sb(Color("#ffd75e"), 10.0, Color("#4a4438"), 2.0, false)
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
		kb_hi_sb.bg_color = Color("#8a6d1f")
		kb_hi_sb.border_color = Color("#ffd75e")
		kb_on_sb.bg_color = Color("#8ab4e0")
		kb_on_sb.border_color = Color("#8b93a8")
		kb_press_sb.bg_color = Color("#6b5a2a")
		kb_press_sb.border_color = Color("#8b93a8")
		kb_press_ok_sb.bg_color = Color("#3f6b3a")
		kb_press_ok_sb.border_color = Color("#9ad08c")
		kb_press_err_sb.bg_color = Color("#7a2f28")
		kb_press_err_sb.border_color = Color("#ff9a90")
		# Ночью буквы светлые, а заяц и ёж — белые спрайты: контур
		# рисует _draw_rows (без него буква на спрайте терялась —
		# видел на эмуляторе).
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
		kb_hi_sb.bg_color = Color("#ffd75e")
		kb_hi_sb.border_color = Color("#4a4438")
		kb_on_sb.bg_color = Color("#a9c6ec")
		kb_press_sb.bg_color = Color("#ffd98a")
		kb_press_sb.border_color = Color("#4a4438")
		kb_press_ok_sb.bg_color = Color("#8fd66a")
		kb_press_ok_sb.border_color = Color("#3f6b2c")
		kb_press_err_sb.bg_color = Color("#ff8a80")
		kb_press_err_sb.border_color = Color("#8e2f26")
		kb_on_sb.border_color = Color("#4a4438")
		# Днём буквы тёмные на светлой карточке — контур не нужен.
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
			Ui.force_touch = true


## Уместить строки уровня в ширину экрана — на ЛЮБОЙ ширине, иначе
## длинная строка вылезает за карточку и её хвоста не видно (жалоба
## автора 13.10.2026). Предложения внутри абзаца склеиваются в сплошной
## текст (как в Word), абзац режется по словам; ждёт ↵ только конец
## абзаца. Сколько знаков влезает — считает _max_chars, проверка — числом,
## а не глазом (см. _text_geometry в logic_test).
func _fit_to_width(frag: Dictionary) -> Dictionary:
	# Headless-тесты и самое начало жизни сцены: вьюпорта ещё нет
	# (64px или нули) — резать не на что, отдаём предложения как есть.
	# Алгоритм покрыт чистыми тестами fit_lines, интеграция тривиальна.
	var raw: Array[String] = []
	for t in frag["texts"] as Array:
		raw.append(String(t))
	if view_w < 100.0:
		var plain: Array[bool] = []
		for f in frag["hard"] as Array:
			plain.append(bool(f))
		var noglue: Array[bool] = []
		for _t in raw:
			noglue.append(false)
		return {"lines": raw, "drops": [] as Array[int], "hard": plain, "glue": noglue}
	var m := B.fit_marked(raw, _max_chars(), frag["hard"] as Array)
	var out: Array[String] = []
	for piece in m["lines"]:
		out.append(String(piece))
	return {"lines": out, "drops": m["drops"], "hard": m["hard"], "glue": m["glue"]}


## Сколько знаков влезает в строку. Один счёт для всех: и разбивки
## при старте уровня, и пересборки при смене ширины экрана.
func _max_chars() -> int:
	return maxi(14, int((view_w - margin * 2.0) / maxf(1.0, char_w)) - 1)


## Высота строки — точным делением комнаты на число строк: стоят ровно
## по карточке, без пустой полосы снизу из-за дискретности (автор
## 14.10.2026: округление вниз оставляло целую строку воздуха).
## Считается ПОСЛЕ пересборки строк (см. _relayout): иначе делилась бы
## комната по старому числу строк. База — две высоты глифа (зазор под
## шар ежа); ужатие ниже 1.8 не даём (ёж впритык к чернилам — непонятно,
## на чьей он строке), растяжку выше 2.4 — тоже (автор 14.10.2026:
## растянутый интерлиньяж «слишком большой»).
func _fit_line_h() -> void:
	var glyph := float(mono.get_height(font_size))
	var nat := glyph * 2.0
	var room := maxf(nat, _text_free_h() - 40.0 * k)
	var want := maxi(1, mini(int(round(room / nat)), maxi(display_lines.size(), 1)))
	# Мера плотности — строка к высоте глифа (2.0 = натурально: зазор под
	# шар ежа равен строке текста). Ниже 1.8 не даём (ёж впритык
	# к чернилам), выше 2.4 — тоже: автор 14.10.2026 назвал растянутый
	# интерлиньяж слишком большим; остаток уходит в поля карточки, а
	# короткий блок центрируется по вертикали.
	line_h = room / float(want)
	var dens := line_h / maxf(1.0, glyph)
	if dens > 2.4:
		line_h = nat
	elif dens < 1.8 and want > 1:
		want -= 1
		line_h = room / float(want)
		if line_h / maxf(1.0, glyph) < 1.8:
			line_h = glyph * 1.8


## Кегль под свободное место (см. _text_free_h) и под САМ текст: текст
## должен занять карточку целиком, без растянутого интерлиньяжа и без
## пустой полосы снизу. Раньше кегль считался на R_MIN_ROWS строк, а
## текст оказывался длиннее — и интерлиньяж растягивался втрое
## (автор 14.10.2026: «слишком большой межстрочный интервал»).
## Считаем от базового 36k: сколько строк текст занимает при нём и
## во сколько раз он уже меньше комнаты. Растёт кегль — растут строки
## (ёмкость строки обратно пропорциональна кеглю), поэтому масштаб берём
## корнем: комната ~ кегль². Один шаг, без итераций и без раскачки.
## Границы: не уже ~15 знаков в строке (иначе буквы толкуются), не
## крупнее 72k и никогда не меньше прежних 36k.
func _text_font(chars: int) -> int:
	var lo := maxi(1, int(36.0 * k))
	var hi := maxi(lo, int(72.0 * k))
	var per_pt := 2.0 * float(mono.get_height(lo)) / float(lo)
	var room := maxf(1.0, _text_free_h() - 40.0 * k)
	var fs := lo
	if chars > 0:
		var per_line := (
			(view_w - margin * 2.0) / maxf(1.0, _marginal_adv(lo)) - 1.0
		)
		var rows := maxf(1.0, ceil(float(chars) / maxf(8.0, per_line)))
		var scale := clampf(
			room / (rows * per_pt * float(lo)), 1.0, 4.0
		)
		fs = int(float(lo) * sqrt(scale))
	return clampi(fs, lo, hi)



## Знаков в текущем тексте: из уже собранных строк (поворот экрана
## меняет кегль, но не число знаков — считать можно по любой раскладке).
func _chars_now() -> int:
	var n := 0
	for l in display_lines:
		n += String(l).length()
	return n



## Предельный advance в строке кеглем fs: целое(64) минус целое(1) на 63.
## Одиночный замер округляет наружу — для шага не годится (см. char_w).
func _marginal_adv(fs: int) -> float:
	var probe: float = mono.get_string_size(
		"н".repeat(64), HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs
	).x
	var one: float = mono.get_string_size("н", HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs).x
	return maxf(1.0, (probe - one) / 63.0)


## Свободная высота под карточку текста: весь экран минус клавиатура,
## сверху шапка (бейдж, имя, меню), снизу полоса снизу целиком — прогресс
## со счётчиком и место под подсказку. Карточка занимает всё остальное,
## без запасов (автор 14.10.2026: запас и в горизонтальной, и в вертикальной).
## Порядок снизу вверх (все от низа карточки, в k): прогресс со счётом
## 14..26, подсказка 36..100, поле 120. Подсказку резервируем ВСЕГДА:
## иначе текст дёргался бы на кадре, когда подсказка появляется.
func _text_free_h() -> float:
	return _eff_h() - 120.0 * k - (80.0 * k + top_safe)


## Ширина экрана может поменяться ПО ХОДУ уровня: на телефоне выезжает
## клавиатура (окно становится ниже и уже), телефон поворачивают. Тогда
## строки, собранные при старте, перестают влезать — текст уезжает за
## правый край, и игрок не видит, что набирать (жалоба автора,
## 07.10.2026: «в мобильной версии не могу закончить уровень»).
## Пересобираем строки и переносим курсор, «пройдено» и красные метки
## по логической оси текста (без пробелов на местах разрыва, см.
## B.reflow): заяц остаётся на той же букве.
func _reflow_text(pe := 0.0, pe_valid := false) -> void:
	if display_lines.is_empty():
		return
	var rf: Dictionary = B.reflow(
		display_lines, cursor_line, cursor_pos, _max_chars(),
		line_drops, line_hard, line_glue
	)
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
	var hard: Array[bool] = []
	for flag in rf["hard"] as Array:
		hard.append(bool(flag))
	line_hard = hard
	var glue: Array[bool] = []
	for flag in rf["glue"] as Array:
		glue.append(bool(flag))
	line_glue = glue
	_refresh_home_chars()
	cursor_line = int(rf["line"])
	cursor_pos = int(rf["pos"])
	_reindex_lines()
	# Ёж едет вместе с текстом: сохраняем его сквозное смещение (вместе
	# с туннелями) и кладём на те же буквы в новой сборке. Экранную
	# позицию _relayout уже пресёк по символам; здесь правим строку.
	if pe_valid and hedge_active and state == "playing":
		_remap_enemy(pe, table)
	# Ремап — по СТАРЫМ drops (они ещё в line_drops), и только потом
	# кладём новые: иначе смещения считаются не в том пространстве.
	_remap_cells(passed, table, rf)
	_remap_cells(errors, table, rf)
	_remap_cells(typed_cells, table, rf)
	line_drops = (rf["drops"] as Array).duplicate()
	# typed_cells едут вместе со всеми: это те же клетки, что passed,
	# только «набранные нажатием». Без переноса они указывают на старые
	# клетки: инвариант «метка внутри набранного» врёт, а Backspace после
	# поворота ищет набранное не там (ловил тестом menu_roundtrip: меню
	# прячет клавиатуру → релэут → рефлоу, и метка оказывалась «вне
	# набранного», хотя её только что поставили).
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
	# Ось — со съеденными пробелами (см. B.line_bases): иначе буква едет
	# по оси при каждой пересборке строк. А длина уровня — в клетках:
	# съеденные пробелы никто не набирает, в прогрессе им не место.
	line_base = B.line_bases(display_lines, line_drops)
	level_total = 0
	for ln in display_lines:
		level_total += String(ln).length()


## Перенести отметки «пройдено»/«ошибка» на те же буквы после пересборки
## строк: ключ «строка:позиция» меняет смысл, буква — нет. Таблица
## переводит логическое смещение старой сборки в клетку новой, и обе
## стороны — в пространстве «все пробелы» (см. B.reflow): старые drops
## берём из line_drops на момент вызова (до замены строк).
## Перенести ежа на то же место текста после пересборки строк.
## pe — сквозное смещение ежа в старой сборке (с туннелями до/после
## строки). Дробная часть (положение между клетками) сохраняется.
func _remap_enemy(pe: float, table: Dictionary) -> void:
	if display_lines.is_empty():
		return
	var rows := display_lines.size()
	if pe < 0.0:
		# Предтуннель первой строки: строка та же, смещение то же.
		enemy_line = 0
		enemy_x = margin + pe * char_w
		return
	var cell := B.cell_for(table, int(floor(pe)), Vector2i(rows, 0))
	var l := clampi(cell.x, 0, rows - 1)
	enemy_line = l
	enemy_x = margin + (pe - float(line_base[l])) * char_w


func _remap_cells(src: Dictionary, table: Dictionary, rf: Dictionary) -> void:
	if src.is_empty():
		return
	var old_lines: Array = rf["old"]
	var old_drops: Array = line_drops.duplicate()
	var out := {}
	for k in src.keys():
		var parts := String(k).split(":")
		if parts.size() != 2:
			continue
		var li := int(parts[0])
		if li >= old_lines.size():
			continue
		var off := int(parts[1])
		if li < old_drops.size():
			off += int(old_drops[li])
		for i in li:
			off += String(old_lines[i]).length()
		# Съеденный пробел — на начало следующей строки (см.
		# B.cell_for): метка переезжает, а не исчезает.
		var c: Vector2i = B.cell_for(table, off, Vector2i(-1, -1))
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
	# Профиль — файл на диске: его правят руками, он может побиться или
	# достаться от другой версии. Значения приводим к допустимым сами —
	# иначе один плохой байт делает игру неиграбельной НАВСЕГДА: ёж при
	# enemy_cps = 1000000 убивает на первом кадре, а значение пишется
	# обратно при каждом конце уровня, и ни одна победа его не починит
	# (проба 10.2026, сценарий «битый профиль»).
	difficulty = clampi(
		int(prof.get("difficulty", 0)), 0, B.KEY_PROGRESSION.length()
	)
	wins_in_row = clampi(int(prof.get("wins_in_row", 0)), 0, B.WINS_TO_LEVEL_UP - 1)
	ema_cpm = clampf(float(prof.get("ema_cpm", 0.0)), 0.0, 10000.0)
	ema_acc = clampf(float(prof.get("ema_acc", 1.0)), 0.0, 1.0)
	enemy_cps = clampf(float(prof.get("enemy_cps", B.BASE_CPS)), B.MIN_CPS, B.MAX_CPS)
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
	play_ui = on
	card_p.visible = on and not display_lines.is_empty()
	hud_label.visible = on
	hud_p.visible = on
	over_p.visible = on and (state == "won" or state == "lost")
	overlay_label.visible = over_p.visible
	# Звёзды — только победа и только с модалкой (см. _layout_stars).
	stars_label.visible = over_p.visible and state == "won"
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
	kb_h = _own_h()
	# Масштаб — от эффективной высоты (экран минус клавиатура): в портрете
	# с выездом клавиатуры остаток альбомный, и вся сцена честно в него
	# вписывается. На узком экране за базу ширины берём 560, а не 1100:
	# иначе k упирается в пол 0.5 и всё мелкое. Метрики букв при этом
	# меняются, поэтому позицию ежа пересчитываем в тех же символах оси
	# (см. _lin): визуально он стоит.
	var old_margin := margin
	var old_cw := char_w
	# Сквозное смещение ежа по оси текста (вместе с туннелями до/после
	# строки): после пересборки строк его клетка едет через таблицу, как
	# курсор и метки, — иначе строка ежа протухает и правило укола
	# считает по чужой строке (ловил _case_relayout).
	var pe_old := 0.0
	var pe_valid := false
	if state == "playing" and hedge_active and enemy_line < line_base.size():
		pe_old = float(line_base[enemy_line]) + (enemy_x - margin) / maxf(old_cw, 0.01)
		pe_valid = true
	var base_w := BASE_W
	if view_h > view_w:
		base_w = 560.0
	k = clampf(minf(view_w / base_w, _eff_h() / BASE_H), 0.5, 2.5)
	# Левое поле широкое: героям нужен воздух в начале строки,
	# а ёж заходит слева из-за края — ему нельзя за край экрана.
	# На узком экране поля жмутся до 8%: иначе съедают пол-экрана.
	margin = 120.0 * k
	if view_w < 700.0:
		margin = view_w * 0.08
	text_y = 80.0 * k + top_safe
	# Крупный текст на свободное место (автор 14.10.2026: текст мелкий,
	# а место пустует — и в горизонтальной, и в вертикальной). Формула
	# — в _text_font, она же считает строки по текущему тексту.
	font_size = _text_font(_chars_now())
	# Шаг клетки — предельный advance в строке, а не одиночный замер:
	# одиночный глиф шейпер округляет наружу (+1 px), и сумма одиночных
	# расходится с целым на ~пиксель/знак с накоплением к концу строки
	# (замерено: 720 против 687 на 60 знаках; жалоба автора 13.10.2026
	# «накопление ошибки в сдвиге курсора»). Все координаты букв — от
	# этого числа: маркер, заяц и отрисовка считают одно и то же.
	char_w = _marginal_adv(font_size)
	if old_cw > 0.0 and char_w > 0.0:
		# Метрики букв поменялись (поворот, системная клавиатура выехала
		# или спряталась, узкое окно) — пересчитываем ОБОИХ героев в тех
		# же символах оси, что и текст. Раньше ёж пересчитывался, а заяц
		# нет: он телепортировался относительно букв, а ёж уезжал один
		# (и на экране проигрыша табло укола разъезжалось — визуальный
		# прогон 10.2026, сценарий «скачок времени»).
		var sx := char_w / old_cw
		if hedge_active:
			enemy_x = margin + (enemy_x - old_margin) * sx
		hero_r.x = margin + (hero_r.x - old_margin) * sx
	# Зазор высотой в строку текста: пустая полоса для качения ежа.
	# Текст при этом никогда не сдвигается.
	sep_h = mono.get_height(font_size)
	# Метрики букв поменялись — строки могут перестать влезать, а на
	# ходу уровня их пересобирает _reflow_text (зайца не сбивает).
	# Интерлиньяж — после неё, по новым строкам: иначе делилась бы
	# комната по старому числу строк.
	_reflow_text(pe_old, pe_valid)
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
	# Видно столько строк, сколько влезает в свободную высоту карточки
	# (та же мера, что растит кегль, — см. _text_free_h): карточка
	# занимает всё место выше клавиатуры без запасов.
	var room := _text_free_h() - 40.0 * k
	# Тот же подсчёт, что в _relayout (там line_h делит комнату нацело):
	# +0.001 против пылинок float (2.9999996 обязан дать 3, а не 2).
	var vis := int(room / maxf(1.0, line_h) + 0.001)
	if kb_h > 0.0:
		return maxi(1, mini(maxi(display_lines.size(), 1), vis))
	return maxi(2, mini(maxi(display_lines.size(), 1), vis))


## Расставить построчные лэйблы. Окно карточки едет за курсором:
## курсор всегда в последней видимой строке, уехавшие прячем.
func _layout_text_lines() -> void:
	# Высота строки — здесь, по актуальным строкам и метрикам (а не в
	# релэуте: там строк ещё нет или они старые).
	_fit_line_h()
	# Блок текста — по центру свободной зоны ЭФФЕКТИВНОЙ высоты: сверху
	# пусто, снизу HUD и подсказка (или клавиатура). Левый край прежний.
	# С открытой клавиатурой — якорь кверху, а не центр: места мало,
	# центрированный блок съезжает вниз на прогресс и подсказку.
	var block_h := float(maxi(display_lines.size(), 1)) * line_h
	if kb_h > 0.0:
		# Короткий текст — по центру свободной высоты, а не с запасом
		# снизу: иначе под карточкой из трёх строк пустота (автор
		# 10.2026). Длинный упирается в верх и едет скроллом, как раньше.
		text_y = 80.0 * k + top_safe + maxf(0.0, (_text_free_h() - block_h) * 0.5)
	else:
		text_y = maxf(40.0 * k, (_eff_h() - 200.0 * k - block_h) * 0.5) + top_safe
	var vis := _vis_lines()
	# Курсор НЕ в последней видимой строке: под ним всегда видна
	# следующая — человек, допечатывая строку, уже видит, что дальше
	# (автор 15.10.2026). На крошечном окне (vis = 1) lookahead некуда
	# деть — тогда курсор всё же последний.
	var first := clampi(
		mini(cursor_line, cursor_line - vis + 2),
		0, maxi(0, display_lines.size() - vis)
	)
	scroll_target = float(first) * line_h
	vis_first = first
	vis_count = vis
	# Модалка победы/поражения — под карточкой, а не поверх букв.
	# Не шире экрана, шрифт под ширину (на телефоне 980px не влезают).
	var ow := minf(980.0 * k, view_w - 32.0 * k)
	var ofs := int(minf(40.0 * k, (view_w - 64.0 * k) / 17.0))
	_over_fs = ofs
	overlay_label.position = Vector2((view_w - ow) * 0.5, text_y + float(vis) * line_h + 24.0 * k)
	# Одна строка статистики: звёзды живут на самом поле, а «Уровень
	# пройден!» убран вовсе (автор 15.10.2026) — двухэтажная модалка
	# больше не нужна, и под ней воздух до клавиатуры.
	overlay_label.size = Vector2(ow, float(ofs) + 36.0 * k)
	overlay_label.add_theme_font_size_override("font_size", ofs)
	# Панель модалки — здесь же, каждый кадр, а не в релэяуте: иначе
	# при скролле лейбл уезжает, а панель (и подсказка звёздочек,
	# которая считается от панели) остаётся и ложится на текст.
	over_p.position = overlay_label.position + Vector2(-24.0 * k, -16.0 * k)
	over_p.size = overlay_label.size + Vector2(48.0 * k, 32.0 * k)
	over_p.visible = overlay_label.visible
	# Буквы рисует _draw_rows по display_lines (каждая в своей клетке
	# pos × char_w): видимость — то же окно, что и скролл.


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
	_layout_stars()


## Крупные звёзды победы — по центру карточки с текстом. Только победа:
## на поражении там ёж с табло, им не мешаем.
func _layout_stars() -> void:
	# Без шрифта молчим (см. _draw): раскладку зовут и до _ready.
	if mono == null or state != "won" or not card_p.visible:
		stars_label.visible = false
		return
	_star_fs = maxi(30, mini(int(120.0 * k), int(card_p.size.y * 0.4)))
	stars_label.add_theme_font_size_override("font_size", _star_fs)
	var t := "★".repeat(_last_stars) + "☆".repeat(3 - _last_stars)
	stars_label.text = t
	var tw := mono.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1.0, _star_fs).x
	var th := float(mono.get_height(_star_fs))
	stars_label.position = card_p.position + (card_p.size - Vector2(tw, th)) * 0.5
	stars_label.size = Vector2(tw, th)
	stars_label.visible = true


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


## Текст уровня — run целых предложений из случайного файла базы
## (встроенные + user://texts). Целостность важнее точного размера:
## начинать с середины предложения и обрывать фразу нельзя
## (автор 10.2026). Вся механика — в Texts.
func _load_text() -> Dictionary:
	return Texts.load_fragment(difficulty, _text_base())


## База текстов: у про-аккаунта взрослая классика, у остальных — детские
## стихи и сказки (автор 10.2026: «не вижу взрослых текстов в своём про
## аккаунте»). Тот же тумблер «Про», что открывает все клавиши.
func _text_base() -> String:
	return "pro" if _all_keys() else "kids"


## Файлы базы для тестов и покрытия.
func _text_files() -> Array[String]:
	return Texts.list_files(_text_base())


func _new_level() -> void:
	var frag := _load_text()
	# Кегль — под САМ этот текст (столько строк, сколько нужно, должны
	# занять карточку): считать надо до переноса, потому что перенос
	# зависит от кегля. Число знаков берём из кусков исходника.
	var n_chars := 0
	for piece in frag["texts"] as Array:
		n_chars += String(piece).length()
	font_size = _text_font(n_chars)
	# Шаг клетки — от нового кегля, до переноса: char_w из _relayout
	# посчитан для прежнего, и строки набились бы шире карточки
	# (ловил logic_test: «row 16 is 638 px wide, card ends at 478»).
	char_w = _marginal_adv(font_size)
	var fit := _fit_to_width(frag)
	var laid: Array[String] = []
	for piece in fit["lines"] as Array:
		laid.append(String(piece))
	display_lines = laid
	line_drops = ((fit["drops"] as Array).duplicate())
	var hard: Array[bool] = []
	for flag in fit["hard"] as Array:
		hard.append(bool(flag))
	line_hard = hard
	var glue: Array[bool] = []
	for flag in fit["glue"] as Array:
		glue.append(bool(flag))
	line_glue = glue
	_refresh_home_chars()
	# Клавиатуру пере-поднимаем: если уровень начат нажатием клавиши,
	# сессия IME рвётся и буквы уходят в никуда (жалоба автора 10.2026:
	# «после смены уровня нажимал правильную букву, реакции не было»).

	# Слой и шифт своей клавиатуры сбрасываем: новый уровень — чистые буквы.
	_set_kb_lang("ru")
	kb_morph_from = ""
	kb_morph = 1.0
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
	cursor_line = 0
	cursor_pos = 0
	need_enter = false
	typed_ok = 0
	typed_bad = 0
	elapsed = 0.0
	_poke_idle()
	last_press_t = -1.0
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
	scroll_target = 0.0
	_skip_inactive()
	shake_t = 0.0
	lunge_t = 0.0
	_refresh()
	# Заяц встаёт ПОСЛЕ раскладки скролла под курсор: _hero_pos считается
	# от scroll_y, а курсор после серого автопропуска глубоко в тексте.
	# Раньше заяц вставал до скролла (на сотни px мимо уровня) и долетал
	# десять кадров — проверки кадра это ловили, а в живой игре было видно
	# подлёт зайца в начале каждого уровня с серым началом.
	hero_r = _hero_pos()


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


## Перенос строки ждёт НАЖАТИЯ ввода: последняя буква строки принята —
## игра стоит, и ↵ переводит на следующую строку (автор 10.2026: «если
## наступил конец строки и на следующую строку надо перейти энтером, то
## надо ожидать от пользователя нажатия этого энтера перед тем как
## реально перейти»). Раньше перенос был автоматическим, и ввод в партии
## не работал вовсе.
func _advance() -> void:
	# Шаг по клеткам. Конец строки бывает двух сортов (автор 13.10.2026):
	# строка не влезла в ширину экрана — обычный перенос, курсор едет сам;
	# в исходнике там перенос строки (абзац, реплика, строка стиха) —
	# игра стоит и ждёт ↵ (автор 10.2026: «если наступил конец строки и на
	# следующую строку надо перейти энтером, то надо ожидать нажатия»).
	while state == "playing":
		cursor_pos += 1
		if cursor_line >= display_lines.size():
			_finish(true)
			return
		if cursor_pos < display_lines[cursor_line].length():
			return
		# Мы за концом строки. Последняя строка текста — уровень кончен,
		# ждать переноса незачем (вводить больше нечего).
		if cursor_line + 1 >= display_lines.size():
			_finish(true)
			return
		if _hard_line(cursor_line):
			# Ввод заблокирован, пока не открыт весь центральный ряд букв
			# этого текста (автор 16.10.2026): серый автопропуск проходит
			# такие переносы сам. Иначе новичок с «а, о, пробел» упирался
			# бы в ↵ на первых же строках — до того, как выучил ряд.
			if not _enter_unlocked():
				cursor_line += 1
				cursor_pos = -1
				need_enter = false
				continue
			need_enter = true
			return
		# Обычный перенос: едем на следующую строку сами. Позиция -1 —
		# чтобы шаг в начале цикла дал ровно 0: первая клетка новой строки
		# не перепрыгивается (иначе потерялась бы клетка с меткой).
		cursor_line += 1
		cursor_pos = -1
		need_enter = false


## Строка заканчивается переносом строки исходника — там нужен ↵.
func _hard_line(i: int) -> bool:
	return i >= 0 and i < line_hard.size() and bool(line_hard[i])


## ↵ на конце строки: переходим на следующую. Из партии и с доски, и с
## физической клавиатуры. Вводит ли текст переносы, никто не знает —
## перенос просто часть строки, поэтому в строке он и набирается.
## Лишний ↵ не в попад: опечатка без метки — переноса здесь нет и клетки
## под него тоже (автор 15.10.2026: «опечатка энтером не работает»).
## Как буква в ожидании переноса: счётчик тикает, заяц шагает назад
## откатом, а клавиша вспыхивает красным (см. вердикт в обоих вводах).
func _wrong_enter() -> void:
	_mark_press()
	typed_bad += 1
	shake_t = SHAKE_T
	_knockback()
	_refresh()


func _enter_next_line() -> bool:
	if not need_enter:
		return false
	need_enter = false
	cursor_line += 1
	cursor_pos = 0
	_skip_inactive()
	_refresh()
	queue_redraw()
	return true


## Серые (неактивные) буквы проходятся сами, ждать их не нужно.
func _skip_inactive() -> void:
	while state == "playing":
		# Стоим на конце строки и ждём ↵ — тут не «конец уровня», а
		# пауза до нажатия. Без этой проверки уровень завершался, минуя
		# ввод, и на доске вместо переноса была модалка победы.
		if need_enter:
			return
		var ch := _current()
		if ch == "":
			_finish(true)
			return
		if _is_active(ch) or errors.has(_key(cursor_line, cursor_pos)):
			return
		passed[_key(cursor_line, cursor_pos)] = true
		_advance()



## Доска следует за раскладкой физической клавиатуры. Следим за
## алфавитом пришедшей буквы, а не за сочетанием клавиш: переключатель у
## человека может быть каким угодно, а буква всегда однозначно говорит,
## что система сейчас отдаёт.
func _follow_keyboard_lang(ch: String) -> void:
	if ch.length() != 1:
		return
	var lo := ch.to_lower()
	var cyr: bool = lo == "ё" or (lo >= "а" and lo <= "я")
	var lat: bool = lo >= "a" and lo <= "z"
	if cyr:
		_set_kb_lang("ru")
	elif lat:
		_set_kb_lang("en")


## Сменить язык ввода доски с перелётом подписей. Смена регистра
## (шифт) перелёт не запускает — там просто меняется крупная буква
## (требование автора 10.2026).
func _set_kb_lang(lang: String) -> void:
	if lang == kb_lang:
		return
	kb_morph_from = kb_lang
	kb_morph_shift = kb_shift
	kb_morph = 0.0
	kb_lang = lang
	queue_redraw()


## Щипок шифта: у знаков — перелёт (старый уходит, новый приходит), у
## букв перелёта нет (автор 10.2026: между большой и малой нет мягкого
## перехода). Проверка на букве живёт в Kbd.draw.
func _set_kb_shift(v: bool) -> void:
	if v == kb_shift:
		return
	kb_morph_from = kb_lang
	kb_morph_shift = kb_shift
	kb_morph = 0.0
	kb_shift = v
	queue_redraw()


## Длительность перелёта, секунды.
const KB_MORPH_T := 0.22

func _unhandled_key_input(event: InputEvent) -> void:
	var ke := event as InputEventKey
	if ke == null:
		return
	if ke.keycode == KEY_SHIFT and not ke.pressed:
		_set_kb_shift(false)
		return
	if ke.echo:
		# Автоповтор зажатой клавиши (как в редакторах): только ввод
		# в партии. Уровни по эху не листаем, шифт не дублируем
		# (автор 10.2026: повтор при долгом залипании, в т.ч. бекспейс).
		if ke.keycode == KEY_SHIFT or state != "playing":
			return
		_poke_idle()
		if ke.keycode == KEY_BACKSPACE or ke.unicode == 8:
			_backspace()
			return
		if ke.unicode < 32:
			return
		var ech := String.chr(ke.unicode)
		var echkey := String(Kbd.combo_for(ech, kb_lang)[0]) if not Kbd.combo_for(ech, kb_lang).is_empty() else ""
		if echkey != "":
			_flash(echkey, _verdict(ech))
		_type_char(ech)
		return
	if not ke.pressed:
		return
	# Раскладку физической клавиатуры мы не угадываем по сочетанию —
	# оно у каждой системы своё (Ctrl+Shift, Alt+Shift, Win+Space, Caps).
	# Следим за СОСТОЯНИЕМ: пришла буква — значит система сейчас отдаёт
	# этот алфавит, и доска обязана показать его же (требование автора
	# 10.2026). Своя экранная клавиатура событий не шлёт, поэтому тап по
	# глобусу состояние не перебивает.
	if ke.unicode > 0:
		_follow_keyboard_lang(String.chr(ke.unicode))
	# Физический шифт — тоже шифт доски: состояние клавиш должно меняться
	# сразу, как его меняет щипок на самой доске (автор 10.2026: «нажатие
	# шифта должно сразу менять состояние клавиш»). Отпускание приходит
	# отдельным событием с pressed = false — его мы уже отсеяли выше.
	if ke.keycode == KEY_SHIFT:
		_set_kb_shift(ke.pressed)
		if not ke.pressed:
			kb_press = ""
			kb_press_t = 0.0
		return
	_poke_idle()
	if ke.keycode == KEY_ESCAPE:
		if menu_open:
			# Открыто меню — ввод его: сюда попадаем, только если меню
			# клавишу не забрало (страховка). Там Esc — выход.
			return
		# Esc уводит из кона в меню, а не гасит игру (автор 10.2026:
		# «выходить не из игры полностью, а из кона в меню»).
		# Полный выход — повторным Esc уже в меню.
		_open_menu()
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
	# Ввод один и тот же для любой клавиатуры: Backspace — стирание,
	# управляющие символы — мимо, всё остальное — буква в игру.
	# Сложной машины с composing-буфером, автозаменой и фильтром дублей
	# больше нет: своей экранной клавиатуре IME не нужен, а с системной
	# мы расстались (решение 10.2026, жалобы на сбитый курсор и подсказку
	# «Стереть», которая ничего не стирала).
	if ke.keycode == KEY_BACKSPACE or ke.unicode == 8:
		_backspace()
		return
	# ↵ с физической клавиатуры — тот же перенос строки, что и с доски
	# (автор 10.2026: «ты не вернул использование энтера»). Не в попад —
	# обычная опечатка без метки (см. _wrong_enter), а не тишина.
	if (
		(ke.keycode == KEY_ENTER or ke.keycode == KEY_KP_ENTER)
		and state == "playing"
	):
		_flash("ввод", "ok" if need_enter else "err")
		if need_enter:
			_enter_next_line()
		else:
			_wrong_enter()
		return
	if ke.unicode < 32:
		return
	if _exact():
		_caps_check(ke)
	var typed2 := String.chr(ke.unicode)
	# Та же клавиша на доске вспыхивает: человек видит, куда попал
	# физический ввод (автор 10.2026: «нажатие верных клавиш на
	# клавиатуре или мышью вспихивало на них зелёным»).
	var kbkey := String(Kbd.combo_for(typed2, kb_lang)[0]) if not Kbd.combo_for(typed2, kb_lang).is_empty() else ""
	if kbkey != "":
		_flash(kbkey, _verdict(typed2))
	_type_char(typed2)


## CapsLock-детект для строгого режима («все клавиши»): движок отдаёт
## готовую букву в unicode, а keycode — физическая клавиша, отдельного
## API состояния CapsLock в 4.3 нет. Буква заглавная без шифта (или
## строчная с шифтом) — значит, lock включён: поднимаем предупреждение
## в подсказке. Не-буквы (цифры, знаки) пропускаем: у них верхний
## и нижний регистр совпадают, судить не о чем.
func _caps_check(ke: InputEventKey) -> void:
	if ke.unicode < 32:
		return
	var ch := String.chr(ke.unicode)
	if ch.to_lower() == ch.to_upper():
		return  # не буква — судить не о чем
	if (ch == ch.to_upper()) != ke.shift_pressed:
		_caps_warn = true


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
		if errors.has(k):
			return Vector2i(l, p)
		if (
			typed_cells.has(k)
			and p >= 0
			and p < display_lines[l].length()
			and _is_active(display_lines[l].substr(p, 1))
		):
			return Vector2i(l, p)
	return Vector2i(-1, -1)


## Вернуть снятое серией DEL: снимаем их из undo-стека обратно.
## Клетки, набранные нажатием (не серые автопропуски). Нужны откату
## Backspace: он отменяет последнюю НАБРАННУЮ букву, а не последнюю
## пройденную клетку (серые символы проскочила сама игра).
var typed_cells: Dictionary = {}


func _type_char(ch: String) -> void:
	if state != "playing":
		return  # уровень окончен: ввод ниже не считается
	if need_enter:
		# Стоим на конце строки и ждём ↵, а жмут букву — это ошибка, и
		# она засчитывается: счётчик тикает, заяц шагает назад, как при
		# любой опечатке (автор 10.2026: «в ожидании энтера можно
		# совершать любые ошибки и они не засчитываются»). Метку ставить
		# не на что — курсор уже за текстом, тут нет клетки; наказанием
		# работает сам откат: перенос отменяется, букву надо набирать
		# заново.
		_mark_press()
		typed_bad += 1
		shake_t = SHAKE_T
		_knockback()
		_refresh()
		return
	_mark_press()
	last_hand = Kbd.hand_of(ch)
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
		# Опечатка: красная метка на месте курсора и шаг назад ровно на
		# ОДИН символ — моноширинная сетка, шаг должен быть точным
		# (автор 10.2026: «вроде у нас моноширинный текст и можно всегда
		# отступать на 1 символ ровно»). Каждая следующая неверная
		# клавиша отбрасывает ещё на символ: метки копятся назад
		# сплошной стопкой, Backspace снимает их по одной. Заглушка
		# diag21 («в пачке без отката») ломала это на всём телефонном
		# вводе: метки затирали друг друга на месте, курсор стоял,
		# снимать было нечего.
		errors[_key(cursor_line, cursor_pos)] = ch
		typed_cells[_key(cursor_line, cursor_pos)] = true
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


## Шаг назад: cumulative — каждая опечатка отбрасывает ещё на ОДИН
## символ, через переносы строк (упор в начало текста). Единица шага —
## глиф: текст моноширинный, и «назад на символ» видно точно.
func _knockback() -> void:
	# Откат назад отменяет ожидание переноса: курсор ушёл с конца строки.
	if need_enter:
		need_enter = false
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
	if need_enter:
		# Стояли на конце строки. Стерли последнюю букву — перенос ждать
		# уже нечего: строка не кончилась, и лишний ↵ уводил бы дальше
		# мимо набранного (автор 10.2026: ждать надо ровно того, что
		# пользователь ещё не сделал). Курсор встаёт НА стёртую клетку
		# (а не висит за концом строки без ожидания — так ловил инвариант
		# «курсор всегда на букве»), клетка возвращается целиком, как при
		# обычном откате; счётчики не трогаем (нажатия были).
		need_enter = false
		if cursor_line >= display_lines.size():
			# Пересборка строк выкинула курсор за текст (редкий стык
			# ожидания и поворота): ждать нечего, уровень доиграется сам.
			_mark_press()
			_refresh()
			return
		cursor_pos = maxi(0, display_lines[cursor_line].length() - 1)
		var bk := _key(cursor_line, cursor_pos)
		passed.erase(bk)
		errors.erase(bk)
		typed_cells.erase(bk)
		_mark_press()
		_refresh()
		return
	_mark_press()
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
	var b := _last_filled_behind()
	if b.x < 0:
		return  # за курсором нет ничего набранного
	cursor_line = b.x
	cursor_pos = b.y
	var bk := _key(cursor_line, cursor_pos)
	var had := passed.has(bk) or errors.has(bk)
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
	# Уровень кончен — ждать переноса больше нечего.
	need_enter = false
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
	_last_stars = stars if won else 0
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
		overlay_label.text = "%s · %s" % [
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


## Потолок кадра для геймплея. Телефон умеет подвисать: уход в фон,
## звонок, тяжёлый кадр — после такого движок отдаёт дельту в секунды, и
## за ОДИН кадр ёж проезжает десятки символов. Ребёнок возвращается к
## «Ёж догнал!», хотя не нажимал ничего (проба 10.2026: dt=0.5, 2 и 8
## секунд — мгновенный проигрыш). Поэтому игровое время живёт по
## ограниченной дельте: худший случай — обычный медленный кадр в 10 fps.
const MAX_FRAME_DT := 0.1



## Своя экранная клавиатура: единственный ввод на телефоне и живая
## подсказка на десктопе (вместо текстовых «Нажми К»: нужная клавиша
## подсвечивается после простоя). Видна в партии; скрыта под открытым
## меню и на модалке победы/поражения — там ввод не нужен.
func _own_shown() -> bool:
	if menu_open:
		return false
	return true



## Область своей клавиатуры: низ экрана, высота от ширины (кнопки —
## почти квадраты, см. height_for). От view_h не зависит: разрываем цикл
## с раскладкой (высота входит в eff_h).
##
## НО высоты экрана не хватает: в альбомной ориентации клавиши по ширине
## выходят ВЫШЕ экрана (2340x1080 → 1128 px клавиатуры при 1080 высоты),
## раскладка схлопывалась в полоску у верхнего края, текст оставался
## огрызком, а нижние клавиши уезжали за экран (визуальный прогон
## 10.2026, кадры «landscape»). Поэтому клавиатура ограничена долей
## экрана, а лишнее убирается ШИРИНОЙ: клавиши остаются квадратными и
## полоса встаёт по центру, а не прилипает к краю.
func _own_rect() -> Rect2:
	# Низ экрана со скруглениями и жестом: клавиатуру поднимаем на
	# безопасный отступ, иначе угловые клавиши обрезаны (жалоба 10.2026).
	var m := 16.0 + Ui.bottom_inset(view_h)
	var max_h: float = maxf(160.0, (view_h - m) * 0.46)
	var w := view_w - 32.0
	var h := Kbd.height_for(w)
	if h > max_h:
		# Обратная задача height_for: ширина, дающая ровно max_h.
		# Обратная задача внутри Kbd: ширина по той же формуле, что
		# height_for, иначе прыгает на ширину самого широкого ряда.
		w = clampf(Kbd.width_for(max_h), 240.0, view_w - 32.0)
		h = minf(Kbd.height_for(w), max_h)
	return Rect2((view_w - w) * 0.5, view_h - h - m, w, h)



## Высота своей клавиатуры в пикселях канваса (0 — скрыта). Ставится
## в _relayout: раскладка едет от неё через _eff_h, как раньше от системной.
func _own_h() -> float:
	if not _own_shown():
		return 0.0
	return _own_rect().size.y



## Эффективная высота экрана: низ, занятый клавиатурой, не наш.
## Вся раскладка считается от неё. Пол под ногами не проваливается:
## минимум 220 px.
func _eff_h() -> float:
	return Ui.eff_h(view_h, kb_h)


func _process(dt: float) -> void:
	dt = minf(dt, MAX_FRAME_DT)
	time += dt
	idle_t += dt
	# Перелёт подписей после смены языка ввода: короткий, чтобы не
	# тянуть игру.
	if kb_morph < 1.0:
		kb_morph = minf(1.0, kb_morph + dt / KB_MORPH_T)
		queue_redraw()
	if kb_held != "" and _repeatable(kb_held):
		if not _own_shown():
			kb_held = ""
			kb_repeat_t = 0.0
		else:
			kb_repeat_t -= dt
			while kb_repeat_t <= 0.0:
				kb_repeat_t += KB_REPEAT_RATE
				if _own_shown():
					_own_press(kb_held_pos, true)
	if kb_press_t > 0.0:
		kb_press_t = maxf(0.0, kb_press_t - dt)
		queue_redraw()
	elif kb_press != "":
		# Таймер дошёл до нуля, а заливка осталась нарисованной: без
		# этого кадра следующий не перерисуется, и клавиша «залипнет»
		# (жалоба автора 10.2026: «выделение остаётся даже после
		# отпускания»). Гасим подсветку последним кадром.
		kb_press = ""
		kb_press_t = 0.0
		queue_redraw()
	# Высота раскладки — всегда своя клавиатура: система больше не
	# участвует, замеров и подстройки нет, раскладка не прыгает сама.
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
					# Одна строка: заяц ровно на дистанцию контакта.
					_settle_contact(cursor_line)
				else:
					# Откат через угол строк: табло укола показываем
					# честное — заяц СТРОГО на строке ежа, шары в касании.
					_settle_contact(enemy_line)
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
	# Плавный скролл: окно догоняет цель быстрее зайца (12/с), чтобы
	# герои не отрывались от букв, но медленнее мгновенного прыжка —
	# текст едет, а не дёргается. Порог 0.5px: ближе — стоим ровно.
	# Вне партии окно замирает вместе с табло: иначе после укола скролл
	# уезжал бы из-под застывших героев (ловил chase_test: заяц «не на
	# строке ежа» на втором кадре табло).
	if state == "playing" and scroll_y != scroll_target:
		scroll_y = lerpf(scroll_y, scroll_target, clampf(dt * 18.0, 0.0, 1.0))
		if absf(scroll_y - scroll_target) < 0.5:
			scroll_y = scroll_target
	var hero_prev := hero_r
	if state != "lost":
		hero_r = hero_r.lerp(_hero_pos(), clampf(dt * 12.0, 0.0, 1.0))
		var moved := (hero_r - hero_prev).length() / maxf(k, 0.01)
		if moved > 0.02:
			hop_ph += moved / 16.0 * PI
		else:
			# Дотягиваем до кратного π и СТАНОВИМСЯ ровно: асимптотический
			# lerp без снэпа зависал на ht→1⁻, а там присед 0.45 — заяц
			# останавливался сплюснутым (автор 15.10.2026). Та же болезнь,
			# что у скролла (добег 0.5px).
			var hop_to := roundf(hop_ph / PI) * PI
			hop_ph = lerpf(hop_ph, hop_to, clampf(dt * 10.0, 0.0, 1.0))
			if absf(hop_ph - hop_to) < 0.02:
				hop_ph = hop_to
		# Фаза живёт весь прогон и уходит в тысячи радиан — там шаг lerp
		# округляется во float32 в ноль и дотягивание встаёт (ловил
		# combo: ht завис на 1.0000 после полутора тысяч кадров хаоса).
		# Дальше фазы всё равно никто не читает, кроме fmod(…, π).
		hop_ph = fmod(hop_ph, TAU)
	queue_redraw()
	_refresh_hud()


## Все буквы — одно начертание и кегль. Состояние только оттенком:
## активная — чернила, будущая — средний серый, пройденная — светлый.
## Знак, нарисованный в клетке: обычно буква строки, а на красной
## метке — нажатая буква (ошибочный пробел виден как ␣). Тот же выбор,
## что рисует _draw_rows; тесты сверяют по нему без чтения пикселей.
func _shown_char(l: int, p: int) -> String:
	var line := String(display_lines[l])
	var ch := line.substr(p, 1)
	var kk := _key(l, p)
	if errors.has(kk):
		# Затирание, а не вставка: красная нажатая буква ВМЕСТО буквы в
		# клетке. Красные копятся назад по ходу отката.
		var shown: String = errors[kk]
		if shown == " ":
			return "␣"
		return shown
	return ch


## Цвет знака в клетке для отрисовки (тот же, что смотрит тест).
func _shown_color(l: int, p: int) -> Color:
	var line := String(display_lines[l])
	var ch := line.substr(p, 1)
	var kk := _key(l, p)
	if errors.has(kk):
		var ecol := Ui.ERR_NIGHT_HEX if night else Ui.ERR_DAY_HEX
		if hints.has(kk):
			ecol = Ui.HINT_NIGHT_HEX if night else Ui.HINT_DAY_HEX
		return Color(ecol)
	return Color(_cell_color(l, p, ch, kk))


## Видна ли строка в окне скролла (тот же порог, что у отрисовки).
func _row_visible(i: int) -> bool:
	return i < display_lines.size() and i >= vis_first and i < vis_first + vis_count


func _refresh() -> void:
	# Снимок показанного: рисование идёт следующим кадром из тех же
	# display_lines, так что экран и модель — одно и то же (раньше тут
	# жили построчные RichText-лейблы со своим шейпингом — второй путь
	# измерения координат, дававший накопление ошибки к концу строки).
	shown_rows.clear()
	for line in display_lines:
		shown_rows.append(String(line))
	# Окно скролла — сразу здесь же, тем же проходом: иначе между
	# _refresh и _layout_text_lines кадр показывает старые строки на
	# новых местах (жалоба автора 10.2026 про «старое не стирается»).
	_layout_text_lines()
	# Карточка и звёзды — тоже здесь: иначе после _finish они показывают
	# прошлый уровень (ловил тест: текст «★★★» при счёте на две).
	_layout_card()
	queue_redraw()


## Цвет буквы в клетке. Отдельной функцией, а не инлайном: на этом цвете
## держится всё, что ребёнок видит про свои клетки, и он проверяется
## тестом (см. marks_test).
##
## Клетка, в которой стоит заяц, рисуется как буква, которую игра ЖДЁТ —
## и когда она серая. Рамка под текущей клеткой (_draw_cursor_marker) была
## всегда, но сама буква рисовалась тем же тусклым цветом, что и
## автопропущенная. Заяц после отката за ошибку встаёт на символ назад по
## сквозной оси, в том числе на серый символ, и игра там ждёт нажатия:
## без разницы в цвете ребёнок читал это как «эта буква не считается», а
## по факту игра требовала именно её (жалоба автора 10.2026: снимать
## метки приходилось, напечатав серые «л» и «е», которых он не нажимал).
func _cell_color(l: int, p: int, ch: String, kk: String) -> String:
	if hints.has(kk):
		# Вспышка: видно, что нажатие принято (буква не изменилась).
		return Ui.HINT_DAY_HEX if not night else Ui.HINT_NIGHT_HEX
	if l == cursor_line and p == cursor_pos:
		return "#1c1a16" if not night else "#f2ede0"
	var col := "#6f6a5e" if not night else "#7a86a0"
	if passed.has(kk):
		# Съеденное серым, но ночное #4a5468 давало 1.9:1 к карточке —
		# буквы пропадали, строка шла дырами.
		col = "#b3a996" if not night else "#6f7b99"
	elif _is_active(ch):
		col = "#1c1a16" if not night else "#f2ede0"
	return col


## Подсказка следующей клавиши частями: обычный текст (cap=false)
## и «кнопки» (cap=true) — буква в скруглённой рамке, пробел — словом
## «Пробел», заглавная в строгом режиме — парой Shift + буква.
## Пустой список — подсказку прятать.
## Латиница ли буква (для варнинга о чужом слое клавиатуры).
static func _is_latin(ch: String) -> bool:
	return (ch >= "A" and ch <= "Z") or (ch >= "a" and ch <= "z")


## Диагностика для разбора на телефоне (F3): сколько меток, где курсор
## и что игра ждёт.
func _marks_debug() -> String:
	var far := 0
	for k in errors.keys():
		var parts := String(k).split(":")
		var ax := _lin(int(parts[0]), float(parts[1]))
		if ax < _lin(cursor_line, float(cursor_pos)) - 0.001:
			far += 1
	return "меток %d (позади %d) курсор %d:%d ждёт %s" % [
		errors.size(),
		far,
		cursor_line,
		cursor_pos,
		_current(),
	]


func _hint_parts() -> Array:
	# Текстов финала нет: исход виден и так (табло со звёздами/ежом),
	# а звёзды лезли на текст (автор 15.10.2026). Подсветку ↵ на доске
	# держит _hint_keys — ей текст не нужен.
	if state == "won":
		return []
	if state == "lost":
		return []
	if state != "playing":
		return []
	if _caps_warn and _exact():
		return [{"s": "Выключи CapsLock!", "cap": false}]
	# Текста «Стереть» нет: метки зовут клавишу «←» на самой доске
	# (см. _hint_keys). Решение 10.2026: подсказки живут на клавиатуре.
	if not errors.is_empty():
		return []
	var cur := _current()
	if cur == "":
		return []
	# Чужая раскладка и знаки со сдвигом зовут клавиши на самой доске
	# (см. _hint_keys): текстовых «Жми» больше нет (автор 10.2026).
	return []


## Та же подсказка одной строкой: для тестов и дебага. Кнопки — в [].
func _hint_text() -> String:
	var out: Array = []
	for p in _hint_parts():
		var s := String(p["s"])
		out.append(("[" + s + "]") if bool(p["cap"]) else s)
	return " ".join(out)


## Центр i-й звёздочки (0..2): строка центрирована в своём лейбле
## поверх карточки, шаг — advance глифа (моноширинный шрифт).
func _star_center(i: int) -> Vector2:
	var pitch := mono.get_string_size(
		"★", HORIZONTAL_ALIGNMENT_LEFT, -1.0, _star_fs
	).x
	return Vector2(
		stars_label.position.x + stars_label.size.x * 0.5 + (float(i) - 1.0) * pitch,
		stars_label.position.y + stars_label.size.y * 0.5
	)


## Какая звезда под точкой (1..3, 0 — мимо). Маппинг относительный
## (ближайший центр), а не прямоугольниками: абсолютные размеры
## плывут от кегля, а центры всегда на своих местах. Палец прощает
## полшага в стороны.
func _star_at(pos: Vector2) -> int:
	if state != "won" or not stars_label.visible:
		return 0
	var top := stars_label.position.y
	if pos.y < top or pos.y > top + stars_label.size.y:
		return 0
	var pitch := mono.get_string_size(
		"★", HORIZONTAL_ALIGNMENT_LEFT, -1.0, _star_fs
	).x
	if pitch <= 0.0:
		return 0
	var cx := stars_label.position.x + stars_label.size.x * 0.5
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
## Верх панели подсказки: зарезервированная полоса под карточкой (см.
## _text_free_h), но не ниже границы эффективной высоты. Отдельная
## функция, а не строчка в _draw: в headless картинку никто не рисует,
## а проверять эту геометрию надо числами (logic_test, _geo_fill).
func _hint_top() -> float:
	var panel_h := 48.0 * k + 16.0 * k
	var y_top := card_p.position.y + card_p.size.y + 44.0 * k
	y_top = minf(y_top, _eff_h() - panel_h - 8.0 * k)
	var lowest := 8.0 * k + top_safe
	if y_top < lowest:
		# Текст заезжает под клавиатуру, но подсказка — нет: она уходит на
		# дно доступной зоны целиком.
		y_top = maxf(lowest, _eff_h() - panel_h - 8.0 * k)
		if y_top + panel_h > _eff_h():
			y_top = maxf(lowest, _eff_h() - panel_h)
	return y_top


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
	# Панель — под прогрессом и счётчиком, в зарезервированной под неё
	# полосе (см. _text_free_h: 78..142 от низа карточки). Ниже клавиатуры
	# ей нельзя (жалоба автора 10.2026: «закрывается»). При очень большой
	# клавиатуре (k/экран маленькие) _eff_h упирается в EFF_MIN_H — тогда
	# подсказка обязана уехать на самый низ ДО границы, а не под неё.
	var panel_h := cap_h + 16.0 * k
	var y_top := _hint_top()
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
	var sc := Ui.dpr()
	var txt := "[dbg ex=%.0f eln=%d cur=%d:%d cw=%.1f k=%.2f ok=%d bad=%d kb=%.0f sc=%.2f vw=%.0f vh=%.0f] %s" % [
		enemy_x, enemy_line, cursor_line, cursor_pos, char_w, k, typed_ok, typed_bad,
		kb_h, sc, view_w, view_h, _marks_debug(),
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
## Табло укола: заяц ровно в касании с ежом, всегда. Капов больше нет:
## частичное подтягивание оставляло зазор между шарами при засчитанном
## уколе — «заяц останавливается сильно до, а игре уже конец» (жалоба
## автора 10.2026). И «щель на пару ежей» (та же жалоба раньше), и
## «не долетает» — одна болезнь: любое отклонение от касания. Рывок
## на кадре укола читается как удар, а не телепорт: дальше модалка.
func _settle_contact(row: int) -> void:
	hero_r.x = enemy_x + _hedge_half()
	hero_r.y = _track_cy(row)
	hop_ph = roundf(hop_ph / PI) * PI


## Левая граница клетки: ЕДИНСТВЕННАЯ формула координат (маркер, заяц,
## отрисовка букв — все отсюда). Шаг — char_w (предельный advance, см.
## _relayout): никаких замеров префиксов целой строкой — целый замер
## округляется иначе, чем сумма клеток, и даёт накопление к концу строки.
func _cell_x(p: int) -> float:
	return margin + float(p) * char_w


## Экранный центр глифа под курсором: клетка курсора, других способов
## узнать «где буква» нет (см. _cell_x).
func _cursor_cx() -> float:
	if cursor_line >= display_lines.size():
		return margin
	return _cell_x(cursor_pos) + char_w * 0.5


func _hero_pos() -> Vector2:
	var bounce := 0.0
	if bounce_t > 0.0:
		bounce = -18.0 * k * bounce_t
	# Заяц стоит ПЕРЕД буквой, спрайт центрируется на левом краю её
	# клетки: буква остаётся читаемой, заяц заходит на пол-шара в клетку.
	var half := HERO_TEX.get_width() * 0.5 * _spr_scale(HERO_TEX, _unit_h()).x
	# Курсор после победы уходит за конец текста (cursor_line == размеру
	# строк). Тогда _cursor_cx() отдаёт margin, и заяц уезжал влево от
	# строки и на пол-экрана вниз — прямо на полосу прогресса
	# (визуальный прогон 10.2026, кадр «11-win»). На экране победы он
	# стоит там, где закончил: последняя строка, сразу за её концом.
	var rows: int = display_lines.size()
	if cursor_line >= rows and rows > 0:
		var end_x: float = margin + float(String(display_lines[rows - 1]).length()) * char_w
		return Vector2(end_x + half, _track_cy(rows - 1) + bounce)
	var row: int = clampi(cursor_line, 0, maxi(0, rows - 1))
	return Vector2(_cursor_cx() - char_w * 0.5 - half, _track_cy(row) + bounce)


func _draw() -> void:
	# Пока открыто меню игроков, геймплей стоит (см. _process), но
	# картинка остаётся нарисованной: вернувшись по F2, игрок видит
	# ту же позицию зайца и ежа, на которой свернул.
	# Исключение — текст, табло, подсказка и сами герои: сквозь вуаль
	# меню они налезали на его подписи («Кто играет?» поверх «Сом уснул
	# на», ночью особенно). Фон-небо остаётся: видно, что это пауза.
	_draw_rows()
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
## Подписи клавиш, которые подсветить после простоя. Пусто — рано
## (игрок ещё думает сам), либо подсказывать нечего: капслок гасится
## текстом, уровень кончился. Метки зовут клавишу «стереть» на самой
## доске. Заглавная в строгом режиме — парой [Shift, буква]; знак не со
## слоя — парой [Shift, цифра]; долгое нажатие — базовой клавишей (жест
## объясняет текст).
## Подписи клавиш, которые подсветить после простоя. Шифт выбирается
## по правилу противоположной руки (буква левой — правый шифт и наоборот,
## подтверждено методикой слепой печати), пробел — большим пальцем руки,
## противоположной от последней буквы (если истории нет — правым).
## На финале после простоя подсвечивается ввод.
func _hint_keys() -> Array:
	if idle_t < _hint_delay():
		return []
	if _caps_warn and _exact():
		return []
	if state == "won" or state == "lost":
		return ["↵"]
	if state != "playing":
		return []
	# Стоим на конце строки: игра ждёт нажатия ↵ — подсвечиваем его
	# (автор 10.2026: «надо ожидать нажатия этого энтера»). Подсветка
	# ждёт ПОДПИСЬ клавиши («↵»), а не действие («ввод»): сравнение идёт
	# по подписи в Kbd.draw.
	if need_enter:
		return ["↵"]
	# Опечатка: жать надо «стереть» — подсвечиваем клавишу, а не текст.
	if not errors.is_empty():
		return ["←"]
	var cur := _current()
	if cur == "":
		return []
	if cur == " ":
		return ["пробел:Л" if last_hand == "П" else "пробел:П"]
	return _keys_for(cur)


## Какие клавиши подсветить для знака. Единый путь на все легенды доски
## (Kbd.combo_for): у букв это сама клавиша, у заглавных — шифт с ней,
## у знаков — та клавиша и тот шифт, где знак живёт (точка — шифт с «ю»,
## запятая — ключ слева от шифта, «?» — Shift+7), а если знак достаётся
## только чужой раскладкой — сперва глобус.
func _keys_for(sym: String) -> Array:
	var combo := Kbd.combo_for(sym, kb_lang)
	if combo.is_empty():
		return []
	if String(combo[2]) != kb_lang:
		# Глобус плюс сама клавиша: после переключения та же доска
		# подсветит уже только клавишу, путь не рвётся.
		return ["глобус", String(combo[0])]
	if bool(combo[1]):
		return [_opp_shift(String(combo[0])), String(combo[0])]
	return [String(combo[0])]


## Шифт противоположной руки от клавиши: буква/цифра левой зоны — правый
## шифт, правой — левый.
func _opp_shift(s: String) -> String:
	return "ShiftR" if Kbd.hand_of(s) == "Л" else "Shift"


func _draw_own_kb() -> void:
	if not _own_shown():
		return
	# Пульсация подсветки — цветом стиля: 0.45..0.8 мажорного жёлтого.
	var pulse := 0.5 + 0.5 * sin(time * 5.0)
	var hi := _hint_keys()
	if not hi.is_empty():
		var c: Color = kb_hi_sb.bg_color
		c.a = 0.45 + 0.35 * pulse
		kb_hi_sb.bg_color = c
	Kbd.draw(
		self, _own_rect(), kb_lang, kb_shift, _kb_enter_shown(), mono,
		int(30.0 * k), kb_key_sb, kb_on_sb, _ui_ink(), hi, kb_hi_sb, _ui_dim(),
		kb_morph, kb_morph_from, kb_morph_shift, _press_sb(), kb_press
	)


## Нажатие на свою клавишу: символ — в _type_char, стереть — в _backspace,
## слой — дальше по кругу, шифт — флип. Напрямую, без key-событий: IME тут
## не участвует вообще, composing-переписям неоткуда взяться.
## Повторяется ли клавиша при удержании: буквы, знаки, пробел и
## стереть — да; шифт (модификатор), глобус (тумблер) и ввод — нет
## (автор 10.2026: «как в любом текстовом редакторе»).
func _repeatable(act: String) -> bool:
	return act != "" and act != "шифт" and act != "язык" and act != "ввод"


## Отпускание удерживаемой клавиши (шифта). Гасит и вспышку: палец
## ушёл — подсветка ушла.
func _release_held() -> void:
	if kb_held == "":
		return
	var was := kb_held
	kb_held = ""
	kb_repeat_t = 0.0
	if was == "шифт":
		_set_kb_shift(false)
	if kb_press == was:
		kb_press = ""
		kb_press_t = 0.0
	queue_redraw()


## Вспышка нажатой клавиши: человек должен видеть, что попал именно в неё
## (а если промахнулся — что не попал ни в одну). Гасится сама.
## verdict: "ok" — верный ввод (зелёный), "err" — опечатка (красный),
## "" — обычная вспышка нажатия.
func _flash(key: String, verdict := "") -> void:
	kb_press = key
	kb_press_ok = verdict != "err"
	kb_press_t = KB_PRESS_T
	queue_redraw()


## Вердикт ввода для вспышки: «ok» — верно, «err» — опечатка. Тот же
## сравниватель, что у ввода (_eq), чтобы цвет совпадал с меткой.
func _verdict(typed: String) -> String:
	if state != "playing":
		return ""
	if need_enter:
		# Ждём ↵ — любая буква тут ошибка (см. _type_char).
		return "err"
	var expected := _current()
	if expected == "":
		return ""
	return "ok" if _eq(typed, expected) else "err"


## Заливка вспышки с учётом вердикта и оставшегося времени: затухание
## плавное, последние кадры почти прозрачны (автор 10.2026: «затухание
## не мгновенным»). Панели ДВА и создаются раз за жизнь: раньше здесь
## каждый кадр рождался новый StyleBoxFlat (ревизия 16.10.2026).
var _press_sb_fade_ok: StyleBoxFlat
var _press_sb_fade_err: StyleBoxFlat


func _press_sb() -> StyleBox:
	if _press_sb_fade_ok == null:
		_press_sb_fade_ok = Ui.panel_sb(Color(1, 1, 1, 0), 10.0, Color("#4a4438"), 2.5, false)
		_press_sb_fade_err = Ui.panel_sb(Color(1, 1, 1, 0), 10.0, Color("#4a4438"), 2.5, false)
	var src: StyleBoxFlat = kb_press_ok_sb if kb_press_ok else kb_press_err_sb
	var dst: StyleBoxFlat = _press_sb_fade_ok if kb_press_ok else _press_sb_fade_err
	var k: float = clampf(kb_press_t / KB_FLASH_T, 0.0, 1.0)
	var c := src.bg_color
	c.a *= k
	var b := src.border_color
	b.a *= k
	dst.bg_color = c
	dst.border_color = b
	return dst


## Показывает ли доска ввод ↵. Пока часть букв текста ещё серая
## (проходится сама), ввода на доске нет — и вводить нечего. Когда
## открылись все буквы уровня (или он пройден), снизу появляется ↵,
## как на настоящей клавиатуре (автор 10.2026: «к полной разблокировке
## всех клавиш эта клавиша точно должна быть»).
func _kb_enter_shown() -> bool:
	if state == "won" or state == "lost":
		return true
	if display_lines.is_empty():
		return false
	# Стоим на конце строки и ждём нажатия — ↵ обязан быть на доске.
	if need_enter:
		return true
	# Режим «все клавиши»: буквы открыты сразу, центральный ряд открыт
	# по определению, и ввод там падавно (автор 10.2026: «а в ПРО режиме
	# он и падавно должен быть»).
	if _all_keys():
		return true
	# Ввод ждёт только центрального ряда — дом и верхний ряд текста он
	# не касается (автор 10.2026: «разблокировал бы клавишу энтер после
	# того, как разблокирован весь центральный ряд букв, а не в самом
	# конце»).
	return _enter_unlocked()


## Ввод ↵ разблокирован: весь центральный ряд ЭТОГО текста уже открыт
## (или режим «все клавиши»). Та же проверка сторожит и ожидание переноса
## в _advance: заблокированный перенос серый автопропуск проходит сам.
func _enter_unlocked() -> bool:
	if _all_keys():
		return true
	for want in home_chars:
		if not _is_active(want):
			return false
	return true


## Есть ли такой символ в тексте уровня (без учёта регистра).
func _has_char(want: String) -> bool:
	for line: String in display_lines:
		for i in line.length():
			if line.substr(i, 1).to_lower() == want:
				return true
	return false


## Центральный ряд букв ИМЕННО ЭТОГО текста. Считается на смену текста,
## а не на кадр: `_kb_enter_shown` дёргается из отрисовки каждый кадр, и
## одиннадцать прогонов по строкам там — лишняя работа.
func _refresh_home_chars() -> void:
	home_chars.clear()
	for want in HOME_LETTERS:
		if _has_char(want):
			home_chars.append(want)


## Центральный ряд доски — те буквы, по которым ввод разблокируется.
const HOME_LETTERS: Array[String] = ["ф", "ы", "в", "а", "п", "р", "о", "л", "д", "ж", "э"]
## Из них — те, что есть в текущем тексте уровня (см. `_refresh_home_chars`).
var home_chars: Array[String] = []


func _own_press(pos: Vector2, live := false) -> bool:
	if not _own_shown():
		return false
	_poke_idle()
	var act := Kbd.hit(_own_rect(), kb_shift, _kb_enter_shown(), pos)
	if act == "":
		return false
	if live and _repeatable(act):
		# Новую клавишу держим с паузой, повтор той же паузу не сносит.
		if kb_held != act:
			kb_repeat_t = KB_REPEAT_DELAY
		kb_held = act
		kb_held_pos = pos
	# Вспышка сразу на любую нажатую клавишу — человек видит, куда попал.
	_flash(act)
	if act == "шифт":
		# Шифт держится пальцем, а не защёлкивается: второй палец в это
		# время жмёт букву (автор 10.2026). Kbd.hit отдаёт «шифт», а не
		# подпись с клавиши.
		kb_held = "шифт"
		_set_kb_shift(true)
	if act == "ввод":
		# На финале — следующий уровень, в партии — перенос строки.
		# Раньше в партии ввод молчал, и перенос был автоматическим
		# (автор 10.2026: «ты не вернул использование энтера»).
		# Не в попад — опечатка без метки, клавиша красным.
		if state == "playing":
			_flash(act, "ok" if need_enter else "err")
			if not _enter_next_line():
				_wrong_enter()
		else:
			_new_level()
			queue_redraw()
		get_viewport().set_input_as_handled()
		return true
	if state != "playing":
		return false
	if act == "стереть":
		_backspace()
	elif act == "язык":
		# Глобус реально меняет язык ввода: та же клавиша даёт другую
		# букву, подсветка перетекает (синонимичные действия).
		_set_kb_lang("en" if kb_lang == "ru" else "ru")
	elif act == "шифт":
		_set_kb_shift(true)
	elif act == "пробел":
		# Через штатное выключение: знаки должны улететь обратно
		# перелётом, а не скачком (автор 10.2026: «-_ и =+ двигаются не
		# анимацией, а скачком»).
		_set_kb_shift(false)
		# Пробел — такой же ввод: вспыхивает зелёным по верности и
		# красным по ошибке (жалоба автора 10.2026: «пробел не вспыхивает
		# зелёным» — он шёл мимо вердикта и горел жёлтым).
		_flash(act, _verdict(" "))
		_type_char(" ")
	else:
		# Шифт + клавиша — знак или заглавная, буква идёт на языке
		# ввода; шифт гаснет, как на настоящей клавиатуре.
		var ch := Kbd.press_out(act, kb_lang, kb_shift)
		# Через штатное выключение: знаки улетают обратно перелётом.
		_set_kb_shift(false)
		var typed := ch if ch != "" else act
		_flash(act, _verdict(typed))
		_type_char(typed)
	queue_redraw()
	get_viewport().set_input_as_handled()
	return true


## Чернила для рисованного текста поверх панелей и фона: днём тёмные,
## ночью светлые. Пилюли сами меняют фон (_apply_night), а рисованный
## текст за ним не следил — ночью «Дальше», чёрточки ≡ и
## подпись прогресса тонули в тёмном.
func _ui_ink() -> Color:
	return Color("#e8e4d8") if night else INK


## Приглушённые чернила для неактивных подписей клавиш.
func _ui_dim() -> Color:
	return Color("#8b93a8") if night else Color("#4a4438").lightened(0.45)


## Десктоп — там, где нет системной клавиатуры (нет и клавиши F2
## на экране, зато есть физическая). Кнопка игроков там подписана.
## _force_touch включает мобильную раскладку принудительно — для
## headless-тестов веток с клавиатурой (там фичи нет никогда).
var _force_touch := false
func _is_desktop() -> bool:
	return not _force_touch and Ui.is_desktop()


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
			# Палец отпущен: удерживаемый шифт гаснет. Именно так ведёт себя
			# настоящая клавиша (автор 10.2026: «нажимаю — загорается,
			# отпускаю — гаснет»), поэтому шифт на доске не защёлкивается.
			_release_held()
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
		# сборка). Первый тап по звезде показывает расшифровку,
		# повторный по той же идёт дальше.
		if _players_rect.has_point(pos):
			_open_menu()
			get_viewport().set_input_as_handled()
			return
		if state == "won":
			# Первый тап по звезде объясняет балл, повторный по той же —
			# идёт дальше (иначе большая звезда по центру поля съедала
			# бы главный тап «следующий уровень»).
			var tip := _star_at(pos)
			if tip > 0 and tip != _star_tip:
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
	if _own_press(pos, true):
		return
	# Карточка: тап по ней ничего не делает, но событие съедаем, чтобы
	# жест не утаскивал текст.
	if card_p.visible and Rect2(card_p.position, card_p.size).has_point(pos):
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
	# Замеры с кэшем (Ui.text_size): тут цикл замеров на каждый обрезаемый
	# символ, а функция зовётся на каждом кадре (ревизия 16.10.2026).
	if Ui.text_size(mono, t, fs).x <= max_w:
		return t
	var out := t
	while out.length() > 1 and Ui.text_size(mono, out + "…", fs).x > max_w:
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


## Полоса пройденного и счёт справа от неё. Счётчик стоит ТОЙ ЖЕ строкой:
## подпись под полосой стоила целой строки высоты в запасе карточки
## (автор 14.10.2026: текст мелкий, а место пустует). Полоса от этого
## чуть короче — она и так читается по заполнению.
func _draw_progress() -> void:
	if level_total <= 0 or not card_p.visible:
		return
	var done := passed.size()
	var frac := clampf(float(done) / float(level_total), 0.0, 1.0)
	var inset := 20.0 * k
	var th := 12.0 * k
	var t := "%d / %d" % [done, level_total]
	var fs := int(16.0 * k)
	var tw := mono.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs).x
	var r := Rect2(
		card_p.position + Vector2(inset, card_p.size.y + 14.0 * k),
		Vector2(card_p.size.x - inset * 2.0 - tw - 12.0 * k, th)
	)
	draw_style_box(bar_track_sb, r)
	if frac > 0.0:
		draw_style_box(
			bar_fill_sb,
			Rect2(r.position, Vector2(maxf(r.size.x * frac, th), r.size.y))
		)
	# Подпись рисуем по небу: старые цвета давали днём 3:1 (мелкий серый
	# на светлом) — берём общий рисованный текст. Под модалкой победы
	# или проигрыша подпись прячем: иначе цифры налезают на звёзды. Сама
	# полоса остаётся — контекст.
	if over_p.visible:
		return
	draw_string(
		mono,
		Vector2(r.end.x + 12.0 * k, r.position.y + th * 0.5 + fs * 0.36),
		t, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs, _ui_ink()
	)



## Рамка маркера текущей буквы: ровно по глифу (та же ширина, что в
## _cursor_cx), внутри своей строки и карточки — иначе выделитель
## «захватывает конец одной строки и начало другой» (жалоба автора
## 13.10.2026). Отдельная функция, а не код внутри _draw: геометрия
## проверяется числом, а не глазом (см. _text_geometry в logic_test).
func _cursor_rect() -> Rect2:
	if state != "playing" or cursor_line >= display_lines.size():
		return Rect2()
	if cursor_pos < 0:
		return Rect2()
	var line := display_lines[cursor_line]
	if cursor_pos > line.length():
		return Rect2()
	return Rect2(
		_cell_x(cursor_pos) - 2.0 * k, _line_y(cursor_line),
		char_w + 4.0 * k, mono.get_height(font_size)
	)


## Строки текста: каждая буква — в своей клетке (_cell_x), тем же
## шрифтом и кеглем, что считает вёрстка. Никаких построчных лейблов со
## своим шейпингом: второй путь измерения координат давал накопление
## ошибки маркера к концу строки (замерено: 720 против 687 на 60 знаках).
## Ночью — с контуром (как раньше у лейблов): без него буква на белом
## спрайте терялась.
func _draw_rows() -> void:
	if not play_ui:
		return
	var ascent := mono.get_ascent(font_size)
	var ow := maxi(2, int(3.0 * k))
	for i in range(vis_first, mini(vis_first + vis_count, display_lines.size())):
		var line := String(display_lines[i])
		var base := Vector2(margin, _line_y(i) + ascent)
		for p in line.length():
			var at := Vector2(_cell_x(p), base.y)
			var col := _shown_color(i, p)
			var glyph := _shown_char(i, p)
			if night:
				draw_string_outline(mono, at, glyph, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, ow, Color("#141a2c"))
			draw_string(mono, at, glyph, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, col)


## Маркер текущей буквы: курсор всегда видно, даже после отката через
## строки.
func _draw_cursor_marker() -> void:
	var r := _cursor_rect()
	if r.size.x <= 0.0:
		return
	draw_style_box(cursor_sb, r)
	# Шеврон «↵» у конца строки, которая ждёт переноса (автор 13.10.2026):
	# без него не видно, что здесь надо нажать ↵ — а больше на экране в
	# этот момент ничего не меняется. Мягкая пульсация: заметно, не мигает.
	var hint := _enter_hint()
	if not hint.is_empty():
		draw_string(
			mono, Vector2(hint["x"], hint["y"]), "↵",
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, int(font_size * 0.78),
			Color(_ui_ink(), float(hint["alpha"]))
		)


## Значок «↵» у конца строки, которая ждёт переноса: где он стоит и с
## какой прозрачностью. Пусто — рисовать нечего. Отдельная функция, а не
## код внутри _draw: решение проверяется тестом (см. _case_wrap_auto).
func _enter_hint() -> Dictionary:
	if state != "playing" or not need_enter or cursor_line >= display_lines.size():
		return {}
	var line := display_lines[cursor_line]
	# Значок живёт ЗА рамкой курсора (рамка стоит на клетке за последней
	# буквой), иначе он сливается с ней в одно пятно и не читается.
	var after := margin + float(line.length()) * char_w + char_w * 1.4
	return {
		"x": after,
		"y": _line_y(cursor_line) + mono.get_height(font_size) * 0.62,
		"alpha": 0.38 + 0.16 * sin(time * 3.2),
	}


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
	# Прыжок зайца как прыгучий мячик (автор 15.10.2026: гипертрофиро-
	# ванная деформация): присед с антиципацией → вытягивание в толчке →
	# присед на приземлении. Цикл быстрый, наверху не висит.
	var ht := fmod(hop_ph, PI) / PI
	var hop := 0.0
	if ht < 0.3:
		hop = sin(ht / 0.3 * PI * 0.5)
	elif ht < 0.55:
		hop = cos((ht - 0.3) / 0.25 * PI * 0.5)
	# Вытягивание — на взлёте и в полёте, максимум в середине дуги.
	var air := sin(PI * clampf(ht / 0.55, 0.0, 1.0)) if ht < 0.55 else 0.0
	# Присед — удар о землю (быстро) и неполный подъём к концу цикла:
	# следующий прыжок начинается уже заряженным (антиципация).
	var crouch := 0.0
	if ht >= 0.55 and ht < 0.7:
		var u := (ht - 0.55) / 0.15
		crouch = u * u * (3.0 - 2.0 * u)
	elif ht >= 0.7:
		var u := (ht - 0.7) / 0.3
		crouch = 1.0 - 0.55 * (u * u * (3.0 - 2.0 * u))
	c.y -= hop * 7.0 * k
	# Дыхание, чтобы не был статуей.
	var breathe := 1.0 + 0.02 * sin(time * 2.5)
	var sq := Vector2((1.0 + 0.22 * punch) * breathe, (1.0 - 0.12 * punch) / breathe)
	sq *= Vector2(1.0 + 0.24 * crouch, 1.0 - 0.20 * crouch)
	sq *= Vector2(1.0 - 0.14 * air, 1.0 + 0.20 * air)
	# Ноги стоят: деформация идёт от земли, а не из центра — иначе присед
	# проваливал бы зайца под строку, а вытягивание отрывало бы от неё.
	c.y += (1.0 - sq.y) * _unit_h() * k * 0.5
	var s := _spr_scale(HERO_TEX, _unit_h()) * sq
	draw_set_transform(c, 0.0, s)
	draw_texture(HERO_TEX, -HERO_TEX.get_size() * 0.5, (Ui.NIGHT_TINT if night else Color.WHITE))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if blink_t > 0.0 and state != "lost":
		# Веки — две чёрточки поперёк глаз. Рамки глаз измерены по
		# спрайту 139x160: центры (-15, 0) и (+28, 0) от его центра.
		var e := _spr_scale(HERO_TEX, _unit_h())
		for ex in [-15.0, 28.0]:
			var p := c + Vector2(ex * sq.x, 0.0) * e.x
			draw_line(
				p + Vector2(-13.0, 0.0) * e.x, p + Vector2(13.0, 0.0) * e.x,
				Color("#3a3230"), 4.0 * e.x
			)
	if state == "lost":
		# Укололи: глаза навыкате (белки + зрачки), рот раскрыт.
		# Координаты глаз — те же рамки, что у век выше.
		var e2 := _spr_scale(HERO_TEX, _unit_h())
		for ex in [-15.0, 28.0]:
			var p2 := c + Vector2(ex * sq.x, 0.0) * e2.x
			draw_circle(p2, 15.0 * e2.x, Color.WHITE)
			draw_circle(p2, 7.0 * e2.x, Color("#1c1a16"))
		var m := c + Vector2(6.0 * sq.x, 34.0 * sq.y) * e2.x
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
