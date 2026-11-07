# Skinning for the hand study: one rest mesh, a skeleton of the phalanges, and
# per-vertex weights taken from the SDF primitives that built the surface.
#
# Why this module exists: the study so far had six BAKED meshes, one per pose.
# IK needs the surface to follow a pose that was never baked, so the rest mesh
# is deformed by a skeleton instead. The weights are not guessed from bones:
# every vertex of the marching-tetrahedra mesh lies on the union surface, so at
# that vertex every SDF primitive is at distance >= 0 and the primitives that
# actually form the surface are the ones at distance ~0. A soft minimum over
# those distances therefore says which part of the hand the vertex belongs to,
# and it blends exactly where the field blends — at the knuckle, at the joint
# crease, where the palm cone and the phalanx cone meet.
#
# The skeleton has one bone per phalanx (plus one for the palm). The bones are
# FLAT in the skeleton: each one's pose is its own frame in model space, which
# is exactly what the FK already gives us. No hierarchy to keep in sync, no
# rest-pose offsets to re-derive — G_pose * G_rest⁻¹ is the matrix of the bone.
extends RefCounted

const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")
const Sdf := preload("res://sdf.gd")

const TAU := 2.5              # mm, soft-min temperature for the weights
const MAX_W := 4
const CACHE := "res://cache/skin_weights.bin"
const CACHE_VERSION := 8      # bump when the weighting rule changes

const PALM := "palm"
# The seam's frame (arm_model.gd: wrist_blend). It owns the cut rim and fades
# into the palm over the wrist band, so the wrist bends through the skin
# instead of stopping at the border between two rigid halves.
const WRIST := "wrist"
# The band is a CHAIN of frames now, not one blend of two. Linear blending of
# two rigid frames D apart shrinks the surface by w1*w2*D^2/2: with the band's
# two ends half a wrist apart (35 degrees at 70 degrees of flexion) that is
# 4.6% of the radius in the middle of the band - 1.2 mm caved in on the palm
# side, which is exactly the sharp V the author sees. Spread the same travel
# over WRIST_SLICES small steps and let every vertex blend only two
# NEIGHBOURING frames: the shrink falls with the square of the step, to 0.13%.
# The chain's ends are the old two frames exactly (`wrist` at the rim, `palm`
# at the band's top), so nothing outside the band moves and the approved rest
# pose is untouched.
const WRIST_SLICES := 18
# The material weights (the palm's own SDF, the thenar under the thumb) fade in
# only near the top of the band, where the chain has already reached the palm.
# Fading them over the whole band would put the rigid palm next to a frame that
# is still close to the forearm at the bottom - the very two-frame blend the
# chain exists to avoid.
const WRIST_BASE_FADE := 0.55
# The band is not the same width all round the wrist. The skin on the back of
# the hand is tight: it has to follow the hand almost to the cut, or the whole
# back of the hand lags behind the wrist. The skin in the hollow of the palm is
# slack — at full flexion it folds instead of stretching — so its band is much
# wider. That is also the lever on the crease: the crease's apex sits ON the
# cut, where both walls are rigid, and only a band that stays near a half
# rotation for longer lets the surface follow the bisector far enough to round
# the corner. Moving the skin instead (a corrective bone) cannot do that: it
# moves a region of skin, not the apex, and reads as a beak over the crease.
const WRIST_PALM_H := 45.0


static func bone_names() -> Array:
	var names := [PALM]
	for ray in HandModel.FINGERS:
		names.append(ray + "_P")
		names.append(ray + "_M")
		names.append(ray + "_D")
	names.append("I_MC")
	names.append("I_P")
	names.append("I_D")
	names.append(WRIST)
	for i in range(1, WRIST_SLICES):
		names.append(wrist_slice(i))
	return names


static func wrist_slice(i: int) -> String:
	return "%s_%d" % [WRIST, i]


