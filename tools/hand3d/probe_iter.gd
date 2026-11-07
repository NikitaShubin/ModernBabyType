# The fixed point the click needs: the solver cannot move the idle fingers, the
# tuck can, and the tuck does not know what the arm will do. So alternate —
# solve, tuck, solve again — and watch whether the placement settles into a
# pose that both reaches and clears, or keeps sliding.
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")
const IK := preload("res://ik.gd")
const Kbd3D := preload("res://kbd3d.gd")
const HomePose := preload("res://home_pose.gd")

const ROOTS := {"L": -72.51, "R": 43.94}
const THUMB_R := [11.8, 10.8, 9.6, 6.6]


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var side := String(args[0]) if args.size() > 0 else "L"
	var want := String(args[1]) if args.size() > 1 else "3"
	var keys := Kbd3D.keys()
	var key: Dictionary = keys[Kbd3D.index_of(keys, want)]
	var r: Rect2 = key["r"]
	var hx := r.get_center().x
	if r.size.x > Kbd3D.KEY_W * 1.05:
		hx = r.get_center().x + (-0.6 if side == "L" else 0.6) \
			* r.size.x * 0.5
	var hit := Vector2(hx, r.get_center().y)
	var ray := String(Kbd3D.hand_finger(want, hx)[1])
	var root_x: float = ROOTS[side]
	var sgn := -1.0 if side == "R" else 1.0
	var deep := Vector3((hit.x - root_x) * sgn, hit.y,
		Kbd3D.FACE_Z - Kbd3D.TRAVEL)
	var home: Dictionary = HomePose.build(side, root_x)
	var opts := {"arm": true, "thumb_dof": 4, "clear_z": Kbd3D.FACE_Z,
		"dir_w": 30.0, "clear_w": 100.0, "idle_sink": 0.5,
		"pair_w": 100.0}
	var p := home
	for it in 8:
		var s: Dictionary = IK._solve_once(ray, deep, p, opts)
		p = s["pose"]
		var xf := ArmModel.hand_transform(p["arm"])
		var clr := IK.clearance(ray, p, Kbd3D.FACE_Z, Rect2(), 0.0)
		var ip := _thumb_finger(xf, p, "II")
		print("%d err %6.2f keyclr %6.2f I/II %5.2f II/III %5.2f  elbow_z %7.2f "
			% [it, float(s["error"]), clr, ip, _pair(xf, p, "II", "III"),
			float(p["arm"]["elbow_z"])]
			+ "wdev %6.2f fabd %6.2f thumb %s"
			% [float(p["arm"]["wrist_dev"]), float(p["arm"]["forearm_abd"]),
			str(_t(p))])
	quit(0)


func _t(p: Dictionary) -> Array:
	var a: Dictionary = HandModel.thumb_of_pose(p)
	return [snappedf(float(a["cmc_flex"]), 0.1), snappedf(float(a["cmc_abd"]), 0.1),
		snappedf(float(a["mcp"]), 0.1), snappedf(float(a["ip"]), 0.1)]


func _thumb_finger(xf: Transform3D, p: Dictionary, ray: String) -> float:
	var tpts: PackedVector3Array = HandModel.thumb_fk(
		HandModel.thumb_of_pose(p))["pts"]
	var pts: PackedVector3Array = HandModel.finger_fk(ray,
		p["fingers"][ray])["pts"]
	var worst := 0.0
	for i in 3:
		for j in 3:
			var d := _seg_dist(xf * tpts[i], xf * tpts[i + 1],
				xf * pts[j], xf * pts[j + 1])
			var rr := maxf(float(THUMB_R[i]), float(THUMB_R[i + 1])) \
				+ maxf(float(HandModel.SKIN_R[ray][j]),
					float(HandModel.SKIN_R[ray][j + 1]))
			worst = maxf(worst, rr - d)
	return worst


func _pair(xf: Transform3D, p: Dictionary, a: String, b: String) -> float:
	var pa: PackedVector3Array = HandModel.finger_fk(a,
		p["fingers"][a])["pts"]
	var pb: PackedVector3Array = HandModel.finger_fk(b,
		p["fingers"][b])["pts"]
	var worst := 0.0
	for i in range(1, 3):
		for j in range(1, 3):
			var d := _seg_dist(xf * pa[i], xf * pa[i + 1],
				xf * pb[j], xf * pb[j + 1])
			var rr := maxf(float(HandModel.SKIN_R[a][i]),
				float(HandModel.SKIN_R[a][i + 1])) \
				+ maxf(float(HandModel.SKIN_R[b][j]),
					float(HandModel.SKIN_R[b][j + 1]))
			worst = maxf(worst, rr - d)
	return worst


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
