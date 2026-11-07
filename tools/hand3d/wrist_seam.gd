# Measures the wrist seam numerically: the hand's cut rim and the arm's first
# loft ring are supposed to be ONE edge. If they drift apart under a bend, the
# seam opens a crack; if the hand's rim vertices are not carried by the seam's
# wrist frame alone, the two skins slide against each other. Headless:
#   mbt-godot --headless --path /work/tools/hand3d --script res://wrist_seam.gd
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")
const SkinRig := preload("res://skin_rig.gd")
const ArmView := preload("res://arm_view.gd")
const Viewer := preload("res://viewer.gd")

const REST_MESH := "res://cache/skin_curled_rest.res"

const POSES := [
	["rest", 0.0, 0.0, 0.0],
	["flex55", 55.0, 0.0, 0.0],
	["flex70", 70.0, 0.0, 0.0],
	["pron+70", 0.0, 0.0, 70.0],
	["flex55-pron40", 55.0, 0.0, 40.0],
	["flex55-dev25", 55.0, 25.0, 0.0],
]

var _fails := 0


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
	# The cap is not a bare polygon: it has interior vertices, and those sit on
	# the cut plane too. Only the boundary loop is the seam, so the hand's rim
	# vertices are found as the mesh vertices that landed on the arm's ring.
	var rim := []
	var unmatched := 0
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
		if bi < 0 or best > 0.05:
			unmatched += 1
			continue
		rim.append(bi)
	print("rim: %d of %d ring points matched, %d unmatched" % [rim.size(),
		arm_rim.size(), unmatched])
	var names: Array = rig["names"]
	var wrist := names.find("wrist")
	var idx: PackedInt32Array = rig["weights"]["indices"]
	var wts: PackedFloat32Array = rig["weights"]["weights"]
	var worst_wrist := 1.0
	var worst_at := Vector3.ZERO
	for i in rim:
		var ww := 0.0
		for j in 4:
			if idx[i * 4 + j] == wrist:
				ww += wts[i * 4 + j]
		if ww < worst_wrist:
			worst_wrist = ww
			worst_at = verts[i]
	print("rim: %d vertices, worst wrist weight %.4f at %s" % [rim.size(),
		worst_wrist, str(worst_at)])
	if worst_wrist < 0.999:
		_fails += 1
		print("FAIL: a rim vertex is not carried by the wrist frame alone")

	# The band's profile, on a synthetic ring: it must walk from the seam's
	# frame at the rim to the palm at the band's end, monotonically, with zero
	# slope at both ends — a linear band would leave a slope step where it meets
	# the rigid rim and the rigid palm. The ring also holds the other half of
	# the rule: the band is wider in the hollow of the palm than on the back of
	# the hand (skin_rig.gd: WRIST_PALM_H), so the palmar column reaches the
	# palm further up than the dorsal one.
	#
	# The measure is not the weight of one bone any more: the band is a CHAIN of
	# frames (skin_rig.gd: WRIST_SLICES), and what must be checked is the thing
	# the chain exists for — the blended matrix must stay a rotation. Two frames
	# 35 degrees apart, blended 50/50, scale the surface by cos(17.5) = 0.954,
	# and that cave-in is the sharp V on the palm side. The radial scale of the
	# blended matrix is therefore measured directly, at full flexion.
	var heights := [0.0, 1.5, 7.5, 15.0, 22.5, 28.5, 30.0, 37.5, 43.5, 45.0]
	var n_ang := 16
	var ring := PackedVector3Array()
	for y in heights:
		for k in n_ang:
			var a := TAU * float(k) / float(n_ang)
			ring.append(Vector3(cos(a) * 20.0, float(y), sin(a) * 20.0))
	var all_names: Array = SkinRig.bone_names()
	var palm_i := all_names.find("palm")
	var wrist_i := all_names.find("wrist")
	var ring_idx := PackedInt32Array()
	var ring_wts := PackedFloat32Array()
	for i in ring.size():
		ring_idx.append_array(PackedInt32Array([palm_i, palm_i, palm_i, palm_i]))
		ring_wts.append_array(PackedFloat32Array([1.0, 0.0, 0.0, 0.0]))
	var base := {"names": all_names, "indices": ring_idx, "weights": ring_wts}
	var banded := SkinRig.with_wrist_band(base, ring, Viewer.WRIST_FLAT_H)
	var bidx: PackedInt32Array = banded["indices"]
	var bwts: PackedFloat32Array = banded["weights"]

	var flexed := HandModel.rest_pose()
	flexed["arm"]["wrist_flex"] = 70.0
	var pm := HandModel.new(1.0, 0.0, flexed)
	var defs := SkinRig.pose_bones(pm)
	var by_name := {}
	for b in defs:
		by_name[str(b["name"])] = SkinRig.frame_of(b)
	var fore := ArmModel.frames(flexed["arm"])
	var fore_dir: Vector3 = (fore["r_fore"] as Basis) * Vector3.UP
	var palm_dir: Vector3 = (fore["r_wrist"] as Basis) * Vector3.UP
	var total := fore_dir.angle_to(palm_dir)

	# k = 12 is the palmar-most column (z = -20), k = 4 the dorsal-most.
	var prof := {}
	var worst_scale := 1.0
	var worst_scale_at := ""
	for side in [[12, "palmar"], [4, "dorsal"]]:
		var k: int = side[0]
		var name: String = side[1]
		var prev_a := -1.0
		var profile := []
		var scales := []
		for hi in heights.size():
			var i: int = hi * n_ang + k
			var mx := Vector3.ZERO
			var my := Vector3.ZERO
			var mz := Vector3.ZERO
			var ww := 0.0
			for j in 4:
				var b := int(bidx[i * 4 + j])
				var wt := bwts[i * 4 + j]
				if wt <= 0.000001:
					continue
				var bb: Basis = (by_name[str(all_names[b])] as Transform3D).basis
				mx += bb.x * wt
				my += bb.y * wt
				mz += bb.z * wt
				if b == wrist_i:
					ww += wt
			var m := Basis(mx, my, mz)
			var a := TAU * float(k) / float(n_ang)
			var radial := Vector3(cos(a), 0.0, sin(a))
			var sc := (m * radial).length()
			if sc < worst_scale:
				worst_scale = sc
				worst_scale_at = "%s %.1f mm" % [name, float(heights[hi])]
			scales.append(sc)
			var ang := (m * Vector3.UP).angle_to(fore_dir)
			profile.append(ang)
			if ang < prev_a - 0.0001:
				_fails += 1
				print("FAIL: the %s band is not monotonic at %.1f mm" % [
					name, float(heights[hi])])
			prev_a = ang
			if hi == 0:
				# The rim is the seam's frame alone, or the two skins slide.
				if absf(ww - 1.0) > 0.001:
					_fails += 1
					print("FAIL: the %s band does not start at the wrist" % name)
		prof[name] = profile
		print("%s band: angle %s" % [name, str(profile)])
		print("%s band: radial scale %s" % [name, str(scales)])
		# Zero slope at the rim: the first step is a tiny fraction of the
		# band's whole travel (the smootherstep's cubic start).
		if float(profile[1]) - float(profile[0]) > 0.12 * total:
			_fails += 1
			print("FAIL: the %s band has a slope step at the rim" % name)
	var dprof: Array = prof["dorsal"]
	var pprof: Array = prof["palmar"]
	if absf(float(dprof[6]) - total) > 0.001:
		_fails += 1
		print("FAIL: the dorsal band does not reach the palm at WRIST_FLAT_H")
	if absf(float(pprof[-1]) - total) > 0.001:
		_fails += 1
		print("FAIL: the palmar band does not reach the palm at WRIST_PALM_H")
	if (total - float(pprof[3])) < (total - float(dprof[3])) + 0.05 * total:
		_fails += 1
		print("FAIL: the palmar band is not wider than the dorsal one")
	# The whole point of the chain: the blended matrix stays a rotation. Two
	# frames (the old rule) give cos(17.5) = 0.954 at full flexion.
	if worst_scale < 0.995:
		_fails += 1
		print("FAIL: the band scales the skin to %.4f at %s" % [
			worst_scale, worst_scale_at])
	print("band: worst radial scale %.4f (%s), full flexion %.1f deg" % [
		worst_scale, worst_scale_at, rad_to_deg(total)])

	print("arm ring 0: %d vertices" % arm_rim.size())

	for pose in POSES:
		var p := HandModel.rest_pose()
		p["arm"]["wrist_flex"] = float(pose[1])
		p["arm"]["wrist_dev"] = float(pose[2])
		p["arm"]["pronation"] = float(pose[3])
		var model := HandModel.new(1.0, 0.0, p)
		var hp := SkinRig.cpu_positions(rig, model)

		var xf := ArmModel.wrist_blend(p["arm"], ArmModel.WRIST_BLEND)
		var ap := PackedVector3Array()
		for q in arm_rim:
			ap.append(xf * q)

		var dmax := 0.0
		for i in rim:
			var q := hp[i]
			var best := 1e9
			for r in ap:
				best = minf(best, q.distance_to(r))
			dmax = maxf(dmax, best)
		for r in ap:
			var best := 1e9
			for i in rim:
				best = minf(best, r.distance_to(hp[i]))
			dmax = maxf(dmax, best)
		print("pose %-14s seam max gap %.4f mm" % [pose[0], dmax])
		if dmax > 0.01:
			_fails += 1
			print("FAIL: the seam opens %.3f mm at %s" % [dmax, pose[0]])

	print("wrist_seam: %d failed" % _fails)
	quit(1 if _fails > 0 else 0)