# The frame's place between the forearm (0) and the hand (1). The chain spans
# the band: the rim keeps WRIST_BLEND, the top of the band is the palm itself.
static func _slice_t(i: int) -> float:
	return ArmModel.WRIST_BLEND \
		+ (1.0 - ArmModel.WRIST_BLEND) * float(i) / float(WRIST_SLICES)


# The bone frames of a pose, in model space (millimetres):
#   {name, a, b, ref, xf} — ref is a vector perpendicular to the bone that
# fixes the twist of the frame. For a phalanx it is the hinge axis: the bone
# can only turn around it, so the frame has no made-up twist. The palm is the
# identity and is marked with a = b = ZERO. xf is the ARM transform: the hand
# is built in its own local space, and the arm moves that whole space. At rest
# xf is the identity, so the bind frames and the approved geometry are
# untouched; a posed arm simply carries every hand bone with it.
static func pose_bones(model: Object) -> Array:
	var arm_pose: Dictionary = model._pose.get("arm", {})
	var xf := ArmModel.hand_transform(arm_pose)
	var out := [{"name": PALM, "a": Vector3.ZERO, "b": Vector3.ZERO,
		"ref": Vector3.UP, "xf": xf}]
	for ray in HandModel.FINGERS:
		var fk := HandModel.finger_fk(ray, model._pose["fingers"][ray])
		var pts: PackedVector3Array = fk["pts"]
		var axis: Vector3 = fk["axis"]
		for j in 3:
			out.append({"name": ray + ["_P", "_M", "_D"][j],
				"a": pts[j], "b": pts[j + 1], "ref": axis, "xf": xf})
	var tfk := HandModel.thumb_fk(HandModel.thumb_of_pose(model._pose))
	var tp: PackedVector3Array = tfk["pts"]
	var palmar: Vector3 = tfk["palmar"]
	var taxis: Vector3 = (tfk["dirs"][0] as Vector3).cross(tfk["palm"]).normalized()
	out.append({"name": "I_MC", "a": tp[0], "b": tp[1], "ref": palmar, "xf": xf})
	out.append({"name": "I_P", "a": tp[1], "b": tp[2], "ref": taxis, "xf": xf})
	out.append({"name": "I_D", "a": tp[2], "b": tp[3], "ref": taxis, "xf": xf})
	# The wrist frame is not a phalanx: it is the seam's own transform, a
	# rotation between the forearm's and the hand's (arm_model.gd). The slices
	# above it continue that rotation to the palm in equal steps.
	out.append({"name": WRIST, "a": Vector3.ZERO, "b": Vector3.ZERO,
		"ref": Vector3.UP,
		"xf": ArmModel.wrist_blend(arm_pose, _slice_t(0))})
	for i in range(1, WRIST_SLICES):
		out.append({"name": wrist_slice(i), "a": Vector3.ZERO, "b": Vector3.ZERO,
			"ref": Vector3.UP,
			"xf": ArmModel.wrist_blend(arm_pose, _slice_t(i))})
	return out


static func frame_of(b: Dictionary) -> Transform3D:
	var xf: Transform3D = b.get("xf", Transform3D.IDENTITY)
	var name := str(b["name"])
	if name == PALM or name == WRIST or name.begins_with(WRIST + "_"):
		return xf
	var a: Vector3 = b["a"]
	var y := ((b["b"] as Vector3) - a).normalized()
	var ref: Vector3 = b["ref"]
	var x := ref - y * ref.dot(y)
	if x.length_squared() < 0.000000001:
		x = y.cross(Vector3.RIGHT)
		if x.length_squared() < 0.000000001:
			x = y.cross(Vector3.UP)
	x = x.normalized()
	return xf * Transform3D(Basis(x, y, x.cross(y)), a)


