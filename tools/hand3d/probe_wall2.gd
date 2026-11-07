# Per-angle radial profile across the wrist seam: the hand's wall just above
# the cut against the arm's rings just below it, at the same angles.
extends SceneTree

const ArmView := preload("res://arm_view.gd")

const MESH := "res://cache/skin_curled_rest.res"


func _init() -> void:
	var src: ArrayMesh = load(MESH)
	var arrays := src.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var rim := ArmView._cut_rim(src)
	var c0 := Vector3.ZERO
	for p in rim:
		c0 += p
	c0 /= float(rim.size())
	var sm := ArmView._smooth(rim, c0)

	# The hand's wall: radius at a given y, sampled at the rim's angles.
	var hand := {}
	for yy in [0.0, 1.0, 2.0, 3.0, 4.0, 6.0, 8.0]:
		var bins := {}
		for p in verts:
			if absf(p.y - yy) > 0.26:
				continue
			var r := Vector2(p.x - c0.x, p.z - c0.z).length()
			var a := atan2(p.z - c0.z, p.x - c0.x)
			var key := int(round(a / TAU * 72.0)) % 72
			if not bins.has(key):
				bins[key] = []
			(bins[key] as Array).append(r)
		hand[yy] = bins

	var rings := []
	for k in 6:
		var t := float(k) / float(ArmView.RINGS - 1)
		var d := (ArmView.TUBE_L - ArmView.CAP_L) * pow(t, 1.25)
		var off := 0.0
		if k > 0:
			off = ArmView.COLLAR_OUT * (1.0 - smoothstep(ArmView.COLLAR_IN, ArmView.COLLAR_L, d))
		rings.append([d, ArmView._ring(rim, sm, c0, d, 1.0, off)])

	print("angle | rim | hand y=0 +1 +2 +4 +6 +8 | arm d=2.5 6 10 14 19")
	for i in range(0, rim.size(), 6):
		var a := atan2(rim[i].z - c0.z, rim[i].x - c0.x)
		var key := int(round(a / TAU * 72.0)) % 72
		var line := "%6.1f | %5.1f |" % [rad_to_deg(a), Vector2(rim[i].x - c0.x, rim[i].z - c0.z).length()]
		for yy in [0.0, 1.0, 2.0, 4.0, 6.0, 8.0]:
			var bin: Array = (hand[yy] as Dictionary).get(key, [])
			var v := -1.0
			if not bin.is_empty():
				var s := 0.0
				for x in bin:
					s += float(x)
				v = s / float(bin.size())
			line += " %5.1f" % v
		line += " |"
		for k in [1, 2, 3, 4, 5]:
			var rr: PackedVector3Array = rings[k][1]
			line += " %5.1f" % Vector2(rr[i].x - c0.x, rr[i].z - c0.z).length()
		print(line)
	quit()
