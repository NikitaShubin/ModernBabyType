extends SceneTree
## Визуальный драйвер песочницы кистей: поднимает scenes/hands.tscn в
## окне телефона (портрет) и альбомном окне, снимает:
##   01      — покой обеих кистей (день);
##   03/04   — тап по букве левой руки и его хвост;
##   05/06   — тап по нижнему ряду (ход кисти) и хвост;
##   07..12  — служебные: пробел (большой и оппозиция), шифт, бе-
##             кспейс, глобус — каждое нажатие ставит палец в позу;
##   13      — альбом: те же кисти при другом окне.
## Кадры /tmp/opencode/vis-hands-*.png. Рендер живой (не headless).
## Запуск: tools/docker/build-game.sh --visual

const SAVE_DIR := "/tmp/opencode/"

var _hands: Node = null
var _frame := 0
var _shot_i := 0
var _wait := 0
var _tag := ""
var _pending := ""


func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/hands.tscn")
	_hands = scene.instantiate()
	root.add_child(_hands)


## Окно — И через DisplayServer, И у корня (как в прочих драйверах).
func _win(wh: Vector2i) -> void:
	# Полноэкранный проект держит размер экрана Xvfb — см. visual_driver.
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(wh)
	root.size = wh
	_hands.call("_relayout")


## Снимок ОТЛОЖЕН на кадр: root.get_texture() держит ПРЕДЫДУЩИЙ
## нарисованный кадр, поэтому снятое в том же _process состояние (фаза
## нажатия, вспышка) в картинку не попадало — все кадры выходили байт в
## байт одинаковыми (поймано 05.11.2026: семь снимков с одним md5).
## _snap только ЗАКАЗЫВАЕТ кадр, а снимает следующий _process — уже после
## того, как сцена нарисовала поставленное состояние.
func _snap(tag: String) -> void:
	_pending = tag


func _capture(tag: String) -> bool:
	_shot_i += 1
	_tag = tag
	var img := root.get_texture().get_image()
	var name := "vis-hands-%02d-%s" % [_shot_i, _tag]
	var area: Rect2 = _hands._area
	print("КАДР_РАЗМЕР %d %d кисти %.0fx%.0f k=%.3f доска=%s" % [
		img.get_width(), img.get_height(),
		_hands.view_w, _hands.view_h, _hands.k, str(area),
	])
	img.save_png(SAVE_DIR + name + ".png")
	print("КАДР ", SAVE_DIR + name + ".png")
	return tag == "landscape"  # последний кадр — конец прогона


func _tap_key(s: String) -> void:
	var area: Rect2 = _hands._area
	var r: Rect2 = Hands.key_rect(_hands._bs, s)
	if r.size == Vector2.ZERO:
		print("TAP НЕТ КЛАВИШИ ", s)
		return
	_hands.call("_tap", r.get_center())


## Фаза нажатия ДЛЯ КАДРА: под llvmpipe между кадрами проходит больше
## времени, чем длится само нажатие (PRESS_TIME 0.34 с), и снимок
## «палец на клавише» приезжал уже после возврата — кадры 01–07 выходили
## байт в байт одинаковыми, то есть не показывали ничего. Драйвер ставит
## фазу руками (0.5 — палец на клавише, 1.0 — вернулся) и замораживает
## спад на время снимка.
func _phase(at: float) -> void:
	_hands.call("set_press_phase", at)


func _process(_dt: float) -> bool:
	if _pending != "":
		var tag := _pending
		_pending = ""
		return _capture(tag)
	_frame += 1
	if _frame == 2:
		_win(Vector2i(540, 1140))
	elif _frame == 30:
		_snap("rest")
	# Далее кейсы по очереди: тап → средний кадр → возврат.
	elif _frame == 40:
		_tap_key("в")
	elif _frame == 49:
		_phase(0.5)
		_snap("tap-v")
	elif _frame == 66:
		_phase(1.0)
		_snap("tap-up")
	# Тап по нижнему ряду: кисть ставится на клавишу вместе с пальцем
	# (посадку делает Hands.pose_of — отдельного хода кисти нет).
	elif _frame == 70:
		_tap_key("я")
	elif _frame == 79:
		_phase(0.5)
		_snap("tap-ya-shift")
	elif _frame == 96:
		_phase(1.0)
		_snap("tap-ya-up")
	elif _frame == 100:
		_tap_key("о")
	elif _frame == 109:
		_phase(0.5)
		_snap("tap-o")
	# Служебные: каждое нажатие — свой палец в позе (пресс этих клавиш
	# в тестах и диагностике меряется, кадр — как он ВЫГЛЯДИТ).
	elif _frame == 122:
		_tap_key("пробел")
	elif _frame == 131:
		_phase(0.5)
		_snap("tap-space")
	elif _frame == 146:
		_tap_key("Shift")  # ключ клавиши, не действие hit («шифт»)
	elif _frame == 155:
		_phase(0.5)
		_snap("tap-shift")
	elif _frame == 170:
		_tap_key("←")  # бекспейс: у кнопки ключ «←», hit зовёт его «стереть»
	elif _frame == 179:
		_phase(0.5)
		_snap("tap-bksp")
	elif _frame == 194:
		_tap_key("глобус")
	elif _frame == 203:
		_phase(0.5)
		_snap("tap-globe")
	elif _frame == 218:
		# Альбом: те же кисти при другом окне.
		_win(Vector2i(1140, 540))
	elif _frame == 248:
		_snap("landscape")
	return false
