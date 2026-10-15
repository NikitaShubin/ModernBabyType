## Банк текстов: файлы лежат целиком (сборник + `user://texts/`), уровень —
## run из 1+ целых предложений подряд на нужное число знаков.
## Целостность важнее точного размера: начинать с середины предложения
## и обрывать фразу нельзя (автор 10.2026), поэтому границы — только
## [.?!…], а сомнительные случаи (сокращения, инициалы, десятичные,
## нумерация) НЕ режут, а склеивают: длиннее можно, рвать нельзя.
## Модуль чистый: состояние не хранит, файлы только читает.
extends RefCounted


const Kbd := preload("res://scripts/kbd.gd")


## Сокращения, после которых точка НЕ кончает предложение. Однобуквенные
## токены (инициалы, т/д/п/н/г/в) правило покрывает отдельно, тут только
## многобуквенные. Список не обязан быть полным: неизвестное сокращение
## в худшем случае склеит два предложения, но никогда не порвёт фразу.
const ABBR := [
	"ул", "пр", "пер", "пл", "наб", "стр", "рис", "напр", "др", "гг",
	"вв", "им", "св", "тов", "гр", "шт", "руб", "коп", "тыс", "млн",
	"млрд", "тел", "акад", "проф", "доц", "канд", "док",
]


## Знаков в уровне: примерно как раньше (3 строки ~ по 40 знаков),
## дальше плавно растёт со сложностью.
static func target_for(difficulty: int) -> int:
	return mini(130 + 12 * maxi(0, difficulty), 450)


## Все файлы базы: встроенные плюс пользовательские, в случайном порядке.
## Первый непустой выигрывает — то есть файл выбирается равновероятно,
## а внутри него уже случайный фрагмент (как в прототипе main.py).
## База следует за тумблером «Про»: у про-аккаунта взрослая классика,
## у остальных — детские стихи и сказки (автор 10.2026).
static func list_files(base := "kids") -> Array[String]:
	var names: Array[String] = []
	for dir_path in ["res://texts/" + base, "user://texts/" + base]:
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		dir.list_dir_begin()
		var fname := dir.get_next()
		while fname != "":
			if not dir.current_is_dir() and fname.ends_with(".txt"):
				names.append(dir_path + "/" + fname)
			fname = dir.get_next()
		dir.list_dir_end()
	# Порядок обхода каталога зависит от файловой системы: без сортировки
	# один и тот же сид тасовал бы по-разному на разных машинах, и
	# seeded-прогоны расходились бы (ловил CI 15.10.2026: backspace-цепочка
	# зелёная дома, красная на раннере). Сортируем — дальше всё решает сид.
	names.sort()
	var out: Array[String] = []
	while not names.is_empty():
		var i := randi() % names.size()
		out.append(names[i])
		names.remove_at(i)
	return out


## Папки пользовательских текстов: создаются при первом запуске, чтобы
## было куда положить свой .txt (вариант B: свой файл + импорт).
static func ensure_user_dir() -> void:
	for sub in ["kids", "pro"]:
		if not DirAccess.dir_exists_absolute("user://texts/" + sub):
			DirAccess.make_dir_recursive_absolute("user://texts/" + sub)


## Непустые обрезанные строки файла. Пустые строки, пробелы и прочий
## мусор отбрасывает фильтр здесь, файлы править не надо (автор 10.2026).
static func read_lines(path: String) -> Array[String]:
	var out: Array[String] = []
	var fa := FileAccess.open(path, FileAccess.READ)
	if fa == null:
		return out
	while not fa.eof_reached():
		var line := fa.get_line().strip_edges()
		if line != "":
			out.append(line)
	return out


## Буква ли символ: латиница, кириллица целиком (включая украинские
## є/і/ї/ґ и старую орфографию — сказ Лескова пишется с ними). Буква без
## клавиши — работа фильтра (предложение пропускается), а не дыра:
## содержимое не правим.
static func is_letter_char(ch: String) -> bool:
	if ch.length() != 1:
		return false
	var code := ch.unicode_at(0)
	return (code >= 65 and code <= 90) or (code >= 97 and code <= 122) \
		or (code >= 0x0400 and code <= 0x04FF)


static func _is_letter(ch: String) -> bool:
	return is_letter_char(ch)


## Цифра ли символ.
static func _is_digit(ch: String) -> bool:
	if ch.length() != 1:
		return false
	var code := ch.unicode_at(0)
	return code >= 48 and code <= 57


## Строчная ли буква.
static func _is_lower(ch: String) -> bool:
	if not _is_letter(ch):
		return false
	return ch == ch.to_lower() and ch != ch.to_upper()


