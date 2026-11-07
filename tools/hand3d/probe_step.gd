# The first LM step from home with the keyboard clearance on: what changes?
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")
const IK := preload("res://ik.gd")
const Kbd3D := preload("res://kbd3d.gd")
const HomePose := preload("res://home_pose.gd")


func _init() -> void:
	var home: Dictionary = HomePose.build("L", -72.51)
	var deep := Vector3(10.5975, 152.0, Kbd3D.FACE_Z - Kbd3D.TRAVEL)
	IK.thumb_dof = 4
	IK.clear_z = Kbd3D.FACE_Z
	IK.clear_w = 100.0
	IK.idle_sink = 0.5
	IK.clear_hx = -1.0
	IK.clear_hy = -1.0
	IK.dir_w = 30.0
	IK.dir_min = -0.5
	IK.thumb_min = -0.7
	var q := []
	q += IK.shares_of("III", home["fingers"]["III"])
	q += ArmModel.shares_of(home.get("arm", {}))
	q = IK._project_chain(q, "III", true, home.get("thumb_hold", {}))
	var cur: Dictionary = IK._chain_res("III", q, deep, true, home)
	var cp: Dictionary = IK._chain_pose("III", q, true, home)
	var cxf := ArmModel.hand_transform(cp["arm"])
	print("init arm %s" % str(cp["arm"]))
	for f in ["II", "III", "IV", "V"]:
		var ang: Dictionary = cp["fingers"][f] if cp["fingers"].has(f) \
			else home["fingers"][f]
		var fk: Dictionary = HandModel.finger_fk(f, ang)
		var pts: PackedVector3Array = fk["pts"]
		var rad: Array = HandModel.SKIN_R[f]
		var vals := []
		for j in 4:
			var w: Vector3 = cxf * pts[j]
			vals.append(str(snappedf(w.z - float(rad[j]) - Kbd3D.FACE_Z, 0.001)))
		print("  %s z-r %s" % [f, str(vals)])
	var rr: Array = cur["r"]
	print("cur fit %s cost %s n %d" % [str(float(cur["fit"])),
		str(IK._cost(rr)), rr.size()])
	for i in rr.size():
		if absf(float(rr[i])) > 0.001:
			print("  r[%d] = %s" % [i, str(float(rr[i]))])
	var cols: Array = IK._chain_jacobian("III", q, deep, true, home)
	var a: Array = IK._normal_equations(cols, 0.001, true)
	var g: Array = IK._gradient(cols, rr)
	var b := []
	for i in g.size():
		b.append(-float(g[i]))
	var delta: Array = IK._solve_n(a, b)
	print("delta %s" % str(delta))
	var qn := []
	for i in q.size():
		qn.append(float(q[i]) + clampf(float(delta[i]), -0.2, 0.2))
	qn = IK._project_chain(qn, "III", true, home.get("thumb_hold", {}))
	var next: Dictionary = IK._chain_res("III", qn, deep, true, home)
	var rn: Array = next["r"]
	print("next fit %s cost %s" % [str(float(next["fit"])),
		str(IK._cost(rn))])
	for i in rn.size():
		if absf(float(rn[i])) > 1.0:
			print("  BIG r[%d] = %s" % [i, str(float(rn[i]))])
	for i in rn.size():
		var d := float(rn[i]) - float(rr[i])
		if absf(d) > 0.001:
			print("  r[%d] %s -> %s  d %s" % [i, str(float(rr[i])),
				str(float(rn[i])), str(d)])
	IK.clear_w = 0.0
	quit(0)
