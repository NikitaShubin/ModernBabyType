extends SceneTree
## Скелет кистей — чистые меры (headless не рисует): карта палец↔клавиша
## покрывает ВСЮ доску, FABRIK не растягивает кости, покой сажает
## кончики над своими дом-клавишами, обе кисти симметричны.
## Пробы каждого правила: правило ломается руками — тест краснеет
## со своим сообщением (правило этого репозитория).
##
## Геометрия доски: живой узел не нужен — buttons() чистый. Окно
## ставим (headless по умолчанию 64×64 — доска вырожденная).

const KB_FRAC := 0.46


func _initialize() -> void:
	main_window_setup()
	_hands_test()
	if _fails == 0:
		print("HANDS_TEST: PASS")
	quit(0 if _fails == 0 else 1)


var _fails := 0


func main_window_setup() -> void:
	DisplayServer.window_set_size(Vector2i(540, 1140))
	root.size = Vector2i(540, 1140)


func _check(ok: bool, msg: String) -> void:
	if not ok:
		print("HANDS: FAIL: ", msg)
		_fails += 1


func _board() -> Array:
	var wh := root.size
	var m := 16.0 + Ui.bottom_inset(float(wh.y))
	var hmax := maxf(160.0, (float(wh.y) - m) * KB_FRAC)
	var w := float(wh.x) - 32.0
	var h := Kbd.height_for(w)
	if h > hmax:
		w = clampf(Kbd.width_for(hmax), 240.0, float(wh.x) - 32.0)
		h = Kbd.height_for(w)
	return Kbd.buttons(Rect2((float(wh.x) - w) * 0.5, float(wh.y) - h - m, w, h), false, false)


func _hands_test() -> void:
	var bs: Array = _board()
	_check(Hands.pitch_of(bs) > 0.0, "pitch from buttons is positive")
	_map_covers_board(bs)
	_map_spot_checks(bs)
	_ik_invariants(bs)
	_rest_pose_checks(bs)
	_mirror_checks(bs)


## Каждая клавиша ДОСКИ имеет палец: карта не может отстать от
## раскладки — новая клавиша без пальца должна ломать тест.
func _map_covers_board(bs: Array) -> void:
	for b in bs:
		var s := String(b["s"])
		var f := Hands.finger_of(s)
		_check(f[0] >= 0,
			"key '%s' has a finger in the map (%s)" % [s, str(Hands.finger_of(s))])


## Точечные правила карты: дом-ряд, крайние колонки, служебные.
func _map_spot_checks(bs: Array) -> void:
	_check(Hands.finger_of("ф") == [Hands.LEFT, Hands.PINKY], "ф is left pinky")
	_check(Hands.finger_of("ы") == [Hands.LEFT, Hands.RING], "ы is left ring")
	_check(Hands.finger_of("в") == [Hands.LEFT, Hands.MIDDLE], "в is left middle")
	_check(Hands.finger_of("а") == [Hands.LEFT, Hands.INDEX], "а is left index")
	_check(Hands.finger_of("и") == [Hands.LEFT, Hands.INDEX],
		"и is left index (key b is under the LEFT palm)")
	_check(Hands.finger_of("о") == [Hands.RIGHT, Hands.INDEX], "о is right index")
	_check(Hands.finger_of("л") == [Hands.RIGHT, Hands.MIDDLE], "л is right middle")
	_check(Hands.finger_of("б") == [Hands.RIGHT, Hands.MIDDLE],
		"б is right middle (key , is under the RIGHT palm)")
	_check(Hands.finger_of("ъ") == [Hands.RIGHT, Hands.PINKY], "ъ is right pinky")
	_check(Hands.finger_of("Shift") == [Hands.LEFT, Hands.PINKY], "left shift is left pinky")
	_check(Hands.finger_of("ShiftR") == [Hands.RIGHT, Hands.PINKY], "right shift is right pinky")
	_check(Hands.finger_of("↵") == [Hands.RIGHT, Hands.PINKY], "enter is right pinky")
	_check(Hands.finger_of("←") == [Hands.RIGHT, Hands.PINKY], "backspace is right pinky")
	_check(Hands.finger_of("4") == [Hands.LEFT, Hands.INDEX], "4 is left index")
	_check(Hands.finger_of("5") == [Hands.LEFT, Hands.INDEX], "5 is left index")
	_check(Hands.finger_of("6") == [Hands.RIGHT, Hands.INDEX], "6 is right index")
	_check(Hands.finger_of("7") == [Hands.RIGHT, Hands.INDEX], "7 is right index")


