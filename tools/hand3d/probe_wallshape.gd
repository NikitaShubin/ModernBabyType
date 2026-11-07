# How much fuller than the cut rim is the hand's own wall, by height above the
# cut? For every vertex in a 1 mm slice, its radius is compared with the
# smoothed rim's radius at the same azimuth. This is exactly what the flatten
# pass erases; the number says how many millimetres of overhang the wall has to
# recover over the flatten height. Headless.
extends SceneTree

const ArmView := preload("res://arm_view.gd")

const REST_MESH := "res://cache/skin_curled_rest.res"


func _init() -> void:
	var src: ArrayMesh = load(REST_MESH)
	var a: Array = src.surface_get_arrays(0)
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	var used := {}
	for i in idx:
		used[i] = true
	var smooth := ArmView._smoothed_rim(ArmView._cut_rim(src))
	var c0 := Vector3.ZERO
	for p in smooth:
		c0 += p
	c0 /= float(smooth.size())
	var tab := []
	for p in smooth:
		tab.append([fposmod(atan2(p.z - c0.z, p.x - c0.x), TAU),
			Vector2(p.x - c0.x, p.z - c0.z).length()])
	tab.sort_custom(func(x, y): return float(x[0]) < float(y[0]))
	print("dy band       verts   dr mean   dr p95   dr max   (mm over the rim)")
	for k in 20:
		var y0 := float(k)
		var y1 := float(k + 1)
		var list := []
		for i in v.size():
			if not used.has(i):
				continue
			var dy := v[i].y - ArmView.CUT_Y
			if dy < y0 - 0.001 or dy >= y1 - 0.001:
				continue
			var r := Vector2(v[i].x - c0.x, v[i].z - c0.z).length()
			var rr := _rim_r(tab, fposmod(atan2(v[i].z - c0.z, v[i].x - c0.x), TAU))
			list.append(r - rr)
		if list.is_empty():
			continue
		list.sort()
		var m := list.size()
		var sum := 0.0
		for e in list:
			sum += float(e)
		print("%4.0f..%4.0f  %6d  %7.2f  %7.2f  %7.2f"
			% [y0, y1, m, sum / float(m), float(list[int(m * 0.95)]), float(list[m - 1])])
	quit()


func _rim_r(tab: Array, a: float) -> float:
	var n := tab.size()
	var i0 := 0
	for i in n:
		if float(tab[i][0]) <= a:
			i0 = i
		else:
			break
	var i1 := (i0 + 1) % n
	var a0: float = tab[i0][0]
	var a1: float = tab[i1][0]
	if i1 == 0:
		a1 += TAU
	if a < a0:
		a += TAU
	var t := 0.0
	if a1 > a0:
		t = clampf((a - a0) / (a1 - a0), 0.0, 1.0)
	return lerpf(float(tab[i0][1]), float(tab[i1][1]), t)
