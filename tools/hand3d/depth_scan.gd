# The reachable DEPTH window of each home key for one arm: prints the x/z
# error at every millimetre of y across the key. The pad needs only its own
# depth, so the useful question is "from which y can it touch the face".
#
#   mbt-godot --headless --path /work/tools/hand3d --script res://depth_scan.gd
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")
const IK := preload("res://ik.gd")
const Kbd3D := preload("res://kbd3d.gd")

const ROOT_L := -72.51
const HOME_LABELS := {"II": "а", "III": "в", "IV": "ы", "V": "ф"}
const TOUCH := 0.3


func _init() -> void:
	var arm := ArmModel.rest_arm()
	arm["forearm_abd"] = 22.0
	arm["wrist_dev"] = -20.0
	arm["wrist_flex"] = -20.0
	arm["pronation"] = 0.0
	arm["elbow_x"] = 0.0 - ArmModel.FOREARM_L * sin(deg_to_rad(22.0))
	arm["elbow_y"] = 20.0 + ArmModel.FOREARM_L \
		- ArmModel.FOREARM_L * cos(deg_to_rad(22.0))
	arm["elbow_z"] = -44.0
	var xf := ArmModel.hand_transform(arm)
	var ks := Kbd3D.keys()
	for ray in ["II", "III", "IV", "V"]:
		var c := Kbd3D.centre(ks[Kbd3D.index_of(ks, HOME_LABELS[ray])])
		var line := "%-3s " % ray
		var first := -99.0
		var last := -99.0
		for k in 21:
			var dy := -10.0 + float(k)
			var t := Vector3(c.x - ROOT_L, c.y + dy, Kbd3D.FACE_Z + TOUCH)
			var p := HandModel.rest_pose()
			p["arm"] = arm.duplicate(true)
			var r: Dictionary = IK.solve_chain(ray, t, p,
				{"arm": false, "tuck": false, "clear_w": 0.0, "dir_w": 0.0})
			var pad: Vector3 = xf * HandModel.finger_pad(ray,
				HandModel.finger_fk(ray, r["angles"]))
			pad.x += ROOT_L
			var ex := pad.x - c.x
			var ez := pad.z - (Kbd3D.FACE_Z + TOUCH)
			var d := sqrt(ex * ex + ez * ez)
			line += "%4.1f" % d
			if d <= 0.5:
				if first < -90.0:
					first = dy
				last = dy
		print(line)
		print("    touch window dy %5.1f .. %5.1f (key depth half 10.4)"
			% [first, last])
	quit(0)
