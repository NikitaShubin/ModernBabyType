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
## Птицы: [pos, phase, size, dir, age]. Летают только днём.
var _birds: Array = []
var _bird_cd := 4.0
## Метеоры: [pos, dir, len, life, speed]. Падают только ночью — днём небо
## и так живое (птицы, облака), а ночью оно было пустое и скучное
## (автор 10.2026: «ночное небо слишком скучное, надо добавить метеоритов
## или комет… пусть ночью тоже что-то будет»).
var _meteors: Array = []
var _meteor_cd := 3.0


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
	# Смена дня/ночи разгоняет стаю сразу: ночные птицы не летают,
	# дневные при ночи не нужны. С метеорами так же.
	_birds.clear()
	_bird_cd = 6.0
	_meteors.clear()
	_meteor_cd = 3.5
	queue_redraw()


func _process(dt: float) -> void:
	# Скрытый фон стоит: облака чужого экрана не плывут.
	if not visible:
		return
	_time += dt
	_bird_cd -= dt
	# Птицы — только днём и не толпой: максимум три, новая каждые
	# 8–16 секунд. Ночью небо пустое (совы не завезли).
	if not night and _bird_cd <= 0.0 and _birds.size() < 3:
		_bird_cd = randf_range(8.0, 16.0)
		_spawn_bird()
	# Метеоры — только ночью, не чаще одной штуки в 6–13 секунд и не
	# больше двух в небе: безмятечность важнее зрелищности.
	if night:
		_meteor_cd -= dt
		if _meteor_cd <= 0.0 and _meteors.size() < 2:
			_meteor_cd = randf_range(6.0, 13.0)
			_spawn_meteor()
		for i in range(_meteors.size() - 1, -1, -1):
			var m: Array = _meteors[i]
			var mv := (m[1] as Vector2) * float(m[4]) * dt
			m[0] = (m[0] as Vector2) + mv
			m[3] = float(m[3]) + dt
			# Гасим на верхней трети неба: ниже метеор всё равно уходит
			# под карточку с текстом, где его не видно.
			var ms := get_viewport_rect().size
			if (m[0] as Vector2).y > ms.y * 0.45 or (m[0] as Vector2).x < -80.0 \
				or (m[0] as Vector2).x > ms.x + 80.0:
				_meteors.remove_at(i)
	for i in range(_birds.size() - 1, -1, -1):
		var b: Array = _birds[i]
		b[0] = (b[0] as Vector2) + Vector2(float(b[3]) * _bird_speed(), 0.0) * dt
		b[4] = float(b[4]) + dt
		var s := get_viewport_rect().size
		if (float(b[3]) > 0.0 and (b[0] as Vector2).x > s.x + 60.0) or (float(b[3]) < 0.0 and (b[0] as Vector2).x < -60.0):
			_birds.remove_at(i)
	queue_redraw()


## Скорость птиц в пикселях канваса за секунду. Медленно (22px/c):
## безмятежность важнее динамики.
func _bird_speed() -> float:
	return 22.0 * _scale()


## Новая птица: с левого или правого края, на высоте верхней трети неба.
func _spawn_bird() -> void:
	var s := get_viewport_rect().size
	if s.x <= 0.0 or s.y <= 0.0:
		return
	var dir := 1.0 if randf() < 0.5 else -1.0
	var pos := Vector2(
		-40.0 if dir > 0.0 else s.x + 40.0,
		randf_range(s.y * 0.08, s.y * 0.30)
	)
	_birds.append([
		pos, randf() * TAU, randf_range(9.0, 14.0) * _scale(), dir, 0.0
	])


## Новый метеор: падает сверху по диагонали вниз, хвост смотрит назад
## по движению. Длина и скорость — с разбросом, чтобы два подряд не
## были копией.
func _spawn_meteor() -> void:
	var s := get_viewport_rect().size
	if s.x <= 0.0 or s.y <= 0.0:
		return
	var sc := _scale()
	var side := 1.0 if randf() < 0.5 else -1.0
	var dir := Vector2(side * randf_range(0.30, 0.75), 1.0).normalized()
	_meteors.append([
		Vector2(randf_range(s.x * 0.12, s.x * 0.88), -20.0 * sc),
		dir, randf_range(40.0, 90.0) * sc, 0.0, randf_range(260.0, 420.0) * sc
	])


