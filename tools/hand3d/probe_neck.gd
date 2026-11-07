# The wrist's silhouette profile: width (x) and depth (z) of the rest mesh at
# each height. The author sees a "waist" at the joint, so the numbers have to
# say where the narrowest band is and how long it is.
# Run: godot --headless --path tools/hand3d --script res://probe_neck.gd
extends SceneTree

const REST_MESH := "res://cache/skin_curled_rest.res"


func _init() -> void:
	var mesh: ArrayMesh = load(REST_MESH)
	var arrays: Array = mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var rows := {}
	for p in verts:
		var k := int(round(p.y))
		if k < -50 or k > 60:
			continue
		if not rows.has(k):
			rows[k] = [1.0e9, -1.0e9, 1.0e9, -1.0e9]
		var r: Array = rows[k]
		r[0] = minf(r[0], p.x)
		r[1] = maxf(r[1], p.x)
		r[2] = minf(r[2], p.z)
		r[3] = maxf(r[3], p.z)
	var keys: Array = rows.keys()
	keys.sort()
	print("  y     width   depth   xmin   xmax   zmin   zmax")
	for k in keys:
		var r: Array = rows[k]
		var w := float(r[1]) - float(r[0])
		var d := float(r[3]) - float(r[2])
		if k % 2 != 0:
			continue
		print("%4d  %7.2f %7.2f  %6.1f %6.1f %6.1f %6.1f" % [
			int(k), w, d, float(r[0]), float(r[1]), float(r[2]), float(r[3])])
	quit()
