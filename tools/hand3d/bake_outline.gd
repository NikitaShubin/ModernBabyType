# ЗАПЕКАНИЕ КОНТУРА КИСТИ ИЗ 3D-ИССЛЕДОВАНИЯ.
#
# Объединение проекций примитивов — НЕ проекция объединения: сглаживание
# smin между запястьем, первой пястной и тенаром выносит настоящую
# поверхность на 5 мм наружу, а объединение теней этого не знает. Отсюда
# ступеньки и «шишах» на контуре (автор 05.11.2026). Поэтому контур
# снимается с САМОГО ПОЛЯ hand_model.field_palm() — вдоль ЛОКАЛЬНОЙ z
# кисти, той же осью, которой игра кладёт пальцы на клавиши, — и
# кладётся в игру готовым. Пальцы и большой в полярную меру не влезают
# (торчат радиально, каждый ~10°) — их игра строит лентами из своей FK
# (hands.gd), а здесь остаётся ладонь с предплечьем.
#
# Форма хранения — полярные радиусы от неподвижного центра в системе
# кисти: поза кадра смешивает радиусы двух-трёх поз покоординатно, значит
# промежуточная поза — тоже контур этой модели. Топология (сколько
# пальцев, где впадины) у всех поз одна, поэтому смешивать честно.
#
# Предплечье входит в тот же контур: в исследовании кисть обрезана плоско
# (hand_model.field: maxf(d, -1.5 - p.y)), и без трубы от среза торчал
# полукруглый обрубок (автор 05.11.2026). Труба прикреплена к кисти
# жёстко и длинная (370 мм видимых) — она уходит за край экрана в любой
# раскладке. Ступеньки на запястье нет: радиус трубы МЕРЯЕТСЯ у каждой
# позы по тени самой ладони на высоте среза, отдельно на лучевую и
# локтевую сторону, и ось трубы ставится так, чтобы совпасть с обеими
# (сварка smin пробована и отвергнута: она выносит запястье наружу на
# 3.6 мм — «бугор» вместо полки).
#
# Запуск (headless; шардами по 8 — ~7 мин, целиком — ~1 час):
#   for i in 0 1 2 3 4 5 6 7; do
#     docker run --rm --user $(id -u):$(id -g) -v $PWD:/work \
#       -e HOME=/tmp/mbt-home -e MBT_SHARD=$i -e MBT_OF=8 \
#       -w /work/tools/hand3d mbt-godot --headless --path /work/tools/hand3d \
#       --script res://bake_outline.gd &
#   done; wait
#   .venv/bin/python tools/hand3d/merge_shape.py
#   MBT_N=1 — только поза покоя (быстрая проверка алгоритма).
#
# Файл данных — сгенерированный: правки руками затрёт следующее запекание.
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")

const POSES := "/work/game/scripts/hands_poses.gd"
const PART := "/tmp/opencode/shape-part-%d.txt"

## Лучей на контур. 256 — шаг 1.4°: на кончике пальца (r≈160) хорда
## 3.9 мм, на запястье 0.7 мм. При 128 кончик пальца выходил
## двухвершинным углом.
const N := 256
## Центр полярной меры в системе кисти — в ладони, ниже пястных головок.
## Отсюда кисть звёздчата: впадины между пальцами смотрят наружу, а
## перепонка большого заполнена тенаром (см. field()).
const CENTER := Vector2(0.0, 22.0)
const RMAX := 440.0
const RSTEP := 2.5

## Луч взгляда: p(t) = (x, y, 0) + t·d. Кисть в z живёт в границах
## исследования (bounds_min/max: z −95..55), d почти единичный по z.
const T0 := -105.0
const T1 := 60.0
const TSTEP := 2.5

## Предплечье — из arm_view.gd: труба от среза к локтю, сечение расширяется
## на 24% (TUBE_L 400, CAP_L 30 — скруглённый торец локтя не виден).
## Длина с запасом: рука поднимается, а предплечье обязано уходить за край
## экрана, а не кончаться обрубком.
const CUT_Y := -1.5
const TUBE_L := 400.0
const CAP_L := 30.0
## Радиус трубы у среза МЕРЯЕТСЯ у каждой позы по тени самой ладони на
## высоте среза. Меряется ПО СТОРОНАМ, а ось трубы сдвигается на
## полуразность: так тень трубы совпадает с тенью ладони с обеих сторон
## даже если модель когда-нибудь перестанет быть симметричной у среза
## (сейчас обе стороны дают 27.72 мм во всех 108 позах — срез приходится
## на запястную капсулу и от позы не зависит). Жёсткий радиус давал полку
## на лучезапястном суставе, если расходился с ладонью.
const FORE_FLARE := 1.24

## Границы исследования с запасом: за ними поле заведомо снаружи, и
## дёргать дорогое field() незачем (это и есть ускорение в 3–5 раз).
const BMIN := Vector3(-90.0, -40.0, -110.0)
const BMAX := Vector3(130.0, 240.0, 70.0)

