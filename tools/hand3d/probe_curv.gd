# Where does the surface actually crease? Estimates the curvature at every
# vertex from the Laplacian along the normal (k = 2 * (mean_nb - p) . n / d^2)
# in the rest pose and at 70 degrees of flexion, and reports the worst places
# by height above the cut. A crease is a vertex where the curvature is many
# times the tube's (1 / radius ~ 0.04 per mm). Headless.
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
	var n: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
	var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	var nbr := {}
	var used := {}
	for i in v.size():
		nbr[i] = {}
	for t in range(0, idx.size(), 3):
		for k in 3:
			var p := idx[t + k]
			var q := idx[t + (k + 1) % 3]
			(nbr[p] as Dictionary)[q] = true
			(nbr[q] as Dictionary)[p] = true
			used[p] = true

	for flex in [0.0, 35.0, 70.0]:
		var pose: Dictionary = HandModel.rest_pose()
		pose["arm"]["wrist_flex"] = flex
		var model := HandModel.new(1.0, 0.0, pose)
		var p: PackedVector3Array = SkinRig.cpu_positions(rig, model)
		var bands := {}
		var top := []
		for i in used:
			var ns: Dictionary = nbr[i]
			if ns.size() < 3:
				continue
			var c := Vector3.ZERO
			var d := 0.0
			for j in ns:
				c += p[j]
				d += p[i].distance_to(p[j])
			c /= float(ns.size())
			d /= float(ns.size())
			if d < 0.001:
				continue
			var lap := c - p[i]
			# The deformed normal: the rest normal carried by the local frame is
			# not available, so use the direction of the Laplacian's own normal
			# component (its magnitude is what we want anyway, with a sign from
			# the rest normal's normalised image).
			var k := 2.0 * lap.length() / (d * d)
			var dy := p[i].y - ArmView.CUT_Y
			var b := "all"
			if dy >= 0.0 and dy < 10.0:
				b = "dy 0..10"
			elif dy >= 10.0 and dy < 25.0:
				b = "dy 10..25"
			elif dy >= 25.0 and dy < 45.0:
				b = "dy 25..45"
			if not bands.has(b):
				bands[b] = []
			(bands[b] as Array).append(k)
			top.append([k, i, dy])
		top.sort_custom(func(x, y): return float(x[0]) > float(y[0]))
		print("--- flex %.0f" % flex)
		for b in ["dy 0..10", "dy 10..25", "dy 25..45"]:
			if not bands.has(b):
				continue
			var arr: Array = bands[b]
			arr.sort()
			var n2 := arr.size()
			print("  %-11s %5d verts  median %.4f  p95 %.4f  p99 %.4f  max %.4f /mm"
				% [b, n2, float(arr[n2 / 2]), float(arr[int(n2 * 0.95)]),
				float(arr[int(n2 * 0.99)]), float(arr[n2 - 1])])
		for k in 6:
			var i: int = top[k][1]
			print("    %.4f /mm  dy %6.2f  at %s" % [float(top[k][0]), float(top[k][2]),
				str(p[i])])
	quit()
