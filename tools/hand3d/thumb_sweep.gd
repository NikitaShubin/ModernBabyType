# Sweep the thumb's single coordinate f on a solved press pose and print the
# pad: where it goes, how deep it is, and how far it is from the key face.
# Answers the defect "hover already crosses the key": is the hover direction
# along the key normal at all?
#   mbt-godot --headless --path /work/tools/hand3d --script res://thumb_sweep.gd
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")
const IK := preload("res://ik.gd")

const KEY_PITCH := 20.0
const KEY_X0 := -90.0
const KEY_Y0 := 80.0
const KEY_Z := -70.0
const KEY_FACE := KEY_Z + 1.0
const THUMB_PRESS_LO := -0.35


func _init() -> void:
	var rest := HandModel.rest_pose()
	for k in [25, 0, 40, 49, 4, 45]:
		var ix: int = k % 10
		var iy: int = k / 10
		var c := Vector3(KEY_X0 + float(ix) * KEY_PITCH,
			KEY_Y0 + float(iy) * KEY_PITCH, KEY_Z)
		var face := Vector3(c.x, c.y, KEY_FACE)
		var deep := Vector3(c.x, c.y, KEY_FACE - 2.6 - 1.0)
		var res: Dictionary = IK.solve_chain("I", deep, rest,
			{"arm": true, "f_lo": THUMB_PRESS_LO})
		var pp: Dictionary = res["pose"]
		var arm: Dictionary = pp["arm"]
		var xf := ArmModel.hand_transform(arm)
		print("== key %d at (%.0f,%.0f) press f %.3f err %.3f" % [
			k, c.x, c.y, float(pp["thumb_f"]), float(res["error"])])
		print("   arm wrist %.1f/%.1f pron %.1f fore %.1f/%.1f elbow %.1f/%.1f/%.1f" % [
			float(arm["wrist_flex"]), float(arm["wrist_dev"]),
			float(arm["pronation"]), float(arm["forearm_flex"]),
			float(arm["forearm_abd"]), float(arm["elbow_x"]),
			float(arm["elbow_y"]), float(arm["elbow_z"])])
		for f in [-1.0, -0.8, -0.65, -0.5, -0.35, -0.2, -0.05, 0.0, 0.2, 0.4, 0.6, 1.0]:
			var p: Dictionary = pp.duplicate(true)
			p["thumb_f"] = f
			var local := HandModel.thumb_pad(HandModel.thumb_fk(f))
			var pad := xf * local
			var d := pad.distance_to(face)
			print("   f %5.2f  local (%7.2f %7.2f %7.2f)  pad (%7.2f %7.2f %7.2f)  dz %6.2f  d %6.2f" % [
				f, local.x, local.y, local.z, pad.x, pad.y, pad.z,
				pad.z - KEY_FACE, d])
	quit(0)
