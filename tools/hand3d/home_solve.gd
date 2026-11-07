# Solves the typing HOME pose: every fingertip over its own home key, both
# hands sharing one arm pose, the thumb over its side of the space bar.
#
# The hand's anatomical rest is the zero of the joint energy, but its pads are
# not on a straight line (the little finger is 27 mm short of the index), so a
# keyboard's home row needs an adapted pose. The arm is a rigid translation
# (the elbow), so the fixed point is simple: solve every finger with the arm
# frozen, then move the elbow by the MEAN pad error. The fingers keep their
# relative geometry, the elbow takes the common part.
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")
const IK := preload("res://ik.gd")
const Kbd3D := preload("res://kbd3d.gd")

const HOVER := 12.0
const THUMB_HOVER := 5.0
const CLEAR_Z := Kbd3D.FACE_Z + 3.0

const ROOT_X := -72.56


func _pad(p: Dictionary, ray: String) -> Vector3:
	var xf := ArmModel.hand_transform(p.get("arm", {}))
	if ray == "I":
		return xf * HandModel.thumb_pad(HandModel.thumb_fk(
			float(p.get("thumb_f", 0.0))))
	return xf * HandModel.finger_pad(ray,
		HandModel.finger_fk(ray, p["fingers"][ray]))


func _targets() -> Dictionary:
	var ks := Kbd3D.keys()
	var out := {}
	for ray in ["II", "III", "IV", "V"]:
		var label: String = {"II": "а", "III": "в", "IV": "ы", "V": "ф"}[ray]
		var c := Kbd3D.centre(ks[Kbd3D.index_of(ks, label)])
		out[ray] = Vector3(c.x - ROOT_X, c.y, Kbd3D.FACE_Z + HOVER)
	# The left thumb presses just left of the split; the nearest point of its
	# half to the rest pad, as the game's own press_point rule does for a wide
	# key. (The right hand is the mirror, so its local target is the same.)
	out["I"] = Vector3(0.0 - ROOT_X - 3.0, Kbd3D.row_y(4),
		Kbd3D.FACE_Z + THUMB_HOVER)
	return out


func _init() -> void:
	var targets := _targets()
	var p := HandModel.rest_pose()
	p["arm"]["elbow_y"] = 20.0
	var rays := ["II", "III", "IV", "V", "I"]
	for it in 10:
		for ray in rays:
			var opts := {"arm": false, "tuck": false, "clear_z": CLEAR_Z,
				"clear_w": 100.0, "dir_w": 30.0}
			if ray == "I":
				opts["thumb_min"] = -0.7
			var r: Dictionary = IK.solve_chain(ray, targets[ray], p, opts)
			p = r["pose"]
		var sum := Vector3.ZERO
		var worst := 0.0
		for ray in rays:
			var pad := _pad(p, ray)
			var e := (targets[ray] as Vector3) - pad
			sum += e
			worst = maxf(worst, e.length())
		var mean := sum / 5.0
		print("iter %2d  mean %s  worst %.2f  elbow %.2f %.2f %.2f" % [
			it, str(mean), worst, float(p["arm"]["elbow_x"]),
			float(p["arm"]["elbow_y"]), float(p["arm"]["elbow_z"])])
		for ray in rays:
			var pad := _pad(p, ray)
			print("   ", ray, " pad ", pad, " err %.2f" % pad.distance_to(
				targets[ray]))
		if mean.length() < 0.05:
			break
		p["arm"]["elbow_x"] = float(p["arm"]["elbow_x"]) + mean.x
		p["arm"]["elbow_y"] = float(p["arm"]["elbow_y"]) + mean.y
		p["arm"]["elbow_z"] = float(p["arm"]["elbow_z"]) + mean.z
	print("HOME POSE:")
	print("  fingers ", p["fingers"])
	print("  thumb_f ", p["thumb_f"])
	print("  arm ", p["arm"])
	quit(0)
