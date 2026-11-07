# What the thumb does on a key click, in numbers. The author's rule (30.10.2026):
# the hand must not sink while the thumb itself goes down onto the key. So the
# press is solved with the arm held at the approach pose, and this probe checks
# the two things that can go wrong with that: the arm must not move at all, and
# the thumb must still reach the key's face.
#   mbt-godot --headless --path /work/tools/hand3d --script res://click_probe.gd
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")
const IK := preload("res://ik.gd")

const KEY_PITCH := 20.0
const KEY_X0 := -90.0
const KEY_Y0 := 80.0
const KEY_Z := -70.0
const KEY_FACE := KEY_Z + 1.0
const KEY_HOVER := 12.0
const KEY_TRAVEL := 2.6

const KEYS := [["top-left", 0, 4], ["middle", 5, 2], ["top-right", 9, 4],
	["bottom-left", 0, 0]]


func _init() -> void:
	for k in KEYS:
		var name: String = k[0]
		var c := Vector3(KEY_X0 + float(k[1]) * KEY_PITCH,
			KEY_Y0 + float(k[2]) * KEY_PITCH, KEY_Z)
		var hover := Vector3(c.x, c.y, KEY_FACE + KEY_HOVER)
		var deep := Vector3(c.x, c.y, KEY_FACE - KEY_TRAVEL - 1.0)
		var rest := HandModel.rest_pose()
		var h: Dictionary = IK.solve_chain("I", hover, rest, {"arm": true})
		var hf: Dictionary = IK.solve_chain("I", deep, h["pose"], {"arm": false})
		var hw: Dictionary = IK.solve_chain("I", deep, h["pose"], {"arm": true})
		var ph: Vector3 = h["pad"]
		var pf: Vector3 = hf["pad"]
		var pw: Vector3 = hw["pad"]
		var arm_h: Dictionary = h["pose"]["arm"]
		var arm_f: Dictionary = hf["pose"]["arm"]
		var arm_w: Dictionary = hw["pose"]["arm"]
		var d_arm := 0.0
		for key in arm_h:
			d_arm = maxf(d_arm, absf(float(arm_h[key]) - float(arm_f[key])))
		print("=== %s key (%.0f, %.0f)" % [name, c.x, c.y])
		print("  hover: f %.3f reach %.3f pad %s" % [float(h["pose"]["thumb_f"]),
			float(h["error"]), str(ph)])
		print("  frozen press: f %.3f reach %.3f pad %s  arm max delta %.4f" % [
			float(hf["pose"]["thumb_f"]), float(hf["error"]), str(pf), d_arm])
		print("  free press:   f %.3f reach %.3f pad %s" % [
			float(hw["pose"]["thumb_f"]), float(hw["error"]), str(pw)])
		print("  pad travel frozen: %s (%.3f mm)" % [str(pf - ph),
			(pf - ph).length()])
		print("  pad travel free:   %s (%.3f mm)" % [str(pw - ph),
			(pw - ph).length()])
		print("  arm hover %s" % str(_brief(arm_h)))
		print("  arm free  %s" % str(_brief(arm_w)))
		# The hand's own frame: where the wrist sits in world space.
		var wh := ArmModel.hand_transform(arm_h)
		var wf := ArmModel.hand_transform(arm_f)
		var ww := ArmModel.hand_transform(arm_w)
		print("  wrist origin frozen move %.4f mm, free move %.4f mm" % [
			(wf.origin - wh.origin).length(), (ww.origin - wh.origin).length()])
		print("  wrist delta free %s, frozen %s" % [
			str(ww.origin - wh.origin), str(wf.origin - wh.origin)])
	quit(0)


func _brief(a: Dictionary) -> String:
	var out := ""
	for key in ["wrist_flex", "wrist_dev", "pronation", "elbow_x", "elbow_y",
			"elbow_z"]:
		out += "%s %.2f  " % [key, float(a.get(key, 0.0))]
	return out
