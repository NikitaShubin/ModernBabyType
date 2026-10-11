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
## Ключ слева от правого шифта — знаковый: в русской раскладке он «,» и
## «?», в английской «/» и «\» (четыре знака на одной клавише, как на
## настоящей — требование автора 10.2026).
const ROWS_RU: Array = [
	["й", "ц", "у", "к", "е", "н", "г", "ш", "щ", "з", "х", "ъ", "\\"],
	["ф", "ы", "в", "а", "п", "р", "о", "л", "д", "ж", "э", "↵"],
	["Shift", "я", "ч", "с", "м", "и", "т", "ь", "б", "ю", ".", "ShiftR"],
]

## Отдельных латинских рядов больше нет: доска одна (русская физическая),
## а латиница набирается теми же клавишами (см. пару RU_EN и kb_lang).

## Низ доски: язык, пробел и служебные клавиши настоящей клавиатуры.
## Слева Ctrl, Win, Alt — как на PC; справа от пробела Alt и Ctrl, как
## на настоящей (требование автора 10.2026). Всё это в наборе не
## участвует: подпись приглушена, нажатие мимо. В меню последней
## клавишей вместо Ctrl — ввод (↵): имя надо чем-то заканчивать.
static func bottom_row(enter: bool) -> Array:
	if enter:
		return ["Ctrl", "Win", "Alt", "глобус", "пробел", "Alt", "↵"]
	return ["Ctrl", "Win", "Alt", "глобус", "пробел", "Alt", "Ctrl"]


## Знаки с цифр в русской раскладке (ЙЦУКЕН, «Русская» в Windows):
## 1→! 2→" 3→№ 4→; 5→% 6→: 7→? 8→* 9→( 0→) -→_ =→+
const RU_SHIFT := {
	"1": "!", "2": "\"", "3": "№", "4": ";", "5": "%",
	"6": ":", "7": "?", "8": "*", "9": "(", "0": ")",
	"-": "_", "=": "+",
}

## Те же клавиши в английской: часть символов совпадает, часть другая
## (2→@ 3→# 4→$ 6→^ 7→&) — из-за этого на цифровой клавише три знака.
const EN_SHIFT := {
	"1": "!", "2": "@", "3": "#", "4": "$", "5": "%",
	"6": "^", "7": "&", "8": "*", "9": "(", "0": ")",
	"-": "_", "=": "+",
}

## Клавиши, где русский знак не совпадает с английским. Таблица взята
## не из головы: скомпилированная карта этой машины
## (`xkbcomp -xkb` для pc+ru(winkeys) — раскладка «Русская», ровно та,
## что в Windows). Из неё: клавиша прямого слеша — ТРЕТЬЯ В ВЕРХНЕМ
## БУКВЕННОМ РЯДУ, сразу после «ъ» (в английской на ней «\\» и «|»);
## клавиша слева от правого шифта — точка и запятая (в английской «/»
## и «?»). Двух слешей на одной клавиши быть не может — автор на это
## указал (10.2026), и таблица это подтверждает.
## Порядок: [русская, русская+шифт, английская, английская+шифт].
const OVERLOAD := {
	".": [".", ",", "/", "?"],
	"\\": ["\\", "/", "\\", "|"],
}

## Знаки с шифтом у тех клавиш, чья пара в английской раскладке — сама
## пунктуация (на настоящей: { выше [, } выше ], : выше ;, " выше ',
## < выше ,, > выше .). Для букв это заглавная, и там to_upper() достаёт.
const US_SHIFT := {
	"[": "{", "]": "}", ";": ":", "'": "\"", ",": "<", ".": ">",
	"/": "?", "\\": "|", "`": "~",
}


