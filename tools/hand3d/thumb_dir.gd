# Why the thumb's distal phalanx is not horizontal at the press: solve the
# same key with growing dir_w and print d2.z, the reach error and the arm.
#   mbt-godot --headless --path /work/tools/hand3d --script res://thumb_dir.gd
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
const CLEAR_W := 100.0
const KEY_RECT := Rect2(Vector2(0.0, 120.0), Vector2(98.5, 48.5))
const THUMB_PRESS_LO := -0.35

const KEYS := [9, 24, 0, 49, 44, 20, 40]


func _init() -> void:
	for k in KEYS:
		var ix: int = k % 10
		var iy: int = k / 10
		var face := Vector3(KEY_X0 + float(ix) * KEY_PITCH,
			KEY_Y0 + float(iy) * KEY_PITCH, KEY_FACE)
		var deep := Vector3(face.x, face.y, KEY_FACE - KEY_TRAVEL)
		for tag in [[0.0, -0.5], [30.0, -0.4], [30.0, -0.5], [30.0, -0.6],
				[30.0, -0.7], [30.0, -0.9]]:
			var dw: float = tag[0]
			var pr: Dictionary = IK.solve_chain("I", deep, HandModel.rest_pose(),
				{"arm": true, "f_lo": THUMB_PRESS_LO, "clear_z": CLEAR_Z,
				"clear_w": CLEAR_W, "dir_w": dw, "clear_rect": KEY_RECT,
				"thumb_min": tag[1]})
			var p: Dictionary = pr["pose"]
			var xf := ArmModel.hand_transform(p["arm"])
			var fk := HandModel.thumb_fk(float(p["thumb_f"]))
			var d2: Vector3 = (xf.basis * (fk["dirs"][2] as Vector3)).normalized()
			var pad: Vector3 = xf * HandModel.thumb_pad(fk)
			var arm: Dictionary = p["arm"]
			print("k%-2d dw %4.0f tm %5.2f err %4.2f f %6.3f d2 (%6.3f %6.3f %6.3f) pad (%7.2f %7.2f %7.2f) | wrist %6.1f/%6.1f pron %5.1f fore %5.1f/%5.1f elbow %5.1f,%5.1f,%5.1f" % [
				k, dw, float(tag[1]), float(pr["error"]), float(p["thumb_f"]),
				d2.x, d2.y, d2.z, pad.x, pad.y, pad.z,
				float(arm["wrist_flex"]), float(arm["wrist_dev"]),
				float(arm["pronation"]), float(arm["forearm_flex"]),
				float(arm["forearm_abd"]), float(arm["elbow_x"]),
				float(arm["elbow_y"]), float(arm["elbow_z"])])
	quit(0)
