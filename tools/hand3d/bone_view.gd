# Skeleton view of a HandModel: shafts as tapered cylinders, epiphyses as
# flattened spheres, and a carpal block so the metacarpals do not end in the
# air. Shared by the still renderer and the live viewer — one source of truth
# for what the bones look like.
extends RefCounted

const ArmModel := preload("res://arm_model.gd")

const SCALE := 0.001

const BONE_COLOR := "#f1e7d2"
const JOINT_COLOR := "#e6d9bd"


static func build(model: Object) -> Node3D:
	var root := Node3D.new()
	root.scale = Vector3.ONE * SCALE
	var xf := ArmModel.hand_transform(model._pose.get("arm", {}))

	var bone_mat := StandardMaterial3D.new()
	bone_mat.albedo_color = Color(BONE_COLOR)
	bone_mat.roughness = 0.55
	var joint_mat := StandardMaterial3D.new()
	joint_mat.albedo_color = Color(JOINT_COLOR)
	joint_mat.roughness = 0.7

	for b in model.bones:
		var a: Vector3 = xf * (b["a"] as Vector3)
		var c: Vector3 = xf * (b["b"] as Vector3)
		var dir := c - a
		var length := dir.length()
		if length < 0.01:
			continue
		var rel := dir / length
		var cyl := CylinderMesh.new()
		cyl.height = length
		cyl.top_radius = float(b["r2"])
		cyl.bottom_radius = float(b["r1"])
		cyl.radial_segments = 20
		cyl.rings = 1
		var mi := MeshInstance3D.new()
		mi.mesh = cyl
		mi.material_override = bone_mat
		var q := Quaternion(Vector3.UP, rel)
		mi.transform = Transform3D(Basis(q), (a + c) * 0.5)
		root.add_child(mi)

		# Epiphyses: the joint ends of real bones are knobbly.
		for e in [[a, float(b["r1"]) * 1.10], [c, float(b["r2"]) * 1.34]]:
			var r: float = e[1]
			var sm := MeshInstance3D.new()
			sm.mesh = _ball()
			sm.material_override = joint_mat
			sm.transform = Transform3D(_local_scale(q, Vector3(r, r * 0.78, r)), e[0])
			root.add_child(sm)

	# The carpus: without it the metacarpals end in mid-air and the palm looks
	# shorter than it is.
	for blob in [[Vector3(0.5, 15, 0), Vector3(17.5, 13.5, 10.5)],
			[Vector3(1, 21, 1), Vector3(14, 9, 9.5)],
			[Vector3(-14, 16, -4), Vector3(5, 7, 6.5)]]:
		var cm := MeshInstance3D.new()
		cm.mesh = _ball()
		cm.material_override = joint_mat
		cm.transform = Transform3D(xf.basis * Basis().scaled(blob[1]), xf * (blob[0] as Vector3))
		root.add_child(cm)
	return root


# Scale in the bone's own frame: R·diag(s), i.e. the basis columns stretched.
# Godot 4.3 has no Basis.scaled_local (it arrived later), and the global
# Basis.scaled stretches along WORLD axes — on a tilted bone that produced
# giant spikes.
static func _local_scale(q: Quaternion, s: Vector3) -> Basis:
	var b := Basis(q)
	return Basis(b.x * s.x, b.y * s.y, b.z * s.z)


static func _ball() -> SphereMesh:
	var sp := SphereMesh.new()
	sp.radius = 1.0
	sp.height = 2.0
	sp.radial_segments = 20
	sp.rings = 10
	return sp


# ---- live bones --------------------------------------------------------
#
# The same shapes, built once and then MOVED. The viewer solves IK many times
# a second; rebuilding a node tree per frame would churn twenty-odd meshes for
# nothing. Each bone is one cylinder (unit height, stretched along its own Y)
# and two balls; update_live only sets transforms.
static func build_live(model: Object) -> Dictionary:
	var root := Node3D.new()
	root.scale = Vector3.ONE * SCALE

	var bone_mat := StandardMaterial3D.new()
	bone_mat.albedo_color = Color(BONE_COLOR)
	bone_mat.roughness = 0.55
	var joint_mat := StandardMaterial3D.new()
	joint_mat.albedo_color = Color(JOINT_COLOR)
	joint_mat.roughness = 0.7

	var parts := []
	for b in model.bones:
		var cyl := CylinderMesh.new()
		cyl.height = 1.0
		cyl.top_radius = float(b["r2"])
		cyl.bottom_radius = float(b["r1"])
		cyl.radial_segments = 20
		cyl.rings = 1
		var shaft := MeshInstance3D.new()
		shaft.mesh = cyl
		shaft.material_override = bone_mat
		root.add_child(shaft)
		var ba := MeshInstance3D.new()
		ba.mesh = _ball()
		ba.material_override = joint_mat
		root.add_child(ba)
		var bb := MeshInstance3D.new()
		bb.mesh = _ball()
		bb.material_override = joint_mat
		root.add_child(bb)
		parts.append({"shaft": shaft, "ba": ba, "bb": bb, "r1": float(b["r1"]),
			"r2": float(b["r2"])})

	var carpus := []
	for blob in [[Vector3(0.5, 15, 0), Vector3(17.5, 13.5, 10.5)],
			[Vector3(1, 21, 1), Vector3(14, 9, 9.5)],
			[Vector3(-14, 16, -4), Vector3(5, 7, 6.5)]]:
		var cm := MeshInstance3D.new()
		cm.mesh = _ball()
		cm.material_override = joint_mat
		cm.transform = Transform3D(Basis().scaled(blob[1]), blob[0])
		root.add_child(cm)
		carpus.append({"node": cm, "pos": blob[0], "scale": blob[1]})
	return {"root": root, "parts": parts, "carpus": carpus}


static func update_live(view: Dictionary, model: Object) -> void:
	var xf := ArmModel.hand_transform(model._pose.get("arm", {}))
	var parts: Array = view["parts"]
	var i := 0
	for b in model.bones:
		if i >= parts.size():
			break
		var p: Dictionary = parts[i]
		i += 1
		var a: Vector3 = xf * (b["a"] as Vector3)
		var c: Vector3 = xf * (b["b"] as Vector3)
		var dir := c - a
		var length := dir.length()
		if length < 0.01:
			(p["shaft"] as Node3D).visible = false
			continue
		var rel := dir / length
		var q := Quaternion(Vector3.UP, rel)
		(p["shaft"] as Node3D).visible = true
		(p["shaft"] as Node3D).transform = Transform3D(
			_local_scale(q, Vector3(1.0, length, 1.0)), (a + c) * 0.5)
		var r1 := float(p["r1"]) * 1.10
		var r2 := float(p["r2"]) * 1.34
		(p["ba"] as Node3D).transform = Transform3D(
			_local_scale(q, Vector3(r1, r1 * 0.78, r1)), a)
		(p["bb"] as Node3D).transform = Transform3D(
			_local_scale(q, Vector3(r2, r2 * 0.78, r2)), c)
	for c in view.get("carpus", []):
		var node: Node3D = c["node"]
		var pos: Vector3 = c["pos"]
		var scale: Vector3 = c["scale"]
		node.transform = Transform3D(xf.basis * Basis().scaled(scale), xf * pos)
