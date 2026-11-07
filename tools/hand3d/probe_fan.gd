extends SceneTree

const HandModel := preload("res://hand_model.gd")
const IK := preload("res://ik.gd")
const HomePose := preload("res://home_pose.gd")


func _init() -> void:
	var home: Dictionary = HomePose.build("L", -72.51)
	print("home:")
	for f in ["II", "III", "IV", "V"]:
		print("  %s %s" % [f, str(home["fingers"][f])])
	var r: Dictionary = IK.solve_chain("V", Vector3(20.0, 195.0, -71.6),
		home, {"arm": true, "thumb_dof": 4, "clear_z": -66.0,
		"clear_w": 100.0, "dir_w": 30.0, "tuck": false})
	print("press, tuck OFF:")
	for f in ["II", "III", "IV", "V"]:
		print("  %s %s" % [f, str(r["pose"]["fingers"][f])])
	var r2: Dictionary = IK.solve_chain("V", Vector3(20.0, 195.0, -71.6),
		home, {"arm": true, "thumb_dof": 4, "clear_z": -66.0,
		"clear_w": 100.0, "dir_w": 30.0, "tuck": true})
	print("press, tuck ON:")
	for f in ["II", "III", "IV", "V"]:
		print("  %s %s" % [f, str(r2["pose"]["fingers"][f])])
	quit(0)
