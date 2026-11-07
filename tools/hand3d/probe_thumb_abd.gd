# The thumb's abduction against the keyboard and against the index: on the
# final press pose, with the tuck's flexion fixed, scan cmc_abd and print the
# keyboard violation and the I/II penetration. The question: is there an
# abduction that clears the keycaps without driving the thumb into the index?
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
	var xf := ArmModel.hand_transform(p["arm"])
	var cur: Dictionary = HandModel.thumb_of_pose(p)
	print("=== %s %s ray %s thumb %s" % [side, want, ray, str(cur)])
	print("  cur viol %.2f I/II %.2f" % [IK._thumb_violation(xf, cur),
		IK._thumb_pairs(xf, HandModel.thumb_fk(cur), p["fingers"])])
	var a := cur.duplicate()
	for it in 56:
		var abd := -25.0 + float(it)
		a["cmc_abd"] = abd
		var v := IK._thumb_violation(xf, a)
		var pen := IK._thumb_pairs(xf, HandModel.thumb_fk(a), p["fingers"])
		if it % 5 == 0 or (v <= 0.05 and pen <= 0.2):
			print("  abd %6.1f viol %6.2f pen %5.2f" % [abd, v, pen])
	quit(0)
