class_name Balance
extends RefCounted
## Чистая логика сложности. Без узлов сцены, только числа.
## Ключевое отличие от legacy (main.py): скорость врага измеряется
## в символах/сек, а не в px/сек, поэтому не зависит от ширины окна.

const KEY_PROGRESSION := " аовлыдфжпреимтнгрушщзхъёйчясмитьбю,.!?-:;\"'()1234567890"
const INITIAL_ACTIVE_COUNT := 3
const WINS_TO_LEVEL_UP := 3
## База slow: даже ребёнок, который только сел за клавиатуру и ищет
## три кнопки (пробел, а, о), успевает убежать. Было 2.0 — ёж ловил
## новичка раньше, чем тот находил буквы.
const BASE_CPS := 1.1
const MIN_CPS := 0.6
const MAX_CPS := 10.0


static func active_char_count(difficulty_level: int) -> int:
	return mini(INITIAL_ACTIVE_COUNT + difficulty_level, KEY_PROGRESSION.length())


static func active_chars(difficulty_level: int) -> Dictionary:
	var result := {}
	var count := active_char_count(difficulty_level)
	for i in count:
		result[KEY_PROGRESSION[i]] = true
	result[" "] = true
	return result


## Целевая скорость врага: растёт с уровнем (мягко, +8% за уровень)
## и подстраивается под скользящее среднее темпа игрока (EMA CPM).
## Игрок ~120 CPM => skill 1.0.
static func target_cps(difficulty_level: int, ema_cpm: float) -> float:
	var skill := 1.0
	if ema_cpm > 0.0:
		skill = clampf(ema_cpm / 120.0, 0.5, 1.6)
	var cps := BASE_CPS * (1.0 + 0.08 * float(difficulty_level)) * skill
	return clampf(cps, MIN_CPS, MAX_CPS)


## Ступенчатая адаптация по итогам уровня + pity при поражении.
static func adapt_cps(won: bool, cps: float, accuracy: float) -> float:
	var next := cps
	if won:
		if accuracy >= 0.95:
			next = cps * 1.1
		else:
			next = cps * 1.03
	else:
		next = cps * 0.75
	return clampf(next, MIN_CPS, MAX_CPS)


static func stars_for_result(won: bool, accuracy: float, errors: int) -> int:
	if not won:
		return 0
	if accuracy >= 0.98 and errors == 0:
		return 3
	if accuracy >= 0.94:
		return 2
	return 1


## Глобальные смещения строк по оси текста. Разрыв строки не символ:
## конец строки — это начало следующей (см. _advance в main).
static func line_bases(lines: Array) -> Array:
	var out: Array = []
	var acc := 0
	for ln in lines:
		out.append(acc)
		acc += String(ln).length()
	return out


## Клетка по физическому смещению: первая строка, в которой смещение
## ещё внутри. За концом текста — Vector2i(size, 0): это «уровень
## набран» (так же считает _advance).
static func cell_at(lines: Array, base: Array, offset: int) -> Vector2i:
	for i in lines.size():
		if offset < int(base[i]) + String(lines[i]).length():
			return Vector2i(i, offset - int(base[i]))
	return Vector2i(lines.size(), 0)


## Разбивка строк с отметкой, сколько пробелов-разделителей ушло в
## огрызок ДО каждого куска. Пробел на месте разрыва не клетка (см.
## fit_lines), поэтому физические смещения после пересборки не совпадают
## со старыми: считать надо по логической оси — без этих пробелов.
static func fit_marked(raw: Array[String], max_chars: int) -> Dictionary:
	var lines: Array[String] = []
	var drops: Array[int] = []
	var dropped := 0
	for line in raw:
		if line.length() <= max_chars:
			lines.append(line)
			drops.append(dropped)
			continue
		var cur := ""
		for w0 in line.split(" ", false):
			var w := w0
			while w.length() > max_chars:
				# Слово-монстр (в текстах таких нет, но без страховки
				# было бы зависание): рубим жёстко кусками.
				if cur != "":
					lines.append(cur)
					drops.append(dropped)
					dropped += 1
					cur = ""
				lines.append(w.left(max_chars))
				drops.append(dropped)
				w = w.substr(max_chars)
			var add := w if cur == "" else cur + " " + w
			if add.length() > max_chars:
				lines.append(cur)
				drops.append(dropped)
				dropped += 1
				cur = w
			else:
				cur = add
		if cur != "":
			lines.append(cur)
			drops.append(dropped)
	return {"lines": lines, "drops": drops}


## Таблица «логическое смещение → клетка»: переживает пересборку строк.
static func logical_cells(lines: Array, drops: Array) -> Dictionary:
	var out := {}
	var acc := 0
	for i in lines.size():
		var d := 0
		if i < drops.size():
			d = int(drops[i])
		for j in String(lines[i]).length():
			out[acc + j - d] = Vector2i(i, j)
		acc += String(lines[i]).length()
	return out


## Пересобрать строки под другую ширину, не сбив курсор и отметки.
## Курсор и отметки задаются клеткой СТАРОЙ сборки, на выходе —
## {"lines", "line", "pos", "table"}: table переводит логическое
## смещение старой сборки в клетку новой. Чистая функция, матрица в
## end_test (игра проходит уровень, который посреди набора сузили).
static func reflow(
	raw: Array[String], line: int, pos: int, max_chars: int
) -> Dictionary:
	# Старые строки — эталон: их смещения и есть логические.
	var want := pos
	for i in mini(line, raw.size()):
		want += String(raw[i]).length()
	var same: Array = raw.duplicate()
	if max_chars <= 0 or max_chars >= 36:
		return {
			"lines": same,
			"line": mini(line, same.size() - 1),
			"pos": pos,
			"table": logical_cells(same, []),
			"old": raw,
		}
	var m := fit_marked(raw, max_chars)
	var fresh: Array = m["lines"]
	var table := logical_cells(fresh, m["drops"])
	var cell: Vector2i = table.get(want, Vector2i(fresh.size(), 0))
	return {
		"lines": fresh, "line": cell.x, "pos": cell.y,
		"table": table, "old": raw,
	}


## Разбить длинные строки под ширину экрана (узкий телефон): режем по
## словам. Пробел на месте разрыва УБИРАЕМ: он всё равно невидим — за
## ним ничего нет, а игра ждёт нажатия. Игрок видел «строка кончилась,
## жми, дальше пусто» и не понимал, что нажимать (жалоба автора,
## 07.10.2026: уровень на телефоне не проходился). Разрыв строки сам
## разделяет слова, символы не теряются.
## Чистая функция, матрица в logic_test и end_test (игра проходит
## уровень целиком на узких экранах).
## Тексты с одиночными пробелами (проверено grep), двойные схлопнутся.
static func fit_lines(raw: Array[String], max_chars: int) -> Array[String]:
	var out: Array[String] = []
	for piece in fit_marked(raw, max_chars)["lines"]:
		out.append(String(piece))
	return out
