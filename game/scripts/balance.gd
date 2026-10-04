class_name Balance
extends RefCounted
## Чистая логика сложности. Без узлов сцены, только числа.
## Ключевое отличие от legacy (main.py): скорость врага измеряется
## в символах/сек, а не в px/сек, поэтому не зависит от ширины окна.

const KEY_PROGRESSION := " аовлыдфжпреимтнгрушщзхъёйчясмитьбю,.!?-:;\"'()1234567890"
const INITIAL_ACTIVE_COUNT := 3
const WINS_TO_LEVEL_UP := 3
const BASE_CPS := 2.0
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


## Целевая скорость врага: растёт с уровнем и подстраивается под
## скользящее среднее темпа игрока (EMA CPM). Игрок ~120 CPM => skill 1.0.
static func target_cps(difficulty_level: int, ema_cpm: float) -> float:
	var skill := 1.0
	if ema_cpm > 0.0:
		skill = clampf(ema_cpm / 120.0, 0.5, 1.6)
	var cps := BASE_CPS * (1.0 + 0.12 * float(difficulty_level)) * skill
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
