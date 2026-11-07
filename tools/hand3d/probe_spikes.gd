# Stray geometry near the cut: vertices with fewer than three neighbours, and
# vertices far from every neighbour (a spike). The dots floating just outside
# the wrist in close-*-f70-hand are a few of those. Headless.
extends SceneTree

const Viewer := preload("res://viewer.gd")
const ArmView := preload("res://arm_view.gd")

const REST_MESH := "res://cache/skin_curled_rest.res"


func _init() -> void:
	var src: ArrayMesh = load(REST_MESH)
	var viewer: Node = Viewer.new()
	var opened: ArrayMesh = viewer._open_wrist(src)
	viewer.free()
	var a: Array = opened.surface_get_arrays(0)
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	var nbr := {}
	var used := {}
	for i in v.size():
		nbr[i] = {}
	for t in range(0, idx.size(), 3):
		for k in 3:
			var p := idx[t + k]
			var q := idx[t + (k + 1) % 3]
			(nbr[p] as Dictionary)[q] = true
			(nbr[q] as Dictionary)[p] = true
			used[p] = true
	var y0 := ArmView.CUT_Y
	var low := []
	var far := []
	for i in used:
		var ns: Dictionary = nbr[i]
		if ns.size() < 3:
			low.append([ns.size(), v[i].y - y0, i])
		var best := 0.0
		for j in ns:
			best = maxf(best, v[i].distance_to(v[j]))
		if best > 3.0:
			far.append([best, v[i].y - y0, i, ns.size()])
	low.sort_custom(func(x, y): return int(x[0]) < int(y[0]))
	far.sort_custom(func(x, y): return float(x[0]) > float(y[0]))
	print("vertices %d, used %d" % [v.size(), used.size()])
	print("neighbours < 3: %d" % low.size())
	var by_n := {}
	for e in low:
		by_n[int(e[0])] = int(by_n.get(int(e[0]), 0)) + 1
	print("  counts by n: %s" % str(by_n))
	for k in mini(low.size(), 12):
		print("  n=%d dy %7.3f  v %s" % [int(low[k][0]), float(low[k][1]),
			str(v[int(low[k][2])])])
	print("longest edge to a neighbour > 3 mm: %d" % far.size())
	for k in mini(far.size(), 14):
		print("  %.2f mm  dy %7.3f  n %d  v %s" % [float(far[k][0]), float(far[k][1]),
			int(far[k][3]), str(v[int(far[k][2])])])
	quit()
