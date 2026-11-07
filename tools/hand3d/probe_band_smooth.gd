# Does the wrist band deform smoothly? For every vertex near the wrist, the
# distance from it to the centroid of its neighbours (a discrete Laplacian) is
# measured in the rest pose and at 70 degrees of flexion. A band whose weights
# are laid out smoothly deforms by an almost rigid map, so the Laplacian grows
# only with the bend's curvature; a band with noisy weights adds a ripple of
# its own, and the growth is local and jagged. Headless.
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const SkinRig := preload("res://skin_rig.gd")
const Viewer := preload("res://viewer.gd")
const ArmView := preload("res://arm_view.gd")

const REST_MESH := "res://cache/skin_curled_rest.res"


func _init() -> void:
	var rest := HandModel.new(1.0, 0.0)
	var src: ArrayMesh = load(REST_MESH)
	var viewer: Node = Viewer.new()
	var opened: ArrayMesh = viewer._open_wrist(src)
	viewer.free()
	var rig := SkinRig.build(rest, opened, REST_MESH, Viewer.WRIST_FLAT_H)
	var a: Array = opened.surface_get_arrays(0)
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	var nbr := {}
	for i in v.size():
		nbr[i] = {}
	for t in range(0, idx.size(), 3):
		for k in 3:
			var p := idx[t + k]
			var q := idx[t + (k + 1) % 3]
			(nbr[p] as Dictionary)[q] = true
			(nbr[q] as Dictionary)[p] = true
	var pose := HandModel.rest_pose()
	pose["arm"]["wrist_flex"] = 70.0
	var model := HandModel.new(1.0, 0.0, pose)
	var flex := SkinRig.cpu_positions(rig, model)
	var y0 := ArmView.CUT_Y
	for band in [[0.0, 5.0], [5.0, 10.0], [10.0, 20.0], [20.0, 30.0], [30.0, 45.0]]:
		var worst_r := 0.0
		var worst_f := 0.0
		var sum_r := 0.0
		var sum_f := 0.0
		var cnt := 0
		var worst_i := -1
		for i in v.size():
			var dy := v[i].y - y0
			if dy < float(band[0]) or dy >= float(band[1]):
				continue
			var ns: Dictionary = nbr[i]
			if ns.size() < 3:
				continue
			var c_r := Vector3.ZERO
			var c_f := Vector3.ZERO
			for j in ns:
				c_r += v[j]
				c_f += flex[j]
			c_r /= float(ns.size())
			c_f /= float(ns.size())
			var dr := v[i].distance_to(c_r)
			var df := flex[i].distance_to(c_f)
			sum_r += dr
			sum_f += df
			cnt += 1
			if df > worst_f:
				worst_f = df
				worst_i = i
			worst_r = maxf(worst_r, dr)
		if cnt == 0:
			continue
		print("y %5.1f..%5.1f  %5d verts  laplacian mean rest %.4f flex %.4f  max rest %.4f flex %.4f"
			% [float(band[0]), float(band[1]), cnt, sum_r / float(cnt), sum_f / float(cnt),
			worst_r, worst_f])
		if worst_i >= 0:
			print("    worst at %s (dy %.2f)" % [str(flex[worst_i]), flex[worst_i].y - y0])
	quit()
