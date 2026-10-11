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
## эмодзи в DejaVu нет). Слоя знаков нет: всё идёт шифтом или прямыми.
## Заглавных рядов нет: одноразовый шифт даёт заглавную. Какой из двух
## шифтов жать — по правилу противоположной руки (см. _hint_keys в игре).
## В меню низ кончается вводом (↵ — создать/войти).
## Модуль чистый (без состояния): язык/слой/шифт хранит вызыватель.

## Верхняя строка цифр — всегда, на всех слоях.
const ROW_DIGITS: Array = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]

## Верх цифр по-русски: своя «ё» слева сверху (как на настоящей),
## справа «-» и «=» (тоже прямые клавиши), дальше «стереть» —
## Backspace сверху справа, как на настоящей (решение 10.2026).
const ROW_DIGITS_RU: Array = ["ё", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "="]

## Ряды русских букв — как на настоящей клавиатуре: «ъ» справа от «х»,
## ввод справа от «э» (как настоящий Enter), два шифта по бокам нижнего
## ряда. Отдельных клавиш Tab/Caps/Enter-слева нет (им нечего делать в
## игре), поэтому ступеньки идут от края — честная адаптация narrow-рядов,
## а не копия вслепую.
const ROWS_RU: Array = [
	["й", "ц", "у", "к", "е", "н", "г", "ш", "щ", "з", "х", "ъ"],
	["ф", "ы", "в", "а", "п", "р", "о", "л", "д", "ж", "э", "↵"],
	["Shift", "я", "ч", "с", "м", "и", "т", "ь", "б", "ю", ".", "ShiftR"],
]

## Ряды латиницы для взрослых текстов (та же геометрия).
const ROWS_EN: Array = [
	["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"],
	["a", "s", "d", "f", "g", "h", "j", "k", "l"],
	["Shift", "z", "x", "c", "v", "b", "n", "m", "←"],
]

## Низ доски: язык, пробел и прямые знаки. Слоя ?123 больше нет: все
## знаки идут шифтом с цифр или прямыми клавишами, как на настоящей
## (решение 10.2026). Запятая — тоже шифтом (Shift+.): отдельной клавиши
## нет. В меню вместо «?» — ввод (↵): имя надо чем-то заканчивать.
static func bottom_row(enter: bool) -> Array:
	var last := "↵" if enter else "?"
	if enter:
		return ["глобус", "пробел", ".", "!", last]
	return ["глобус", "пробел", ".", "!", "?", "-", "\\"]


## Все ряды слоя сверху вниз (цифры + верх + низ).
static func all_rows(layer: String, lang: String, enter: bool) -> Array:
	var rows: Array = []
	if layer == "en":
		rows.append(ROW_DIGITS)
		rows.append_array(ROWS_EN)
	else:
		rows.append(ROW_DIGITS_RU + ["←"])
		rows.append_array(ROWS_RU)
	rows.append(bottom_row(enter))
	return rows


## Рука клавиши: «Л» левая, «П» правая (зоны слепой печати: левая рука —
## ё12345, йцуке, фывап, ячсми; всё остальное — правая). Нужно правилу
## противоположной руки: шифт и пробел жмутся рукой, свободной от буквы.
static func hand_of(s: String) -> String:
	var lo := s.to_lower()
	if lo in ["ё", "1", "2", "3", "4", "5"]:
		return "Л"
	if lo in ["й", "ц", "у", "к", "е"]:
		return "Л"
	if lo in ["ф", "ы", "в", "а", "п"]:
		return "Л"
	if lo in ["я", "ч", "с", "м", "и"]:
		return "Л"
	return "П"


