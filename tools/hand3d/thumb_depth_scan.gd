# The four fingers pin the hand's orientation: home_scan.gd tried 300 wrist
# placements and only ONE lets the four pads reach their keys at all. So the
# thumb crossing cannot be fixed by turning the hand.
#
# What the brief does leave free is the thumb's DEPTH along the space bar. The
# four fingers already use that freedom ("depth is free, width and height are
# not"), and the key is 20.76 mm deep. The thumb's own natural pad sits 27 mm
# BEHIND the space bar's centre line, so pressing nearer the back edge is the
# natural direction — and it changes how far the column must fold, which is
# exactly what decides where the IP joint lands.
#
# This probe keeps the home arm and the four fingers as they are, re-solves the
# thumb for a grid of (x, y) on the space bar, and prints the IP joint's world x
# and the two thumbs' flesh gap.
#
#   mbt-godot --headless --path /work/tools/hand3d --script res://thumb_depth_scan.gd
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")
const IK := preload("res://ik.gd")
const Kbd3D := preload("res://kbd3d.gd")
const HomePose := preload("res://home_pose.gd")

const ROOTS := {"L": -72.51, "R": 43.94}
const THUMB_R := [11.8, 10.8, 9.6, 6.6]
const LIFT := 2.0


func _world(side: String, q: Vector3) -> Vector3:
	if side == "R":
		return Vector3(float(ROOTS[side]) - q.x, q.y, q.z)
	return Vector3(float(ROOTS[side]) + q.x, q.y, q.z)


func _solve_thumb(side: String, home: Dictionary, x: float, y: float) -> Dictionary:
	var root_x: float = ROOTS[side]
	var sgn := -1.0 if side == "R" else 1.0
	var tgt := Vector3((x - root_x) * sgn, y, Kbd3D.FACE_Z + LIFT)
	var r: Dictionary = IK.solve_chain("I", tgt, home, HomePose._opts("I"))
	return r["pose"]


func _ip(side: String, p: Dictionary) -> Vector3:
	var xf := ArmModel.hand_transform(p["arm"])
	var fk: Dictionary = HandModel.thumb_fk(HandModel.thumb_of_pose(p))
	return _world(side, xf * (fk["pts"] as PackedVector3Array)[2])


func _pad(side: String, p: Dictionary) -> Vector3:
	var xf := ArmModel.hand_transform(p["arm"])
	var fk: Dictionary = HandModel.thumb_fk(HandModel.thumb_of_pose(p))
	return _world(side, xf * HandModel.thumb_pad(fk))


func _seg_dist(p1: Vector3, q1: Vector3, p2: Vector3, q2: Vector3) -> float:
	var d1 := q1 - p1
	var d2 := q2 - p2
	var r := p1 - p2
	var a := d1.dot(d1)
	var e := d2.dot(d2)
	var f := d2.dot(r)
	var s := 0.0
	var t := 0.0
	if a <= 1e-12 and e <= 1e-12:
		return r.length()
	if a <= 1e-12:
		t = clampf(f / e, 0.0, 1.0)
	elif e <= 1e-12:
		s = clampf(-d1.dot(r) / a, 0.0, 1.0)
	else:
		var c := d1.dot(r)
		var b := d1.dot(d2)
		var denom := a * e - b * b
		if absf(denom) > 1e-12:
			s = clampf((b * f - c * e) / denom, 0.0, 1.0)
		t = (b * s + f) / e
		if t < 0.0:
			t = 0.0
			s = clampf(-c / a, 0.0, 1.0)
		elif t > 1.0:
			t = 1.0
			s = clampf((b - c) / a, 0.0, 1.0)
	return (p1 + d1 * s).distance_to(p2 + d2 * t)


