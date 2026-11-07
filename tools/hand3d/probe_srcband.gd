# The SOURCE mesh's normals (the SDF gradient) above the cut, slice by slice:
# how far each leans from horizontal, and whether it is smooth along the wall.
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
	var on: PackedVector3Array = oa[Mesh.ARRAY_NORMAL]
	# How far the open normals differ from the source ones, per slice.
	for k in 10:
		var y0 := ArmView.CUT_Y + float(k) * 0.5
		var y1 := y0 + 0.5
		var worst := 0.0
		var sum := 0.0
		var cnt := 0
		var flat := 0.0
		for i in v.size():
			if not used.has(i):
				continue
			if v[i].y < y0 - 0.001 or v[i].y >= y1 - 0.001:
				continue
			cnt += 1
			flat = maxf(flat, rad_to_deg(asin(clampf(absf(n[i].y), 0.0, 1.0))))
			# the open mesh kept the same vertex indices; positions moved a bit
			var ang := rad_to_deg(n[i].angle_to(on[i]))
			sum += ang
			worst = maxf(worst, ang)
		print("y %5.2f..%5.2f  %4d verts  source tilt %5.2f  src-vs-open mean %5.2f worst %5.2f" % [
			y0 - ArmView.CUT_Y, y1 - ArmView.CUT_Y, cnt, flat,
			sum / float(maxi(cnt, 1)), worst])
	quit()
