class_name Hands3D
extends RefCounted

## Кисть ИЗ 3D-ИССЛЕДОВАНИЯ (tools/hand3d) — геометрия и прямая кинематика.
##
## Автор 04.11.2026: «это должны быть те самые руки из 3д». Поэтому модель
## здесь не своя: скелет, углы покоя, кожа и плечо — один в один
## hand_model.gd и arm_model.gd исследования (числа перенесены, объяснения
## остались там). Игра НЕ решает IK: поза каждого нажатия запечена
## (hands_poses.gd, запекает tools/hand3d/bake_poses.gd тем же решателем,
## что и просмотрщик доски) — здесь только FK и список примитивов кожи,
## который hands.gd проецирует на плоскость доски.
##
## Координаты — миллиметры исследования: x вправо, y от печатающего,
## z вверх от доски (лицо клавиши FACE_Z = −69). Проекция на экран —
## по xy; z живёт только в механике нажатия.

const PITCH_MM := 19.05
const ROW_STEP_MM := 21.7575  # (PITCH − 1) * 1.15 + 1
const HOME_Y := 152.0

const FINGERS := ["II", "III", "IV", "V"]

## Пальцы игры → лучи исследования. Порядок плоской позы — FINGERS.
const RAY_OF := {1: "II", 2: "III", 3: "IV", 4: "V"}

const MC_BASE := {
	"I": Vector3(22, 26, -4),
	"II": Vector3(19, 28, 4),
	"III": Vector3(4, 27, 5),
	"IV": Vector3(-10, 27, 3),
	"V": Vector3(-24, 26, 0),
}
const MC_AIM := {
	"I": Vector3(47, 65, -13),
	"II": Vector3(28.0, 92.0, 4.5),
	"III": Vector3(6.5, 92.0, 6),
	"IV": Vector3(-14, 88.5, 2.5),
	"V": Vector3(-33.5, 81.5, -1),
}
const MC_LEN := {"I": 46.0, "II": 67.0, "III": 65.0, "IV": 62.0, "V": 56.0}
const PH_LEN := {
	"I": [34.0, 25.0],
	"II": [44.0, 25.0, 19.0],
	"III": [48.0, 27.0, 21.0],
	"IV": [47.0, 27.0, 20.0],
	"V": [37.0, 21.0, 16.0],
}
const FAN := {"II": 1.2, "III": 0.2, "IV": -1.0, "V": -2.2}
const FLEX := {"II": [20.0, 34.0, 14.0], "III": [19.0, 33.0, 14.0],
	"IV": [22.0, 36.0, 15.0], "V": [26.0, 40.0, 17.0]}

const THUMB_REST := {"cmc_flex": 0.0, "cmc_abd": 0.0, "twist": 0.0,
	"mcp": 16.0, "ip": 34.0}
const THUMB_JOINTS := ["cmc_flex", "cmc_abd", "twist", "mcp", "ip"]

const SKIN_R := {
	"II": [9.8, 8.7, 7.4, 5.5],
	"III": [10.2, 9.0, 7.6, 5.7],
	"IV": [9.6, 8.5, 7.2, 5.3],
	"V": [8.6, 7.6, 6.5, 4.9],
}
const THUMB_R := [11.8, 10.8, 9.6, 6.6]
const THUMB_TIP_R := 6.6

const FOREARM_L := 150.0
const ELBOW := Vector3(0, -FOREARM_L, 0)
const ARM_JOINTS := ["wrist_flex", "wrist_dev", "pronation",
	"forearm_flex", "forearm_abd", "elbow_x", "elbow_y", "elbow_z"]

## ---------- плоская поза ----------

## [0..7] плечо, [8..23] пальцы II..V (mcp, pip, dip, fan), [24..28] большой.
static func arm_of(flat: Array) -> Dictionary:
	var a := {}
	for i in ARM_JOINTS.size():
		a[ARM_JOINTS[i]] = float(flat[i])
	return a


static func finger_angles(flat: Array, ray: String) -> Dictionary:
	var i := 8 + FINGERS.find(ray) * 4
	return {"mcp": float(flat[i]), "pip": float(flat[i + 1]),
		"dip": float(flat[i + 2]), "fan": float(flat[i + 3])}