# ---- the primitives, tagged with the bone they belong to -------------
#
# The list mirrors HandModel.field() but is not the field: only the primitives
# that can own a vertex are here, each with a tag. The thenar is tagged to the
# thumb's metacarpal because the field itself rotates it with that bone.
static func primitives(m: Object) -> Array:
	var out := []
	out.append({"bone": PALM, "kind": "capsule_scaled", "a": HandModel.WRIST_A,
		"b": HandModel.WRIST_B, "ra": 25.0, "rb": 25.5, "s": Vector3(1, 1, 0.70)})
	out.append({"bone": PALM, "kind": "ellipsoid", "c": HandModel.CARPUS_C,
		"r": HandModel.CARPUS_R})
	for c in m._palm_cones:
		out.append({"bone": PALM, "kind": "capsule_scaled", "a": c[0], "b": c[1],
			"ra": float(c[2]), "rb": float(c[3]), "s": Vector3(1, 1, 1.12)})
	out.append({"bone": PALM, "kind": "ellipsoid", "c": Vector3(33, 56, 4),
		"r": Vector3(12, 18, 11)})
	out.append({"bone": "I_MC", "kind": "ellipsoid_oriented", "c": m._thenar_c,
		"r": HandModel.THENAR_R, "ax": m._thenar_ax})
	out.append({"bone": PALM, "kind": "ellipsoid", "c": HandModel.HYPOTH_C,
		"r": HandModel.HYPOTH_R})

	var thumb_bones := ["I_MC", "I_P", "I_D"]
	for i in 3:
		out.append({"bone": thumb_bones[i], "kind": "cone", "a": m._thumb_pts[i],
			"b": m._thumb_pts[i + 1], "ra": float(m._thumb_r[i]),
			"rb": float(m._thumb_r[i + 1])})

	var tags := ["_P", "_M", "_D"]
	for fi in HandModel.FINGERS.size():
		var ray: String = HandModel.FINGERS[fi]
		var skin: Dictionary = m._skins[fi]
		var pts: PackedVector3Array = skin["pts"]
		var rs: PackedFloat32Array = skin["rs"]
		for j in 3:
			out.append({"bone": ray + tags[j], "kind": "cone", "a": pts[j],
				"b": pts[j + 1], "ra": float(rs[j]), "rb": float(rs[j + 1])})
	return out


# A bone's finger: the four fingers are separate chains and the thumb is its
# own, so skin must never be carried by a neighbouring finger.
static func ray_of(bone: String) -> String:
	if bone == PALM:
		return PALM
	if bone.begins_with("I_"):
		return "I"
	return bone.substr(0, bone.find("_"))


static func _dist(pr: Dictionary, p: Vector3) -> float:
	match str(pr["kind"]):
		"cone":
			return Sdf.cone(p, pr["a"], pr["b"], float(pr["ra"]), float(pr["rb"]))
		"ellipsoid":
			return Sdf.ellipsoid(p, pr["c"], pr["r"])
		"ellipsoid_oriented":
			var ax: Array = pr["ax"]
			return Sdf.ellipsoid_oriented(p, pr["c"], pr["r"], ax[0], ax[1], ax[2])
		"capsule_scaled":
			return Sdf.capsule_scaled(p, pr["a"], pr["b"], float(pr["ra"]),
				float(pr["rb"]), pr["s"])
	return INF


