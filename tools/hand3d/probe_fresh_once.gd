# One _solve_once from a fresh home: what is the initial fit?
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")
const IK := preload("res://ik.gd")
const Kbd3D := preload("res://kbd3d.gd")
const HomePose := preload("res://home_pose.gd")


func _pad(ray: String, p: Dictionary) -> Vector3:
	var xf := ArmModel.hand_transform(p.get("arm", {}))
	return xf * HandModel.finger_pad(ray,
		HandModel.finger_fk(ray, p["fingers"][ray]))


func _init() -> void:
	var side := "L"
	var root_x := -72.51
	var home: Dictionary = HomePose.build(side, root_x)
	var deep := Vector3(10.5975, 152.0, Kbd3D.FACE_Z - Kbd3D.TRAVEL)
	print("before pad %s" % str(_pad("III", home)))
	var opts := {"arm": true, "thumb_dof": 4,
		"clear_z": Kbd3D.FACE_Z + 0.0, "clear_w": 100.0, "dir_w": 30.0}
	var one: Dictionary = IK._solve_once("III", deep, home, opts)
	var tr: Array = one["trace"]
	print("fresh once err %s iters %d elbow_z %s" % [str(float(one["error"])),
		int(one["iterations"]),
		str(float(one["pose"]["arm"].get("elbow_z", 0.0)))])
	print("  first fit %s ok %s" % [str(float(tr[0][1])), str(tr[0][4])])
	print("after pad %s" % str(_pad("III", home)))
	quit(0)
