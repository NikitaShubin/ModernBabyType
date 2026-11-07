# The visible forearm of the hand study: a distal forearm from the hand's own
# cut to a rounded elbow stump. Built once; the skin is one bone per loft ring,
# each ring carried rigidly by its own frame (the same pattern as bone_view.gd's
# live hand bones).
#
# The author (28.10.2026): "кожа предплечья приделана к кисти грубо — со
# швами"; "Руку делать достаточно до локтя. Плечё не нужно." So the forearm is
# not a capsule stuck onto the wrist: it is a LOFT that starts at the hand's own
# (smoothed) cut contour and shares the seam's blended frame with the hand's
# weight band. There is no collar: the band and the vertical wall hold the seam.
#
# There is no upper arm and no shoulder. The elbow is the fixed root of the
# chain (arm_model.gd), so the tube ends in a rounded stump there; the radius,
# the ulna and the elbow ball are drawn as separate rigid parts.
extends RefCounted

const ArmModel := preload("res://arm_model.gd")
const HandModel := preload("res://hand_model.gd")

const SCALE := 0.001
const SKIN_COLOR := "#cb9077"
const BONE_COLOR := "#f1e7d2"
const JOINT_COLOR := "#e6d9bd"

const CUT_Y := -1.5            # the hand's flat cut, mm
const TUBE_L := 150
# The wrist bend lives in this stretch below the cut; beyond it the forearm is
# rigid, as a real one is between the wrist crease and the elbow. Bending the
# whole 150 mm tube made the forearm look like rubber.
const BEND_L := 35
const CAP_L := 30.0            # rounded stump at the elbow
const RINGS := 55              # rings from the cut to the cap's start (see ring_depths)
const CAP_RINGS := 7           # rings over the rounded stump
const COLLAR_IN := 2.2         # mm below the cut: the collar would be at full width
const COLLAR_OUT := 0.0        # disabled: the weight band and the vertical wall hold the seam
const COLLAR_L := 14.0         # mm below the cut: the collar would be gone

static func build(src: ArrayMesh, model: Object = null) -> Dictionary:
	var root := Node3D.new()
	root.name = "Arm"
	root.scale = Vector3.ONE * SCALE

	var skin_root := Node3D.new()
	skin_root.name = "ArmSkin"
	root.add_child(skin_root)
	var bone_root := Node3D.new()
	bone_root.name = "ArmBones"
	root.add_child(bone_root)

	var skin_mat := StandardMaterial3D.new()
	skin_mat.albedo_color = Color(SKIN_COLOR)
	skin_mat.roughness = 0.78
	skin_mat.metallic_specular = 0.14
	skin_mat.rim_enabled = true
	skin_mat.rim = 0.07
	skin_mat.rim_tint = 0.6

	var bone_mat := StandardMaterial3D.new()
	bone_mat.albedo_color = Color(BONE_COLOR)
	bone_mat.roughness = 0.55
	var joint_mat := StandardMaterial3D.new()
	joint_mat.albedo_color = Color(JOINT_COLOR)
	joint_mat.roughness = 0.7

	var rim := _cut_rim(src)
	if rim.size() < 3:
		push_error("arm_view: не нашёл контур среза кисти (y %.1f)" % CUT_Y)
		rim = _fallback_rim()
	# The mesh's rim is NOT the wrist's contour: the cut lies between two grid
	# rows, so the field below the upper row is clamped by the cut and the rim
	# lands on the last grid column that is still inside — up to 4 mm inside the
	# true surface (probe_cutrim: 2.3 mm mean). The hand's wall was flattened
	# onto that rim, which is exactly the "waist" the author sees. Take the
	# contour from the SDF at the cut plane instead; the viewer moves the hand's
	# rim onto the same contour.
	var rest: Object = model
	if rest == null:
		rest = HandModel.new(1.0, 0.0)
	rim = sdf_rim(rest, rim, CUT_Y)
	# NO Gaussian here. The SDF's contour is already smooth (the field is), and
	# smoothing RADIAL VECTORS on a convex section pulls the points INWARD: the
	# chord midpoint of a 27 degree window sits at r*cos(13.5) = 0.972 r, so the
	# old pass shrank the rim by 0.8-1.5 mm. The arm was lofted from that
	# shrunken rim while the hand's wall above the cut sat on the true SDF
	# surface, so the forearm came out narrower than the wrist: the ledge and
	# the "waist" the author saw. The rim's angles are uneven, but the loft
	# connects ring points one to one, so that costs nothing.
	var c0 := Vector3.ZERO
	for p in rim:
		c0 += p
	c0 /= maxf(float(rim.size()), 1.0)

	var skel := Skeleton3D.new()
	skel.name = "ArmSkeleton"
	# One bone per loft ring: the wrist is not two rigid bones with a blend in
	# between (that is what made the bend lag, bulge on the outside and pinch
	# on the inside), but a proper bend field — every ring rotates by its own
	# share of the wrist angle, so the surface bends like a tube instead of
	# being interpolated between two rigid poses.
	var depths := ring_depths()
	for i in depths.size():
		skel.add_bone("r%d" % i)
		skel.set_bone_rest(i, Transform3D.IDENTITY)
		skel.set_bone_pose(i, Transform3D.IDENTITY)
	skin_root.add_child(skel)

	var mesh := _loft(rim, depths)
	var mi := MeshInstance3D.new()
	mi.name = "ArmSkinMesh"
	mi.mesh = mesh
	mi.material_override = skin_mat
	mi.skin = _skin_of(depths.size())
	skin_root.add_child(mi)

	var bones := {}
	bones["radius"] = _unit_cyl(bone_root, bone_mat)
	bones["ulna"] = _unit_cyl(bone_root, bone_mat)
	bones["elbow_ball"] = _ball(bone_root, 16.0, joint_mat)

	var view := {"root": root, "skin_root": skin_root, "bone_root": bone_root,
		"skin_mesh": mi, "skeleton": skel, "bones": bones, "skin_mat": skin_mat,
		"rim": rim, "depths": depths, "c0": c0}
	update_live(view, ArmModel.rest_arm())
	return view


