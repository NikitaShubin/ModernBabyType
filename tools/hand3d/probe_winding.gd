# Which winding convention reproduces the source mesh's normals? Prints the
# mean dot product of each candidate against the stored normals.
extends SceneTree

const REST_MESH := "res://cache/skin_curled_rest.res"


func _init() -> void:
	var src: ArrayMesh = load(REST_MESH)
	var a: Array = src.surface_get_arrays(0)
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
	var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	var c1 := PackedVector3Array()
	var c2 := PackedVector3Array()
	c1.resize(v.size())
	c2.resize(v.size())
	for i in v.size():
		c1[i] = Vector3.ZERO
		c2[i] = Vector3.ZERO
	for t in range(0, idx.size(), 3):
		var i0 := idx[t]
		var i1 := idx[t + 1]
		var i2 := idx[t + 2]
		var n1 := (v[i1] - v[i0]).cross(v[i2] - v[i0])
		var n2 := (v[i2] - v[i0]).cross(v[i1] - v[i0])
		c1[i0] += n1
		c1[i1] += n1
		c1[i2] += n1
		c2[i0] += n2
		c2[i1] += n2
		c2[i2] += n2
	var s1 := 0.0
	var s2 := 0.0
	var m1 := 0.0
	var m2 := 0.0
	for i in v.size():
		if c1[i].length_squared() < 1e-9:
			continue
		s1 += c1[i].normalized().dot(n[i])
		s2 += c2[i].normalized().dot(n[i])
		m1 = maxf(m1, rad_to_deg(c1[i].normalized().angle_to(n[i])))
		m2 = maxf(m2, rad_to_deg(c2[i].normalized().angle_to(n[i])))
	print("(p1-p0)x(p2-p0): mean dot %.3f, worst %.1f deg" % [
		s1 / float(v.size()), m1])
	print("(p2-p0)x(p1-p0): mean dot %.3f, worst %.1f deg" % [
		s2 / float(v.size()), m2])
	quit()
