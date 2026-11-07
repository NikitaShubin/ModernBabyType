# The twist is the right joint for the job — it turns the plane the distal
# phalanges fold in, which is exactly what the hook needs. But left FREE it is
# cheap in the energy model and the solver folds the thumb ACROSS the palm
# instead (IP at world x 0 instead of -5, gap -15 mm). The joint must be
# PINNED at a value the two hands can both live with, not handed to the solver.
#
# This probe pins the twist by shrinking its ROM to a point (share -> +-1, the
# angle cannot move) and re-solves the other four joints for the home target.
# It prints the pad error, the IP joint's world x and the two thumbs' flesh gap
# for every pinned angle.
#
#   mbt-godot --headless --path /work/tools/hand3d --script res://thumb_twist_scan.gd
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")
const IK := preload("res://ik.gd")
const HomePose := preload("res://home_pose.gd")

const ROOTS := {"L": -72.51, "R": 43.94}
const THUMB_R := [11.8, 10.8, 9.6, 6.6]

var _home := {}


func _world(side: String, q: Vector3) -> Vector3:
	if side == "R":
		return Vector3(float(ROOTS[side]) - q.x, q.y, q.z)
	return Vector3(float(ROOTS[side]) + q.x, q.y, q.z)


func _solve(side: String) -> Dictionary:
	var base: Dictionary = _home[side]
	var tgt: Vector3 = HomePose.target(side, "I", float(ROOTS[side]))
	return IK.solve_chain("I", tgt, base, HomePose._opts("I"))


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


func _gap(pl: Dictionary, pr: Dictionary) -> float:
	var xl := ArmModel.hand_transform(pl["arm"])
	var xr := ArmModel.hand_transform(pr["arm"])
	var jl: PackedVector3Array = HandModel.thumb_fk(HandModel.thumb_of_pose(pl))["pts"]
	var jr: PackedVector3Array = HandModel.thumb_fk(HandModel.thumb_of_pose(pr))["pts"]
	var worst := 1e9
	for i in 3:
		for k in 3:
			var d := _seg_dist(_world("L", xl * jl[i]), _world("L", xl * jl[i + 1]),
				_world("R", xr * jr[k]), _world("R", xr * jr[k + 1]))
			worst = minf(worst, d - maxf(float(THUMB_R[i]), float(THUMB_R[i + 1]))
				- maxf(float(THUMB_R[k]), float(THUMB_R[k + 1])))
	return worst


func _init() -> void:
	_home["L"] = HomePose.build("L", ROOTS["L"])
	_home["R"] = HomePose.build("R", ROOTS["R"])
	_home["L"].erase("thumb_hold")
	_home["R"].erase("thumb_hold")
	print("free twist (wide ROM):")
	var rl0 := _solve("L")
	var rr0 := _solve("R")
	print("  L ip %7.2f  R ip %7.2f  gap %6.2f  L %s" % [_ip("L", rl0["pose"]).x,
		_ip("R", rr0["pose"]).x, _gap(rl0["pose"], rr0["pose"]),
		str(HandModel.thumb_of_pose(rl0["pose"]))])
	print("  twist %7.3f / %7.3f" % [float(HandModel.thumb_of_pose(rl0["pose"])["twist"]),
		float(HandModel.thumb_of_pose(rr0["pose"])["twist"])])
	print("pinned twist:")
	print("   t   | L pad err  L ip x | R pad err  R ip x | gap")
	for tv in [-30.0, -25.0, -20.0, -15.0, -10.0, -5.0, 0.0, 10.0, 20.0, 30.0]:
		var t: float = tv
		_home["L"]["thumb_hold"] = {"twist": t}
		_home["R"]["thumb_hold"] = {"twist": t}
		var rl := _solve("L")
		var rr := _solve("R")
		var tl: Dictionary = HandModel.thumb_of_pose(rl["pose"])
		var tr: Dictionary = HandModel.thumb_of_pose(rr["pose"])
		var el: float = _pad("L", rl["pose"]).distance_to(
			_world("L", HomePose.target("L", "I", ROOTS["L"])))
		var er: float = _pad("R", rr["pose"]).distance_to(
			_world("R", HomePose.target("R", "I", ROOTS["R"])))
		print("%5.0f | %8.3f %8.2f | %8.3f %8.2f | %6.2f   L ip %6.2f  R ip %6.2f"
			% [t, el, _ip("L", rl["pose"]).x, er, _ip("R", rr["pose"]).x,
			_gap(rl["pose"], rr["pose"]), float(tl["ip"]), float(tr["ip"])])
	quit(0)
