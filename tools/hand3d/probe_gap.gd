# From HOME with both guards on: how far short of the press does the solve
# stop, and WHICH joint is the one holding the hand up? Prints every joint's
# gap to the key face (z - r, negative = inside) for the final pose, and the
# same for the finger alone with the arm frozen.
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
	print("target %s ray %s" % [str(deep), ray])
	var home: Dictionary = HomePose.build(side, root_x)
	var base := {"arm": true, "thumb_dof": 4, "clear_z": Kbd3D.FACE_Z,
		"dir_w": 30.0, "tuck": false, "clear_w": 100.0, "idle_sink": 0.5,
		"pair_w": 100.0}
	_show("home", home, ray)
	var s: Dictionary = IK._solve_once(ray, deep, home, base)
	_show("from-home", s["pose"], ray)
	print("  err %.3f iters %d" % [float(s["error"]), int(s["iterations"])])
	var fr := {"arm": false, "thumb_dof": 4, "clear_z": Kbd3D.FACE_Z,
		"dir_w": 30.0, "tuck": false, "clear_w": 100.0, "idle_sink": 0.5}
	var sf: Dictionary = IK._solve_once(ray, deep, home, fr)
	_show("finger-only", sf["pose"], ray)
	print("  err %.3f" % float(sf["error"]))
	quit(0)


func _show(tag: String, p: Dictionary, ray: String) -> void:
	var xf := ArmModel.hand_transform(p.get("arm", {}))
	print("--- %s arm %s" % [tag, str(p.get("arm", {}))])
	for f in ["II", "III", "IV", "V"]:
		var pts: PackedVector3Array = HandModel.finger_fk(f,
			p["fingers"][f])["pts"]
		var rr: Array = HandModel.SKIN_R[f]
		var gaps := []
		for j in 4:
			var w: Vector3 = xf * pts[j]
			gaps.append("%s %6.2f" % ["MCP/PIP/DIP/TIP".split("/")[j],
				w.z - float(rr[j])])
		print("  %s %s" % [f, str(gaps)])
	var tpts: PackedVector3Array = HandModel.thumb_fk(
		HandModel.thumb_of_pose(p))["pts"]
	var tg := []
	for j in 4:
		var tw: Vector3 = xf * tpts[j]
		tg.append("%6.2f" % (tw.z - float(THUMB_R[j])))
	print("  I  %s   (CMC, MCP, IP, TIP)" % str(tg))