## Легенды клавиши: [русская, русская+шифт, английская, английская+шифт].
## Настоящая раскладка, а не придумка: у цифр часть знаков с шифтом в
## двух языках разная (2 → " / @, 3 → № / #, 4 → ; / $, 6 → : / ^,
## 7 → ? / &), поэтому на клавише три знака, а не два (требование
## автора 10.2026). У букв это заглавные + пара раскладки.
static func legends(s: String) -> Array:
	if OVERLOAD.has(s):
		return Array(OVERLOAD[s])
	if RU_SHIFT.has(s):
		return [s, String(RU_SHIFT[s]), s, String(EN_SHIFT[s])]
	var pair := pair_of(s)
	if pair != "" and s.length() == 1:
		return [s, s.to_upper(), pair, String(US_SHIFT.get(pair, pair.to_upper()))]
	return []


## Что введёт нажатие этой клавиши при данном языке и шифте. Пустая
## строка — служебная клавиша (Shift, ↵, ←, глобус, Ctrl…): её разбирает
## вызывающий.
static func press_out(s: String, lang: String, shift: bool) -> String:
	var lg := legends(s)
	if lg.is_empty():
		return ""
	return String(lg[(2 if lang == "en" else 0) + (1 if shift else 0)])


## Чем набрать знак: [клавиша, нужен_шифт, язык]. Пусто — нечем набрать.
## Язык может отличаться от текущего: подсказка тогда сначала зовёт глобус,
## а потом уже клавишу (знаки вроде «?» живут в чужой раскладке).
## Сначала ищем в том языке, который включён — так подсказка выбирает
## привычную руке комбинацию, а не единственную.
static func combo_for(sym: String, prefer := "ru") -> Array:
	if sym == "":
		return []
	var other := "en" if prefer == "ru" else "ru"
	for want in [prefer, other]:
		# Сначала без шифта: запятая — это своя клавиша, а не Shift+б
		# (хотя и так можно). Потом с шифтом.
		var idx := [0, 1] if want == "ru" else [2, 3]
		for i in idx:
			for row in all_rows(false):
				for label in row:
					var lg := legends(String(label))
					# Служебные клавиши (шифт, пробел, глобус, Ctrl) легенд
					# не имеют — их пропускаем, а не читаем по индексу.
					if lg.size() <= i:
						continue
					if String(lg[i]) == sym:
						return [String(label), i % 2 == 1, want]
	return []


## Мелкие подписи на клавише: все легенды, кроме активной. У букв —
## только основания обеих раскладок (заглавные не мельчат: шифт и так
## виден на доске), у знаков — все, их бывает по четыре.
static func small_legends(s: String, lang: String, shift: bool) -> Array:
	var lg := legends(s)
	if lg.is_empty():
		return []
	var act := press_out(s, lang, shift)
	var cands: Array = [lg[0], lg[2]] if _is_letter_key(s) else lg
	var out: Array = []
	for v in cands:
		var t := String(v)
		if t != act and not out.has(t):
			out.append(t)
	return out


## Должна ли клавиша перелетать? Смена раскладки — все клавиши. А вот
## щипок шифта — только знаки: у буквы большой и малый варианты не разные
## знаки, мягкого перехода между ними нет (автор 10.2026: «анимация не
## нужна при нажатии шифта в случае букв… в случае всех остальных знаков —
## всё как обычно»).
static func animates(s: String, from_lang: String, from_shift: bool, to_lang: String) -> bool:
	if from_lang == "":
		return false
	return not (from_lang == to_lang and _is_letter_key(s))


## Буквенная клавиша (у неё пара раскладок, а не набор знаков).
static func _is_letter_key(s: String) -> bool:
	return s.length() == 1 and pair_of(s) != ""