## Метеор: яркая голова и хвост из четырёх отрезков с падающей
## прозрачностью. Затухает по краям полёта: на чём-то исчезает резко.
func _draw_meteors() -> void:
	var sc := _scale()
	var ms := get_viewport_rect().size
	for m in _meteors:
		var p: Vector2 = m[0]
		var dir: Vector2 = m[1]
		var life: float = float(m[3])
		var ln: float = float(m[2])
		var fade := clampf(life * 2.0, 0.0, 1.0)
		# К холмам метеор гаснет заранее и целиком — и голова, и хвост:
		# иначе хвост обрывается вместе с головой в один кадр
		# (автор 10.2026: «хвост тут же исчезает вместе с ним»).
		var ground := 1.0
		if ms.y > 0.0:
			ground = clampf((ms.y * 0.45 - p.y) / (ms.y * 0.15), 0.0, 1.0)
		fade *= ground
		for i in 4:
			var t0 := float(i) / 4.0
			var t1 := float(i + 1) / 4.0
			draw_line(
				p - dir * ln * t1, p - dir * ln * t0,
				Color(1.0, 0.97, 0.88, (1.0 - t0) * 0.80 * fade),
				(2.8 - 0.5 * float(i)) * sc
			)
		draw_circle(p, 2.6 * sc, Color(1.0, 0.99, 0.95, fade))


## Чайка-галочка: два крыла-дуги, машут синусом от фазы и возраста.
## Дуги строим ВВЕРХ (углы вокруг 1.5π: в экранных координатах Y
## смотрит вниз, поэтому нижняя полусфера — это 0.5π). Снизу крылья
## выглядели перевёрнутыми — птица плавала кверху пузом (заметил
## автор на эмуляторе).
## Чайка: крылья — безье от тела, кончики ходят вверх/вниз.
## Внутренний конец крыла у тела, внешний — на окружности:
## взмах виден как поворот крыльев, а не елозение всей галки
## и не вытягивание тела каплей (обе ошибки тут уже были).
func _bird_wing(p: Vector2, r: float, side: float, lift: float) -> PackedVector2Array:
	var inner := p + Vector2(side * 0.15 * r, 0.0)
	var outer := p + Vector2(side * 1.05 * r, -lift * 0.85 * r)
	# Горб крыла следует за ходом плюс постоянный лёгкий изгиб,
	# иначе середина цикла — мёртвая прямая.
	var ctrl := (inner + outer) * 0.5 + Vector2(0.0, -0.30 * r * lift - 0.08 * r)
	var pts := PackedVector2Array()
	for i in 9:
		var t := float(i) / 8.0
		var a := inner.lerp(ctrl, t)
		var b := ctrl.lerp(outer, t)
		pts.append(a.lerp(b, t))
	return pts


func _draw_birds() -> void:
	var col := Color(0.35, 0.38, 0.45, 0.85)
	var sc := _scale()
	for b in _birds:
		var p: Vector2 = b[0]
		var r: float = float(b[2])
		# Взмах: фаза от возраста, период ~2.1 с. Медленный, вальяжный.
		var lift := sin(float(b[1]) + float(b[4]) * 3.0)
		draw_polyline(_bird_wing(p, r, -1.0, lift), col, 2.5 * sc)
		draw_polyline(_bird_wing(p, r, 1.0, lift), col, 2.5 * sc)
		# Тельце: эллипс поверх внутренних концов крыльев, иначе
		# два крыла висят раздельно. Трансформ сбрасываем сразу.
		draw_set_transform(p, 0.0, Vector2(0.30 * r, 0.20 * r))
		draw_circle(Vector2.ZERO, 1.0, col)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Масштаб фона под экран: облака, звёзды и птицы одного калибра.
## Раньше считался на месте в трёх местах, а птицы не масштабировались
## вовсе: на 1080px они выходили тонкими чёрточками.
func _scale() -> float:
	var s := get_viewport_rect().size
	return clampf(minf(s.x / 1100.0, s.y / 650.0), 0.5, 2.5)


func _draw() -> void:
	var s := get_viewport_rect().size
	if s.x <= 0.0 or s.y <= 0.0:
		return
	draw_texture_rect(_sky, Rect2(Vector2.ZERO, s), false)
	if night:
		_draw_stars(s)
		_draw_moon(s)
		# Метеоры — по небу, до холмов: падая, они не летят над землёй.
		_draw_meteors()
	else:
		_draw_sun(s)
	# Холмы — поверх звёзд: небо кончается там, где начинается земля,
	# звёзды на холмах не висят. Птицы — перед холмами (они ближе),
	# облака выше всех.
	_draw_hills(s)
	if not night:
		_draw_birds()
	_draw_clouds(s)


