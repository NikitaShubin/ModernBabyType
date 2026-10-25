extends Node2D
## Песочница кистей (автор 19.10.2026): скелет обеих рук НАД доской,
## чтобы видеть, каким пальцем на какую клавишу нажимать.
##
## Доска здесь — НАСТОЯЩАЯ: рисуется тем же вызовом Kbd.draw с теми же
## стилями, что в игре (стили из Ui, единый шрифт). Тапы работают: тап
## по клавише вспыхивает, и палец этой клавиши сгибается к ней (FABRIK
## из Hands), затем возвращается в покой. Никакой игровой логики —
## чистый стенд для поз и анимации.
##
## Запуск: сцена scenes/hands.tscn (F5) или visual-драйвер
## tests/hands_driver.gd (кадры /tmp/opencode/vis-hands-*.png).

const KB_FRAC := 0.46  # доска занимает те же % высоты, что в игре

var view_w := 1080.0
var view_h := 2340.0
var k := 1.0
var mono: Font = null

# Стили доски — из Ui, одинаковые с main (день).
var kb_key_sb: StyleBox
var kb_on_sb: StyleBox
var kb_flash_ok: StyleBoxFlat

var lang := "ru"
var shift := false
var press_key := ""       # вспыхнувшая клавиша
var press_t := 0.0        # таймер всего хода
# Куда палец идёт при этой вспышке: [рука, палец, точка нажатия].
var press_hand := -1
var press_finger := -1
var press_point := Vector2.ZERO
const FLASH_T := 0.28     # затухание заливки клавиши (как в игре)
const PRESS_TIME := 0.34  # ход пальца: опустился и вернулся

# Позы покоя: {рука: поза из Hands.rest_pose}. Пересчитываются на
# релэйауте: геометрия доски меняется — пальцы садятся заново.
var _rest: Dictionary = {}
var _bs: Array = []
var _area := Rect2()
var _pitch := 0.0
var _bg: Color = Ui.PAPER_DAY


func _ready() -> void:
	mono = load("res://fonts/DejaVuSansMono.ttf")
	kb_key_sb = Ui.panel_sb(Ui.SURFACE_DAY, 10.0, Ui.LINE_DAY, 2.0, false)
	kb_on_sb = Ui.panel_sb(Ui.ACCENT_DAY, 10.0, Ui.ACCENT_EDGE_DAY, 2.0, false)
	kb_flash_ok = Ui.panel_sb(Ui.OK_DAY, 10.0, Ui.OK_EDGE_DAY, 2.5, false)
	get_tree().root.size_changed.connect(_relayout)
	_relayout()


## Раскладка как в игре: доска прижата к низу и отцентрована, k — от
## остатка высоты, как у main. Кисти живут в координатах доски.
func _relayout() -> void:
	var s := get_viewport_rect().size
	if s.x <= 0.0 or s.y <= 0.0:
		return
	view_w = s.x
	view_h = s.y
	k = clampf(minf(view_w / 1100.0,
		(view_h - Ui.bottom_inset(view_h)) / 650.0), 0.5, 2.5)
	var m := 16.0 + Ui.bottom_inset(view_h)
	var hmax := maxf(160.0, (view_h - m) * KB_FRAC)
	var w := view_w - 32.0
	var h := Kbd.height_for(w)
	if h > hmax:
		w = clampf(Kbd.width_for(hmax), 240.0, view_w - 32.0)
		h = Kbd.height_for(w)
	_area = Rect2((view_w - w) * 0.5, view_h - h - m, w, h)
	_bs = Kbd.buttons(_area, shift, false)
	_pitch = Hands.pitch_of(_bs)
	_rest = Hands.rest_both(_bs)
	queue_redraw()


func _process(dt: float) -> void:
	if press_t > 0.0:
		press_t = maxf(0.0, press_t - dt)
		if press_t <= 0.0:
			press_key = ""
			press_hand = -1
			press_finger = -1
		queue_redraw()


