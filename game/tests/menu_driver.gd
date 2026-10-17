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
	for i in _menu.call("_row_count"):
		var c: Rect2 = Rect2(_menu.call("_card_rect", i))
		var p: Rect2 = Rect2(_menu.call("_pro_tap_rect", i))
		print(
			"  КАРТОЧКА %d %s кнопка=%s правка=%s" % [
				i, str(c), str(p), str(_menu.editing == i),
			]
		)
	print(
		"  ОКНО %s кнопки=%.0f подсказка=%.0f прокрутка=%.0f" % [
			str(Rect2(_menu.call("_list_rect"))),
			float(_menu.call("_buttons_y")),
			float(_menu.call("_chip_hint_y")),
			_menu._scroll,
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
	_menu.call("_start_edit", _menu.users.size())
	_menu.input_text = "Ма"
	_menu.queue_redraw()


func _a_delete_confirm() -> void:
	_menu.call("_cancel_edit")
	var del_pos: Vector2 = Rect2(_menu.call("_del_tap_rect", 0)).get_center()
	_menu.call("_input", _tap(del_pos))
	_menu.call("_input", _release(del_pos))


func _a_night() -> void:
	_menu.call("_cancel_confirm")
	# Добиваем список, чтобы было что листать: скроллбар проверяем ночью.
	for n in ["Гена", "Дина", "Егор", "Жанна", "Зоя"]:
		S.create_user(n)
	_menu.call("_reload")
	# Ночь — через режим, а не флагом: _apply_night пересчитывает флаг
	# из режима (флаг напрямую не липнет).
	_menu.nmode = S.NIGHT_ON
	_menu.call("_apply_night")
	_menu._scroll_target = float(_menu.call("_list_max_scroll")) * 0.5
	_menu._scroll = _menu._scroll_target


func _a_landscape_table() -> void:
	_menu.nmode = S.NIGHT_DAY
	_menu.call("_apply_night")
	_win(Vector2i(1000, 700))


## Ховер над заголовком «Победы»: таймер взведён руками (ждать полсекунды
## реального времени драйвер не умеет), пузырь — у курсора.
func _a_hover_tip() -> void:
	var p: Vector2 = Rect2(_menu.call("_rec_head_rect")).get_center()
	_menu._hover_pos = p
	_menu._hover_t = 1.0
	_menu.queue_redraw()
	print("ХОВЕР «Победы» в %s: «%s»" % [str(p), String(_menu.call("_head_tip_at", p))])


## Обратно в портрет: строчное редактирование (автор 15.10.2026).
func _a_phone_again() -> void:
	_win(Vector2i(540, 1140))


## Строка создания: дабл-клик по ней открывает чистое поле ввода
## с чипами «Про» и «Ё» и крестиком отмены (одинарный только выделяет).
## Создание кнопкой «+ Новый игрок»: внизу, постоянного пункта в списке
## нет. Строка ввода появляется в конце и подтягивается в окно.
func _a_create_open() -> void:
	var p: Vector2 = Rect2(_menu.call("_new_tap_rect")).get_center()
	_menu.call("_input", _tap(p))
	_menu.call("_input", _release(p))
	_menu._scroll = _menu._scroll_target
	_menu.input_text = "Ново"


## Enter в поле — новая строка внизу списка, без автозапуска игры.
func _a_create_commit() -> void:
	_menu.call("_commit_edit")
	print("ПОСЛЕ СОЗДАНИЯ: %s выделен=%d" % [str(_menu.users), _menu.sel])


## ПКМ по строке — переименование: поле с прежним именем.
func _a_rename_open() -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_RIGHT
	ev.pressed = true
	ev.position = Rect2(_menu.call("_row_tap_rect", 0)).get_center()
	_menu.call("_input", ev)
	_menu.input_text = "Марья"


## Esc в переименовании возвращает прежний вид, имя в списке цело.
func _a_rename_cancel() -> void:
	_menu.call("_cancel_edit")


## Список пролистан в самый низ: строка создания на виду.
func _a_scroll_end() -> void:
	_menu.call("_input", _wheel_down())
	_menu.call("_input", _wheel_down())
	_menu.call("_input", _wheel_down())
	_menu.call("_input", _wheel_down())


func _wheel_down() -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_WHEEL_DOWN
	ev.pressed = true
	ev.position = Vector2(_menu.view_w * 0.5, _menu.view_h * 0.4)
	return ev


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
		["07-hover-tip", _a_hover_tip, 6],
		["08-back-portrait", _a_phone_again, 4],
		["09-create-open", _a_create_open, 12],
		["10-created", _a_create_commit, 12],
		["11-rename-open", _a_rename_open, 12],
		["12-rename-cancel", _a_rename_cancel, 12],
		["13-scrolled-end", _a_scroll_end, 12],
	]