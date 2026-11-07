# Directional clearance between the wrist cut rim and the hand's skin just
# above the cut: how far inward a ring at y = -1.5 + h may sit without
# poking through the hand.
extends SceneTree

const ArmView := preload("res://arm_view.gd")

func _init() -> void:
	var mesh: ArrayMesh = load("res://cache/skin_curled_rest.res")
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var rim := ArmView._cut_rim(mesh)
	var c0 := Vector3.ZERO
	for p in rim:
		c0 += p
	c0 /= float(rim.size())
	for yi in [0.0, 0.5, 1.0, 1.5, 2.0]:
		var y := float(yi)
		var band := []
		for p in verts:
			if absf(p.y - y) > 0.3:
				continue
			band.append(p)
		var worst := 1e9
		var worst_dir := ""
		var sum := 0.0
		for i in rim.size():
			var rv := Vector2(rim[i].x - c0.x, rim[i].z - c0.z)
			var ra := atan2(rv.y, rv.x)
			var best := 0.0
			for p in band:
				var v := Vector2(p.x - c0.x, p.z - c0.z)
				if v.length() < 0.01:
					continue
				var da := absf(angle_difference(ra, atan2(v.y, v.x)))
				if da > 0.09:
					continue
				best = maxf(best, v.length())
			if best < 0.01:
				continue
			var d := best - rv.length()
			sum += d
			if d < worst:
				worst = d
				worst_dir = "i %d dir %+.0f° rim r %.1f hand r %.1f" % [
					i, rad_to_deg(ra), rv.length(), best]
		print("y %+4.1f: clearance min %+.2f mean %+.2f | %s" % [
			y, worst, sum / float(rim.size()), worst_dir])
	quit()
