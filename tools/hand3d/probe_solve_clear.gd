# Did the SOLVE bury the thumb, or did the tuck? Calls _solve_once directly
# (no tuck), prints the clearance residual pieces and the thumb's pad, then
# repeats with a heavier clearance weight.
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")
const IK := preload("res://ik.gd")
const Kbd3D := preload("res://kbd3d.gd")
const HomePose := preload("res://home_pose.gd")

const ROOTS := {"L": -72.51, "R": 43.94}
const CLEAR_Z := Kbd3D.FACE_Z + 3.0
const DIR_W := 30.0


func _local(side: String, root_x: float, p: Vector3) -> Vector3:
	if side == "R":
		return Vector3(-(p.x - root_x), p.y, p.z)
	return Vector3(p.x - root_x, p.y, p.z)


func _pad_world(side: String, p: Dictionary) -> Vector3:
	var xf := ArmModel.hand_transform(p.get("arm", {}))
	var local: Vector3 = xf * HandModel.thumb_pad(HandModel.thumb_fk(
		HandModel.thumb_of_pose(p)))
	if side == "R":
		return Vector3(float(ROOTS[side]) - local.x, local.y, local.z)
	return Vector3(float(ROOTS[side]) + local.x, local.y, local.z)


func _case(side: String, want: String) -> void:
	var keys := Kbd3D.keys()
	var idx := -1
	for i in keys.size():
		if String(keys[i]["s"]) == want:
			idx = i
			break
	var key: Dictionary = keys[idx]
	var r: Rect2 = key["r"]
	var hx := r.get_center().x
	if r.size.x > Kbd3D.KEY_W * 1.05:
		hx = r.get_center().x + (-0.6 if side == "L" else 0.6) * r.size.x * 0.5
	var hit := Vector2(hx, r.get_center().y)
	var ray := String(Kbd3D.hand_finger(want, hx)[1])
	var root_x: float = ROOTS[side]
	var home: Dictionary = HomePose.build(side, root_x)
	var deep := _local(side, root_x, Vector3(hit.x, hit.y,
		Kbd3D.FACE_Z - Kbd3D.TRAVEL))
	print("=== %s %s ray %s" % [side, want, ray])
	for w in [100.0, 1000.0, 10000.0]:
		var r1: Dictionary = IK._solve_once(ray, deep, home,
			{"arm": true, "thumb_dof": 4, "clear_z": CLEAR_Z,
			"clear_w": w, "dir_w": DIR_W})
		var p: Dictionary = r1["pose"]
		print("  w %.0f err %.3f clr %.2f  thumb pad %s  arm %s" % [
			w, float(r1["error"]),
			IK.clearance(ray, p, CLEAR_Z, Rect2(), 0.0),
			str(_pad_world(side, p)), str(p["arm"])])
	quit(0)


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	_case(String(args[0]), String(args[1]))
