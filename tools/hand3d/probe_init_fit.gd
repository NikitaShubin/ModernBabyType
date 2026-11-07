# Why does the initial fit differ with clear_w? Isolate _chain_res from the solve.
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")
const IK := preload("res://ik.gd")
const Kbd3D := preload("res://kbd3d.gd")
const HomePose := preload("res://home_pose.gd")

const ROOTS := {"L": -72.51, "R": 43.94}


func _local(side: String, root_x: float, p: Vector3) -> Vector3:
	if side == "R":
		return Vector3(-(p.x - root_x), p.y, p.z)
	return Vector3(p.x - root_x, p.y, p.z)


func _init() -> void:
	var side := "L"
	var root_x: float = ROOTS[side]
	var home: Dictionary = HomePose.build(side, root_x)
	var ray := "III"
	var deep := Vector3(10.5975, 152.0, Kbd3D.FACE_Z - Kbd3D.TRAVEL)
	print("home arm %s" % str(home["arm"]))
	var arm2 := ArmModel.angles_of_shares(ArmModel.shares_of(home["arm"]))
	print("rt arm   %s" % str(arm2))
	for cw in [0.0, 100.0]:
		IK.clear_w = cw
		IK.clear_z = Kbd3D.FACE_Z
		IK.clear_hx = -1.0
		IK.clear_hy = -1.0
		IK.thumb_dof = 4
		IK.dir_w = 30.0
		var q := []
		q += IK.shares_of(ray, home["fingers"][ray])
		q += ArmModel.shares_of(home.get("arm", {}))
		q = IK._project_chain(q, ray, true, home.get("thumb_hold", {}))
		var res: Dictionary = IK._chain_res(ray, q, deep, true, home)
		print("cw %s q %s" % [str(cw), str(q)])
		print("   fit %s reach %s dist %s" % [str(float(res["fit"])),
			str(float(res["reach"])),
			str((res["pad"] as Vector3).distance_to(deep))])
	IK.clear_w = 0.0
	quit(0)
