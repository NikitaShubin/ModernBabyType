extends SceneTree

const MESH := "res://cache/skin_curled_rest.res"

func _init() -> void:
	var mesh: ArrayMesh = load(MESH)
	if mesh == null:
		print("no mesh")
		quit()
		return
	var a := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	print("verts %d tris %d" % [verts.size(), idx.size() / 3])
	var lo := 1e9
	var hi := -1e9
	var near := 0
	for v in verts:
		if absf(v.y + 1.5) < 0.05:
			near += 1
			lo = minf(lo, v.x)
			hi = maxf(hi, v.x)
	print("near cut %d, x range %.2f .. %.2f" % [near, lo, hi])
	# Cap triangles: all three vertices at y ~ -1.5.
	var cap := {}
	var cap_count := 0
	for t in range(0, idx.size(), 3):
		var p0 := verts[idx[t]]
		var p1 := verts[idx[t + 1]]
		var p2 := verts[idx[t + 2]]
		if absf(p0.y + 1.5) < 0.01 and absf(p1.y + 1.5) < 0.01 and absf(p2.y + 1.5) < 0.01:
			cap_count += 1
			for e in [[idx[t], idx[t + 1]], [idx[t + 1], idx[t + 2]], [idx[t + 2], idx[t]]]:
				var key := Vector2i(mini(e[0], e[1]), maxi(e[0], e[1]))
				cap[key] = int(cap.get(key, 0)) + 1
	print("cap tris %d, cap edges %d" % [cap_count, cap.size()])
	# Boundary of the cap: edges with count 1 (the outer rim).
	var rim := {}
	var rim_n := 0
	for key in cap:
		if int(cap[key]) == 1:
			rim_n += 1
			rim[key] = true
	print("rim edges %d" % rim_n)
	# Order the rim into a loop.
	var adj := {}
	for key in rim:
		var a0: int = key.x
		var b0: int = key.y
		if not adj.has(a0):
			adj[a0] = []
		if not adj.has(b0):
			adj[b0] = []
		(adj[a0] as Array).append(b0)
		(adj[b0] as Array).append(a0)
	var start := -1
	for k in adj:
		if (adj[k] as Array).size() != 2:
			print("rim vertex %d has %d neighbours" % [k, (adj[k] as Array).size()])
		if start < 0:
			start = int(k)
	var loop := []
	var prev := -1
	var cur := start
	for i in 2000:
		loop.append(cur)
		var nb: Array = adj[cur]
		var nxt := -1
		for n in nb:
			if int(n) != prev:
				nxt = int(n)
				break
		if nxt < 0 or nxt == start:
			break
		prev = cur
		cur = nxt
	print("loop %d" % loop.size())
	var rmin := 1e9
	var rmax := 0.0
	var zmin := 1e9
	var zmax := -1e9
	for i in loop:
		var p := verts[i]
		rmin = minf(rmin, p.x)
		rmax = maxf(rmax, p.x)
		zmin = minf(zmin, p.z)
		zmax = maxf(zmax, p.z)
	print("loop x %.2f..%.2f z %.2f..%.2f" % [rmin, rmax, zmin, zmax])
	# Print every 10th point.
	var out := []
	for j in range(0, loop.size(), maxi(1, loop.size() / 24)):
		var p := verts[loop[j]]
		out.append("(%.1f,%.1f,%.1f)" % [p.x, p.y, p.z])
	print(", ".join(out))
	quit()