## Пары букв двух раскладок на одной физической клавише (позиционное
## соответствие ЙЦУКЕН–QWERTY). Нужно двуязычным подписям: обе буквы
## печатаются на клавише, активная светится ярче.
const RU_EN := {
	"й": "q", "ц": "w", "у": "e", "к": "r", "е": "t", "н": "y",
	"г": "u", "ш": "i", "щ": "o", "з": "p", "х": "[", "ъ": "]",
	"ф": "a", "ы": "s", "в": "d", "а": "f", "п": "g", "р": "h",
	"о": "j", "л": "k", "д": "l", "ж": ";", "э": "'",
	"я": "z", "ч": "x", "с": "c", "м": "v", "и": "b", "т": "n",
	"ь": "m", "б": ",", "ю": ".", "ё": "`",
	"q": "й", "w": "ц", "e": "у", "r": "к", "t": "е", "y": "н",
	"u": "г", "i": "ш", "o": "щ", "p": "з", "[": "х", "]": "ъ",
	"a": "ф", "s": "ы", "d": "в", "f": "а", "g": "п", "h": "р",
	"j": "о", "k": "л", "l": "д", ";": "ж", "'": "э",
	"z": "я", "x": "ч", "c": "с", "v": "м", "b": "и", "n": "т",
	"m": "ь", ",": "б", ".": "ю", "`": "ё",
}


## Вторая буква клавиши (другая раскладка). Пусто — пара одна.
static func pair_of(s: String) -> String:
	return String(RU_EN.get(s.to_lower(), ""))


## Долгого нажатия больше нет: у «ё» и «ъ» свои клавиши, как на
## настоящей клавиатуре (решение 10.2026).


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
			if shift and lab.length() == 1 and lab != "←" and lab != "Shift" and lab != "ShiftR":
				lab = lab.to_upper()
			if lab == s:
				return true
	return false


## Обычная буква или пробел — на буквенном слое есть всегда, проверять
## нечего.
static func is_plain_letter(s: String) -> bool:
	if s.length() != 1:
		return false
	if s == " ":
		return true
	var lo := s.to_lower()
	# «ё» вне диапазона а..я (U+0451), но буква обычная: у неё своя клавиша.
	if lo == "ё":
		return true
	return lo >= "а" and lo <= "я" or lo >= "a" and lo <= "z"


## Шифт + цифра верхней строки — как на настоящей клавиатуре: знаки
## препинания там набираются шифтом, а не слоем ?123 (а мы учим человека
## реальной, а не виртуальной клавиатуре — решение 10.2026). Пусто —
## цифра без пары (или не цифра вовсе).
static func shift_digit(s: String) -> String:
	match s:
		"1":
			return "!"
		"2":
			return "\""
		"3":
			return "№"
		"4":
			return ";"
		"5":
			return "%"
		"6":
			return ":"
		"7":
			return "?"
		"8":
			return "*"
		"9":
			return "("
		"0":
			return ")"
		".":
			return ","
	return ""


## Обратная к shift_digit: какой клавишей с шифтом набрать этот знак.
## Пусто — знак так не набирается.
static func digit_for(sym: String) -> String:
	match sym:
		"!":
			return "1"
		"\"":
			return "2"
		"№":
			return "3"
		";":
			return "4"
		"%":
			return "5"
		":":
			return "6"
		"?":
			return "7"
		"*":
			return "8"
		"(":
			return "9"
		")":
			return "0"
		",":
			return "."
	return ""


## Широкие кнопки (долей ширины ряда): пробел тройной, шифт
## и стереть полуторные (как у Яндекс-клавиатуры), остальные обычные.
static func _span(label: String) -> float:
	if label == "пробел":
		return 3.0
	if label == "Shift" or label == "ShiftR" or label == "←":
		return 1.5
	return 1.0


## Высота клавиатуры в пикселях: кнопки чуть выше ширины (×1.15, как у
## Яндекс-клавиатуры), рядов всегда 5 (цифры + 3 верха + низ).
static func height_for(view_w: float) -> float:
	var w := (view_w - 32.0 - 11.0 * 8.0) / 12.0
	return 5.0 * w * ROW_TALL + 4.0 * 8.0 + 32.0


