# How jagged is the cut contour? The turn between neighbouring vertices'
# normals around ring 0 of the arm, and the radius variation per step.
extends SceneTree

const ArmView := preload("res://arm_view.gd")

const REST_MESH := "res://cache/skin_curled_rest.res"


func _init() -> void:
	var src: ArrayMesh = load(REST_MESH)
	var raw := ArmView._cut_rim(src)
	var sm := ArmView._smoothed_rim(raw)
	var c0 := Vector3.ZERO
	for p in raw:
		c0 += p
	c0 /= maxf(float(raw.size()), 1.0)
	var arm := ArmView.build(src)
	var aa: Array = ((arm["skin_mesh"] as MeshInstance3D).mesh as ArrayMesh).surface_get_arrays(0)
	var av: PackedVector3Array = aa[Mesh.ARRAY_VERTEX]
	var an: PackedVector3Array = aa[Mesh.ARRAY_NORMAL]
	var ring := []
	for i in av.size():
		if absf(av[i].y - ArmView.CUT_Y) < 0.01:
			ring.append(i)
	ring.sort_custom(func(p, q):
		return fposmod(atan2(av[p].z - c0.z, av[p].x - c0.x), TAU) \
			< fposmod(atan2(av[q].z - c0.z, av[q].x - c0.x), TAU))
	print("ring %d" % ring.size())
	var worst := 0.0
	var worst_i := -1
	var turns := []
	for k in ring.size():
		var a: int = ring[k]
		var b: int = ring[(k + 1) % ring.size()]
		var d := rad_to_deg(an[a].angle_to(an[b]))
		turns.append(d)
		if d > worst:
			worst = d
			worst_i = k
	turns.sort()
	print("normal turn around ring: median %.2f, p90 %.2f, worst %.2f deg" % [
		float(turns[turns.size() / 2]), float(turns[int(turns.size() * 0.9)]), worst])
	print("worst between %d and %d" % [ring[worst_i], ring[(worst_i + 1) % ring.size()]])
	var rmin := 1e9
	var rmax := -1e9
	for p in sm:
		var r := Vector2(p.x - c0.x, p.z - c0.z).length()
		rmin = minf(rmin, r)
		rmax = maxf(rmax, r)
	print("smoothed radius %.2f .. %.2f mm" % [rmin, rmax])
	# The same, on the RAW contour: how much does the smoothing help?
	var wraw := 0.0
	var wsm := 0.0
	for i in raw.size():
		var j := (i + 1) % raw.size()
		var d1 := Vector3(raw[j].x - raw[i].x, 0, raw[j].z - raw[i].z)
		var d2 := Vector3(raw[i].x - raw[(i - 1 + raw.size()) % raw.size()].x, 0,
			raw[i].z - raw[(i - 1 + raw.size()) % raw.size()].z)
		if d1.length() > 0.001 and d2.length() > 0.001:
			wraw = maxf(wraw, rad_to_deg(d1.angle_to(d2)))
		var e1 := Vector3(sm[j].x - sm[i].x, 0, sm[j].z - sm[i].z)
		var e2 := Vector3(sm[i].x - sm[(i - 1 + sm.size()) % sm.size()].x, 0,
			sm[i].z - sm[(i - 1 + sm.size()) % sm.size()].z)
		if e1.length() > 0.001 and e2.length() > 0.001:
			wsm = maxf(wsm, rad_to_deg(e1.angle_to(e2)))
	print("contour kink: raw worst %.2f deg, smoothed worst %.2f deg" % [wraw, wsm])
	quit()
