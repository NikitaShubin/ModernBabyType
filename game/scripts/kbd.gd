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
const ROW_DIGITS_RU: Array = ["ё", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "=", "←"]

## Ряды русских букв — как на настоящей клавиатуре: «ъ» справа от «х»,
## ввод справа от «э» (как настоящий Enter), два шифта по бокам нижнего
## ряда. Отдельных клавиш Tab/Caps/Enter-слева нет (им нечего делать в
## игре), поэтому ступеньки идут от края — честная адаптация narrow-рядов,
## а не копия вслепую.
## Ключ слева от правого шифта — знаковый: в русской раскладке он «,» и
## «?», в английской «/» и «\» (четыре знака на одной клавише, как на
## настоящей — требование автора 10.2026).
const ROWS_RU: Array = [
	["Tab", "й", "ц", "у", "к", "е", "н", "г", "ш", "щ", "з", "х", "ъ", "\\"],
	["Caps", "ф", "ы", "в", "а", "п", "р", "о", "л", "д", "ж", "э", "↵"],
	["Shift", "я", "ч", "с", "м", "и", "т", "ь", "б", "ю", ".", "ShiftR"],
]

## Отдельных латинских рядов больше нет: доска одна (русская физическая),
## а латиница набирается теми же клавишами (см. пару RU_EN и kb_lang).

## Низ доски: язык, пробел и служебные клавиши настоящей клавиатуры.
## Слева Ctrl, Win, Alt — как на PC; справа от пробела Alt и Ctrl, как
## на настоящей (требование автора 10.2026). Всё это в наборе не
## участвует: подпись приглушена, нажатие мимо. В меню последней
## клавишей вместо Ctrl — ввод (↵): имя надо чем-то заканчивать.
static func bottom_row(_enter: bool) -> Array:
	# Глобус — между правыми Alt и Ctrl (автор 10.2026).
	return ["Ctrl", "Win", "Alt", "пробел", "Alt", "глобус", "Ctrl"]


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
##
## Результат ЗАПОМИНЕН: функция чистая, а её зовут ~60 раз на кадр
## (каждая клавиша доски), и каждый вызов рождал массив из четырёх
## строк с новыми to_upper() — мусор в куче на каждом кадре (ревизия
## 16.10.2026). Набор подписей фиксирован, кэш не растёт. Никто
## результат не меняет — все только читают.
static var _legends_cache: Dictionary = {}
## Счётчики для perf_test: промахи кэшей. Их должно быть по чуть-чуть
## на кадр, а не по шестьдесят (ревизия 16.10.2026): доска зовётся и на
## рисовании, и на тапе, но чистый результат считается один раз.
static var legends_misses := 0
static var buttons_misses := 0


static func legends(s: String) -> Array:
	if _legends_cache.has(s):
		return _legends_cache[s]
	legends_misses += 1
	var out: Array = []
	if OVERLOAD.has(s):
		out = Array(OVERLOAD[s])
	elif RU_SHIFT.has(s):
		out = [s, String(RU_SHIFT[s]), s, String(EN_SHIFT[s])]
	else:
		var pair := pair_of(s)
		if pair != "" and s.length() == 1:
			out = [s, s.to_upper(), pair, String(US_SHIFT.get(pair, pair.to_upper()))]
	_legends_cache[s] = out
	return out


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


const ROW_TALL := 1.15



## ── Механика раскладки подписи ──────────────────────────────────────────
## Одно правило на все случаи (автор 10.2026: «универсальную механику
## прописать для любого положения знака в пределах кнопки, чтобы движение
## было единым»). У каждого знака клавиши ровно один ДОМ из девяти мест:
## углы tl tr br bl, края t b l r, центр c (автор 10.2026: «у каждой кнопки
## своё место… пусть 9»). Дом — только функция от самого знака (таблицы
## CORNERS и EDGE, иначе роль в легендах): ни язык, ни шифт, ни морф дом
## не двигают, так что подпись не может уехать в чужой угол. Набираемая
## сейчас подпись стоит в ЦЕНТРЕ, и в своём доме её нет: уехала в центр —
## в углу её не должно быть. Регистр в дом не идёт: это та же подпись
## крупно, на настоящем колпачке «Ц» не написано. Смена того, что
## набирается, — единственное движение: прежняя уходит из центра в свой
## дом, новая выходит из своего дома в центр. Прямая, одна на все знаки.
## Исключений для отдельных клавиш нет: «-_» и «+=» живут в краевых домах
## t/b той же таблицей EDGE и летят тем же перелётом.

