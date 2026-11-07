# Dumps the arm loft's normals by height: the top ring and the first collar
# ring, where the dark band appears.
extends SceneTree

const ArmView := preload("res://arm_view.gd")

func _init() -> void:
	var src: ArrayMesh = load("res://cache/skin_curled_rest.res")
	var rim := ArmView._cut_rim(src)
	var mesh: ArrayMesh = ArmView._loft(rim)
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var c0 := Vector3.ZERO
	for p in rim:
		c0 += p
	c0 /= float(rim.size())
	for y in [-1.5, -4.0186, -7.5, -11.0]:
		var cnt := 0
		var dot_min := 1.0
		var dot_sum := 0.0
		var ny_min := 1.0
		var ny_sum := 0.0
		var samples := []
		for i in verts.size():
			if absf(verts[i].y - float(y)) > 0.02:
				continue
			var r := Vector3(verts[i].x - c0.x, 0.0, verts[i].z - c0.z)
			if r.length_squared() < 0.0001:
				continue
			var d := norms[i].dot(r.normalized())
			cnt += 1
			dot_min = minf(dot_min, d)
			dot_sum += d
			ny_min = minf(ny_min, norms[i].y)
			ny_sum += norms[i].y
			if samples.size() < 4:
				samples.append("n %s dot %+.2f" % [str(norms[i]), d])
		print("y %.3f: %d verts | radial dot mean %+.2f min %+.2f | ny mean %+.2f min %+.2f | %s" % [
			float(y), cnt, dot_sum / maxf(float(cnt), 1.0), dot_min,
			ny_sum / maxf(float(cnt), 1.0), ny_min, " ; ".join(samples)])
	quit()
