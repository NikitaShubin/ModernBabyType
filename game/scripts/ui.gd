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
## ВЫВОД ПАЛИТРЫ ИЗ ФОНОВ (автор 17.10.2026: «цвета остального интерфейса
## надо выбирать под них»). Фоны meadow.gd заданы автором и хороши, значит
## остальное выводится из них, а не выбирается на глаз. Считаем в OKLCH —
## воспринимаемая светлота L, насыщенность C, hue H (цвета в HSL/смеси
## RGB сравнивать нельзя: там одинаково «яркие» цвета разной светлоты).
## Опоры — сами фоны, их OKLCH:
##   небо день  #8fd0ee → L .82 C .29 H 187   горизонт #f7f3e8 → H  35
##   солнце     #ffd94d → H  47                холм     #cfe6b8 → H 133
##   небо ночь  #2a3a5e → H 209
## Отсюда hue-якоря, по одному на семью (theme_test держит разброс ≤12°):
##   тёплый 40 (бумага, чернила, жёлтое) · синий 200 (акцент) ·
##   зелёный 150 (холм) · красный 5 (семантический, в фонах его нет) ·
##   ночные поверхности 210 (ночное небо).
##
## Четыре правила, по которым дальше меняются роли:
##   1. СВЕТЛОТА — по контрасту, а не по вкусу: у всех состояний заливка
##      стоит на одном L в обеих темах (0.78 «верно», 0.72 «ошибка»).
##      Раньше «верно» днём было светло-зелёным, а ночью тёмно-зелёным —
##      один смысл и два разных цвета (правило «цвет значит одно»).
##   2. НАСЫЩЕННОСТЬ у hue своя, и это не каприз: в sRGB красный живёт
##      при C≈0.45-0.85, синий при C≈0.12. Сравнять абсолютно — значит
##      сделать красный коричневым (проверено сеткой: L.72 H5 C.28 — это
##      пыльная роза). Сравнивают относительную насыщенность C/Cmax(L,H),
##      долю доступной гаммы: у состояний она 0.4-1.2, у нейтралей ≤0.35.
##   3. НОЧЬ = те же hue и та же полярность, сдвинута только светлота:
##      бумага холодная (небо ночи), чернила тёплые (светлое на холодном
##      фоне — единственная тёплая пара, которую не меняем).
##   4. КОНТРАСТ по WCAG (текст 4.5, рамка/заливка 3) — и не на бумаге
##      роли, а на НАСТОЯЩЕМ фоне: карточка полупрозрачная и лежит
##      поверх неба, поэтому theme_test кладёт её на оба края градиента
##      (#8fd0ee и #f7f3e8 днём, #0d1526 и #2a3a5e ночью).
##
## Смысловые роли: акцент один (синий) и означает одно — «включено»
## (клавиша-ввод, флаг профиля). Выделение строки — жёлтое и другое
## (это выбор, а не включение). ok/danger — только про результат.
const CARD_DAY := Color(1.0, 0.992, 0.965, 0.65)
const CARD_NIGHT := Color(0.137, 0.173, 0.267, 0.65)