static func thumb_angles(flat: Array) -> Dictionary:
	var t := {}
	for i in THUMB_JOINTS.size():
		t[THUMB_JOINTS[i]] = float(flat[24 + i])
	return t


## Покоординатный лерп двух плоских поз: поза кисти на кадре — это
## покой, подтянутый к позе нажатия на его ход. Углы — одна мера,
## поэтому лерп честный (промежуточная поза — тоже поза этой модели).
static func blend(a: Array, b: Array, t: float) -> Array:
	var out := []
	for i in mini(a.size(), b.size()):
		out.append(lerpf(float(a[i]), float(b[i]), t))
	return out


## Средневзвешенная поза по нескольким нажатиям: {луч: [поза, вес]}.
## Сумма весов ограничена единицей: покой — это тоже участник с весом
## 1 − Σw, иначе одно недожатое нажатие тянуло бы кисть на себя целиком.
static func blend_many(base: Array, poses: Dictionary) -> Array:
	var out: Array = []
	for i in base.size():
		out.append(float(base[i]))
	if poses.is_empty():
		return out
	var wsum := 0.0
	for k in poses.keys():
		wsum += clampf(float((poses[k] as Array)[1]), 0.0, 1.0)
	var k0 := clampf(1.0 - wsum, 0.0, 1.0)
	for i in out.size():
		var v := float(base[i]) * k0
		for k in poses.keys():
			var e: Array = poses[k] as Array
			var p: Array = e[0] as Array
			v += float(p[i]) * clampf(float(e[1]), 0.0, 1.0)
		out[i] = v
	return out


## ---------- прямая кинематика ----------

static func _bend(d: Vector3, axis: Vector3, ang: float) -> Vector3:
	if absf(ang) < 0.00001:
		return d
	return d.rotated(axis, ang)


static func _flex(d: Vector3, t: Vector3, ang: float) -> Vector3:
	if absf(ang) < 0.00001:
		return d
	var axis := d.cross(t)
	if axis.length_squared() < 0.0000001:
		return d
	return d.rotated(axis.normalized(), ang)


static func metacarpal_head(ray: String) -> Vector3:
	var base: Vector3 = MC_BASE[ray]
	var aim: Vector3 = MC_AIM[ray]
	return base + (aim - base).normalized() * float(MC_LEN[ray])


## Цепь пальца: 4 точки [MCP, PIP, DIP, кончик]. Ось сгиба одна на всю
## цепь — иначе при вертикальной фаланге векторное произведение
## вырождается и сустав отказывается сгибаться (см. hand_model.gd).
static func finger_fk(ray: String, angles: Dictionary) -> PackedVector3Array:
	var mcp := metacarpal_head(ray)
	var down := Vector3(0, 0, -1)
	var fan := deg_to_rad(float(angles.get("fan", FAN[ray])))
	var d := Vector3(sin(fan), cos(fan), 0.0)
	var axis := d.cross(down).normalized()
	var lens: Array = PH_LEN[ray]
	var d1 := _bend(d, axis, deg_to_rad(float(angles.get("mcp", FLEX[ray][0]))))
	var pip := mcp + d1 * float(lens[0])
	var d2 := _bend(d1, axis, deg_to_rad(float(angles.get("pip", FLEX[ray][1]))))
	var dip := pip + d2 * float(lens[1])
	var d3 := _bend(d2, axis, deg_to_rad(float(angles.get("dip", FLEX[ray][2]))))
	var tip := dip + d3 * float(lens[2])
	return PackedVector3Array([mcp, pip, dip, tip])


