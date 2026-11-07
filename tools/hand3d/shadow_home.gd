# ЧЕСТНАЯ ТЕНЬ КИСТИ В ПОЗЕ ПОКОЯ ИГРЫ (автор 05.11.2026: «шишах» со
# стороны большого пальца). shadow_probe.gd меряет scaled_pose(1, 0) —
# позу исследования, а игра стоит в СВОЁМ решённом покое (HomePose.build:
# подушечки на дом-клавишах), и большой у него повёрнут иначе. Здесь та же
# тень, но для HOME из game/scripts/hands_poses.gd.
#
# Запуск (headless):
#   docker run --rm ... mbt-godot --headless --path /work/tools/hand3d \
#     --script res://shadow_home.gd
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")
const Sdf := preload("res://sdf.gd")

const X0 := -62.0
const X1 := 66.0
const Y0 := -10.0
const Y1 := 70.0
const Z0 := -30.0
const Z1 := 26.0
const ZSTEP := 2.0

const HOME := [-20.0000, -10.0000, 0.0000, 0.0000, 34.0000, -83.8789,
	45.6444, -49.0000, 38.0315, 33.9876, 14.0965, -12.2396, 27.5328,
	55.4005, 28.8211, -7.2805, 23.6516, 63.6973, 34.8851, -2.9139,
	33.9503, 42.4299, 19.5347, 0.5225, 4.1371, -9.0000, -10.0000,
	21.3197, 0.7834]

var _m = null


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
	_m = HandModel.new(1.0, 0.0, _pose_from_flat(HOME))


func _min_z(f: Callable, x: float, y: float) -> float:
	var best := 1.0e9
	var z := Z0
	while z <= Z1:
		best = minf(best, float(f.call(Vector3(x, y, z))))
		z += ZSTEP
	return best


func _field_of(p: Vector3) -> float:
	return _m.field(p)


func _right_edge(f: Callable, y: float) -> float:
	var x := X1
	while x >= X0:
		if _min_z(f, x, y) <= 0.0:
			var lo := x
			var hi := x + 2.0
			for i in 14:
				var mid := (lo + hi) * 0.5
				if _min_z(f, mid, y) <= 0.0:
					lo = mid
				else:
					hi = mid
			return lo
		x -= 2.0
	return X0


func _process(_dt: float) -> bool:
	var nx := int(X1 - X0) + 1
	var ny := int(Y1 - Y0) + 1
	var sc := 4
	var img := Image.create(nx * sc, ny * sc, false, Image.FORMAT_RGB8)
	img.fill(Color(0.98, 0.96, 0.92))
	for iy in ny:
		var y := Y0 + float(iy)
		for ix in nx:
			var x := X0 + float(ix)
			if _min_z(Callable(self, "_field_of"), x, y) <= 0.0:
				for dy in sc:
					for dx in sc:
						img.set_pixel(ix * sc + dx, iy * sc + dy,
							Color(0.1, 0.1, 0.1))
	img.save_png("/tmp/opencode/shadow-home.png")
	print("PNG /tmp/opencode/shadow-home.png %dx%d" % [nx, ny])

	print("\nПРОФИЛЬ")
	var y := Y0
	while y <= Y1:
		var x := _right_edge(Callable(self, "_field_of"), y)
		print("%6.1f  x=%6.2f" % [y, x])
		y += 1.0

	print("\nПРИМИТИВЫ")
	for y2 in [0.0, 4.0, 8.0, 12.0, 16.0, 20.0, 24.0, 28.0, 32.0, 36.0,
			40.0, 44.0, 48.0, 52.0, 56.0, 60.0]:
		print("y=%6.1f  " % y2, _edges_all(y2))
	return true


func _edges_all(y: float) -> String:
	var m = _m
	var prims := {}
	prims["wrist"] = func(p: Vector3) -> float:
		return Sdf.capsule_scaled(p, HandModel.WRIST_A, HandModel.WRIST_B,
			27.0, 27.5, Vector3(1, 1, 0.72))
	prims["carpus"] = func(p: Vector3) -> float:
		return Sdf.ellipsoid(p, HandModel.CARPUS_C, HandModel.CARPUS_R)
	prims["dorsal"] = func(p: Vector3) -> float:
		return Sdf.ellipsoid(p, Vector3(33, 56, 4), Vector3(12, 18, 11))
	prims["thenar"] = func(p: Vector3) -> float:
		return Sdf.ellipsoid_oriented(p, m._thenar_c, HandModel.THENAR_R,
			m._thenar_ax[0], m._thenar_ax[1], m._thenar_ax[2])
	prims["hypoth"] = func(p: Vector3) -> float:
		return Sdf.ellipsoid(p, HandModel.HYPOTH_C, HandModel.HYPOTH_R)
	prims["thumb_mc"] = func(p: Vector3) -> float:
		return Sdf.cone(p, m._thumb_pts[0], m._thumb_pts[1],
			m._thumb_r[0], m._thumb_r[1])
	prims["thumb_p"] = func(p: Vector3) -> float:
		return Sdf.cone(p, m._thumb_pts[1], m._thumb_pts[2],
			m._thumb_r[1], m._thumb_r[2])
	prims["palm"] = func(p: Vector3) -> float:
		var d := 1.0e9
		for c in m._palm_cones:
			d = minf(d, Sdf.capsule_scaled(p, c[0], c[1], c[2], c[3],
				Vector3(1, 1, 1.12)))
		return d
	var out := []
	for k in prims.keys():
		out.append("%s=%6.1f" % [k, _right_edge(prims[k], y)])
	return " ".join(out)