## Подписи, которые печатаются по своим домам: всё, кроме набираемой
## сейчас, её регистра и регистров вообще.
static func small_legends(s: String, lang: String, shift: bool) -> Array:
	var lg := legends(s)
	if lg.is_empty():
		return []
	var act := press_out(s, lang, shift)
	var out: Array = []
	for v in lg:
		var t := String(v)
		if t == "" or out.has(t) or _case_of(t, lg) or _twin(t, act):
			continue
		out.append(t)
	return out


## Регистр другой подписи той же клавиши: «Ф» — это «ф» покрупнее.
static func _case_of(t: String, lg: Array) -> bool:
	for w in lg:
		var u := String(w)
		if u != t and u.to_upper() == t:
			return true
	return false


## Та же буква, что и набираемая, но в другом регистре. В угол такая не
## идёт: в моноширинном шрифте «ц» и «Ц» не отличить, и на клавише
## оказываются две одинаковые буквы (автор 10.2026: «некоторые остаются
## одновременно даже после анимации»).
static func _twin(t: String, act: String) -> bool:
	if act == "" or t.length() != act.length():
		return false
	return t.to_lower() == act.to_lower()


## Презентация подписи в покое: [точка, кегль]. Набираемая — в центре
## (у столбика чуть меньше и с оптическим подъёмом подчёрка), остальные —
## по домам мелко. Полёт идёт ровно между этими же презентациями: концы
## перелёта совпадают с покоем до и после, и знак не скачет (автор 10.2026:
## «-_ и =+ двигаются не анимацией, а скачком»).
static func _rest(s: String, r: Rect2, font: Font, t: String, main: String, f: int, sub_fs: int) -> Array:
	if t == main:
		var ff := float(f)
		var at := r.get_center()
		if t == "_":
			# Подчёрк висит на базовой линии и тела выше неё не имеет: с
			# якорем ровно в центре он читается «ниже центра». Это свойство
			# самого знака, а не клавиши: подъём действует везде одинаково.
			at.y -= float(font.get_height(int(ff))) * 0.3
		return [at, ff]
	return [home(r, s, t), float(sub_fs)]


## Дом подписи на клавише — одна из восьми точек (см. corner_for).
## Только функция от самого знака: ни язык, ни шифт, ни морф дом не
## двигают.
static func home(r: Rect2, s: String, sym: String) -> Vector2:
	return _corner(r, corner_for(s, sym)).get_center()


## Должна ли подпись перелетать. Смена раскладки — все клавиши. А вот
## щипок шифта — только знаки: у буквы большая и малая не разные знаки
## (автор 10.2026: «анимация не нужна при нажатии шифта в случае букв»).
## У столбиковых клавиш домов-углов нет, лететь некуда.
## Летит ли подпись. Смена раскладки — летят все знаки. Щипок шифта —
## летит, только если меняется сам знак: ф↔Ф — не смена знака (та же буква
## крупно, автор 10.2026: «анимация не нужна при нажатии шифта в случае
## букв»), а [↔{, ,↔<, `↔~ — смена, и она летит, как все знаки. Раньше
## правило смотрело только на клавишу (буквенная — не летит), и в
## английской раскладке пары знаков менялись скачком (тест
## _shift_edges_static это поймал, автор 10.2026).
static func animates(s: String, from_lang: String, from_shift: bool, to_lang: String, to_shift: bool) -> bool:
	if from_lang == "":
		return false
	if from_lang != to_lang:
		return true
	if from_shift == to_shift:
		return false
	var was := press_out(s, from_lang, from_shift)
	var now := press_out(s, to_lang, to_shift)
	if was == now:
		return false
	if _is_letter_key(s) and _twin(was, now):
		return false
	return true


