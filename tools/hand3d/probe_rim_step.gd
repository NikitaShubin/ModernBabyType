# The raw cut contour and its smoothed version near one angle: are there
# STEPS (two points at nearly the same angle, different radius)?
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
	print("raw rim %d points, c0 %s" % [raw.size(), str(c0)])
	for i in raw.size():
		var a := rad_to_deg(fposmod(atan2(raw[i].z - c0.z, raw[i].x - c0.x), TAU))
		if absf(angle_difference(deg_to_rad(45.0), deg_to_rad(a))) > deg_to_rad(6.0):
			continue
		print("i %3d a %7.2f raw r %6.3f  smooth r %6.3f  d %6.3f  d_ang %.2f" % [
			i, a, Vector2(raw[i].x - c0.x, raw[i].z - c0.z).length(),
			Vector2(sm[i].x - c0.x, sm[i].z - c0.z).length(),
			Vector2(sm[i].x - c0.x, sm[i].z - c0.z).length()
				- Vector2(raw[i].x - c0.x, raw[i].z - c0.z).length(),
			rad_to_deg(angle_difference(
				atan2(raw[i].z - c0.z, raw[i].x - c0.x),
				atan2(sm[i].z - c0.z, sm[i].x - c0.x)))])
	quit()
