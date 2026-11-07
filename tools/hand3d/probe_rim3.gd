# The arm's rim (SDF contour) and the opened hand's rim, angle by angle, plus
# the mesh's first wall rows. Answers one question: is the rim really on the
# SDF contour, and how far from the mesh's own wall does that put it? Headless.
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const ArmView := preload("res://arm_view.gd")
const Viewer := preload("res://viewer.gd")

const REST_MESH := "res://cache/skin_curled_rest.res"


func _init() -> void:
	var rest := HandModel.new(1.0, 0.0)
	var src: ArrayMesh = load(REST_MESH)
	var viewer: Node = Viewer.new()
	var opened: ArrayMesh = viewer._open_wrist(src, rest)
	viewer.free()
	var arm := ArmView.build(src, rest)
	var rim: PackedVector3Array = arm["rim"]
	var c0: Vector3 = arm["c0"]
	var a: Array = opened.surface_get_arrays(0)
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	var used := {}
	for i in idx:
		used[i] = true

	# The arm's rim, polar profile.
	var prof := []
	for p in rim:
		prof.append([fposmod(atan2(p.z - c0.z, p.x - c0.x), TAU),
			Vector2(p.x - c0.x, p.z - c0.z).length()])
	prof.sort_custom(func(x, y): return float(x[0]) < float(y[0]))
	print("arm rim %d points, radius %.2f..%.2f" % [rim.size(),
		prof[0][1], prof[prof.size() - 1][1]])
	for deg in range(0, 360, 15):
		var ang := deg_to_rad(float(deg))
		var best := 1e9
		var r := 0.0
		for q in prof:
			var da := absf(angle_difference(float(q[0]), ang))
			if da < best:
				best = da
				r = float(q[1])
		print("  ang %3d  arm rim r %7.3f" % [deg, r])

	# The opened mesh's rim vertices (y == CUT_Y) and the rows above.
	var rows := {}
	for i in used:
		var y := v[i].y
		var key := int(round((y - ArmView.CUT_Y) * 100.0))
		if key < 0 or key > 40:
			continue
		if not rows.has(key):
			rows[key] = []
		var rr := Vector2(v[i].x - c0.x, v[i].z - c0.z).length()
		(rows[key] as Array).append(rr)
	var keys := rows.keys()
	keys.sort()
	print("mesh rows above the cut (dy mm -> n, r min/mean/max):")
	for k in keys:
		var arr: Array = rows[k]
		var mn := 1e9
		var mx := -1e9
		var sum := 0.0
		for r in arr:
			mn = minf(mn, float(r))
			mx = maxf(mx, float(r))
			sum += float(r)
		print("  dy %5.2f  n %3d  r %7.3f %7.3f %7.3f" % [
			float(k) / 100.0, arr.size(), mn, sum / float(arr.size()), mx])
	quit()
