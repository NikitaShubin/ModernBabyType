extends SceneTree
## ПРОБА: честная ТЕНЬ модели в позе покоя вдоль мировой z, растром.
## Нужна, чтобы увидеть ВПАДИНЫ между пальцами: профиль shadow_world.log
## даёт только крайние x на строке, а вырезы — это внутренняя структура.
## Печать ASCII (y сверху вниз), шаг 1 мм.

const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")

const HOME := [-20.0000, -10.0000, 0.0000, 0.0000, 34.0000, -83.8789,
	45.6444, -49.0000, 38.0315, 33.9876, 14.0965, -12.2396, 27.5328,
	55.4005, 28.8211, -7.2805, 23.6516, 63.6973, 34.8851, -2.9139,
	33.9503, 42.4299, 19.5347, 0.5225, 4.1371, -9.0000, -10.0000,
	21.3197, 0.7834]

const X0 := -70.0
const X1 := 70.0
const Y0 := -20.0
const Y1 := 175.0
const STEP := 1.0
const T0 := -105.0
const T1 := 60.0
const TSTEP := 2.5

var _m = null
var _d := Vector3.BACK


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


func _inside(x: float, y: float) -> bool:
	var base := Vector3(x, y, 0.0)
	var t := T0
	while t <= T1:
		if _m.field(base + _d * t) <= 0.0:
			return true
		t += TSTEP
	return false


func _initialize() -> void:
	var pose := _pose_from_flat(HOME)
	_m = HandModel.new(1.0, 0.0, pose)
	var xf := ArmModel.hand_transform(pose["arm"])
	_d = xf.basis.transposed() * Vector3.BACK
	print("# тень кисти вдоль мировой z, система кисти, шаг %.1f мм" % STEP)
	var hdr := "     "
	var x := X0
	while x <= X1:
		hdr += ("|" if absf(x) < 0.5 else " ")
		x += STEP
	print(hdr)
	var y := Y1
	while y >= Y0:
		var row := "%5.0f" % y
		x = X0
		while x <= X1:
			row += "#" if _inside(x, y) else "."
			x += STEP
		print(row)
		y -= STEP
	quit(0)
