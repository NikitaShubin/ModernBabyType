class_name Meadow
extends Node2D
## Общий фон игры и меню игроков: днём — небо градиентом, солнце, облака,
## далёкие холмы; ночью — тёмное небо, луна, звёзды, те же холмы темнее.
## Только картинка, никакой логики и никакой геометрии погони: тесты её
## не трогают, потому что фон не знает ни про зайца, ни про ежа, ни про
## буквы.
##
## Живёт отдельным узлом с z_index = -20, позади всего: текст и герои
## рисуются поверх. Свои часы (time) — облака медленно плывут, пока
## игрок думает над буквой.

var _time := 0.0
var _sky: GradientTexture2D
## Ночь снаружи ставит игра/меню (S.get_night_mode): переключение —
## просто другой набор красок, геометрия та же.
var night := false


func _ready() -> void:
	z_index = -20
	_sky = GradientTexture2D.new()
	_sky.width = 4
	_sky.height = 256
	_sky.fill_from = Vector2(0.5, 0.0)
	_sky.fill_to = Vector2(0.5, 1.0)
	_apply_sky()


## Градиент неба под режим: вызывается из _ready и при смене ночи.
func _apply_sky() -> void:
	var grad := Gradient.new()
	if night:
		grad.set_color(0, Color("#0d1526"))
		grad.set_color(1, Color("#2a3a5e"))
	else:
		grad.set_color(0, Color("#8fd0ee"))
		grad.set_color(1, Color("#f7f3e8"))
	_sky.gradient = grad
	queue_redraw()


func _process(dt: float) -> void:
	_time += dt
	queue_redraw()


func _draw() -> void:
	var s := get_viewport_rect().size
	if s.x <= 0.0 or s.y <= 0.0:
		return
	draw_texture_rect(_sky, Rect2(Vector2.ZERO, s), false)
	_draw_hills(s)
	if night:
		_draw_stars(s)
		_draw_moon(s)
	else:
		_draw_sun(s)
	_draw_clouds(s)


## Далёкие холмы: видны по краям карточки с текстом, середину она
## закрывает. Большие круги, обрезанные краем экрана, — дёшево и ровно.
func _draw_hills(s: Vector2) -> void:
	if night:
		draw_circle(Vector2(s.x * 0.10, s.y * 1.10), s.x * 0.44, Color("#16283a"))
		draw_circle(Vector2(s.x * 0.94, s.y * 1.14), s.x * 0.48, Color("#1b3040"))
	else:
		draw_circle(Vector2(s.x * 0.10, s.y * 1.10), s.x * 0.44, Color("#cfe6b8"))
		draw_circle(Vector2(s.x * 0.94, s.y * 1.14), s.x * 0.48, Color("#bcdc9f"))


func _draw_sun(s: Vector2) -> void:
	var c := Vector2(s.x * 0.87, s.y * 0.13)
	var r := minf(s.x, s.y) * 0.045
	draw_circle(c, r * 2.3, Color(1.0, 0.85, 0.30, 0.16))
	draw_circle(c, r * 1.6, Color(1.0, 0.85, 0.30, 0.22))
	draw_circle(c, r, Color("#ffd94d"))


## Луна вместо солнца: бледный диск и пара кратеров потемнее.
func _draw_moon(s: Vector2) -> void:
	var c := Vector2(s.x * 0.87, s.y * 0.13)
	var r := minf(s.x, s.y) * 0.045
	draw_circle(c, r * 2.0, Color(0.85, 0.88, 1.0, 0.10))
	draw_circle(c, r, Color("#f4f1de"))
	draw_circle(c + Vector2(-r * 0.3, -r * 0.2), r * 0.22, Color("#d9d4bd"))
	draw_circle(c + Vector2(r * 0.25, r * 0.3), r * 0.15, Color("#d9d4bd"))


## Звёзды: детерминированные точки (формула от индекса, не randf —
## иначе мерцали бы каждый кадр). Яркость волной от времени.
func _draw_stars(s: Vector2) -> void:
	for i in 48:
		var fx := fposmod(float(i) * 0.61803 + 0.13, 1.0)
		var fy := fposmod(float(i) * 0.38197 + 0.07, 0.62)
		var tw := 0.45 + 0.35 * sin(_time * (0.6 + 0.1 * float(i % 5)) + float(i))
		var r := 1.0 + 1.2 * fposmod(float(i) * 0.33, 1.0)
		var sc := clampf(minf(s.x / 1100.0, s.y / 650.0), 0.5, 2.5)
		draw_circle(Vector2(s.x * fx, s.y * fy), r * sc, Color(1, 1, 1, tw))


func _draw_clouds(s: Vector2) -> void:
	var sc := clampf(minf(s.x / 1100.0, s.y / 650.0), 0.5, 2.5)
	var bases := [
		Vector4(0.20, 0.12, 0.05, 0.0),
		Vector4(0.52, 0.20, 0.035, 2.1),
		Vector4(0.72, 0.09, 0.06, 4.2),
	]
	for b in bases:
		var p := Vector2(
			s.x * b.x + sin(_time * b.z + b.w) * 30.0 * sc,
			s.y * b.y
		)
		_cloud(p, b.z * 22.0 * sc + 0.8 * sc)


## Облако — приплюснутый ком из кругов: снизу серо-голубая тень,
## сверху белые купола. Без тени облако выглядит наклейкой.
## Ночью — те же комья, но призрачные.
func _cloud(p: Vector2, sc: float) -> void:
	var shadow := Color(0.75, 0.85, 0.93, 0.9)
	var white := Color(1, 1, 1, 0.92)
	if night:
		shadow = Color(0.35, 0.42, 0.55, 0.5)
		white = Color(0.55, 0.62, 0.75, 0.5)
	draw_circle(p + Vector2(-46, 8) * sc, 22.0 * sc, shadow)
	draw_circle(p + Vector2(0, 10) * sc, 26.0 * sc, shadow)
	draw_circle(p + Vector2(46, 8) * sc, 22.0 * sc, shadow)
	draw_circle(p + Vector2(-40, 0) * sc, 20.0 * sc, white)
	draw_circle(p + Vector2(-10, -14) * sc, 26.0 * sc, white)
	draw_circle(p + Vector2(22, -10) * sc, 22.0 * sc, white)
	draw_circle(p + Vector2(48, 2) * sc, 16.0 * sc, white)
