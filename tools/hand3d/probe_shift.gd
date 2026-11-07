# How far a press moves the arm away from HOME, for every key of the board.
# The crossing test says whether a pose is legal; this says whether it is a
# hand. Prints, per key: the reach the solve still owes, the wrist and forearm
# change from home in degrees, the elbow change in mm, and the thumb's own
# excursion. The worst offender at the end.
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")
const IK := preload("res://ik.gd")
const Kbd3D := preload("res://kbd3d.gd")
const HomePose := preload("res://home_pose.gd")

const ROOTS := {"L": -72.51, "R": 43.94}
const WRIST_W := 1.0
const FORE_W := 0.25
const ELBOW_W := 0.02


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var only := String(args[0]) if args.size() > 0 else ""
	var ks: Array = Kbd3D.keys()
	var rows := []
	for side in ["L", "R"]:
		var home: Dictionary = HomePose.build(side, float(ROOTS[side]))
		var ha: Dictionary = home["arm"]
		for idx in ks.size():
			var key: Dictionary = ks[idx]
			if int(key["hand"]) != (Kbd3D.LEFT if side == "L" else Kbd3D.RIGHT):
				continue
			var label := String(key["s"])
			if only != "" and label != only:
				continue
			var r: Rect2 = key["r"]
			var hx := r.get_center().x
			if r.size.x > Kbd3D.KEY_W * 1.05:
				hx = r.get_center().x + (-0.6 if side == "L" else 0.6) \
					* r.size.x * 0.5
			var hit := Vector2(hx, r.get_center().y)
			var ray := String(Kbd3D.hand_finger(label, hx)[1])
			var root_x: float = ROOTS[side]
			var sgn := -1.0 if side == "R" else 1.0
			var deep := Vector3((hit.x - root_x) * sgn, hit.y,
				Kbd3D.FACE_Z - Kbd3D.TRAVEL)
			var pr: Dictionary = IK.solve_chain(ray, deep, home,
				{"arm": true, "thumb_dof": 4, "clear_z": Kbd3D.FACE_Z,
				"clear_w": 100.0, "dir_w": 30.0})
			var pa: Dictionary = pr["pose"]["arm"]
			var dwf := absf(float(pa["wrist_flex"]) - float(ha["wrist_flex"]))
			var dwd := absf(float(pa["wrist_dev"]) - float(ha["wrist_dev"]))
			var dpr := absf(float(pa["pronation"]) - float(ha["pronation"]))
			var dff := absf(float(pa["forearm_flex"]) - float(ha["forearm_flex"]))
			var dfa := absf(float(pa["forearm_abd"]) - float(ha["forearm_abd"]))
			var de := Vector3(float(pa["elbow_x"]) - float(ha["elbow_x"]),
				float(pa["elbow_y"]) - float(ha["elbow_y"]),
				float(pa["elbow_z"]) - float(ha["elbow_z"]))
			var cost := WRIST_W * (dwf + dwd) + WRIST_W * dpr \
				+ FORE_W * (dff + dfa) + ELBOW_W * de.length()
			rows.append([cost, "%s %-6s %-3s err %5.2f | wrist %5.1f/%5.1f "
				% [side, label, ray, float(pr["error"]), dwf, dwd]
				+ "pron %5.1f | fore %5.1f/%5.1f | elbow %5.1f  "
				% [dpr, dff, dfa, de.length()]
				+ "arm %s" % str(pa)])
	rows.sort_custom(func(a, b): return float(a[0]) > float(b[0]))
	for row in rows:
		print("%6.1f  %s" % [float(row[0]), String(row[1])])
	quit(0)
