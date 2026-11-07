# Times the pieces home_solve5 is built from, so its budget is known.
# It runs the same 5-ray x 3-settle block per side without the retargeting.
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
const THUMB_X := 23.0
const THUMB_LIFT := 2.0
const SETTLE := 3


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


func _opts(ray: String) -> Dictionary:
	var o := {"arm": false, "tuck": false, "clear_w": 0.0, "dir_w": 0.0}
	if ray == "I":
		o["thumb_dof"] = 4
	return o


func _arm(par: Dictionary) -> Dictionary:
	var a := ArmModel.rest_arm()
	var abd := deg_to_rad(float(par["abd"]))
	a["forearm_abd"] = float(par["abd"])
	a["wrist_dev"] = float(par["dev"])
	a["wrist_flex"] = float(par["flex"])
	a["pronation"] = float(par["pron"])
	a["elbow_x"] = float(par["wx"]) - ArmModel.FOREARM_L * sin(abd)
	a["elbow_y"] = float(par["wy"]) + ArmModel.FOREARM_L \
		- ArmModel.FOREARM_L * cos(abd)
	a["elbow_z"] = float(par["wz"])
	return a


func _side_noret(side: String, arm: Dictionary) -> void:
	var p := HandModel.rest_pose()
	p["arm"] = arm.duplicate(true)
	p["thumb_f"] = 0.0
	p["thumb"] = HandModel.thumb_at(0.0)
	p["thumb_dof"] = 4
	for ray in ["II", "III", "IV", "V", "I"]:
		var t := _target(side, ray)
		for it in SETTLE:
			var r: Dictionary = IK.solve_chain(ray, t, p, _opts(ray))
			p = r["pose"]
	# return nothing on purpose — this probe only measures time


func _init() -> void:
	var par := {"wx": 0.0, "wy": 20.0, "wz": -44.0, "abd": 22.0,
		"dev": -20.0, "flex": -20.0, "pron": 0.0}
	var arm := _arm(par)
	var p0 := HandModel.rest_pose()
	p0["arm"] = arm.duplicate(true)
	var warm: Dictionary = IK.solve_chain("II", _target("L", "II"), p0,
		_opts("II"))
	print("warm-up one solve: ms=")
	var t0 := Time.get_ticks_msec()
	var s := 0.0
	for i in 10:
		_side_noret("L", arm)
		s += 1.0
	var dt := Time.get_ticks_msec() - t0
	print("10 sides in %d ms -> per _score ~ %.0f ms, full search(360 evals) ~ %.1f min"
		% [dt, float(dt) * 0.2, float(dt) * 0.2 * 360.0 / 60000.0])
	quit(0)
