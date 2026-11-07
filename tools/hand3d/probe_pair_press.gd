# A bad case from the full run: what the pre-tuck does to the idle index and
# middle, and whether the press pose itself is clean.
extends SceneTree
const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")
const IK := preload("res://ik.gd")
const Kbd3D := preload("res://kbd3d.gd")
const HomePose := preload("res://home_pose.gd")
const ROOTS := {"L": -72.51, "R": 43.94}

func _init() -> void:
	var ks := Kbd3D.keys()
	for c in [["R", "9"], ["R", "8"], ["L", "ё"], ["L", "е"]]:
		var side := String(c[0])
		var want := String(c[1])
		var k: Dictionary = ks[Kbd3D.index_of(ks, want)]
		var r: Rect2 = k["r"]
		var hx := r.get_center().x
		if r.size.x > Kbd3D.KEY_W * 1.05:
			hx = r.get_center().x + (-0.6 if side == "L" else 0.6) * r.size.x * 0.5
		var ray := String(Kbd3D.hand_finger(want, hx)[1])
		var rx: float = ROOTS[side]
		var home: Dictionary = HomePose.build(side, rx)
		var deep := Vector3(hx - rx, r.get_center().y, Kbd3D.FACE_Z - Kbd3D.TRAVEL)
		if side == "R":
			deep.x = -(hx - rx)
		for pre in [true, false]:
			var pr: Dictionary = IK.solve_chain(ray, deep, home,
				{"arm": true, "thumb_dof": 4, "clear_z": Kbd3D.FACE_Z,
				"clear_w": 100.0, "dir_w": 30.0, "pretuck": pre})
			var p: Dictionary = pr["pose"]
			var xf := ArmModel.hand_transform(p["arm"])
			var worst := 0.0
			var tag := ""
			var tmp := []
			IK.pair_w = 100.0
			IK._pair_residuals(xf, p, home, tmp)
			IK.pair_w = 0.0
			for i in tmp.size():
				if absf(float(tmp[i])) > worst:
					worst = absf(float(tmp[i]))
			print("%s %-2s %-3s pre %-5s err %.2f arm z %6.2f  II %s  III %s" % [
				side, want, ray, str(pre), float(pr["error"]),
				float(p["arm"]["elbow_z"]), str(_a(p["fingers"]["II"])),
				str(_a(p["fingers"]["III"]))])
			print("      worst pair residual %.2f  home II %s III %s" % [worst,
				str(_a(home["fingers"]["II"])), str(_a(home["fingers"]["III"]))])
	quit(0)

func _a(a: Dictionary) -> Array:
	return [snappedf(float(a["mcp"]), 0.1), snappedf(float(a["pip"]), 0.1),
		snappedf(float(a["dip"]), 0.1), snappedf(float(a["fan"]), 0.1)]
