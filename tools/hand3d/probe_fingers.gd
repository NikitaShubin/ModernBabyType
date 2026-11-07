extends SceneTree
const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")
const IK := preload("res://ik.gd")
const Kbd3D := preload("res://kbd3d.gd")
const HomePose := preload("res://home_pose.gd")
const ROOTS := {"L": -72.51, "R": 43.94}

func _init() -> void:
	var keys := Kbd3D.keys()
	var want := "Alt"
	var idx := Kbd3D.index_of(keys, want)
	var r: Rect2 = keys[idx]["r"]
	var hx := r.get_center().x - 0.6 * r.size.x * 0.5
	var ray := String(Kbd3D.hand_finger(want, hx)[1])
	var deep := Vector3(hx - ROOTS["L"], r.get_center().y, Kbd3D.FACE_Z - Kbd3D.TRAVEL)
	var home: Dictionary = HomePose.build("L", ROOTS["L"])
	var pr: Dictionary = IK.solve_chain(ray, deep, home,
		{"arm": true, "thumb_dof": 4, "clear_z": Kbd3D.FACE_Z,
		"clear_w": 100.0, "dir_w": 30.0})
	for tag in [["home", home], ["press", pr["pose"]]]:
		var p: Dictionary = tag[1]
		var xf := ArmModel.hand_transform(p["arm"])
		print("%s arm %s" % [tag[0], str(p["arm"])])
		for f in HandModel.FINGERS:
			var a: Dictionary = p["fingers"][f]
			var pts: PackedVector3Array = HandModel.finger_fk(f, a)["pts"]
			var mc: Vector3 = xf * HandModel.MC_BASE[f]
			var pad: Vector3 = xf * HandModel.finger_pad(f, HandModel.finger_fk(f, a))
			print("  %s mcp %5.1f pip %5.1f dip %5.1f fan %6.1f | mc (%6.1f %6.1f) pad (%6.1f %6.1f)" % [
				f, float(a["mcp"]), float(a["pip"]), float(a["dip"]), float(a["fan"]),
				mc.x, mc.y, pad.x, pad.y])
	quit(0)
