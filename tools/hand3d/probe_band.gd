# The hand's wall normals in the first centimetre above the cut: how far each
# one is from horizontal, per millimetre slice, and the worst direction.
extends SceneTree

const ArmView := preload("res://arm_view.gd")
const Viewer := preload("res://viewer.gd")

const REST_MESH := "res://cache/skin_curled_rest.res"


func _init() -> void:
	var src: ArrayMesh = load(REST_MESH)
	var viewer: Node = Viewer.new()
	var opened: ArrayMesh = viewer._open_wrist(src)
	viewer.free()
	var ha: Array = opened.surface_get_arrays(0)
	var hv: PackedVector3Array = ha[Mesh.ARRAY_VERTEX]
	var hn: PackedVector3Array = ha[Mesh.ARRAY_NORMAL]
	var used := {}
	for i in (ha[Mesh.ARRAY_INDEX] as PackedInt32Array):
		used[i] = true
	var c0 := Vector3.ZERO
	var n := 0
	for i in hv.size():
		if used.has(i) and absf(hv[i].y - ArmView.CUT_Y) < 0.01:
			c0 += hv[i]
			n += 1
	c0 /= float(n)
	for k in 12:
		var y0 := ArmView.CUT_Y + float(k) * 0.5
		var y1 := y0 + 0.5
		var worst := 0.0
		var wa := 0.0
		var wv := -1
		var cnt := 0
		for i in hv.size():
			if not used.has(i):
				continue
			if hv[i].y < y0 - 0.001 or hv[i].y >= y1 - 0.001:
				continue
			cnt += 1
			var dev := rad_to_deg(asin(clampf(absf(hn[i].y), 0.0, 1.0)))
			if dev > worst:
				worst = dev
				wa = rad_to_deg(fposmod(atan2(hv[i].z - c0.z, hv[i].x - c0.x), TAU))
				wv = i
		print("y %6.2f..%6.2f  %4d verts  worst tilt from horizontal %5.2f deg at a %6.1f" % [
			y0 - ArmView.CUT_Y, y1 - ArmView.CUT_Y, cnt, worst, wa])
		if wv >= 0 and worst > 20.0:
			print("      n %s p %s" % [str(hn[wv]), str(hv[wv])])
	quit()
