extends SceneTree
## ПРОБА: точные ИНТЕРВАЛЫ тени на горизонтальных строках (шаг x 0.25 мм).
## Нужна, чтобы измерить настоящую ширину и глубину щелей между пальцами
## и сравнить их с тем, что даёт полярный контур.

const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")

const HOME := [-20.0000, -10.0000, 0.0000, 0.0000, 34.0000, -83.8789,
	45.6444, -49.0000, 38.0315, 33.9876, 14.0965, -12.2396, 27.5328,
	55.4005, 28.8211, -7.2805, 23.6516, 63.6973, 34.8851, -2.9139,
	33.9503, 42.4299, 19.5347, 0.5225, 4.1371, -9.0000, -10.0000,
	21.3197, 0.7834]

const X0 := -50.0
const X1 := 60.0
const XSTEP := 0.25
const Y0 := 60.0
const Y1 := 135.0
const YSTEP := 2.5
const T0 := -105.0
const T1 := 60.0
const TSTEP := 2.0

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
	var y := Y1
	while y >= Y0:
		var runs := []
		var on := false
		var start := 0.0
		var x := X0
		while x <= X1:
			var ins := _inside(x, y)
			if ins and not on:
				on = true
				start = x
			elif not ins and on:
				on = false
				runs.append([start, x - XSTEP])
			x += XSTEP
		if on:
			runs.append([start, X1])
		var txt := ""
		for r in runs:
			txt += " [%.2f..%.2f]" % [r[0], r[1]]
		print("%6.1f%s" % [y, txt])
		y -= YSTEP
	quit(0)