## Свой угол знака: по РОЛИ в легендах, а не по месту в списке мелких.
## Иначе все буквы делят один угол (автор 10.2026: «у каждого знака на
## клавише свой угол, и она должна из него выходить в центр и
## возвращаться назад в свой угол»). Углы: 0 — левый верхний,
## 1 — правый верхний, 2 — левый нижний, 3 — правый нижний.
## У буквенных клавиш рисуются только основания двух раскладок:
## русская — в левом верхнем, латинская — в левом нижнем.
static func corner_for(s: String, sym: String) -> int:
	if sym == "":
		return 0
	var lg := legends(s)
	if lg.is_empty():
		return 0
	if _is_letter_key(s):
		return 0 if String(lg[0]) == sym else 2
	var i := lg.find(sym)
	return i if i >= 0 else 0


## Все ряды слоя сверху вниз (цифры + верх + низ).
static func all_rows(enter: bool) -> Array:
	var rows: Array = []
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


## Обычная буква или пробел — на буквенном слое есть всегда, проверять
## нечего. Знаки сюда не относятся: на буквенных клавишах их нет, они
## живут на цифрах и на ключе слева от правого шифта (см. combo_for).
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


## Широкие кнопки (долей ширины ряда): пробел тройной, шифт
## и стереть полуторные (как у Яндекс-клавиатуры), остальные обычные.
## Клавиш питчем в ряду: всё, кроме широких служебных (шифты, стереть,
## пробел) и ввода — ввод получает остаток ряда, а не питч.
static func _plain_count(row: Array) -> int:
	var n := 0
	for label in row:
		var s := String(label)
		if s == "↵" or _span(s) != 1.0:
			continue
		n += 1
	return n


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
static func buttons(area: Rect2, shift: bool, enter := false) -> Array:
	var rows: Array = all_rows(enter)
	var out: Array = []
	var gap := 8.0
	var rh := (area.size.y - gap * float(rows.size() - 1)) / float(rows.size())
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
	if rows.size() >= 5:
		var w := area.size.x
		# Сколько клавиш питчем в каждом ряду — считаем по САМИМ рядам,
		# а не константами: после правок раскладки (клавиша слеша слева
		# от ввода) константы разъехались и ввод схлопнулся в 7px.
		var n1 := _plain_count(rows[1])
		var n2 := _plain_count(rows[2])
		var n3 := _plain_count(rows[3])
		# Верхний буквенный ряд: питчем влезает целиком.
		ru_p = (w - float(n1) * gap) / float(n1)
		# Средний ряд и низ: ступенька слева, n2 клавиш питчем, ввод не
		# меньше 1.2 питча, шифты делят остаток пополам. Из этого:
		# p ≤ (5w − (6·n2 − n3)·gap) / (6·n2 − n3 + 7.2).
		var k := 6.0 * float(n2) - float(n3)
		ru_p = minf(ru_p, (5.0 * w - k * gap) / (k + 7.2))
		ru_p = maxf(ru_p, 16.0)
		ru_lr = maxf((w - float(n3) * (ru_p + gap)) * 0.5, 32.0)
		ru_a = ru_lr / 3.0
	for ri in rows.size():
		var row: Array = rows[ri]
		var x := area.position.x
		var y := area.position.y + float(ri) * (rh + gap)
		# Русская доска: цифры, 12 букв, 11 букв + ввод, шифты.
		if rows.size() >= 5 and (ri >= 0 and ri <= 3):
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
static func hit(area: Rect2, shift: bool, enter: bool, pos: Vector2) -> String:
	for b in buttons(area, shift, enter):
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
			if s == "Ctrl" or s == "Win" or s == "Alt":
				return ""
			return s
	return ""


