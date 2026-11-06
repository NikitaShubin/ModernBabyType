extends SceneTree
## Рендер КИСТЕЙ БЕЗ ДОСКИ (зеркало глазами, автор 26.10.2026):
## свой Node2D рисует только Hands.draw_both, доска не рисуется (только
## сетка прямоугольников клавиш, чтобы видеть посадку).
## Кадры: /tmp/opencode/hands-mirror-*.png.

const SAVE_DIR := "/tmp/opencode/"


class Hander extends Node2D:
	var rest := {}
	var pitch := 0.0
	var area := Rect2()
	var bs: Array = []

	func layout() -> void:
		var s: Vector2 = get_viewport_rect().size
		var m := 16.0 + Ui.bottom_inset(s.y)
		var hmax := maxf(160.0, (s.y - m) * 0.46)
		var w := s.x - 32.0
		var h := Kbd.height_for(w)
		if h > hmax:
			w = clampf(Kbd.width_for(hmax), 240.0, s.x - 32.0)
			h = Kbd.height_for(w)
		area = Rect2((s.x - w) * 0.5, s.y - h - m, w, h)
		bs = Kbd.buttons(area, false, false)
		pitch = Hands.pitch_of(bs)
		rest = Hands.rest_both(bs)
		queue_redraw()

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, get_viewport_rect().size),
			Color(0.97, 0.95, 0.90))
		if rest.is_empty():
			return
		for b in bs:
			draw_rect(b["r"] as Rect2, Color(0.55, 0.55, 0.55), false, 1.0)
		Hands.draw_both(self, bs, rest, {}, Color(0.10, 0.10, 0.10))


var _h: Hander = null
var _frame := 0
var _shot_i := 0


func _initialize() -> void:
	_h = Hander.new()
	root.add_child(_h)


func _win(wh: Vector2i) -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(wh)
	root.size = wh
	_h.layout()


func _snap(tag: String, zoom: Rect2 = Rect2()) -> void:
	_shot_i += 1
	var img := root.get_texture().get_image()
	if zoom.size != Vector2.ZERO:
		var src := img.get_region(zoom)
		src.resize(src.get_width() * 2, src.get_height() * 2,
			Image.INTERPOLATE_NEAREST)
		img = src
	img.save_png(SAVE_DIR + "hands-mirror-%02d-%s.png" % [_shot_i, tag])
	print("КАДР_РАЗМЕР %d %d area=%s" % [img.get_width(), img.get_height(),
		str(_h.area)])
	print("КАДР ", SAVE_DIR + "hands-mirror-%02d-%s.png" % [_shot_i, tag])


func _process(_dt: float) -> bool:
	_frame += 1
	var ks := [1.0, 1.0, 1.0, 1.0]
	var fa := [0.14, 0.20, 0.26, 0.34]
	if _frame == 2:
		_win(Vector2i(540, 1140))
	elif _frame >= 10:
		var i := (_frame - 10) / 10
		var ph := (_frame - 10) % 10
		if i >= ks.size():
			return true
		if ph == 0:
			Hands.depth_k = ks[i]
			Hands.fill_a = fa[i]
			Hands.line_a = 0.85
			Hands.line_w = 0.08
			_h.layout()
		elif ph == 2:
			_snap("phone-k%02d-f%02d" % [int(ks[i] * 100), int(fa[i] * 100)])
			_snap("phone-k%02d-f%02d-zoom" % [int(ks[i] * 100), int(fa[i] * 100)],
				Rect2(0, 900, 540, 240))
	return false
