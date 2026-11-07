extends SceneTree

const HandModel := preload("res://hand_model.gd")
const IK := preload("res://ik.gd")
const HomePose := preload("res://home_pose.gd")

func _init() -> void:
	var home: Dictionary = HomePose.build("L", -72.51)
	print("home thumb %s" % str(HandModel.thumb_of_pose(home)))
	var tgt: Vector3 = HomePose.target("L", "I", -72.51)
	print("target %s" % str(tgt))
	var r: Dictionary = IK.solve_chain("I", tgt, home, HomePose._opts("I"))
	print("err %f angles %s" % [float(r["error"]), str(HandModel.thumb_of_pose(r["pose"]))])
	quit(0)