# Per-vertex weights: a soft minimum over the primitive distances, summed per
# bone, top four kept and normalised. Vertices are on the union surface, so the
# winner is the primitive whose surface passes through them.
static func compute_weights(m: Object, verts: PackedVector3Array) -> Dictionary:
	var prs := primitives(m)
	var names := bone_names()
	var index_of := {}
	for i in names.size():
		index_of[names[i]] = i
	var idx := PackedInt32Array()
	var wts := PackedFloat32Array()
	idx.resize(verts.size() * MAX_W)
	wts.resize(verts.size() * MAX_W)
	var total := 0.0
	var worst_top := 1.0
	var worst_at := Vector3.ZERO
	for vi in verts.size():
		var p := verts[vi]
		var ds := []
		var d0 := INF
		for pr in prs:
			var d := _dist(pr, p)
			ds.append(d)
			if d < d0:
				d0 = d
		var by := {}
		for pi in prs.size():
			var w := exp(-(float(ds[pi]) - d0) / TAU)
			if w < 0.002:
				continue
			var bone: String = prs[pi]["bone"]
			by[bone] = float(by.get(bone, 0.0)) + w
		# A vertex belongs to ONE finger: where two fingers nearly touch the
		# field is a hard crease (a real interdigital fold), so the soft
		# minimum can hand one and the same vertex to both, and then curling
		# one finger drags the skin of its neighbour. The winner is the finger
		# with the most weight; the palm stays in every blend, because that is
		# the surface the fingers grow out of.
		var rayw := {}
		for b in by:
			var r := ray_of(str(b))
			if r != PALM:
				rayw[r] = float(rayw.get(r, 0.0)) + float(by[b])
		var win := ""
		var wbest := 0.0
		for r in rayw:
			if float(rayw[r]) > wbest:
				wbest = float(rayw[r])
				win = str(r)
		if win != "":
			for b in by.keys():
				var r := ray_of(str(b))
				if r != PALM and r != win:
					by.erase(b)
		var top := []
		for b in by:
			top.append([float(by[b]), str(b)])
		top.sort_custom(func(x, y): return float(x[0]) > float(y[0]))
		var sum := 0.0
		for t in top.slice(0, MAX_W):
			sum += float(t[0])
		var base := vi * MAX_W
		for j in MAX_W:
			if j < top.size() and j < MAX_W:
				var t: Array = top[j]
				idx[base + j] = int(index_of[t[1]])
				wts[base + j] = float(t[0]) / sum
			else:
				idx[base + j] = 0
				wts[base + j] = 0.0
		var topw := float(top[0][0]) / sum
		total += topw
		if topw < worst_top:
			worst_top = topw
			worst_at = p
	return {"indices": idx, "weights": wts, "mean_top": total / maxf(float(verts.size()), 1.0),
		"worst_top": worst_top, "worst_at": worst_at, "names": names}


static func load_or_compute(m: Object, verts: PackedVector3Array,
		mesh_path: String) -> Dictionary:
	var stamp := "v%d:%d:%d" % [CACHE_VERSION, verts.size(), FileAccess.get_modified_time(mesh_path)]
	if FileAccess.file_exists(CACHE):
		var f := FileAccess.open(CACHE, FileAccess.READ)
		var data = f.get_var()
		f.close()
		if typeof(data) == TYPE_DICTIONARY and str(data.get("stamp", "")) == stamp:
			return data
	var data := compute_weights(m, verts)
	data["stamp"] = stamp
	var f := FileAccess.open(CACHE, FileAccess.WRITE)
	if f != null:
		f.store_var(data)
		f.close()
	return data


