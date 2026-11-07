# The SOURCE mesh's normals at the rim: how much of the cap's downward normal
# is in them, and does the horizontal part point the right way?
extends SceneTree

const ArmView := preload("res://arm_view.gd")
const Viewer := preload("res://viewer.gd")

const REST_MESH := "res://cache/skin_curled_rest.res"


func _init() -> void:
	var src: ArrayMesh = load(REST_MESH)
	var a: Array = src.surface_get_arrays(0)
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
	var c0 := Vector3.ZERO
	var cnt := 0
	for i in v.size():
		if absf(v[i].y - ArmView.CUT_Y) < 0.01:
			c0 += v[i]
			cnt += 1
	c0 /= float(cnt)
	var arm := ArmView.build(src)
	var aa: Array = ((arm["skin_mesh"] as MeshInstance3D).mesh as ArrayMesh).surface_get_arrays(0)
	var av: PackedVector3Array = aa[Mesh.ARRAY_VERTEX]
	var an: PackedVector3Array = aa[Mesh.ARRAY_NORMAL]
	var worst := 0.0
	var sum := 0.0
	var nhor := 0
	var lmin := 1.0
	var lmax := 0.0
	for i in v.size():
		if absf(v[i].y - ArmView.CUT_Y) > 0.01:
			continue
		var h := Vector3(n[i].x, 0.0, n[i].z)
		lmin = minf(lmin, h.length())
		lmax = maxf(lmax, h.length())
		if h.length() < 0.05:
			continue
		nhor += 1
		var a_ang := atan2(v[i].z - c0.z, v[i].x - c0.x)
		var best := 1e9
		var bi := -1
		for j in av.size():
			if absf(av[j].y - ArmView.CUT_Y) > 0.01:
				continue
			var d := absf(angle_difference(a_ang, atan2(av[j].z - c0.z, av[j].x - c0.x)))
			if d < best:
				best = d
				bi = j
		if bi < 0:
			continue
		var ang := rad_to_deg(h.normalized().angle_to(an[bi]))
		sum += ang
		worst = maxf(worst, ang)
	print("rim source normals: %d verts, horizontal part %.3f..%.3f, %d usable" % [
		cnt, lmin, lmax, nhor])
	print("horizontal part vs arm ring 0: mean %.2f, worst %.2f deg" % [
		sum / float(maxi(nhor, 1)), worst])
	quit()
