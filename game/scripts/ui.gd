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
static func is_desktop() -> bool:
	return not DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD)


## Затемнение героев ночью: светлый мех не светится на тёмном фоне.
const NIGHT_TINT := Color(0.72, 0.76, 0.90)


## Эффективная высота: низ, занятый клавиатурой, не наш. Пол не
## проваливается ниже минимума.
const EFF_MIN_H := 220.0
static func eff_h(view_h: float, kb_h: float) -> float:
	return maxf(view_h - kb_h, EFF_MIN_H)


## Карточка текста: тёплый картон днём, холодный ночью. Полупрозрачная
## (0.80): небо с облаками и птицами просвечивает, а буквы (они
## отдельными лейблами поверх) остаются полностью читаемыми.
const CARD_DAY := Color(1.0, 0.992, 0.965, 0.80)
const CARD_NIGHT := Color(0.137, 0.173, 0.267, 0.80)


## Красные метки опечаток: день и ночь (и hex для BBCode).
const ERR_DAY := Color("#c02727")
const ERR_NIGHT := Color("#ff7a6b")
const ERR_DAY_HEX := "#c02727"
const ERR_NIGHT_HEX := "#ff7a6b"