# The wrist band: the hand's cut edge must be carried by the seam's frame, not
# by the palm alone. At the rim the arm's ring 0 is that frame; if the rim
# stayed rigid while the arm turned, the two skins would slide against each
# other and the wall above the rim would kink at the cut. The band walks from
# the wrist frame at the rim to the palm at `band_h` through the slice chain,
# so the bend is spread through the wrist instead of stopping at the border of
# two rigid halves — and, unlike a single two-frame blend, it does not shrink
# the surface at the middle of the band.
# It is applied AFTER the cached base weights, so the cache stays valid and
# the same rule works for any band height.
static func with_wrist_band(w: Dictionary, verts: PackedVector3Array,
		band_h: float) -> Dictionary:
	var names: Array = w["names"]
	var wi := names.find(WRIST)
	if wi < 0 or band_h <= 0.0:
		return w
	# The chain's frame index at each step: 0 is the wrist bone, WRIST_SLICES
	# is the palm itself.
	var chain := []
	for i in WRIST_SLICES + 1:
		if i == 0:
			chain.append(wi)
		elif i == WRIST_SLICES:
			chain.append(names.find(PALM))
		else:
			chain.append(names.find(wrist_slice(i)))
	for i in chain.size():
		if int(chain[i]) < 0:
			return w
	var y0 := INF
	for v in verts:
		y0 = minf(y0, v.y)
	# The rim's centre, for the palmar direction of the band. It is the same
	# centre the arm uses, measured from the rim itself.
	var c0 := Vector3.ZERO
	var n0 := 0
	for v in verts:
		if absf(v.y - y0) < 0.01:
			c0 += v
			n0 += 1
	if n0 > 0:
		c0 /= float(n0)
	var span := maxf(band_h, WRIST_PALM_H)
	var idx: PackedInt32Array = (w["indices"] as PackedInt32Array).duplicate()
	var wts: PackedFloat32Array = (w["weights"] as PackedFloat32Array).duplicate()
	for vi in verts.size():
		var dy := verts[vi].y - y0
		if dy > span:
			continue
		var bh := _band_at(verts[vi], c0, band_h)
		var s := 1.0
		if dy < bh:
			s = _smootherstep(clampf(dy / bh, 0.0, 1.0))
		var base := vi * MAX_W
		# The chain carries the rotation; the material weights come in only
		# near its top, where the chain's own frame is already the palm.
		var b := _smootherstep(clampf((s - WRIST_BASE_FADE)
			/ (1.0 - WRIST_BASE_FADE), 0.0, 1.0))
		var basel := []
		for j in MAX_W:
			var wt := wts[base + j]
			if wt > 0.000001 and b > 0.000001:
				basel.append([wt * b, int(idx[base + j])])
		basel.sort_custom(func(x, y): return float(x[0]) > float(y[0]))
		# Two of the four slots belong to the chain, so the material never
		# crowds it out: a dropped chain frame would be a visible step.
		var keep := []
		for j in mini(basel.size(), MAX_W - 2):
			keep.append(basel[j])
		var u := s * float(WRIST_SLICES)
		var i0 := clampi(int(floor(u)), 0, WRIST_SLICES - 1)
		var f := clampf(u - float(i0), 0.0, 1.0)
		keep.append([(1.0 - b) * (1.0 - f), int(chain[i0])])
		keep.append([(1.0 - b) * f, int(chain[i0 + 1])])
		keep.sort_custom(func(x, y): return float(x[0]) > float(y[0]))
		var sum := 0.0
		for j in MAX_W:
			if j < keep.size():
				sum += float(keep[j][0])
		for j in MAX_W:
			if j < keep.size() and sum > 0.000001:
				idx[base + j] = int(keep[j][1])
				wts[base + j] = float(keep[j][0]) / sum
			else:
				idx[base + j] = 0
				wts[base + j] = 0.0
	var out := w.duplicate()
	out["indices"] = idx
	out["weights"] = wts
	return out


# The band's height at a point: the full width in the hollow of the palm, the
# base width on the back of the hand, blended by the palmar measure below.
static func _band_at(p: Vector3, c0: Vector3, band_h: float) -> float:
	if WRIST_PALM_H <= band_h:
		return band_h
	return lerpf(band_h, WRIST_PALM_H, _palmar(p, c0))


# How palmar a point is: 1 at the middle of the palm's hollow, 0 on the back of
# the hand, with a zero-slope fade at both ends.
static func _palmar(p: Vector3, c0: Vector3) -> float:
	var r := Vector2(p.x - c0.x, p.z - c0.z).length()
	if r < 0.001:
		return 0.0
	var u := clampf(-(p.z - c0.z) / r, 0.0, 1.0)
	return _smootherstep(clampf((u - 0.10) / 0.80, 0.0, 1.0))


# Quintic ease with zero first AND second derivative at both ends, so the
# wrist band joins the rigid palm without a curvature step.
static func _smootherstep(t: float) -> float:
	var u := clampf(t, 0.0, 1.0)
	return u * u * u * (u * (u * 6.0 - 15.0) + 10.0)