const ROW_TALL := 1.15


## Кнопки слоя: [{r: Rect2, s: String}]. При shift буквы заглавные.
## Раскладка ряда: у буквенных клавиш ОДИНАКОВАЯ ширина на всех рядах
## (питч слоя), а сдвиги-соты добираются нестандартной шириной краевых
## клавиш — как на настоящей клавиатуре (решение 10.2026).
## Питч задают ряды без широких клавиш (min их натуральной ширины);
## ряды с пробелом считаются по-старому (пробел тянется во всю ширину).
## Остаток ряда без широких клавиш (цифры) — делится поровну по бокам.
## Остаток ряда со стиранием/шифтом уходит в края: ведущий край берёт
## всё сверх минимума 32px (это и есть ступенька), замыкающий — 32px.
## Минимум держит и узкий телефон: питч ограничен сверху и этим рядом.
## Раскладка ряда: у буквенных клавиш ОДИНАКОВАЯ ширина на всех рядах,
## а сдвиги-соты добираются нестандартной шириной краевых клавиш — как на
## настоящей клавиатуре (ANSI-референс: Tab 1.5u, Caps 1.75u, Shift 2.25u —
## ступеньки буквенных рядов 0.25u и 0.75u; решение 10.2026).
## Русские буквенные ряды (11/11/10+края): питч p = min() из трёх условий —
## й-ряд во всю ширину, стиранию со шифтом хватает минимумов, ф-ряд не
## вылезает за край. Отступы: й 0, ф треть шифта, я весь шифт (пропорция
## Caps-Tab : Shift-Tab = 1:3 с референса). Шифт = отступ (как настоящий
## левый шифт во всю высоту ступени), «стереть» = ровно остаток (≥28px).
## Остальные ряды и слои — по-старому (заливка/центровка): там нет
## буквенных краёв, которым надо держать ступеньку.
static func buttons(area: Rect2, layer: String, lang: String, shift: bool, enter := false) -> Array:
	var rows: Array = all_rows(layer, lang, enter)
	var out: Array = []
	var gap := 8.0
	var rh := (area.size.y - gap * float(rows.size() - 1)) / float(rows.size())
	var ru_letters := lang == "ru"
	var pitch := -1.0
	for row in rows:
		var n1 := 0
		var wide := false
		for label in row:
			if _span(String(label)) != 1.0:
				wide = true
			else:
				n1 += 1
		if n1 <= 0:
			continue
		var u := (area.size.x - gap * float(row.size() - 1)) / float(n1)
		if wide:
			# Ряд со стиранием/шифтом: буквы плюс достойные края.
			u = (area.size.x - gap * float(row.size() - 1) - 64.0) / float(n1)
		if pitch < 0.0:
			pitch = u
		else:
			pitch = minf(pitch, u)
	if pitch < 1.0:
		pitch = 24.0
	# Русские буквенные ряды: общий питч и ступеньки с референса.
	# Русская доска — физическая раскладка: цифры с ё/-/= и стереть
	# сверху справа (как настоящий Backspace), 12 букв, 11 букв + ввод
	# (как настоящий Enter), два шифта. У букв питч один на все ряды;
	# ступеньки ф/я идут от ширины шифтов (1:2, как Tab→Caps→Shift).
	var ru_p := 0.0
	var ru_a := 0.0
	var ru_lr := 0.0
	if ru_letters and rows.size() >= 5:
		var w := area.size.x
		# Питч один на всё, включая цифры: 12 букв, ступеньки ф/я,
		# симметричные шифты от 32px, стереть от 48px.
		ru_p = minf((w - 11.0 * gap) / 12.0, (w - 11.0 * gap - 64.0) / 10.0)
		ru_p = minf(ru_p, (5.0 * w - 55.0 * gap - 192.0) / 56.0)
		ru_p = minf(ru_p, (w - 11.0 * gap - 32.0) / 11.25)
		ru_p = minf(ru_p, (w - 11.0 * gap - 80.0) / 10.0)
		# Ввод не меньше 1.2 питча (жалоба: слишком маленький Enter).
		ru_p = minf(ru_p, (5.0 * w - 55.0 * gap) / 63.2)
		ru_p = maxf(ru_p, 16.0)
		ru_lr = (w - 10.0 * ru_p - 11.0 * gap) * 0.5
		ru_lr = maxf(ru_lr, 32.0)
		ru_a = ru_lr / 3.0
	for ri in rows.size():
		var row: Array = rows[ri]
		var x := area.position.x
		var y := area.position.y + float(ri) * (rh + gap)
		# Русская доска: цифры, 12 букв, 11 букв + ввод, шифты.
		if ru_letters and rows.size() >= 5 and (ri >= 0 and ri <= 3):
			if ri == 0:
				# Цифры своим калибром (их 13 + стереть — в питч букв
				# не влезть), стереть — двойное, как настоящее.
				var ud := (area.size.x - 13.0 * gap) / 15.0
				for label in row:
					var s0 := String(label)
					var w0 := 2.0 * ud if s0 == "←" else ud
					if shift and s0.length() == 1 and s0 != "←":
						s0 = s0.to_upper()
					out.append({"r": Rect2(x, y, w0, rh), "s": s0})
					x += w0 + gap
				continue
			if ri == 1:
				for label in row:
					var s1 := String(label)
					if shift and s1.length() == 1:
						s1 = s1.to_upper()
					out.append({"r": Rect2(x, y, ru_p, rh), "s": s1})
					x += ru_p + gap
				continue
			if ri == 2:
				x += ru_a
				for label in row:
					var s2 := String(label)
					if s2 == "↵":
						continue
					if shift and s2.length() == 1:
						s2 = s2.to_upper()
					out.append({"r": Rect2(x, y, ru_p, rh), "s": s2})
					x += ru_p + gap
				out.append({"r": Rect2(x, y, area.position.x + area.size.x - x, rh), "s": "↵"})
				continue
			if ri == 3:
				# Шифт шириной в ступеньку без зазора: буквы начинаются
				# ровно на ru_lr, шаги 1:2 держатся точно.
				out.append({"r": Rect2(area.position.x, y, ru_lr - gap, rh), "s": "Shift"})
				x += ru_lr
				for label in row:
					var s3 := String(label)
					if s3 == "Shift" or s3 == "ShiftR":
						continue
					if shift and s3.length() == 1:
						s3 = s3.to_upper()
					out.append({"r": Rect2(x, y, ru_p, rh), "s": s3})
					x += ru_p + gap
				out.append({"r": Rect2(x, y, area.position.x + area.size.x - x, rh), "s": "ShiftR"})
				continue
		# Крайние широкие без пробела (шифты/стереть): впитывают остаток.
		var lead := -1
		var trail := -1
		var has_fill := false
		for bi in row.size():
			var sp := _span(String(row[bi]))
			if sp != 1.0 and String(row[bi]) != "пробел":
				if lead < 0:
					lead = bi
				trail = bi
			if String(row[bi]) == "пробел":
				has_fill = true
		if has_fill or lead < 0:
			# Пробел тянется (старый счёт) или ряд чисто из одиночных:
			# остаток (если есть) — поровну по бокам.
			var total_units := 0.0
			for label in row:
				total_units += _span(String(label))
			if has_fill:
				var unit := (area.size.x - gap * float(row.size() - 1)) / total_units
				for label in row:
					var w0 := unit * _span(String(label))
					var s0 := String(label)
					if shift and s0.length() == 1 and s0 != "←" and s0 != "Shift" and s0 != "ShiftR":
						s0 = s0.to_upper()
					out.append({"r": Rect2(x, y, w0, rh), "s": s0})
					x += w0 + gap
			else:
				var n1b := row.size()
				var left := (area.size.x - (float(n1b) * pitch + gap * float(n1b - 1))) * 0.5
				x += left
				for label in row:
					var s1 := String(label)
					if shift and s1.length() == 1 and s1 != "←" and s1 != "Shift" and s1 != "ShiftR":
						s1 = s1.to_upper()
					out.append({"r": Rect2(x, y, pitch, rh), "s": s1})
					x += pitch + gap
			continue
		# Ряд со стиранием/шифтом: одиночные — питчем, края — остатком.
		var singles := 0
		for label in row:
			if _span(String(label)) == 1.0:
				singles += 1
		var rest := area.size.x - (float(singles) * pitch + gap * float(row.size() - 1))
		var widths := []
		for bi in row.size():
			var lab := String(row[bi])
			if _span(lab) == 1.0:
				widths.append(pitch)
			elif bi == lead:
				widths.append(maxf(rest - 32.0, 32.0))
			else:
				widths.append(32.0)
		for bi in row.size():
			var s := String(row[bi])
			if shift and s.length() == 1 and s != "←" and s != "Shift" and s != "ShiftR":
				s = s.to_upper()
			out.append({"r": Rect2(x, y, float(widths[bi]), rh), "s": s})
			x += float(widths[bi]) + gap
	return out