## Буквенная клавиша (у неё пара раскладок, а не набор знаков). Смотрим
## на СВОИ легенды, а не на `pair_of`: точка с запятой тоже с кем-то
## спарена (с «ю» — это её место в ЙЦУКЕНе), но на клавише знаки, а не
## буквы, и щипок шифта на ней перелёт запускает.
static func _is_letter_key(s: String) -> bool:
	if s.length() != 1:
		return false
	var lg := legends(s)
	if lg.size() < 2:
		return false
	return is_plain_letter(String(lg[0])) and String(lg[1]) == String(lg[0]).to_upper()


## Углы знаков по ТЗ автора (10.2026), заданы строкой из четырёх
## символов: 1 — левый верхний, 2 — правый верхний, 3 — левый нижний,
## 4 — правый нижний, пробел — знака на этом углу нет.
const CORNERS: Dictionary = {
	"1": "! 1 ", "2": "@ 2\"", "3": "# 3№", "4": "$ 4;", "5": "% 5 ",
	"6": "^ 6:", "7": "& 7?", "8": "* 8 ", "9": "( 9 ", "0": ") 0 ",
	".": "?,/.", "ё": "~ `ё",
	"б": "< ,б", "ю": "> .ю", "ж": ": ;ж", "э": "\" 'э",
	"х": "{ [х", "ъ": "} ]ъ",
}
## Номер угла автора → наш угол: 0 — левый верхний, 1 — правый верхний,
## 2 — правый нижний, 3 — левый нижний.
const CORNER_ID: Array[int] = [0, 1, 3, 2]

## Краевые дома: знаки, живущие не в углу, а по центру края. Клавиши
## «-_» и «+=» стоят столбиком (автор 10.2026: «два знака — один строго
## под другим, выравнивание по центру»): знак с шифтом — верхняя середина,
## основа — нижняя. Нумерация домов единая: 0 ЛВ, 1 ПВ, 2 ПН, 3 ЛН (углы),
## 4 верх, 5 низ, 6 лево, 7 право (края).
const EDGE := {"-": {"_": 4, "-": 5}, "=": {"+": 4, "=": 5}}


## Свой угол знака: по ТЗ автора строкой из CORNERS, иначе по РОЛИ в
## легендах. И то и другое — только функция от самого знака, поэтому
## подпись, став пассивной, возвращается в свой угол, а не в чужой.
static func corner_for(s: String, sym: String) -> int:
	if sym == "":
		return 0
	if EDGE.has(s):
		var slots: Dictionary = EDGE[s]
		if slots.has(sym):
			return int(slots[sym])
	var row: String = String(CORNERS.get(s, ""))
	if row.length() == 4:
		var i := row.find(sym)
		if i >= 0:
			return CORNER_ID[i]
	var lg := legends(s)
	if lg.is_empty():
		return 0
	if _is_letter_key(s):
		# Индекс 2 — английская основа (левый верхний), 0 — русская
		# (правый нижний).
		return 0 if String(lg[2]) == sym else 2
	# Роль знака → угол: русская основа (0) — правый нижний, русский
	# шифт (1) — правый верхний, английская основа (2) — левый верхний,
	# английский шифт (3) — левый нижний.
	var i := lg.find(sym)
	match i:
		0:
			return 2
		1:
			return 1
		3:
			return 3
		2:
			return 0
	return 0


