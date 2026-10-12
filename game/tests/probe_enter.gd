extends SceneTree
## Перенос строки по ↵ и его откат: игра стоит на конце строки, ↵ переносит,
## Backspace возвращает на последнюю букву, в последней строке уровень
## кончается сам. Плюс ПРО-режим: ввод на доске падавно.

const Kbd := preload("res://scripts/kbd.gd")

var _main: Node = null
var _f := 0
var _log: Array = []
var _area: Rect2 = Rect2()


func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	_main = scene.instantiate()
	_main.skip_menu = true
	root.add_child(_main)


func _show(what: String) -> void:
	_log.append(
		"%s: %d:%d ждёт=«%s» ждём_ввод=%s ввод_на_доске=%s состояние=%s"
		% [what, _main.cursor_line, _main.cursor_pos, _main._current(),
			str(bool(_main.need_enter)), str(bool(_main._kb_enter_shown())),
			String(_main.state)]
	)


func _key(label: String) -> Vector2:
	for b in Kbd.buttons(_area, bool(_main.kb_shift), _main._kb_enter_shown()):
		if String(b["s"]) == label:
			return (b["r"] as Rect2).get_center()
	return Vector2(-1, -1)


func _type(sym: String) -> void:
	_main._type_char(sym)
	_main.hero_r = _main._hero_pos()


func _process(_dt: float) -> bool:
	_f += 1
	if _f == 2:
		DisplayServer.window_set_size(Vector2i(820, 1180))
		root.size = Vector2i(820, 1180)
		_main._force_touch = true
		_main._relayout()
	if _f < 4:
		return false
	if _f == 4:
		_run()
	for l in _log:
		print(l)
	quit()
	return true


func _text(lines: Array[String], open_all: bool) -> void:
	_main.display_lines = lines
	_main.line_drops = []
	_main._reindex_lines()
	_main._refresh_home_chars()
	_main.active.clear()
	if open_all:
		for line in lines:
			for i in line.length():
				_main.active[line.substr(i, 1)] = true
	else:
		for ch in ["ф", "ы", "в", "а", "п", "р", "о", "л", "д", "ж", "э"]:
			_main.active[ch] = true
	_main.cursor_line = 0
	_main.cursor_pos = 0
	_main.need_enter = false
	_main.typed_ok = 0
	_main.typed_bad = 0
	_main.errors.clear()
	_main.passed.clear()
	_main.typed_cells.clear()
	_main.state = "playing"
	_main._refresh()
	_area = _main._own_rect()


func _run() -> void:
	_main.all_keys_override = 1
	_main.kb_lang = "ru"
	_main.kb_shift = false
	_main.difficulty = 0
	_main._new_level()
	_main.grace_t = 9999.0
	_main.enemy_cps = 0.0
	_main.hedge_active = false

	# 1. Перенос ждёт ↵, Backspace возвращает назад.
	_text(["мама", "мыла"], true)
	for ch in ["м", "а", "м", "а"]:
		_type(ch)
	_show("1. конец строки")
	_main._backspace()
	_main.hero_r = _main._hero_pos()
	_show("1. Backspace назад")
	_main._own_press(_key("↵"))
	_main.hero_r = _main._hero_pos()
	_show("1. ↵ на доске")

	# 2. Физический ↵ переносит так же.
	_text(["мама", "мыла"], true)
	for ch in ["м", "а", "м", "а"]:
		_type(ch)
	_main.call("_unhandled_key_input", _hardkey(KEY_ENTER, 13))
	_show("2. физический ↵")

	# 3. Последняя строка: уровень кончается сам, ввода не требует.
	_text(["мама"], true)
	for ch in ["м", "а", "м", "а"]:
		_type(ch)
	_show("3. конец единственной строки")

	# 4. ПРО-режим (буквы не открыты): ввод на доске падавно.
	_text(["мама", "мыла"], false)
	_show("4. ПРО: ввод есть")
	_type("м")
	_show("4. ПРО: серая буква прошла сама")

	# 5. Обычный режим: ввода нет, пока хоть одна буква центрального ряда
	#    текста не открыта.
	_main.all_keys_override = 0
	_text(["бмм", "ыыы"], false)
	_main.active.clear()
	_main.active["б"] = true
	_main.active["ы"] = true
	_main.cursor_line = 0
	_main.cursor_pos = 0
	_main.need_enter = false
	_main.state = "playing"
	_show("5. ряд открыт частично")
	# active — словарь КЛЮЧЕЙ (active.has), присваивание false ключ не
	# убирает: стирать через erase.
	_main.active.erase("ы")
	_show("5. ряд не открыт")
	_main.all_keys_override = 1
	_main.cursor_line = 0
	_main.cursor_pos = 0
	_main.need_enter = false
	_main.state = "playing"
	_show("5. без центрального ряда")


func _hardkey(code: int, uni: int) -> InputEventKey:
	var ke := InputEventKey.new()
	ke.keycode = code
	ke.unicode = uni
	ke.pressed = true
	return ke