## Нарисовать кнопки на канве вызывателя. Шрифт и стиль — вызывателя.
## Кегль — от высоты ряда (палец!), служебные чуть мельче. Глобус —
## векторный (круг + меридиан): шрифтового эмодзи в DejaVu нет.
## shift_on подсвечивает шифт заливкой (второй стиль вызывателя).
static func draw(
	ci: CanvasItem, area: Rect2, lang: String, shift: bool,
	enter: bool, font: Font, fs: int, sb: StyleBox, sb_on: StyleBox, ink: Color,
	hi: Array = [], hi_sb: StyleBox = null, ink_dim: Color = Color(0, 0, 0, 0),
	morph := 1.0, morph_from := "", morph_shift := false
) -> void:
	# hi — подписи клавиш, которые игра подсвечивает после простоя
	# (вместо текстовой подсказки «Нажми К»). hi_sb рисует их вызыватель
	# и сам же в нём ведёт пульсацию цветом каждый кадр. Запись вида
	# «пробел:Л»/«пробел:П» подсвечивает половину пробела (палец
	# противоположной руки) с мягкой градиентной границей.
	# ink_dim — приглушённые чернила для неактивных подписей: у каждой
	# буквы напечатаны обе раскладки, активная светится ярче.
	# morph (0..1), morph_from и morph_shift — перелёт: старая
	# центральная подпись уходит в свой угол, новая выходит из своего
	# в центр (требование автора 10.2026). morph_from пустой или
	# morph = 1 — перелёта нет. На щипке шифта буквы перелёта не имеют
	# (автор: между большой и малой нет мягкого перехода) — знаки
	# перелетают как обычно.
	var gap := 8.0
	var rh := (area.size.y - gap * 4.0) / 5.0
	var key_fs := maxi(fs, int(rh * 0.40))
	var sub_fs := maxi(int(float(fs) * 0.55), int(rh * 0.22))
	var dim := ink_dim if ink_dim.a > 0.0 else ink
	for b in buttons(area, shift, enter):
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
		if shown.length() > 1:
			# Слова на служебных клавишах (Shift, Ctrl, Win, Alt) обязаны
			# влезать в узкую клавишу: на маленьком экране шифт едва шире
			# пальца, а «Ctrl» ещё и обрезался краем экрана.
			while f > 10:
				var probe := font.get_string_size(shown, HORIZONTAL_ALIGNMENT_LEFT, -1.0, f).x
				if probe <= r.size.x - 12.0:
					break
				f -= 2
		# Клавиша со знаками: по центру — та, что вводится сейчас (язык
		# и шифт), по углам мелко — остальные. При смене языка центральная
		# подпись меняется местами с угловой (требование автора 10.2026:
		# раньше по центру всегда стояла русская буква).
		if not legends(s).is_empty():
			# У букв второй раскладки почти тот же размер, как у первой
			# (на настоящей клавиатуре они напечатаны одинаково), у знаков
			# — мельче: их на клавише по три-четыре.
			if pair_of(s) != "" and s.length() == 1:
				sub_fs = maxi(int(float(f) * 0.66), int(rh * 0.24))
			_draw_legends(ci, r, font, s, lang, shift, f, sub_fs, ink, dim, morph, morph_from, morph_shift)
			continue
		# Служебная клавиша: одна подпись по центру. Заблокированные
		# (Ctrl/Win/Alt) в наборе не участвуют — приглушены, чтобы не
		# звать палец.
		var tw := font.get_string_size(shown, HORIZONTAL_ALIGNMENT_LEFT, -1.0, f).x
		var th := font.get_height(f)
		var blocked := s == "Ctrl" or s == "Win" or s == "Alt"
		ci.draw_string(
			font,
			Vector2(r.get_center().x - tw * 0.5, r.get_center().y + float(th) * 0.3),
			" " if s == "пробел" else shown,
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, f, dim if blocked else ink
		)


