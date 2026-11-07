# Coarse grid over the hand's TURN (wrist deviation, flexion, pronation) with
# the forearm splayed 22 degrees and the wrist near the home row. The four
# finger pads must all land on the key faces; the table prints the sum of
# squared pad errors and the worst one, so the valley is visible.
#
#   mbt-godot --headless --path /work/tools/hand3d --script res://home_grid2.gd
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")
const IK := preload("res://ik.gd")
const Kbd3D := preload("res://kbd3d.gd")

const ROOT_L := -72.51
const ROOT_R := 43.94
const HOME_LABELS := {
	"L": {"II": "а", "III": "в", "IV": "ы", "V": "ф"},
	"R": {"II": "о", "III": "л", "IV": "д", "V": "ж"},
}
const TOUCH := 0.3
const THUMB_X := 20.5
const THUMB_LIFT := 2.0


func _target(side: String, ray: String) -> Vector3:
	var sgn := -1.0 if side == "R" else 1.0
	var rx: float = ROOT_L if side == "L" else ROOT_R
	if ray == "I":
		var wx := -THUMB_X if side == "L" else THUMB_X
		return Vector3((wx - rx) * sgn, Kbd3D.row_y(4),
			Kbd3D.FACE_Z + THUMB_LIFT)
	var label: String = (HOME_LABELS[side] as Dictionary)[ray]
	var ks := Kbd3D.keys()
	var c := Kbd3D.centre(ks[Kbd3D.index_of(ks, label)])
	return Vector3((c.x - rx) * sgn, c.y, Kbd3D.FACE_Z + TOUCH)


func _arm(par: Dictionary) -> Dictionary:
	var a := ArmModel.rest_arm()
	var abd := deg_to_rad(float(par["abd"]))
	a["forearm_abd"] = float(par["abd"])
	a["forearm_flex"] = 0.0
	a["wrist_dev"] = float(par["dev"])
	a["wrist_flex"] = float(par["flex"])
	a["pronation"] = float(par["pron"])
	a["elbow_x"] = float(par["wx"]) - ArmModel.FOREARM_L * sin(abd)
	a["elbow_y"] = float(par["wy"]) + ArmModel.FOREARM_L \
		- ArmModel.FOREARM_L * cos(abd)
	a["elbow_z"] = float(par["wz"])
	return a


func _pad_world(side: String, ray: String, p: Dictionary) -> Vector3:
	var rx: float = ROOT_L if side == "L" else ROOT_R
	var xf := ArmModel.hand_transform(p.get("arm", {}))
	var local: Vector3
	if ray == "I":
		local = xf * HandModel.thumb_pad(HandModel.thumb_fk(
			HandModel.thumb_of_pose(p)))
	else:
		local = xf * HandModel.finger_pad(ray,
			HandModel.finger_fk(ray, p["fingers"][ray]))
	if side == "R":
		return Vector3(rx - local.x, local.y, local.z)
	return Vector3(rx + local.x, local.y, local.z)


func _opts(ray: String) -> Dictionary:
	var o := {"arm": false, "tuck": false, "clear_w": 0.0, "dir_w": 0.0}
	if ray == "I":
		o["thumb_dof"] = 4
	return o


func _side(side: String, arm: Dictionary) -> Dictionary:
	var p := HandModel.rest_pose()
	p["arm"] = arm.duplicate(true)
	p["thumb_f"] = 0.0
	p["thumb"] = HandModel.thumb_at(0.0)
	p["thumb_dof"] = 4
	var errs := {}
	var worst := 0.0
	var sum := 0.0
	var rx: float = ROOT_L if side == "L" else ROOT_R
	for ray in ["II", "III", "IV", "V", "I"]:
		var t := _target(side, ray)
		var r: Dictionary = IK.solve_chain(ray, t, p, _opts(ray))
		p = r["pose"]
		var pad := _pad_world(side, ray, p)
		var tw := Vector3(rx + t.x if side == "L" else rx - t.x, t.y, t.z)
		var e := (pad - tw).length()
		errs[ray] = e
		sum += e * e
		worst = maxf(worst, e)
	return {"worst": worst, "sum": sum, "errs": errs, "pose": p}


func _init() -> void:
	var par := {"wx": 0.0, "wy": 20.0, "wz": -42.0, "abd": 22.0,
		"dev": -22.0, "flex": -20.0, "pron": 0.0}
	print("dev  pron   flex  sum4    worst4  II    III   IV    V")
	for dev in [-35.0, -30.0, -25.0, -20.0, -15.0, -10.0, -5.0, 0.0]:
		for pron in [-30.0, -25.0, -20.0, -15.0, -10.0, -5.0, 0.0, 5.0, 10.0]:
			par["dev"] = dev
			par["pron"] = pron
			par["flex"] = -20.0
			var s := _side("L", _arm(par))
			var e: Dictionary = s["errs"]
			var sum4 := pow(float(e["II"]), 2.0) + pow(float(e["III"]), 2.0) \
				+ pow(float(e["IV"]), 2.0) + pow(float(e["V"]), 2.0)
			var worst4 := maxf(float(e["II"]), maxf(float(e["III"]),
				maxf(float(e["IV"]), float(e["V"]))))
			print("%5.1f %5.1f %6.1f %7.2f %6.2f  %5.2f %5.2f %5.2f %5.2f"
				% [dev, pron, -20.0, sum4, worst4, float(e["II"]),
				float(e["III"]), float(e["IV"]), float(e["V"])])
	# The valley's floor: what each pad misses in x/y/z and what the finger
	# angles are. This is where the ring-versus-pinky trade is visible.
	for cand in [[-20.0, 0.0], [-20.0, -5.0], [-25.0, -5.0], [-20.0, -10.0],
			[-22.5, -2.5]]:
		par["dev"] = float(cand[0])
		par["pron"] = float(cand[1])
		par["flex"] = -20.0
		var s := _side("L", _arm(par))
		print("== dev %.1f pron %.1f  sum4 %.2f worst %.2f" % [par["dev"],
			par["pron"], float(s["sum"]) - pow(float(s["errs"]["I"]), 2.0),
			float(s["worst"])])
		for ray in ["II", "III", "IV", "V"]:
			var t := _target("L", ray)
			var tw := Vector3(ROOT_L + t.x, t.y, t.z)
			var pad := _pad_world("L", ray, s["pose"])
			print("  %-3s pad %s target %s d %s angles %s" % [ray, str(pad),
				str(tw), str(pad - tw), str(s["pose"]["fingers"][ray])])
	quit(0)
