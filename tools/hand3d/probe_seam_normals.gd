# Where does the seam's shading step come from? Compares the hand's rim normals
# with the arm's first rings, and prints the normal turn per millimetre down
# the arm and up the hand. Headless:
#   mbt-godot --headless --path /work/tools/hand3d --script res://probe_seam_normals.gd
extends SceneTree

const ArmView := preload("res://arm_view.gd")
const Viewer := preload("res://viewer.gd")

const REST_MESH := "res://cache/skin_curled_rest.res"
const BUCKETS := 720


func _angle(p: Vector3, c0: Vector3) -> float:
	var a := atan2(p.z - c0.z, p.x - c0.x)
	return fposmod(a, TAU)


# Vertices of one height, indexed by angle bucket: bucket -> vertex index.
func _ring(verts: PackedVector3Array, y: float, c0: Vector3) -> Dictionary:
	var out := {}
	for i in verts.size():
		if absf(verts[i].y - y) > 0.01:
			continue
		var b := int(_angle(verts[i], c0) / TAU * float(BUCKETS)) % BUCKETS
		out[b] = i
	return out


func _nearest(ring: Dictionary, a: float) -> int:
	var b0 := int(a / TAU * float(BUCKETS)) % BUCKETS
	for d in 12:
		for s in ([1, -1] if d > 0 else [1]):
			var i: int = ring.get((b0 + s * d + BUCKETS) % BUCKETS, -1)
			if i >= 0:
				return i
	return -1


func _init() -> void:
	var src: ArrayMesh = load(REST_MESH)
	var viewer: Node = Viewer.new()
	var opened: ArrayMesh = viewer._open_wrist(src)
	viewer.free()
	var ha: Array = opened.surface_get_arrays(0)
	var hv_all: PackedVector3Array = ha[Mesh.ARRAY_VERTEX]
	var hn_all: PackedVector3Array = ha[Mesh.ARRAY_NORMAL]
	# The cap's interior vertices are still in the array (only its triangles
	# were dropped) and they sit on the cut plane too, with no faces left to
	# give them a normal. Only vertices the open surface actually uses are the
	# rim.
	var used := {}
	for i in (ha[Mesh.ARRAY_INDEX] as PackedInt32Array):
		used[i] = true
	var hv := PackedVector3Array()
	var hn := PackedVector3Array()
	for i in hv_all.size():
		if used.has(i):
			hv.append(hv_all[i])
			hn.append(hn_all[i])
	var arm := ArmView.build(src)
	var am: ArrayMesh = (arm["skin_mesh"] as MeshInstance3D).mesh
	var aa: Array = am.surface_get_arrays(0)
	var av: PackedVector3Array = aa[Mesh.ARRAY_VERTEX]
	var an: PackedVector3Array = aa[Mesh.ARRAY_NORMAL]

	var ys := {}
	for i in av.size():
		ys[snappedf(av[i].y, 0.01)] = true
	var keys := ys.keys()
	keys.sort()
	keys.reverse()
	print("arm ring heights: ", str(keys.slice(0, 8)))

	var c0 := Vector3.ZERO
	var nrim := 0
	for i in hv.size():
		if absf(hv[i].y - ArmView.CUT_Y) < 0.01:
			c0 += hv[i]
			nrim += 1
	c0 /= maxf(float(nrim), 1.0)
	var hrim := _ring(hv, ArmView.CUT_Y, c0)
	var arim := _ring(av, ArmView.CUT_Y, c0)
	print("hand rim: %d vertices, arm ring 0: %d" % [hrim.size(), arim.size()])

	var worst := 0.0
	var worst_a := 0.0
	var sum := 0.0
	for b in hrim:
		var i: int = hrim[b]
		var j := _nearest(arim, _angle(hv[i], c0))
		if j < 0:
			continue
		var ang := rad_to_deg(hn[i].angle_to(an[j]))
		sum += ang
		if ang > worst:
			worst = ang
			worst_a = rad_to_deg(_angle(hv[i], c0))
	print("seam normals: mean %.2f deg, worst %.2f deg at %.0f deg" % [
		sum / maxf(float(hrim.size()), 1.0), worst, worst_a])

	for k in mini(4, keys.size() - 1):
		var ya: float = keys[k]
		var yb: float = keys[k + 1]
		var ra := _ring(av, ya, c0)
		var rb := _ring(av, yb, c0)
		var worst_k := 0.0
		for b in ra:
			var i: int = ra[b]
			var j := _nearest(rb, _angle(av[i], c0))
			if j >= 0:
				worst_k = maxf(worst_k, rad_to_deg(an[i].angle_to(an[j])))
		print("arm ring %.2f -> %.2f (%.2f mm): worst normal turn %.2f deg" % [
			ya, yb, ya - yb, worst_k])

	for k in 6:
		var ya := ArmView.CUT_Y + float(k)
		var yb := ArmView.CUT_Y + float(k + 1)
		var ra := _ring(hv, ya, c0)
		var rb := _ring(hv, yb, c0)
		var worst_k := 0.0
		for b in ra:
			var i: int = ra[b]
			var j := _nearest(rb, _angle(hv[i], c0))
			if j >= 0:
				worst_k = maxf(worst_k, rad_to_deg(hn[i].angle_to(hn[j])))
		print("hand %.1f -> %.1f mm: %d verts, worst normal turn %.2f deg" % [
			ya, yb, ra.size(), worst_k])
	quit()
