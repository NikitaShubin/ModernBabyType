# The thumb's own arc at a solved press pose: how the pad moves when the thumb
# coordinate opens by df, with the arm frozen. The click hover is built from it:
# the thumb opens until the pad is KEY_HOVER in front, and the hand translates
# only the remainder — the author's rule is that the hand must not sink when the
# thumb presses.
#   mbt-godot --headless --path /work/tools/hand3d --script res://thumb_arc.gd
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
const KEY_RECT := Rect2(Vector2(0.0, 120.0), Vector2(98.5, 48.5))
const THUMB_PRESS_LO := -0.35

const KEYS := [0, 9, 24, 44, 49, 20, 40, 25]


func _init() -> void:
	var rest := HandModel.rest_pose()
	for k in KEYS:
		var ix: int = k % 10
		var iy: int = k / 10
		var face := Vector3(KEY_X0 + float(ix) * KEY_PITCH,
			KEY_Y0 + float(iy) * KEY_PITCH, KEY_FACE)
		var deep := Vector3(face.x, face.y, KEY_FACE - KEY_TRAVEL)
		var pr: Dictionary = IK.solve_chain("I", deep, rest,
			{"arm": true, "f_lo": THUMB_PRESS_LO, "clear_z": CLEAR_Z,
			"clear_w": 100.0, "dir_w": 30.0, "clear_rect": KEY_RECT,
			"thumb_min": -0.7})
		var p: Dictionary = pr["pose"]
		var xf := ArmModel.hand_transform(p["arm"])
		var f := float(p["thumb_f"])
		var pad0: Vector3 = xf * HandModel.thumb_pad(HandModel.thumb_fk(f))
		var line := "k%-2d err %5.2f f %6.3f" % [k, float(pr["error"]), f]
		var need := 0.0
		var found := false
		for i in 21:
			var df := 0.05 * float(i)
			if df > f + 1.0:
				break
			var pad: Vector3 = xf * HandModel.thumb_pad(HandModel.thumb_fk(f - df))
			var dz := pad.z - pad0.z
			var dxy := Vector2(pad.x - pad0.x, pad.y - pad0.y).length()
			if not found and dz >= KEY_HOVER:
				found = true
				need = df
				line += " | lift at %.2f: dz %5.2f dxy %5.2f" % [df, dz, dxy]
			if i % 4 == 0:
				line += " | %.2f dz %5.2f dxy %5.2f" % [df, dz, dxy]
		if not found:
			line += " | NEVER lifts"
		print(line)
	quit(0)
