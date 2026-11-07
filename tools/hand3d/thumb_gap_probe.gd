# Where the two thumbs' joints really are at the home pose, in world mm, and
# how close their capsules come. The pads are 41 mm apart, yet the capsule test
# reports a 5 mm crossing of the middle phalanges — so the question is which
# joint sits inward of the pad.
#
#   mbt-godot --headless --path /work/tools/hand3d --script res://thumb_gap_probe.gd
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")
const Kbd3D := preload("res://kbd3d.gd")
const HomePose := preload("res://home_pose.gd")

const ROOTS := {"L": -72.51, "R": 43.94}
const THUMB_R := [11.8, 10.8, 9.6, 6.6]
const NAMES := ["base", "mcp", "ip", "tip"]


func _world(side: String, q: Vector3) -> Vector3:
	if side == "R":
		return Vector3(float(ROOTS[side]) - q.x, q.y, q.z)
	return Vector3(float(ROOTS[side]) + q.x, q.y, q.z)


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


func _init() -> void:
	var pts := {}
	var pads := {}
	var th := {}
	for side in ["L", "R"]:
		var p: Dictionary = HomePose.build(side, float(ROOTS[side]))
		var xf := ArmModel.hand_transform(p["arm"])
		var fk: Dictionary = HandModel.thumb_fk(HandModel.thumb_of_pose(p))
		var raw: PackedVector3Array = fk["pts"]
		var w := []
		for i in 4:
			w.append(_world(side, xf * raw[i]))
		pts[side] = w
		pads[side] = _world(side, xf * HandModel.thumb_pad(fk))
		th[side] = HandModel.thumb_of_pose(p)
		print("=== %s thumb %s" % [side, str(th[side])])
		for i in 4:
			print("    %-4s %s" % [NAMES[i], str(w[i])])
		print("    pad  %s" % str(pads[side]))
	print("-- corresponding joint gaps (L to R):")
	for i in 4:
		var a: Vector3 = pts["L"][i]
		var b: Vector3 = pts["R"][i]
		print("    %-4s %7.2f mm  (L x %8.2f  R x %8.2f)"
			% [NAMES[i], a.distance_to(b), a.x, b.x])
	print("    pad  %7.2f mm" % (pads["L"] as Vector3).distance_to(pads["R"]))
	print("-- capsule pairs (middle phalanx = mcp..ip):")
	for i in 3:
		var d := _seg_dist(pts["L"][i], pts["L"][i + 1],
			pts["R"][i], pts["R"][i + 1])
		var rr := maxf(float(THUMB_R[i]), float(THUMB_R[i + 1]))
		print("    seg %d  bone dist %7.2f  radii %.1f+%.1f  pen %6.2f"
			% [i, d, rr, rr, maxf(0.0, rr + rr - d)])
	quit(0)
