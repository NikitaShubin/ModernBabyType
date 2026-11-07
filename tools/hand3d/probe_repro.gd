# Reproduce probe_press_home step by step to find which pre-call matters.
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")
const IK := preload("res://ik.gd")
const Kbd3D := preload("res://kbd3d.gd")
const HomePose := preload("res://home_pose.gd")


func _init() -> void:
	var keys := Kbd3D.keys()
	var idx := Kbd3D.index_of(keys, "в")
	var key: Dictionary = keys[idx]
	var r: Rect2 = key["r"]
	var hit := r.get_center()
	print("hit %s" % str(hit))
	var home: Dictionary = HomePose.build("L", -72.51)
	var deep := Vector3(10.5975, 152.0, Kbd3D.FACE_Z - Kbd3D.TRAVEL)
	print("deep %s" % str(deep))
	var opts := {"arm": true, "thumb_dof": 4, "clear_z": Kbd3D.FACE_Z + 0.0,
		"clear_w": 100.0, "idle_sink": 0.5, "dir_w": 30.0}
	var chain0: Dictionary = IK.solve_chain("III", deep, home, opts)
	print("chain0 elbow_z %s" % str(float(chain0["pose"]["arm"]["elbow_z"])))
	var one: Dictionary = IK._solve_once("III", deep, home, opts)
	print("once  elbow_z %s wrist_flex %s fan %s" % [
		str(float(one["pose"]["arm"]["elbow_z"])),
		str(float(one["pose"]["arm"]["wrist_flex"])),
		str(float(one["pose"]["fingers"]["III"]["fan"]))])
	var two: Dictionary = IK._solve_once("III", deep, one["pose"], opts)
	print("twice elbow_z %s wrist_flex %s fan %s" % [
		str(float(two["pose"]["arm"]["elbow_z"])),
		str(float(two["pose"]["arm"]["wrist_flex"])),
		str(float(two["pose"]["fingers"]["III"]["fan"]))])
	var chain: Dictionary = IK.solve_chain("III", deep, home, opts)
	print("chain elbow_z %s wrist_flex %s fan %s" % [
		str(float(chain["pose"]["arm"]["elbow_z"])),
		str(float(chain["pose"]["arm"]["wrist_flex"])),
		str(float(chain["pose"]["fingers"]["III"]["fan"]))])
	quit(0)