## Рисунок клавиши: печать по домам, набираемая подпись в центре, и —
## если набираемое сменилось — две подписи, идущие дом↔центр.
static func _draw_legends(
	ci: CanvasItem, r: Rect2, font: Font, s: String, lang: String, shift: bool,
	f: int, sub_fs: int, ink: Color, dim: Color, morph := 1.0, morph_from := "",
	morph_shift := false
) -> void:
	var main := press_out(s, lang, shift)
	# Кто улетает, — один раз на кадр, дальше движение единое.
	var away := ""
	if morph < 1.0 and morph_from != "" and animates(s, morph_from, morph_shift, lang, shift):
		var was := press_out(s, morph_from, morph_shift)
		if was != main:
			away = was
	# Печать по домам. Летящей подписи дома нет: она в этот момент в пути,
	# и из-под неё выглядывала бы вторая копия (автор 10.2026).
	for v in small_legends(s, lang, shift):
		var t := String(v)
		if t == away:
			continue
		var pr := _rest(s, r, font, t, main, f, sub_fs)
		_draw_glyph(ci, font, t, pr[0], pr[1], dim)
	# Рисочки под указательные пальцы: на настоящей клавиатуре клавиши
	# «а» и «о» приподняты, их находят не глядя.
	if s == "а" or s == "о":
		_bump(ci, r, dim)
	if away != "":
		# Прежняя — из центра в свой дом, новая — из своего дома в центр.
		# Концы совпадают с покоем: начало — презентация прежней как
		# набираемой, конец — презентация новой как набираемой и прежней
		# как пассивной. Поэтому ни в начале, ни в конце перелёта знак не
		# прыгает — только едет.
		var pa := _rest(s, r, font, away, main, f, sub_fs)
		var pm := _rest(s, r, font, main, main, f, sub_fs)
		# Презентация новой как пассивной (её дом): _rest с чужим main.
		var pm_slot := _rest(s, r, font, main, away, f, sub_fs)
		# Презентация прежней как набираемой (откуда едем).
		var pa_main := _rest(s, r, font, away, away, f, sub_fs)
		_draw_glyph(
			ci, font, away, (pa_main[0] as Vector2).lerp(pa[0], morph),
			lerpf(pa_main[1], pa[1], morph), ink.lerp(dim, morph)
		)
		_draw_glyph(
			ci, font, main, (pm_slot[0] as Vector2).lerp(pm[0], morph),
			lerpf(pm_slot[1], pm[1], morph), dim.lerp(ink, morph)
		)
		return
	var pm0 := _rest(s, r, font, main, main, f, sub_fs)
	_draw_glyph(ci, font, main, pm0[0], pm0[1], ink)


## Все ряды слоя сверху вниз (цифры + верх + низ).
static func all_rows(enter: bool) -> Array:
	var rows: Array = []
	rows.append(ROW_DIGITS_RU)
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


## Вторая буква клавиши (другая раскладка). Пусто — пара одна.
static func pair_of(s: String) -> String:
	return String(RU_EN.get(s.to_lower(), ""))


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
## Служебные клавиши настоящей раскладки: в наборе они не участвуют,
## подпись приглушена, тап мимо (автор 10.2026: «всё заблокировано —
## в наборе не участвует, подпись приглушена, тап мимо»).
static func _is_blocked(label: String) -> bool:
	return label in ["Ctrl", "Win", "Alt", "Tab", "Caps"]


## Ширина клавиши в единицах питча: стандарт ANSI. Tab 1.5, Caps 1.75,
## левый Shift 2.25 — отсюда и ступеньки рядов (см. buttons): буквы
## верхнего ряда стоят на 1.5 питча, среднего — на 1.75, нижнего — на
## 2.25. Стереть — двойное, пробел — тройной.
static func _span(label: String) -> float:
	if label == "пробел":
		return 3.0
	if label == "←":
		return 2.0
	if label == "Tab":
		return 1.5
	if label == "Caps":
		return 1.75
	if label == "Shift":
		return 2.25
	if label == "ShiftR":
		return 1.5
	return 1.0


## Ширина модификатора в пикселях: буквы начинаются ровно на целом числе
## питчей (M*(p+gap)), и ступеньки держатся точно, без накопления ошибки.
static func _mod_w(m: float, p: float, gap: float) -> float:
	return m * p + (m - 1.0) * gap