## Тап по клавиатуре: "" — мимо, иначе действие ("стереть", "шифт",
## "ввод", "язык", "пробел", символ). Слоя ?123 больше нет.
static func hit(area: Rect2, layer: String, lang: String, shift: bool, enter: bool, pos: Vector2) -> String:
	for b in buttons(area, layer, lang, shift, enter):
		if (b["r"] as Rect2).has_point(pos):
			var s := String(b["s"])
			if s == "←":
				return "стереть"
			if s == "Shift" or s == "ShiftR":
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
	enter: bool, font: Font, fs: int, sb: StyleBox, sb_on: StyleBox, ink: Color,
	hi: Array = [], hi_sb: StyleBox = null, ink_dim: Color = Color(0, 0, 0, 0)
) -> void:
	# hi — подписи клавиш, которые игра подсвечивает после простоя
	# (вместо текстовой подсказки «Нажми К»). hi_sb рисует их вызыватель
	# и сам же в нём ведёт пульсацию цветом каждый кадр. Запись вида
	# «пробел:Л»/«пробел:П» подсвечивает половину пробела (палец
	# противоположной руки) с мягкой градиентной границей.
	# ink_dim — приглушённые чернила для неактивных подписей: у каждой
	# буквы напечатаны обе раскладки, активная светится ярче.
	var gap := 8.0
	var rh := (area.size.y - gap * 4.0) / 5.0
	var key_fs := maxi(fs, int(rh * 0.40))
	var sub_fs := maxi(int(float(fs) * 0.55), int(rh * 0.22))
	var dim := ink_dim if ink_dim.a > 0.0 else ink
	for b in buttons(area, layer, lang, shift, enter):
		var r := b["r"] as Rect2
		var s := String(b["s"])
		var box := sb_on if (s == "Shift" or s == "ShiftR") and shift else sb
		var hi_side := _hi_side_for(s, hi)
		var exact := hi_sb != null and s in hi
		if exact:
			box = hi_sb
		ci.draw_style_box(box, r)
		if hi_sb != null and not exact and hi_side != "" and s == "пробел":
			_draw_half(ci, r, hi_side, hi_sb)
		if s == "глобус":
			_draw_globe(ci, r.get_center(), minf(r.size.x, r.size.y) * 0.30, ink)
			continue
		var shown := s
		if s == "ShiftR":
			shown = "Shift"
		var f := key_fs
		if s == "пробел":
			f = maxi(int(float(fs) * 0.75), int(rh * 0.24))
		if s == "Shift" or s == "ShiftR":
			# «Shift» обязано влезать в узкую клавишу (на маленьком экране
			# шифт едва шире пальца): кегль ужимается под ширину.
			while f > 10:
				var probe := font.get_string_size(shown, HORIZONTAL_ALIGNMENT_LEFT, -1.0, f).x
				if probe <= r.size.x - 12.0:
					break
				f -= 2
		var tw := font.get_string_size(shown, HORIZONTAL_ALIGNMENT_LEFT, -1.0, f).x
		var th := font.get_height(f)
		ci.draw_string(
			font,
			Vector2(r.get_center().x - tw * 0.5, r.get_center().y + float(th) * 0.3),
			" " if s == "пробел" else shown,
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, f, ink
		)
		# Вторая подпись клавиши: пара из другой раскладки (у букв) или
		# знак с шифтом (у цифр). Активная светится ярче.
		var sub := ""
		var sub_on := false
		var pair := pair_of(s)
		if pair != "" and s.length() == 1:
			sub = pair
			# Активна та раскладка, чей язык включён.
			var ru := (s >= "а" and s <= "я") or s == "ё" or (s >= "А" and s <= "Я") or s == "Ё"
			sub_on = (lang != "ru") if ru else (lang == "ru")
		elif s.length() == 1:
			var sym := shift_digit(s)
			if sym != "":
				sub = sym
				sub_on = shift
		if sub != "":
			var stw := font.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1.0, sub_fs).x
			ci.draw_string(
				font,
				Vector2(r.end.x - stw - 7.0, r.position.y + float(font.get_height(sub_fs)) * 0.85),
				sub, HORIZONTAL_ALIGNMENT_LEFT, -1.0, sub_fs,
				ink if sub_on else dim
			)


