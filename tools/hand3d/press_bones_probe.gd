extends SceneTree
const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")
const IK := preload("res://ik.gd")
const Kbd3D := preload("res://kbd3d.gd")
const HomePose := preload("res://home_pose.gd")
func _init() -> void:
	var root_x := 43.94
	var home: Dictionary = HomePose.build("R", root_x)
	var ks := Kbd3D.keys()
	var w := Kbd3D.centre(ks[Kbd3D.index_of(ks, "глобус")])
	var local := Vector3(-(w.x - root_x), w.y, w.z - Kbd3D.TRAVEL)
	var r: Dictionary = IK.solve_chain("I", local, home,
		{"arm": true, "thumb_dof": 4, "clear_z": Kbd3D.FACE_Z + 3.0,
		"clear_w": 100.0, "dir_w": 30.0})
	var p: Dictionary = r["pose"]
	printerr("pose thumb_dof %d" % int(p.get("thumb_dof", -1)))
	printerr("pose thumb %s" % str(p.get("thumb", {})))
	var m := HandModel.new(1.0, 0.0, p)
	var xf := ArmModel.hand_transform(p["arm"])
	for b in m.bones:
		var nm := str(b["name"])
		if nm.begins_with("I "):
			printerr("%s  a %s  b %s" % [nm, str(b["a"]), str(b["b"])])
			printerr("   world a %s  b %s" % [str(xf * (b["a"] as Vector3)),
				str(xf * (b["b"] as Vector3))])
	var tfk: Dictionary = HandModel.thumb_fk(HandModel.thumb_of_pose(p))
	printerr("thumb_fk pts %s" % str(tfk["pts"]))
	printerr("pad %s" % str(HandModel.thumb_pad(tfk)))
	printerr("pad world %s" % str(xf * HandModel.thumb_pad(tfk)))
	quit(0)
