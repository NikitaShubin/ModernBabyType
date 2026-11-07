# Can the hand's TURN alone balance the ring and the little finger? Rotates
# the hand about a local axis that separates the two rays and re-solves the
# digits, printing the pad errors.
#
# The axis is in the hand's own frame: a roll about the forearm (local y)
# plus a pitch (local x), which is exactly what pronation + flexion give.
#
#   mbt-godot --headless --path /work/tools/hand3d --script res://home_roll_probe.gd
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")
const IK := preload("res://ik.gd")
const Kbd3D := preload("res://kbd3d.gd")

const ROOT_L := -72.51
const HOME_LABELS := {"II": "а", "III": "в", "IV": "ы", "V": "ф"}
const TOUCH := 0.3
const THUMB_X := 20.5
const THUMB_LIFT := 2.0


func _target(ray: String) -> Vector3:
	if ray == "I":
		return Vector3(-THUMB_X - ROOT_L, Kbd3D.row_y(4),
			Kbd3D.FACE_Z + THUMB_LIFT)
	var ks := Kbd3D.keys()
	var c := Kbd3D.centre(ks[Kbd3D.index_of(ks, HOME_LABELS[ray])])
	return Vector3(c.x - ROOT_L, c.y, Kbd3D.FACE_Z + TOUCH)


func _opts(ray: String) -> Dictionary:
	var o := {"arm": false, "tuck": false, "clear_w": 0.0, "dir_w": 0.0}
	if ray == "I":
		o["thumb_dof"] = 4
	return o


func _pad_local(side: String, ray: String, p: Dictionary) -> Vector3:
	var xf := ArmModel.hand_transform(p.get("arm", {}))
	var v: Vector3
	if ray == "I":
		v = xf * HandModel.thumb_pad(HandModel.thumb_fk(
			HandModel.thumb_of_pose(p)))
	else:
		v = xf * HandModel.finger_pad(ray,
			HandModel.finger_fk(ray, p["fingers"][ray]))
	if side == "R":
		return Vector3(-v.x, v.y, v.z)
	return v


# Decompose a hand rotation into the wrist chain, with the root fixed.
# r_wrist = Basis(UP, pron) * Basis(BACK, -dev) * Basis(RIGHT, -flex).
func _wrist_angles(r_root: Basis, r_hand: Basis) -> Dictionary:
	var r := r_root.inverse() * r_hand
	var dev := -asin(clampf(r.x.y, -1.0, 1.0))
	var flex := atan2(r.z.y, r.y.y)
	var pron := atan2(-r.x.z, r.x.x)
	return {"pronation": rad_to_deg(pron), "wrist_dev": rad_to_deg(dev),
		"wrist_flex": rad_to_deg(flex)}


func _base_arm(wy: float, wz: float) -> Dictionary:
	var arm := ArmModel.rest_arm()
	arm["forearm_abd"] = 22.0
	arm["wrist_dev"] = -20.0
	arm["wrist_flex"] = -20.0
	arm["pronation"] = 0.0
	arm["elbow_x"] = -ArmModel.FOREARM_L * sin(deg_to_rad(22.0))
	arm["elbow_y"] = wy + ArmModel.FOREARM_L \
		- ArmModel.FOREARM_L * cos(deg_to_rad(22.0))
	arm["elbow_z"] = wz
	return arm


func _run(arm: Dictionary, label: String) -> void:
	var p := HandModel.rest_pose()
	p["arm"] = arm
	p["thumb_dof"] = 4
	p["thumb"] = HandModel.thumb_at(0.0)
	var errs := {}
	var worst := 0.0
	for ray in ["II", "III", "IV", "V", "I"]:
		var t := _target(ray)
		var r: Dictionary = IK.solve_chain(ray, t, p, _opts(ray))
		p = r["pose"]
		var pad := _pad_local("L", ray, p)
		pad.x += ROOT_L
		var tw := Vector3(ROOT_L + t.x, t.y, t.z)
		var e := (pad - tw).length()
		errs[ray] = e
		worst = maxf(worst, e)
	print("%-22s worst %6.2f  II %5.2f III %5.2f IV %5.2f V %5.2f I %6.3f  arm %s"
		% [label, worst, float(errs["II"]), float(errs["III"]),
		float(errs["IV"]), float(errs["V"]), float(errs["I"]),
		str({"dev": arm["wrist_dev"], "flex": arm["wrist_flex"],
		"pron": arm["pronation"]})])


func _init() -> void:
	var wy := 30.0
	var wz := -41.0
	var base := _base_arm(wy, wz)
	var f := ArmModel.frames(base)
	var r0: Basis = f["r_wrist"]
	var axis := Vector3(0.36, -0.93, 0.0).normalized()
	_run(base, "base")
	for deg in [-12.0, -8.0, -4.0, 4.0, 8.0, 12.0]:
		var arm := base.duplicate(true)
		var wa := _wrist_angles(f["r_root"], r0 * Basis(axis, deg_to_rad(deg)))
		arm["wrist_dev"] = wa["wrist_dev"]
		arm["wrist_flex"] = wa["wrist_flex"]
		arm["pronation"] = wa["pronation"]
		_run(arm, "roll %+.0f" % deg)
	# And the pure pronation / flexion axes for comparison.
	for deg in [-12.0, -8.0, -4.0, 4.0, 8.0, 12.0]:
		var arm := base.duplicate(true)
		var wa := _wrist_angles(f["r_root"], r0 * Basis(Vector3.UP, deg_to_rad(deg)))
		arm["wrist_dev"] = wa["wrist_dev"]
		arm["wrist_flex"] = wa["wrist_flex"]
		arm["pronation"] = wa["pronation"]
		_run(arm, "pron %+.0f" % deg)
	quit(0)