## Сторона подсветки для клавиши: «Л»/«П» из записи «подпись:Л/П»,
## иначе пусто (совпадение без суффикса красит всю клавишу).
static func _hi_side_for(s: String, hi: Array) -> String:
	for h in hi:
		var hs := String(h)
		if hs.begins_with(s + ":"):
			return hs.get_slice(":", 1)
	return ""


## Половина пробела с мягкой границей: залитая половина плюс градиентная
## полоса в сторону другой (6 полосок с падающей прозрачностью).
static func _draw_half(ci: CanvasItem, r: Rect2, side: String, sb: StyleBox) -> void:
	var half := r.size.x * 0.5
	var base := Color(1, 1, 1)
	if sb is StyleBoxFlat:
		base = (sb as StyleBoxFlat).bg_color
	if side == "Л":
		ci.draw_style_box(sb, Rect2(r.position.x, r.position.y, half, r.size.y))
		for i in 6:
			var t := float(i) / 6.0
			var c := base
			c.a *= (1.0 - t) * 0.6
			var w := 22.0 / 6.0
			ci.draw_rect(Rect2(r.position.x + half + float(i) * w, r.position.y, w + 1.0, r.size.y), c)
	else:
		ci.draw_style_box(sb, Rect2(r.position.x + half, r.position.y, half, r.size.y))
		for i in 6:
			var t := float(i) / 6.0
			var c := base
			c.a *= (1.0 - t) * 0.6
			var w := 22.0 / 6.0
			ci.draw_rect(Rect2(r.position.x + half - (float(i) + 1.0) * w, r.position.y, w + 1.0, r.size.y), c)


## Глобус кнопки языка: круг, вертикальный меридиан-эллипс и горизонталь.
static func _draw_globe(ci: CanvasItem, c: Vector2, rad: float, ink: Color) -> void:
	ci.draw_arc(c, rad, 0.0, TAU, 32, ink, 2.5)
	var pts := PackedVector2Array()
	for i in 17:
		var a := float(i) / 16.0 * TAU
		pts.append(c + Vector2(cos(a) * rad * 0.45, sin(a) * rad))
	ci.draw_polyline(pts, ink, 2.0)
	ci.draw_line(c + Vector2(-rad, 0.0), c + Vector2(rad, 0.0), ink, 2.0)
