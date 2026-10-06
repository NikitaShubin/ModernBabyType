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


## Разбить длинные строки под ширину экрана (портрет телефона): режем
## по словам, пробел-разделитель уезжает в конец куска (пробел — тоже
## клетка, символы не теряются). Чистая функция, матрица в logic_test.
## Тексты с одиночными пробелами (проверено grep), двойные схлопнутся.
static func fit_lines(raw: Array[String], max_chars: int) -> Array[String]:
	var out: Array[String] = []
	for line in raw:
		if line.length() <= max_chars:
			out.append(line)
			continue
		var cur := ""
		for w0 in line.split(" ", false):
			var w := w0
			while w.length() > max_chars:
				# Слово-монстр (в текстах таких нет, но без страховки
				# было бы зависание): рубим жёстко кусками.
				if cur != "":
					out.append(cur + " ")
					cur = ""
				out.append(w.left(max_chars))
				w = w.substr(max_chars)
			var add := w if cur == "" else cur + " " + w
			if add.length() > max_chars:
				out.append(cur + " ")
				cur = w
			else:
				cur = add
		if cur != "":
			out.append(cur)
	return out
