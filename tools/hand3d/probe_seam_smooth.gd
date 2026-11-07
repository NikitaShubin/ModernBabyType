# Is the seam's normal field smooth ALONG the contour? Prints the angle between
# neighbouring normals of the hand's rim row and of the arm's ring 0, so a
# zigzag (alternating +- degrees, the sawtooth seen in close-palm-f70) shows
# as a large second difference. Headless.
extends SceneTree

const ArmView := preload("res://arm_view.gd")
const Viewer := preload("res://viewer.gd")

const REST_MESH := "res://cache/skin_curled_rest.res"


func _init() -> void:
	var src: ArrayMesh = load(REST_MESH)
	var viewer: Node = Viewer.new()
	var opened: ArrayMesh = viewer._open_wrist(src)
	viewer.free()
	var ha: Array = opened.surface_get_arrays(0)
	var hv: PackedVector3Array = ha[Mesh.ARRAY_VERTEX]
	var hn: PackedVector3Array = ha[Mesh.ARRAY_NORMAL]
	var idx: PackedInt32Array = ha[Mesh.ARRAY_INDEX]
	var used := {}
	for i in idx:
		used[i] = true
	var arm := ArmView.build(src)
	var aa: Array = ((arm["skin_mesh"] as MeshInstance3D).mesh as ArrayMesh).surface_get_arrays(0)
	var av: PackedVector3Array = aa[Mesh.ARRAY_VERTEX]
	var an: PackedVector3Array = aa[Mesh.ARRAY_NORMAL]
	var rim: PackedVector3Array = arm["rim"]
	var c0: Vector3 = arm["c0"]
	var n := rim.size()
	# Hand rim normal per contour point: the rim vertex nearest that point.
	var hrim := PackedVector3Array()
	hrim.resize(n)
	var arim := PackedVector3Array()
	arim.resize(n)
	for j in n:
		var best := 1e9
		var bi := -1
		for i in hv.size():
			if not used.has(i) or absf(hv[i].y - ArmView.CUT_Y) > 0.01:
				continue
			var d := Vector2(hv[i].x - rim[j].x, hv[i].z - rim[j].z).length()
			if d < best:
				best = d
				bi = i
		hrim[j] = hn[bi]
		var abest := 1e9
		var ai := -1
		for i in av.size():
			if absf(av[i].y - ArmView.CUT_Y) > 0.01:
				continue
			var darm := Vector2(av[i].x - rim[j].x, av[i].z - rim[j].z).length()
			if darm < abest:
				abest = darm
				ai = i
		arim[j] = an[ai]
	# Neighbour step and second difference, around the ring.
	for who in [["hand", hrim], ["arm", arim]]:
		var ns: PackedVector3Array = who[1]
		var step := []
		var d2 := []
		for j in n:
			var a: float = ns[j].angle_to(ns[(j + 1) % n])
			step.append(a)
			var b: float = ns[(j + 1) % n].angle_to(ns[(j + 2) % n])
			d2.append(absf(a - b))
		var mx := 0.0
		var mi := 0
		for j in n:
			if float(step[j]) > mx:
				mx = float(step[j])
				mi = j
		var m2 := 0.0
		var m2i := 0
		for j in n:
			if float(d2[j]) > m2:
				m2 = float(d2[j])
				m2i = j
		var mean := 0.0
		for j in n:
			mean += float(step[j])
		mean /= float(n)
		print("%s: step mean %.3f  max %.3f deg at %d  |  second diff max %.3f deg at %d"
			% [who[0], rad_to_deg(mean), rad_to_deg(mx), mi, rad_to_deg(m2), m2i])
	# The hand's rim against the arm's ring 0, point by point.
	var worst := 0.0
	var sum := 0.0
	for j in n:
		var a: float = hrim[j].angle_to(arim[j])
		sum += a
		worst = maxf(worst, a)
	print("hand vs arm: mean %.3f  worst %.3f deg" % [
		rad_to_deg(sum / float(n)), rad_to_deg(worst)])
	quit()
