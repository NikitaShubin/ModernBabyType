# Times the weight bake in its stages, so a slow smoothing pass is visible
# instead of a silent 10-minute wait.
#   mbt-godot --headless --path /work/tools/hand3d --script res://smooth_time.gd
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const SkinRig := preload("res://skin_rig.gd")

const REST_MESH := "res://cache/skin_curled_rest.res"


func _init() -> void:
	var rest := HandModel.new(1.0, 0.0)
	var src: ArrayMesh = load(REST_MESH)
	var arrays: Array = src.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var tris: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	print("verts %d tris %d" % [verts.size(), tris.size() / 3])
	var t0 := Time.get_ticks_msec()
	var w := SkinRig.compute_weights(rest, verts, tris)
	print("compute_weights %.1f s" % [float(Time.get_ticks_msec() - t0) / 1000.0])
	print("mean_top %.3f worst_top %.3f at %s" % [float(w["mean_top"]),
		float(w["worst_top"]), str(w["worst_at"])])
	quit(0)