## FABRIK: кости НЕ растягиваются никогда; достижимая цель достигается;
## недостижимая — цепь вытянута по лучу ровно на Σbones.
func _ik_invariants(bs: Array) -> void:
	var pitch := Hands.pitch_of(bs)
	_check(pitch > 0.0, "pitch positive before IK")
	for f in [Hands.THUMB, Hands.INDEX, Hands.MIDDLE, Hands.RING, Hands.PINKY]:
		var bones := Hands.bones_px(f, pitch)
		var reach := 0.0
		for b in bones:
			reach += b
		var root := Vector2(0, 0)
		# Достижимо: цель в пределах руки.
		for case in [["diagonal", root + Vector2(reach * 0.62, reach * 0.60)]]:
			var pts: Array = Hands.ik_chain(root, bones, case[1])
			_check(pts.size() == bones.size() + 1,
				"%s f=%d chain has root+all joints" % [case[0], f])
			for i in bones.size():
				var seg: float = (pts[i + 1] as Vector2).distance_to(pts[i])
				_check(absf(seg - bones[i]) < 0.002,
					"%s f=%d bone %d keeps its length (%.4f vs %.4f)" % [
						case[0], f, i, seg, bones[i]])
			_check((pts[pts.size() - 1] as Vector2).distance_to(case[1]) < 0.01,
				"%s f=%d tip reaches the target" % [case[0], f])
		# Недостижимо: кончик ровно на Σbones от корня.
		var far := root + Vector2(reach * 2.4, 0)
		var pts2: Array = Hands.ik_chain(root, bones, far)
		var tip := pts2[pts2.size() - 1] as Vector2
		_check(absf(tip.distance_to(root) - reach) < 0.01,
			"f=%d unreachable target stops the chain at full stretch" % f)


## Покой: пять пальцев у каждой руки, кончики над своими дом-клавишами
## (на HOVER питча над верхом), корни на пястной линии внутри колонок,
## запястье ниже пясти.
func _rest_pose_checks(bs: Array) -> void:
	var pitch := Hands.pitch_of(bs)
	var pose := Hands.rest_both(bs)
	_check(pose.has(Hands.LEFT) and pose.has(Hands.RIGHT), "both hands rest")
	for h in [Hands.LEFT, Hands.RIGHT]:
		var p: Dictionary = pose[h]
		var fl: Dictionary = p["fingers"]
		_check(fl.size() == 5, "hand %d rests with 5 fingers" % h)
		var home_map: Dictionary = Hands.HOME_KEY[h]
		for f in [Hands.INDEX, Hands.MIDDLE, Hands.RING, Hands.PINKY]:
			var chain: Array = fl[f]
			_check(chain.size() == 4, "hand %d f=%d chain has 4 joints" % [h, f])
			var tip := chain[chain.size() - 1] as Vector2
			var kr := Hands.key_rect(bs, String(home_map[f]))
			_check(kr.size.x > 0.0, "home key of hand %d f=%d on the board" % [h, f])
			var expect := kr.position + Vector2(kr.size.x * 0.5, -Hands.HOVER * pitch)
			_check(tip.distance_to(expect) < 0.35 * pitch,
				"hand %d f=%d tip hovers over its home key" % [h, f])
		# Запястье ниже пясти, кончик большого на своей половине пробела.
		for f in [Hands.THUMB]:
			var chain2: Array = fl[f]
			var tip2 := chain2[chain2.size() - 1] as Vector2
			var sp := Hands.key_rect(bs, "пробел")
			var inside := sp.grow(0.5 * pitch)
			_check(inside.has_point(tip2), "hand %d thumb hovers over the space" % h)
		_check((p["wrist"] as Vector2).y > p["knuckle_y"],
			"hand %d wrist sits below the knuckles" % h)


## Симметрия: правая кисть — ЗЕРКАЛО левой около оси между дом-
## клавишами указательных (а от зеркальной оси к колонкам идут те же
## шаги). Ось не по центру доски: справа живут ввод и «\» — доска
## шире справа, мера обязана идти от самих колонок.
func _mirror_checks(bs: Array) -> void:
	var pitch := Hands.pitch_of(bs)
	var pose := Hands.rest_both(bs)
	var pl: Dictionary = pose[Hands.LEFT]
	var pr: Dictionary = pose[Hands.RIGHT]
	var la := Hands.key_rect(bs, "а")
	var ra := Hands.key_rect(bs, "о")
	var axis := (la.get_center().x + ra.get_center().x) * 0.5
	for f in [Hands.INDEX, Hands.MIDDLE, Hands.RING, Hands.PINKY]:
		# Tip chain: [root, 2 joints, tip] for fingers (4 points).
		var ltip := pl["fingers"][f][3] as Vector2
		var rtip := pr["fingers"][f][3] as Vector2
		var dx := ltip.x - axis
		var dy := absf(ltip.y - rtip.y)
		var rx := (rtip.x - axis) - (-dx)
		_check(dy < 0.4 * pitch, "finger %d tips at one height in both hands" % f)
		_check(absf(rx) < 0.4 * pitch, "finger %d tips mirror across the hand axis" % f)
