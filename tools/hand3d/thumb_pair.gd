# The thumb's hover and press as two separate solves: the press from rest, the
# hover from the press (warm), both with the arm free. Prints where each pad
# lands, the thumb's f, and how much the hand moves between the two — the
# author's rule is that the hand must not sink as the thumb goes down.
#   mbt-godot --headless --path /work/tools/hand3d --script res://thumb_pair.gd
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
const KEY_HOVER := 12.0
const CLEAR_Z := KEY_FACE + 3.0
const CLEAR_W := 100.0
const DIR_W := 30.0
const THUMB_PRESS_LO := -0.35

const KEYS := [0, 4, 5, 9, 20, 24, 25, 29, 40, 44, 45, 49]


func _init() -> void:
	var rest := HandModel.rest_pose()
	for k in KEYS:
		var ix: int = k % 10
		var iy: int = k / 10
		var face := Vector3(KEY_X0 + float(ix) * KEY_PITCH,
			KEY_Y0 + float(iy) * KEY_PITCH, KEY_FACE)
		var deep := Vector3(face.x, face.y, KEY_FACE - KEY_TRAVEL - 1.0)
		var hover := Vector3(face.x, face.y, KEY_FACE + KEY_HOVER)
		var opts := {"arm": true, "f_lo": THUMB_PRESS_LO, "clear_z": CLEAR_Z,
			"clear_w": CLEAR_W, "dir_w": DIR_W}
		var pr: Dictionary = IK.solve_chain("I", deep, rest, opts)
		var pp: Dictionary = pr["pose"]
		var pf := float(pp["thumb_f"])
		var pxf := ArmModel.hand_transform(pp["arm"])
		var ppad: Vector3 = pxf * HandModel.thumb_pad(HandModel.thumb_fk(pf))
		var hr: Dictionary = IK.solve_chain("I", hover, pp, opts)
		var hp: Dictionary = hr["pose"]
		var hf := float(hp["thumb_f"])
		var hxf := ArmModel.hand_transform(hp["arm"])
		var hpad: Vector3 = hxf * HandModel.thumb_pad(HandModel.thumb_fk(hf))
		var lat := Vector2(hpad.x - ppad.x, hpad.y - ppad.y).length()
		var pa: Dictionary = pp["arm"]
		var ha: Dictionary = hp["arm"]
		print("k%-2d press err %4.2f f %6.3f pad (%.1f %.1f %.1f) | hover err %4.2f f %6.3f pad (%.1f %.1f %.1f) dz %5.2f lat %5.2f | d wrist %+5.1f/%+5.1f pron %+5.1f fore %+5.1f/%+5.1f elbow %+5.1f/%+5.1f/%+5.1f" % [
			k, float(pr["error"]), pf, ppad.x, ppad.y, ppad.z,
			float(hr["error"]), hf, hpad.x, hpad.y, hpad.z,
			hpad.z - ppad.z, lat,
			float(ha["wrist_flex"]) - float(pa["wrist_flex"]),
			float(ha["wrist_dev"]) - float(pa["wrist_dev"]),
			float(ha["pronation"]) - float(pa["pronation"]),
			float(ha["forearm_flex"]) - float(pa["forearm_flex"]),
			float(ha["forearm_abd"]) - float(pa["forearm_abd"]),
			float(ha["elbow_x"]) - float(pa["elbow_x"]),
			float(ha["elbow_y"]) - float(pa["elbow_y"]),
			float(ha["elbow_z"]) - float(pa["elbow_z"])])
	quit(0)
