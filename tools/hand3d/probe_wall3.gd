# The radial profile of the wrist wall, exact: the mesh is cut by a vertical
# half-plane at a given angle and the outer crossing of every height row is
# printed against the SDF's true radius. Raw mesh vs opened mesh, so the
# opening's rim correction can be judged: the wall above the cut must stay on
# the SDF, not bulge out or cave in. Headless.
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const ArmView := preload("res://arm_view.gd")
const Viewer := preload("res://viewer.gd")

const REST_MESH := "res://cache/skin_curled_rest.res"

const ANGLES := [["palmar", -PI / 2.0], ["dorsal", PI / 2.0],
	["radial", 0.0], ["ulnar", PI]]
const ROWS := [0.0, 0.5, 1.0, 1.5, 2.0, 3.0, 5.0, 8.0, 12.0, 20.0, 30.0]


func _init() -> void:
	var rest := HandModel.new(1.0, 0.0)
	var src: ArrayMesh = load(REST_MESH)
	var viewer: Node = Viewer.new()
	var opened: ArrayMesh = viewer._open_wrist(src, rest)
	viewer.free()
	var raw := ArmView._cut_rim(src)
	var c0 := Vector3.ZERO
	for p in raw:
		c0 += p
	c0 /= float(raw.size())
	print("c0 %s   cut %.2f" % [str(c0), ArmView.CUT_Y])

	for want in ANGLES:
		var ang: float = float(want[1])
		var dir := Vector3(cos(ang), 0.0, sin(ang))
		print("--- %s" % str(want[0]))
		var raw_hits := _profile(src, c0, ang)
		var op_hits := _profile(opened, c0, ang)
		for row in ROWS:
			var y := ArmView.CUT_Y + float(row)
			# The SDF is clamped at the cut plane (max(d, 0)), so the rim row
			# is measured a hundredth of a millimetre above it.
			var base := Vector3(0.0, y + 0.01, 0.0)
			var lo := 0.0
			var hi := 1.0
			while hi < 60.0 and rest.field(base + dir * hi) < 0.0:
				hi += 1.0
			for k in 26:
				var mid := 0.5 * (lo + hi)
				if rest.field(base + dir * mid) < 0.0:
					lo = mid
				else:
					hi = mid
			print("  y %6.2f  opened %7.3f  raw %7.3f  sdf %7.3f" % [
				y, _at(op_hits, y), _at(raw_hits, y), hi])
	quit()


# All intersections of the mesh's triangles with the vertical half-plane at
# `ang`, as [y, radius] pairs of the OUTER crossing on the +dir side.
func _profile(mesh: ArrayMesh, c0: Vector3, ang: float) -> Array:
	var a: Array = mesh.surface_get_arrays(0)
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	var n := Vector3(-sin(ang), 0.0, cos(ang))
	var dir := Vector3(cos(ang), 0.0, sin(ang))
	var out := []
	for t in range(0, idx.size(), 3):
		var p := [v[idx[t]], v[idx[t + 1]], v[idx[t + 2]]]
		var sd := []
		var any_pos := false
		var any_neg := false
		for k in 3:
			var d := n.dot(p[k] - c0)
			sd.append(d)
			if d > 0.0:
				any_pos = true
			else:
				any_neg = true
		if not (any_pos and any_neg):
			continue
		var pts := []
		for k in 3:
			var k2 := (k + 1) % 3
			var d0: float = sd[k]
			var d1: float = sd[k2]
			if (d0 > 0.0) == (d1 > 0.0):
				continue
			var u := d0 / (d0 - d1)
			pts.append((p[k] as Vector3).lerp(p[k2] as Vector3, u))
		if pts.size() != 2:
			continue
		var q0: Vector3 = pts[0]
		var q1: Vector3 = pts[1]
		var r0 := Vector2(q0.x - c0.x, q0.z - c0.z).dot(Vector2(dir.x, dir.z))
		var r1 := Vector2(q1.x - c0.x, q1.z - c0.z).dot(Vector2(dir.x, dir.z))
		if maxf(r0, r1) <= 0.0:
			continue
		out.append([q0.y, r0, q1.y, r1])
	return out


# The outer radius at height y: walk every crossing segment that spans y and
# take the largest interpolated radius.
func _at(hits: Array, y: float) -> float:
	var best := 0.0
	for h in hits:
		var y0: float = h[0]
		var r0: float = h[1]
		var y1: float = h[2]
		var r1: float = h[3]
		if y < minf(y0, y1) - 0.001 or y > maxf(y0, y1) + 0.001:
			continue
		var u := 0.0
		if absf(y1 - y0) > 0.000001:
			u = clampf((y - y0) / (y1 - y0), 0.0, 1.0)
		best = maxf(best, lerpf(r0, r1, u))
	return best
