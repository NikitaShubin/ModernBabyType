# Measures the tangent of the hand's wrist wall just above the seam and of the
# arm's wall just below it. A crease at the seam means these two directions do
# not agree; a smooth joint means they do. Headless:
#   mbt-godot --headless --path /work/tools/hand3d --script res://wrist_tangent.gd
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")
const SkinRig := preload("res://skin_rig.gd")
const ArmView := preload("res://arm_view.gd")
const Viewer := preload("res://viewer.gd")
const WristOpen := preload("res://wrist_open.gd")

const REST_MESH := "res://cache/skin_curled_rest.res"


func _init() -> void:
	var rest := HandModel.new(1.0, 0.0)
	var src: ArrayMesh = load(REST_MESH)
	var viewer: Node = Viewer.new()
	var opened: ArrayMesh = viewer._open_wrist(src)
	viewer.free()
	var rig := SkinRig.build(rest, opened, REST_MESH, WristOpen.WRIST_FLAT_H)
	var arm := ArmView.build(src)
	var arrays: Array = opened.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var arm_rim: PackedVector3Array = arm["rim"]
	var c0: Vector3 = arm["c0"]
	var depths: PackedFloat32Array = arm["depths"]

	# The rim of the hand, matched to the arm ring exactly as wrist_seam does.
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
	print("rim matched: %d / %d" % [rim_i.size(), arm_rim.size()])

	var sm := PackedVector3Array()
	sm.resize(arm_rim.size())
	for i in arm_rim.size():
		sm[i] = arm_rim[i] - c0
	var ring0 := ArmView._ring(arm_rim, sm, c0, depths[0], 1.0, 0.0)
	var ring1 := ArmView._ring(arm_rim, sm, c0, depths[1], 1.0, 0.0)
	print("ring depths: %.3f %.3f" % [depths[0], depths[1]])

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
		print("--- flex %.0f, hand down %s" % [flex, str(down)])
		# Four sides of the wrist: the indices are picked by their direction in
		# rest space, so the same points are compared at both flexions.
		var picks := {}
		for i in arm_rim.size():
			var v := Vector2(arm_rim[i].x - c0.x, arm_rim[i].z - c0.z)
			var a := atan2(v.y, v.x)
			for want in [["palmar", -PI / 2.0], ["dorsal", PI / 2.0],
					["radial", 0.0], ["ulnar", PI]]:
				var key: String = want[0]
				var da := absf(angle_difference(a, float(want[1])))
				if not picks.has(key) or da < float(picks[key][1]):
					picks[key] = [i, da]
		for key in picks:
			var i: int = int(picks[key][0])
			# Hand tangent: from the rim vertex to the closest vertex above it
			# in the same angular direction.
			var rr := arm_rim[i]
			var best := 1e9
			var hi := -1
			for j in verts.size():
				var dy := verts[j].y - ArmView.CUT_Y
				if dy < 2.0 or dy > 6.0:
					continue
				var dj := Vector2(verts[j].x - rr.x, verts[j].z - rr.z).length()
				if dj < best:
					best = dj
					hi = j
			var h0 := hp[rim_i[i]]
			var h1 := hp[hi]
			var th := (h1 - h0).normalized()
			var a0 := x0 * ring0[i]
			var a1 := x1 * ring1[i]
			var ta := (a1 - a0).normalized()
			var ang := 180.0 - rad_to_deg(th.angle_to(ta))
			var ah := 180.0 - rad_to_deg(th.angle_to(down))
			var aa := rad_to_deg(ta.angle_to(down))
			print("%-7s hand %s  arm %s  kink %5.2f°  hand-down %5.2f°  arm-down %5.2f°"
				% [key, str(th), str(ta), ang, ah, aa])
	quit(0)
