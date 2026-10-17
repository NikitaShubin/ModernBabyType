class_name Ui
extends RefCounted
## Общие UI-кирпичи игры и меню: раньше копипаста жила в обоих скриптах
## и уже разъезжалась (палитры ночи правили в одном месте из двух).
## Чистые статики, состояния нет.


## Замер строки с ЗАПОМИНАНИЕМ по (шрифт, текст, кегль). Замеры идут
## на каждом кадре — у каждой клавиши доски, у каждой подписи, в цикле
## обрезки длинного текста, — а font.get_string_size ходит в раскладку
## шрифта каждый раз (ревизия 16.10.2026). Ключи ограничены тем, что
## реально рисуют: подписи доски, имена игроков, строки подсказок.
static var _tsize: Dictionary = {}
## Счётчики для perf_test: промахи кэша замера и создания панелей. Панели
## на кадре не создаются (ревизия 16.10.2026), замер после первого кадра
## не промахивается — обе цифры растут только на переразметке.
static var text_size_misses := 0
static var panel_sb_calls := 0


static func text_size(font: Font, txt: String, fs: int) -> Vector2:
	if font == null:
		# Шрифта ещё нет (сцена монтируется): грубая оценка, как раньше.
		return Vector2(float(txt.length()) * float(fs) * 0.6, float(fs))
	var fid: int = font.get_instance_id()
	var by_text: Dictionary = _tsize.get(fid, {})
	var by_fs: Variant = by_text.get(txt)
	if by_fs is Dictionary and (by_fs as Dictionary).has(fs):
		return by_fs[fs]
	text_size_misses += 1
	var sz := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs)
	if not by_fs is Dictionary:
		by_fs = {}
		by_text[txt] = by_fs
	by_fs[fs] = sz
	_tsize[fid] = by_text
	return sz


## Скруглённая панель: тень — только у больших карточек, радиусы
## в пикселях (без пересоздания стилей при каждом ресайзе).
static func panel_sb(bg: Color, radius: float, border := Color(0, 0, 0, 0), bw := 0.0, shadow := false) -> StyleBoxFlat:
	panel_sb_calls += 1
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


## Десктоп — там, где печатают физической клавиатурой.
## Признак больше не «нет системной клавиатуры» (с ней мы расстались),
## а платформа: своя экранная клавиатура рисуется на телефоне, на
## десктопе её нет. force_touch включает мобильную раскладку принудительно
## — для headless-тестов и стенда.
static var force_touch := false
static func is_desktop() -> bool:
	if force_touch:
		return false
	return OS.get_name() != "Android" and OS.get_name() != "iOS"


## Переопределение плотности для тестов (0 — авто).
static var dpr_override := 0.0


## Плотность экрана (px в dp) для сенсорных. Меню считает в физических
## пикселях, а на телефоне они в 2–3 раза мельче десктопных: без этого
## всё меню в портрете мелкое (жалоба автора 10.2026). На десктопе
## и в headless — всегда 1, там координаты уже независимые.
static func dpr() -> float:
	if dpr_override > 0.0:
		return dpr_override
	if is_desktop():
		return 1.0
	if DisplayServer.get_name() == "headless":
		return 1.0
	var scr := DisplayServer.window_get_current_screen()
	if scr < 0:
		return 1.0
	return clampf(DisplayServer.screen_get_scale(scr), 1.0, 3.5)


## Затемнение героев ночью: светлый мех не светится на тёмном фоне.
const NIGHT_TINT := Color(0.72, 0.76, 0.90)


## Низ верхнего выреза экрана (камера-капля, требование автора 10.2026:
## полноэкранная игра залезает под камеру, та закрывает имя игрока).
## Чистая функция от списка вырезов — матрица в тестах; живые вырезы
## берёт top_inset() (на десктопе их нет — всегда ноль).
static func cutout_bottom(cutouts: Array, view_h: float) -> float:
	var out := 0.0
	for r in cutouts:
		var rc := r as Rect2
		if rc == null:
			continue
		if rc.position.y < view_h * 0.1:
			out = maxf(out, rc.end.y)
	return out


static func top_inset(view_h: float) -> float:
	if is_desktop():
		return 0.0
	return cutout_bottom(DisplayServer.get_display_cutouts(), view_h)


