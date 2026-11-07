# The wall triangles that touch the hand's rim vertex near a given angle:
# their other vertices, so a horizontal shelf at the seam can be seen.
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
	var idx: PackedInt32Array = ha[Mesh.ARRAY_INDEX]
	var c0 := Vector3.ZERO
	var n := 0
	for i in hv.size():
		if absf(hv[i].y - ArmView.CUT_Y) < 0.01:
			c0 += hv[i]
			n += 1
	c0 /= float(n)
	var want := deg_to_rad(3.87)
	var vi := -1
	var best := 1e9
	for i in hv.size():
		if absf(hv[i].y - ArmView.CUT_Y) > 0.01:
			continue
		var a := atan2(hv[i].z - c0.z, hv[i].x - c0.x)
		var d := absf(angle_difference(want, a))
		if d < best:
			best = d
			vi = i
	print("rim vertex %d at %s n %s" % [vi, str(hv[vi]), str(hn[vi])])
	var seen := {}
	for t in range(0, idx.size(), 3):
		var tri := [idx[t], idx[t + 1], idx[t + 2]]
		if not tri.has(vi):
			continue
		for j in tri:
			if j == vi or seen.has(j):
				continue
			seen[j] = true
			print("  other %5d p (%7.3f %7.3f %7.3f) r %6.3f n (%6.3f %6.3f %6.3f)" % [
				j, hv[j].x, hv[j].y, hv[j].z,
				Vector2(hv[j].x - c0.x, hv[j].z - c0.z).length(),
				hn[j].x, hn[j].y, hn[j].z])
	quit()
