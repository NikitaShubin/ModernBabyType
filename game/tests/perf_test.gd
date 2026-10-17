extends SceneTree
## Тест производительности отрисовки (автор 16.10.2026): меню тянуло
## сохранения с диска на КАЖДЫЙ кадр (103 чтения на кадр, ~14 мс на
## кадр в headless) — анимация зайца шла рывками. Проверяем, чтобы это
## не вернулось молча:
##   1) ни одного чтения конфига на кадр отрисовки;
##   2) объекты не плодятся кадрами (нет аллокаций StyleBox/словарей);
##   3) кадр меню и кадр игры укладываются в бюджет 60 Гц.
## Запуск: godot --headless --path game --script res://tests/perf_test.gd

const S := preload("res://scripts/save.gd")
## Бюджет кадра при 60 Гц. Меряем без vsync, в headless — это ЧИСТАЯ
## стоимость отрисовки, запас большой намеренно: тест ловит возврат
## порядка величины (чтение файла на кадр), а не дрожание таймера.
const BUDGET_MS := 16.0

var _failures: Array[String] = []
var _menu: Node = null
var _game: Node = null


func _check(cond: bool, what: String) -> void:
	if not cond:
		_failures.append(what)


func _initialize() -> void:
	var menu_scene: PackedScene = load("res://scenes/menu.tscn")
	_menu = menu_scene.instantiate()
	root.add_child(_menu)
	_menu.visible = true


func _process(_dt: float) -> bool:
	_menu_cfg_reads()
	_menu_no_alloc()
	_menu_budget()
	_game_budget()
	_report()
	return true


## 1) Отрисовка меню не читает конфиг с диска.
func _menu_cfg_reads() -> void:
	_seed_users(10)
	_menu.view_w = 1000.0
	_menu.view_h = 700.0
	_menu.k = 1.8
	_menu.call("_relayout")
	_menu.view_w = 1000.0
	_menu.view_h = 700.0
	_menu.k = 1.8
	_menu.call("_reload")
	_menu.call("_draw")
	var before: int = S.cfg_loads
	for i in 100:
		_menu.call("_draw")
	_check(
		S.cfg_loads == before,
		"100 кадров меню прочитали конфиг %d раз" % (S.cfg_loads - before)
	)


## 2) Кадры не плодят объекты: ни StyleBox, ни словарей на кадр.
func _menu_no_alloc() -> void:
	_menu.call("_start_edit", _menu.users.size())
	_menu.call("_draw")
	var before := Performance.get_monitor(Performance.OBJECT_COUNT)
	for i in 100:
		_menu.call("_draw")
	var grown := Performance.get_monitor(Performance.OBJECT_COUNT) - before
	_check(grown == 0, "100 кадров меню создали %d объектов" % grown)
	_menu.call("_cancel_edit")


## 3) Кадр меню — в бюджете 60 Гц.
func _menu_budget() -> void:
	var ms := _frame_ms(func() -> void: _menu.call("_draw"), 100)
	print("  кадр меню: %.2f мс (%.0f fps)" % [ms, 1000.0 / maxf(ms, 0.001)])
	_check(ms < BUDGET_MS, "кадр меню %.2f мс — вне бюджета %.0f мс" % [ms, BUDGET_MS])


## 3b) Кадр игры — тоже: текст уровня и герои рисуются каждый кадр.
func _game_budget() -> void:
	if _game == null:
		var scene: PackedScene = load("res://scenes/main.tscn")
		_game = scene.instantiate()
		_game.skip_menu = true
		_game.all_keys_override = 1
		root.add_child(_game)
		S.create_user("Тестер")
		_game.profile_name = "Тестер"
		_game._start_game()
	_game.call("_draw")
	var ms := _frame_ms(func() -> void: _game.call("_draw"), 100)
	print("  кадр игры: %.2f мс (%.0f fps)" % [ms, 1000.0 / maxf(ms, 0.001)])
	_check(ms < BUDGET_MS, "кадр игры %.2f мс — вне бюджета %.0f мс" % [ms, BUDGET_MS])


## Стоимость n вызовов fn на кадр, мс на кадр.
func _frame_ms(fn: Callable, n: int) -> float:
	var t0 := Time.get_ticks_usec()
	for i in n:
		fn.call()
	return float(Time.get_ticks_usec() - t0) / float(n) / 1000.0


func _seed_users(n: int) -> void:
	for u in S.user_list():
		S.delete_user(u)
	for i in n:
		S.create_user("Игрок%02d" % i)


func _report() -> void:
	if _failures.is_empty():
		print("PERF_TEST: PASS")
	else:
		for f in _failures:
			print("PERF_TEST: FAIL: ", f)
	quit(1 if not _failures.is_empty() else 0)
