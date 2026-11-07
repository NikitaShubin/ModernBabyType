# The true SDF radius at the wrist, angle by angle, against the mesh's rim and
# wall. Tells whether the seam step is the mesh's or the field's.
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const ArmView := preload("res://arm_view.gd")

const MESH := "res://cache/skin_curled_rest.res"


func _init() -> void:
	var m := HandModel.new(1.0, 0.0)
	var src: ArrayMesh = load(MESH)
	var verts: PackedVector3Array = src.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var rim := ArmView._cut_rim(src)
	var c0 := Vector3.ZERO
	for p in rim:
		c0 += p
	c0 /= float(rim.size())

	print("angle | SDF r at y=-1.5  0  +2  +4 | rim | mesh y=0 +2 +4")
	for deg in [0, 30, 60, 90, 120, 150, 180, 210, 240, 270, 300, 330]:
		var a := deg_to_rad(float(deg))
		var line := "%6.0f |" % deg
		for yy in [-1.5, 0.0, 2.0, 4.0]:
			var lo := 5.0
			var hi := 35.0
			for i in 40:
				var mid := (lo + hi) * 0.5
				var p := c0 + Vector3(cos(a) * mid, 0.0, sin(a) * mid)
				p.y = yy
				if m.field(p) < 0.0:
					lo = mid
				else:
					hi = mid
			line += " %5.2f" % ((lo + hi) * 0.5)
		# The mesh's rim at the nearest angle.
		var best := 1e9
		var br := 0.0
		for i in rim.size():
			var ra := atan2(rim[i].z - c0.z, rim[i].x - c0.x)
			var da := absf(angle_difference(a, ra))
			if da < best:
				best = da
				br = Vector2(rim[i].x - c0.x, rim[i].z - c0.z).length()
		line += " | %5.2f |" % br
		for yy in [0.0, 2.0, 4.0]:
			var best2 := 1e9
			var br2 := -1.0
			for p in verts:
				if absf(p.y - yy) > 0.26:
					continue
				var ra := atan2(p.z - c0.z, p.x - c0.x)
				var da := absf(angle_difference(a, ra))
				if da < best2:
					best2 = da
					br2 = Vector2(p.x - c0.x, p.z - c0.z).length()
			line += " %5.2f" % br2
		print(line)
	quit()