func _gap(pl: Dictionary, pr: Dictionary) -> Array:
	var xl := ArmModel.hand_transform(pl["arm"])
	var xr := ArmModel.hand_transform(pr["arm"])
	var jl: PackedVector3Array = HandModel.thumb_fk(HandModel.thumb_of_pose(pl))["pts"]
	var jr: PackedVector3Array = HandModel.thumb_fk(HandModel.thumb_of_pose(pr))["pts"]
	var worst := 1e9
	var tag := ""
	for i in 3:
		for k in 3:
			var d := _seg_dist(_world("L", xl * jl[i]), _world("L", xl * jl[i + 1]),
				_world("R", xr * jr[k]), _world("R", xr * jr[k + 1]))
			var g := d - maxf(float(THUMB_R[i]), float(THUMB_R[i + 1])) \
				- maxf(float(THUMB_R[k]), float(THUMB_R[k + 1]))
			if g < worst:
				worst = g
				tag = "%d/%d" % [i, k]
	return [worst, tag]


func _init() -> void:
	var home_l: Dictionary = HomePose.build("L", ROOTS["L"])
	var home_r: Dictionary = HomePose.build("R", ROOTS["R"])
	print("space bar y %.2f .. %.2f, centre %.2f" % [
		Kbd3D.row_y(4) - Kbd3D.ROW_H * 0.5, Kbd3D.row_y(4) + Kbd3D.ROW_H * 0.5,
		Kbd3D.row_y(4)])
	var y0 := Kbd3D.row_y(4)
	var best := {}
	var best_gap := -1e9
	print("  x     y     | L pad err  L ip x  | R pad err  R ip x  | gap")
	for xv in [20.5, 21.5, 22.5]:
		for dyv in [-8.0, -4.0, 0.0, 4.0, 8.0]:
			var x: float = xv
			var y: float = y0 + float(dyv)
			var pl := _solve_thumb("L", home_l, -x, y)
			var pr := _solve_thumb("R", home_r, x, y)
			var el := _pad("L", pl).distance_to(Vector3(-x, y, Kbd3D.FACE_Z + LIFT))
			var er := _pad("R", pr).distance_to(Vector3(x, y, Kbd3D.FACE_Z + LIFT))
			var g := _gap(pl, pr)
			print("%5.1f %6.2f | %8.3f %8.2f | %8.3f %8.2f | %6.2f %s"
				% [x, y, el, _ip("L", pl).x, er, _ip("R", pr).x,
				float(g[0]), str(g[1])])
			if float(g[0]) > best_gap and el < 0.5 and er < 0.5:
				best_gap = float(g[0])
				best = {"x": x, "y": y, "L": pl, "R": pr}
	print("== best same-depth pair: gap %.2f mm at x %.1f y %.2f"
		% [best_gap, float(best.get("x", 0)), float(best.get("y", 0))])
	if not best.is_empty():
		print("   L %s" % str(HandModel.thumb_of_pose(best["L"])))
		print("   R %s" % str(HandModel.thumb_of_pose(best["R"])))
	# Independent depths: the left can sit forward while the right sits back.
	var grid_l := []
	var grid_r := []
	for xv in [20.5, 21.5, 22.5]:
		for dyv in [-8.0, -6.0, -4.0, -2.0, 0.0, 2.0, 4.0, 6.0, 8.0]:
			var x: float = xv
			var y: float = y0 + float(dyv)
			grid_l.append({"x": -x, "y": y, "p": _solve_thumb("L", home_l, -x, y)})
			grid_r.append({"x": x, "y": y, "p": _solve_thumb("R", home_r, x, y)})
	var bi := {}
	var bg := -1e9
	for a in grid_l:
		for b in grid_r:
			var g := _gap(a["p"], b["p"])
			if float(g[0]) > bg:
				bg = float(g[0])
				bi = {"L": a, "R": b, "tag": g[1]}
	print("== best independent-depth pair: gap %.2f mm  L x %.1f y %.2f  R x %.1f y %.2f (%s)"
		% [bg, float(bi["L"]["x"]), float(bi["L"]["y"]), float(bi["R"]["x"]),
		float(bi["R"]["y"]), str(bi["tag"])])
	print("   L %s" % str(HandModel.thumb_of_pose(bi["L"]["p"])))
	print("   R %s" % str(HandModel.thumb_of_pose(bi["R"]["p"])))
	print("   L ip x %7.2f  R ip x %7.2f" % [_ip("L", bi["L"]["p"]).x,
		_ip("R", bi["R"]["p"]).x])
	quit(0)
