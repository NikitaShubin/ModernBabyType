# What the post-solve skin-margin tuck does to a press pose: per-finger capsule
# violation before and after, and the pose clearance the path guard will see.
#   mbt-godot --headless --path /work/tools/hand3d --script res://tuck_probe.gd -- V 43
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
	var face := Vector3(KEY_X0 + float(k % 10) * KEY_PITCH,
		KEY_Y0 + float(k / 10) * KEY_PITCH, KEY_FACE)
	var deep := Vector3(face.x, face.y, KEY_FACE - KEY_TRAVEL)
	var flo := THUMB_PRESS_LO if ray == "I" else -1.0
	var opts := {"arm": true, "f_lo": flo, "clear_z": CLEAR_Z,
		"clear_w": 100.0, "dir_w": 30.0, "clear_rect": KEY_RECT}
	var r: Dictionary = IK.solve_chain(ray, deep, HandModel.rest_pose(), opts)
	var p: Dictionary = r["pose"]
	print("after solve: err %.2f clr %.2f" % [float(r["error"]),
		IK.clearance(ray, p, CLEAR_Z, KEY_RECT)])
	_dump(p, ray)
	# Re-run the margin tuck by hand on a copy and compare.
	var copy: Dictionary = p.duplicate(true)
	IK.clear_z = CLEAR_Z
	IK.clear_w = 100.0
	IK.clear_cx = KEY_RECT.position.x
	IK.clear_cy = KEY_RECT.position.y
	IK.clear_hx = KEY_RECT.size.x
	IK.clear_hy = KEY_RECT.size.y
	IK._tuck_others(ray, copy, IK.TUCK_MARGIN)
	print("after extra tuck: clr %.2f" % IK.clearance(ray, copy, CLEAR_Z, KEY_RECT))
	_dump(copy, ray)
	quit(0)


func _dump(p: Dictionary, ray: String) -> void:
	var xf := ArmModel.hand_transform(p.get("arm", {}))
	for other in ["II", "III", "IV", "V"]:
		var v: float = IK._finger_violation(xf, other, p["fingers"][other], 0.0)
		var vm: float = IK._finger_violation(xf, other, p["fingers"][other],
			IK.TUCK_MARGIN)
		var a: Dictionary = p["fingers"][other]
		print("  %s m%5.1f p%5.1f d%5.1f | viol %5.2f margin viol %5.2f" % [
			other, float(a["mcp"]), float(a["pip"]), float(a["dip"]), v, vm])
	print("  I f %5.2f" % float(p.get("thumb_f", 0.0)))
