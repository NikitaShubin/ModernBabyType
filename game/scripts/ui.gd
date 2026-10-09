class_name Ui
extends RefCounted
## Общие UI-кирпичи игры и меню: раньше копипаста жила в обоих скриптах
## и уже разъезжалась (палитры ночи правили в одном месте из двух).
## Чистые статики, состояния нет.


## Скруглённая панель: тень — только у больших карточек, радиусы
## в пикселях (без пересоздания стилей при каждом ресайзе).
static func panel_sb(bg: Color, radius: float, border := Color(0, 0, 0, 0), bw := 0.0, shadow := false) -> StyleBoxFlat:
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


## Десктоп — там, где нет системной клавиатуры.
## force_touch включает мобильную раскладку принудительно — для стенда
## (--touch-kb) и headless-тестов: игру и меню переключает игра.
static var force_touch := false
static func is_desktop() -> bool:
	return not force_touch and not DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD)


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
	if not DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD):
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
	if not DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD):
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


## Карточка текста: тёплый картон днём, холодный ночью. Полупрозрачная
## (0.65): небо с облаками и птицами просвечивает, а буквы (они
## отдельными лейблами поверх) остаются полностью читаемыми.
const CARD_DAY := Color(1.0, 0.992, 0.965, 0.65)
const CARD_NIGHT := Color(0.137, 0.173, 0.267, 0.65)


## Красные метки опечаток: день и ночь (и hex для BBCode).
const ERR_DAY := Color("#c02727")
const ERR_NIGHT := Color("#ff7a6b")
const ERR_DAY_HEX := "#c02727"

## Вспышка клетки: ответ на нажатие, которое ничего не изменило (откат
## в серую клетку, проглоченный дубль). Видно, что игра услышала.
const HINT_DAY_HEX := "#2f7fd0"
const HINT_NIGHT_HEX := "#7fc0ff"
const ERR_NIGHT_HEX := "#ff7a6b"
