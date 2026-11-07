# What does the arm actually do on L Alt, and where do the two thumbs sit?
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")
const IK := preload("res://ik.gd")
const Kbd3D := preload("res://kbd3d.gd")
const HomePose := preload("res://home_pose.gd")

const ROOTS := {"L": -72.51, "R": 43.94}
const THUMB_R := [11.8, 10.8, 9.6, 6.6]


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var side := String(args[0]) if args.size() > 0 else "L"
	var want := String(args[1]) if args.size() > 1 else "Alt"
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
	var sgn := -1.0 if side == "R" else 1.0
	var deep := Vector3((hit.x - root_x) * sgn, hit.y,
		Kbd3D.FACE_Z - Kbd3D.TRAVEL)
	print("key %s rect %s centre %.2f hit %.2f -> local %.2f ray %s" % [
		want, str(r), r.get_center().x, hit.x, deep.x, ray])
	var home: Dictionary = HomePose.build(side, root_x)
	var other := "R" if side == "L" else "L"
	var idle: Dictionary = HomePose.build(other, float(ROOTS[other]))
	var pr: Dictionary = IK.solve_chain(ray, deep, home,
		{"arm": true, "thumb_dof": 4, "clear_z": Kbd3D.FACE_Z,
		"clear_w": 100.0, "dir_w": 30.0})
	var pp: Dictionary = pr["pose"]
	print("home arm %s" % str(home["arm"]))
	print("press arm %s" % str(pp["arm"]))
	for tag in [["home", home], ["press", pp], ["idle", idle]]:
		var nm := String(tag[0])
		var p: Dictionary = tag[1]
		var sd := side if nm != "idle" else other
		var rx: float = ROOTS[sd]
		var xf := ArmModel.hand_transform(p["arm"])
		print("%s %s root %s wrist %s" % [nm, sd,
			str(_w(sd, rx, xf.origin)),
			str(_w(sd, rx, xf.origin))])
		var tp: PackedVector3Array = HandModel.thumb_fk(
			HandModel.thumb_of_pose(p))["pts"]
		var out := []
		for j in 4:
			out.append(str(_w(sd, rx, xf * tp[j])))
		print("  thumb joints %s" % str(out))
		for f in HandModel.FINGERS:
			var fp: PackedVector3Array = HandModel.finger_fk(f,
				p["fingers"][f])["pts"]
			print("  %s pad %s" % [f, str(_w(sd, rx, xf * fp[3]))])
	print("error %.3f" % float(pr["error"]))
	quit(0)


func _w(side: String, root_x: float, q: Vector3) -> Vector3:
	if side == "R":
		return Vector3(root_x - q.x, q.y, q.z)
	return Vector3(root_x + q.x, q.y, q.z)
