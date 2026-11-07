# The press of one far key: what the solve does to the idle pads, before and
# after the tuck, and how far the idle fingers sit from each other.
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")
const IK := preload("res://ik.gd")
const Kbd3D := preload("res://kbd3d.gd")
const HomePose := preload("res://home_pose.gd")

const ROOTS := {"L": -72.51, "R": 43.94}


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
	var sgn := -1.0 if side == "R" else 1.0
	var deep := Vector3((hit.x - root_x) * sgn, hit.y,
		Kbd3D.FACE_Z - Kbd3D.TRAVEL)
	var home: Dictionary = HomePose.build(side, root_x)
	print("=== %s %s ray %s deep %s" % [side, want, ray, str(deep)])
	for tuck in [false, true]:
		var pr: Dictionary = IK.solve_chain(ray, deep, home,
			{"arm": true, "thumb_dof": 4, "clear_z": Kbd3D.FACE_Z,
			"clear_w": 100.0, "idle_sink": 0.5, "dir_w": 30.0,
			"tuck": tuck})
		var p: Dictionary = pr["pose"]
		print("tuck %s err %.4f arm %s" % [str(tuck), float(pr["error"]),
			str(p["arm"])])
		var xf := ArmModel.hand_transform(p["arm"])
		for f in ["II", "III", "IV", "V"]:
			var fk: Dictionary = HandModel.finger_fk(f, p["fingers"][f])
			var pts: PackedVector3Array = fk["pts"]
			var rr: Array = HandModel.SKIN_R[f]
			var lo := []
			for j in 4:
				var w: Vector3 = xf * pts[j]
				lo.append(str(snappedf(w.z - float(rr[j]) - Kbd3D.FACE_Z, 0.01)))
			print("   %s %s z-r %s" % [f, str(p["fingers"][f]), str(lo)])
		var tp: PackedVector3Array = HandModel.thumb_fk(
			HandModel.thumb_of_pose(p))["pts"]
		var tr := [11.8, 10.8, 9.6, 6.6]
		var tlo := []
		for j in 4:
			var w: Vector3 = xf * tp[j]
			tlo.append(str(snappedf(w.z - float(tr[j]) - Kbd3D.FACE_Z, 0.01)))
		print("   I z-r %s" % str(tlo))
	quit(0)