# The hand's cut contour, taken from the rest mesh itself. The mesh is capped
# flat at CUT_Y: the cap triangles are the ones whose three vertices sit on the
# plane, and the rim is the boundary of that cap (edges used by exactly one cap
# triangle). The loop is ordered by walking its two-neighbour adjacency.
static func _cut_rim(src: ArrayMesh) -> PackedVector3Array:
	var out := PackedVector3Array()
	var arrays := src.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var cap := {}
	for t in range(0, idx.size(), 3):
		var i0 := idx[t]
		var i1 := idx[t + 1]
		var i2 := idx[t + 2]
		if absf(verts[i0].y - CUT_Y) > 0.01 \
				or absf(verts[i1].y - CUT_Y) > 0.01 \
				or absf(verts[i2].y - CUT_Y) > 0.01:
			continue
		for e in [[i0, i1], [i1, i2], [i2, i0]]:
			var key := Vector2i(mini(int(e[0]), int(e[1])), maxi(int(e[0]), int(e[1])))
			cap[key] = int(cap.get(key, 0)) + 1
	var adj := {}
	for key in cap:
		if int(cap[key]) != 1:
			continue
		var a: int = key.x
		var b: int = key.y
		if not adj.has(a):
			adj[a] = []
		if not adj.has(b):
			adj[b] = []
		(adj[a] as Array).append(b)
		(adj[b] as Array).append(a)
	if adj.is_empty():
		return out
	var start := -1
	for k in adj:
		if (adj[k] as Array).size() == 2:
			start = int(k)
			break
	if start < 0:
		return out
	var loop := []
	var prev := -1
	var cur := start
	for i in 4000:
		loop.append(cur)
		var nb: Array = adj[cur]
		var nxt := -1
		for n in nb:
			if int(n) != prev:
				nxt = int(n)
				break
		if nxt < 0 or nxt == start:
			break
		prev = cur
		cur = nxt
	if loop.size() < 3:
		return out
	out.resize(loop.size())
	for i in loop.size():
		var p := verts[loop[i]]
		out[i] = Vector3(p.x, CUT_Y, p.z)
	return out


