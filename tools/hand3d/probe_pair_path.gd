# The path of one bad case, frame by frame: where the idle index and middle
# cross, and what their angles are doing there.
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
	for c in [["R", "9"], ["L", "ё"]]:
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
			var pp: Dictionary = pr["pose"]
			var pad := _pad(ray, pp)
			var lift := maxf(0.0, Kbd3D.FACE_Z + 12.0 - pad.z)
			var hp: Dictionary = pp.duplicate(true)
			hp["arm"]["elbow_z"] = float(hp["arm"].get("elbow_z", 0.0)) + lift
			var path: Dictionary = ClickPath.build(home, hp, pp, 0.35, 0.16,
				0.12, 0.40, {"ray": ray, "clear_z": Kbd3D.FACE_Z,
				"key_rects": _keys_local(side, rx), "own": Kbd3D.index_of(ks, want)})
			var total := float(path["total"])
			print("== %s %s %s pre %s" % [side, want, ray, str(pre)])
			for i in 25:
				var t := total * float(i) / 24.0
				var p: Dictionary = ClickPath.at(path, t)
				var xf := ArmModel.hand_transform(p["arm"])
				var pen := IK._pair_pen(xf, "II", p["fingers"]["II"], "III",
					p["fingers"]["III"])
				var a: Dictionary = p["fingers"]["II"]
				var b: Dictionary = p["fingers"]["III"]
				if pen > 0.05 or i % 6 == 0:
					print("  t %5.2f pen %5.2f  II %5.1f %5.1f %5.1f f%5.1f  III %5.1f %5.1f %5.1f f%5.1f  z %6.1f" % [
						t, pen, float(a["mcp"]), float(a["pip"]), float(a["dip"]),
						float(a["fan"]), float(b["mcp"]), float(b["pip"]),
						float(b["dip"]), float(b["fan"]), float(p["arm"]["elbow_z"])])
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