## Переопределение нижнего отступа для тестов (< 0 — авто).
static var bottom_override := -1.0


## Низ безопасной зоны: жест внизу и скругления экрана съедают низ.
## Своя клавиатура поднимается на него, иначе угловые клавиши под
## скруглением не достать (жалоба автора 10.2026). Как и вырезы,
## считаем в координатах вьюпорта. Без фичи клавиатуры — всегда ноль.
## Скругления API может не учитывать, поэтому минимум 12dp на сенсорных.
static func bottom_inset(view_h: float) -> float:
	if bottom_override >= 0.0:
		return bottom_override
	if is_desktop():
		return 0.0
	var safe := 0.0
	var area: Rect2 = DisplayServer.get_display_safe_area()
	if area.size.x > 0.0 and area.size.y > 0.0:
		safe = maxf(0.0, view_h - area.end.y)
	return maxf(safe, 12.0 * dpr())


## Эффективная высота: низ, занятый клавиатурой, не наш. Пол не
## проваливается ниже минимума.
const EFF_MIN_H := 220.0
static func eff_h(view_h: float, kb_h: float) -> float:
	return maxf(view_h - kb_h, EFF_MIN_H)


## СЛОВАРЬ РОЛЕЙ (ревизия 17.10.2026). До него каждая панель красилась
## своим литералом в своём файле: 12 зелёных, 8 красных, 8 синих и два
## разных «чернила» на весь проект, а игра и меню держали разные палитры
## (клавиша бежевая в игре и белая в меню, ошибка #c02727 и #b02323).
## Теперь роль одна — значение одно на день и на ночь, и оно проверено
## на контраст (theme_test).
##
## Правила выбора:
##   * бумага тёплая днём (#fffdf6 и рядом), холодная ночью (#232c44);
##   * чернила — единственный цвет текста, dim — для второстепенного;
##   * акцент один (синий) и означает одно: «включено» (клавиша-ввод,
##     флаг профиля). Выделение строки — жёлтое и другое (это выбор,
##     а не включение) — иначе «выделение внутри выделения»;
##   * ok/danger — только про результат (верный ввод, опечатка, крестик);
##   * фокус — чернила по теме: единственная пара, которая контрастит и
##     с пустой рамкой, и с акцентной заливкой, и с жёлтой строкой.
const CARD_DAY := Color(1.0, 0.992, 0.965, 0.65)
const CARD_NIGHT := Color(0.137, 0.173, 0.267, 0.65)

