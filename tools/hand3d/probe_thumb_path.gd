# Where the two thumbs actually are along one click path. Prints the world
# points of both thumbs' MCP/IP/tip and the pad at every sampled instant, plus
# the solved press pose's own thumb angles and its hold.
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")
const IK := preload("res://ik.gd")
const Kbd3D := preload("res://kbd3d.gd")
const ClickPath := preload("res://click_path.gd")
const HomePose := preload("res://home_pose.gd")

const ROOTS := {"L": -72.51, "R": 43.94}
const KEY_HOVER := 12.0
const THUMB_HOVER := 5.0
const CLEAR_Z := Kbd3D.FACE_Z + 3.0
const CLEAR_W := 100.0
const DIR_W := 30.0
const APPROACH := 0.35
const PRESS := 0.16
const RELEASE := 0.12
const RETURN := 0.40


func _local(side: String, root_x: float, p: Vector3) -> Vector3:
	if side == "R":
		return Vector3(-(p.x - root_x), p.y, p.z)
	return Vector3(p.x - root_x, p.y, p.z)


func _world(side: String, q: Vector3) -> Vector3:
	if side == "R":
		return Vector3(float(ROOTS[side]) - q.x, q.y, q.z)
	return Vector3(float(ROOTS[side]) + q.x, q.y, q.z)


func _pad(ray: String, p: Dictionary) -> Vector3:
	var xf := ArmModel.hand_transform(p.get("arm", {}))
	if ray == "I":
		return xf * HandModel.thumb_pad(HandModel.thumb_fk(
			HandModel.thumb_of_pose(p)))
	return xf * HandModel.finger_pad(ray,
		HandModel.finger_fk(ray, p["fingers"][ray]))


func _thumb_pts(side: String, p: Dictionary) -> Array:
	var xf := ArmModel.hand_transform(p.get("arm", {}))
	var fk: Dictionary = HandModel.thumb_fk(HandModel.thumb_of_pose(p))
	var pts: PackedVector3Array = fk["pts"]
	var out := []
	for i in 4:
		out.append(_world(side, xf * pts[i]))
	return out


func _local_keys(side: String, root_x: float) -> Array:
	var out := []
	for k in Kbd3D.keys():
		var r: Rect2 = k["r"]
		if side == "R":
			out.append(Rect2(-(r.end.x - root_x), r.position.y, r.size.x,
				r.size.y))
		else:
			out.append(Rect2(r.position.x - root_x, r.position.y, r.size.x,
				r.size.y))
	return out


func _case(side: String, want: String) -> void:
	var keys := Kbd3D.keys()
	var idx := -1
	for i in keys.size():
		if String(keys[i]["s"]) == want:
			idx = i
			break
	if idx < 0:
		print("no key ", want)
		return
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
	var deep := _local(side, root_x, Vector3(hit.x, hit.y,
		Kbd3D.FACE_Z - Kbd3D.TRAVEL))
	print("  HOME BEFORE arm %s" % str(home["arm"]))
	print("  HOME BEFORE pad  %s  target %s" % [str(_pad("I", home)),
		str(HomePose.target(side, "I", root_x))])
	var pr: Dictionary = IK.solve_chain(ray, deep, home,
		{"arm": true, "thumb_dof": 4, "clear_z": CLEAR_Z,
		"clear_w": CLEAR_W, "dir_w": DIR_W})
	print("  HOME AFTER  arm %s" % str(home["arm"]))
	print("  HOME AFTER  pad  %s" % str(_pad("I", home)))
	var pp: Dictionary = pr["pose"]
	var pr2: Dictionary = IK.solve_chain(ray, deep, home,
		{"arm": true, "thumb_dof": 4, "clear_z": CLEAR_Z,
		"clear_w": CLEAR_W, "dir_w": DIR_W, "tuck": false})
	print("  raw home thumb %s dof %s" % [str(home.get("thumb")),
		str(home.get("thumb_dof"))])
	print("  tuck=false press thumb %s" % str(pr2["pose"].get("thumb")))
	print("  tuck=true  press thumb %s" % str(pp.get("thumb")))
	var ppad := _pad(ray, pp)
	var hov := THUMB_HOVER if ray == "I" else KEY_HOVER
	var lift := maxf(0.0, (Kbd3D.FACE_Z + hov) - ppad.z)
	var hp: Dictionary = pp.duplicate(true)
	hp["arm"]["elbow_z"] = float(hp["arm"].get("elbow_z", 0.0)) + lift
	var rects := _local_keys(side, root_x)
	var path: Dictionary = ClickPath.build(home, hp, pp, APPROACH, PRESS,
		RELEASE, RETURN, {"ray": ray, "clear_z": CLEAR_Z,
		"key_rects": rects, "own": idx})
	var other := "R" if side == "L" else "L"
	var idle: Dictionary = HomePose.build(other, float(ROOTS[other]))
	print("=== %s %s ray %s  home hold %s" % [side, want, ray,
		str(home.get("thumb_hold", {}))])
	print("    press arm %s" % str(pp["arm"]))
	print("    press angles %s  hold %s" % [
		str(HandModel.thumb_of_pose(pp)), str(pp.get("thumb_hold", {}))])
	print("    home  thumb angles %s" % str(HandModel.thumb_of_pose(home)))
	var total := float(path["total"])
	for i in 11:
		var t := total * float(i) / 10.0
		var p: Dictionary = ClickPath.at(path, t)
		var a := _thumb_pts(side, p)
		var b := _thumb_pts(other, idle)
		print("  t %.3f  %s MCP %s IP %s TIP %s PAD %s | %s MCP %s IP %s TIP %s" % [
			t, side, str(a[1]), str(a[2]), str(a[3]),
			str(_pad("I", p)),
			other, str(b[1]), str(b[2]), str(b[3])])
		print("        angles %s" % str(HandModel.thumb_of_pose(p)))
	quit(0)


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var side := "R" if args.size() < 1 else String(args[0])
	var want := "н" if args.size() < 2 else String(args[1])
	_case(side, want)
