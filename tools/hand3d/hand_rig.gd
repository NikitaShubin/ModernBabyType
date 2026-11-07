# One visible hand of the study: the skinned hand, its live bones and the
# forearm, all under one root that can be MIRRORED for the other side.
#
# The hand model (hand_model.gd) is a left hand in millimetres. The right hand
# is not a second model with its own numbers: it is the SAME model, the same
# solver and the same bone poses, rendered under a root scaled (-1, 1, 1). The
# mirror is a rigid reflection of the whole visible arm, so the two hands are
# mirror images by construction, not by tuning. Only the material needs
# culling disabled on the mirrored side, because a negative determinant turns
# the triangles inside out.
#
# The skin rig is built once (its weights come from the baked mesh) and cloned
# for the second hand: the mesh and the Skin resource are shared, only the
# Skeleton3D and the MeshInstance3D are new.
extends RefCounted

const HandModel := preload("res://hand_model.gd")
const SkinRig := preload("res://skin_rig.gd")
const BoneView := preload("res://bone_view.gd")
const ArmView := preload("res://arm_view.gd")
const WristOpen := preload("res://wrist_open.gd")

const SCALE := 0.001


## Build both hands. root_x is the wrist's world x in millimetres; the y and z
## of the wrist are the model's own origin. `mesh` is the capped rest mesh.
static func build_pair(mesh: ArrayMesh, rest: Object, root_x: Array,
		mat_skin: Material, mat_xray: Material) -> Dictionary:
	var open := WristOpen.open_wrist(mesh, rest)
	var rig := SkinRig.build(rest, open, "res://cache/skin_curled_rest.res",
		WristOpen.WRIST_FLAT_H)
	var out := {}
	for side in ["L", "R"]:
		var mirror: bool = side == "R"
		var hand := _build_one(rest, mesh, rig, root_x[0 if side == "L" else 1],
			mirror, mat_skin, mat_xray)
		out[side] = hand
	return out


static func _build_one(rest: Object, mesh: ArrayMesh, src: Dictionary,
		root_x: float, mirror: bool, mat_skin: Material,
		mat_xray: Material) -> Dictionary:
	var root := Node3D.new()
	root.name = "HandR" if mirror else "HandL"
	root.position = Vector3(root_x * SCALE, 0.0, 0.0)
	# The reflection is at the ROOT: every child keeps the left hand's local
	# coordinates and the left hand's bone poses, so the two sides cannot drift.
	if mirror:
		root.scale = Vector3(-1.0, 1.0, 1.0)

	var rig := _clone_rig(src)
	root.add_child(rig["skeleton"])
	root.add_child(rig["instance"])
	SkinRig.wire(rig)
	var mi: MeshInstance3D = rig["instance"]
	mi.scale = Vector3.ONE * SCALE
	mi.material_override = mat_skin

	var live := BoneView.build_live(rest)
	root.add_child(live["root"])

	var arm := ArmView.build(mesh, rest)
	root.add_child(arm["root"])
	ArmView.wire(arm)
	ArmView.set_skin_material(arm, mat_skin)

	return {"root": root, "rig": rig, "live": live, "arm": arm,
		"mirror": mirror, "root_x": root_x}


## A second skeleton and mesh instance over the same baked mesh, weights and
## Skin. The bones are flat frames (skin_rig.gd), so copying the rest frames is
## the whole job.
static func _clone_rig(src: Dictionary) -> Dictionary:
	var names: Array = src["names"]
	var frames: Array = src["rest_frames"]
	var skel := Skeleton3D.new()
	skel.name = "Skeleton3D"
	for i in names.size():
		skel.add_bone(String(names[i]))
		skel.set_bone_rest(i, frames[i])
		skel.set_bone_pose(i, frames[i])
	var src_mi: MeshInstance3D = src["instance"]
	var mi := MeshInstance3D.new()
	mi.name = "Skin"
	mi.mesh = src_mi.mesh
	mi.skin = src_mi.skin
	return {"skeleton": skel, "instance": mi, "weights": src["weights"],
		"names": names, "rest_frames": frames,
		"rest_model": src["rest_model"]}


## Put a solved pose on one hand. The mirrored hand needs nothing special: its
## local pose is the left hand's pose, and the root's reflection draws it as
## the right hand's.
static func apply(hand: Dictionary, model: Object) -> void:
	SkinRig.apply_pose(hand["rig"], model)
	BoneView.update_live(hand["live"], model)
	ArmView.update_live(hand["arm"], model._pose.get("arm", {}))


static func set_mode(hand: Dictionary, mode: int, mat_skin: Material,
		mat_xray: Material) -> void:
	var mi: MeshInstance3D = hand["rig"]["instance"]
	mi.visible = mode != 1
	mi.material_override = mat_xray if mode == 2 else mat_skin
	(hand["live"]["root"] as Node3D).visible = mode != 0
	var arm: Dictionary = hand["arm"]
	(arm["skin_root"] as Node3D).visible = mode != 1
	(arm["bone_root"] as Node3D).visible = mode != 0
	ArmView.set_skin_material(arm, mat_xray if mode == 2 else mat_skin)
