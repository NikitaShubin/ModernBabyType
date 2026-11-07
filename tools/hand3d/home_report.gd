# The home pose as the viewer builds it, printed in world millimetres: wrists,
# elbows, every pad, the thumb gap, and the angles that made it. This is the
# baseline the author is looking at, not a test.
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")
const IK := preload("res://ik.gd")
const Kbd3D := preload("res://kbd3d.gd")
const HomePose := preload("res://home_pose.gd")

const ROOTS := {"L": -72.51, "R": 43.94}
const ARM_KEYS := ["wrist_flex", "wrist_dev", "pronation", "forearm_flex",
	"forearm_abd", "elbow_x", "elbow_y", "elbow_z"]


func _xf(p: Dictionary) -> Transform3D:
	return ArmModel.hand_transform(p.get("arm", {}))


func _pad_world(side: String, ray: String, p: Dictionary) -> Vector3:
	var rx: float = ROOTS[side]
	var xf := _xf(p)
	var local: Vector3
	if ray == "I":
		local = xf * HandModel.thumb_pad(HandModel.thumb_fk(
			HandModel.thumb_of_pose(p)))
	else:
		local = xf * HandModel.finger_pad(ray,
			HandModel.finger_fk(ray, p["fingers"][ray]))
	if side == "R":
		return Vector3(rx - local.x, local.y, local.z)
	return Vector3(rx + local.x, local.y, local.z)


func _elbow_world(side: String, p: Dictionary) -> Vector3:
	var rx: float = ROOTS[side]
	var w: Vector3 = ArmModel.elbow_of(p["arm"])
	if side == "R":
		return Vector3(rx - w.x, w.y, w.z)
	return Vector3(rx + w.x, w.y, w.z)


func _init() -> void:
	var ks := Kbd3D.keys()
	var pads := {}
	var elbows := {}
	for side in ["L", "R"]:
		var p: Dictionary = HomePose.build(side, ROOTS[side])
		var xf := _xf(p)
		var wrist := xf.origin
		var ww := wrist
		if side == "R":
			ww = Vector3(ROOTS[side] - wrist.x, wrist.y, wrist.z)
		else:
			ww = Vector3(ROOTS[side] + wrist.x, wrist.y, wrist.z)
		var ew := _elbow_world(side, p)
		elbows[side] = ew
		print("=== %s root %.2f  wrist world %s  elbow world %s"
			% [side, ROOTS[side], str(ww), str(ew)])
		print("    arm %s" % str(p["arm"]))
		for ray in ["II", "III", "IV", "V", "I"]:
			var pad := _pad_world(side, ray, p)
			pads[side + ray] = pad
			var label := ""
			if ray == "I":
				label = "пробел"
			else:
				label = String((HomePose.HOME_LABELS[side] as Dictionary)[ray])
			var k: Dictionary = ks[Kbd3D.index_of(ks, label)]
			var c := Kbd3D.centre(k)
			print("    %-3s %-7s pad %s  key %s  dx %+6.2f dy %+6.2f dz %+6.2f"
				% [ray, label, str(pad), str(c), pad.x - c.x, pad.y - c.y,
					pad.z - c.z])
	var gap := (pads["RI"] as Vector3).distance_to(pads["LI"] as Vector3)
	var egap: float = (elbows["L"] as Vector3).distance_to(elbows["R"] as Vector3)
	print("elbow gap %.1f mm (L %s R %s)" % [egap, str(elbows["L"]),
		str(elbows["R"])])
	print("thumb pad gap %.2f mm (L %s R %s)" % [gap,
		str(pads["LI"]), str(pads["RI"])])
	quit(0)