## Цепь большого: [CMC, MCP, IP, кончик] и направление столбика (для
## поворота тенара вслед за первой пястной).
static func thumb_fk(arg) -> Dictionary:
	var th: Dictionary
	if arg is Dictionary:
		var d := arg as Dictionary
		th = {}
		for j in THUMB_JOINTS:
			th[j] = float(d.get(j, THUMB_REST[j]))
	else:
		th = THUMB_REST.duplicate()
	var base: Vector3 = MC_BASE["I"]
	var lens: Array = PH_LEN["I"]
	var palm := Vector3(-0.35, 0.10, -0.93).normalized()
	var palmar := Vector3(0, 0, -1)
	var radial := Vector3(1, 0, 0)
	var d0 := (Vector3(MC_AIM["I"]) - base).normalized()
	d0 = _flex(d0, palmar, deg_to_rad(float(th["cmc_flex"])))
	d0 = _flex(d0, radial, deg_to_rad(float(th["cmc_abd"])))
	var mcp := base + d0 * float(MC_LEN["I"])
	var palm_t := palm.rotated(d0, deg_to_rad(float(th["twist"])))
	var axis := d0.cross(palm_t).normalized()
	var d1 := _bend(d0, axis, deg_to_rad(float(th["mcp"])))
	var ip := mcp + d1 * float(lens[0])
	var d2 := _bend(d1, axis, deg_to_rad(float(th["ip"])))
	var tip := ip + d2 * float(lens[1])
	return {"pts": PackedVector3Array([base, mcp, ip, tip]), "d0": d0}


## Точка касания пальца: низ сферы кончика (доска — стена при
## постоянном z, сфера касается её ровно под центром).
static func finger_pad(ray: String, pts: PackedVector3Array) -> Vector3:
	return pts[3] + Vector3(0.0, 0.0, -float(SKIN_R[ray][3]))


static func thumb_pad(pts: PackedVector3Array) -> Vector3:
	return pts[3] + Vector3(0.0, 0.0, -THUMB_TIP_R)


## ---------- плечо ----------

static func _rot_up_to(dir: Vector3) -> Basis:
	var d := dir.normalized()
	var c := clampf(Vector3.UP.dot(d), -1.0, 1.0)
	if c > 0.999999:
		return Basis.IDENTITY
	var axis := Vector3.UP.cross(d)
	if axis.length_squared() < 0.000000001:
		return Basis(Vector3.RIGHT, PI)
	return Basis(axis.normalized(), acos(c))


static func elbow_of(arm: Dictionary) -> Vector3:
	return ELBOW + Vector3(float(arm.get("elbow_x", 0.0)),
		float(arm.get("elbow_y", 0.0)), float(arm.get("elbow_z", 0.0)))


## Рама кисти: R_root — кратчайшая дуга UP→направление предплечья,
## R_fore — пронация вокруг своей оси, R_wrist — отклонение и сгиб.
## При покое плеча (все нули) это ТОЖДЕСТВО, и одобренная геометрия
## не двигается ни на микрон.
static func hand_xf(arm: Dictionary) -> Transform3D:
	var flex := deg_to_rad(float(arm.get("forearm_flex", 0.0)))
	var abd := deg_to_rad(float(arm.get("forearm_abd", 0.0)))
	var dir := Vector3(sin(abd) * cos(flex), cos(abd) * cos(flex), sin(flex))
	var r_root := _rot_up_to(dir)
	var r_fore := r_root * Basis(Vector3.UP,
		deg_to_rad(float(arm.get("pronation", 0.0))))
	var r_wrist := r_fore * Basis(Vector3.BACK,
		deg_to_rad(-float(arm.get("wrist_dev", 0.0)))) \
		* Basis(Vector3.RIGHT, deg_to_rad(-float(arm.get("wrist_flex", 0.0))))
	var wrist := elbow_of(arm) + r_root * Vector3(0, FOREARM_L, 0)
	return Transform3D(r_wrist, wrist)


## Локальная рама кисти → мир: у правой кисти x зеркалится.
static func to_world(side: String, root_x: float, q: Vector3) -> Vector3:
	if side == "R":
		return Vector3(root_x - q.x, q.y, q.z)
	return Vector3(root_x + q.x, q.y, q.z)


## ---------- плечо ----------

static func pad(flat: Array, side: String, root_x: float, ray: String) -> Vector3:
	var xf := hand_xf(arm_of(flat))
	if ray == "I":
		return to_world(side, root_x,
			xf * thumb_pad(thumb_fk(thumb_angles(flat))["pts"]))
	return to_world(side, root_x,
		xf * finger_pad(ray, finger_fk(ray, finger_angles(flat, ray))))
