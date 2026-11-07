# Compares where the thumb's skin sits in the two baked poses. Headless:
#   mbt-godot --headless --path /work/tools/hand3d --script res://probe_thumb_mesh.gd
extends SceneTree

const FILES := ["res://cache/skin.res", "res://cache/skin_flat.res",
	"res://cache/skin_flat_back.res"]


func _init() -> void:
	for f in FILES:
		if not ResourceLoader.exists(f):
			print("%s: MISSING" % f)
			continue
		var mesh: ArrayMesh = load(f)
		var arr := mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		# The thumb is the only part of the hand with x > 50 mm.
		var zmin := 1.0e9
		var zmax := -1.0e9
		var n := 0
		for v in verts:
			if v.x > 50.0:
				zmin = minf(zmin, v.z)
				zmax = maxf(zmax, v.z)
				n += 1
		print("%s: thumb vertices %d  z %.1f .. %.1f mm" % [f, n, zmin, zmax])
	quit()
