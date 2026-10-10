class_name Kbd
extends RefCounted
## Своя экранная клавиатура (решение автора 10.2026): системные IME
## (Яндекс, Gboard) коверкают ввод composing-перепиской и автозаменой.
## Свои кнопки дают символ напрямую, без IME.
## Проверяется обычным десктопом (тапы мышью) — живой телефон не нужен.
##
## Слои: русские буквы (ЙЦУКЕН), латиница (QWERTY, для взрослых текстов),
## знаки. Цифры — верхней строкой всегда (требование автора: как у всех).
## Языки (РУ/EN) переключает отдельная кнопка-глобус (векторная, шрифтового
## эмодзи в DejaVu нет); "?123" уводит в знаки с возвратом на свой язык.
## Заглавных рядов нет: одноразовый шифт (⇧) даёт заглавную. ё — долгое
## нажатие е, ъ — долгое ь (стандарт Яндекс-клавиатуры). В меню низ
## кончается вводом (↵ — создать/войти), в игре там «?».
## Модуль чистый (без состояния): язык/слой/шифт хранит вызыватель.

## Верхняя строка цифр — всегда, на всех слоях.
const ROW_DIGITS: Array = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]

## Ряды русских букв (без отдельных ё/ъ — они долгие).
## Шифт и стереть — по бокам нижнего буквенного ряда, широкие
## (раскладка Яндекс-клавиатуры, требование автора 10.2026).
const ROWS_RU: Array = [
	["й", "ц", "у", "к", "е", "н", "г", "ш", "щ", "з", "х"],
	["ф", "ы", "в", "а", "п", "р", "о", "л", "д", "ж", "э"],
	["⇧", "я", "ч", "с", "м", "и", "т", "ь", "б", "ю", "←"],
]

## Ряды латиницы для взрослых текстов (та же геометрия).
const ROWS_EN: Array = [
	["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"],
	["a", "s", "d", "f", "g", "h", "j", "k", "l"],
	["⇧", "z", "x", "c", "v", "b", "n", "m", "←"],
]

## Ряд знаков (цифры — сверху, отдельно).
const ROWS_SYM: Array = [
	["!", "?", ",", ".", ":", ";", "-", "\"", "'", "(", ")"],
]

## Низ буквенных слоёв: [знаки, глобус, запятая, пробел, точка, …].
## В меню вместо «?» — ввод (↵): имя надо чем-то заканчивать.
static func bottom_row(enter: bool) -> Array:
	var last := "↵" if enter else "?"
	return ["?123", "глобус", ",", "пробел", ".", "!", last]


## Низ слоя знаков: [глобус, возврат на язык, пробел, стереть].
static func bottom_sym_row(lang: String) -> Array:
	var back := "РУ" if lang == "ru" else "ABC"
	return ["глобус", back, "пробел", "←"]


## Все ряды слоя сверху вниз (цифры + верх + низ).
static func all_rows(layer: String, lang: String, enter: bool) -> Array:
	var rows: Array = [ROW_DIGITS]
	if layer == "en":
		rows.append_array(ROWS_EN)
	elif layer == "sym":
		rows.append_array(ROWS_SYM)
	else:
		rows.append_array(ROWS_RU)
	if layer == "sym":
		rows.append(bottom_sym_row(lang))
	else:
		rows.append(bottom_row(enter))
	return rows


## Долгое нажатие (стандарт Яндекс-клавиатуры): е→ё, ь→ъ. Пусто — нет пары.
static func long_alt(s: String) -> String:
	match s:
		"е":
			return "ё"
		"ь":
			return "ъ"
		"Е":
			return "Ё"
		"Ь":
			return "Ъ"
	return ""


## Обратная к long_alt: какую клавишу надо ДЕРЖАТЬ, чтобы получить эту
## букву. Игра ждёт «ё» или «ъ», а отдельной клавиши на клавиатуре нет —
## без этой подсказки ребёнок жмёт «е» и собирает красные метки
## (визуальный прогон 10.2026: подсказка молчала «Жми: ё»).
static func long_base(s: String) -> String:
	match s:
		"ё":
			return "е"
		"ъ":
			return "ь"
		"Ё":
			return "Е"
		"Ъ":
			return "Ь"
	return ""


## Есть ли такая клавиша на этом слое? Игра так учит ребёнка, если
## символа на текущем слое нет: «:» и «-» живут только на знаках, а
## подсказка молчала «Жми: :» — набирать было нечем (визуальный прогон
## 10.2026).
##
## Смотрим ТОЛЬКО подписи рядов, без прямоугольников: подсказка
## пересчитывается каждый кадр, и пятьдесят выделенных Rect2 и словарей
## на кадр — это мусор в куче на телефоне (проверено: было именно так).
static func has_key(layer: String, lang: String, shift: bool, s: String) -> bool:
	if s == "":
		return false
	for row in all_rows(layer, lang, false):
		for label in row:
			var lab := String(label)
			if shift and lab.length() == 1 and lab != "←" and lab != "⇧":
				lab = lab.to_upper()
			if lab == s:
				return true
	return false


