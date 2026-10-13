## Банк текстов: файлы лежат целиком (сборник + `user://texts/`), уровень —
## run из 1+ целых предложений подряд на нужное число знаков.
## Целостность важнее точного размера: начинать с середины предложения
## и обрывать фразу нельзя (автор 10.2026), поэтому границы — только
## [.?!…], а сомнительные случаи (сокращения, инициалы, десятичные,
## нумерация) НЕ режут, а склеивают: длиннее можно, рвать нельзя.
## Модуль чистый: состояние не хранит, файлы только читает.
extends RefCounted


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
static func list_files() -> Array[String]:
	var names: Array[String] = []
	for base in ["res://texts", "user://texts"]:
		var dir := DirAccess.open(base)
		if dir == null:
			continue
		dir.list_dir_begin()
		var fname := dir.get_next()
		while fname != "":
			if not dir.current_is_dir() and fname.ends_with(".txt"):
				names.append(base + "/" + fname)
			fname = dir.get_next()
		dir.list_dir_end()
	var out: Array[String] = []
	while not names.is_empty():
		var i := randi() % names.size()
		out.append(names[i])
		names.remove_at(i)
	return out


## Папка пользовательских текстов: создаётся при первом запуске, чтобы
## было куда положить свой .txt (вариант B: свой файл + импорт).
static func ensure_user_dir() -> void:
	if not DirAccess.dir_exists_absolute("user://texts"):
		DirAccess.make_dir_recursive_absolute("user://texts")


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


## Буква ли символ (кириллица, латиница, ё).
static func _is_letter(ch: String) -> bool:
	if ch.length() != 1:
		return false
	var code := ch.unicode_at(0)
	return (code >= 65 and code <= 90) or (code >= 97 and code <= 122) \
		or (code >= 1040 and code <= 1103) or code == 1025 or code == 1105


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
static func pick_fragment(sentences: Array[String], target: int) -> Array[String]:
	var out: Array[String] = []
	if sentences.is_empty():
		return out
	# Старт — чтобы вперёд влезло минимум три (как в прототипе: окно
	# [start, start+n) внутри файла). Маленький пул отдаём целиком.
	var start := 0
	if sentences.size() > 3:
		start = randi() % (sentences.size() - 2)
	var total := 0
	var i := start
	while i < sentences.size() and (total < target or out.size() < 3) and out.size() < 12:
		total += String(sentences[i]).length() + 1
		out.append(String(sentences[i]))
		i += 1
	return out


## Предложения первого непустого файла базы.
static func file_sentences(path: String) -> Array[String]:
	var lines := read_lines(path)
	if lines.is_empty():
		return []
	return split_sentences(" ".join(PackedStringArray(lines)))


## Фрагмент уровня: случайный файл, в нём случайный run предложений.
static func load_fragment(difficulty: int) -> Array[String]:
	ensure_user_dir()
	for path in list_files():
		var sentences := file_sentences(path)
		if sentences.is_empty():
			continue
		var run := pick_fragment(sentences, target_for(difficulty))
		if not run.is_empty():
			return run
	return ["мама мыла раму.", "папа читал газету!", "солнце светило ярко?"]
