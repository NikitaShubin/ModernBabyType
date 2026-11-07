# Can a finger lift off its key with its own flexion ALONE, the hand frozen?
# Solves the press (arm free), then sweeps a uniform flexion delta on the press
# pose and reports the pad's lift and sideways drift.
#   mbt-godot --headless --path /work/tools/hand3d --script res://finger_hold.gd
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
const DIR_W := 30.0

const CASES := [["II", 4], ["III", 4], ["IV", 4], ["V", 5], ["V", 44],
	["II", 49]]


func _init() -> void:
	var rest := HandModel.rest_pose()
	for c in CASES:
		var ray: String = c[0]
		var k: int = c[1]
		var ix: int = k % 10
		var iy: int = k / 10
		var face := Vector3(KEY_X0 + float(ix) * KEY_PITCH,
			KEY_Y0 + float(iy) * KEY_PITCH, KEY_FACE)
		var deep := Vector3(face.x, face.y, KEY_FACE - KEY_TRAVEL - 1.0)
		var pr: Dictionary = IK.solve_chain(ray, deep, rest,
			{"arm": true, "clear_z": CLEAR_Z, "clear_w": CLEAR_W,
			"dir_w": DIR_W})
		var p: Dictionary = pr["pose"]
		var xf := ArmModel.hand_transform(p["arm"])
		var fk := HandModel.finger_fk(ray, p["fingers"][ray])
		var pad0: Vector3 = xf * HandModel.finger_pad(ray, fk)
		var s: Array = IK.shares_of(ray, p["fingers"][ray])
		var s0 := "k%-2d %s err %4.2f pad (%.1f %.1f %.1f) |" % [k, ray,
			float(pr["error"]), pad0.x, pad0.y, pad0.z]
		for d in [-0.05, -0.10, -0.15, -0.20, -0.25, -0.30, -0.40]:
			var a: Dictionary = IK.angles_of_shares(ray, [
				clampf(float(s[0]) + float(d), -1.0, 1.0),
				clampf(float(s[1]) + float(d), -1.0, 1.0),
				clampf(float(s[2]) + float(d), -1.0, 1.0),
				float(s[3])])
			var pad: Vector3 = xf * HandModel.finger_pad(ray,
				HandModel.finger_fk(ray, a))
			var dv := pad - pad0
			s0 += " %+.2f:(%+.1f,%+.1f,%+.1f)" % [float(d), dv.x, dv.y, dv.z]
		print(s0)
	quit(0)