## Высота клавиатуры в пикселях: кнопки чуть выше ширины (×1.15, как у
## Яндекс-клавиатуры), рядов всегда 5 (цифры + 3 верха + низ).
## Сколько клавиш в самом широком ряду и сколько в нём зазоров: по этим
## числам обратная задача даёт ширину доски (высота 46% экрана). Считаем
## по САМОЙ доске: константа «12» разъехалась, когда в ряд цифр добавили
## Tab и ↵ стал шире (автор 10.2026: «если ты от этого зависишь, то
## считай по самой доске»).
static func _widest_row() -> Array:
	var best: Array = []
	for row in all_rows(true):
		if row.size() > best.size():
			best = row
	return best


static func height_for(view_w: float) -> float:
	return _h_of_w(view_w)


## Обратная задача: ширина, дающая ровно заданную высоту. Нужна, когда
## доска не влезает в 46% высоты экрана и высоту приходится ужимать.
static func width_for(h: float) -> float:
	var row := _widest_row()
	var nw := _row_units(row)
	var unit := (h - 4.0 * 8.0 - 32.0) / (5.0 * ROW_TALL)
	return unit * nw + (nw - 1.0) * 8.0 + 32.0


## Ширина клавиши-единицы в самом широком ряду (стереть — две единицы).
static func _row_units(row: Array) -> float:
	var nw := 0.0
	for label in row:
		nw += _span(String(label))
	return nw


static func _h_of_w(view_w: float) -> float:
	var nw := _row_units(_widest_row())
	var w := (view_w - 32.0 - (nw - 1.0) * 8.0) / nw
	return 5.0 * w * ROW_TALL + 4.0 * 8.0 + 32.0


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
## Кнопки доски (чистая функция геометрии). Результат ЗАПОМИНЕН на
## (area, shift, enter): каждый кадр рисования и каждый тап строили
## ~60 словарей заново — на 3120x2080 это самая дорогая часть кадра
## после чтения конфига (ревизия 16.10.2026).
static var _btn_key_ok := false
static var _btn_pos := Vector2.ZERO
static var _btn_size := Vector2.ZERO
static var _btn_shift := false
static var _btn_enter := false
static var _btn_cache: Array = []


static func buttons(area: Rect2, shift: bool, enter := false) -> Array:
	if (
		_btn_key_ok
		and _btn_pos == area.position
		and _btn_size == area.size
		and _btn_shift == shift
		and _btn_enter == enter
	):
		return _btn_cache
	buttons_misses += 1
	_btn_cache = _buttons_now(area, shift, enter)
	_btn_key_ok = true
	_btn_pos = area.position
	_btn_size = area.size
	_btn_shift = shift
	_btn_enter = enter
	return _btn_cache


