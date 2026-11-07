# Checks the skinning against the thing it must reproduce: the SDF.
#
# The rest mesh is the surface of the curled hand. If the weights are right,
# then deforming that mesh with the skeleton of a pose lands every vertex
# back on the surface of the SDF of the same pose. That is a direct, absolute
# check — it does not compare the rig against itself, so a wrong weight or a
# wrong bone frame cannot hide.
#
# Four claims:
#   · the rest pose is reproduced exactly (the rig is identity there);
#   · straight / thumb-press / IK poses land on their SDF surfaces;
#   · the weights are sane: every vertex has a clear owner, no vertex is
#     owned by a bone it is far from, and posing one finger does not drag
#     the neighbours (the fingers are separate chains, and the skin between
#     them must stay put);
#   · the cache round-trips, and the GPU formula (bone global × bind) is the
#     same arithmetic as the CPU check used here.
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")
const SkinRig := preload("res://skin_rig.gd")
const IK := preload("res://ik.gd")

const REST_MESH := "res://cache/skin_curled_rest.res"

var _checks := 0
var _fails := 0
var _rig: Dictionary
var _idx: PackedInt32Array
var _names: Array


func _init() -> void:
	var t0 := Time.get_ticks_msec()
	var src: ArrayMesh = load(REST_MESH)
	if src == null:
		print("FAIL: no rest mesh at ", REST_MESH)
		quit(1)
		return
	var rest := HandModel.new(1.0, 0.0)

	var had_cache := FileAccess.file_exists(SkinRig.CACHE)
	if had_cache:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SkinRig.CACHE))
	_rig = SkinRig.build(rest, src, REST_MESH)
	var t_build := Time.get_ticks_msec() - t0

	print("== rig")
	var w: Dictionary = _rig["weights"]
	if _idx.is_empty():
		_idx = w["indices"]
		_names = _rig["names"]
	var verts := (src.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array)
	print("   %d verts, %d bones, weights %.1f s (%s), mean top %.3f, worst top %.3f at %s" % [
		verts.size(), (_rig["names"] as Array).size(), t_build / 1000.0,
		"recomputed after dropping the cache" if had_cache else "computed", float(w["mean_top"]),
		float(w["worst_top"]), str(w["worst_at"])])
	_ck(verts.size() > 40000, "rest mesh has only %d vertices" % verts.size())

	# The cache must come back the same, not recomputed into something else.
	t0 = Time.get_ticks_msec()
	var rig2 := SkinRig.build(rest, src, REST_MESH)
	var t_load := Time.get_ticks_msec() - t0
	var w2: Dictionary = rig2["weights"]
	_ck((w["indices"] as PackedInt32Array) == (w2["indices"] as PackedInt32Array),
		"cache round-trip changed the bone indices")
	_ck((w["weights"] as PackedFloat32Array) == (w2["weights"] as PackedFloat32Array),
		"cache round-trip changed the weights")
	_ck(t_load < maxi(2000, t_build / 2), "cache load %.1f s vs build %.1f s — not a cache" % [
		t_load / 1000.0, t_build / 1000.0])
	print("   cache: %.2f s load against %.1f s build" % [t_load / 1000.0, t_build / 1000.0])

	_test_rest(rest, verts)
	_test_poses(rest)
	_test_weights(rest, verts)
	_test_isolation(rest, verts)
	_test_skeleton_frames(rest)

	print("skin_test: %d checks, %d failed" % [_checks, _fails])
	quit(1 if _fails > 0 else 0)


