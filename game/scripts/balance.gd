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


## Глобальные смещения строк по оси текста — в пространстве «все
## пробелы» (съеденные на разрывах пробелы считаются занятыми позициями,
## как в logical_cells). Иначе одна и та же буква имеет разные координаты
## до и после пересборки строк, и погоня рвётся на ровном месте
## (14.10.2026: зазор 46 → 76 при том же зайце — съеденных пробелов до
## курсора стало меньше). Разрыв строки не символ: конец строки — это
## начало следующей (см. _advance в main), а съеденный пробел — начало
## следующей строки (см. cell_for).
static func line_bases(lines: Array, drops: Array = []) -> Array:
	var out: Array = []
	var acc := 0
	for i in lines.size():
		out.append(acc)
		acc += String(lines[i]).length()
		if i + 1 < lines.size() and i + 1 < drops.size():
			acc += int(drops[i + 1]) - int(drops[i] if i < drops.size() else 0)
	return out


## Клетка по логическому смещению: первая строка, в которой смещение
## ещё внутри. Смещение на съеденном пробеле — начало следующей строки.
## За концом текста — Vector2i(size, 0): это «уровень набран» (так же
## считает _advance).
static func cell_at(lines: Array, base: Array, offset: int, drops: Array = []) -> Vector2i:
	for i in lines.size():
		if offset < int(base[i]) + String(lines[i]).length():
			return Vector2i(i, offset - int(base[i]))
		# Съеденный пробел между строками: начало следующей.
		if i + 1 < lines.size() and offset < int(base[i + 1]):
			return Vector2i(i + 1, 0)
	return Vector2i(lines.size(), 0)


## Разложить предложения по строкам экрана. hard[i] — «после этого
## предложения в источнике был перенос строки» (абзац, реплика диалога,
## строка стиха): там игра ждёт ↵. Предложения внутри абзаца СКЛЕИВАЮТСЯ
## в сплошной текст, как в Word (автор 13.10.2026: переносы строк «не надо
## ни исключать, ни добавлять»): видимый разрыв строки — либо перенос по
## ширине (мягкий, курсор едет сам), либо конец абзаца (жёсткий, ждёт ↵).
## Нет флага — считаем жёстким: физическая строка файла кончается
## переносом, если file_units не сказал иначе. Так прямые вызовы со
## строками файла (без флагов) ничего не склеивают.
## Пробел на месте разрыва по ширине УБИРАЕМ: он невидим, а клетка за ним
## была бы невидимым нажатием (жалоба автора 07.10.2026: уровень на
## телефоне не проходился). Разрыв сам разделяет слова, символы целы.
## Пробелы склейки предложений и переносы абзацев — обычные символы оси:
## в drops их нет, ось одна и та же до и после пересборки строк.
## Разложить предложения по строкам экрана. hard[i] — «после этого
## предложения в источнике был перенос строки» (абзац, реплика диалога,
## строка стиха): там игра ждёт ↵. Предложения внутри абзаца СКЛЕИВАЮТСЯ
## в сплошной текст, как в Word (автор 13.10.2026: переносы строк «не надо
## ни исключать, ни добавлять»): видимый разрыв строки — либо перенос по
## ширине (мягкий, курсор едет сам), либо конец абзаца (жёсткий, ждёт ↵).
## Нет флага — считаем жёстким: физическая строка файла кончается
## переносом, если file_units не сказал иначе. Так прямые вызовы со
## строками файла (без флагов) ничего не склеивают.
## glue_in[i] — строка i продолжает предыдущую БЕЗ пробела (кусок слова,
## разрезанного посередине): при пересборке клеится тоже без пробела,
## иначе рефлоу вставит пробел внутрь слова и ось уедет. Строка, уже
## кончающаяся пробелом, тоже клеится без добавки. Остальные мягкие
## строки клеятся через один пробел.
## Отдаём и свой glue (параллелен lines): первая строка абзаца — false.
## Пробел на месте переноса — ОБЫЧНАЯ КЛЕТКА в конце строки
## (автор 14.10.2026: «при автопереносе сам пробел надо нажимать, как в
## редакторе»): игрок жмёт пробел, курсор едет дальше сам. Съеденных
## пробелов больше нет (drops всегда нули); glue остался только для
## кусков разрезанных посередине слов.
static func fit_marked(
	raw: Array[String], max_chars: int, hard: Array = [], glue_in: Array = []
) -> Dictionary:
	var lines: Array[String] = []
	var drops: Array[int] = []
	var hard_out: Array[bool] = []
	var glue: Array[bool] = []
	if max_chars <= 0:
		for i in raw.size():
			var unit := String(raw[i])
			if unit == "":
				continue
			lines.append(unit)
			drops.append(0)
			hard_out.append(_unit_hard(hard, i))
			glue.append(bool(glue_in[i]) if i < glue_in.size() else false)
		return {"lines": lines, "drops": drops, "hard": hard_out, "glue": glue}
	var dropped := 0
	var para := ""
	var i := 0
	while i < raw.size():
		var unit := String(raw[i])
		if unit != "":
			if para == "" or para.ends_with(" "):
				para += unit
			elif i < glue_in.size() and bool(glue_in[i]):
				para += unit
			else:
				para += " " + unit
		# Абзац кончается переносом исходника или концом списка.
		# Жёсткая граница бьёт склейку: новый абзац всегда с пробела.
		if _unit_hard(hard, i) or i + 1 >= raw.size():
			if para != "":
				dropped = _wrap_para(para, max_chars, lines, drops, hard_out, glue, dropped)
				para = ""
		i += 1
	return {"lines": lines, "drops": drops, "hard": hard_out, "glue": glue}


