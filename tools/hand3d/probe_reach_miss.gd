# Why L «е» II stops 0.64 mm short: the same solve with and without the pair
# guard, and which pair is actually pressing.
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
	for want in ["е", "3", "6", "и"]:
		var idx := Kbd3D.index_of(ks, want)
		var k: Dictionary = ks[idx]
		var r: Rect2 = k["r"]
		var xy := r.get_center()
		var hf := Kbd3D.hand_finger(want, xy.x)
		if int(hf[0]) != 0:
			continue
		var ray := String(hf[1])
		var deep := Vector3(xy.x - ROOTS["L"], xy.y, Kbd3D.FACE_Z - Kbd3D.TRAVEL)
		for cfg in [["full", 100.0, 100.0, 30.0], ["noclear", 100.0, 0.0, 30.0],
				["nodir", 100.0, 100.0, 0.0], ["bare", 0.0, 0.0, 0.0]]:
			var res: Dictionary = IK.solve_chain(ray, deep, home,
				{"arm": true, "thumb_dof": 4, "clear_z": Kbd3D.FACE_Z,
				"clear_w": float(cfg[2]), "dir_w": float(cfg[3]),
				"pair_w": float(cfg[1])})
			var p: Dictionary = res["pose"]
			var xf := ArmModel.hand_transform(p["arm"])
			var worst := 0.0
			var tag := ""
			var tmp := []
			IK.pair_w = 100.0
			IK._pair_residuals(xf, p, home, tmp)
			IK.pair_w = 0.0
			print("%s %-7s %s err %5.2f fan %5.1f mcp %5.1f | %s" % [
				cfg[0], want, ray, float(res["error"]),
				float(p["fingers"][ray]["fan"]), float(p["fingers"][ray]["mcp"]),
				str(_pairs(xf, p, home))])
	quit(0)

func _pairs(xf: Transform3D, p: Dictionary, base: Dictionary) -> Array:
	var out := []
	var names := [["II", "III"], ["II", "IV"], ["II", "V"], ["III", "IV"],
		["III", "V"], ["IV", "V"]]
	for nm in names:
		var v := IK._pair_pen(xf, String(nm[0]), p["fingers"][nm[0]],
			String(nm[1]), p["fingers"][nm[1]])
		if v > 0.05:
			out.append("%s/%s %.2f" % [nm[0], nm[1], v])
	var tfk: Dictionary = HandModel.thumb_fk(HandModel.thumb_of_pose(p))
	for f in HandModel.FINGERS:
		var v := IK._thumb_pair_pen(xf, tfk, f, p["fingers"][f])
		if v > 0.05:
			out.append("I/%s %.2f" % [f, v])
	return out
