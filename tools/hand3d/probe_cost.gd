# Cost comparison: the natural press pose vs the clearance press pose, both
# measured with the clearance term on. If the natural pose is clean, its cost
# must beat the clearance pose's — otherwise something in the residual pulls.
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")
const IK := preload("res://ik.gd")
const Kbd3D := preload("res://kbd3d.gd")
const HomePose := preload("res://home_pose.gd")


func _q(ray: String, p: Dictionary, arm: bool) -> Array:
	var q := []
	if ray == "I":
		q += IK.thumb_shares_of(HandModel.thumb_of_pose(p),
			p.get("thumb_hold", {}))
	else:
		q += IK.shares_of(ray, p["fingers"][ray])
	if arm:
		q += ArmModel.shares_of(p.get("arm", {}))
	return IK._project_chain(q, ray, arm, p.get("thumb_hold", {}))


func _show(tag: String, ray: String, p: Dictionary, base: Dictionary,
		tgt: Vector3) -> void:
	var q := _q(ray, p, true)
	var res: Dictionary = IK._chain_res(ray, q, tgt, true, base)
	var rr: Array = res["r"]
	var cost := IK._cost(rr)
	print("%s cost %s reach %s fit %s" % [tag, str(cost),
		str(float(res["reach"])), str(float(res["fit"]))])
	var shown := 0
	for i in rr.size():
		if absf(float(rr[i])) > 0.0005 and shown < 24:
			print("   r[%d] %s" % [i, str(float(rr[i]))])
			shown += 1


func _init() -> void:
	var home: Dictionary = HomePose.build("L", -72.51)
	var deep := Vector3(10.5975, 152.0, Kbd3D.FACE_Z - Kbd3D.TRAVEL)
	IK.thumb_dof = 4
	IK.clear_z = Kbd3D.FACE_Z
	IK.clear_hx = -1.0
	IK.clear_hy = -1.0
	IK.dir_w = 30.0
	IK.dir_min = -0.5
	IK.thumb_min = -0.7
	IK.clear_w = 100.0
	IK.idle_sink = 0.5
	var pr: Dictionary = IK.solve_chain("III", deep, home,
		{"arm": true, "thumb_dof": 4, "clear_z": Kbd3D.FACE_Z,
		"clear_w": 100.0, "idle_sink": 0.5, "dir_w": 30.0})
	print("clear pose elbow_z %s" % str(float(pr["pose"]["arm"]["elbow_z"])))
	_show("clear", "III", pr["pose"], home, deep)
	var pr2: Dictionary = IK.solve_chain("III", deep, home,
		{"arm": true, "thumb_dof": 4, "clear_z": Kbd3D.FACE_Z,
		"clear_w": 0.0, "dir_w": 30.0})
	print("noclr pose elbow_z %s" % str(float(pr2["pose"]["arm"]["elbow_z"])))
	_show("noclr", "III", pr2["pose"], home, deep)
	IK.clear_w = 0.0
	IK.idle_sink = 0.0
	quit(0)