## Флаг «после этой единицы перенос строки исходника». Нет флага —
## жёсткий (не склеивать чужое).
static func _unit_hard(hard: Array, i: int) -> bool:
	if i < hard.size():
		return bool(hard[i])
	return true


## Нарезать абзац по словам на строки не шире max_chars (строка с
## концевым пробелом — на знак шире: этот пробел набирается, см. выше).
## Возвращает счётчик (всегда 0, оставлен для формы). Первая строка
## абзаца — glue=false; дальше мягкие переносы — тоже false, а
## продолжение разрезанного посередине слова — true.
static func _wrap_para(
	para: String, max_chars: int, lines: Array[String], drops: Array[int],
	hard_out: Array[bool], glue: Array[bool], dropped: int
) -> int:
	if para.length() <= max_chars:
		lines.append(para)
		drops.append(dropped)
		hard_out.append(true)
		glue.append(false)
		return dropped
	var cur := ""
	# Остаток разрезанного слова, осевший в cur: строка с ним продолжает
	# слово без пробела (иначе склейка вставит пробел внутрь слова —
	# ловил матрицей: «принадлежала ;» вместо «принадлежала;»).
	var cur_glue := false
	for w0 in para.split(" ", false):
		var w := String(w0)
		var was_split := false
		while w.length() > max_chars:
			# Слово-монстр (на узком экране бывает и обычное длинное):
			# рубим жёстко кусками. Куски слова пробелом не кончаются,
			# все помечаются glue (включая первый: перед ним всегда
			# строка с концевым пробелом).
			if cur != "":
				lines.append(cur + " ")
				drops.append(dropped)
				hard_out.append(false)
				glue.append(cur_glue)
				cur = ""
				cur_glue = false
			lines.append(w.left(max_chars))
			drops.append(dropped)
			hard_out.append(false)
			glue.append(true)
			w = w.substr(max_chars)
			was_split = true
		var add := w if cur == "" else cur + " " + w
		if add.length() > max_chars:
			lines.append(cur + " ")
			drops.append(dropped)
			hard_out.append(false)
			glue.append(cur_glue)
			cur = w
			cur_glue = false
		else:
			cur = add
			# Остаток резки осел в cur первым: строка с ним продолжает
			# слово (см. cur_glue выше).
			if was_split:
				cur_glue = true
	if cur != "":
		lines.append(cur)
		drops.append(dropped)
		hard_out.append(true)
		glue.append(cur_glue)
	return dropped


## Таблица «логическое смещение → клетка»: переживает пересборку строк.
static func logical_cells(lines: Array, drops: Array) -> Dictionary:
	# Таблица «логическое смещение → клетка» в пространстве «все пробелы»:
	# выкинутые на разрывах пробелы считаются занятыми позициями. Иначе
	# старые смещения (с пробелами) ищутся в новой таблице (без них) и
	# всё уезжает на число выкинутых пробелов (10.2026: метки и курсор
	# после поворота вставали не на те буквы).
	var out := {}
	var acc := 0
	for i in lines.size():
		var d := 0
		if i < drops.size():
			d = int(drops[i])
		for j in String(lines[i]).length():
			out[acc + j] = Vector2i(i, j)
		acc += String(lines[i]).length()
		if i + 1 < drops.size():
			acc += int(drops[i + 1]) - d
	return out


