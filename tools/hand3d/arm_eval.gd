# Evaluate candidate arm placements with the digits' DEPTH scanned over the
# key: for each finger, try several y targets across the key's depth and keep
# the pose that comes closest to the key's column and face. Reports the best
# per-finger error and the depth it lands at.
#
#   mbt-godot --headless --path /work/tools/hand3d --script res://arm_eval.gd
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
const YS := [0.0, -3.0, -6.0, -9.0, 3.0, 6.0, 9.0]


func _arm(p: Dictionary) -> Dictionary:
	var a := ArmModel.rest_arm()
	var abd := deg_to_rad(float(p["abd"]))
	a["forearm_abd"] = float(p["abd"])
	a["forearm_flex"] = 0.0
	a["wrist_dev"] = float(p["dev"])
	a["wrist_flex"] = float(p["flex"])
	a["pronation"] = float(p["pron"])
	a["elbow_x"] = float(p["wx"]) - ArmModel.FOREARM_L * sin(abd)
	a["elbow_y"] = float(p["wy"]) + ArmModel.FOREARM_L \
		- ArmModel.FOREARM_L * cos(abd)
	a["elbow_z"] = float(p["wz"])
	return a


func _opts(ray: String) -> Dictionary:
	var o := {"arm": false, "tuck": false, "clear_w": 0.0, "dir_w": 0.0}
	if ray == "I":
		o["thumb_dof"] = 4
	return o


func _run(tag: String, par: Dictionary) -> void:
	var arm := _arm(par)
	var xf := ArmModel.hand_transform(arm)
	var ks := Kbd3D.keys()
	var worst := 0.0
	var line := ""
	for ray in ["II", "III", "IV", "V"]:
		var c := Kbd3D.centre(ks[Kbd3D.index_of(ks, HOME_LABELS[ray])])
		var best := 1e9
		var best_y := 0.0
		var best_pad := Vector3.ZERO
		var best_a := {}
		for dy in YS:
			var t := Vector3(c.x - ROOT_L, c.y + float(dy),
				Kbd3D.FACE_Z + TOUCH)
			var p := HandModel.rest_pose()
			p["arm"] = arm.duplicate(true)
			var r: Dictionary = IK.solve_chain(ray, t, p, _opts(ray))
			var pad: Vector3 = xf * HandModel.finger_pad(ray,
				HandModel.finger_fk(ray, r["angles"]))
			pad.x += ROOT_L
			var ex := pad.x - c.x
			var ez := pad.z - (Kbd3D.FACE_Z + TOUCH)
			var d := sqrt(ex * ex + ez * ez)
			if d < best:
				best = d
				best_y = pad.y
				best_pad = pad
				best_a = r["angles"]
		worst = maxf(worst, best)
		line += "%s %.2f@y%.1f " % [ray, best, best_y]
	print("%-8s worst %5.2f  %s" % [tag, worst, line])
	print("         arm %s" % str(par))
	for ray in ["II", "III", "IV", "V"]:
		var c := Kbd3D.centre(ks[Kbd3D.index_of(ks, HOME_LABELS[ray])])
		var best := 1e9
		var best_y := 0.0
		var best_a := {}
		for dy in YS:
			var t := Vector3(c.x - ROOT_L, c.y + float(dy),
				Kbd3D.FACE_Z + TOUCH)
			var p := HandModel.rest_pose()
			p["arm"] = arm.duplicate(true)
			var r: Dictionary = IK.solve_chain(ray, t, p, _opts(ray))
			var pad: Vector3 = xf * HandModel.finger_pad(ray,
				HandModel.finger_fk(ray, r["angles"]))
			pad.x += ROOT_L
			var ex := pad.x - c.x
			var ez := pad.z - (Kbd3D.FACE_Z + TOUCH)
			var d := sqrt(ex * ex + ez * ez)
			if d < best:
				best = d
				best_y = pad.y
				best_a = r["angles"]
		print("   %-3s d %5.2f at y %6.1f  angles %s" % [ray, best, best_y,
			str(best_a)])
	# The thumb.
	var ti := Kbd3D.index_of(ks, "пробел")
	var sp: Rect2 = ks[ti]["r"]
	var tx := -THUMB_X
	var t := Vector3(tx - ROOT_L, sp.get_center().y, Kbd3D.FACE_Z + THUMB_LIFT)
	var p := HandModel.rest_pose()
	p["arm"] = arm.duplicate(true)
	p["thumb_dof"] = 4
	p["thumb"] = HandModel.thumb_at(0.0)
	var r: Dictionary = IK.solve_chain("I", t, p, _opts("I"))
	var pad: Vector3 = xf * HandModel.thumb_pad(HandModel.thumb_fk(
		HandModel.thumb_of_pose(r["pose"])))
	pad.x += ROOT_L
	print("   I   err %.3f  pad %s  thumb %s" % [(pad - Vector3(tx, t.y, t.z)).length(),
		str(pad), str(HandModel.thumb_of_pose(r["pose"]))])


func _init() -> void:
	_run("A", {"wx": 0.0, "wy": 20.6120624542236, "wz": -43.75, "abd": 22.0,
		"dev": -20.0, "flex": -20.0, "pron": 0.0})
	_run("B", {"wx": -0.5, "wy": 20.0, "wz": -42.5, "abd": 21.5,
		"dev": -20.0, "flex": -20.0, "pron": -0.25})
	_run("C", {"wx": 1.0, "wy": 20.0, "wz": -44.0, "abd": 22.0,
		"dev": -20.0, "flex": -20.0, "pron": 0.0})
	_run("D", {"wx": 0.0, "wy": 20.0, "wz": -44.0, "abd": 22.0,
		"dev": -20.0, "flex": -20.0, "pron": 0.0})
	quit(0)
