# Does the thumb's own chain reach its home pad after the hand has rotated to
# press a far key? If it does, the idle thumb can stay on the space bar (world
# fixed) instead of riding the hand across the centre line.
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")
const IK := preload("res://ik.gd")
const Kbd3D := preload("res://kbd3d.gd")
const HomePose := preload("res://home_pose.gd")

const ROOTS := {"L": -72.51, "R": 43.94}
const CLEAR_Z := Kbd3D.FACE_Z + 3.0
const CLEAR_W := 100.0
const DIR_W := 30.0


func _local(side: String, root_x: float, p: Vector3) -> Vector3:
	if side == "R":
		return Vector3(-(p.x - root_x), p.y, p.z)
	return Vector3(p.x - root_x, p.y, p.z)


func _world(side: String, q: Vector3) -> Vector3:
	if side == "R":
		return Vector3(float(ROOTS[side]) - q.x, q.y, q.z)
	return Vector3(float(ROOTS[side]) + q.x, q.y, q.z)


func _thumb_world(side: String, p: Dictionary) -> Dictionary:
	var xf := ArmModel.hand_transform(p.get("arm", {}))
	var fk: Dictionary = HandModel.thumb_fk(HandModel.thumb_of_pose(p))
	var pts: PackedVector3Array = fk["pts"]
	var out := {}
	for i in 4:
		out[i] = _world(side, xf * pts[i])
	out["pad"] = _world(side, xf * HandModel.thumb_pad(fk))
	return out


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
	var pr: Dictionary = IK.solve_chain(ray, deep, home,
		{"arm": true, "thumb_dof": 4, "clear_z": CLEAR_Z,
		"clear_w": CLEAR_W, "dir_w": DIR_W})
	var pp: Dictionary = pr["pose"]
	var th := _thumb_world(side, pp)
	print("=== %s %s ray %s" % [side, want, ray])
	print("  hand thumb pad %s  IP %s" % [str(th["pad"]), str(th[2])])
	var tgt: Vector3 = HomePose.target(side, "I", root_x)
	print("  home pad target %s" % str(tgt))
	var r2: Dictionary = IK.solve_chain("I", tgt, pp,
		{"arm": false, "thumb_dof": 4, "tuck": false, "clear_w": 0.0})
	var th2 := _thumb_world(side, r2["pose"])
	print("  retarget err %.3f  pad %s  IP %s" % [float(r2["error"]),
		str(th2["pad"]), str(th2[2])])
	print("  retarget angles %s" % str(HandModel.thumb_of_pose(r2["pose"])))
	quit(0)


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	_case(String(args[0]), String(args[1]))
