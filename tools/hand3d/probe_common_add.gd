# Would curling the idle fingers by ONE shared share keep the path clean?
# Takes the natural press (exact pad) and only moves the idle fingers.
extends SceneTree
const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")
const IK := preload("res://ik.gd")
const Kbd3D := preload("res://kbd3d.gd")
const ClickPath := preload("res://click_path.gd")
const HomePose := preload("res://home_pose.gd")
const ROOTS := {"L": -72.51, "R": 43.94}

func _init() -> void:
	var ks := Kbd3D.keys()
	for c in [["R", "9"], ["L", "ё"], ["L", "е"]]:
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
		print("== %s %s %s" % [side, want, ray])
		for add in [-0.35, -0.30, -0.25, -0.20, -0.15, -0.10, 0.0]:
			var press: Dictionary = nat.duplicate(true)
			var xf := ArmModel.hand_transform(press["arm"])
			IK.clear_z = Kbd3D.FACE_Z
			IK.clear_hx = -1.0
			var v := 0.0
			for f in ["II", "III", "IV", "V"]:
				if f == ray:
					continue
				var s := IK.shares_of(f, press["fingers"][f])
				var a: Dictionary = IK._curled(f, s, add)
				press["fingers"][f] = a
				v = maxf(v, IK._finger_violation(xf, f, a, 0.0))
			IK.clear_z = -1e9
			var pp := press
			var pad := _pad(ray, pp)
			var lift := maxf(0.0, Kbd3D.FACE_Z + 12.0 - pad.z)
			var hp: Dictionary = pp.duplicate(true)
			hp["arm"]["elbow_z"] = float(hp["arm"].get("elbow_z", 0.0)) + lift
			var path: Dictionary = ClickPath.build(home, hp, pp, 0.35, 0.16,
				0.12, 0.40, {"ray": ray, "clear_z": Kbd3D.FACE_Z,
				"key_rects": _keys_local(side, rx), "own": Kbd3D.index_of(ks, want)})
			var total := float(path["total"])
			var worst := 0.0
			for i in 49:
				var t := total * float(i) / 48.0
				var p: Dictionary = ClickPath.at(path, t)
				var x2 := ArmModel.hand_transform(p["arm"])
				var pen := IK._pair_pen(x2, "II", p["fingers"]["II"], "III",
					p["fingers"]["III"])
				pen = maxf(pen, IK._pair_pen(x2, "III", p["fingers"]["III"], "IV",
					p["fingers"]["IV"]))
				pen = maxf(pen, IK._pair_pen(x2, "IV", p["fingers"]["IV"], "V",
					p["fingers"]["V"]))
				worst = maxf(worst, pen)
			print("  add %+.2f  key violation %5.2f  path worst %5.2f" % [add, v, worst])
	quit(0)

func _pad(ray: String, p: Dictionary) -> Vector3:
	var xf := ArmModel.hand_transform(p.get("arm", {}))
	return xf * HandModel.finger_pad(ray, HandModel.finger_fk(ray, p["fingers"][ray]))

func _keys_local(side: String, root_x: float) -> Array:
	var out := []
	for k in Kbd3D.keys():
		var r: Rect2 = k["r"]
		if side == "R":
			out.append(Rect2(-(r.end.x - root_x), r.position.y, r.size.x, r.size.y))
		else:
			out.append(Rect2(r.position.x - root_x, r.position.y, r.size.x, r.size.y))
	return out
