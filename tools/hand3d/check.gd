# Numeric check of the baked skin mesh: normals, winding, NaNs.
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const Mesher := preload("res://mesher.gd")


func _initialize() -> void:
	var model := HandModel.new(1.0)
	var t0 := Time.get_ticks_msec()
	var mesh := Mesher.build(model, model.bounds_min(), model.bounds_max(), 3.0)
	print("bake %d ms" % (Time.get_ticks_msec() - t0))
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	print("verts %d idx %d" % [verts.size(), idx.size()])

	var bad_n := 0
	var short_n := 0
	for n in norms:
		if is_nan(n.x) or is_nan(n.y) or is_nan(n.z):
			bad_n += 1
		elif absf(n.length() - 1.0) > 0.01:
			short_n += 1
	print("nan normals %d, non-unit normals %d" % [bad_n, short_n])

	var flip := 0
	var good := 0
	var degenerate := 0
	var sdf_bad := 0
	var t := 0
	while t < idx.size():
		var p0 := verts[idx[t]]
		var p1 := verts[idx[t + 1]]
		var p2 := verts[idx[t + 2]]
		var n := (p1 - p0).cross(p2 - p0)
		if n.length_squared() < 1e-9:
			degenerate += 1
		else:
			var cen := (p0 + p1 + p2) / 3.0
			var gx: float = model.field(cen + Vector3(0.3, 0, 0)) - model.field(cen - Vector3(0.3, 0, 0))
			var gy: float = model.field(cen + Vector3(0, 0.3, 0)) - model.field(cen - Vector3(0, 0.3, 0))
			var gz: float = model.field(cen + Vector3(0, 0, 0.3)) - model.field(cen - Vector3(0, 0, 0.3))
			var g := Vector3(gx, gy, gz)
			if g.length_squared() < 1e-9:
				sdf_bad += 1
			elif n.dot(g) > 0.0:
				flip += 1
			else:
				good += 1
		t += 3
	print("tris %d: outward-cross %d, inward-cross %d, degenerate %d, no-grad %d"
		% [idx.size() / 3, flip, good, degenerate, sdf_bad])

	# Manifoldness: every edge of a closed surface belongs to exactly two
	# triangles. A hole in a render is a boundary edge, and a boundary edge
	# can be named: this is how the fingertip hole was found.
	var edges := {}
	var t2 := 0
	while t2 < idx.size():
		for e in [[idx[t2], idx[t2 + 1]], [idx[t2 + 1], idx[t2 + 2]], [idx[t2 + 2], idx[t2]]]:
			var key := Vector2i(mini(e[0], e[1]), maxi(e[0], e[1]))
			edges[key] = int(edges.get(key, 0)) + 1
		t2 += 3
	var boundary := 0
	var where := PackedVector3Array()
	for key in edges:
		if int(edges[key]) == 1:
			boundary += 1
			if where.size() < 12:
				where.append((verts[key.x] + verts[key.y]) * 0.5)
	var nonmanifold := 0
	for key in edges:
		if int(edges[key]) > 2:
			nonmanifold += 1
	print("boundary edges %d, non-manifold edges %d" % [boundary, nonmanifold])
	for w in where:
		print("  open at ", w)

	print("field(0,0,0) = ", model.field(Vector3.ZERO))
	print("field at tip = ", model.field(model.joints["III_TIP"]))
	quit()
