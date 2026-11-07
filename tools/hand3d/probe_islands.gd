# Connected components of the open hand mesh: the mesh is one big surface plus
# a few stray slivers (tiny dark dots floating over the wrist wall in
# close-*-f70-hand). Prints each component's size and bounds. Headless.
extends SceneTree

const Viewer := preload("res://viewer.gd")

const REST_MESH := "res://cache/skin_curled_rest.res"


static func _find(par: PackedInt32Array, i0: int) -> int:
	var i := i0
	var r := i
	while par[r] != r:
		r = par[r]
	while par[i] != r:
		var nx := par[i]
		par[i] = r
		i = nx
	return r


func _init() -> void:
	var src: ArrayMesh = load(REST_MESH)
	var viewer: Node = Viewer.new()
	var opened: ArrayMesh = viewer._open_wrist(src)
	viewer.free()
	var a: Array = opened.surface_get_arrays(0)
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	var par := PackedInt32Array()
	par.resize(v.size())
	for i in v.size():
		par[i] = i
	for t in range(0, idx.size(), 3):
		var a0 := _find(par, idx[t])
		var b0 := _find(par, idx[t + 1])
		var c0 := _find(par, idx[t + 2])
		par[b0] = a0
		par[c0] = a0
	var groups := {}
	for t in range(0, idx.size(), 3):
		var r := _find(par, idx[t])
		if not groups.has(r):
			groups[r] = {"tris": 0, "verts": {}, "lo": Vector3(1e9, 1e9, 1e9),
				"hi": Vector3(-1e9, -1e9, -1e9)}
		var g: Dictionary = groups[r]
		g["tris"] = int(g["tris"]) + 1
		for k in 3:
			var vi := idx[t + k]
			(g["verts"] as Dictionary)[vi] = true
			var p := v[vi]
			g["lo"] = Vector3(minf(g["lo"].x, p.x), minf(g["lo"].y, p.y), minf(g["lo"].z, p.z))
			g["hi"] = Vector3(maxf(g["hi"].x, p.x), maxf(g["hi"].y, p.y), maxf(g["hi"].z, p.z))
	var list := []
	for r in groups:
		var g: Dictionary = groups[r]
		list.append([int(g["tris"]), (g["verts"] as Dictionary).size(), g["lo"], g["hi"]])
	list.sort_custom(func(x, y): return int(x[0]) > int(y[0]))
	print("components: %d, vertices %d, triangles %d" % [list.size(), v.size(), idx.size() / 3])
	for k in mini(list.size(), 24):
		print("  #%d  %5d tris  %5d verts  lo %s  hi %s" % [k, int(list[k][0]),
			int(list[k][1]), str(list[k][2]), str(list[k][3])])
	quit()
