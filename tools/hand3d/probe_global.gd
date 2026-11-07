# Does the GLOBAL idle_sink change solve_chain's result, opts being equal?
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")
const IK := preload("res://ik.gd")
const Kbd3D := preload("res://kbd3d.gd")
const HomePose := preload("res://home_pose.gd")


func _init() -> void:
	var deep := Vector3(10.5975, 152.0, Kbd3D.FACE_Z - Kbd3D.TRAVEL)
	for g in [0.0, 0.5]:
		var home: Dictionary = HomePose.build("L", -72.51)
		IK.idle_sink = g
		print("home III %s arm %s" % [str(home["fingers"]["III"]), str(home["arm"])])
		var pr: Dictionary = IK.solve_chain("III", deep, home,
			{"arm": true, "thumb_dof": 4, "clear_z": Kbd3D.FACE_Z,
			"clear_w": 100.0, "idle_sink": 0.5, "dir_w": 30.0})
		var p: Dictionary = pr["pose"]
		print("global %s -> elbow_z %s fan %s wrist_flex %s" % [str(g),
			str(float(p["arm"]["elbow_z"])), str(float(p["fingers"]["III"]["fan"])),
			str(float(p["arm"]["wrist_flex"]))])
		print("   II %s" % str(p["fingers"]["II"]))
		print("   III %s" % str(p["fingers"]["III"]))
		print("   thumb %s" % str(p.get("thumb", {})))
	IK.idle_sink = 0.0
	quit(0)
