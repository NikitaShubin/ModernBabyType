# The arm's posed surface along one meridian of the outer bend: is the shading
# banding a corrugation of the skin (radius wobbles) or only the per-ring
# normals? Vertices are grouped by their bone (SurfaceTool reorders them, so
# the bone is the only reliable ring id).
extends SceneTree

const ArmView := preload("res://arm_view.gd")
const ArmModel := preload("res://arm_model.gd")
const HandModel := preload("res://hand_model.gd")

const REST_MESH := "res://cache/skin_curled_rest.res"


func _init() -> void:
	var src: ArrayMesh = load(REST_MESH)
	var arm: Dictionary = ArmView.build(src)
	var pose: Dictionary = HandModel.rest_pose()
	pose["arm"]["wrist_flex"] = 70.0
	ArmView.update_live(arm, pose["arm"])
	var skel: Skeleton3D = arm["skeleton"]
	var mi: MeshInstance3D = arm["skin_mesh"]
	var a: Array = (mi.mesh as ArrayMesh).surface_get_arrays(0)
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
	var bones: PackedInt32Array = a[Mesh.ARRAY_BONES]
	var depths: PackedFloat32Array = arm["depths"]
	var c0: Vector3 = arm["c0"]
	var want := deg_to_rad(90.0)
	var pick := {}
	for i in v.size():
		var k := bones[i * 4]
		if k >= depths.size():
			continue
		var ang := atan2(v[i].z - c0.z, v[i].x - c0.x)
		var d := absf(angle_difference(want, ang))
		if not pick.has(k) or d < float(pick[k][0]):
			pick[k] = [d, i]
	var prev_n := Vector3.ZERO
	var prev_r := 0.0
	for k in depths.size():
		if not pick.has(k):
			continue
		var vi: int = int(pick[k][1])
		var d := depths[k]
		var xf := skel.get_bone_global_pose(k)
		var fade := 1.0 - smoothstep(0.0, ArmView.TUBE_L, d)
		var rest_c := Vector3(c0.x * fade, ArmView.CUT_Y - d, c0.z * fade)
		var c := xf * rest_c
		var p := xf * v[vi]
		var nn := (xf.basis * n[vi]).normalized()
		var rad := p - c
		var step := rad_to_deg(prev_n.angle_to(nn)) if k > 0 else 0.0
		var dr := rad.length() - prev_r if k > 0 else 0.0
		print("ring %2d depth %6.2f  r %6.3f  dr %+6.3f  radial %6.3f  step %5.2f" % [
			k, d, rad.length(), dr, rad.normalized().dot(nn), step])
		prev_n = nn
		prev_r = rad.length()
	quit()
