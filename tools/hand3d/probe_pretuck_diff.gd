# Which idle fingers does the pre-tuck actually move, and by how much?
extends SceneTree
const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")
const IK := preload("res://ik.gd")
const Kbd3D := preload("res://kbd3d.gd")
const HomePose := preload("res://home_pose.gd")
const ROOTS := {"L": -72.51, "R": 43.94}

func _init() -> void:
	var ks := Kbd3D.keys()
	for c in [["R", "9"], ["L", "ё"], ["L", "е"], ["R", "8"]]:
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
		var nat: Dictionary = IK._solve_once(ray, deep, home,
			{"arm": true, "thumb_dof": 4, "clear_w": 0.0, "tuck": false})["pose"]
		var pre: Dictionary = nat.duplicate(true)
		IK._pretuck(ray, pre, {"clear_z": Kbd3D.FACE_Z, "clear_w": 100.0})
		print("== %s %s %s" % [side, want, ray])
		for f in ["II", "III", "IV", "V"]:
			if f == ray:
				continue
			var a: Dictionary = nat["fingers"][f]
			var b: Dictionary = pre["fingers"][f]
			print("   %s  %s -> %s" % [f, str(_a(a)), str(_a(b))])
	quit(0)

func _a(a: Dictionary) -> Array:
	return [snappedf(float(a["mcp"]), 0.1), snappedf(float(a["pip"]), 0.1),
		snappedf(float(a["dip"]), 0.1), snappedf(float(a["fan"]), 0.1)]
