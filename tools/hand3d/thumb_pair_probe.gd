# The home thumb pair the scan found, printed joint by joint so the SHAPE can
# be judged, not just the numbers: base, MCP, IP, tip, pad in world space, the
# distal phalanx's direction, and the two thumbs' flesh gap.
#
#   mbt-godot --headless --path /work/tools/hand3d --script res://thumb_pair_probe.gd
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


func _build(side: String) -> Dictionary:
	var base: Dictionary = HomePose.build(side, float(ROOTS[side]))
	var tgt: Vector3 = HomePose.target(side, "I", float(ROOTS[side]))
	var r: Dictionary = IK.solve_chain("I", tgt, base, HomePose._opts("I"))
	return {"pose": r["pose"], "err": r["error"], "target": tgt}


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
			var r1 := maxf(float(THUMB_R[i]), float(THUMB_R[i + 1]))
			var r2 := maxf(float(THUMB_R[k]), float(THUMB_R[k + 1]))
			var g := d - r1 - r2
			if g < worst:
				worst = g
				tag = "%d/%d" % [i, k]
	return [worst, tag]


func _init() -> void:
	var bl := _build("L")
	var br := _build("R")
	for side in ["L", "R"]:
		var b: Dictionary = bl if side == "L" else br
		var p: Dictionary = b["pose"]
		var xf := ArmModel.hand_transform(p["arm"])
		var fk: Dictionary = HandModel.thumb_fk(HandModel.thumb_of_pose(p))
		var pts: PackedVector3Array = fk["pts"]
		var names := ["base", "mcp ", "ip  ", "tip "]
		print("== %s  pad err %.4f  angles %s" % [side, float(b["err"]),
			str(HandModel.thumb_of_pose(p))])
		for i in 4:
			var w := _world(side, xf * pts[i])
			print("   %s %8.2f %8.2f %8.2f  r %.1f" % [names[i], w.x, w.y, w.z,
				float(THUMB_R[i])])
		var pad := _world(side, xf * HandModel.thumb_pad(fk))
		var d2 := (xf.basis * (fk["dirs"][2] as Vector3)).normalized()
		var tw := _world(side, b["target"] as Vector3)
		print("   pad  %8.2f %8.2f %8.2f   target %8.2f %8.2f %8.2f"
			% [pad.x, pad.y, pad.z, tw.x, tw.y, tw.z])
		print("   distal dir %6.3f %6.3f %6.3f  (z should be near -1 for a press)"
			% [d2.x, d2.y, d2.z])
	var g := _gap(bl["pose"], br["pose"])
	print("== flesh gap %.2f mm (%s)" % [float(g[0]), str(g[1])])
	quit(0)
