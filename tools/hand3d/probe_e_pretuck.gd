# Does pre-tucking the natural press (so the refine sees tucked idle fingers)
# let L «е» II reach while the clearance is on?
extends SceneTree
const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")
const IK := preload("res://ik.gd")
const Kbd3D := preload("res://kbd3d.gd")
const HomePose := preload("res://home_pose.gd")
const ROOTS := {"L": -72.51, "R": 43.94}

func _init() -> void:
	var ks := Kbd3D.keys()
	var home: Dictionary = HomePose.build("L", ROOTS["L"])
	for want in ["е", "в", "3", "6", "и"]:
		var k: Dictionary = ks[Kbd3D.index_of(ks, want)]
		var r: Rect2 = k["r"]
		var xy := r.get_center()
		var hf := Kbd3D.hand_finger(want, xy.x)
		if int(hf[0]) != 0:
			continue
		var ray := String(hf[1])
		var deep := Vector3(xy.x - ROOTS["L"], xy.y, Kbd3D.FACE_Z - Kbd3D.TRAVEL)
		var opts := {"arm": true, "thumb_dof": 4, "clear_z": Kbd3D.FACE_Z,
			"clear_w": 100.0, "dir_w": 30.0, "pair_w": 100.0}
		var now: Dictionary = IK.solve_chain(ray, deep, home, opts)
		var warm := opts.duplicate(true)
		warm["clear_w"] = 0.0
		warm["tuck"] = false
		var nat: Dictionary = IK._solve_once(ray, deep, home, warm)
		var pre: Dictionary = (nat["pose"] as Dictionary).duplicate(true)
		IK._pretuck(ray, pre, opts)
		var res: Dictionary = IK.solve_chain(ray, deep, pre, opts)
		for tag in [["now", now], ["pre", res]]:
			var p: Dictionary = tag[1]["pose"]
			var ang: Dictionary = p["fingers"][ray]
			print("%-4s %-3s err %.3f  mcp %.1f pip %.1f dip %.1f fan %.1f  arm %s" % [
				tag[0], want, float(tag[1]["error"]), float(ang["mcp"]),
				float(ang["pip"]), float(ang["dip"]), float(ang["fan"]),
				str(_arm(p["arm"]))])
	quit(0)

func _arm(a: Dictionary) -> Array:
	var out := []
	for j in ArmModel.ALL_JOINTS:
		out.append("%s %.1f" % [j, float(a[j])])
	return out
