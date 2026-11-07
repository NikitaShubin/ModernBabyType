# Radial profile of the hand's wall just above the cut, and of the arm loft
# just below it. The seam is only smooth if the two profiles meet with the
# same slope, so this prints both sides ring by ring.
extends SceneTree

const HandModel := preload("res://hand_model.gd")
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
	print("rim n=%d centre %s" % [rim.size(), str(c0)])

	print("-- hand wall above the cut (mean radius, min, max, n) --")
	for yy in [-1.5, -1.0, -0.5, 0.0, 0.5, 1.0, 2.0, 3.0, 4.0, 6.0, 8.0, 10.0, 12.0]:
		var lo := 1e9
		var hi := -1e9
		var sum := 0.0
		var n := 0
		for p in verts:
			if absf(p.y - yy) > 0.26:
				continue
			var r := Vector2(p.x - c0.x, p.z - c0.z).length()
			lo = minf(lo, r)
			hi = maxf(hi, r)
			sum += r
			n += 1
		if n > 0:
			print("  y %+5.1f  mean %6.2f  min %6.2f  max %6.2f  n %3d" % [
				yy, sum / float(n), lo, hi, n])

	# The arm's own rings: same measure, ring by ring. _ring is the source of
	# the surface, so this is not a re-implementation.
	print("-- arm rings below the cut --")
	var sm := ArmView._smooth(rim, c0)
	for k in 8:
		var t := float(k) / float(ArmView.RINGS - 1)
		var d := (ArmView.TUBE_L - ArmView.CAP_L) * pow(t, 1.25)
		var off := 0.0
		if k > 0:
			off = ArmView.COLLAR_OUT * (1.0 - smoothstep(ArmView.COLLAR_IN, ArmView.COLLAR_L, d))
		var ring := ArmView._ring(rim, sm, c0, d, 1.0, off)
		var lo := 1e9
		var hi := -1e9
		var sum := 0.0
		for p in ring:
			var r := Vector2(p.x - c0.x, p.z - c0.z).length()
			lo = minf(lo, r)
			hi = maxf(hi, r)
			sum += r
		print("  k %2d  depth %6.2f  off %.2f  mean %6.2f  min %6.2f  max %6.2f" % [
			k, d, off, sum / float(ring.size()), lo, hi])
	quit()