## Поверхности. Бумага дня — ровно горизонт неба (#f7f3e8, H35).
const PAPER_DAY := Color("#f7f3e8")
const PAPER_NIGHT := Color("#0f1520")
## Полупрозрачная строка списка (сквозь неё видно небо).
const ROW_IDLE_DAY := Color(1, 1, 1, 0.45)
const ROW_IDLE_NIGHT := Color(0.10, 0.12, 0.20, 0.60)
## Пилюля-подсказка.
const PILL_DAY := Color(1, 1, 1, 0.72)
const PILL_NIGHT := Color(0.10, 0.12, 0.20, 0.80)
const SURFACE_DAY := Color("#f8f9f8")  # L.98 C.03 H36
const SURFACE_NIGHT := Color("#272f3e")  # L.30 C.06 H209
## Вторая поверхность: клавиша доски, выключенный чип, ключ подсказки.
const SURFACE_ALT_DAY := Color("#f8fdff")  # L.99 C.01 H40
const SURFACE_ALT_NIGHT := Color("#3c4557")  # L.38 C.06 H211
## Рамки: обычная и тихая (рамка списка, пилюля-пояснение).
const LINE_DAY := Color("#4f4c42")  # L.42 C.04 H41
const LINE_NIGHT := Color("#a3acbb")  # L.74 C.03 H207
const LINE_SOFT_DAY := Color("#d6d3c6")  # L.87 C.05 H41
const LINE_SOFT_NIGHT := Color("#4c576d")  # L.45 C.07 H211
## Текст. Шаг светлоты вместо шага насыщенности: чёрный, тёмно-серый
## и серый различаются светлотой, а не тем, что один «теплее» другого.
const INK_DAY := Color("#23211b")  # L.25 C.03 H40
const INK_NIGHT := Color("#ededea")  # L.95 C.03 H36 — тёплые на холодном
const UI_TEXT_DAY := Color("#4f4c42")  # L.42 C.04 H41
const UI_TEXT_NIGHT := Color("#ddddd9")  # L.90 C.03 H38
const DIM_DAY := Color("#68665f")  # L.52 C.03 H40 — и на худшем небе 4.8
const DIM_NIGHT := Color("#a3acbb")  # L.74 C.03 H207
## Серая буква уровня (серая клетка = проходится сама).
const GREY_CHAR_DAY := Color("#6c6961")  # L.53 C.04 H40
const GREY_CHAR_NIGHT := Color("#9ba4b5")  # L.72 C.03 H212
## Выбор строки (жёлтый, обе темы — он и есть «выбран»). Hue 46 — солнце.
const SELECT_DAY := Color("#f0d98a")  # L.90 C.18 H46
const SELECT_NIGHT := Color("#e2cc7f")  # L.86 C.17 H46 — ночью тише
## Текст на выбранной строке: строка светлая в обеих темах, значит
## чернила тёмные в обеих (иначе ночью 1.37:1).
const SELECT_TEXT_DAY := Color("#2a261d")
const SELECT_TEXT_NIGHT := Color("#2a261d")
## Акцент: «включено». Hue 200 — небо (187), чуть сильнее: на самом небе
## акцент не должен сливаться с фоном.
const ACCENT_DAY := Color("#abc5e5")  # L.81 C.12 H200
const ACCENT_NIGHT := Color("#a2bbda")  # L.78 C.12 H200
## Текст НА акценте: акцент светлый в обеих темах, поэтому и чернила
## здесь тёмные (8.5:1 днём, 8.1:1 ночью). Светлый текст на голубом
## давал 1.85:1 — нечитаемо.
const ACCENT_INK := Color("#2a261d")
const ACCENT_INK_NIGHT := Color("#1d222c")  # ночь — холоднее фона
## Рамка включённого чипа — тёмная в обеих темах: акцент светлый
## всегда, а ночная серая рамка на нём давала 1.42:1.
const ACCENT_EDGE_DAY := Color("#2a261d")
const ACCENT_EDGE_NIGHT := Color("#1d222c")
## Ободок фокуса: два значения, потому что обводит он РАЗНОЕ. На
## светлом (пустая рамка, включённый чип, жёлтая строка) — тёмный;
## на тёмном (ночная клавиша) — светлый. Один цвет на все неё даёт
## либо 1.2, либо 1.1 (ловил на числах: 17.10.2026).
const FOCUS_DARK := Color("#2a261d")
const FOCUS_LIGHT := Color("#ededea")
## Верный ввод. Заливка на одном L с «ошибкой» в обеих темах (правило 1),
## hue 150 — холм.
const OK_DAY := Color("#8bbf76")  # L.78 C.24 H150
const OK_NIGHT := Color("#90bf7f")  # L.78 C.22 H150
const OK_EDGE_DAY := Color("#3c5a2e")  # L.45 C.16 H150
const OK_EDGE_NIGHT := Color("#365129")  # L.42 C.15 H150
## Текст «верно» (итог в модалке) — тот же hue, светлота по контрасту.
const OK_TEXT_DAY := Color("#4e6e42")  # L.52 C.16 H150
const OK_TEXT_NIGHT := Color("#9bbc93")  # L.78 C.15 H150
## Ошибка/опасное действие. Hue 5 — семантический: в фонах красного нет,
## и он не должен выглядеть как часть пейзажа.
const DANGER_DAY := Color("#ee917b")  # L.72 C.48 H5
const DANGER_NIGHT := Color("#e9927f")  # L.72 C.45 H5
const DANGER_EDGE_DAY := Color("#682e1e")  # L.35 C.35 H5
const DANGER_EDGE_NIGHT := Color("#652f20")  # L.35 C.33 H5
const DANGER_TEXT_DAY := Color("#863d29")  # L.42 C.42 H5
const DANGER_TEXT_NIGHT := Color("#ebb1a8")  # L.80 C.30 H5
## Красные метки опечаток (в тексте, BBCode) — тот же hue ошибки.
const ERR_DAY := Color("#a95742")  # L.52 C.45 H5
const ERR_NIGHT := Color("#d48878")  # L.68 C.40 H5
## Нажатая клавиша (нейтральная вспышка) и подсветка подсказки.
const PRESS_DAY := Color("#fada67")  # L.91 C.23 H47 — солнце
const PRESS_NIGHT := Color("#9a8127")  # L.62 C.18 H46
const HINT_KEY_DAY := Color("#fdd74c")  # L.90 C.25 H47
const HINT_KEY_NIGHT := Color("#b19100")  # L.68 C.22 H47
## Прогресс и бейдж.
const PROGRESS_DAY := Color("#5f7f53")  # L.58 C.16 H150
const PROGRESS_NIGHT := Color("#87aa7e")  # L.72 C.16 H150
const TRACK_DAY := Color("#d9d6c9")  # L.88 C.05 H41
const TRACK_NIGHT := Color("#454f61")  # L.42 C.06 H209
const BADGE_DAY := Color("#81ab71")  # L.72 C.20 H150
const BADGE_EDGE_DAY := Color("#3a542f")  # L.43 C.14 H150
const BADGE_EDGE_NIGHT := Color("#b5d2b3")  # L.85 C.12 H150
const BADGE_NIGHT := Color("#455840")  # L.45 C.10 H150
## Курсор/маркер клетки: мягкое пятно цвета выбора под буквой.
const CURSOR_DAY := Color(0.941, 0.851, 0.541, 0.55)
const CURSOR_NIGHT := Color(0.886, 0.800, 0.498, 0.42)
## Звёзды за уровень и фейерверк.
const STAR_DAY := Color("#7c6714")  # L.53 C.16 H47 — это текст (Label)
const STAR_NIGHT := Color("#d2c07d")  # L.82 C.15 H48

## Значение роли по теме. Ночью берём второе, иначе первое: тема
## хранится в узлах, а роли — здесь.
static func pick(night: bool, day: Color, n: Color) -> Color:
	return n if night else day


## Те же роли строкой — для BBCode (игра размечает им текст ошибок и
## подсказку). Держим рядом с ролью: раньше hex и Color жили в разных
## местах и разошлись (#c02727 против #b02323 на одном экране).
static func hex_of(c: Color) -> String:
	return "#" + c.to_html(false)


const ERR_DAY_HEX := "#a95742"
const ERR_NIGHT_HEX := "#d48878"

## Вспышка клетки: ответ на нажатие, которое ничего не изменило (откат
## в серую клетку, проглоченный дубль). Видно, что игра услышала. Тот
## же hue акцента — подсказка не новое состояние, а отклик.
const HINT_DAY_HEX := "#5c7697"
const HINT_NIGHT_HEX := "#97b2d3"
