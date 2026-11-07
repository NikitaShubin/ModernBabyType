# Dumps the arm's normals near the seam at the angle where the turn is worst.
extends SceneTree

const ArmView := preload("res://arm_view.gd")

const REST_MESH := "res://cache/skin_curled_rest.res"


func _init() -> void:
	var src: ArrayMesh = load(REST_MESH)
	var arm := ArmView.build(src)
	var am: ArrayMesh = (arm["skin_mesh"] as MeshInstance3D).mesh
	var aa: Array = am.surface_get_arrays(0)
	var av: PackedVector3Array = aa[Mesh.ARRAY_VERTEX]
	var an: PackedVector3Array = aa[Mesh.ARRAY_NORMAL]
	var c0: Vector3 = arm["c0"]
	var ys := [-1.5, -4.02, -7.49]
	for i in av.size():
		var a := rad_to_deg(fposmod(atan2(av[i].z - c0.z, av[i].x - c0.x), TAU))
		if absf(a - 334.0) > 6.0:
			continue
		if absf(av[i].y - ys[0]) > 0.01 and absf(av[i].y - ys[1]) > 0.01 \
				and absf(av[i].y - ys[2]) > 0.01:
			continue
		print("y %7.2f a %6.1f p (%7.2f %7.2f) n (%6.3f %6.3f %6.3f) |n| %.3f" % [
			av[i].y, a, av[i].x, av[i].z, an[i].x, an[i].y, an[i].z, an[i].length()])
	quit()
