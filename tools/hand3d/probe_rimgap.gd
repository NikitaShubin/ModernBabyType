# How far the source SDF normals near the cut are from the contour's normal,
# and how NOISY they are along the wall (the sawtooth the zebra probe shows as
# teeth at the seam). Per 0.5 mm slice: mean/worst angle to the contour normal,
# and the mean/worst second difference between neighbours around the ring.
extends SceneTree

const ArmView := preload("res://arm_view.gd")
const Viewer := preload("res://viewer.gd")

const REST_MESH := "res://cache/skin_curled_rest.res"


func _init() -> void:
	var src: ArrayMesh = load(REST_MESH)
	var a: Array = src.surface_get_arrays(0)
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
	var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	var used := {}
	for i in idx:
		used[i] = true
	var viewer: Node = Viewer.new()
	var opened: ArrayMesh = viewer._open_wrist(src)
	viewer.free()
	var oa: Array = opened.surface_get_arrays(0)
	var ov: PackedVector3Array = oa[Mesh.ARRAY_VERTEX]
	var oidx: PackedInt32Array = oa[Mesh.ARRAY_INDEX]
	var oused := {}
	for i in oidx:
		oused[i] = true
	var c0 := Vector3.ZERO
	var n0 := 0
	for i in ov.size():
		if oused.has(i) and absf(ov[i].y - ArmView.CUT_Y) < 0.01:
			c0 += ov[i]
			n0 += 1
	c0 /= float(n0)
	var smooth := ArmView._smoothed_rim(ArmView._cut_rim(src))
	var tab := ArmView.rim_normals(smooth, c0)

	print("slice          verts   to-contour mean  p95   max   |  along-wall d2 mean  max")
	for k in 12:
		var y0 := ArmView.CUT_Y + float(k) * 0.5
		var y1 := y0 + 0.5
		var list := []
		for i in v.size():
			if not used.has(i):
				continue
			var dy := v[i].y - ArmView.CUT_Y
			if dy < float(k) * 0.5 - 0.001 or dy >= float(k + 1) * 0.5 - 0.001:
				continue
			var rn := ArmView.rim_normal_at(tab, v[i], c0)
			var ang := rad_to_deg(n[i].angle_to(rn))
			var az := fposmod(atan2(v[i].z - c0.z, v[i].x - c0.x), TAU)
			list.append([az, ang, n[i]])
		if list.is_empty():
			continue
		list.sort_custom(func(x, y): return float(x[0]) < float(y[0]))
		var angs := []
		for e in list:
			angs.append(float(e[1]))
		angs.sort()
		var m := angs.size()
		var sum := 0.0
		for e in angs:
			sum += float(e)
		# Second difference around the ring: normal[j-1], [j], [j+1].
		var d2 := []
		for j in list.size():
			var nm: Vector3 = list[(j - 1 + list.size()) % list.size()][2]
			var nc: Vector3 = list[j][2]
			var np: Vector3 = list[(j + 1) % list.size()][2]
			d2.append(rad_to_deg(nm.angle_to(nc) + nc.angle_to(np)
				- nm.angle_to(np)))
		var d2s := 0.0
		var d2m := 0.0
		for e in d2:
			d2s += absf(float(e))
			d2m = maxf(d2m, absf(float(e)))
		print("%4.1f..%4.1f  %5d   %8.2f  %6.2f  %6.2f   |  %8.3f  %6.3f"
			% [float(k) * 0.5, float(k + 1) * 0.5, m, sum / float(m),
			float(angs[int(m * 0.95)]), float(angs[m - 1]),
			d2s / float(m), d2m])
	quit()
