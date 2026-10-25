extends SceneTree
## Визуальный драйвер песочницы кистей: поднимает scenes/hands.tscn в
## окне телефона (портрет) и альбомном окне, снимает:
##   01/02 — покой обеих кистей (день);
##   03    — тап по букве левой руки (палец согнулся к клавише);
##   04    — хвост того же тапа (палец вернулся);
##   05    — ночь: те же руки на ночном фоне.
## Кадры /tmp/opencode/vis-hands-*.png. Рендер живой (не headless).
## Запуск: tools/docker/build-game.sh --visual

const SAVE_DIR := "/tmp/opencode/"

var _hands: Node = null
var _frame := 0
var _shot_i := 0
var _wait := 0
var _tag := ""


func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/hands.tscn")
	_hands = scene.instantiate()
	root.add_child(_hands)


## Окно — И через DisplayServer, И у корня (как в прочих драйверах).
func _win(wh: Vector2i) -> void:
	DisplayServer.window_set_size(wh)
	root.size = wh
	_hands.call("_relayout")


func _snap(tag: String) -> void:
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


func _tap_key(s: String) -> void:
	var area: Rect2 = _hands._area
	var r: Rect2 = Hands.key_rect(_hands._bs, s)
	if r.size == Vector2.ZERO:
		print("TAP НЕТ КЛАВИШИ ", s)
		return
	_hands.call("_tap", r.get_center())


func _process(_dt: float) -> bool:
	_frame += 1
	if _frame == 2:
		_win(Vector2i(540, 1140))
	elif _frame == 30:
		_snap("rest")
	# Далее кейсы по очереди: тап → средний кадр → возврат.
	elif _frame == 40:
		_tap_key("в")
	elif _frame == 49:
		_snap("tap-v")
	elif _frame == 66:
		_snap("tap-up")
	elif _frame == 75:
		_tap_key("о")
	elif _frame == 84:
		_snap("tap-o")
	elif _frame == 100:
		# Альбом: те же кисти при другом окне.
		_win(Vector2i(1140, 540))
	elif _frame == 130:
		_snap("landscape")
		return true  # true в SceneTree._process = закончить прогон
	return false
