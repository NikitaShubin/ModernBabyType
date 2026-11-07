# Does the hand mesh duplicate the cut-rim vertices (cap and wall separately)?
# If it does, dropping the cap leaves clean outward normals at the rim.
extends SceneTree

const ArmView := preload("res://arm_view.gd")

func _init() -> void:
	var mesh: ArrayMesh = load("res://cache/skin_curled_rest.res")
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var rim := ArmView._cut_rim(mesh)
	var dup := 0
	var shared := 0
	var sample := ""
	for ri in [0, 30, 60, 90, 120]:
		var p: Vector3 = rim[ri]
		var hits := []
		for i in verts.size():
			if verts[i].distance_to(p) < 0.01:
				hits.append(i)
		if hits.size() > 1:
			dup += 1
		else:
			shared += 1
		if sample == "":
			sample = "rim %d at %s: %d verts" % [ri, str(p), hits.size()]
			for i in hits:
				sample += " | n %s" % str(norms[i])
	print(sample)
	print("sampled rim points: %d duplicated, %d single" % [dup, shared])
	# Count cap triangles and their vertex indices' normals.
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var cap_tris := 0
	for t in range(0, idx.size(), 3):
		var i0 := idx[t]
		var i1 := idx[t + 1]
		var i2 := idx[t + 2]
		if absf(verts[i0].y + 1.5) < 0.01 and absf(verts[i1].y + 1.5) < 0.01 \
				and absf(verts[i2].y + 1.5) < 0.01:
			cap_tris += 1
	print("cap triangles: %d of %d" % [cap_tris, idx.size() / 3])
	quit()
