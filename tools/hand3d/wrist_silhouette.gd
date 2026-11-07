# Finds the rim point that forms the TOP of the wrist silhouette in the palm
# camera and measures the hand's wall tangent and the arm's wall tangent right
# there. The cardinal points are not the silhouette: the rim is tilted, so the
# top of its projection can sit between them. Headless:
#   mbt-godot --headless --path /work/tools/hand3d --script res://wrist_silhouette.gd
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")
const SkinRig := preload("res://skin_rig.gd")
const ArmView := preload("res://arm_view.gd")
const Viewer := preload("res://viewer.gd")

const REST_MESH := "res://cache/skin_curled_rest.res"
const CAM_YAW := -1.30
const CAM_PITCH := 0.10
const CAM_DIST := 340.0
const CAM_CENTER := Vector3(0.0, 35.0, 0.0)


func _init() -> void:
	var rest := HandModel.new(1.0, 0.0)
	var src: ArrayMesh = load(REST_MESH)
	var viewer: Node = Viewer.new()
	var opened: ArrayMesh = viewer._open_wrist(src)
	viewer.free()
	var rig := SkinRig.build(rest, opened, REST_MESH, Viewer.WRIST_FLAT_H)
	var arm := ArmView.build(src)
	var arrays: Array = opened.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var arm_rim: PackedVector3Array = arm["rim"]
	var c0: Vector3 = arm["c0"]
	var depths: PackedFloat32Array = arm["depths"]
	var rim_i := []
	for r in arm_rim:
		var best := 1e9
		var bi := -1
		for i in verts.size():
			if absf(verts[i].y - ArmView.CUT_Y) > 0.01:
				continue
			var d := Vector2(verts[i].x - r.x, verts[i].z - r.z).length()
			if d < best:
				best = d
				bi = i
		if bi >= 0 and best < 0.05:
			rim_i.append(bi)

	var sm := PackedVector3Array()
	sm.resize(arm_rim.size())
	for i in arm_rim.size():
		sm[i] = arm_rim[i] - c0
	var ring0 := ArmView._ring(arm_rim, sm, c0, depths[0], 1.0, 0.0)
	var ring1 := ArmView._ring(arm_rim, sm, c0, depths[1], 1.0, 0.0)

	var dir := Vector3(sin(CAM_YAW) * cos(CAM_PITCH), sin(CAM_PITCH),
		cos(CAM_YAW) * cos(CAM_PITCH)).normalized()
	var cam := CAM_CENTER + dir * CAM_DIST
	var fwd := (CAM_CENTER - cam).normalized()
	var right := fwd.cross(Vector3.UP).normalized()
	var up := right.cross(fwd).normalized()

	for flex in [0.0, 70.0]:
		var p := HandModel.rest_pose()
		p["arm"]["wrist_flex"] = flex
		var model := HandModel.new(1.0, 0.0, p)
		var hp := SkinRig.cpu_positions(rig, model)
		ArmView.update_live(arm, p["arm"])
		var skel: Skeleton3D = arm["skeleton"]
		var x0 := skel.get_bone_pose(0)
		var x1 := skel.get_bone_pose(1)
		var blend_xf := ArmModel.wrist_blend(p["arm"], ArmModel.WRIST_BLEND)
		var down := (blend_xf.basis * Vector3.DOWN).normalized()

		var best_i := -1
		var best_y := -1e9
		for i in rim_i.size():
			var q := hp[rim_i[i]]
			var v := q - cam
			var sy := v.dot(up) / v.dot(fwd)
			if sy > best_y:
				best_y = sy
				best_i = i
		var q0 := hp[rim_i[best_i]]
		var v0 := q0 - cam
		var sx := v0.dot(right) / v0.dot(fwd)
		var sy := v0.dot(up) / v0.dot(fwd)
		print("--- flex %.0f silhouette rim %d at screen (%.4f, %.4f)" % [flex, best_i, sx, sy])

		# Hand tangent: the closest vertex 2..6 mm above the rim, in the
		# vertical (hand-local) direction.
		var best := 1e9
		var hi := -1
		for j in verts.size():
			var dy := verts[j].y - ArmView.CUT_Y
			if dy < 2.0 or dy > 6.0:
				continue
			var dj := Vector2(verts[j].x - arm_rim[best_i].x,
				verts[j].z - arm_rim[best_i].z).length()
			if dj < best:
				best = dj
				hi = j
		var th := (hp[hi] - q0).normalized()
		var a0 := x0 * ring0[best_i]
		var a1 := x1 * ring1[best_i]
		var ta := (a1 - a0).normalized()
		print("hand tangent %s  arm tangent %s" % [str(th), str(ta)])
		print("kink %.2f°  hand-down %.2f°  arm-down %.2f°"
			% [180.0 - rad_to_deg(th.angle_to(ta)), 180.0 - rad_to_deg(th.angle_to(down)),
			rad_to_deg(ta.angle_to(down))])
		# Project both tangents onto the screen and compare their slopes.
		var ph := _project(q0 + th * 10.0, cam, fwd, right, up) \
			- _project(q0, cam, fwd, right, up)
		var pa := _project(q0 + ta * 10.0, cam, fwd, right, up) \
			- _project(q0, cam, fwd, right, up)
		print("screen hand %s  arm %s  slope angle %.1f°"
			% [str(ph), str(pa), rad_to_deg(atan2(ph.y, ph.x) - atan2(pa.y, pa.x))])
	quit(0)


func _project(p: Vector3, cam: Vector3, fwd: Vector3, right: Vector3,
		up: Vector3) -> Vector2:
	var v := p - cam
	return Vector2(v.dot(right) / v.dot(fwd), v.dot(up) / v.dot(fwd))