func _input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		if ev.pressed:
			_tap(Vector2(ev.position.x, ev.position.y))
	elif ev is InputEventScreenTouch:
		if ev.pressed:
			_tap(Vector2(ev.position.x, ev.position.y))


func _tap(pos: Vector2) -> void:
	var s := Kbd.hit(_area, shift, false, pos)
	if s == "":
		return
	if s == "Shift" or s == "ShiftR":
		shift = not shift
		_bs = Kbd.buttons(_area, shift, false)
		queue_redraw()
		return
	press_key = s
	press_t = maxf(FLASH_T, PRESS_TIME)
	var pf := Hands.finger_of(s)
	press_hand = pf[0]
	press_finger = pf[1]
	press_point = Hands.key_center(_bs, s)
	queue_redraw()


func _draw() -> void:
	if mono == null or _area.size == Vector2.ZERO:
		return
	# Фон и доска — как в игре.
	draw_rect(Rect2(Vector2.ZERO, Vector2(view_w, view_h)), _bg)
	Kbd.draw(self, _area, lang, shift, false, mono,
		int(30.0 * k), kb_key_sb, kb_on_sb, Ui.INK_DAY,
		[], null, Ui.DIM_DAY, 1.0, "", false, _flash_sb(), press_key)
	# Кисти ПОВЕРХ доски (полупрозрачно: подписи читаются).
	_draw_hand(Hands.LEFT)
	_draw_hand(Hands.RIGHT)


## Заливка вспышки — тем же стилем верного ввода, но alpha = таймеру.
## Единый StyleBoxFlat (не создаётся раз в кадр).
func _flash_sb() -> StyleBox:
	var c: Color = kb_flash_ok.bg_color
	c.a = clampf(press_t / FLASH_T, 0.0, 1.0)
	var sb: StyleBoxFlat = kb_flash_ok
	sb.bg_color = c
	return sb


## Цепь пальца для рисования: покой из rest; если палец сейчас
## «нажат», цель едет от покоя (над клавишей) к центру клавиши и
## обратно — синус: нажал-вернулся без рыва.
func _finger_chain(h: int, f: int) -> Array:
	var pose: Dictionary = _rest.get(h, {})
	var chains: Dictionary = pose.get("fingers", {})
	if not chains.has(f):
		return []
	var chain: Array = chains[f]
	if h != press_hand or f != press_finger or press_t <= 0.0:
		return chain
	# Ход: 0..1..0 (полсинуса от таймера танца PRESS_TIME).
	var t01 := 1.0 - press_t / float(PRESS_TIME)
	var depth := sin(clampf(t01, 0.0, 1.0) * PI)
	var tgt: Vector2 = pose["targets"][f]
	var target := tgt.lerp(press_point, depth)
	return Hands.ik_chain(chain[0], Hands.bones_px(f, _pitch), target)


func _draw_hand(h: int) -> void:
	var pose: Dictionary = _rest.get(h, {})
	if not pose.has("wrist"):
		return
	var w := _stroke()
	for f in pose["fingers"].keys():
		var pts: Array = _finger_chain(h, f)
		if pts.size() < 2:
			continue
		for i in pts.size() - 1:
			draw_line(pts[i], pts[i + 1], _bone(), w * 2.2, true)
		for pt in pts:
			draw_circle(pt, w, _joint())
	# Запястье — крупнее: главный «якорь» руки.
	draw_circle(pose["wrist"], w * 1.6, _joint())


## Штрих скелета — ОТ ПИТЧА (кегль кеглю не штрих): доска на телефоне
## мельче, а палец читаться обязан на любой геометрии.
func _stroke() -> float:
	return clampf(_pitch * 0.11, 2.6, 5.0)


func _bone() -> Color:
	var c := Ui.LINE_DAY
	c.a = 0.55
	return c


func _joint() -> Color:
	var c := Ui.INK_DAY
	c.a = 0.7
	return c
