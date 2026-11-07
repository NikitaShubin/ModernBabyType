# Which thumb pose does the home target admit? The pad is one point and the
# thumb has four joints, so the solutions form a curve. The home solve takes the
# FIRST pose on that curve (its warm run stops as soon as the pad is within
# CHAIN_WARM_TOL), and that pose hooks the IP joint inboard: world x -5.0 on the
# left, +9.0 on the right, i.e. 17.4 mm between two 21.6 mm-thick capsules.
#
# This probe walks the same curve from several starts with the priors polished
# (a comfort run) and prints, for each, the energy and the IP joint's x. If a
# cheaper pose has the IP further out, the home solve can be steered to it.
#
#   mbt-godot --headless --path /work/tools/hand3d --script res://thumb_comfort_probe.gd
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


func _joints(side: String, p: Dictionary) -> Array:
	var xf := ArmModel.hand_transform(p.get("arm", {}))
	var fk: Dictionary = HandModel.thumb_fk(HandModel.thumb_of_pose(p))
	var out := []
	for i in 4:
		out.append(_world(side, xf * (fk["pts"] as PackedVector3Array)[i]))
	return out


func _energy(p: Dictionary) -> float:
	var s: Array = IK.thumb_shares_of(HandModel.thumb_of_pose(p))
	var e := 0.0
	for v in s:
		e += float(v) * float(v)
	return e


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


# The smallest flesh gap between the two thumbs' capsules (positive = clear).
func _gap(pl: Dictionary, pr: Dictionary) -> Array:
	var jl := _joints("L", pl)
	var jr := _joints("R", pr)
	var worst := 1e9
	var tag := ""
	for i in 3:
		for k in 3:
			var d := _seg_dist(jl[i], jl[i + 1], jr[k], jr[k + 1])
			var g := d - maxf(float(THUMB_R[i]), float(THUMB_R[i + 1])) \
				- maxf(float(THUMB_R[k]), float(THUMB_R[k + 1]))
			if g < worst:
				worst = g
				tag = "%d/%d" % [i, k]
	return [worst, tag]


func _show(tag: String, side: String, p: Dictionary, tgt: Vector3) -> void:
	var xf := ArmModel.hand_transform(p.get("arm", {}))
	var fk: Dictionary = HandModel.thumb_fk(HandModel.thumb_of_pose(p))
	var pad: Vector3 = _world(side, xf * HandModel.thumb_pad(fk))
	var j := _joints(side, p)
	var th: Dictionary = HandModel.thumb_of_pose(p)
	print("  %-14s E %7.4f  err %6.3f  IP x %7.2f  tip x %7.2f  pad x %7.2f  %s"
		% [tag, _energy(p), pad.distance_to(_world(side, tgt)), j[2].x, j[3].x,
		pad.x, str(th)])


func _scan(side: String) -> void:
	var root_x: float = ROOTS[side]
	var tgt: Vector3 = HomePose.target(side, "I", root_x)
	var base: Dictionary = HomePose.build(side, root_x)
	print("=== %s target root-relative %s  home thumb %s"
		% [side, str(tgt), str(HandModel.thumb_of_pose(base))])
	IK.thumb_dof = 4
	IK.dir_w = 0.0
	IK.hover_lift = 0.0
	IK.clear_w = 0.0
	var starts := []
	for a in [-0.6, 0.0, 0.6]:
		for b in [-0.6, 0.0, 0.6]:
			for m in [0.0, 0.4]:
				for i in [0.0, 0.5, 1.0]:
					starts.append([float(a), float(b), float(m), float(i)])
	var best := {}
	var best_e := 1e9
	for st in starts:
		var run: Dictionary = IK._chain_run("I", tgt, base, st, false, true)
		var p: Dictionary = run["cur"]["pose"]
		var e := _energy(p)
		if e < best_e - 1e-6:
			best_e = e
			best = p
	print("  cheapest of %d starts:" % starts.size())
	_show("cheapest", side, best, tgt)
	_home[side] = best
	# The plain solve the home pose actually takes, for comparison.
	var plain: Dictionary = IK._chain_run("I", tgt, base,
		IK.thumb_shares_of(HandModel.thumb_of_pose(base)), false, false)["cur"]["pose"]
	_show("warm (as now)", side, plain, tgt)
	_home[side + "_plain"] = plain


func _init() -> void:
	_scan("L")
	_scan("R")
	print("== two thumbs, gap of the flesh capsules (positive = clear):")
	print("  home as now   %7.2f mm  (%s)" % [_gap(_home["L_plain"], _home["R_plain"])[0],
		str(_gap(_home["L_plain"], _home["R_plain"])[1])])
	print("  cheapest      %7.2f mm  (%s)" % [_gap(_home["L"], _home["R"])[0],
		str(_gap(_home["L"], _home["R"])[1])])
	quit(0)