## Делит текст на целые предложения. Возвращает их же, обрезанными.
static func split_sentences(text: String) -> Array[String]:
	var clean := text.replace("\r\n", " ").replace("\r", " ").replace("\n", " ")
	clean = clean.replace("\t", " ")
	while clean.contains("  "):
		clean = clean.replace("  ", " ")
	clean = clean.strip_edges()
	var out: Array[String] = []
	var start := 0
	var i := 0
	while i < clean.length():
		var ch := clean.substr(i, 1)
		if ch != "." and ch != "?" and ch != "!" and ch != "…":
			i += 1
			continue
		# Проглатываем run терминаторов ("..." — один run) и висящие
		# закрывающие кавычки/скобки за ним.
		var j := i
		while j < clean.length():
			var cj := clean.substr(j, 1)
			if cj == "." or cj == "?" or cj == "!" or cj == "…":
				j += 1
			else:
				break
		while j < clean.length():
			var cj2 := clean.substr(j, 1)
			if cj2 == "»" or cj2 == "\"" or cj2 == "'" or cj2 == ")" or cj2 == "]":
				j += 1
			else:
				break
		var cut := _is_boundary(clean, i, j)
		i = j
		if cut:
			var piece := clean.substr(start, j - start).strip_edges()
			if piece != "":
				out.append(piece)
			while i < clean.length() and clean.substr(i, 1) == " ":
				i += 1
			start = i
	var tail := clean.substr(start).strip_edges()
	if tail != "":
		out.append(tail)
	return out


## Граница ли предложения после терминатора [i, j).
static func _is_boundary(clean: String, i: int, j: int) -> bool:
	# Предшествующий знак: буква или цифра непосредственно перед run.
	var prev := ""
	var k := i - 1
	if k >= 0:
		prev = clean.substr(k, 1)
	# Следующий значащий знак после run и закрывашек.
	var nxt := ""
	var t := j
	while t < clean.length() and clean.substr(t, 1) == " ":
		t += 1
	if t < clean.length():
		nxt = clean.substr(t, 1)
	# Конец текста — всегда граница.
	if nxt == "":
		return true
	# Цифра перед точкой: десятичные, даты, нумерация — склеить.
	if _is_digit(prev):
		return false
	# Токен перед точкой: однобуквенный (инициалы, т/д/п/н) или из
	# списка сокращений — склеить.
	var tok := ""
	var m := i - 1
	while m >= 0 and _is_letter(clean.substr(m, 1)):
		tok = clean.substr(m, 1) + tok
		m -= 1
	if tok.length() == 1:
		return false
	if tok != "" and tok.to_lower() in ABBR:
		return false
	# Дальше строчная буква или цифра — предложение продолжается.
	if _is_lower(nxt) or _is_digit(nxt):
		return false
	return true


## Случайный run целых предложений подряд примерно на target знаков
## (минимум три — уровень многострочный, как раньше; максимум 12 —
## защита от крошки вроде «а о а о»).
## Возвращает сами предложения списком, а перенос по ширине экрана
## доделывает _fit_to_width.
static func pick_fragment(
	sentences: Array[String], target: int, start := -1
) -> Array[String]:
	var out: Array[String] = []
	if sentences.is_empty():
		return out
	# Старт — чтобы вперёд влезло минимум три (как в прототипе: окно
	# [start, start+n) внутри файла). Маленький пул отдаём целиком.
	if start < 0:
		start = _run_start(sentences.size())
	var total := 0
	var i := start
	while i < sentences.size() and (total < target or out.size() < 3) and out.size() < 12:
		total += String(sentences[i]).length() + 1
		out.append(String(sentences[i]))
		i += 1
	return out


## Нормализация пунктуации под доску. Файлы хранят ОРИГИНАЛЫ, правит
## парсер (автор 10.2026): тире нет на клавиатуре, ёлочек тоже, а "..."
## набирается тремя точками. Слова не трогаем, только знаки.
static func normalize_text(s: String) -> String:
	var t := s.replace("—", "-").replace("–", "-") \
		.replace("\u00ab", "").replace("\u00bb", "") \
		.replace("\u201e", "").replace("\u201c", "").replace("\u201d", "") \
		.replace("\u201f", "") \
		.replace("…", "...").replace("\u2019", "'").replace("\u2018", "'")
	t = _spaces_to_plain(t)
	return _strip_combining(t)


## Все пробельные разделители юникода — в обычный пробел. Типографика,
## а не текст: иначе тонкий пробел издания даёт ненабираемую клетку.
static func _spaces_to_plain(s: String) -> String:
	var out := ""
	for i in s.length():
		var code := s.unicode_at(i)
		if code == 0x00A0 or code == 0x1680 \
			or (code >= 0x2000 and code <= 0x200A) \
			or code == 0x202F or code == 0x205F or code == 0x3000:
			out += " "
		else:
			out += s.substr(i, 1)
	return out


