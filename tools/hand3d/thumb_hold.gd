# Can the thumb press a key with its own coordinate ALONE, once the hover pose
# has been solved? That is the author's rule: the hand must not sink as the
# thumb goes down. Solves press (arm free), hover (arm free, warm from press),
# then sweeps f on the HOVER arm and reports how close the pad gets to the
# press target and how far it drifts sideways.
#   mbt-godot --headless --path /work/tools/hand3d --script res://thumb_hold.gd
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
		var hr: Dictionary = IK.solve_chain("I", hover, pp, opts)
		var hp: Dictionary = hr["pose"]
		var hf := float(hp["thumb_f"])
		var hxf := ArmModel.hand_transform(hp["arm"])
		var best_f := hf
		var best_d := 1e9
		var best_pad := Vector3.ZERO
		for i in 401:
			var f := -1.0 + 2.0 * float(i) / 400.0
			var pad: Vector3 = hxf * HandModel.thumb_pad(HandModel.thumb_fk(f))
			var d := pad.distance_to(deep)
			if d < best_d:
				best_d = d
				best_f = f
				best_pad = pad
		var hp2: Vector3 = hxf * HandModel.thumb_pad(HandModel.thumb_fk(hf))
		var lat := Vector2(best_pad.x - deep.x, best_pad.y - deep.y).length()
		print("k%-2d hover f %6.3f | frozen-arm f %6.3f (df %+6.3f) pad (%.1f %.1f %.1f) err %5.2f lat %5.2f | hover pad z %.1f" % [
			k, hf, best_f, best_f - hf, best_pad.x, best_pad.y, best_pad.z,
			best_d, lat, hp2.z])
	quit(0)
