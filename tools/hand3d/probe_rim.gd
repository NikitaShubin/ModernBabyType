extends SceneTree

const ArmView := preload("res://arm_view.gd")

func _init() -> void:
	var mesh: ArrayMesh = load("res://cache/skin_curled_rest.res")
	var rim := ArmView._cut_rim(mesh)
	print("rim %d" % rim.size())
	var c0 := Vector3.ZERO
	for p in rim:
		c0 += p
	c0 /= float(rim.size())
	var sm := ArmView._smooth(rim, c0)
	var dmax := -1e9
	var dmin := 1e9
	var worst := 0
	for i in rim.size():
		var a := Vector2(rim[i].x - c0.x, rim[i].z - c0.z)
		var b := Vector2(sm[i].x, sm[i].z)
		var d := a.length() - b.length()
		if d > dmax:
			dmax = d
			worst = i
		dmin = minf(dmin, d)
	print("raw minus smooth radius: %.2f .. %.2f mm (worst i %d at %s)" % [dmin, dmax, worst, str(rim[worst])])
	print("center %s  smooth extents x %.2f..%.2f z %.2f..%.2f" % [str(c0),
		sm[0].x, sm[0].x, sm[0].z, sm[0].z])
	var xmin := 1e9
	var xmax := -1e9
	var zmin := 1e9
	var zmax := -1e9
	for p in sm:
		xmin = minf(xmin, p.x)
		xmax = maxf(xmax, p.x)
		zmin = minf(zmin, p.z)
		zmax = maxf(zmax, p.z)
	print("smooth extents x %.2f..%.2f z %.2f..%.2f" % [xmin, xmax, zmin, zmax])
	quit()
