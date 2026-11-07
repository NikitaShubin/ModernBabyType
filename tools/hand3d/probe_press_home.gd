# Home pose vs press pose for one key: angles, shares, pad, distal direction.
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


func _pad(ray: String, p: Dictionary) -> Vector3:
	var xf := ArmModel.hand_transform(p.get("arm", {}))
	if ray == "I":
		return xf * HandModel.thumb_pad(HandModel.thumb_fk(
			HandModel.thumb_of_pose(p)))
	return xf * HandModel.finger_pad(ray,
		HandModel.finger_fk(ray, p["fingers"][ray]))


func _show(tag: String, ray: String, p: Dictionary) -> void:
	var xf := ArmModel.hand_transform(p.get("arm", {}))
	var fk: Dictionary = HandModel.finger_fk(ray, p["fingers"][ray])
	var d3: Vector3 = (xf.basis * (fk["dirs"][2] as Vector3)).normalized()
	var pad := _pad(ray, p)
	var s := IK.shares_of(ray, p["fingers"][ray])
	print("%s %s %s  shares %s" % [tag, ray, str(p["fingers"][ray]),
		str(s)])
	print("   d3 %s z %.3f pad %s" % [str(d3), d3.z, str(pad)])
	print("   arm %s" % str(p["arm"]))


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var side := String(args[0])
	var want := String(args[1])
	var keys := Kbd3D.keys()
	var idx := Kbd3D.index_of(keys, want)
	var key: Dictionary = keys[idx]
	var r: Rect2 = key["r"]
	var hx := r.get_center().x
	if r.size.x > Kbd3D.KEY_W * 1.05:
		hx = r.get_center().x + (-0.6 if side == "L" else 0.6) \
			* r.size.x * 0.5
	var hit := Vector2(hx, r.get_center().y)
	var ray := String(Kbd3D.hand_finger(want, hx)[1])
	var root_x: float = ROOTS[side]
	var home: Dictionary = HomePose.build(side, root_x)
	print("=== %s %s ray %s" % [side, want, ray])
	_show("home", ray, home)
	var deep := _local(side, root_x, Vector3(hit.x, hit.y,
		Kbd3D.FACE_Z - Kbd3D.TRAVEL))
	print("   target %s" % str(deep))
	var pr: Dictionary = IK.solve_chain(ray, deep, home,
		{"arm": true, "thumb_dof": 4, "clear_z": Kbd3D.FACE_Z + 0.0,
		"clear_w": 100.0, "idle_sink": 0.5, "dir_w": 30.0})
	_show("press", ray, pr["pose"])
	print("   err %.4f  elbow_z %.2f" % [float(pr["error"]),
		float(pr["pose"]["arm"].get("elbow_z", 0.0))])
	# The press without the keyboard clearance, for comparison.
	var pr2: Dictionary = IK.solve_chain(ray, deep, home,
		{"arm": true, "thumb_dof": 4, "clear_z": Kbd3D.FACE_Z + 0.0,
		"clear_w": 0.0, "dir_w": 30.0})
	_show("noclr", ray, pr2["pose"])
	print("   err %.4f  elbow_z %.2f" % [float(pr2["error"]),
		float(pr2["pose"]["arm"].get("elbow_z", 0.0))])
	var rects := []
	for k in keys:
		var kr: Rect2 = k["r"]
		if side == "R":
			rects.append(Rect2(-(kr.end.x - root_x), kr.position.y,
				kr.size.x, kr.size.y))
		else:
			rects.append(Rect2(kr.position.x - root_x, kr.position.y,
				kr.size.x, kr.size.y))
	var fp := Rect2()
	print("   footprint %s" % str(fp))
	for tag in ["home", "press", "noclr"]:
		var pp: Dictionary = home if tag == "home" else \
			(pr["pose"] if tag == "press" else pr2["pose"])
		var cl := IK.clearance(ray, pp, Kbd3D.FACE_Z, fp)
		print("   clearance %s = %.3f" % [tag, cl])
		var xf := ArmModel.hand_transform(pp.get("arm", {}))
		var th := HandModel.thumb_fk(HandModel.thumb_of_pose(pp))
		var tp: PackedVector3Array = th["pts"]
		var tr := [11.8, 10.8, 9.6, 6.6]
		var tlo := []
		for j in 4:
			var w: Vector3 = xf * tp[j]
			tlo.append("%d:%s" % [j, str(snappedf(w.z - float(tr[j]) - Kbd3D.FACE_Z, 0.1))])
		print("     I z-r %s  %s" % [str(tlo),
			str(HandModel.thumb_of_pose(pp))])
		for f in ["II", "III", "IV", "V"]:
			var fk2: Dictionary = HandModel.finger_fk(f, pp["fingers"][f])
			var pts: PackedVector3Array = fk2["pts"]
			var rr: Array = HandModel.SKIN_R[f]
			var lo := []
			for j in 4:
				var w: Vector3 = xf * pts[j]
				lo.append("%d:%s" % [j, str(snappedf(w.z - float(rr[j]) - Kbd3D.FACE_Z, 0.1))])
			print("     %s z-r %s" % [f, str(lo)])
	# And without the direction term, with clearance.
	var pr3: Dictionary = IK.solve_chain(ray, deep, home,
		{"arm": true, "thumb_dof": 4, "clear_z": Kbd3D.FACE_Z + 0.0,
		"clear_w": 100.0, "dir_w": 0.0})
	_show("nodir", ray, pr3["pose"])
	print("   err %.4f  elbow_z %.2f" % [float(pr3["error"]),
		float(pr3["pose"]["arm"].get("elbow_z", 0.0))])
	print("   home pad after solves %s" % str(_pad(ray, home)))
	var one: Dictionary = IK._solve_once(ray, deep, home,
		{"arm": true, "thumb_dof": 4, "clear_z": Kbd3D.FACE_Z + 0.0,
		"clear_w": 100.0, "idle_sink": 0.5, "dir_w": 30.0})
	print("   once clear_w 100 err %s iters %d elbow_z %s" % [
		str(float(one["error"])), int(one["iterations"]),
		str(float(one["pose"]["arm"].get("elbow_z", 0.0)))])
	var zero: Dictionary = IK._solve_once(ray, deep, home,
		{"arm": true, "thumb_dof": 4, "clear_z": Kbd3D.FACE_Z + 0.0,
		"clear_w": 0.0, "dir_w": 30.0})
	print("   once clear_w 0 err %s iters %d elbow_z %s" % [
		str(float(zero["error"])), int(zero["iterations"]),
		str(float(zero["pose"]["arm"].get("elbow_z", 0.0)))])
	var tr0: Array = zero["trace"]
	for k in tr0.size():
		if k < 6:
			print("      z it %d fit %s ok %s" % [int(tr0[k][0]),
				str(float(tr0[k][1])), str(tr0[k][4])])
	var tr: Array = one["trace"]
	for k in tr.size():
		if k < 14 or k > tr.size() - 4:
			print("      it %d fit %s lam %s step %s ok %s" % [
				int(tr[k][0]), str(float(tr[k][1])), str(float(tr[k][2])),
				str(float(tr[k][3])), str(tr[k][4])])
	quit(0)