## Комбинируемые диакритические знаки (ударения изданий) — долой.
## Типографика, а не текст: снять их нельзя только вместе с буквой.
static func _strip_combining(s: String) -> String:
	var out := ""
	for i in s.length():
		var code := s.unicode_at(i)
		if code >= 0x0300 and code <= 0x036F:
			continue
		out += s.substr(i, 1)
	return out


## Знаки, набираемые с доски. Считается один раз и дальше только
## читается: `Kbd.combo_for` перебирает всю доску и пересобирает легенды
## на КАЖДЫЙ знак, а проверка идёт по каждому знаку файла (десятки
## тысяч на уровень — на телефоне это заметная заминка).
static var _typable: Dictionary = {}


static func _build_typable() -> void:
	for row in Kbd.all_rows(false):
		for label in row:
			for s in Kbd.legends(String(label)):
				if String(s) != "":
					_typable[String(s)] = true


## Есть ли у знака клавиша на доске — оба языка и оба регистра (легенды
## ключей). Букву без клавиши (сказовое «є») предложение просто
## пропускает, а знак без клавиши — дыра в нормализации.
static func _has_key(ch: String) -> bool:
	if ch == " ":
		return true
	if _typable.is_empty():
		_build_typable()
	return _typable.has(ch)


## Предложения без бесклавишных букв. Файл хранит оригинал целиком, но
## уровень из такого предложения не собрать (набрать нечем): как пустые
## строки, они отбрасываются фильтром, а не правятся (автор 10.2026).
static func playable(sentences: Array[String]) -> Array[String]:
	var out: Array[String] = []
	for s in sentences:
		var ok := true
		for ch in String(s):
			if not _has_key(ch):
				ok = false
				break
		if ok:
			out.append(String(s))
	return out


## Предложения файла вместе с признаком «здесь в источнике был перенос
## строки». Физическая строка файла — это абзац, реплика диалога или
## строка стиха; ↵ в игре ждёт ровно таких мест (автор 13.10.2026:
## «где в оригинальном файле был перенос строки — диалоги, концы
## абзацев, стихи»). Внутри физической строки предложения идут подряд,
## их границы — обычный перенос, он автоматический.
## Отдаём словарём, чтобы старый file_sentences остался совместимым.
static func file_units(path: String) -> Dictionary:
	var lines := read_lines(path)
	if lines.is_empty():
		return {"texts": [] as Array[String], "hard": [] as Array[bool]}
	var texts: Array[String] = []
	var hard: Array[bool] = []
	for raw in lines:
		var part := split_sentences(normalize_text(raw))
		for i in part.size():
			texts.append(String(part[i]))
			hard.append(i == part.size() - 1)
	return {"texts": texts, "hard": hard}


## Предложения первого непустого файла базы.
static func file_sentences(path: String) -> Array[String]:
	var units := file_units(path)
	var texts: Array[String] = []
	for t in units["texts"]:
		texts.append(String(t))
	return texts


## Фрагмент уровня: случайный файл базы, в нём случайный run
## предложений. Пустая база откатывается к детской, дальше — запасной
## набор: уровень обязан собраться всегда.
static func load_fragment(difficulty: int, base := "kids") -> Dictionary:
	ensure_user_dir()
	var order := [base]
	if base != "kids":
		order.append("kids")
	for want in order:
		for path in list_files(want):
			var units := file_units(path)
			var texts: Array[String] = []
			var hard: Array[bool] = []
			var src_hard: Array = units["hard"]
			for i in (units["texts"] as Array).size():
				var one := String((units["texts"] as Array)[i])
				if not playable([one]).is_empty():
					texts.append(one)
					hard.append(i < src_hard.size() and bool(src_hard[i]))
			if texts.is_empty():
				continue
			var start := _run_start(texts.size())
			var run := pick_fragment(texts, target_for(difficulty), start)
			if not run.is_empty():
				var out_hard: Array[bool] = []
				for i in run.size():
					var j := start + i
					out_hard.append(j < hard.size() and bool(hard[j]))
				# Разрывы между предложениями пробела не добавляют: ось
				# логики (B.logical_cells) должна считаться одинаково и до,
				# и после пересборки строк, иначе после поворота экрана
				# заяц и ёж расходятятся (ловил _case_relayout).
				return {"texts": run, "hard": out_hard, "drops": [] as Array[int]}
	return {
		"texts": ["мама мыла раму.", "папа читал газету!", "солнце светило ярко?"] as Array[String],
		"hard": [false, false, true] as Array[bool],
		"drops": [0, 1, 2] as Array[int],
	}


## Старт run внутри файла (смещение предложений): вынесено, чтобы и
## выбор, и сборка фрагмента считали одно и то же.
static func _run_start(size: int) -> int:
	if size <= 3:
		return 0
	return randi() % (size - 2)
