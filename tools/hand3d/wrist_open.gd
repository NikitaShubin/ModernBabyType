# The open wrist: the hand mesh is capped flat at the cut, and this module
# removes the cap and puts the rim, the wall and its normals on the SDF's true
# contour so the forearm loft (arm_view.gd) meets the hand without a seam, a
# waist or a shading ring. It lives here, not in a viewer, because BOTH viewers
# (the single-hand study and the two-hand board) build the same hand.
extends RefCounted

const ArmView := preload("res://arm_view.gd")
const HandModel := preload("res://hand_model.gd")


# The study hand is capped flat at the wrist. The cap's boundary is inset (the
# mesher puts it on grid nodes inside the true section), so the rim and the
# wall just above it are snapped onto the SDF's true contour: the rim fully,
# the wall with a weight that falls to zero at WRIST_SMOOTH_H. The cap
# triangles themselves are dropped; the arm's first ring closes the hole.
const WRIST_SMOOTH_H := 1.0
# The palm is wider than the wrist, so the hand's wall flares outward above the
# cut. The arm cannot follow that overhang — the seam would read as a ledge,
# and under a bend the ledge becomes a hard corner. The old answer was to
# flatten the wall onto the rim for WRIST_FLAT_H; that is now OFF
# (WRIST_WALL_H = 0) because the rim is no longer inset: snapping the wall to
# the SDF for the first millimetre is enough, and the SDF's own shape is the
# approved one.
const WRIST_FLAT_H := 30.0
# Height of the shape flattening (see above). Zero: disabled.
const WRIST_WALL_H := 0.0


# Quintic ease: unlike smoothstep, its SECOND derivative is zero at both ends,
# so the flattened wall joins the untouched wall without a curvature jump. A
# curvature jump shows as a kink in the silhouette at grazing angles — that is
# exactly what smoothstep left ten millimetres above the cut.
static func _smootherstep(t: float) -> float:
	var x := clampf(t, 0.0, 1.0)
	return x * x * x * (x * (x * 6.0 - 15.0) + 10.0)


# A column of the contour's angle table, linearly interpolated. The table is
# sorted by angle and wraps around, so a query between the last point and the
# first one takes the short way across zero.
static func _tab_at(table: Array, a: float, col: int):
	var n := table.size()
	if n == 0:
		return null
	var i1 := n
	for i in n:
		if float(table[i][0]) > a:
			i1 = i
			break
	var i0 := (i1 - 1 + n) % n
	var a0 := float(table[i0][0])
	var a1 := float(table[i1 % n][0])
	if i1 >= n:
		a1 += TAU
	elif i1 == 0:
		a0 -= TAU
	var t := 0.0
	if a1 > a0:
		t = clampf((a - a0) / (a1 - a0), 0.0, 1.0)
	var v0 = table[i0][col]
	var v1 = table[i1 % n][col]
	if typeof(v0) == TYPE_FLOAT:
		return lerpf(float(v0), float(v1), t)
	if typeof(v0) == TYPE_VECTOR3:
		return (v0 as Vector3).slerp(v1 as Vector3, t)
	return (v0 as Vector2).lerp(v1 as Vector2, t)


