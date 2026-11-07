# What does the typing home position look like if it is SOLVED, not posed?
#
# The anatomical rest pose is the hand's own zero, but its four fingertips do
# not lie on one straight line: the little finger is 27 mm short of the index.
# A keyboard's home row IS a straight line, so the hands must adapt. This probe
# cycles the same solve_chain the clicks use, one finger at a time, and prints
# where the pads end up and how much the arm had to move.
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")
const IK := preload("res://ik.gd")
const Kbd3D := preload("res://kbd3d.gd")

const HOVER := 12.0
const THUMB_HOVER := 5.0
const CLEAR_Z := Kbd3D.FACE_Z + 3.0

var _keys: Array


func _pad(p: Dictionary, ray: String) -> Vector3:
	var xf := ArmModel.hand_transform(p.get("arm", {}))
	if ray == "I":
		return xf * HandModel.thumb_pad(HandModel.thumb_fk(
			float(p.get("thumb_f", 0.0))))
	return xf * HandModel.finger_pad(ray,
		HandModel.finger_fk(ray, p["fingers"][ray]))


func _home_x() -> Dictionary:
	# In the left model's own space both hands share the same home targets:
	# the right hand is a mirror, so its local x is the same as the left's.
	var out := {}
	var ks := Kbd3D.keys()
	for ray in ["II", "III", "IV", "V"]:
		var label: String = {"II": "а", "III": "в", "IV": "ы", "V": "ф"}[ray]
		var c := Kbd3D.centre(ks[Kbd3D.index_of(ks, label)])
		out[ray] = c
	return out


func _init() -> void:
	_keys = Kbd3D.keys()
	var homes := _home_x()
	var root_x := -72.56
	var p := HandModel.rest_pose()
	print("rest pads:")
	for ray in ["I", "II", "III", "IV", "V"]:
		print("  ", ray, " ", _pad(p, ray))
	var targets := {}
	for ray in homes:
		var c: Vector3 = homes[ray]
		targets[ray] = Vector3(c.x - root_x, c.y, Kbd3D.FACE_Z + HOVER)
	# The space halves: nearest point to the rest thumb, not the centre.
	targets["I"] = Vector3(0.0 - root_x - 3.0, Kbd3D.row_y(4),
		Kbd3D.FACE_Z + THUMB_HOVER)
	print("targets:")
	for ray in targets:
		print("  ", ray, " ", targets[ray])
	for round_i in 3:
		for ray in ["II", "III", "IV", "V", "I"]:
			var opts := {"arm": true, "clear_z": CLEAR_Z, "clear_w": 100.0,
				"dir_w": 30.0}
			if ray == "I":
				opts["thumb_min"] = -0.7
			var r: Dictionary = IK.solve_chain(ray, targets[ray], p, opts)
			p = r["pose"]
		print("round ", round_i + 1, ":")
		for ray in ["I", "II", "III", "IV", "V"]:
			var pad := _pad(p, ray)
			var d := pad.distance_to(targets[ray])
			print("  ", ray, " pad ", pad, " err %.2f" % d)
		var a: Dictionary = p["arm"]
		print("  arm ", a)
		print("  thumb_f %.3f" % float(p.get("thumb_f", 0.0)))
	quit(0)
