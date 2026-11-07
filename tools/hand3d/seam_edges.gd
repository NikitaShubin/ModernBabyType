# Edge-level comparison of the two skins at the wrist seam: the open hand's
# boundary loop against the arm's ring 0. The seam's pixels are background
# leaking through sub-pixel cracks, so the two loops must be ONE loop — same
# count, same order, same points. Headless:
#   mbt-godot --headless --path /work/tools/hand3d --script res://seam_edges.gd
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const ArmView := preload("res://arm_view.gd")
const Viewer := preload("res://viewer.gd")

const REST_MESH := "res://cache/skin_curled_rest.res"


func _init() -> void:
	var rest := HandModel.new(1.0, 0.0)
	var src: ArrayMesh = load(REST_MESH)
	var viewer: Node = Viewer.new()
	var opened: ArrayMesh = viewer._open_wrist(src)
	viewer.free()
	var arrays: Array = opened.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]

	# Boundary edges of the open hand: used by exactly one triangle.
	var use := {}
	for t in range(0, idx.size(), 3):
		for e in 3:
			var a := idx[t + e]
			var b := idx[t + (e + 1) % 3]
			var key := Vector2i(mini(a, b), maxi(a, b))
			use[key] = int(use.get(key, 0)) + 1
	var adj := {}
	for key in use:
		if int(use[key]) != 1:
			continue
		var a: int = key.x
		var b: int = key.y
		if not adj.has(a):
			adj[a] = []
		if not adj.has(b):
			adj[b] = []
		(adj[a] as Array).append(b)
		(adj[b] as Array).append(a)
	var start := -1
	for k in adj:
		if (adj[k] as Array).size() == 2:
			start = int(k)
			break
	var loop := []
	var prev := -1
	var cur := start
	for i in 4000:
		loop.append(cur)
		var nxt := -1
		for n in adj[cur]:
			if int(n) != prev:
				nxt = int(n)
				break
		if nxt < 0 or nxt == start:
			break
		prev = cur
		cur = nxt
	print("hand boundary: %d edges, %d vertices" % [adj.size() / 2, loop.size()])

	var arm := ArmView.build(src, rest)
	var rim: PackedVector3Array = arm["rim"]
	print("arm ring 0: %d vertices" % rim.size())

	# Is the boundary loop on the cut plane at all?
	var off_plane := 0
	for i in loop:
		if absf(verts[i].y - ArmView.CUT_Y) > 0.01:
			off_plane += 1
	print("boundary off the cut plane: %d" % off_plane)

	# One-to-one in loop order vs ring order: the ring is the SDF rim of the
	# cap's loop, and the open hand's loop walks the same edges.
	var n := mini(loop.size(), rim.size())
	var dmax := 0.0
	var dmax_at := -1
	for i in n:
		var d := verts[loop[i]].distance_to(rim[i])
		if d > dmax:
			dmax = d
			dmax_at = i
	print("same order: max %.6f mm at %d" % [dmax, dmax_at])
	# Nearest partner of each boundary vertex, to catch a rotation/reversal.
	var worst_nn := 0.0
	var worst_at := -1
	var shift_hist := {}
	for i in loop.size():
		var best := 1e9
		var bj := -1
		for j in rim.size():
			var d := Vector2(verts[loop[i]].x - rim[j].x,
				verts[loop[i]].z - rim[j].z).length()
			if d < best:
				best = d
				bj = j
		if best > worst_nn:
			worst_nn = best
			worst_at = i
		var sh := bj - i
		shift_hist[sh] = int(shift_hist.get(sh, 0)) + 1
	print("nearest: worst %.6f mm at %d, shifts %s" % [worst_nn, worst_at,
		str(shift_hist)])

	# The loop's own point spacing: a T-junction shows as one edge spanning two
	# of the other loop's points.
	var hand_step := PackedFloat32Array()
	for i in loop.size():
		var a := verts[loop[i]]
		var b := verts[loop[(i + 1) % loop.size()]]
		hand_step.append(Vector2(a.x - b.x, a.z - b.z).length())
	var arm_step := PackedFloat32Array()
	for j in rim.size():
		var a := rim[j]
		var b := rim[(j + 1) % rim.size()]
		arm_step.append(Vector2(a.x - b.x, a.z - b.z).length())
	print("hand step: min %.4f max %.4f mean %.4f" % [_min(hand_step),
		_max(hand_step), _mean(hand_step)])
	print("arm  step: min %.4f max %.4f mean %.4f" % [_min(arm_step),
		_max(arm_step), _mean(arm_step)])
	# Any ring point that sits in the MIDDLE of a hand edge?
	var t_junctions := 0
	for j in rim.size():
		var p := Vector2(rim[j].x, rim[j].z)
		for i in loop.size():
			var a := Vector2(verts[loop[i]].x, verts[loop[i]].z)
			var b := Vector2(verts[loop[(i + 1) % loop.size()]].x,
				verts[loop[(i + 1) % loop.size()]].z)
			var ab := b - a
			var l2 := ab.length_squared()
			if l2 < 1e-9:
				continue
			var t := clampf((p - a).dot(ab) / l2, 0.0, 1.0)
			var d := (a + ab * t).distance_to(p)
			if d < 0.02 and t > 0.05 and t < 0.95:
				t_junctions += 1
				break
	print("ring points in the middle of a hand edge: %d" % t_junctions)

	# Where the loops do NOT coincide, print the worst few by index.
	var worst := []
	for i in loop.size():
		var d := verts[loop[i]].distance_to(rim[i])
		worst.append([d, i, verts[loop[i]], rim[i]])
	worst.sort_custom(func(x, y): return float(x[0]) > float(y[0]))
	for k in 6:
		print("  d=%.6f i=%d hand=%s arm=%s" % [float(worst[k][0]),
			int(worst[k][1]), str(worst[k][2]), str(worst[k][3])])
	quit(0)


func _mean(a: PackedFloat32Array) -> float:
	var s := 0.0
	for v in a:
		s += v
	return s / maxf(float(a.size()), 1.0)


func _min(a: PackedFloat32Array) -> float:
	var m := 1e9
	for v in a:
		m = minf(m, v)
	return m


func _max(a: PackedFloat32Array) -> float:
	var m := -1e9
	for v in a:
		m = maxf(m, v)
	return m
