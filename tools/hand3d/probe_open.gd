# The hand's wall profile after viewer._open_wrist: did the flattening land?
extends SceneTree

const ArmView := preload("res://arm_view.gd")
const Viewer := preload("res://viewer.gd")

const MESH := "res://cache/skin_curled_rest.res"


func _init() -> void:
	var src: ArrayMesh = load(MESH)
	var v: Node3D = Viewer.new()
	var open: ArrayMesh = v._open_wrist(src)
	var verts: PackedVector3Array = open.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var raw := ArmView._cut_rim(src)
	var c0 := Vector3.ZERO
	for p in raw:
		c0 += p
	c0 /= float(raw.size())

	print("y | mean min max n | angle 0 30 60 90 180 270")
	for yy in [-1.5, -1.0, -0.5, 0.0, 0.5, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 8.0]:
		var sum := 0.0
		var n := 0
		var lo := 1e9
		var hi := -1e9
		for p in verts:
			if absf(p.y - yy) > 0.26:
				continue
			var r := Vector2(p.x - c0.x, p.z - c0.z).length()
			sum += r
			n += 1
			lo = minf(lo, r)
			hi = maxf(hi, r)
		if n == 0:
			continue
		var line := "%+5.1f | %5.2f %5.2f %5.2f %3d |" % [yy, sum / float(n), lo, hi, n]
		for deg in [0, 30, 60, 90, 180, 270]:
			var a := deg_to_rad(float(deg))
			var best := 1e9
			var br := -1.0
			for p in verts:
				if absf(p.y - yy) > 0.26:
					continue
				var ra := atan2(p.z - c0.z, p.x - c0.x)
				var da := absf(angle_difference(a, ra))
				if da < best:
					best = da
					br = Vector2(p.x - c0.x, p.z - c0.z).length()
			line += " %5.2f" % br
		print(line)
	quit()
