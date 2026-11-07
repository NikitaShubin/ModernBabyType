# The thumb's tuck candidate scan on the final press pose of one key: keyboard
# violation and capsule penetration against the fingers, for every uniform
# flexion add. The question: is there a candidate that clears BOTH, and if so
# why did the tuck not take it?
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")
const IK := preload("res://ik.gd")
const Kbd3D := preload("res://kbd3d.gd")
const HomePose := preload("res://home_pose.gd")

const ROOTS := {"L": -72.51, "R": 43.94}


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
	var pr: Dictionary = IK.solve_chain(ray, deep, home,
		{"arm": true, "thumb_dof": 4, "clear_z": Kbd3D.FACE_Z,
		"clear_w": 100.0, "dir_w": 30.0})
	var p: Dictionary = pr["pose"]
	print("=== %s %s ray %s thumb %s" % [side, want, ray,
		str(HandModel.thumb_of_pose(p))])
	var xf := ArmModel.hand_transform(p["arm"])
	var cur: Dictionary = HandModel.thumb_of_pose(p)
	print("current viol %.2f pairs %.2f" % [
		IK._thumb_violation(xf, cur),
		IK._thumb_pairs(xf, HandModel.thumb_fk(cur), p["fingers"])])
	var hold: Dictionary = p.get("thumb_hold", {})
	var free := []
	for j in ["cmc_flex", "mcp", "ip"]:
		if not hold.has(j):
			free.append(HandModel.THUMB_JOINTS.find(j))
	var q0: Array = IK.thumb_shares_of(cur, hold)
	for it in 81:
		var add := -1.0 + 2.0 * float(it) / 80.0
		var cand: Array = q0.duplicate()
		for i in free:
			cand[i] = clampf(float(q0[i]) + add, -1.0, 1.0)
		var a: Dictionary = IK.thumb_angles_of_shares(cand, hold)
		var v := IK._thumb_violation(xf, a)
		var pen := IK._thumb_pairs(xf, HandModel.thumb_fk(a), p["fingers"])
		if v <= 0.05 or pen <= 0.15 or absf(add) < 0.05:
			print("  add %6.3f viol %6.2f pen %5.2f angles %s" % [add, v, pen,
				str(a)])
	quit(0)
