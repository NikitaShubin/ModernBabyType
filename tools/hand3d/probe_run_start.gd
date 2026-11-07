# Rebuild _solve_once's start by hand and compare with what _solve_once sees.
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")
const IK := preload("res://ik.gd")
const Kbd3D := preload("res://kbd3d.gd")
const HomePose := preload("res://home_pose.gd")


func _init() -> void:
	var home: Dictionary = HomePose.build("L", -72.51)
	var deep := Vector3(10.5975, 152.0, Kbd3D.FACE_Z - Kbd3D.TRAVEL)
	# The statics as _solve_once sets them.
	IK.thumb_dof = 4
	IK.clear_z = Kbd3D.FACE_Z
	IK.clear_w = 100.0
	IK.clear_skin = 0.0
	IK.clear_cx = 0.0
	IK.clear_cy = 0.0
	IK.clear_hx = -1.0
	IK.clear_hy = -1.0
	IK.dir_w = 30.0
	IK.dir_min = -0.5
	IK.thumb_min = -0.7
	IK.hover_lift = 0.0
	var q := []
	q += IK.shares_of("III", home["fingers"]["III"])
	q += ArmModel.shares_of(home.get("arm", {}))
	q = IK._project_chain(q, "III", true, home.get("thumb_hold", {}))
	print("q %s" % str(q))
	var run: Dictionary = IK._chain_run("III", deep, home, q, true)
	print("run first fit %s err %s" % [str(float(run["cur"]["fit"])),
		str(float(run["cur"]["reach"]))])
	print("run arm %s" % str(run["cur"]["pose"]["arm"]))
	var tr: Array = run["trace"]
	for k in tr.size():
		if k < 10 or k > tr.size() - 3:
			print("   it %d fit %s lam %s step %s ok %s" % [
				int(tr[k][0]), str(float(tr[k][1])), str(float(tr[k][2])),
				str(float(tr[k][3])), str(tr[k][4])])
	IK.clear_w = 0.0
	quit(0)
