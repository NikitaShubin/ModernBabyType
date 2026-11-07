# Why L «е» II stops 0.64 mm short with the clearance on: which joint of the
# pressing finger is violating the keys, and by how much.
extends SceneTree
const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")
const IK := preload("res://ik.gd")
const Kbd3D := preload("res://kbd3d.gd")
const HomePose := preload("res://home_pose.gd")
const ROOTS := {"L": -72.51, "R": 43.94}

func _init() -> void:
	var ks := Kbd3D.keys()
	var want := "е"
	var home: Dictionary = HomePose.build("L", ROOTS["L"])
	var k: Dictionary = ks[Kbd3D.index_of(ks, want)]
	var r: Rect2 = k["r"]
	var xy := r.get_center()
	var ray := String(Kbd3D.hand_finger(want, xy.x)[1])
	var deep := Vector3(xy.x - ROOTS["L"], xy.y, Kbd3D.FACE_Z - Kbd3D.TRAVEL)
	for cfg in [["full", 100.0], ["noclear", 0.0]]:
		var res: Dictionary = IK.solve_chain(ray, deep, home,
			{"arm": true, "thumb_dof": 4, "clear_z": Kbd3D.FACE_Z,
			"clear_w": float(cfg[1]), "dir_w": 30.0, "pair_w": 100.0})
		var p: Dictionary = res["pose"]
		var xf := ArmModel.hand_transform(p["arm"])
		print("%s err %.3f  padz %.2f  arm %s" % [cfg[0], float(res["error"]),
			IK._chain_pad(ray, p).z, str(_arm(p["arm"]))])
		var ang: Dictionary = p["fingers"][ray]
		print("   %s mcp %.1f pip %.1f dip %.1f fan %.1f" % [ray,
			float(ang["mcp"]), float(ang["pip"]), float(ang["dip"]), float(ang["fan"])])
		var pts: PackedVector3Array = HandModel.finger_fk(ray, ang)["pts"]
		for j in 4:
			var w: Vector3 = xf * pts[j]
			var rr := float(HandModel.SKIN_R[ray][j])
			IK.clear_cx = r.position.x
			IK.clear_cy = r.position.y
			IK.clear_hx = r.size.x
			IK.clear_hy = r.size.y
			var v := IK._joint_violation(w.x, w.y, w.z, rr, Kbd3D.FACE_Z)
			IK.clear_hx = -1.0
			print("     j%d z %7.2f r %5.2f  v %5.3f   world (%.2f %.2f)" % [j,
				w.z, rr, v, w.x, w.y])
		# idle fingers
		for f in HandModel.FINGERS:
			if f == ray:
				continue
			var a: Dictionary = p["fingers"][f]
			var fp: PackedVector3Array = HandModel.finger_fk(f, a)["pts"]
			var worst := 0.0
			var wj := -1
			for j in 4:
				var w: Vector3 = xf * fp[j]
				IK.clear_hx = r.size.x
				IK.clear_cx = r.position.x
				IK.clear_cy = r.position.y
				IK.clear_hy = r.size.y
				var v := IK._joint_violation(w.x, w.y, w.z, float(HandModel.SKIN_R[f][j]), Kbd3D.FACE_Z)
				IK.clear_hx = -1.0
				if v > worst:
					worst = v
					wj = j
			print("     idle %s worst %.3f at j%d" % [f, worst, wj])
		IK.clear_hx = -1.0
	quit(0)

func _arm(a: Dictionary) -> Array:
	var out := []
	for j in ArmModel.ALL_JOINTS:
		out.append("%s %.1f" % [j, float(a[j])])
	return out