static func _fallback_rim() -> PackedVector3Array:
	# Only used if the rest mesh is missing its cap; the measured cut is
	# 49.5 × 31.5 mm, centred at (-0.75, -0.75).
	var out := PackedVector3Array()
	var n := 96
	for i in n:
		var a := TAU * float(i) / float(n)
		out.append(Vector3(-0.75 + 24.75 * cos(a), CUT_Y,
			-0.75 + 15.75 * sin(a)))
	return out


# The rim's points moved onto the smoothed section, still in world space.
# The true cross-section of the hand at the cut plane. The mesher can only
# sample the field at grid nodes, and the cut sits half a voxel above the last
# row, so its rim is inset; the SDF itself knows where the surface really is.
# For every rim vertex the radius is found by a ray cast from the wrist's axis:
# the section is star-shaped there, so one outer zero per angle exists.
static func _sdf_radius(model: Object, y: float, c0: Vector3, ang: float) -> float:
	# The field AT the cut is max(d, 0) and never negative; a hair above the
	# plane the cut term is small enough not to bias the zero.
	var base := Vector3(c0.x, y + 0.05, c0.z)
	var dir := Vector3(cos(ang), 0.0, sin(ang))
	var r := 1.0
	while r < 60.0 and model.field(base + dir * r) < 0.0:
		r += 1.0
	var lo := 0.0
	var hi := r
	for k in 24:
		var mid := 0.5 * (lo + hi)
		if model.field(base + dir * mid) < 0.0:
			lo = mid
		else:
			hi = mid
	return hi