## Обычная буква или пробел — на буквенном слое есть всегда, проверять
## нечего (ё/ъ разбираются отдельно, они только долгим нажатием).
static func is_plain_letter(s: String) -> bool:
	if s.length() != 1:
		return false
	if s == " ":
		return true
	var lo := s.to_lower()
	return lo >= "а" and lo <= "я" or lo >= "a" and lo <= "z"


## Широкие кнопки (долей ширины ряда): пробел тройной, шифт
## и стереть полуторные (как у Яндекс-клавиатуры), остальные обычные.
static func _span(label: String) -> float:
	if label == "пробел":
		return 3.0
	if label == "⇧" or label == "←":
		return 1.5
	return 1.0


## Высота клавиатуры в пикселях: кнопки чуть выше ширины (×1.15, как у
## Яндекс-клавиатуры), рядов всегда 5 (цифры + 3 верха + низ).
static func height_for(view_w: float) -> float:
	var w := (view_w - 32.0 - 11.0 * 8.0) / 12.0
	return 5.0 * w * ROW_TALL + 4.0 * 8.0 + 32.0


const ROW_TALL := 1.15


## Кнопки слоя: [{r: Rect2, s: String}]. При shift буквы заглавные.
static func buttons(area: Rect2, layer: String, lang: String, shift: bool, enter := false) -> Array:
	var rows: Array = all_rows(layer, lang, enter)
	var out: Array = []
	var gap := 8.0
	var rh := (area.size.y - gap * float(rows.size() - 1)) / float(rows.size())
	for ri in rows.size():
		var row: Array = rows[ri]
		var total_units := 0.0
		for label in row:
			total_units += _span(String(label))
		var unit := (area.size.x - gap * float(row.size() - 1)) / total_units
		var x := area.position.x
		var y := area.position.y + float(ri) * (rh + gap)
		for label in row:
			var w := unit * _span(String(label))
			var s := String(label)
			if shift and s.length() == 1 and s != "←" and s != "⇧":
				s = s.to_upper()
			out.append({"r": Rect2(x, y, w, rh), "s": s})
			x += w + gap
	return out


## Тап по клавиатуре: "" — мимо, иначе действие ("стереть", "слой",
## "шифт", "ввод", "язык", "пробел", символ).
static func hit(area: Rect2, layer: String, lang: String, shift: bool, enter: bool, pos: Vector2) -> String:
	for b in buttons(area, layer, lang, shift, enter):
		if (b["r"] as Rect2).has_point(pos):
			var s := String(b["s"])
			if s == "←":
				return "стереть"
			if s == "?123" or s == "ABC" or s == "РУ":
				return "слой"
			if s == "⇧":
				return "шифт"
			if s == "↵":
				return "ввод"
			if s == "глобус":
				return "язык"
			return s
	return ""


## Нарисовать кнопки на канве вызывателя. Шрифт и стиль — вызывателя.
## Кегль — от высоты ряда (палец!), служебные чуть мельче. Глобус —
## векторный (круг + меридиан): шрифтового эмодзи в DejaVu нет.
## shift_on подсвечивает шифт заливкой (второй стиль вызывателя).
static func draw(
	ci: CanvasItem, area: Rect2, layer: String, lang: String, shift: bool,
	enter: bool, font: Font, fs: int, sb: StyleBox, sb_on: StyleBox, ink: Color
) -> void:
	var gap := 8.0
	var rh := (area.size.y - gap * 4.0) / 5.0
	var key_fs := maxi(fs, int(rh * 0.40))
	for b in buttons(area, layer, lang, shift, enter):
		var r := b["r"] as Rect2
		var s := String(b["s"])
		ci.draw_style_box(sb_on if s == "⇧" and shift else sb, r)
		if s == "глобус":
			_draw_globe(ci, r.get_center(), minf(r.size.x, r.size.y) * 0.30, ink)
			continue
		var f := key_fs
		if s == "пробел" or s == "?123" or s == "ABC" or s == "РУ":
			f = maxi(int(float(fs) * 0.75), int(rh * 0.24))
		var tw := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1.0, f).x
		var th := font.get_height(f)
		ci.draw_string(
			font,
			Vector2(r.get_center().x - tw * 0.5, r.get_center().y + float(th) * 0.3),
			" " if s == "пробел" else s,
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, f, ink
		)


## Глобус кнопки языка: круг, вертикальный меридиан-эллипс и горизонталь.
static func _draw_globe(ci: CanvasItem, c: Vector2, rad: float, ink: Color) -> void:
	ci.draw_arc(c, rad, 0.0, TAU, 32, ink, 2.5)
	var pts := PackedVector2Array()
	for i in 17:
		var a := float(i) / 16.0 * TAU
		pts.append(c + Vector2(cos(a) * rad * 0.45, sin(a) * rad))
	ci.draw_polyline(pts, ink, 2.0)
	ci.draw_line(c + Vector2(-rad, 0.0), c + Vector2(rad, 0.0), ink, 2.0)
