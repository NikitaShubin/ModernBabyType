# Why the little finger cannot press the far keys, and what the direction term
# costs. Solves the same key with the clearance prism, the direction term and
# both switched off, and prints the arm, the residual and the distal phalanx.
# A constraint that eats the reach shows as an error that collapses when it is
# removed; a pose that "reaches" with d3 pointing AWAY from the keys (d3.z > 0)
# is not a press, it is the finger bent backwards.
#   mbt-godot --headless --path /work/tools/hand3d --script res://v5_probe.gd
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")
const IK := preload("res://ik.gd")

const KEY_PITCH := 20.0
const KEY_X0 := -90.0
const KEY_Y0 := 80.0
const KEY_Z := -70.0
const KEY_FACE := KEY_Z + 1.0
const KEY_TRAVEL := 2.6
const CLEAR_Z := KEY_FACE + 3.0
const KEY_RECT := Rect2(Vector2(0.0, 120.0), Vector2(98.5, 48.5))

const KEYS := [5, 15, 25, 6, 4, 14, 45, 44, 49]

# [tag, dir_w, dir_min]; dir_w 0 switches the term off.
const TAGS := [
	["w30 m.5", 30.0, -0.5],
	["w30 m.65", 30.0, -0.65],
	["w30 m.8", 30.0, -0.8],
	["w60 m.5", 60.0, -0.5],
	["w10 m.5", 10.0, -0.5],
	["off", 0.0, -0.5],
	["no_clr", 30.0, -0.5],
]


func _init() -> void:
	var rest := HandModel.rest_pose()
	for k in KEYS:
		var ix: int = k % 10
		var iy: int = k / 10
		var face := Vector3(KEY_X0 + float(ix) * KEY_PITCH,
			KEY_Y0 + float(iy) * KEY_PITCH, KEY_FACE)
		var deep := Vector3(face.x, face.y, KEY_FACE - KEY_TRAVEL)
		print("== V k%d at (%6.1f %6.1f)" % [k, face.x, face.y])
		for tag in TAGS:
			var o := {"arm": true, "f_lo": -1.0}
			if tag[0] != "no_clr":
				o["clear_z"] = CLEAR_Z
				o["clear_w"] = 100.0
				o["clear_rect"] = KEY_RECT
			o["dir_w"] = tag[1]
			o["dir_min"] = tag[2]
			var pr: Dictionary = IK.solve_chain("V", deep, rest, o)
			var p: Dictionary = pr["pose"]
			var arm: Dictionary = p["arm"]
			var pad := _pad("V", p)
			var fk := HandModel.finger_fk("V", p["fingers"]["V"])
			var d3: Vector3 = (ArmModel.hand_transform(arm).basis
				* (fk["dirs"][2] as Vector3)).normalized()
			print("   %-9s err %5.2f pad (%6.1f %6.1f %7.2f) d3 (%5.2f %5.2f %5.2f) | wrist %6.1f/%6.1f pron %5.1f fore %5.1f/%5.1f elbow %6.1f,%6.1f,%6.1f" % [
				tag[0], float(pr["error"]), pad.x, pad.y, pad.z,
				d3.x, d3.y, d3.z,
				float(arm["wrist_flex"]), float(arm["wrist_dev"]),
				float(arm["pronation"]), float(arm["forearm_flex"]),
				float(arm["forearm_abd"]), float(arm["elbow_x"]),
				float(arm["elbow_y"]), float(arm["elbow_z"])])
	quit(0)


func _pad(ray: String, p: Dictionary) -> Vector3:
	var xf := ArmModel.hand_transform(p.get("arm", {}))
	return xf * HandModel.finger_pad(ray,
		HandModel.finger_fk(ray, p["fingers"][ray]))
