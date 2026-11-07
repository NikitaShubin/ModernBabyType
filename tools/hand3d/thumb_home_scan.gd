# The two hands are NOT mirror images over this board: the home row is offset
# 0.75u left of the centre (Caps 1.75u on the left, Enter on the right) while
# the space bar is centred, so the left thumb reaches 30 mm inboard from its
# base and the right one hangs almost straight down. One shared twist cannot
# serve both: at t = 0 the left hooks and crosses; at t = -10 the left clears
# but the right misses its pad by 0.7 mm; further negative and the right is
# out of reach entirely.
#
# So the opposition is a POSTURE of each hand, and the posture may differ:
# this probe scans (twist, pad x, pad y) per hand and reports, among the poses
# that REACH the pad, the one whose IP joint is furthest OUTBOARD — that is the
# joint the two thumbs collide with.
#
#   mbt-godot --headless --path /work/tools/hand3d --script res://thumb_home_scan.gd
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")
const IK := preload("res://ik.gd")
const Kbd3D := preload("res://kbd3d.gd")
const HomePose := preload("res://home_pose.gd")

const ROOTS := {"L": -72.51, "R": 43.94}
const THUMB_R := [11.8, 10.8, 9.6, 6.6]
const LIFT := 2.0

var _home := {}


func _world(side: String, q: Vector3) -> Vector3:
	if side == "R":
		return Vector3(float(ROOTS[side]) - q.x, q.y, q.z)
	return Vector3(float(ROOTS[side]) + q.x, q.y, q.z)


func _solve(side: String, x: float, y: float) -> Dictionary:
	var root_x: float = ROOTS[side]
	var sgn := -1.0 if side == "R" else 1.0
	var wx := -x if side == "L" else x
	var tgt := Vector3((wx - root_x) * sgn, y, Kbd3D.FACE_Z + LIFT)
	return IK.solve_chain("I", tgt, _home[side], HomePose._opts("I"))


func _ip(side: String, p: Dictionary) -> Vector3:
	var xf := ArmModel.hand_transform(p["arm"])
	var fk: Dictionary = HandModel.thumb_fk(HandModel.thumb_of_pose(p))
	return _world(side, xf * (fk["pts"] as PackedVector3Array)[2])


func _pad(side: String, p: Dictionary) -> Vector3:
	var xf := ArmModel.hand_transform(p["arm"])
	var fk: Dictionary = HandModel.thumb_fk(HandModel.thumb_of_pose(p))
	return _world(side, xf * HandModel.thumb_pad(fk))


func _comfort(p: Dictionary) -> float:
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
			var r1 := maxf(float(THUMB_R[i]), float(THUMB_R[i + 1]))
			var r2 := maxf(float(THUMB_R[k]), float(THUMB_R[k + 1]))
			worst = minf(worst, d - r1 - r2)
	return worst


func _init() -> void:
	_home["L"] = HomePose.build("L", ROOTS["L"])
	_home["R"] = HomePose.build("R", ROOTS["R"])
	var y0 := Kbd3D.row_y(4)
	print("space y %.2f .. %.2f" % [y0 - Kbd3D.ROW_H * 0.5, y0 + Kbd3D.ROW_H * 0.5])
	var picks := {}
	for side in ["L", "R"]:
		var sgn := -1.0 if side == "L" else 1.0
		print("== %s: poses that reach (err < 0.1), outboard IP first" % side)
		var rows := []
		for tv in [-30.0, -25.0, -20.0, -15.0, -10.0, -5.0, 0.0]:
			var t: float = tv
			_home[side]["thumb_hold"] = {"twist": t}
			for xv in [20.5, 21.5, 22.5, 23.0]:
				var x: float = xv
				for yv in [104.0, 108.0, 112.0, 116.0, 118.5]:
					var y: float = yv
					var r := _solve(side, x, y)
					var p: Dictionary = r["pose"]
					var pad := _pad(side, p)
					var wx := -x if side == "L" else x
					var err := pad.distance_to(Vector3(wx, y, Kbd3D.FACE_Z + LIFT))
					var ip := _ip(side, p).x * sgn
					if err < 0.1:
						rows.append({"t": t, "x": x, "y": y, "err": err,
							"ip": _ip(side, p).x, "c": _comfort(p), "p": p})
		rows.sort_custom(func(a, b): return float(a["ip"]) * sgn > float(b["ip"]) * sgn)
		for i in mini(10, rows.size()):
			var b: Dictionary = rows[i]
			print("  t %6.1f x %5.1f y %6.1f | err %.3f  IP %7.2f  energy %6.3f  %s"
				% [float(b["t"]), float(b["x"]), float(b["y"]), float(b["err"]),
				float(b["ip"]), float(b["c"]),
				str(HandModel.thumb_of_pose(b["p"]))])
		picks[side] = rows[0]
	# The pair: the two most outboard poses, and their flesh gap.
	var pl: Dictionary = picks["L"]["p"]
	var pr: Dictionary = picks["R"]["p"]
	print("== pair: L IP %7.2f  R IP %7.2f  gap %6.2f mm"
		% [float(picks["L"]["ip"]), float(picks["R"]["ip"]), _gap(pl, pr)])
	quit(0)
