# The final (open-mesh) normals row by row up the wrist wall, sorted by
# azimuth: the step to the next neighbour and the second difference. This is
# what the zebra shows as a staircase — a plateau-and-step pattern would be
# piecewise-constant normals. Headless.
extends SceneTree

const ArmView := preload("res://arm_view.gd")
const Viewer := preload("res://viewer.gd")

const REST_MESH := "res://cache/skin_curled_rest.res"


func _init() -> void:
	var src: ArrayMesh = load(REST_MESH)
	var viewer: Node = Viewer.new()
	var opened: ArrayMesh = viewer._open_wrist(src)
	viewer.free()
	var a: Array = opened.surface_get_arrays(0)
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
	var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	var used := {}
	for i in idx:
		used[i] = true
	var c0 := Vector3.ZERO
	var n0 := 0
	for i in v.size():
		if used.has(i) and absf(v[i].y - ArmView.CUT_Y) < 0.01:
			c0 += v[i]
			n0 += 1
	c0 /= float(n0)
	print("rim vertices %d, centre %s" % [n0, str(c0)])
	for k in 8:
		var dy0 := float(k) * 0.5
		var list := []
		for i in v.size():
			if not used.has(i):
				continue
			var dy := v[i].y - ArmView.CUT_Y
			if dy < dy0 - 0.001 or dy >= dy0 + 0.5 - 0.001:
				continue
			list.append([fposmod(atan2(v[i].z - c0.z, v[i].x - c0.x), TAU), n[i]])
		if list.size() < 4:
			continue
		list.sort_custom(func(x, y): return float(x[0]) < float(y[0]))
		var m := list.size()
		var st := 0.0
		var d2 := 0.0
		var d2m := 0.0
		for j in m:
			var nm: Vector3 = list[(j - 1 + m) % m][1]
			var nc: Vector3 = list[j][1]
			var np: Vector3 = list[(j + 1) % m][1]
			st = maxf(st, rad_to_deg(nc.angle_to(np)))
			var e := rad_to_deg(nm.angle_to(nc) + nc.angle_to(np) - nm.angle_to(np))
			d2 += absf(e)
			d2m = maxf(d2m, absf(e))
		print("dy %4.1f..%4.1f  %4d verts  step max %6.2f  d2 mean %5.3f  max %6.3f"
			% [dy0, dy0 + 0.5, m, st, d2 / float(m), d2m])
	# One row in full: the wall at 0.5..1.0, first 24 entries of a window.
	var dy0 := 0.5
	var list := []
	for i in v.size():
		if not used.has(i):
			continue
		var dy := v[i].y - ArmView.CUT_Y
		if dy < dy0 - 0.001 or dy >= dy0 + 0.5 - 0.001:
			continue
		list.append([fposmod(atan2(v[i].z - c0.z, v[i].x - c0.x), TAU), n[i], v[i]])
	list.sort_custom(func(x, y): return float(x[0]) < float(y[0]))
	print("row 0.5..1.0, entries 0..23:")
	for j in mini(list.size(), 24):
		print("  a %7.2f deg  n %s" % [rad_to_deg(float(list[j][0])), str(list[j][1])])
	quit()
