extends SceneTree
## Короткий драйвер доски: три устойчивых состояния (РУ, РУ+шифт, АН) и
## координаты домов подписей из модели рядом. Только для ревизии углов —
## полный visual_driver здесь не нужен.

const SAVE_DIR := "/tmp/opencode/"
const Kbd := preload("res://scripts/kbd.gd")

var _main: Node = null
var _frame := 0
var _steps: Array = []
var _wait := 0
var _tag := ""
var _burst := 0
var _burst_n := 0
var _burst_tag := ""


func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	_main = scene.instantiate()
	_main.skip_menu = true
	_main.all_keys_override = 1
	root.add_child(_main)


func _snap() -> void:
	var img := root.get_texture().get_image()
	var name := "kbd-%s" % _tag
	img.save_png(SAVE_DIR + name + ".png")
	print("КАДР ", SAVE_DIR + name + ".png lang=%s shift=%s morph=%.2f state=%s" % [
		_main.kb_lang, str(bool(_main.kb_shift)), float(_main.kb_morph),
		String(_main.state)
	])
	print("ДОСКА rect=%s idle=%.2f hint=%s" % [
		str(_main._own_rect()), float(_main.idle_t), str(_main._hint_keys())
	])
	# Дома подписей из модели для спорных клавиш.
	var r := Rect2(0, 0, 100, 60)
	for s in ["х", "ъ", "б", "ю", "ж", "э", "2", ".", "ё"]:
		var parts: Array = []
		for v in Kbd.small_legends(s, String(_main.kb_lang), bool(_main.kb_shift)):
			var t := String(v)
			parts.append("%s@%d" % [t, int(Kbd.corner_for(s, t))])
		print("МОДЕЛЬ %s центр=%s печать=[%s]" % [
			s, String(Kbd.press_out(s, String(_main.kb_lang), bool(_main.kb_shift))),
			" ".join(PackedStringArray(parts))
		])


func _win() -> void:
	DisplayServer.window_set_size(Vector2i(820, 1180))
	root.size = Vector2i(820, 1180)
	_main._force_touch = true
	_main.kb_lang = "ru"
	_main.kb_shift = false
	_main.kb_morph = 1.0
	_main.difficulty = 0
	_main._new_level()
	_main.grace_t = 9999.0
	_main.enemy_cps = 0.0
	_main.hedge_active = false
	_main._relayout()


func _process(_dt: float) -> bool:
	_frame += 1
	if _frame < 3:
		return false
	if _frame == 3:
		_win()
		_steps = [
			["ru", 25],
			["arm", 0],
			["tapminus", 0],
			["off", 25],
			["en", 25],
		]
	if _steps.is_empty() and _wait <= 0 and _burst <= 0:
		return true
	if _burst > 0:
		# Серия: снимаем каждый кадр подряд, чтобы видеть полёт.
		_tag = "%s-%02d" % [_burst_tag, _burst_n - _burst]
		_snap()
		_burst -= 1
		return false
	if _wait > 0:
		_wait -= 1
		if _wait == 0:
			_snap()
		return false
	var step: Array = _steps.pop_front()
	_tag = String(step[0])
	if _tag == "arm":
		# Настоящий жест: взвод шифта штатным включением (сброс морфа),
		# дальше 12 кадров подряд — сам полёт.
		_main._set_kb_shift(true)
		_burst_tag = "armfly"
		_burst_n = 12
		_burst = 12
	elif _tag == "tapminus":
		# Настоящий жест: тап по минусу — ввод плюс гашение шифта.
		var area: Rect2 = _main._own_rect()
		for b in Kbd.buttons(area, true, _main._kb_enter_shown()):
			if String(b["s"]) == "-":
				print("ТАП минус в ", str((b["r"] as Rect2).get_center()))
				_main._own_press((b["r"] as Rect2).get_center())
				break
		_burst_tag = "tapfly"
		_burst_n = 12
		_burst = 12
	elif _tag == "ru-shift-mid":
		# Середина перелёта на щипке: шифт через штатное включение (сброс
		# морфа), сам морф ставим вручную — за два кадра он почти не
		# продвинется.
		_main._set_kb_shift(true)
		_main.kb_morph = 0.45
	elif _tag == "off":
		_main.kb_morph = 1.0
	elif _tag == "en":
		_main.kb_shift = false
		_main.kb_lang = "en"
	_wait = int(step[1])
	return false