## Клетка по логическому смещению со сдвигом вперёд через съеденные
## пробелы: смещение, попавшее ровно на съеденный новой вёрсткой пробел,
## принадлежит НАЧАЛУ следующей строки (туда же _advance увозит курсор
## мягким переносом). Без сдвига курсор на таком пробеле падал в
## (size, 0), а метка молча исчезала (14.10.2026: курсор 4:5 → 14:0).
## Разрывы съедают по одному пробелу, поэтому сдвига на +2 хватает
## с запасом; дальше — fallback (конец уровня / снять метку).
static func cell_for(table: Dictionary, want: int, fallback: Vector2i) -> Vector2i:
	var off := want
	while off <= want + 2:
		if table.has(off):
			return table[off]
		off += 1
	return fallback


## Пересобрать строки под другую ширину, не сбив курсор и отметки.
## Курсор и отметки задаются клеткой СТАРОЙ сборки, на выходе —
## {"lines", "line", "pos", "table"}: table переводит логическое
## смещение старой сборки в клетку новой. Чистая функция, матрица в
## end_test (игра проходит уровень, который посреди набора сузили).
static func reflow(
	raw: Array[String], line: int, pos: int, max_chars: int,
	old_drops: Array = [], hard: Array = [], glue_in: Array = []
) -> Dictionary:
	# Логическое смещение — в пространстве «все пробелы»: старые строки
	# могли потерять пробелы на разрывах (их считает old_drops), новые —
	# теряют свои (считает таблица). Без этого курсор и метки после
	# поворота встают не на те буквы: старые смещения искали в новой
	# таблице как есть и уезжали на число выкинутых пробелов (10.2026).
	var want := pos
	for i in mini(line, raw.size()):
		want += String(raw[i]).length()
	if line < old_drops.size():
		want += int(old_drops[line])
	var same: Array = raw.duplicate()
	if max_chars <= 0:
		return {
			"lines": same,
			"line": mini(line, same.size() - 1),
			"pos": pos,
			"table": logical_cells(same, []),
			"drops": old_drops.duplicate(),
			"hard": hard.duplicate(),
			"glue": glue_in.duplicate(),
			"old": raw,
		}
	# Мягкие строки склеиваются обратно в абзацы (пробел — тот же, что
	# съел перенос; куски слов — без него, см. glue) и режутся под новую
	# ширину. Абзацный текст с обеих сторон один и тот же, поэтому
	# логическая ось не рвётся.
	var m := fit_marked(raw, max_chars, hard, glue_in)
	var fresh: Array = m["lines"]
	var table := logical_cells(fresh, m["drops"])
	var cell: Vector2i = cell_for(table, want, Vector2i(fresh.size(), 0))
	return {
		"lines": fresh, "line": cell.x, "pos": cell.y,
		"table": table, "drops": m["drops"], "hard": m["hard"],
		"glue": m["glue"], "old": raw,
	}


## Разложить текст по строкам экрана (любая ширина: и телефон, и
## десктоп — иначе длинная строка вылезает за карточку и её не видно,
## жалоба автора 13.10.2026). Предложения внутри абзаца склеиваются,
## абзац режется по словам. Пробел на месте разрыва УБИРАЕМ: он всё равно
## невидим — за ним ничего нет, а клетка за ним была бы невидимым
## нажатием (жалоба автора 07.10.2026: уровень на телефоне не
## проходился). Разрыв строки сам разделяет слова, символы не теряются.
## Чистая функция, матрица в logic_test и end_test (игра проходит
## уровень целиком на любых экранах).
## Тексты с одиночными пробелами (проверено grep), двойные схлопнутся.
static func fit_lines(
	raw: Array[String], max_chars: int, hard: Array = [], glue_in: Array = []
) -> Array[String]:
	var out: Array[String] = []
	for piece in fit_marked(raw, max_chars, hard, glue_in)["lines"]:
		out.append(String(piece))
	return out