static func open_wrist(src: ArrayMesh, rest_model: Object = null) -> ArrayMesh:
	var arrays := src.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var raw := ArmView._cut_rim(src)
	var rest: Object = rest_model
	if rest == null:
		rest = HandModel.new(1.0, 0.0)
	# The mesh rim is inset by up to a voxel (see ArmView.sdf_rim); the true
	# contour comes from the SDF, and the hand's rim is moved onto it. It is
	# NOT smoothed afterwards: averaging radial vectors on a convex section
	# shrinks it by 0.8-1.5 mm (the old Gaussian pass), and the arm lofted from
	# that shrunken rim was narrower than the hand — the "waist" at the seam.
	var target := ArmView.sdf_rim(rest, raw, ArmView.CUT_Y)
	var smooth := target
	var c0 := Vector3.ZERO
	for p in raw:
		c0 += p
	c0 /= maxf(float(raw.size()), 1.0)
	var keep := PackedInt32Array()
	for t in range(0, idx.size(), 3):
		var i0 := idx[t]
		var i1 := idx[t + 1]
		var i2 := idx[t + 2]
		if absf(verts[i0].y - ArmView.CUT_Y) < 0.01 \
				and absf(verts[i1].y - ArmView.CUT_Y) < 0.01 \
				and absf(verts[i2].y - ArmView.CUT_Y) < 0.01:
			continue
		keep.append(i0)
		keep.append(i1)
		keep.append(i2)
	# The rim's raw points are the CAP's boundary: marching tetrahedra put the
	# cap on grid nodes inside the true section, so the raw rim is 2-4 mm in
	# (probe_cutrim). The true contour comes from the SDF (sdf_rim), and the
	# wall within WRIST_SMOOTH_H is pulled onto the SDF as well — each vertex
	# at its OWN height and angle. Pulling it by the rim's delta (the old way)
	# overshot: the rim is 2 mm inside, the wall only half a millimetre, so the
	# wall was pushed a millimetre OUTSIDE the surface and read as a ridge
	# right above the seam. The weight falls from one at the cut to zero at
	# the band's top, so the wall above is the baked mesh untouched.
	var rad_tab := []
	for j in raw.size():
		rad_tab.append([
			fposmod(atan2(smooth[j].z - c0.z, smooth[j].x - c0.x), TAU),
			Vector2(smooth[j].x - c0.x, smooth[j].z - c0.z).length()])
	rad_tab.sort_custom(func(x, y): return float(x[0]) < float(y[0]))
	var band := WRIST_SMOOTH_H
	# The mesher puts the cap's boundary within a few microns of the plane but
	# not ON it (measured y = -1.4946 .. -1.5017). The radius below is taken at
	# the vertex's own height, so a rim vertex a hair above the cut takes its
	# radius from a different height than the arm's ring 0, which is exactly at
	# CUT_Y: the two loops then miss each other by 0.0006 mm (seam_edges). That
	# is 0.01 px on screen, but MSAA samples are points: along the seam one
	# sample in four landed in the crack, and the seam showed as a dashed line
	# of background pixels (9 in one band, each 25% background). The cut IS a
	# plane and the zigzag is mesher noise, so snap the rim onto it. Then the
	# rim and ring 0 are the same points, and the rasteriser's top-left rule
	# closes the seam.
	for i in verts.size():
		if absf(verts[i].y - ArmView.CUT_Y) < 0.01:
			verts[i].y = ArmView.CUT_Y
	for i in verts.size():
		var dy := verts[i].y - ArmView.CUT_Y
		if dy < -0.01 or dy > band:
			continue
		var v := Vector2(verts[i].x - c0.x, verts[i].z - c0.z)
		if v.length() < 0.001:
			continue
		var rr := ArmView._sdf_radius(rest, ArmView.CUT_Y + maxf(dy, 0.0),
			c0, atan2(v.y, v.x))
		var w := 1.0 - smoothstep(0.0, band, maxf(dy, 0.0))
		var k := lerpf(v.length(), rr, w) / v.length()
		verts[i].x = c0.x + v.x * k
		verts[i].z = c0.z + v.y * k
	# Flatten the wall: pull its radius toward the smoothed rim's radius with
	# a weight that is one at the cut and falls to zero at WRIST_WALL_H. The
	# weight's derivative is zero at the cut, so the wall meets the rim
	# vertically instead of overhanging it. Only the SHAPE is flattened here;
	# the weight band keeps its own height (WRIST_FLAT_H).
	#
	# The radius before the pull and the pull's weight are kept per vertex:
	# the normals need them (see below), and after the move the original
	# radius is gone.
	var flat_nat := PackedFloat32Array()
	var flat_rim := PackedFloat32Array()
	var flat_w := PackedFloat32Array()
	flat_nat.resize(verts.size())
	flat_rim.resize(verts.size())
	flat_w.resize(verts.size())
	for i in verts.size():
		flat_nat[i] = -1.0
		flat_rim[i] = 0.0
		flat_w[i] = 0.0
	for i in verts.size():
		var dy := verts[i].y - ArmView.CUT_Y
		if dy < 0.01 or dy > WRIST_WALL_H:
			continue
		var v := Vector2(verts[i].x - c0.x, verts[i].z - c0.z)
		if v.length() < 0.001:
			continue
		var rr: float = _tab_at(rad_tab, fposmod(atan2(v.y, v.x), TAU), 1)
		var s := _smootherstep(dy / WRIST_WALL_H)
		var k := lerpf(rr, v.length(), s) / v.length()
		flat_nat[i] = v.length()
		flat_rim[i] = rr
		flat_w[i] = s
		verts[i].x = c0.x + v.x * k
		verts[i].z = c0.z + v.y * k
	# The wall's radius comes from the mesh, which marching tetrahedra quantise
	# to the 2 mm grid: row to row it steps by up to half a millimetre. The
	# flatten's own displacement is smooth, but the CORRECTION to the normal is
	# proportional to the overhang, so the quantisation would show as terraces
	# in the shading (it did). A few Laplacian passes over the band's edges
	# take the steps out without touching the wall's real shape.
	var adj := {}
	for t in range(0, keep.size(), 3):
		for e in 3:
			var a := keep[t + e]
			var b := keep[t + (e + 1) % 3]
			if not adj.has(a):
				adj[a] = []
			if not adj.has(b):
				adj[b] = []
			(adj[a] as Array).append(b)
			(adj[b] as Array).append(a)
	for it in 8:
		var next := flat_nat.duplicate()
		for i in adj:
			if flat_w[i] <= 0.0:
				continue
			var sum := 0.0
			var cnt := 0
			var list: Array = adj[i]
			for j in list:
				if flat_w[j] > 0.0:
					sum += flat_nat[j]
					cnt += 1
			if cnt > 0:
				next[i] = lerpf(flat_nat[i], sum / float(cnt), 0.6)
		flat_nat = next
	# The source normals are KEPT: the mesh was baked from the SDF, so its
	# normals are the field's gradient — smooth by construction, and the rest
	# of the hand (palm, fingers) has always used them. Only the cut is wrong:
	# the mesh was capped flat there, so the rim normals are the CAP's (only 8
	# of 1276 carry any horizontal part, probe_srcnorm.gd), and so are the
	# normals of the wall below 1 mm.
	#
	# Area-weighted normals of the open surface are NOT a substitute: marching
	# tetrahedra leave long, thin, uneven triangles, so a vertex's normal is
	# dominated by one or two of them. On the flat palm they produced visible
	# blocky patches even in the rest pose (fold-*-f00-norm), and on the wrist
	# wall a facet pattern that no amount of position smoothing removed. The
	# wall is vertical and leaves the contour perpendicular to it, so near the
	# cut the SMOOTHED contour's normal is the right one. It is perpendicular
	# to the contour's tangent, not radial: on the ellipse those differ by up
	# to 22 degrees, which is the step the radial force used to put at the seam.
	var src_n: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var ns := smooth.size()
	# Rim and the fan ring just above it (0.023 mm) both belong to the same
	# vertical wall, and both were moved onto the smoothed contour by the
	# loops above, so both take the contour's normal. The cap's normals reach
	# up to about a millimetre (probe_srcband.gd: the row at 0.5-1.0 mm still
	# tilts 90 degrees, the one at 1.0-1.5 is already 12), so the contour
	# holds to 1 mm and gives way to the SDF's over the next millimetre — a
	# step there would be a shading ring all round the wrist.
	#
	# The lookup is ArmView's: the arm gives its ring 0 the SAME normal from
	# the same table. generate_normals() alone left the two 0.4 degrees apart
	# on average (probe_seam_smooth.gd), and at a grazing light that draws a
	# dashed line along the seam.
	var rim_tab := ArmView.rim_normals(smooth, c0)
	var rim_band := 1.0
	var rim_fade := 4.0
	for i in verts.size():
		var dy := verts[i].y - ArmView.CUT_Y
		var rn := ArmView.rim_normal_at(rim_tab, verts[i], c0)
		if dy <= rim_band:
			norms[i] = rn
			continue
		var n := src_n[i].normalized()
		# The flatten MOVED the wall without moving its normals. On the wall
		# of revolution the normal says how fast the radius grows with height:
		# r' = -n_y / n_r. The pull changes that slope to
		#   r'_disp = r'_nat * (1 - w) + (rr - r_nat) * w',
		# so the SDF's normal is wrong by atan(r'_nat) - atan(r'_disp) —
		# up to 20 degrees in the middle of the pull, where the wall is held
		# back but the shading still says it flares. That error drew a broad
		# bright band across the wrist (the "sock" seam the author saw).
		if flat_w[i] > 0.0:
			var r := flat_nat[i]
			var v2 := Vector2(verts[i].x - c0.x, verts[i].z - c0.z)
			var l2 := v2.length()
			if l2 > 0.001:
				var er := Vector3(v2.x / l2, 0.0, v2.y / l2)
				var ne := n.dot(er)
				if ne > 0.05:
					var rp_nat := -n.y / ne
					var t := clampf(dy / WRIST_WALL_H, 0.0, 1.0)
					var dw := 30.0 * t * t * (1.0 - t) * (1.0 - t) / WRIST_WALL_H
					var rp_disp := rp_nat * (1.0 - flat_w[i]) \
						+ (flat_rim[i] - r) * dw
					var delta := atan(rp_nat) - atan(rp_disp)
					var ea := Vector3(-v2.y / l2, 0.0, v2.x / l2)
					n = n * cos(delta) + ea.cross(n) * sin(delta)
		if dy > rim_fade:
			norms[i] = n
		else:
			var w := _smootherstep((dy - rim_band) / (rim_fade - rim_band))
			norms[i] = rn.slerp(n, w)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_INDEX] = keep
	var open := ArrayMesh.new()
	open.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return open


