# How big is the shading crease between two neighbouring rings of the arm,
# meridian by meridian? A step over ~3 degrees reads as a band. Prints the
# worst step per ring pair inside the bend, then the overall worst.
extends SceneTree

const ArmView := preload("res://arm_view.gd")
const ArmModel := preload("res://arm_model.gd")
const HandModel := preload("res://hand_model.gd")

const REST_MESH := "res://cache/skin_curled_rest.res"


func _init() -> void:
	var src: ArrayMesh = load(REST_MESH)
	var arm: Dictionary = ArmView.build(src)
	var pose: Dictionary = HandModel.rest_pose()
	pose["arm"]["wrist_flex"] = 70.0
	ArmView.update_live(arm, pose["arm"])
	var skel: Skeleton3D = arm["skeleton"]
	var a: Array = ((arm["skin_mesh"] as MeshInstance3D).mesh as ArrayMesh).surface_get_arrays(0)
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
	var bones: PackedInt32Array = a[Mesh.ARRAY_BONES]
	var depths: PackedFloat32Array = arm["depths"]
	var c0: Vector3 = arm["c0"]
	# posed normal and angle per ring
	var ring_n := []
	var ring_a := []
	for k in depths.size():
		ring_n.append([])
		ring_a.append([])
	for i in v.size():
		var k := bones[i * 4]
		if k >= depths.size():
			continue
		var xf := skel.get_bone_global_pose(k)
		ring_n[k].append((xf.basis * n[i]).normalized())
		ring_a[k].append(atan2(v[i].z - c0.z, v[i].x - c0.x))
	var worst := 0.0
	var wi := 0
	var wj := 0
	var wa := 0.0
	for k in depths.size() - 1:
		var ns: Array = ring_n[k]
		var na: Array = ring_a[k]
		var ms: Array = ring_n[k + 1]
		var ma: Array = ring_a[k + 1]
		var step := 0.0
		var sa := 0.0
		for i in ns.size():
			var best := 1e9
			var bj := -1
			for j in ms.size():
				var d := absf(angle_difference(na[i], ma[j]))
				if d < best:
					best = d
					bj = j
			if bj < 0:
				continue
			var ang := rad_to_deg(ns[i].angle_to(ms[bj]))
			if ang > step:
				step = ang
				sa = rad_to_deg(na[i])
		if step > worst:
			worst = step
			wi = k
			wj = k + 1
			wa = sa
		if depths[k] < 60.0:
			print("rings %2d-%2d  depth %6.2f-%6.2f  worst step %5.2f deg at a %6.1f" % [
				k, k + 1, depths[k], depths[k + 1], step, sa])
	print("WORST %5.2f deg between rings %d-%d at a %.1f (depths %.2f-%.2f)" % [
		worst, wi, wj, wa, depths[wi], depths[wj]])
	quit()