# ---- skeleton and skinned mesh ---------------------------------------
#
# The rig is built from the REST model and the REST mesh. Every later pose only
# sets the bone poses; the mesh, weights and binds stay put.
static func build(rest_model: Object, src: ArrayMesh, mesh_path: String,
		band_h := 0.0) -> Dictionary:
	var arrays: Array = src.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var w := load_or_compute(rest_model, verts, mesh_path)
	if band_h > 0.0:
		w = with_wrist_band(w, verts, band_h)

	var names: Array = w["names"]
	var skel := Skeleton3D.new()
	skel.name = "Skeleton3D"
	var frames := []
	var defs := pose_bones(rest_model)
	var by_name := {}
	for b in defs:
		by_name[str(b["name"])] = b
	for i in names.size():
		skel.add_bone(str(names[i]))
	for i in names.size():
		var f := frame_of(by_name[str(names[i])])
		frames.append(f)
		skel.set_bone_rest(i, f)
		skel.set_bone_pose(i, f)

	var skin := Skin.new()
	skin.set_bind_count(names.size())
	for i in names.size():
		skin.set_bind_name(i, StringName(str(names[i])))
		skin.set_bind_pose(i, (frames[i] as Transform3D).affine_inverse())

	arrays[Mesh.ARRAY_BONES] = w["indices"]
	arrays[Mesh.ARRAY_WEIGHTS] = w["weights"]
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var mi := MeshInstance3D.new()
	mi.name = "Skin"
	mi.mesh = mesh
	mi.skin = skin
	return {"skeleton": skel, "instance": mi, "weights": w, "names": names,
		"rest_frames": frames, "rest_model": rest_model}


# Call after both nodes are in the tree (the path is resolved by the instance).
static func wire(rig: Dictionary) -> void:
	var mi: MeshInstance3D = rig["instance"]
	mi.skeleton = mi.get_path_to(rig["skeleton"])


static func apply_pose(rig: Dictionary, model: Object) -> void:
	var skel: Skeleton3D = rig["skeleton"]
	var names: Array = rig["names"]
	var defs := pose_bones(model)
	var by_name := {}
	for b in defs:
		by_name[str(b["name"])] = b
	for i in names.size():
		skel.set_bone_pose(i, frame_of(by_name[str(names[i])]))
	# Bone globals are cached and usually refreshed on the next frame; a test
	# that reads them (or a driver that shoots on this very frame) needs them
	# now.
	skel.force_update_all_bone_transforms()


# CPU linear blend skinning over the same weights: the verification path. The
# viewer uses the GPU; this is what skin_test compares against the SDF.
static func cpu_positions(rig: Dictionary, model: Object) -> PackedVector3Array:
	var rest: Object = rig["rest_model"]
	var rest_defs := pose_bones(rest)
	var pose_defs := pose_bones(model)
	var rest_by := {}
	var pose_by := {}
	for b in rest_defs:
		rest_by[str(b["name"])] = frame_of(b)
	for b in pose_defs:
		pose_by[str(b["name"])] = frame_of(b)
	var names: Array = rig["names"]
	var mats := []
	for n in names:
		var g0: Transform3D = rest_by[str(n)]
		var gp: Transform3D = pose_by[str(n)]
		mats.append(gp * g0.affine_inverse())
	var w: Dictionary = rig["weights"]
	var idx: PackedInt32Array = w["indices"]
	var wts: PackedFloat32Array = w["weights"]
	var mesh: ArrayMesh = rig["instance"].mesh
	var src := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = src[Mesh.ARRAY_VERTEX]
	var out := PackedVector3Array()
	out.resize(verts.size())
	for vi in verts.size():
		var p := verts[vi]
		var q := Vector3.ZERO
		var base := vi * MAX_W
		for j in MAX_W:
			var weight := wts[base + j]
			if weight <= 0.0:
				continue
			q += (mats[idx[base + j]] as Transform3D) * p * weight
		out[vi] = q
	return out