var _m = null
var _d := Vector3.BACK
## Полуширины тени ладони на высоте среза: +x и −x, и ось трубы между
## ними. У покоя обе равны (27.72), у наклонённой кисти расходятся.
var _rx := 27.375
var _rn := 27.375
var _rc := 0.0
var _rr := 27.375


# ---------------------------------------------------------------- данные

func _read_poses() -> Dictionary:
	var txt := FileAccess.get_file_as_string(POSES)
	if txt == "":
		push_error("bake_outline: нет %s" % POSES)
		return {}
	var out := {"L": {}, "R": {}}
	var side := ""
	var in_press := false
	for raw in txt.split("\n"):
		var ln := raw.strip_edges()
		if ln.begins_with("const HOME"):
			in_press = false
			continue
		if ln.begins_with("const PRESS"):
			in_press = true
			continue
		if ln.begins_with("\"L\":") or ln.begins_with("\"R\":"):
			var p := ln.split(":")
			var s := String(p[0]).replace("\"", "").strip_edges()
			if in_press:
				side = s
				continue
			# HOME: "L": [ ... ],
			var arr := _nums(ln.substr(ln.find("[")))
			if arr.size() == 29:
				out[s][" "] = arr
			continue
		if in_press and ln.begins_with("\"") and ln.contains(": ["):
			var q := ln.find("\":")
			var label := _unesc(ln.substr(1, q - 1))
			var arr2 := _nums(ln.substr(ln.find("[")))
			if arr2.size() == 29 and side != "":
				out[side][label] = arr2
	return out


func _unesc(s: String) -> String:
	var out := ""
	var i := 0
	while i < s.length():
		var ch := s[i]
		if ch == "\\" and i + 1 < s.length():
			i += 1
			out += s[i]
		else:
			out += ch
		i += 1
	return out


func _nums(s: String) -> Array:
	var i := s.find("[")
	var j := s.find("]")
	if i < 0 or j < 0:
		return []
	var out := []
	for part in s.substr(i + 1, j - i - 1).split(",", false):
		out.append(float(part.strip_edges()))
	return out


func _pose_from_flat(f: Array) -> Dictionary:
	var p := HandModel.rest_pose()
	var arm := {}
	for j in ArmModel.ALL_JOINTS.size():
		arm[ArmModel.ALL_JOINTS[j]] = float(f[j])
	p["arm"] = arm
	for i in HandModel.FINGERS.size():
		var ray: String = HandModel.FINGERS[i]
		p["fingers"][ray] = {"mcp": float(f[8 + i * 4]),
			"pip": float(f[9 + i * 4]), "dip": float(f[10 + i * 4]),
			"fan": float(f[11 + i * 4])}
	p["thumb_dof"] = 4
	var th := {}
	for j in HandModel.THUMB_JOINTS.size():
		th[HandModel.THUMB_JOINTS[j]] = float(f[24 + j])
	p["thumb"] = th
	return p


# ---------------------------------------------------------------- поле

## Предплечье в системе кисти: конус по −y от среза к локтю, ограничен
## плоскостью среза (выше неё кисть считает сама). Ось сдвинута на
## полуразность мер стороны, поэтому тень трубы совпадает с тенью ладони
## на срезе с обеих сторон — стык без ступеньки.
func _fore_d(p: Vector3) -> float:
	var len := TUBE_L - CAP_L
	var s := clampf((CUT_Y - p.y) / len, 0.0, 1.0)
	var r := _rr * (1.0 + (FORE_FLARE - 1.0) * s)
	var dx := p.x - _rc
	var d_side := sqrt(dx * dx + p.z * p.z) - r
	return maxf(maxf(d_side, (CUT_Y - len) - p.y), p.y - CUT_Y)


func _field(p: Vector3) -> float:
	if p.x < BMIN.x or p.x > BMAX.x or p.y < BMIN.y or p.y > BMAX.y \
			or p.z < BMIN.z or p.z > BMAX.z:
		return 100.0
	# ЛАДОНЬ С КОРНЯМИ ПАЛЬЦЕВ (field_roots), а не вся кисть: пальцы в
	# полярную меру не помещаются (они торчат от ладони радиально, каждый
	# занимает ~10° — на 256 лучах по одной точке на бок, и щели между
	# пальцами становятся широкими клиньями). Корни же — короткие
	# заготовки первых фаланг: они возвращают в контур ладони ТУ САМУЮ
	# фаску 6 мм, которой модель сваривает палец с ладонью, и жёсткое
	# объединение с лентой пальца перестаёт давать залом на стыке (автор
	# 06.11.2026: «контур там, где палец переходит в ладонь, имеет
	# неестественный изгиб»). Четыре пальца игра по-прежнему строит
	# лентами из своей FK (см. hands.gd).
	return _m.field_roots(p)


