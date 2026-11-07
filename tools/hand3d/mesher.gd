# Marching tetrahedra over a regular grid: SDF in, smooth-shaded mesh out.
# The SDF is evaluated once per grid point; normals come from its gradient.
extends RefCounted

const CORNERS := [
	Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 1, 0), Vector3(0, 1, 0),
	Vector3(0, 0, 1), Vector3(1, 0, 1), Vector3(1, 1, 1), Vector3(0, 1, 1),
]

# Six tetrahedra tiling the cell around the main diagonal 0..6 (000–111).
# A set built around any other pair leaves the faces that hold neither
# endpoint uncovered — that showed up as a regular lattice of pinholes.
const TETS := [
	[0, 1, 2, 6], [0, 2, 3, 6], [0, 3, 7, 6], [0, 7, 4, 6], [0, 4, 5, 6], [0, 5, 1, 6],
]


static func build(model: Object, bmin: Vector3, bmax: Vector3, h: float) -> ArrayMesh:
	var nx := int(ceil((bmax.x - bmin.x) / h)) + 1
	var ny := int(ceil((bmax.y - bmin.y) / h)) + 1
	var nz := int(ceil((bmax.z - bmin.z) / h)) + 1
	var vals := PackedFloat32Array()
	vals.resize(nx * ny * nz)
	var p := Vector3.ZERO
	for k in nz:
		for j in ny:
			var base := nx * (j + ny * k)
			for i in nx:
				p.x = bmin.x + i * h
				p.y = bmin.y + j * h
				p.z = bmin.z + k * h
				# A node whose field lands exactly on zero makes the tetrahedra
				# disagree about whether it is inside, and the surface opens at
				# that node. A deterministic ±2 µm jitter breaks the exact hits;
				# a constant bias only moves them to the next node.
				var jitter := float((i * 73 + j * 151 + k * 227) % 5 - 2) * 0.001
				vals[base + i] = model.field(p) + jitter

	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	var vmap := {}
	var pa: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
	var va: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var eps := h * 0.35
	var cell: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO,
		Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
	var cval := PackedFloat32Array()
	cval.resize(8)

	for k in nz - 1:
		for j in ny - 1:
			for i in nx - 1:
				var idx0 := i + nx * (j + ny * k)
				var idx1 := idx0 + 1
				var idx2 := idx0 + nx
				var idx3 := idx2 + 1
				var idx4 := idx0 + nx * ny
				var idx5 := idx4 + 1
				var idx6 := idx4 + nx
				var idx7 := idx6 + 1
				cval[0] = vals[idx0]
				cval[1] = vals[idx1]
				cval[2] = vals[idx3]
				cval[3] = vals[idx2]
				cval[4] = vals[idx4]
				cval[5] = vals[idx5]
				cval[6] = vals[idx7]
				cval[7] = vals[idx6]
				# All in or all out: no surface here.
				if (cval[0] < 0.0 and cval[1] < 0.0 and cval[2] < 0.0 and cval[3] < 0.0
						and cval[4] < 0.0 and cval[5] < 0.0 and cval[6] < 0.0 and cval[7] < 0.0):
					continue
				if (cval[0] >= 0.0 and cval[1] >= 0.0 and cval[2] >= 0.0 and cval[3] >= 0.0
						and cval[4] >= 0.0 and cval[5] >= 0.0 and cval[6] >= 0.0 and cval[7] >= 0.0):
					continue
				var o := Vector3(bmin.x + i * h, bmin.y + j * h, bmin.z + k * h)
				for c in 8:
					cell[c] = o + CORNERS[c] * h
				for t in 6:
					var tet: Array = TETS[t]
					for m in 4:
						pa[m] = cell[tet[m]]
						va[m] = cval[tet[m]]
					_emit_tet(model, pa, va, verts, norms, idx, vmap, eps)

	if idx.is_empty():
		return ArrayMesh.new()
	_seal(verts, idx)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _emit_tet(model: Object, pa: Array[Vector3], va: Array[float],
		verts: PackedVector3Array, norms: PackedVector3Array, idx: PackedInt32Array,
		vmap: Dictionary, eps: float) -> void:
	var inside: Array[int] = []
	var outside: Array[int] = []
	for i in 4:
		if va[i] < 0.0:
			inside.append(i)
		else:
			outside.append(i)
	var n_in := inside.size()
	if n_in == 0 or n_in == 4:
		return

	var pts := PackedVector3Array()
	if n_in == 1:
		var a := inside[0]
		for b in outside:
			pts.append(_edge(pa[a], va[a], pa[b], va[b]))
		_tri(model, pts[0], pts[1], pts[2], pa[outside[0]], verts, norms, idx, vmap, eps)
	elif n_in == 3:
		var a := outside[0]
		for b in inside:
			pts.append(_edge(pa[a], va[a], pa[b], va[b]))
		_tri(model, pts[0], pts[1], pts[2], pa[a], verts, norms, idx, vmap, eps)
	else:
		var a := inside[0]
		var b := inside[1]
		var c := outside[0]
		var d := outside[1]
		pts.append(_edge(pa[a], va[a], pa[c], va[c]))
		pts.append(_edge(pa[a], va[a], pa[d], va[d]))
		pts.append(_edge(pa[b], va[b], pa[d], va[d]))
		pts.append(_edge(pa[b], va[b], pa[c], va[c]))
		_tri(model, pts[0], pts[1], pts[2], pa[c], verts, norms, idx, vmap, eps)
		_tri(model, pts[0], pts[2], pts[3], pa[c], verts, norms, idx, vmap, eps)


