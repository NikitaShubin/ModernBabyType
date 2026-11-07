# The right thumb's resting arch as a function of its held twist: the MCP's
# height above the CMC and the pair's flesh gap to the left thumb.
extends SceneTree
const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")
const IK := preload("res://ik.gd")
const Kbd3D := preload("res://kbd3d.gd")
const HomePose := preload("res://home_pose.gd")
const ROOTS := {"L": -72.51, "R": 43.94}
const THUMB_R := [11.8, 10.8, 9.6, 6.6]

func _init() -> void:
	var homeL: Dictionary = HomePose.build("L", ROOTS["L"])
	var baseR: Dictionary = HomePose.build("R", ROOTS["R"])
	var tgtL := HomePose.target("L", "I", ROOTS["L"])
	for tw in [-30.0, -25.0, -20.0, -15.0, -10.0, -5.0]:
		var p: Dictionary = baseR.duplicate(true)
		p["thumb_hold"] = {"twist": tw}
		p["thumb"] = HandModel.thumb_at(0.0)
		var r: Dictionary = IK.solve_chain("I", HomePose.target("R", "I", ROOTS["R"]), p,
			{"arm": false, "thumb_dof": 4, "clear_z": -1e9, "clear_w": 0.0,
			"tuck": false})
		var q: Dictionary = r["pose"]
		var xf := ArmModel.hand_transform(q["arm"])
		var tp: PackedVector3Array = HandModel.thumb_fk(HandModel.thumb_of_pose(q))["pts"]
		var w := []
		for j in 4:
			w.append(_w("R", ROOTS["R"], xf * tp[j]))
		var gap := _gap(homeL, q)
		print("twist %5.1f  arch %5.2f  mcp_x %6.2f  pad (%6.2f %6.2f %6.2f)  gap %6.2f  err %.2f" % [
			tw, w[1].z - w[0].z, w[1].x, w[3].x, w[3].y, w[3].z, gap,
			w[3].distance_to(HomePose.target("R", "I", ROOTS["R"]))])
	quit(0)

func _gap(pL: Dictionary, pR: Dictionary) -> float:
	var worst := 1e9
	var xfL := ArmModel.hand_transform(pL["arm"])
	var xfR := ArmModel.hand_transform(pR["arm"])
	var a: PackedVector3Array = HandModel.thumb_fk(HandModel.thumb_of_pose(pL))["pts"]
	var b: PackedVector3Array = HandModel.thumb_fk(HandModel.thumb_of_pose(pR))["pts"]
	for i in 3:
		for j in 3:
			var d := _seg_dist(_w("L", ROOTS["L"], xfL * a[i]),
				_w("L", ROOTS["L"], xfL * a[i + 1]),
				_w("R", ROOTS["R"], xfR * b[j]),
				_w("R", ROOTS["R"], xfR * b[j + 1]))
			worst = minf(worst, d - maxf(float(THUMB_R[i]), float(THUMB_R[i + 1]))
				- maxf(float(THUMB_R[j]), float(THUMB_R[j + 1])))
	return worst

func _w(side: String, root_x: float, q: Vector3) -> Vector3:
	if side == "R":
		return Vector3(root_x - q.x, q.y, q.z)
	return Vector3(root_x + q.x, q.y, q.z)

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
	var c1 := p1 + d1 * s
	var c2 := p2 + d2 * t
	return c1.distance_to(c2)