## Далёкие холмы: видны по краям карточки с текстом, середину она
## закрывает. Большие круги, обрезанные краем экрана, — дёшево и ровно.
## Правила холмов (автор 18.10.2026, №4 и правка после релиза 18.10:
## «не уменьшать радиусы, а опустить вниз центры, радиусы вернуть
## большими»): радиус от ШИРИНЫ экрана (весь s.x, у обоих) — иначе на
## телефоне
## видны два раздельных шара с провалом посередине; высоту держит
## ОПУЩЕННЫЙ вниз центр: вершина обязана оставаться в нижней трети
## неба (64%/72% высоты), чтобы не съедать солнце и луну. При таких
## радиусах и низких центрах дуги перекрываются — провала внизу нет.
func hill_radius_1(s: Vector2) -> float:
	return s.x


func hill_radius_2(s: Vector2) -> float:
	return s.x


## Верх первой горы: во всех ориентациях на одной высоте (доля высоты).
func hill_top_1(s: Vector2) -> float:
	return s.y * 0.64


## Верх второй горы — ниже первой: земля поднимается ступеньками.
func hill_top_2(s: Vector2) -> float:
	return s.y * 0.72


func hill_center_1(s: Vector2) -> Vector2:
	return Vector2(s.x * 0.10, hill_top_1(s) + hill_radius_1(s))


func hill_center_2(s: Vector2) -> Vector2:
	return Vector2(s.x * 0.94, hill_top_2(s) + hill_radius_2(s))


## Полуширина горы на высоте y (когда вершина выше): по ней тест
## считает, что земля в нижней полосе НЕ имеет провала между шарами.
func hill_span_1(s: Vector2, y: float) -> float:
	var dy := hill_center_1(s).y - y
	if dy <= 0.0 or dy >= hill_radius_1(s):
		return 0.0
	return sqrt(hill_radius_1(s) * hill_radius_1(s) - dy * dy)


func hill_span_2(s: Vector2, y: float) -> float:
	var dy := hill_center_2(s).y - y
	if dy <= 0.0 or dy >= hill_radius_2(s):
		return 0.0
	return sqrt(hill_radius_2(s) * hill_radius_2(s) - dy * dy)


func _draw_hills(s: Vector2) -> void:
	if night:
		draw_circle(hill_center_1(s), hill_radius_1(s), Color("#16283a"))
		draw_circle(hill_center_2(s), hill_radius_2(s), Color("#1b3040"))
	else:
		draw_circle(hill_center_1(s), hill_radius_1(s), Color("#cfe6b8"))
		draw_circle(hill_center_2(s), hill_radius_2(s), Color("#bcdc9f"))


## Солнце с ореолом. Ореол — не жёлтый: жёлтый по голубому небу
## даёт грязно-зелёный шар (видел на эмуляторе). Тёплый белый
## смешивается с небом в светлую дымку, как и должно быть.
func _draw_sun(s: Vector2) -> void:
	var c := Vector2(s.x * 0.87, s.y * 0.13)
	var r := minf(s.x, s.y) * 0.045
	draw_circle(c, r * 2.4, Color(1.0, 0.97, 0.86, 0.16))
	draw_circle(c, r * 1.7, Color(1.0, 0.98, 0.90, 0.22))
	draw_circle(c, r, Color("#ffd94d"))


## Луна вместо солнца: бледный диск и пара кратеров потемнее.
## Ореол двухслойный, как у солнца: один слабый круг на тёмном небе
## терялся, и луна читалась «чёрной дырой».
func _draw_moon(s: Vector2) -> void:
	var c := Vector2(s.x * 0.87, s.y * 0.13)
	var r := minf(s.x, s.y) * 0.045
	draw_circle(c, r * 2.4, Color(0.90, 0.93, 1.0, 0.14))
	draw_circle(c, r * 1.7, Color(0.92, 0.94, 1.0, 0.20))
	draw_circle(c, r, Color("#f4f1de"))
	draw_circle(c + Vector2(-r * 0.3, -r * 0.2), r * 0.22, Color("#d9d4bd"))
	draw_circle(c + Vector2(r * 0.25, r * 0.3), r * 0.15, Color("#d9d4bd"))


