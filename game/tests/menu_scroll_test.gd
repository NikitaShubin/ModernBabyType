extends SceneTree
## Регресс видимости выбранной строки списка (автор 16.10.2026): обёртка
## через край и возврат после создания прятали верхнюю строку боксом под
## маску — расчёт целился линией строки, а бокс таблицы начинается на 38k
## выше неё. Тесты — чистой математикой: ставим состояние, доводим цель
## до факта рывком (без ожидания догона) и сверяем бокс с окном.
## Запуск: godot --headless --path game --script res://tests/menu_scroll_test.gd

const S := preload("res://scripts/save.gd")
const EPS := 0.05

var _failures: Array[String] = []
var _menu: Node = null


func _check(cond: bool, what: String) -> void:
	if not cond:
		_failures.append(what)


func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/menu.tscn")
	_menu = scene.instantiate()
	root.add_child(_menu)
	_menu.visible = true


func _process(_dt: float) -> bool:
	_cards_mode()
	_table_mode()
	_report()
	return true


func _fresh(names: Array[String]) -> void:
	for u in S.user_list():
		S.delete_user(u)
	for n in names:
		S.create_user(n)
	_menu.call("_reload")
	_menu.sel = 0
	_menu._scroll = 0.0
	_menu._scroll_target = 0.0


func _fit_cards() -> void:
	_menu.view_w = 540.0
	_menu.view_h = 1140.0
	_menu.k = 1.0


func _fit_table() -> void:
	_menu.view_w = 1000.0
	_menu.view_h = 700.0
	_menu.k = 1.8


## Рывок: цель посчитана — принимаем как факт (догон проверен пробами).
func _snap() -> void:
	_menu._scroll = _menu._scroll_target


## Бокс выбранной строки целиком в окне списка.
func _sel_visible(tag: String) -> void:
	var view: Rect2 = _menu.call("_list_rect")
	var chip: Rect2 = Rect2(_menu.call("_row_draw_rect", _menu.sel))
	_check(
		chip.position.y >= view.position.y - EPS,
		"%s: верх %.2f за окном %.2f" % [tag, chip.position.y, view.position.y]
	)
	_check(
		chip.end.y <= view.end.y + EPS,
		"%s: низ %.2f за окном %.2f" % [tag, chip.end.y, view.end.y]
	)


func _mode(tag: String) -> void:
	_fresh(["Аня", "Боря", "Вера", "Гена", "Дина", "Егор", "Жанна", "Зоя"])
	var n: int = _menu.users.size()
	_check(_menu.call("_list_max_scroll") > 0.0, tag + ": список листается")
	# К каждой строке — с обоих краёв: сверху вниз и снизу вверх.
	for i in n:
		_menu.sel = i
		_menu._scroll = _menu.call("_list_max_scroll")
		_menu._scroll_target = _menu._scroll
		_menu.call("_scroll_to_sel")
		_snap()
		_sel_visible("%s: к строке %d сверху" % [tag, i])
	for i in n:
		_menu.sel = i
		_menu._scroll = 0.0
		_menu._scroll_target = 0.0
		_menu.call("_scroll_to_sel")
		_snap()
		_sel_visible("%s: к строке %d снизу" % [tag, i])
	# Обёртка вниз: с конца — в начало, верхняя строка целиком в окне.
	_menu.sel = n - 1
	_menu._scroll = _menu.call("_list_max_scroll")
	_menu._scroll_target = _menu._scroll
	_menu.call("_nav", 1)
	_check(_menu.sel == 0, tag + ": обёртка вниз на первую")
	_snap()
	_sel_visible(tag + ": первая после обёртки")
	# Обёртка вверх: с начала — в конец.
	_menu.sel = 0
	_menu._scroll = 0.0
	_menu._scroll_target = 0.0
	_menu.call("_nav", -1)
	_check(_menu.sel == n - 1, tag + ": обёртка вверх на последнюю")
	_snap()
	_sel_visible(tag + ": последняя после обёртки")
	# Возврат после создания: новый игрок сверху — целиком в окне.
	S.create_user("Юля")
	_menu.call("_reload")
	_menu.sel = _menu.users.find("Юля")
	_menu.call("_scroll_to_sel")
	_snap()
	_sel_visible(tag + ": новая сверху")
	# Якорь: колесо и drag не увозят фокус из окна.
	_menu.sel = 2
	_menu._scroll = 0.0
	_menu._scroll_target = 0.0
	for i in 20:
		_wheel(1)
	_snap()
	_sel_visible(tag + ": якорь держит при колесе")
	_check(
		_menu._scroll_target < _menu.call("_list_max_scroll"),
		tag + ": упор раньше дна (якорь, а не край)"
	)
	_drag_far()
	_snap()
	_sel_visible(tag + ": якорь держит при drag")


func _cards_mode() -> void:
	_fit_cards()
	_mode("карточки")


func _table_mode() -> void:
	_fit_table()
	_mode("таблица")


func _wheel(down: int) -> void:
	var view: Rect2 = _menu.call("_list_rect")
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_WHEEL_DOWN if down > 0 else MOUSE_BUTTON_WHEEL_UP
	ev.pressed = true
	ev.position = view.get_center()
	_menu.call("_input", ev)


func _drag_far() -> void:
	var p: Vector2 = Rect2(_menu.call("_row_tap_rect", _menu.sel)).get_center()
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = p
	_menu.call("_input", press)
	var mv := InputEventMouseMotion.new()
	mv.position = p + Vector2(0.0, 600.0)
	mv.relative = Vector2(0.0, 600.0)
	mv.button_mask = MOUSE_BUTTON_MASK_LEFT
	_menu.call("_input", mv)
	var rel := InputEventMouseButton.new()
	rel.button_index = MOUSE_BUTTON_LEFT
	rel.pressed = false
	rel.position = p + Vector2(0.0, 600.0)
	_menu.call("_input", rel)


func _report() -> void:
	if _failures.is_empty():
		print("MENU_SCROLL_TEST: PASS")
	else:
		for f in _failures:
			print("MENU_SCROLL_TEST: FAIL: ", f)
	quit(1 if not _failures.is_empty() else 0)