## Подписи клавиши со знаками: активная — по центру крупно, остальные
## по трём углам мелко и приглушённо (на настоящей клавиатуре на
## клавише тоже несколько знаков: у цифр три, у ключа слева от правого
## шифта четыре). Кегль каждой ужимается под свой угол, иначе знак
## вылез бы за клавишу.
static func _draw_legends(
	ci: CanvasItem, r: Rect2, font: Font, s: String, lang: String, shift: bool,
	f: int, sub_fs: int, ink: Color, dim: Color, morph := 1.0, morph_from := "",
	morph_shift := false
) -> void:
	var main := press_out(s, lang, shift)
	if morph < 1.0 and morph_from != "":
		if animates(s, morph_from, morph_shift, lang) and _draw_morph(
			ci, r, font, s, lang, shift, f, sub_fs, ink, dim, morph, morph_from,
			morph_shift
		):
			return
	var tw := font.get_string_size(main, HORIZONTAL_ALIGNMENT_LEFT, -1.0, f).x
	ci.draw_string(
		font,
		Vector2(r.get_center().x - tw * 0.5, r.get_center().y + float(font.get_height(f)) * 0.3),
		main, HORIZONTAL_ALIGNMENT_LEFT, -1.0, f, ink
	)
	var smalls := small_legends(s, lang, shift)
	for i in smalls.size():
		var t := String(smalls[i])
		var zone := _corner(r, corner_for(s, t))
		var sf := sub_fs
		while sf > 8 and font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1.0, sf).x > zone.size.x:
			sf -= 1
		var w := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1.0, sf).x
		ci.draw_string(
			font, Vector2(zone.get_center().x - w * 0.5, zone.get_center().y + float(font.get_height(sf)) * 0.3),
			t, HORIZONTAL_ALIGNMENT_LEFT, -1.0, sf, dim
		)


## Перелёт при смене языка: старая центральная подпись уменьшается,
## тускнеет и уходит в свой угол, новая выходит из другого угла,
## растёт и ярчает до центра. Возвращает true, если перелёт был (тогда
## обычный рисунок не рисуется). Ключи, у которых подпись не меняется
## (цифры: «2» и в русской, и в английской даёт «2»), перелёта не
## имеют. Смена регистра сюда не попадает: вызывающий не запускает
## перелёт на щипке шифта (требование автора 10.2026).
static func _draw_morph(
	ci: CanvasItem, r: Rect2, font: Font, s: String, lang: String, shift: bool,
	f: int, sub_fs: int, ink: Color, dim: Color, morph: float, morph_from: String,
	morph_shift: bool
) -> bool:
	var old_main := press_out(s, morph_from, morph_shift)
	var main := press_out(s, lang, shift)
	if old_main == main:
		return false
	var center := r.get_center()
	# У каждого знака свой угол по роли в легендах (см. corner_for):
	# уходящая уходит в свой, приходящая выходит из своего — в полёте
	# они не накладываются, и каждая возвращается туда же.
	var from_corner := _corner(r, corner_for(s, main))
	var to_corner := _corner(r, corner_for(s, old_main)).get_center()
	_draw_glyph(ci, font, old_main, center.lerp(to_corner, morph),
		lerpf(float(f), float(sub_fs), morph), ink.lerp(dim, morph))
	_draw_glyph(ci, font, main, from_corner.get_center().lerp(center, morph),
		lerpf(float(sub_fs), float(f), morph), dim.lerp(ink, morph))
	return true


## Глиф по центру точки, кеглем и чернилами на выбор.
static func _draw_glyph(
	ci: CanvasItem, font: Font, txt: String, at: Vector2, f: float, col: Color
) -> void:
	var fi := int(f)
	var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fi).x
	ci.draw_string(
		font, Vector2(at.x - w * 0.5, at.y + float(font.get_height(fi)) * 0.3),
		txt, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fi, col
	)


## Зона угловой подписи: четыре угла, как на настоящей клавише. Места
## под центральную подпись не режем.
static func _corner(r: Rect2, i: int) -> Rect2:
	var pad := 3.0
	var w := r.size.x * 0.34
	var h := r.size.y * 0.30
	match i:
		1:
			return Rect2(r.end.x - w - pad, r.position.y + pad, w, h)
		2:
			return Rect2(r.position.x + pad, r.end.y - h - pad, w, h)
		3:
			return Rect2(r.end.x - w - pad, r.end.y - h - pad, w, h)
	return Rect2(r.position.x + pad, r.position.y + pad, w, h)


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