static func _buttons_now(area: Rect2, shift: bool, enter := false) -> Array:
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
	# Русская доска — стандартная ступенька ANSI в единицах питча:
	# цифры с ё/-/= и стереть сверху (стереть двойное, как настоящий
	# Backspace), Tab + 12 букв + слеш, Caps + 11 букв + ввод (как
	# настоящий Enter), Shift + 10 букв + правый шифт. Питч ОДИН на все
	# ряды: цифры 1..0,-,= — того же размера, что буквы (автор 10.2026).
	# Буквы стоят на 1.5 / 1.75 / 2.25 питча — ровно как Tab / Caps /
	# Shift настоящей клавиатуры. Отсюда сдвиг цифр: «1» на полпитча левее
	# «й» — та же ступенька, что на настоящей (там «1» левее Q на 0.5u).
	var ru_p := 0.0
	if rows.size() >= 5:
		var w := area.size.x
		# Потолки питча по рядам (модификатор + буквы + зазоры; правый край
		# вбирает остаток: стереть не меньше 2u, ввод не меньше 1.2 питча,
		# правый шифт не меньше 32 px).
		# Ряд цифр: 13 клавиш питчем + стереть(2u) + 13 зазоров.
		ru_p = (w - 13.0 * gap) / 15.0
		# Верхний ряд: Tab(1.5) + 13 букв + 13 зазоров + слеш(≥1u).
		ru_p = minf(ru_p, (w - 13.5 * gap) / 14.5)
		ru_p = minf(ru_p, (w - 13.5 * gap) / 15.5)
		# Средний ряд: Caps(1.75) + 11 букв + 12 зазоров + ввод(1.2).
		ru_p = minf(ru_p, (w - 12.75 * gap) / 13.95)
		# Низ: Shift(2.25) + 10 букв + 11 зазоров + правый шифт(32).
		ru_p = minf(ru_p, (w - 12.25 * gap - 32.0) / 12.25)
		ru_p = maxf(ru_p, 16.0)
	for ri in rows.size():
		var row: Array = rows[ri]
		var x := area.position.x
		var y := area.position.y + float(ri) * (rh + gap)
		# Русская доска: цифры, Tab + 12 букв + слеш, Caps + 11 букв +
		# ввод, Shift + 10 букв + правый шифт. Все ряды от левого края;
		# ступеньки — шириной модификаторов (1.5 / 1.75 / 2.25).
		if rows.size() >= 5 and (ri >= 0 and ri <= 3):
			if ri == 0:
				# Ряд цифр тем же питчем, что буквы (автор 10.2026).
				# Стереть вбирает остаток до края доски (автор 10.2026:
				# «бекспейс не достаточно широк, чтобы дотягиваться до
				# края»): выходит ~2.5u — широкая мишень, как и положено
				# краю. Потолок питча держит его не меньше 2u.
				for label in row:
					var s0 := String(label)
					if s0 == "←":
						continue
					out.append({"r": Rect2(x, y, ru_p, rh), "s": s0})
					x += ru_p + gap
				out.append({"r": Rect2(x, y, area.position.x + area.size.x - x, rh), "s": "←"})
				continue
			if ri == 1:
				for label in row:
					var s1 := String(label)
					if s1 == "\\":
						continue
					var w1 := _mod_w(_span(s1), ru_p, gap) if s1 == "Tab" else ru_p
					out.append({"r": Rect2(x, y, w1, rh), "s": s1})
					x += w1 + gap
				# Слеш вбирает остаток (потолок питча держит его ≥ 1u).
				out.append({"r": Rect2(x, y, area.position.x + area.size.x - x, rh), "s": "\\"})
				continue
			if ri == 2:
				for label in row:
					var s2 := String(label)
					if s2 == "↵":
						continue
					var w2 := _mod_w(_span(s2), ru_p, gap) if s2 == "Caps" else ru_p
					out.append({"r": Rect2(x, y, w2, rh), "s": s2})
					x += w2 + gap
				out.append({"r": Rect2(x, y, area.position.x + area.size.x - x, rh), "s": "↵"})
				continue
			if ri == 3:
				for label in row:
					var s3 := String(label)
					if s3 == "ShiftR":
						continue
					var w3 := _mod_w(_span(s3), ru_p, gap) if s3 == "Shift" else ru_p
					out.append({"r": Rect2(x, y, w3, rh), "s": s3})
					x += w3 + gap
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
					out.append({"r": Rect2(x, y, w0, rh), "s": s0})
					x += w0 + gap
			else:
				var n1b := row.size()
				var left := (area.size.x - (float(n1b) * pitch + gap * float(n1b - 1))) * 0.5
				x += left
				for label in row:
					var s1 := String(label)
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
			out.append({"r": Rect2(x, y, float(widths[bi]), rh), "s": s})
			x += float(widths[bi]) + gap
	return out


