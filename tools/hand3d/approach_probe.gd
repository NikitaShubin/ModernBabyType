# How far the hand is from the keyboard in the rest pose, and how far a straight
# joint interpolation rest → hover → press dips behind the 3 mm margin. Prints
# the analytic clearance (a joint minus its soft-tissue radius, the same rule
# ik.gd uses) of the keyframes, the worst violation of the RAW path (built
# without the guard) together with the lift ClickPath applies there, and the
# worst violation of the GUARDED path, which must be zero.
#   mbt-godot --headless --path /work/tools/hand3d --script res://approach_probe.gd
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")
const IK := preload("res://ik.gd")
const ClickPath := preload("res://click_path.gd")

const KEY_PITCH := 20.0
const KEY_SIZE := 17.0
const KEY_X0 := -90.0
const KEY_Y0 := 80.0
const KEY_Z := -70.0
const KEY_FACE := KEY_Z + 1.0
const KEY_HOVER := 12.0
const THUMB_HOVER := 5.0
const KEY_TRAVEL := 2.6
const THUMB_PRESS_LO := -0.35
const CLEAR_Z := KEY_FACE + 3.0
const KEY_RECT := Rect2(Vector2(0.0, 120.0), Vector2(98.5, 48.5))
const CLEAR_W := 100.0
const DIR_W := 30.0
const APPROACH := 0.35
const PRESS := 0.16
const RELEASE := 0.12
const RETURN := 0.40
const STEPS := 40

const CASES := [["I", 9], ["I", 24], ["II", 4], ["III", 4], ["IV", 4],
	["V", 5], ["V", 44], ["II", 49], ["III", 24]]


func _init() -> void:
	var rest := HandModel.rest_pose()
	print("rest clearance %.2f | II %5.2f III %5.2f IV %5.2f V %5.2f I %5.2f" % [
		IK.clearance("", rest, CLEAR_Z, KEY_RECT),
		_deep(rest, "II"), _deep(rest, "III"), _deep(rest, "IV"),
		_deep(rest, "V"), _deep(rest, "I")])
	for c in CASES:
		var ray: String = c[0]
		var k: int = c[1]
		var ix: int = k % 10
		var iy: int = k / 10
		var face := Vector3(KEY_X0 + float(ix) * KEY_PITCH,
			KEY_Y0 + float(iy) * KEY_PITCH, KEY_FACE)
		var deep := Vector3(face.x, face.y, KEY_FACE - KEY_TRAVEL)
		var flo := THUMB_PRESS_LO if ray == "I" else -1.0
		var pr: Dictionary = IK.solve_chain(ray, deep, rest,
			{"arm": true, "f_lo": flo, "clear_z": CLEAR_Z,
			"clear_w": CLEAR_W, "dir_w": DIR_W, "clear_rect": KEY_RECT})
		var pp: Dictionary = pr["pose"]
		var ppad := _pad(ray, pp)
		var hov := THUMB_HOVER if ray == "I" else KEY_HOVER
		var lift: float = maxf(0.0, (KEY_FACE + hov) - ppad.z)
		var hp: Dictionary = pp.duplicate(true)
		hp["arm"]["elbow_z"] = float(hp["arm"].get("elbow_z", 0.0)) + lift
		var raw_path: Dictionary = ClickPath.build(rest, hp, pp,
			APPROACH, PRESS, RELEASE, RETURN)
		var path: Dictionary = ClickPath.build(rest, hp, pp,
			APPROACH, PRESS, RELEASE, RETURN,
			{"ray": ray, "clear_z": CLEAR_Z, "clear_rect": KEY_RECT,
			"key": k})
		var total := float(path["total"])
		var raw_worst := -1e9
		var raw_t := 0.0
		var raw_bone := ""
		var raw_lift := 0.0
		var guarded_worst := -1e9
		for i in STEPS + 1:
			var t := total * float(i) / float(STEPS)
			var raw: Dictionary = ClickPath.at(raw_path, t)
			var v := IK.clearance(ray, raw, CLEAR_Z, KEY_RECT)
			if v > raw_worst:
				raw_worst = v
				raw_t = t
				raw_bone = _worst_bone(ray, raw)
				raw_lift = v
			var g: Dictionary = ClickPath.at(path, t)
			guarded_worst = maxf(guarded_worst,
				IK.clearance(ray, g, CLEAR_Z, KEY_RECT))
		print("%s k%-2d press clr %5.2f hover clr %5.2f | raw worst %6.2f at t %.2f (%s) lift %5.2f | guarded worst %5.2f" % [
			ray, k, IK.clearance(ray, pp, CLEAR_Z, KEY_RECT),
			IK.clearance(ray, hp, CLEAR_Z, KEY_RECT), raw_worst, raw_t,
			raw_bone, raw_lift, guarded_worst])
	quit(0)


func _deep(p: Dictionary, ray: String) -> float:
	var xf := ArmModel.hand_transform(p.get("arm", {}))
	if ray == "I":
		var fk := HandModel.thumb_fk(float(p["thumb_f"]))
		var pts: PackedVector3Array = fk["pts"]
		var rr := [11.8, 10.8, 9.6, 6.6]
		var d := 1e9
		for j in 4:
			d = minf(d, (xf * pts[j]).z - float(rr[j]))
		return d
	var pts2: PackedVector3Array = HandModel.finger_fk(ray,
		p["fingers"][ray])["pts"]
	var radii: Array = HandModel.SKIN_R[ray]
	var d2 := 1e9
	for j in 4:
		d2 = minf(d2, (xf * pts2[j]).z - float(radii[j]))
	return d2


func _worst_bone(ray: String, p: Dictionary) -> String:
	var xf := ArmModel.hand_transform(p.get("arm", {}))
	var best := 1e9
	var name := ""
	for other in ["II", "III", "IV", "V"]:
		var angles: Dictionary = p["fingers"][other]
		var pts: PackedVector3Array = HandModel.finger_fk(other, angles)["pts"]
		var radii: Array = HandModel.SKIN_R[other]
		var last := 3 if other == ray else 4
		for j in last:
			var z: float = (xf * pts[j]).z - float(radii[j])
			if z < best:
				best = z
				name = "%s_%d" % [other, j]
	if ray != "I":
		var fk := HandModel.thumb_fk(float(p["thumb_f"]))
		var pts2: PackedVector3Array = fk["pts"]
		var rr := [11.8, 10.8, 9.6, 6.6]
		for j in 4:
			var z2: float = (xf * pts2[j]).z - float(rr[j])
			if z2 < best:
				best = z2
				name = "I_%d" % j
	return "%s z%.2f" % [name, best]


func _pad(ray: String, p: Dictionary) -> Vector3:
	var xf := ArmModel.hand_transform(p.get("arm", {}))
	if ray == "I":
		return xf * HandModel.thumb_pad(HandModel.thumb_fk(float(p["thumb_f"])))
	return xf * HandModel.finger_pad(ray,
		HandModel.finger_fk(ray, p["fingers"][ray]))
