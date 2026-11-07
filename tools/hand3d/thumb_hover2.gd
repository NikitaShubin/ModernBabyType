# The thumb's hover: the author's rule is that the hand must not sink with the
# thumb, so the hover should be the SAME arm pose with the thumb's own
# coordinate moved back (hover_lift / thumb_df), not a rigid translation of the
# whole hand. Prints, for a set of keys and several hover distances, the press
# error, the hover error and the thumb coordinate step.
#   mbt-godot --headless --path /work/tools/hand3d --script res://thumb_hover2.gd
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
const THUMB_PRESS_LO := -0.35

const KEYS := [0, 9, 24, 44, 49, 20, 40, 25]
const LIFTS := [12.0, 8.0, 5.0, 4.0]


func _init() -> void:
	var rest := HandModel.rest_pose()
	for k in KEYS:
		var ix: int = k % 10
		var iy: int = k / 10
		var face := Vector3(KEY_X0 + float(ix) * KEY_PITCH,
			KEY_Y0 + float(iy) * KEY_PITCH, KEY_FACE)
		var deep := Vector3(face.x, face.y, KEY_FACE - KEY_TRAVEL)
		var line := "k%-2d" % k
		for lift in LIFTS:
			var pr: Dictionary = IK.solve_chain("I", deep, rest,
				{"arm": true, "f_lo": THUMB_PRESS_LO, "clear_z": CLEAR_Z,
				"clear_w": 100.0, "dir_w": 30.0, "clear_rect": KEY_RECT,
				"thumb_min": -0.7, "hover_lift": lift})
			var p: Dictionary = pr["pose"]
			var xf := ArmModel.hand_transform(p["arm"])
			var f := float(p["thumb_f"])
			var df := float(p.get("thumb_df", 0.0))
			var press := xf * HandModel.thumb_pad(HandModel.thumb_fk(f))
			var hover := xf * HandModel.thumb_pad(HandModel.thumb_fk(f - df))
			var dz := hover.z - press.z
			line += " | %4.1f: perr %4.2f f %6.3f df %5.3f dz %5.2f dx %5.2f" % [
				lift, float(pr["error"]), f, df, dz, hover.x - press.x]
		print(line)
	quit(0)
