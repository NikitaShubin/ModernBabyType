extends SceneTree
## Измерительный стенд (временный, не тест): гоняем настоящий текст с
## серией ошибок и после каждого нажатия печатаем координаты обоих
## персонажей и ВСЕ красные метки с их осью. Нужен, чтобы оценить
## словами то, что автор видит на телефоне («стек красных букв
## перескакивает»), до того, как это станет жалобой.

var _main: Node = null
var _step := 0
var _frame := 0


func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	_main = scene.instantiate()
	_main.skip_menu = true
	_main.all_keys_override = 1
	root.add_child(_main)


func _cell_ch(l: int, p: int) -> String:
	if l < 0 or l >= _main.display_lines.size():
		return ""
	var line: String = _main.display_lines[l]
	if p < 0 or p >= line.length():
		return ""
	return line.substr(p, 1)


func _dump(what: String) -> void:
	_step += 1
	var l := int(_main.cursor_line)
	var p := int(_main.cursor_pos)
	var lin: float = _main._lin(l, float(p))
	var cur := _cell_ch(l, p)
	var marks: Array[String] = []
	for k in _main.errors.keys():
		var parts: PackedStringArray = String(k).split(":")
		var ml := int(parts[0])
		var mp := int(parts[1])
		var mch := _cell_ch(ml, mp)
		marks.append("%d:%d[%s→%s %s]" % [
			ml, mp, mch, String(_main.errors[k]),
			"АКТ" if _main._is_active(mch) else "сер",
		])
	marks.sort()
	print("шаг %02d %-8s курсор=%d:%d '%s'%s ось=%.1f заяц.x=%.0f ёж.x=%.0f d=%.1f метки(%d)=%s" % [
		_step, what, l, p, cur,
		"" if cur == "" or _main._is_active(cur) else " СЕРАЯ",
		lin, _main.hero_r.x, _main.enemy_x,
		_main._lin(int(_main.enemy_line), (_main.enemy_x - _main.margin) / _main.char_w) - lin,
		_main.errors.size(), " ".join(marks),
	])


func _wrong() -> String:
	var cur: String = _main._current()
	return "ы" if cur.to_lower() != "ы" else "ж"


func _type_right() -> void:
	var ch: String = _main._current()
	if ch != "":
		_main._type_char(ch)


func _run() -> void:
	_run_mode("ВСЕ КЛАВИШИ (серых нет)", 1)
	_run_mode("ОБЫЧНЫЙ (буквы серые)", 0)


func _run_mode(title: String, all_keys: int) -> void:
	_main.all_keys_override = all_keys
	_main._new_level()
	# Ёж стоит сзади и не идёт: смотрим только метки и откат.
	_main.grace_t = 9999.0
	_main.hedge_active = true
	_main.enemy_cps = 0.0
	_main.enemy_line = 0
	_main.enemy_x = _main.margin
	_main.hero_r = _main._hero_pos()
	print("=== %s" % title)
	print("=== строка 0: «%s»" % _main.display_lines[0])
	print("=== активные: %s" % str(_main.active.keys()))
	_dump("старт")
	# 1) Набираем 10 активных букв подряд правильно.
	for i in 10:
		_type_right()
		_dump("верно")
	# 2) Серия из 4 ошибок подряд — то, на что жалуется автор.
	for i in 4:
		_main._type_char(_wrong())
		_dump("ОШИБКА")
	# 3) Двигаем экранные координаты: заяц едет к клетке кадрами.
	for i in 12:
		_step += 1
		print("кадр %02d  заяц.x=%7.1f клетка.x=%7.1f отставание=%.1f симв.  ёж.x=%7.1f  курсор=%d:%d метки=%d" % [
			i, _main.hero_r.x, _main._cursor_cx(),
			(_main._cursor_cx() - _main.hero_r.x) / _main.char_w,
			_main.enemy_x, _main.cursor_line, _main.cursor_pos,
			_main.errors.size(),
		])
	# 4) И снова правильные буквы: смотрим, куда придётся идти.
	for i in 6:
		_type_right()
		_dump("верно")
	# 5) Backspace четыре раза подряд — разбираем стек меток.
	for i in 4:
		_main._backspace()
		_dump("BACK")


func _process(_dt: float) -> bool:
	_frame += 1
	if _frame == 4:
		_run()
	if _frame > 6:
		return true
	return false