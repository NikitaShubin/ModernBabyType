extends SceneTree
const ArmView := preload("res://arm_view.gd")
const HandModel := preload("res://hand_model.gd")
func _init() -> void:
	var arm: Dictionary = ArmView.build(load("res://cache/skin_curled_rest.res"))
	var a: Array = ((arm["skin_mesh"] as MeshInstance3D).mesh as ArrayMesh).surface_get_arrays(0)
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
	var nr: int = (arm["rim"] as PackedVector3Array).size()
	for k in [0, 1, 2, 3, 10, 12]:
		for j in [0, 1, 75]:
			var vi: int = k * nr + j
			print("k %2d j %3d vi %5d  p (%7.3f %8.3f %7.3f)  n (%6.3f %6.3f %6.3f)" % [
				k, j, vi, v[vi].x, v[vi].y, v[vi].z, n[vi].x, n[vi].y, n[vi].z])
	print("rim0 %s  rim1 %s" % [str((arm["rim"] as PackedVector3Array)[0]), str((arm["rim"] as PackedVector3Array)[1])])
	quit()