## Звёзды: детерминированные точки (формула от индекса, не randf —
## иначе мерцали бы каждый кадр). Раскладка (автор 18.10.2026):
## две трети живут в мягкой наклонной полосе — имитация млечного
## пути, треть рассыпана ПО всему верхнему небу: раньше обе
## прогрессии были комплементарными (0.61803 и 1−0.61803), и вся
## стая ложилась на прямую. Яркость волной от времени, размах
## крупный: прежние 0.35·sin были еле заметны (автор: «мигания
## чуть более сильными, а то еле заметно»).
func star_xy(i: int) -> Vector2:
	var u := fposmod(float(i) * 0.61803 + 0.13, 1.0)
	if i % 3 != 2:
		# Полоса: gentle diagonal + собственный джиттер по высоте,
		# у каждой звезды свой сдвиг — полоса не идеальная прямая.
		var band := 0.42 - 0.16 * (u - 0.5)
		var j := fposmod(float(i) * 0.2731 + 0.05, 1.0)
		return Vector2(u, clampf(band + (j - 0.5) * 0.26, 0.03, 0.62))
	# Рассыпанные: вторая, НЕзависимая прогрессия по высоте.
	var v := fposmod(float(i) * 0.2731 + 0.41, 1.0)
	return Vector2(u, clampf(v * 0.62, 0.03, 0.62))


## Яркость звезды: alpha 0.15..1.0, у каждой свой период.
func star_tw(i: int) -> float:
	var w := 0.6 + 0.13 * float(i % 5)
	return clampf(0.55 + 0.45 * sin(_time * w + float(i)), 0.15, 1.0)


func _draw_stars(s: Vector2) -> void:
	for i in 48:
		var p := star_xy(i)
		var r := 1.0 + 1.2 * fposmod(float(i) * 0.33, 1.0)
		draw_circle(Vector2(s.x * p.x, s.y * p.y), r * _scale(), Color(1, 1, 1, star_tw(i)))


func _draw_clouds(s: Vector2) -> void:
	var sc := _scale()
	# x, y, скорость дрейфа (доля ширины экрана в секунду), фаза, размер.
	# Дрейф ЛИНЕЙНЫЙ с закольцовкой, очень медленный: безмятежность.
	# Прежние скорости (в 2.5 раза выше) рябили.
	var bases := [
		[0.20, 0.12, 0.006, 0.0, 1.9],
		[0.52, 0.20, 0.010, 2.1, 1.4],
		[0.72, 0.09, 0.004, 4.2, 2.2],
	]
	# Запас за краем экрана — на ширину самого облака, иначе оно
	# появляется из ниоткуда: круг уходит за край на m, но не исчезает.
	var m := 300.0 * sc
	var span := s.x + m * 2.0
	for b in bases:
		var x := fposmod(s.x * float(b[0]) + _time * float(b[2]) * s.x, span) - m
		# Лёгкое покачивание по вертикали: без него линейный дрейф
		# выглядит как движущаяся калька. Тоже медленное.
		var y := s.y * float(b[1]) + sin(_time * 0.15 + float(b[3])) * 5.0 * sc
		_cloud(Vector2(x, y), float(b[4]) * sc)


## Облако — приплюснутый ком из кругов: снизу серо-голубая тень,
## сверху белые купола. Без тени облако выглядит наклейкой.
## Круги НЕпрозрачные: при полупрозрачности мозг видит не объединение,
## а пересечения — ночью ком читался как набор наложенных дисков
## (видел на эмуляторе). Ночь поэтому не «призрачная», а тёмная и
## плотная: светлее ночного неба, но без просвечивания.
func _cloud(p: Vector2, sc: float) -> void:
	var shadow := Color("#d3e2ec")
	var white := Color("#ffffff")
	if night:
		shadow = Color("#2c3750")
		white = Color("#4a5674")
	draw_circle(p + Vector2(-46, 8) * sc, 22.0 * sc, shadow)
	draw_circle(p + Vector2(0, 10) * sc, 26.0 * sc, shadow)
	draw_circle(p + Vector2(46, 8) * sc, 22.0 * sc, shadow)
	draw_circle(p + Vector2(-40, 0) * sc, 20.0 * sc, white)
	draw_circle(p + Vector2(-10, -14) * sc, 26.0 * sc, white)
	draw_circle(p + Vector2(22, -10) * sc, 22.0 * sc, white)
	draw_circle(p + Vector2(48, 2) * sc, 16.0 * sc, white)
