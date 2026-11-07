# Which joint holds the press pose off the keyboard: every finger joint's world
# position and its prism violation at two skin margins, for one press.
#   mbt-godot --headless --path /work/tools/hand3d --script res://press_clear.gd -- V 39
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
const THUMB_PRESS_LO := -0.35
const CLEAR_Z := KEY_FACE + 3.0
const KEY_RECT := Rect2(Vector2(0.0, 120.0), Vector2(98.5, 48.5))


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var ray := "V" if args.size() < 1 else str(args[0])
	var k := 39 if args.size() < 2 else int(args[1])
	var ix: int = k % 10
	var iy: int = k / 10
	var face := Vector3(KEY_X0 + float(ix) * KEY_PITCH,
		KEY_Y0 + float(iy) * KEY_PITCH, KEY_FACE)
	var deep := Vector3(face.x, face.y, KEY_FACE - KEY_TRAVEL)
	var flo := THUMB_PRESS_LO if ray == "I" else -1.0
	var pr: Dictionary = IK.solve_chain(ray, deep, HandModel.rest_pose(),
		{"arm": true, "f_lo": flo, "clear_z": CLEAR_Z,
		"clear_w": 100.0, "dir_w": 30.0, "clear_rect": KEY_RECT})
	var p: Dictionary = pr["pose"]
	var xf := ArmModel.hand_transform(p.get("arm", {}))
	print("%s k%d err %.2f" % [ray, k, float(pr["error"])])
	for other in ["II", "III", "IV", "V"]:
		var pts: PackedVector3Array = HandModel.finger_fk(other,
			p["fingers"][other])["pts"]
		var radii: Array = HandModel.SKIN_R[other]
		var last := 4 if other != ray else 3
		for j in last:
			var w: Vector3 = xf * pts[j]
			var r := float(radii[j])
			_row(other, j, w, r)
	var tpts: PackedVector3Array = HandModel.thumb_fk(
		float(p["thumb_f"]))["pts"]
	var tradii := [11.8, 10.8, 9.6, 6.6]
	var tlast := 4 if ray != "I" else 3
	for j in tlast:
		var w: Vector3 = xf * tpts[j]
		_row("I", j, w, float(tradii[j]))
	quit(0)


func _row(ray: String, j: int, w: Vector3, r: float) -> void:
	var s := "%s[%d] %7.1f %7.1f %7.1f r %4.1f" % [ray, j, w.x, w.y, w.z, r]
	for margin in [0.0, 2.0, 4.0]:
		s += " | m%.0f v%5.2f" % [margin,
			_joint(w.x, w.y, w.z, r + margin)]
	print(s)


func _joint(x: float, y: float, z: float, r: float) -> float:
	var qx := absf(x) - KEY_RECT.size.x
	var qy := absf(y - KEY_RECT.position.y) - KEY_RECT.size.y
	var qz := z - CLEAR_Z
	var ox := maxf(qx, 0.0)
	var oy := maxf(qy, 0.0)
	var oz := maxf(qz, 0.0)
	var sdf := sqrt(ox * ox + oy * oy + oz * oz) \
		+ minf(maxf(qx, maxf(qy, qz)), 0.0)
	return maxf(0.0, r - sdf)