static func sdf_rim(model: Object, raw: PackedVector3Array, cut_y: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	out.resize(raw.size())
	var c := Vector3.ZERO
	for p in raw:
		c += p
	c /= maxf(float(raw.size()), 1.0)
	for i in raw.size():
		var ang := atan2(raw[i].z - c.z, raw[i].x - c.x)
		var r := _sdf_radius(model, cut_y, c, ang)
		out[i] = Vector3(c.x + cos(ang) * r, cut_y, c.z + sin(ang) * r)
	return out


static func _smoothed_rim(rim: PackedVector3Array) -> PackedVector3Array:
	var n := rim.size()
	var c0 := Vector3.ZERO
	for p in rim:
		c0 += p
	c0 /= maxf(float(n), 1.0)
	var sm := _smooth(rim, c0)
	var out := PackedVector3Array()
	out.resize(n)
	for i in n:
		out[i] = Vector3(c0.x + sm[i].x, CUT_Y, c0.z + sm[i].z)
	return out


# The outward normal of the cut contour at each of its points: perpendicular to
# the contour's tangent (the chord two steps either side), turned to face away
# from the centroid. It is NOT the radial direction — the section is an
# ellipse, and there the two differ by up to 22 degrees (probe_ring.gd).
#
# The hand's rim band and the arm's ring 0 are the same edge seen from two
# sides, so both take their normal from THIS table: generated normals left the
# two 0.4 degrees apart on average (probe_seam_smooth.gd), and under a grazing
# light that much draws a dashed line along the seam.
static func rim_normals(rim: PackedVector3Array, c0: Vector3) -> Array:
	var n := rim.size()
	var tab := []
	for j in n:
		var t := rim[(j + 2) % n] - rim[(j - 2 + n) % n]
		var nn := Vector3(t.z, 0.0, -t.x)
		if nn.dot(rim[j] - c0) < 0.0:
			nn = -nn
		tab.append([fposmod(atan2(rim[j].z - c0.z, rim[j].x - c0.x), TAU),
			nn.normalized() if nn.length_squared() > 1e-12 else Vector3.UP])
	tab.sort_custom(func(x, y): return float(x[0]) < float(y[0]))
	return tab


# The table's normal at the angle of p, interpolated between the two
# neighbouring contour points. Nearest-neighbour would give adjacent vertices
# the normals of different points, which is a visible sawtooth where the
# ellipse's normal turns fastest.
static func rim_normal_at(tab: Array, p: Vector3, c0: Vector3) -> Vector3:
	var a := fposmod(atan2(p.z - c0.z, p.x - c0.x), TAU)
	var n := tab.size()
	var i1 := n
	for i in n:
		if float(tab[i][0]) > a:
			i1 = i
			break
	var i0 := (i1 - 1 + n) % n
	var a0 := float(tab[i0][0])
	var a1 := float(tab[i1 % n][0])
	if i1 >= n:
		a1 += TAU
	elif i1 == 0:
		a0 -= TAU
	var t := 0.0
	if a1 > a0:
		t = clampf((a - a0) / (a1 - a0), 0.0, 1.0)
	return (tab[i0][1] as Vector3).slerp(tab[i1 % n][1], t)


# The loft: the first ring is the hand's cut rim vertex for vertex, so the two
# skins share their edge and no crack can open. Ring k's vertices correspond to
# the rim's vertices, so the surface has no twist. The rim passed in is ALREADY
# the smoothed contour (build() smooths it once, the viewer moves the hand's rim
# onto the same one); smoothing it a second time here would shrink the arm a
# fraction of a millimetre below the hand's edge and reopen the seam.
static func _loft(rim: PackedVector3Array, depths: PackedFloat32Array) -> ArrayMesh:
	var n := rim.size()
	var c0 := Vector3.ZERO
	for p in rim:
		c0 += p
	c0 /= float(n)
	var sm := PackedVector3Array()
	sm.resize(n)
	for i in n:
		sm[i] = rim[i] - c0
	var verts := PackedVector3Array()
	var rings := []
	var main := depths.size() - CAP_RINGS
	for k in main:
		var d := depths[k]
		var off := 0.0
		if k > 0:
			off = COLLAR_OUT * (1.0 - smoothstep(COLLAR_IN, COLLAR_L, d))
		rings.append(_ring(rim, sm, c0, d, 1.0, off))
	for j in range(1, CAP_RINGS + 1):
		var phi := 0.5 * PI * float(j) / float(CAP_RINGS)
		rings.append(_ring(rim, sm, c0, depths[main + j - 1], cos(phi), 0.0))
	var pole := Vector3(0.0, CUT_Y - TUBE_L, 0.0)
	for r in rings:
		for p in (r as PackedVector3Array):
			verts.append(p)
	var pole_i := verts.size()
	verts.append(pole)

	var idx := PackedInt32Array()
	for k in rings.size() - 1:
		var base := k * n
		var nxt := (k + 1) * n
		for i in n:
			var j := (i + 1) % n
			idx.append(base + i)
			idx.append(base + j)
			idx.append(nxt + j)
			idx.append(base + i)
			idx.append(nxt + j)
			idx.append(nxt + i)
	var last := (rings.size() - 1) * n
	for i in n:
		var j := (i + 1) % n
		idx.append(last + i)
		idx.append(last + j)
		idx.append(pole_i)

	# Outward winding. Godot treats clockwise triangles as front faces, so the
	# outward normal of the first quad is (p2-p0)×(p1-p0); flip the whole mesh
	# when that points at the axis.
	var p0 := verts[0]
	var p1 := verts[1]
	var p2 := verts[n]
	var normal := (p2 - p0).cross(p1 - p0)
	if normal.dot(p0 - Vector3(c0.x, p0.y, c0.z)) < 0.0:
		for t in range(0, idx.size(), 3):
			var tmp := idx[t + 1]
			idx[t + 1] = idx[t + 2]
			idx[t + 2] = tmp

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for p in verts:
		st.add_vertex(p)
	for i in idx:
		st.add_index(i)
	st.generate_normals()
	var tmp_mesh := st.commit()
	var arrays := tmp_mesh.surface_get_arrays(0)

	# The loft's normals are its own surface's normals — except ring 0, which
	# is the hand's cut rim seen from the arm's side. It takes the contour's
	# normal from the same table the hand's rim band uses, so the seam's
	# shading is continuous by construction (see rim_normals above).
	var vv: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var rim_tab := rim_normals(rim, c0)
	var nn: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	for vi in vv.size():
		if absf(vv[vi].y - CUT_Y) < 0.01:
			nn[vi] = rim_normal_at(rim_tab, vv[vi], c0)
	arrays[Mesh.ARRAY_NORMAL] = nn

	# One bone per ring, weight 1: each ring is carried rigidly by its own
	# share of the wrist angle (see update_live), so the surface bends as a
	# tube. The ring is found by height because SurfaceTool merges vertices.
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	bones.resize(vv.size() * 4)
	weights.resize(vv.size() * 4)
	for vi in vv.size():
		var depth := CUT_Y - vv[vi].y
		var best := 0
		var bd := 1e9
		for k in depths.size():
			var da := absf(depths[k] - depth)
			if da < bd:
				bd = da
				best = k
		var base := vi * 4
		bones[base] = best
		weights[base] = 1.0
		for j in range(1, 4):
			bones[base + j] = 0
			weights[base + j] = 0.0
	arrays[Mesh.ARRAY_BONES] = bones
	arrays[Mesh.ARRAY_WEIGHTS] = weights
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _ring(rim: PackedVector3Array, sm: PackedVector3Array, c0: Vector3,
		depth: float, cap: float, off: float) -> PackedVector3Array:
	var dpos := maxf(depth, 0.0)
	# The forearm is wider than the wrist, and it gains that width within the
	# first few centimetres: the old smoothstep over the whole 150 mm left the
	# arm a straight extrusion of the wrist, so the hand's own flare stepped
	# out of it and the seam read as a ledge.
	#
	# THE FLARE MUST LEAVE THE CUT AT THE HAND WALL'S OWN ANGLE. A Gaussian
	# flare starts flat, which is right only if the hand's wall leaves the rim
	# vertically; it does not — the palm widens by about a millimetre a side
	# over the first five millimetres (11 degrees). Two walls meeting at
	# 11 degrees make a visible crease all round the wrist, which is exactly
	# the "unnaturally sharp bend" the author saw in the top view. An
	# exponential has a non-zero slope at the cut, so the arm's wall continues
	# the hand's wall without a crease: A/L is the hand's own slope
	# (0.0072 = tan 11.3 / 27.75 mm), and the arm then eases off like a real
	# forearm, which is widest at the elbow.
	var s := 1.0 - exp(-dpos / 36.0)
	var sx := 1.0 + 0.24 * s
	var sz := 1.0 + 0.18 * s
	var fade := 1.0 - smoothstep(0.0, TUBE_L, dpos)
	# The hand's own rim is moved onto the smoothed contour by the viewer, so
	# the loft must use the SAME smoothed contour from its very first ring:
	# lerping from the raw rim here left the two skins up to 1.8 mm apart at
	# the seam, which read as a dark ledge. The raw rim is only the input of
	# the smoothing.
	var out := PackedVector3Array()
	out.resize(rim.size())
	for i in rim.size():
		var vx := sm[i].x
		var vz := sm[i].z
		# The collar (disabled: COLLAR_OUT = 0): a radial offset that would
		# bury the hand's cut edge in the arm skin. The weight band and the
		# vertical wall already hold the seam, and the collar read as a
		# bracelet, so the term stays at zero.
		var l := sqrt(vx * vx + vz * vz)
		if l > 0.001:
			vx += vx / l * off
			vz += vz / l * off
		var x := c0.x * fade + vx * sx * cap
		var z := c0.z * fade + vz * sz * cap
		out[i] = Vector3(x, CUT_Y - depth, z)
	return out


# The smooth section the loft turns into the arm. The exact rim is a
# marching-tetrahedra contour: its radius is quantised to the 0.5 mm grid and
# carries the wrist's low-frequency bumps. Lofting that shape 150 mm down
# turns every bump into a longitudinal ridge (seen on the first render), so
# the profile is a wide circular Gaussian of the rim's radial vectors. The
# viewer moves the hand's own rim onto this same contour, so the first ring
# of the loft and the hand's rim are one edge.
static func _smooth(rim: PackedVector3Array, c0: Vector3) -> PackedVector3Array:
	var n := rim.size()
	var out := PackedVector3Array()
	out.resize(n)
	var half := 12
	var sigma := 6.0
	var w := []
	var sum := 0.0
	for k in range(-half, half + 1):
		var wk := exp(-0.5 * pow(float(k) / sigma, 2.0))
		w.append(wk)
		sum += wk
	for i in n:
		var v := Vector3.ZERO
		for k in w.size():
			var j := (i + k - half + n) % n
			v += Vector3(rim[j].x - c0.x, 0.0, rim[j].z - c0.z) * float(w[k])
		out[i] = v / sum
	return out


static func _skin_of(n: int) -> Skin:
	var skin := Skin.new()
	skin.set_bind_count(n)
	for i in n:
		skin.set_bind_name(i, StringName("r%d" % i))
		skin.set_bind_pose(i, Transform3D.IDENTITY)
	return skin


# Depth below the cut of every ring of the loft, in the order the rings are
# built. The bones, the weights and the mesh all read this one list.
#
# The wrist's curvature is concentrated in the first 25 mm (the seam frame
# already carries half the bend), and with the old spacing a ring pair 4.3 mm
# apart turned the normal by 12.9 degrees — a visible band under a grazing
# light (probe_ringstep.gd). So the rings are dense exactly where the bend is:
# 0.8 mm up to 25 mm, 2.2 mm to the end of the bend, then growing steps.
static func ring_depths() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var d := 0.0
	while d < 24.999:
		out.append(d)
		d += 0.8
	while d < 55.999:
		out.append(d)
		d += 2.2
	var last := TUBE_L - CAP_L
	var prev := out[out.size() - 1]
	var step := 3.2
	for k in 8:
		prev = minf(prev + step, last)
		out.append(prev)
		step *= 1.25
	out[out.size() - 1] = last
	for j in range(1, CAP_RINGS + 1):
		var phi := 0.5 * PI * float(j) / float(CAP_RINGS)
		out.append(last + CAP_L * sin(phi))
	return out


static func _unit_cyl(parent: Node3D, mat: Material) -> MeshInstance3D:
	var cyl := CylinderMesh.new()
	cyl.height = 1.0
	cyl.top_radius = 1.0
	cyl.bottom_radius = 1.0
	cyl.radial_segments = 16
	cyl.rings = 1
	var mi := MeshInstance3D.new()
	mi.mesh = cyl
	mi.material_override = mat
	parent.add_child(mi)
	return mi


static func _ball(parent: Node3D, r: float, mat: Material) -> MeshInstance3D:
	var sp := SphereMesh.new()
	sp.radius = 1.0
	sp.height = 2.0
	sp.radial_segments = 24
	sp.rings = 12
	var mi := MeshInstance3D.new()
	mi.mesh = sp
	mi.material_override = mat
	mi.set_meta("radius", r)
	parent.add_child(mi)
	return mi


# Call after both nodes are in the tree: the mesh finds its skeleton by path.
static func wire(view: Dictionary) -> void:
	var mi: MeshInstance3D = view["skin_mesh"]
	mi.skeleton = mi.get_path_to(view["skeleton"])


static func set_skin_material(view: Dictionary, mat: Material) -> void:
	(view["skin_mesh"] as MeshInstance3D).material_override = mat


# The skin is not a two-bone blend and not a fan of rings hinged at the wrist.
# A wrist bend rotates the hand about the wrist; a ring-by-ring rotation about
# that same point makes the inner side of the bend move faster than the rings
# are spaced apart, so the palmar wall folds into a notch. Instead the forearm
# skin is swept along a Hermite centreline from the hand's cut to the elbow:
# the endpoints and tangents are the hand's and the forearm's own, the rings
# are spaced by arc length, and each ring's frame is the shortest arc to the
# centreline tangent with the pronation twist interpolated. The centreline
# bends like a real forearm instead of folding, and both the wrist edge and
# the elbow stump keep their exact transforms.
static func update_live(view: Dictionary, arm: Dictionary) -> void:
	var fore_xf := ArmModel.forearm_transform(arm)
	# The seam's frame: the hand's wall above the cut fades from it into the
	# palm, the arm's sweep starts from it, so both skins share one edge and
	# the wrist's bend is split between them instead of stopping at the cut.
	var blend_xf := ArmModel.wrist_blend(arm, ArmModel.WRIST_BLEND)
	var skel: Skeleton3D = view["skeleton"]
	var depths: PackedFloat32Array = view["depths"]
	var c0: Vector3 = view["c0"]
	# The cut sits 1.5 mm below the wrist, so the skin's centreline starts
	# there, not at the joint itself; the elbow is the fixed far end.
	var d_elbow := CUT_Y - ArmModel.ELBOW.y
	var p0 := blend_xf * Vector3(c0.x, CUT_Y, c0.z)
	var p1 := fore_xf * ArmModel.ELBOW
	var t0 := (blend_xf.basis * Vector3.DOWN).normalized()
	var t1 := (fore_xf.basis * Vector3.DOWN).normalized()
	# The bend is short: it ends where the straight part of the forearm begins.
	# `q` lies on the forearm's own line, so the elbow stays exact; the bend's
	# arc length is measured, and the straight part takes the remainder, which
	# keeps the rest pose the identity (at rest the bend IS the straight line).
	var bend := minf(BEND_L, d_elbow)
	var straight := maxf(d_elbow - bend, 0.0)
	var q := p1 - t1 * straight
	var m0 := t0 * bend
	var m1 := t1 * bend
	var arc0 := _arc_from_to(Vector3.DOWN, t0)
	var arc1 := _arc_from_to(Vector3.DOWN, t1)
	var phi0 := _twist_of(blend_xf.basis, arc0, t0)
	var phi1 := _twist_of(fore_xf.basis, arc1, t1)
	# Arc-length table: the Hermite's parameter is not uniform once it bends,
	# and the rings must keep their spacing along the skin.
	var n := 48
	var cum := PackedFloat32Array()
	cum.resize(n + 1)
	cum[0] = 0.0
	var prev := p0
	for k in range(1, n + 1):
		var w := _hermite(p0, m0, q, m1, float(k) / float(n))
		cum[k] = cum[k - 1] + w.distance_to(prev)
		prev = w
	var s_bend := cum[n]
	var total := s_bend + straight
	for i in depths.size():
		var d := depths[i]
		if d >= d_elbow:
			skel.set_bone_pose(i, fore_xf)
			continue
		var s := d / d_elbow * total
		var u := 1.0
		var c: Vector3
		var tang: Vector3
		if s <= s_bend:
			u = _u_at(cum, s)
			c = _hermite(p0, m0, q, m1, u)
			tang = _hermite_tan(p0, m0, q, m1, u).normalized()
		else:
			c = q + t1 * (s - s_bend)
			tang = t1
		var rot := Basis(tang, lerpf(phi0, phi1, u)) * _arc_from_to(Vector3.DOWN, tang)
		var fade := 1.0 - smoothstep(0.0, TUBE_L, d)
		var rest_c := Vector3(c0.x * fade, CUT_Y - d, c0.z * fade)
		skel.set_bone_pose(i, Transform3D(rot, c - rot * rest_c))
	skel.force_update_all_bone_transforms()

	# Radius and ulna are rigidly part of the forearm, so their rest points
	# are simply carried by the forearm transform. The elbow ball stays on the
	# fixed root.
	var b: Dictionary = view["bones"]
	_set_bone(b["radius"], fore_xf * Vector3(9.0, -150.0, 0.0),
		fore_xf * Vector3(7.0, 0.0, 0.0), 4.6)
	_set_bone(b["ulna"], fore_xf * Vector3(-9.0, -150.0, 0.0),
		fore_xf * Vector3(-7.0, 0.0, 0.0), 4.2)
	_set_ball(b["elbow_ball"], p1, Basis.IDENTITY, Vector3.ONE * 16.0)


static func _hermite(p0: Vector3, m0: Vector3, p1: Vector3, m1: Vector3,
		u: float) -> Vector3:
	# Quintic, not cubic: the second derivative is zero at BOTH ends, so the
	# arm's wall leaves the seam straight (continuing the hand's wall) and
	# reaches the elbow straight (continuing the forearm). A cubic already
	# turns at the seam, and that turn is the crease seen at 70°.
	var u2 := u * u
	var u3 := u2 * u
	var u4 := u3 * u
	var u5 := u4 * u
	var h0 := 1.0 - 10.0 * u3 + 15.0 * u4 - 6.0 * u5
	var h1 := u - 6.0 * u3 + 8.0 * u4 - 3.0 * u5
	var h3 := 10.0 * u3 - 15.0 * u4 + 6.0 * u5
	var h4 := -4.0 * u3 + 7.0 * u4 - 3.0 * u5
	return p0 * h0 + m0 * h1 + p1 * h3 + m1 * h4


static func _hermite_tan(p0: Vector3, m0: Vector3, p1: Vector3, m1: Vector3,
		u: float) -> Vector3:
	var u2 := u * u
	var u3 := u2 * u
	var u4 := u3 * u
	var d0 := -30.0 * u2 + 60.0 * u3 - 30.0 * u4
	var d1 := 1.0 - 18.0 * u2 + 32.0 * u3 - 15.0 * u4
	var d3 := 30.0 * u2 - 60.0 * u3 + 30.0 * u4
	var d4 := -12.0 * u2 + 28.0 * u3 - 15.0 * u4
	return p0 * d0 + m0 * d1 + p1 * d3 + m1 * d4


# Shortest arc carrying `a` onto `b`.
static func _arc_from_to(a: Vector3, b: Vector3) -> Basis:
	var u := a.normalized()
	var v := b.normalized()
	var c := clampf(u.dot(v), -1.0, 1.0)
	if c > 0.999999:
		return Basis.IDENTITY
	var axis := u.cross(v)
	if axis.length_squared() < 0.000000001:
		axis = u.cross(Vector3.RIGHT)
		if axis.length_squared() < 0.000000001:
			axis = u.cross(Vector3.BACK)
		return Basis(axis.normalized(), PI)
	return Basis(axis.normalized(), acos(c))


# Signed roll of `full` relative to `arc` around `axis`, both of which carry
# the rest tangent onto the same axis. Used to interpolate pronation without
# letting the shortest arc throw the twist away.
static func _twist_of(full: Basis, arc: Basis, axis: Vector3) -> float:
	var ref := Vector3.RIGHT
	if absf(ref.dot(axis)) > 0.9:
		ref = Vector3.BACK
	var a := full * ref
	var b := arc * ref
	a = (a - axis * a.dot(axis)).normalized()
	b = (b - axis * b.dot(axis)).normalized()
	return atan2(axis.dot(b.cross(a)), b.dot(a))


# The parameter u at arc length s, by linear interpolation in the table.
static func _u_at(cum: PackedFloat32Array, s: float) -> float:
	var n := cum.size() - 1
	if s <= 0.0:
		return 0.0
	if s >= cum[n]:
		return 1.0
	var lo := 0
	var hi := n
	while lo + 1 < hi:
		var mid := (lo + hi) / 2
		if cum[mid] <= s:
			lo = mid
		else:
			hi = mid
	var span := cum[hi] - cum[lo]
	var f := 0.0 if span < 0.000000001 else (s - cum[lo]) / span
	return (float(lo) + f) / float(n)


static func _set_bone(mi: MeshInstance3D, a: Vector3, b: Vector3, r: float) -> void:
	var d := b - a
	var length := d.length()
	if length < 0.001:
		mi.visible = false
		return
	mi.visible = true
	var y := d / length
	var x := y.cross(Vector3.RIGHT)
	if x.length_squared() < 0.000001:
		x = y.cross(Vector3.UP)
	x = x.normalized()
	var z := x.cross(y).normalized()
	mi.transform = Transform3D(Basis(x * r, y * length, z * r), (a + b) * 0.5)


static func _set_ball(mi: MeshInstance3D, at: Vector3, basis: Basis, scale: Vector3) -> void:
	mi.transform = Transform3D(basis * Basis().scaled(scale), at)
