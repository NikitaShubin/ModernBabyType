# The radial profile of the hand's wall just above the cut, at one angle:
# y, radius, and the normal, to see why the rim's normal tilts down.
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
	var used := {}
	for i in (ha[Mesh.ARRAY_INDEX] as PackedInt32Array):
		used[i] = true
	var c0 := Vector3.ZERO
	var n := 0
	for i in hv.size():
		if used.has(i) and absf(hv[i].y - ArmView.CUT_Y) < 0.01:
			c0 += hv[i]
			n += 1
	c0 /= float(n)
	for deg in [3.87, 5.7, 45.0]:
		var want := deg_to_rad(deg)
		var rows := []
		for i in hv.size():
			if not used.has(i):
				continue
			var y := hv[i].y - ArmView.CUT_Y
			if y < -0.01 or y > 6.0:
				continue
			var a := fposmod(atan2(hv[i].z - c0.z, hv[i].x - c0.x), TAU)
			if absf(angle_difference(want, a)) > deg_to_rad(0.6):
				continue
			rows.append([y, Vector2(hv[i].x - c0.x, hv[i].z - c0.z).length(),
				hn[i].y, rad_to_deg(hn[i].angle_to(Vector3.UP))])
		rows.sort_custom(func(p, q): return float(p[0]) < float(q[0]))
		print("--- %.0f deg" % deg)
		for r in rows:
			print("  y %5.2f  r %6.2f  ny %6.3f  from-up %6.1f" % [
				float(r[0]), float(r[1]), float(r[2]), float(r[3])])
	quit()