## Поверхности.
const PAPER_DAY := Color("#f7f3e8")
const PAPER_NIGHT := Color("#141a2c")
## Полупрозрачная строка списка (сквозь неё видно небо).
const ROW_IDLE_DAY := Color(1, 1, 1, 0.45)
const ROW_IDLE_NIGHT := Color(0.10, 0.12, 0.20, 0.60)
## Пилюля-подсказка.
const PILL_DAY := Color(1, 1, 1, 0.72)
const PILL_NIGHT := Color(0.10, 0.12, 0.20, 0.80)
const SURFACE_DAY := Color("#fffdf6")
const SURFACE_NIGHT := Color("#232c44")
## Вторая поверхность: клавиша доски, выключенный чип, ключ подсказки.
const SURFACE_ALT_DAY := Color("#ffffff")
const SURFACE_ALT_NIGHT := Color("#2f3a5c")
## Рамки: обычная и тихая (рамка списка, пилюля-пояснение).
const LINE_DAY := Color("#4a4438")
const LINE_NIGHT := Color("#8b93a8")
const LINE_SOFT_DAY := Color("#e0d5bd")
const LINE_SOFT_NIGHT := Color("#3a4a6b")
## Текст.
const INK_DAY := Color("#1c1a16")
const INK_NIGHT := Color("#f2ede0")
const UI_TEXT_DAY := Color("#4a4438")
const UI_TEXT_NIGHT := Color("#e8e4d8")
const DIM_DAY := Color("#6f6a5e")
const DIM_NIGHT := Color("#9aa3b8")
## Серая буква уровня (серая клетка = проходится сама).
const GREY_CHAR_DAY := Color("#787366")
const GREY_CHAR_NIGHT := Color("#7f8bab")
## Выбор строки (жёлтый, обе темы — он и есть «выбран»).
const SELECT_DAY := Color("#f0d98a")
const SELECT_NIGHT := Color("#f0d98a")
## Акцент: «включено». День — тот же голубой, что у включённой клавиши
## в игре, ночь — светлее, чтобы читался на тёмном.
const ACCENT_DAY := Color("#a9c6ec")
const ACCENT_NIGHT := Color("#8ab4e0")
## Текст НА акценте: акцент светлый в обеих темах, поэтому и чернила
## здесь тёмные (8.6:1 днём, 6.9:1 ночью). Светлый текст на голубом
## давал 1.85:1 — нечитаемо.
const ACCENT_INK := Color("#2a2620")
## Рамка включённого чипа — тёмная в обеих темах: акцент светлый
## всегда, а ночная серая рамка на нём давала 1.42:1.
const ACCENT_EDGE_DAY := Color("#2a2620")
const ACCENT_EDGE_NIGHT := Color("#2a2620")
## Ободок фокуса: два значения, потому что обводит он РАЗНОЕ. На
## светлом (пустая рамка, включённый чип, жёлтая строка) — тёмный;
## на тёмном (ночная клавиша) — светлый. Один цвет на все неё даёт
## либо 1.2, либо 1.1 (ловил на числах: 17.10.2026).
const FOCUS_DARK := Color("#2a2620")
const FOCUS_LIGHT := Color("#f2ede0")
## Верный ввод.
const OK_DAY := Color("#8fd66a")
const OK_NIGHT := Color("#3f6b3a")
const OK_EDGE_DAY := Color("#3f6b2c")
const OK_EDGE_NIGHT := Color("#9ad08c")
## Текст «верно» (итог в модалке) — тот же зелёный, но читаемый на
## тёмной подложке модалки.
const OK_TEXT_DAY := Color("#1e7a34")
const OK_TEXT_NIGHT := Color("#8fd07f")
## Ошибка/опасное действие.
const DANGER_DAY := Color("#ff8a80")
const DANGER_NIGHT := Color("#7a2f28")
const DANGER_EDGE_DAY := Color("#8e2f26")
const DANGER_EDGE_NIGHT := Color("#ff9a90")
const DANGER_TEXT_DAY := Color("#b02323")
const DANGER_TEXT_NIGHT := Color("#ff9a90")
## Нажатая клавиша (нейтральная вспышка) и подсветка подсказки.
const PRESS_DAY := Color("#ffd98a")
const PRESS_NIGHT := Color("#6b5a2a")
const HINT_KEY_DAY := Color("#ffd75e")
const HINT_KEY_NIGHT := Color("#8a6d1f")
## Прогресс и бейдж.
const PROGRESS_DAY := Color("#51783f")
const PROGRESS_NIGHT := Color("#7fb069")
const TRACK_DAY := Color("#e6dcc4")
const TRACK_NIGHT := Color("#3a4a6b")
const BADGE_DAY := Color("#7fb069")
const BADGE_EDGE_DAY := Color("#405936")
const BADGE_EDGE_NIGHT := Color("#9ad08c")
const BADGE_NIGHT := Color("#33513c")
## Курсор/маркер клетки: мягкое жёлтое пятно под буквой.
const CURSOR_DAY := Color(1.0, 0.82, 0.25, 0.5)
const CURSOR_NIGHT := Color(1.0, 0.82, 0.25, 0.38)
## Звёзды за уровень и фейерверк.
const STAR_DAY := Color("#9a6615")
const STAR_NIGHT := Color("#e8a93d")

## Значение роли по теме. Ночью берём второе, иначе первое: тема
## хранится в узлах, а роли — здесь.
static func pick(night: bool, day: Color, n: Color) -> Color:
	return n if night else day


## Красные метки опечаток: день и ночь (и hex для BBCode).
const ERR_DAY := Color("#c02727")
const ERR_NIGHT := Color("#ff7a6b")
const ERR_DAY_HEX := "#c02727"

## Вспышка клетки: ответ на нажатие, которое ничего не изменило (откат
## в серую клетку, проглоченный дубль). Видно, что игра услышала.
const HINT_DAY_HEX := "#2f7fd0"
const HINT_NIGHT_HEX := "#7fc0ff"
const ERR_NIGHT_HEX := "#ff7a6b"
