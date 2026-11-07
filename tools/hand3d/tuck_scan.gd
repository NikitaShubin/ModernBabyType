# Can an idle finger that grazes a keycap be moved out of it without touching
# the arm? Scans the fan share and the uniform curl of one idle finger on a
# solved press pose and prints the best skin-margin violation found.
#   mbt-godot --headless --path /work/tools/hand3d --script res://tuck_scan.gd -- V 43 IV
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")
const IK := preload("res://ik.gd")

const KEY_PITCH := 20.0
const KEY_X0 := -90.0
const KEY_Y0 := 80.0
const KEY_FACE := -69.0
const KEY_TRAVEL := 2.6
const THUMB_PRESS_LO := -0.35
const CLEAR_Z := KEY_FACE + 3.0
const KEY_RECT := Rect2(Vector2(0.0, 120.0), Vector2(98.5, 48.5))


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var ray := str(args[0]) if args.size() > 0 else "V"
	var k := int(args[1]) if args.size() > 1 else 43
	var other := str(args[2]) if args.size() > 2 else "IV"
	var face := Vector3(KEY_X0 + float(k % 10) * KEY_PITCH,
		KEY_Y0 + float(k / 10) * KEY_PITCH, KEY_FACE)
	var deep := Vector3(face.x, face.y, KEY_FACE - KEY_TRAVEL)
	var flo := THUMB_PRESS_LO if ray == "I" else -1.0
	var opts := {"arm": true, "f_lo": flo, "clear_z": CLEAR_Z,
		"clear_w": 100.0, "dir_w": 30.0, "clear_rect": KEY_RECT}
	var r: Dictionary = IK.solve_chain(ray, deep, HandModel.rest_pose(), opts)
	var p: Dictionary = r["pose"]
	IK.clear_z = CLEAR_Z
	IK.clear_w = 100.0
	IK.clear_cx = KEY_RECT.position.x
	IK.clear_cy = KEY_RECT.position.y
	IK.clear_hx = KEY_RECT.size.x
	IK.clear_hy = KEY_RECT.size.y
	var xf := ArmModel.hand_transform(p.get("arm", {}))
	var s: Array = IK.shares_of(other, p["fingers"][other])
	var base: float = IK._finger_violation(xf, other, p["fingers"][other],
		IK.TUCK_MARGIN)
	print("%s k%d %s base margin viol %.2f shares %s" % [
		ray, k, other, base, str(s)])
	for ci in 11:
		var curl: float = -float(ci) / 10.0
		var a: Dictionary = IK.angles_of_shares(other, [
			clampf(float(s[0]) + curl, -1.0, 1.0),
			clampf(float(s[1]) + curl, -1.0, 1.0),
			clampf(float(s[2]) + curl, -1.0, 1.0),
			float(s[3])])
		print("  curl %5.2f fan 0 -> margin viol %5.2f" % [curl,
			IK._finger_violation(xf, other, a, IK.TUCK_MARGIN)])
	for lim_i in 5:
		var lim: float = [0.0, 0.15, 0.30, 0.60, 1.0][lim_i]
		var best := base
		var best_at := "none"
		for fi in 41:
			var fan: float = -lim + 2.0 * lim * float(fi) / 40.0
			for ci in 41:
				var curl: float = -1.0 + 2.0 * float(ci) / 40.0
				var a: Dictionary = IK.angles_of_shares(other, [
					clampf(float(s[0]) + curl, -1.0, 1.0),
					clampf(float(s[1]) + curl, -1.0, 1.0),
					clampf(float(s[2]) + curl, -1.0, 1.0),
					clampf(fan, -1.0, 1.0)])
				var v: float = IK._finger_violation(xf, other, a,
					IK.TUCK_MARGIN)
				if v < best - 0.01:
					best = v
					best_at = "curl %5.2f fan %5.2f" % [curl, fan]
		print("fan |%.2f|: margin viol %.2f at %s" % [lim, best, best_at])
	quit(0)
