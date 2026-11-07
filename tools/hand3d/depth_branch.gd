# One finger, several DEPTH targets: the settle picks the branch nearest the
# key centre, but the little finger has an exact x/z solution further forward
# (its pad reaches the face at y about 146 mm). Prints the pad and the x/z
# error for each y so the branch can be seen.
#
#   mbt-godot --headless --path /work/tools/hand3d --script res://depth_branch.gd
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")
const IK := preload("res://ik.gd")
const Kbd3D := preload("res://kbd3d.gd")

const ROOT_L := -72.51
const HOME_LABELS := {"II": "а", "III": "в", "IV": "ы", "V": "ф"}
const TOUCH := 0.3


func _arm() -> Dictionary:
	var a := ArmModel.rest_arm()
	a["forearm_abd"] = 22.0
	a["wrist_dev"] = -20.0
	a["wrist_flex"] = -20.0
	a["pronation"] = 0.0
	a["elbow_x"] = 0.0 - ArmModel.FOREARM_L * sin(deg_to_rad(22.0))
	a["elbow_y"] = 20.6120624542236 + ArmModel.FOREARM_L \
		- ArmModel.FOREARM_L * cos(deg_to_rad(22.0))
	a["elbow_z"] = -43.75
	return a


func _init() -> void:
	var arm := _arm()
	var xf := ArmModel.hand_transform(arm)
	var ks := Kbd3D.keys()
	for ray in ["IV", "V"]:
		var c := Kbd3D.centre(ks[Kbd3D.index_of(ks, HOME_LABELS[ray])])
		print("== %s key %s" % [ray, str(c)])
		for dy in [0.0, -2.0, -4.0, -6.0, -8.0]:
			var t := Vector3(c.x - ROOT_L, c.y + dy, Kbd3D.FACE_Z + TOUCH)
			var p := HandModel.rest_pose()
			p["arm"] = arm.duplicate(true)
			var r: Dictionary = IK.solve_chain(ray, t, p, {
				"arm": false, "tuck": false, "clear_w": 0.0, "dir_w": 0.0})
			var pad: Vector3 = xf * HandModel.finger_pad(ray,
				HandModel.finger_fk(ray, r["angles"]))
			pad.x += ROOT_L
			var ex := pad.x - c.x
			var ez := pad.z - (Kbd3D.FACE_Z + TOUCH)
			print("  y %6.1f  pad %s  dx %6.2f dz %6.2f  d %5.2f  angles %s"
				% [c.y + dy, str(pad), ex, ez, sqrt(ex * ex + ez * ez),
				str(r["angles"])])
	quit(0)