## Точка в тени САМОЙ КИСТИ (без предплечья).
func _in_hand(x: float, y: float) -> bool:
	var base := Vector3(x, y, 0.0)
	var t := T0
	while t <= T1:
		if _field(base + _d * t) <= 0.0:
			return true
		t += TSTEP
	return false


## Полуширина тени кисти на высоте y в сторону sign (−1 влево, +1 вправо).
func _half(y: float, sign: float) -> float:
	var lo := 0.0
	var hi := 70.0
	for i in 26:
		var mid := (lo + hi) * 0.5
		if _in_hand(sign * mid, y):
			lo = mid
		else:
			hi = mid
	return lo


## Точка в тени кисти ИЛИ предплечья. Стык — жёсткое объединение: радиус
## трубы уже совпадает с тенью ладони на срезе (см. FORE_FLARE/_rx/_rn),
## так что ступеньки нет, а сварка smin выносила запястье наружу.
func _inside(x: float, y: float) -> bool:
	var base := Vector3(x, y, 0.0)
	var t := T0
	while t <= T1:
		var p := base + _d * t
		if minf(_field(p), _fore_d(p)) <= 0.0:
			return true
		t += TSTEP
	return false


## Радиус первого выхода из тени по лучу из центра. Первый, а не
## последний: впадина между пальцами — граница, а не провал в ладонь.
func _ray(a: float) -> float:
	var dir := Vector2(cos(a), sin(a))
	var r := 0.0
	var prev := 0.0
	var hit := -1.0
	while r <= RMAX:
		if not _inside(CENTER.x + dir.x * r, CENTER.y + dir.y * r):
			hit = r
			break
		prev = r
		r += RSTEP
	if hit < 0.0:
		return RMAX
	var lo := prev
	var hi := hit
	for i in 10:
		var mid := (lo + hi) * 0.5
		if _inside(CENTER.x + dir.x * mid, CENTER.y + dir.y * mid):
			lo = mid
		else:
			hi = mid
	return lo


func _outline() -> Array:
	var out := []
	for k in N:
		out.append(_ray(TAU * float(k) / float(N)))
	return out


# ---------------------------------------------------------------- прогон

func _initialize() -> void:
	var poses := _read_poses()
	if poses.is_empty():
		quit(1)
		return
	var only := OS.get_environment("MBT_N") == "1"
	var shard := int(OS.get_environment("MBT_SHARD"))
	var of := maxi(1, int(OS.get_environment("MBT_OF")))
	var jobs := []
	for side in ["L", "R"]:
		var d: Dictionary = poses[side]
		var labels := d.keys()
		labels.sort()
		if only:
			labels = [" "]
		for lb in labels:
			jobs.append([side, lb])
	var done := 0
	var t_all := Time.get_ticks_msec()
	for idx in jobs.size():
		if idx % of != shard:
			continue
		var side: String = jobs[idx][0]
		var lb: String = jobs[idx][1]
		var t0 := Time.get_ticks_msec()
		var pose := _pose_from_flat(poses[side][lb] as Array)
		_m = HandModel.new(1.0, 0.0, pose)
		# Луч — ЛОКАЛЬНАЯ z кисти, а не мировая. Игра строит пальцы из своей
		# FK и кладёт подушечки на клавиши, отбрасывая локальную z; ладонь
		# обязана мериться той же осью, иначе наклон кисти даёт косую
		# проекцию и ладонь уезжает от пальцев на 7–10 мм.
		_d = Vector3.BACK
		_rx = _half(CUT_Y, 1.0)
		_rn = _half(CUT_Y, -1.0)
		_rc = 0.5 * (_rx - _rn)
		_rr = 0.5 * (_rx + _rn)
		var radii := _outline()
		_write(side, lb, radii, shard)
		done += 1
		print("bake_outline: шард %d/%d  %s %-10s r+=%.2f r-=%.2f  %.1f s" % [shard,
			of, side, "покой" if lb == " " else lb, _rx, _rn,
			(Time.get_ticks_msec() - t0) / 1000.0])
	print("bake_outline: шард %d/%d  %d поз за %.0f s" % [shard, of, done,
		(Time.get_ticks_msec() - t_all) / 1000.0])
	quit(0)


func _write(side: String, label: String, radii: Array, shard: int) -> void:
	var path := PART % shard
	var f := FileAccess.open(path, FileAccess.READ_WRITE)
	if f == null:
		f = FileAccess.open(path, FileAccess.WRITE)
	else:
		f.seek_end()
	if f == null:
		push_error("bake_outline: не могу писать %s" % path)
		return
	var parts := []
	for v in radii:
		parts.append("%.2f" % float(v))
	f.store_line("%s\t%s\t%s" % [side, _esc(label), ",".join(parts)])
	f.close()


func _esc(s: String) -> String:
	return s.replace("\\", "\\\\").replace("\t", "\\t") \
		.replace("\n", "\\n")