## Тап по клавиатуре: "" — мимо, иначе действие ("стереть", "шифт",
## "ввод", "язык", "пробел", символ). Слоя ?123 больше нет.
## Клавиша под точкой.
##
## finger — режим пальца: контактная пятна шире клавиши, а щель между
## клавишами на телефоне 18-31 % шага (замерено: ряд букв 37 px при шаге
## 45, ряд цифр 18 px при шаге 26 — canvas). Мышь сюда не попадает: её
## промах виден, и он виноват человек, а не палец.
## В режиме пальца действуют два правила:
##   1. точка ВНУТРИ клавиши — попадает в неё (тут не спорим);
##   2. точка между клавишами — достаётся БЛИЖАЙШЕЙ, если она не дальше
##      finger_pad() от её рамки. Раньше такой тап просто пропадал: человек
##      жал повторно, попадал в соседнюю букву — и метка вставала на ту
##      букву, которую он и хотел нажать (метка всегда на клетке курсора),
##      то есть «нажал правильную букву, а она красная» (автор
##      17.10.2026, телефон; на десктопе не воспроизводится — там щель
##      6-8 % шага и клик точный).
static func hit(area: Rect2, shift: bool, enter: bool, pos: Vector2, finger := false) -> String:
	var bs := buttons(area, shift, enter)
	if finger:
		return _hit_finger(bs, pos)
	for b in bs:
		if (b["r"] as Rect2).has_point(pos):
			return _act_of(String(b["s"]))
	return ""


## Режим пальца: сначала «внутри», потом «рядом с ближайшей».
static func _hit_finger(bs: Array, pos: Vector2) -> String:
	for b in bs:
		if (b["r"] as Rect2).has_point(pos):
			return _act_of(String(b["s"]))
	var pad := finger_pad(bs)
	if pad <= 0.0:
		return ""
	var best := ""
	var best_d := pad
	for b in bs:
		var r: Rect2 = b["r"]
		var d := INF
		if pos.x < r.position.x:
			d = r.position.x - pos.x
		elif pos.x > r.end.x:
			d = pos.x - r.end.x
		if pos.y < r.position.y:
			d = maxf(d, r.position.y - pos.y)
		elif pos.y > r.end.y:
			d = maxf(d, pos.y - r.end.y)
		if d < best_d:
			best_d = d
			best = String(b["s"])
	return _act_of(best)


## Запас для пальца: 40 % самого тесного шага в раскладке. Щель между
## клавишами — примерно треть шага, поэтому 40 % её перекрывают с запасом,
## а соседнюю клавишу при этом не украсть: выигрывает ближайшая.
static func finger_pad(bs: Array) -> float:
	var pitch := INF
	var rows := {}
	for b in bs:
		var r: Rect2 = b["r"]
		var key := int(round(r.position.y))
		if not rows.has(key):
			rows[key] = []
		(rows[key] as Array).append(r)
	for key in rows.keys():
		var row: Array = []
		row.assign(rows[key] as Array)
		row.sort_custom(func(a: Rect2, c: Rect2) -> bool: return a.position.x < c.position.x)
		for i in row.size() - 1:
			var step: float = (row[i + 1] as Rect2).position.x - (row[i] as Rect2).position.x
			pitch = minf(pitch, step)
	if pitch == INF:
		return 0.0
	return pitch * 0.4


## Подпись клавиши → действие. Пусто для заблокированных (Ctrl, Win, Alt).
static func _act_of(s: String) -> String:
	if s == "←":
		return "стереть"
	if s == "Shift" or s == "ShiftR":
		return "шифт"
	if s == "↵":
		return "ввод"
	if s == "глобус":
		return "язык"
	if _is_blocked(s):
		return ""
	return s


## Нарисовать кнопки на канве вызывателя. Шрифт и стиль — вызывателя.
## Кегль — от высоты ряда (палец!), служебные чуть мельче. Глобус —
## векторный (круг + меридиан): шрифтового эмодзи в DejaVu нет.
## shift_on подсвечивает шифт заливкой (второй стиль вызывателя).
static func draw(
	ci: CanvasItem, area: Rect2, lang: String, shift: bool,
	enter: bool, font: Font, fs: int, sb: StyleBox, sb_on: StyleBox, ink: Color,
	hi: Array = [], hi_sb: StyleBox = null, ink_dim: Color = Color(0, 0, 0, 0),
	morph := 1.0, morph_from := "", morph_shift := false,
	press_sb: StyleBox = null, press_key := ""
) -> void:
	# hi — подписи клавиш, которые игра подсвечивает после простоя
	# (вместо текстовой подсказки «Нажми К»). hi_sb рисует их вызыватель
	# и сам же в нём ведёт пульсацию цветом каждый кадр. Запись вида
	# «пробел:Л»/«пробел:П» подсвечивает половину пробела (палец
	# противоположной руки) с мягкой градиентной границей.
	# ink_dim — приглушённые чернила для неактивных подписей: у каждой
	# буквы напечатаны обе раскладки, активная светится ярче.
	# press_sb — заливка нажатой клавиши: человек должен видеть, что
	# попал в ту самую клавишу (или промахнулся мимо всех).
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
		if press_sb != null and s == press_key:
			box = press_sb
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
				var probe := Ui.text_size(font, shown, f).x
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
		var tw := Ui.text_size(font, shown, f).x
		var th := font.get_height(f)
		var blocked := _is_blocked(s)
		ci.draw_string(
			font,
			Vector2(r.get_center().x - tw * 0.5, r.get_center().y + float(th) * 0.3),
			" " if s == "пробел" else shown,
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, f, dim if blocked else ink
		)


