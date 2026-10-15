extends SceneTree
## Визуальный драйвер меню: поднимает НАСТОЯЩУЮ сцену меню в окне
## телефона (портрет) и снимает ключевые состояния — карточки игроков,
## переключение галочки с пояснением, поле ввода со своей клавиатурой,
## подтверждение удаления — и для сравнения таблицу в альбоме.
##
## Зачем при живом рендере: headless-проверки меряют прямоугольники, но
## не видят, что текст в них помещается, а кнопки не наезжают на имя.
## Именно это ломалось в портрете (имя уходило в многоточие из двух
## букв) — карточками.
##
## Запуск (НЕ headless — нужен настоящий рендер):
##   DISPLAY=:99 tools/docker/build-game.sh --visual
## Кадры: /tmp/opencode/vis-menu-*.png

const SAVE_DIR := "/tmp/opencode/"
const S := preload("res://scripts/save.gd")

var _menu: Node = null
var _frame := 0
var _shot_i := 0
## Очередь шагов: [имя кадра, действие, сколько кадров ждать].
var _steps: Array = []
var _wait := 0
var _tag := ""


func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/menu.tscn")
	_menu = scene.instantiate()
	root.add_child(_menu)
	for u in S.user_list():
		S.delete_user(u)


## Окно телефона: И через DisplayServer, И у корня (как в visual_driver) —
## под полноэкранным режимом один вызов не срабатывает.
func _win(wh: Vector2i) -> void:
	DisplayServer.window_set_size(wh)
	root.size = wh
	_menu.call("_relayout")


## Кадр + геометрия списка одной строкой: что где должно быть.
func _snap() -> void:
	_shot_i += 1
	var img := root.get_texture().get_image()
	var name := "vis-menu-%02d-%s" % [_shot_i, _tag]
	print(
		"КАДР_РАЗМЕР %d %d меню %.0fx%.0f k=%.3f карточки=%s" % [
			img.get_width(), img.get_height(),
			_menu.view_w, _menu.view_h, _menu.k, str(_menu.call("_cards")),
		]
	)
	img.save_png(SAVE_DIR + name + ".png")
	for i in _menu.users.size():
		var c: Rect2 = Rect2(_menu.call("_card_rect", i))
		var p: Rect2 = Rect2(_menu.call("_pro_tap_rect", i))
		print(
			"  КАРТОЧКА %d %s кнопка=%s имя=«%s»" % [
				i, str(c), str(p), String(_menu.call("_short_name", _menu.users[i])),
			]
		)
	print("КАДР ", SAVE_DIR + name + ".png")


func _users(n: int) -> void:
	for u in S.user_list():
		S.delete_user(u)
	for i in n:
		S.create_user(["Таня", "Федя", "Маруся"][i])
	# Разные флаги: карточка должна читаться без подсказки.
	S.set_all_keys("Федя", true)
	S.set_yo_strict("Федя", false)
	S.set_all_keys("Маруся", false)
	_menu.call("_reload")
	_menu.visible = true
	_menu.confirm_name = ""
	_menu.input_active = false
	_menu.sel = 1


## Телефон портретом: окно 540x1140 при плотности 2 — те же пропорции,
## что у настоящего 1080x2280 (масштаб ~0.98), но окно влезает в стенд.
func _a_phone_cards() -> void:
	Ui.dpr_override = 2.0
	_win(Vector2i(540, 1140))
	_users(3)


## Тап по галочке «Про» второй карточки: чип заливается и внизу
## появляется пояснение (в карточках шапки колонок нет).
func _a_tap_pro() -> void:
	var pro_pos: Vector2 = Rect2(_menu.call("_pro_tap_rect", 1)).get_center()
	_menu.call("_input", _tap(pro_pos))
	_menu.call("_input", _release(pro_pos))


func _a_name_field() -> void:
	_menu.input_active = true
	_menu.input_text = "Ма"
	_menu.queue_redraw()


func _a_delete_confirm() -> void:
	_menu.input_active = false
	_menu.input_text = ""
	var del_pos: Vector2 = Rect2(_menu.call("_del_tap_rect", 0)).get_center()
	_menu.call("_input", _tap(del_pos))
	_menu.call("_input", _release(del_pos))


func _a_night() -> void:
	_menu.call("_cancel_confirm")
	_menu.night = true
	_menu.call("_apply_night")


func _a_landscape_table() -> void:
	_menu.night = false
	_menu.call("_apply_night")
	_win(Vector2i(1000, 700))


func _tap(pos: Vector2) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = pos
	return ev


func _release(pos: Vector2) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = false
	ev.position = pos
	return ev


func _process(_dt: float) -> bool:
	_frame += 1
	if _frame < 3:
		return false
	if _frame == 3:
		_plan()
	if _steps.is_empty() and _wait <= 0:
		return true
	if _wait > 0:
		_wait -= 1
		if _wait == 0:
			_snap()
		return false
	var step: Array = _steps.pop_front()
	_tag = String(step[0])
	step[1].call()
	_wait = int(step[2])
	return false


## Сценарий: состояния меню, которые должны быть видны на экране.
func _plan() -> void:
	_steps = [
		["01-cards", _a_phone_cards, 12],
		["02-chip-hint", _a_tap_pro, 12],
		["03-name-field", _a_name_field, 12],
		["04-delete", _a_delete_confirm, 12],
		["05-night", _a_night, 12],
		["06-table", _a_landscape_table, 12],
	]