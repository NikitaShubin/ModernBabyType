# ЧЕСТНАЯ ТЕНЬ КИСТИ ВДОЛЬ МИРОВОЙ z — той, которой игра и проецирует.
#
# shadow_home.gd сканировал вдоль ЛОКАЛЬНОЙ z кисти. Но кисть повёрнута
# плечом (wrist_flex = -20), и мировая z в системе кисти — это
# d = Rᵀ·e_z = (0, 0.342, 0.940), а не (0, 0, 1). Тень вдоль локальной z
# систематически смещена, и сверять с ней объединение проекций нельзя:
# на y=42..52 «тень» оказывалась НА 2.9 мм ВНУТРИ объединения, чего не
# бывает по построению (объединение проекций всегда лежит в проекции
# объединения).
#
# Координаты q = (qx, qy) — те же, в которых меряет hand_prof_dbg.gd:
# мировые xy, разложенные по первым двум столбцам R (то есть точка q
# лежит в плоскости p_z = 0 системы кисти). Линия взгляда для q —
# p(t) = (qx, qy, 0) + t·d: её мировые xy не зависят от t, потому что
# R[0:2,:]·d = 0.
#
# Запуск (headless):
#   docker run --rm ... mbt-godot --headless --path /work/tools/hand3d \
#     --script res://shadow_world.gd
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")

const X0 := -62.0
const X1 := 68.0
const Y0 := -10.0
const Y1 := 70.0
const T0 := -55.0
const T1 := 50.0
const TSTEP := 1.0

const HOME := [-20.0000, -10.0000, 0.0000, 0.0000, 34.0000, -83.8789,
	45.6444, -49.0000, 38.0315, 33.9876, 14.0965, -12.2396, 27.5328,
	55.4005, 28.8211, -7.2805, 23.6516, 63.6973, 34.8851, -2.9139,
	33.9503, 42.4299, 19.5347, 0.5225, 4.1371, -9.0000, -10.0000,
	21.3197, 0.7834]

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


func _initialize() -> void:
	var pose := _pose_from_flat(HOME)
	_m = HandModel.new(1.0, 0.0, pose)
	var xf := ArmModel.hand_transform(pose["arm"])
	_d = xf.basis.transposed() * Vector3.BACK
	print("D %.9f %.9f %.9f" % [_d.x, _d.y, _d.z])


func _inside(x: float, y: float) -> bool:
	var t := T0
	var base := Vector3(x, y, 0.0)
	while t <= T1:
		if _m.field(base + _d * t) <= 0.0:
			return true
		t += TSTEP
	return false


## Правый край: идём от X1 влево шагом 2, на первом попадании уточняем.
func _edge(y: float, dir: float) -> float:
	var x := X1 if dir > 0.0 else X0
	var step := -2.0 if dir > 0.0 else 2.0
	while (x - X0) * (x - X1) <= 0.0:
		if _inside(x, y):
			var lo := x
			var hi := x - step
			for i in 14:
				var mid := (lo + hi) * 0.5
				if _inside(mid, y):
					lo = mid
				else:
					hi = mid
			return lo
		x += step
	return x


func _process(_dt: float) -> bool:
	print("\nПРОФИЛЬ")
	var y := Y0
	while y <= Y1 + 0.001:
		print("%6.1f  R=%7.2f  L=%7.2f" % [y, _edge(y, 1.0), _edge(y, -1.0)])
		y += 1.0

	# Картинка 2 мм: тень вдоль мировой z.
	var nx := int((X1 - X0) * 0.5) + 1
	var ny := int((Y1 - Y0) * 0.5) + 1
	var img := Image.create(nx, ny, false, Image.FORMAT_RGB8)
	img.fill(Color(0.98, 0.96, 0.92))
	for iy in ny:
		var yy := Y0 + float(iy) * 2.0
		for ix in nx:
			var xx := X0 + float(ix) * 2.0
			if _inside(xx, yy):
				img.set_pixel(ix, iy, Color(0.1, 0.1, 0.1))
	img.save_png("/tmp/opencode/shadow-world.png")
	print("\nPNG /tmp/opencode/shadow-world.png %dx%d" % [nx, ny])
	return true
