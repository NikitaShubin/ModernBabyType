# The raw rim against the smoothed one: how much does the Gaussian smoothing
# shrink the section? A few millimetres here would mean the flatten pass pulls
# the hand's wall inward from the very start and the seam sits inside the
# hand's own wrist. Headless.
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
	c0 /= float(raw.size())
	print("rim points %d, centre %s" % [raw.size(), str(c0)])
	var dr := []
	var worst := [0.0, Vector3.ZERO]
	for i in raw.size():
		var r0 := Vector2(raw[i].x - c0.x, raw[i].z - c0.z).length()
		var r1 := Vector2(sm[i].x - c0.x, sm[i].z - c0.z).length()
		dr.append(r1 - r0)
		if absf(r1 - r0) > absf(worst[0]):
			worst = [r1 - r0, raw[i]]
	dr.sort()
	var n := dr.size()
	var sum := 0.0
	for e in dr:
		sum += float(e)
	print("smoothed - raw: mean %+.3f  min %+.3f  p05 %+.3f  p95 %+.3f  max %+.3f mm"
		% [sum / float(n), float(dr[0]), float(dr[n / 20]), float(dr[n - n / 20]), float(dr[n - 1])])
	print("worst at %s" % str(worst[1]))
	# The ellipse the smoothing should approximate: the capsule's own section.
	print("radii raw: min %.2f max %.2f   smoothed: min %.2f max %.2f" % [
		_rmin(raw, c0), _rmax(raw, c0), _rmin(sm, c0), _rmax(sm, c0)])
	quit()


func _rmin(pts: PackedVector3Array, c0: Vector3) -> float:
	var m := 1e9
	for p in pts:
		m = minf(m, Vector2(p.x - c0.x, p.z - c0.z).length())
	return m


func _rmax(pts: PackedVector3Array, c0: Vector3) -> float:
	var m := 0.0
	for p in pts:
		m = maxf(m, Vector2(p.x - c0.x, p.z - c0.z).length())
	return m
