# Continuation: solve the press without the keyboard clearance first, then
# refine with it. Does the refine stay in the natural valley?
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")
const IK := preload("res://ik.gd")
const Kbd3D := preload("res://kbd3d.gd")
const HomePose := preload("res://home_pose.gd")


func _init() -> void:
	var home: Dictionary = HomePose.build("L", -72.51)
	var deep := Vector3(10.5975, 152.0, Kbd3D.FACE_Z - Kbd3D.TRAVEL)
	var no := {"arm": true, "thumb_dof": 4, "clear_z": Kbd3D.FACE_Z,
		"clear_w": 0.0, "dir_w": 30.0}
	var cl := {"arm": true, "thumb_dof": 4, "clear_z": Kbd3D.FACE_Z,
		"clear_w": 100.0, "idle_sink": 0.5, "dir_w": 30.0}
	var a: Dictionary = IK._solve_once("III", deep, home, no)
	print("stage1 elbow_z %s fan %s err %s" % [
		str(float(a["pose"]["arm"]["elbow_z"])),
		str(float(a["pose"]["fingers"]["III"]["fan"])), str(float(a["error"]))])
	var b: Dictionary = IK._solve_once("III", deep, a["pose"], cl)
	print("stage2 elbow_z %s fan %s err %s" % [
		str(float(b["pose"]["arm"]["elbow_z"])),
		str(float(b["pose"]["fingers"]["III"]["fan"])), str(float(b["error"]))])
	var c: Dictionary = IK._solve_once("III", deep, b["pose"], cl)
	print("stage3 elbow_z %s fan %s err %s" % [
		str(float(c["pose"]["arm"]["elbow_z"])),
		str(float(c["pose"]["fingers"]["III"]["fan"])), str(float(c["error"]))])
	var d: Dictionary = IK.solve_chain("III", deep, home, cl)
	print("chain  elbow_z %s fan %s err %s" % [
		str(float(d["pose"]["arm"]["elbow_z"])),
		str(float(d["pose"]["fingers"]["III"]["fan"])), str(float(d["error"]))])
	quit(0)