func _ck(ok: bool, msg: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
		print("FAIL: ", msg)


func _bone_of_ray(name: String) -> String:
	return SkinRig.ray_of(name)


func _field_stats(model: Object, pts: PackedVector3Array) -> Dictionary:
	# The SDF lives in hand-local space, while cpu_positions returns the posed
	# hand in the arm's space. The arm transform is rigid over the whole hand,
	# so the surface check maps the points back before asking the field.
	var xf := ArmModel.hand_transform(model._pose.get("arm", {}))
	var inv := xf.affine_inverse()
	var errs := PackedFloat32Array()
	errs.resize(pts.size())
	var sum := 0.0
	var mx := 0.0
	var mx_at := Vector3.ZERO
	var over2 := 0
	var by_ray := {}
	for i in pts.size():
		var local := inv * pts[i]
		var d := absf(model.field(local))
		errs[i] = d
		sum += d
		if d > 2.0:
			over2 += 1
		if d > mx:
			mx = d
			mx_at = pts[i]
		if not _names.is_empty():
			var ray := SkinRig.ray_of(str(_names[_idx[i * SkinRig.MAX_W]]))
			var cur: Array = by_ray.get(ray, [0.0, 0.0])
			cur[0] = float(cur[0]) + d
			if d > float(cur[1]):
				cur[1] = d
			by_ray[ray] = cur
	errs.sort()
	var p95 := errs[int(errs.size() * 0.95)] if errs.size() > 0 else 0.0
	var rays := []
	for r in by_ray:
		rays.append([float(by_ray[r][1]), str(r), float(by_ray[r][0]) / maxf(1.0, pts.size())])
	rays.sort_custom(func(x, y): return float(x[0]) > float(y[0]))
	return {"mean": sum / maxf(float(pts.size()), 1.0), "p95": p95, "max": mx,
		"max_at": mx_at, "over2": float(over2) / maxf(float(pts.size()), 1.0),
		"by_ray": rays.slice(0, 2)}


func _report(msg: String, s: Dictionary) -> void:
	print("   %s: mean %.3f, p95 %.3f, max %.3f mm at %s, %.2f%% over 2 mm" % [
		msg, float(s["mean"]), float(s["p95"]), float(s["max"]),
		str(s["max_at"]), float(s["over2"]) * 100.0])
	var parts := []
	for r in s.get("by_ray", []):
		parts.append("%s max %.2f (mean %.3f)" % [str(r[1]), float(r[0]), float(r[2])])
	if not parts.is_empty():
		print("      by owner: ", ", ".join(parts))


# The rig must be the identity at rest: the rest mesh already IS the rest
# surface, so any movement at all is a bug in the bind or the frames.
func _test_rest(rest: Object, verts: PackedVector3Array) -> void:
	print("== rest")
	var pts := SkinRig.cpu_positions(_rig, rest)
	var mx := 0.0
	for i in verts.size():
		mx = maxf(mx, verts[i].distance_to(pts[i]))
	_ck(mx < 0.001, "rest pose moved a vertex by %.4f mm" % mx)
	var fs := _field_stats(rest, verts)
	_report("rest", fs)
	# The mesh is a linear interpolation of the field on a 2 mm grid, so a
	# vertex already sits a little off the true surface before any posing;
	# that baseline is the mesh's, not the rig's.
	_ck(float(fs["max"]) < 1.2, "rest mesh is %.3f mm off its own field" % float(fs["max"]))
	print("   rest: largest vertex move %.6f mm" % mx)


# Poses that were never baked: the straight fingers, the pressing thumb, and
# an IK solution. Each must land on its own SDF.
func _test_poses(rest: Object) -> void:
	print("== poses")
	var poses := {}
	poses["straight"] = HandModel.new(0.0, 0.0)
	poses["thumb press"] = HandModel.new(1.0, float(HandModel.POSE_THUMBS["press"]))

	# An IK pose: II and IV reach forward targets, V straightens part way.
	var p := HandModel.rest_pose()
	var t2 := HandModel.finger_pad("II", HandModel.finger_fk("II",
		IK.angles_of_shares("II", [0.55, 0.55, 0.55, 1.0])))
	var r2 := IK.solve_finger("II", t2, p)
	p = r2["pose"]
	var t4 := HandModel.finger_pad("IV", HandModel.finger_fk("IV",
		IK.angles_of_shares("IV", [-0.35, -0.35, -0.35, -1.0])))
	var r4 := IK.solve_finger("IV", t4, p)
	p = r4["pose"]
	p["thumb_f"] = 0.25
	poses["IK"] = HandModel.new(1.0, 0.0, p)
	poses["IK: only II"] = HandModel.new(1.0, 0.0, r2["pose"])

	# The hierarchy moves the whole hand with the arm. The skin must ride that
	# rigid transform without a dent: the surface check maps the posed points
	# back into hand-local space, so this pose proves the xf path of the rig.
	var arm := IK.solve_chain("II", Vector3(0, -80, -80), HandModel.rest_pose(),
		{"arm": true})
	poses["IK + arm"] = HandModel.new(1.0, 0.0, arm["pose"])

	for name in poses:
		var model: Object = poses[name]
		var pts := SkinRig.cpu_positions(_rig, model)
		var fs := _field_stats(model, pts)
		_report(name, fs)
		# The grid is 2 mm, so a vertex may sit up to ~0.3 mm off the true
		# surface before any posing; a pose adds the blend error at the
		# creases. Anything above 2 mm is a visible dent or spike.
		_ck(float(fs["mean"]) < 0.8, "%s: mean surface error %.3f mm" % [name, float(fs["mean"])])
		_ck(float(fs["p95"]) < 1.6, "%s: p95 surface error %.3f mm" % [name, float(fs["p95"])])
		_ck(float(fs["max"]) < 3.5, "%s: worst surface error %.3f mm" % [name, float(fs["max"])])
		_ck(float(fs["over2"]) < 0.02, "%s: %.2f%% of the vertices are over 2 mm off" % [
			name, float(fs["over2"]) * 100.0])


# Weight sanity, measured against the geometry the weights claim to know:
# the distance from the vertex to each bone.
func _test_weights(rest: Object, verts: PackedVector3Array) -> void:
	print("== weights")
	var w: Dictionary = _rig["weights"]
	var idx: PackedInt32Array = w["indices"]
	var wts: PackedFloat32Array = w["weights"]
	var names: Array = _rig["names"]

	# Bone segments of the rest pose, for the distance test.
	var segs := {}
	var defs := SkinRig.pose_bones(rest)
	for b in defs:
		if str(b["name"]) == "palm":
			continue
		segs[str(b["name"])] = [b["a"], b["b"]]

	var worst_top := 1.0
	var worst_owner := 0.0
	var worst_owner_at := Vector3.ZERO
	var worst_leak := 0.0
	var worst_leak_at := Vector3.ZERO
	var bad_sum := 0
	for vi in verts.size():
		var p := verts[vi]
		var base := vi * SkinRig.MAX_W
		var top := float(wts[base])
		worst_top = minf(worst_top, top)
		var total := 0.0
		for j in SkinRig.MAX_W:
			total += wts[base + j]
		if absf(total - 1.0) > 0.002:
			bad_sum += 1
		var top_bone: String = names[idx[base]]
		if top_bone == "palm":
			continue
		var seg: Array = segs[top_bone]
		var d_top := _seg_dist(p, seg[0], seg[1])
		var d_min := INF
		for other in segs:
			d_min = minf(d_min, _seg_dist(p, segs[other][0], segs[other][1]))
		if d_top - d_min > worst_owner:
			worst_owner = d_top - d_min
			worst_owner_at = p

		# Cross-finger leak: a vertex owned by one finger must not be
		# carried by another finger's bones.
		var ray := _bone_of_ray(top_bone)
		if ray == "palm":
			continue
		var leak := 0.0
		for j in SkinRig.MAX_W:
			var wn := float(wts[base + j])
			if wn <= 0.0:
				continue
			var r2 := _bone_of_ray(names[idx[base + j]])
			if r2 != ray and r2 != "palm":
				leak += wn
		if leak > worst_leak:
			worst_leak = leak
			worst_leak_at = p

	print("   worst top weight %.3f, worst foreign-finger weight %.3f at %s" % [
		worst_top, worst_leak, str(worst_leak_at)])
	print("   worst owner is %.2f mm farther than the nearest bone at %s" % [
		worst_owner, str(worst_owner_at)])
	_ck(worst_top > 0.20, "a vertex has almost no owner: top weight %.3f" % worst_top)
	_ck(worst_owner < 4.0, "a vertex is owned by a bone %.2f mm farther than the nearest" % worst_owner)
	_ck(worst_leak < 0.15, "a vertex is carried %.3f by another finger" % worst_leak)
	_ck(bad_sum == 0, "%d vertices have weights that do not sum to one" % bad_sum)


func _seg_dist(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 < 0.000001:
		return p.distance_to(a)
	return p.distance_to(a + ab * clampf((p - a).dot(ab) / l2, 0.0, 1.0))


# Posing one finger must not drag the others: their vertices are carried by
# their own bones, and the palm takes only what it always takes.
func _test_isolation(rest: Object, verts: PackedVector3Array) -> void:
	print("== isolation")
	var p := HandModel.rest_pose()
	var target := HandModel.finger_pad("II", HandModel.finger_fk("II",
		IK.angles_of_shares("II", [0.6, 0.6, 0.6, 1.0])))
	var r := IK.solve_finger("II", target, p)
	var model := HandModel.new(1.0, 0.0, r["pose"])
	var pts := SkinRig.cpu_positions(_rig, model)

	var w: Dictionary = _rig["weights"]
	var idx: PackedInt32Array = w["indices"]
	var names: Array = _rig["names"]
	var worst := 0.0
	var worst_at := Vector3.ZERO
	var moved := 0
	for vi in verts.size():
		var top_bone: String = names[idx[vi * SkinRig.MAX_W]]
		var ray := _bone_of_ray(top_bone)
		if ray == "II" or ray == "palm":
			continue
		var d := verts[vi].distance_to(pts[vi])
		if d > 0.05:
			moved += 1
		if d > worst:
			worst = d
			worst_at = verts[vi]
	print("   finger II curled: other fingers move at most %.3f mm (%d verts over 0.05 mm)" % [
		worst, moved])
	_ck(worst < 0.5, "curling II moved a neighbour finger by %.2f mm at %s" % [worst, str(worst_at)])


# The CPU check above uses pose × rest⁻¹. The GPU path uses the skeleton's
# global pose × bind. For flat bones Godot's global pose IS the pose frame,
# so the two formulas must agree — and the frames must come out of the
# skeleton exactly as FK computed them.
func _test_skeleton_frames(rest: Object) -> void:
	print("== skeleton")
	var skel: Skeleton3D = _rig["skeleton"]
	var mi: MeshInstance3D = _rig["instance"]
	root.add_child(skel)
	root.add_child(mi)
	SkinRig.wire(_rig)
	_ck(mi.skeleton == mi.get_path_to(skel), "the mesh does not point at its skeleton")

	# At the rest pose, GPU arithmetic (global × bind) must be the identity.
	var names: Array = _rig["names"]
	var skin: Skin = mi.skin
	_ck(skin != null, "the mesh has no skin")
	SkinRig.apply_pose(_rig, rest)
	var worst_rest := 0.0
	for i in names.size():
		var x := skel.get_bone_global_pose(i) * skin.get_bind_pose(i)
		worst_rest = maxf(worst_rest, x.origin.length())
		worst_rest = maxf(worst_rest, (x.basis.x - Vector3.RIGHT).length())
		worst_rest = maxf(worst_rest, (x.basis.z - Vector3.BACK).length())
	_ck(worst_rest < 0.01, "at rest the GPU matrix is %.3f mm off the identity" % worst_rest)

	# Posed: the skeleton's matrices must equal the ones cpu_positions used.
	var model := HandModel.new(0.0, 0.0)
	var worst := _frame_error(model, skel, skin, names, rest)
	_ck(worst < 0.01, "skeleton frames drift %.3f mm from the FK frames" % worst)

	# The same with the arm: xf must ride through the skeleton exactly as it
	# rides through cpu_positions, or the GPU hand would detach from the arm.
	var arm := IK.solve_chain("II", Vector3(0, -80, -80), HandModel.rest_pose(),
		{"arm": true})
	var arm_model := HandModel.new(1.0, 0.0, arm["pose"])
	var worst_arm := _frame_error(arm_model, skel, skin, names, rest)
	_ck(worst_arm < 0.01, "arm skeleton frames drift %.3f mm from the FK frames" % worst_arm)
	print("   %d bones, rest bind %.5f mm, posed matrices agree with CPU within %.5f (arm %.5f)" % [
		names.size(), worst_rest, worst, worst_arm])


func _frame_error(model: Object, skel: Skeleton3D, skin: Skin, names: Array,
		rest: Object) -> float:
	SkinRig.apply_pose(_rig, model)
	var by := {}
	for b in SkinRig.pose_bones(model):
		by[str(b["name"])] = SkinRig.frame_of(b)
	var rest_by := {}
	for b in SkinRig.pose_bones(rest):
		rest_by[str(b["name"])] = SkinRig.frame_of(b)
	var worst := 0.0
	for i in names.size():
		var g := skel.get_bone_global_pose(i)
		var want: Transform3D = by[str(names[i])]
		worst = maxf(worst, (g.origin - want.origin).length())
		var gpu := g * skin.get_bind_pose(i)
		var cpu: Transform3D = want * (rest_by[str(names[i])] as Transform3D).affine_inverse()
		worst = maxf(worst, (gpu.origin - cpu.origin).length())
		for ax in 3:
			worst = maxf(worst, ((gpu.basis[ax] as Vector3) - (cpu.basis[ax] as Vector3)).length())
	return worst
