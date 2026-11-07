# Boundary edges of the opened hand mesh. A closed skin has none: the cut is
# opened on purpose, but every other edge must belong to two triangles. A
# stray edge in the middle of the wrist wall is a crack, and a crack opens
# into a spike when the skin bends.
# Run: godot --headless --path tools/hand3d --script res://probe_hole.gd
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
	var edge := {}
	for t in range(0, idx.size(), 3):
		for k in 3:
			var p := idx[t + k]
			var q := idx[t + (k + 1) % 3]
			var key := "%d:%d" % [mini(p, q), maxi(p, q)]
			edge[key] = int(edge.get(key, 0)) + 1
	var cut := 0
	var bad := []
	for key in edge:
		if int(edge[key]) != 1:
			continue
		var parts := str(key).split(":")
		var i := int(parts[0])
		var j := int(parts[1])
		if absf(v[i].y - ArmView.CUT_Y) < 0.01 and absf(v[j].y - ArmView.CUT_Y) < 0.01:
			cut += 1
			continue
		bad.append([v[i].y, i, j])
	bad.sort_custom(func(x, y): return float(x[0]) < float(y[0]))
	print("vertices %d, boundary edges at the cut %d, elsewhere %d" % [
		v.size(), cut, bad.size()])
	for e in bad:
		var i := int(e[1])
		var j := int(e[2])
		print("  y %7.3f / %7.3f  %s  %s" % [v[i].y, v[j].y, str(v[i]), str(v[j])])
	quit()