static func _edge(a: Vector3, va: float, b: Vector3, vb: float) -> Vector3:
	var den := va - vb
	if absf(den) < 0.000001:
		return (a + b) * 0.5
	return a + (b - a) * (va / den)


# Emit one triangle with its winding turned outward (away from ref, the
# vertex known to be outside the surface).
static func _tri(model: Object, p0: Vector3, p1: Vector3, p2: Vector3, ref: Vector3,
		verts: PackedVector3Array, norms: PackedVector3Array, idx: PackedInt32Array,
		vmap: Dictionary, eps: float) -> void:
	var n := (p1 - p0).cross(p2 - p0)
	if n.length_squared() < 1e-14:
		return
	var cen := (p0 + p1 + p2) / 3.0
	# Godot treats clockwise winding as the front face: the geometric cross
	# product must point INTO the surface, i.e. away from the outside vertex.
	if n.dot(ref - cen) > 0.0:
		var tmp := p1
		p1 = p2
		p2 = tmp
	idx.append(_vert(model, p0, verts, norms, vmap, eps))
	idx.append(_vert(model, p1, verts, norms, vmap, eps))
	idx.append(_vert(model, p2, verts, norms, vmap, eps))


# One vertex per position: the surface is shared between neighbouring cells,
# and a mesh of 130k loose vertices is both wasteful and awkward for the
# driver. Positions are matched to a thousandth of a millimetre.
static func _vert(model: Object, p: Vector3, verts: PackedVector3Array,
		norms: PackedVector3Array, vmap: Dictionary, eps: float) -> int:
	var key := Vector3i(roundi(p.x * 1000.0), roundi(p.y * 1000.0), roundi(p.z * 1000.0))
	if vmap.has(key):
		return vmap[key]
	var i := verts.size()
	verts.append(p)
	norms.append(_normal(model, p, eps))
	vmap[key] = i
	return i


static func _normal(model: Object, p: Vector3, e: float) -> Vector3:
	var x: float = model.field(Vector3(p.x + e, p.y, p.z)) - model.field(Vector3(p.x - e, p.y, p.z))
	var y: float = model.field(Vector3(p.x, p.y + e, p.z)) - model.field(Vector3(p.x, p.y - e, p.z))
	var z: float = model.field(Vector3(p.x, p.y, p.z + e)) - model.field(Vector3(p.x, p.y, p.z - e))
	var n := Vector3(x, y, z)
	if n.length_squared() < 1e-14:
		return Vector3.UP
	return n.normalized()


# Every closed surface uses each edge twice. Where the field grazes a grid
# node the tetrahedra can leave a one-cell hole; the holes are tiny and
# handful, so they are stitched shut instead of being chased in the field.
# A boundary edge is a directed edge whose reverse is missing: the patch has
# to run the loop backwards to keep the winding outward.
static func _seal(verts: PackedVector3Array, idx: PackedInt32Array) -> void:
	var count := {}
	var t := 0
	while t < idx.size():
		for e in [[idx[t], idx[t + 1]], [idx[t + 1], idx[t + 2]], [idx[t + 2], idx[t]]]:
			var key := Vector2i(mini(e[0], e[1]), maxi(e[0], e[1]))
			count[key] = int(count.get(key, 0)) + 1
		t += 3
	var next := {}
	var has_next := {}
	t = 0
	while t < idx.size():
		for e in [[idx[t], idx[t + 1]], [idx[t + 1], idx[t + 2]], [idx[t + 2], idx[t]]]:
			var key := Vector2i(mini(e[0], e[1]), maxi(e[0], e[1]))
			if int(count[key]) == 1:
				next[e[0]] = e[1]
				has_next[e[0]] = true
		t += 3
	if next.is_empty():
		return
	var used := {}
	for start in next:
		var s: int = start
		if used.has(s):
			continue
		var loop: Array[int] = []
		var cur := s
		while not used.has(cur) and has_next.has(cur):
			used[cur] = true
			loop.append(cur)
			cur = int(next[cur])
		if loop.size() < 3:
			continue
		# Fan the loop from its first vertex, wound opposite to its edges.
		for i in range(1, loop.size() - 1):
			idx.append(loop[0])
			idx.append(loop[i + 1])
			idx.append(loop[i])