## Глиф по центру точки, кеглем и чернилами на выбор.
static func _draw_glyph(
	ci: CanvasItem, font: Font, txt: String, at: Vector2, f: float, col: Color
) -> void:
	var fi := int(f)
	var w := Ui.text_size(font, txt, fi).x
	ci.draw_string(
		font, Vector2(at.x - w * 0.5, at.y + float(font.get_height(fi)) * 0.3),
		txt, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fi, col
	)


## Зона угловой подписи: четыре угла, как на настоящей клавише. Места
## под центральную подпись не режем.
## Зона подписи: девять мест (автор 10.2026: «у каждой кнопки своё место…
## tl t tr l r bl b br», плюс центр — девятое). Углы 0–3, края 4–7, центр 8:
## центр — дом служебных клавиш (шифт, стереть, ввод, глобус: их знак не
## меняется и живёт там всегда) и временная стоянка набираемой подписи.
static func _corner(r: Rect2, i: int) -> Rect2:
	var pad := 3.0
	var w := r.size.x * 0.34
	var h := r.size.y * 0.30
	var cx := r.get_center().x
	var cy := r.get_center().y
	match i:
		1:
			return Rect2(r.end.x - w - pad, r.position.y + pad, w, h)
		2:
			return Rect2(r.end.x - w - pad, r.end.y - h - pad, w, h)
		3:
			return Rect2(r.position.x + pad, r.end.y - h - pad, w, h)
		4:
			return Rect2(cx - w * 0.5, r.position.y + pad, w, h)
		5:
			return Rect2(cx - w * 0.5, r.end.y - h - pad, w, h)
		6:
			return Rect2(r.position.x + pad, cy - h * 0.5, w, h)
		7:
			return Rect2(r.end.x - w - pad, cy - h * 0.5, w, h)
		8:
			return Rect2(cx - w * 0.5, cy - h * 0.5, w, h)
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


## Тактильный рисочек на «а» и «о»: на настоящей клавиатуре под указательными
## пальцами клавиши чуть приподняты — их находят не глядя. Рисуем
## короткую черту у нижнего края клавиши.
static func _bump(ci: CanvasItem, r: Rect2, ink: Color) -> void:
	var w := r.size.x * 0.42
	var h := maxf(2.0, r.size.y * 0.035)
	var x := r.get_center().x - w * 0.5
	var y := r.end.y - h - r.size.y * 0.10
	ci.draw_rect(Rect2(x, y, w, h), ink)


## Глобус кнопки языка: круг, вертикальный меридиан-эллипс и горизонталь.
static func _draw_globe(ci: CanvasItem, c: Vector2, rad: float, ink: Color) -> void:
	ci.draw_arc(c, rad, 0.0, TAU, 32, ink, 2.5)
	var pts := PackedVector2Array()
	for i in 17:
		var a := float(i) / 16.0 * TAU
		pts.append(c + Vector2(cos(a) * rad * 0.45, sin(a) * rad))
	ci.draw_polyline(pts, ink, 2.0)
	ci.draw_line(c + Vector2(-rad, 0.0), c + Vector2(rad, 0.0), ink, 2.0)
