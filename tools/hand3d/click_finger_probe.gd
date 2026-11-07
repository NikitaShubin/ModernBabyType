# The click's new shape for the four fingers: solve the press with the arm
# free, then the hover from that pose with the arm frozen. How far can the
# finger alone lift off the key, and is the hand parked during the press?
#   mbt-godot --headless --path /work/tools/hand3d --script res://click_finger_probe.gd
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

const KEYS := [[0, 0], [5, 2], [9, 4], [0, 4], [9, 0]]


func _init() -> void:
	var rest := HandModel.rest_pose()
	for ray in ["II", "III", "V"]:
		for k in KEYS:
			var c := Vector3(KEY_X0 + float(k[0]) * KEY_PITCH,
				KEY_Y0 + float(k[1]) * KEY_PITCH, KEY_Z)
			var face := Vector3(c.x, c.y, KEY_FACE)
			var deep := Vector3(c.x, c.y, KEY_FACE - KEY_TRAVEL - 1.0)
			var press: Dictionary = IK.solve_chain(ray, deep, rest, {"arm": true})
			var hov: Dictionary = IK.solve_chain(ray,
				face + Vector3(0.0, 0.0, KEY_HOVER), press["pose"],
				{"arm": false})
			var hov2: Dictionary = IK.solve_chain(ray,
				face + Vector3(0.0, 0.0, KEY_HOVER), rest, {"arm": true})
			var press2: Dictionary = IK.solve_chain(ray, deep, hov2["pose"],
				{"arm": false})
			var pp: Dictionary = press["pose"]
			var hp: Dictionary = hov["pose"]
			var dp := _pad(ray, pp).distance_to(face)
			var dh := _pad(ray, hp).distance_to(face)
			var a: Dictionary = pp["arm"]
			print("%s key %d,%d  press err %5.2f d %5.2f | hover err %5.2f d %5.2f | wrist %5.1f/%5.1f pron %5.1f elbow %5.1f,%5.1f,%5.1f" % [
				ray, k[0], k[1], float(press["error"]), dp, float(hov["error"]),
				dh, float(a["wrist_flex"]), float(a["wrist_dev"]),
				float(a["pronation"]), float(a["elbow_x"]),
				float(a["elbow_y"]), float(a["elbow_z"])])
			print("    hover-from-rest err %5.2f d %5.2f -> press-frozen err %5.2f d %5.2f (hover arm wrist %5.1f elbow %5.1f,%5.1f)" % [
				float(hov2["error"]), _pad(ray, hov2["pose"]).distance_to(face),
				float(press2["error"]), _pad(ray, press2["pose"]).distance_to(face),
				float(hov2["pose"]["arm"]["wrist_flex"]),
				float(hov2["pose"]["arm"]["elbow_x"]),
				float(hov2["pose"]["arm"]["elbow_y"])])
			var hov3: Dictionary = IK.solve_chain(ray,
				face + Vector3(0.0, 0.0, KEY_HOVER), press["pose"], {"arm": true})
			var ah: Dictionary = hov3["pose"]["arm"]
			print("    hover-from-press err %5.2f d %5.2f | dwrist %5.2f dpron %5.2f delbow %5.2f,%5.2f,%5.2f" % [
				float(hov3["error"]), _pad(ray, hov3["pose"]).distance_to(face),
				float(ah["wrist_flex"]) - float(a["wrist_flex"]),
				float(ah["pronation"]) - float(a["pronation"]),
				float(ah["elbow_x"]) - float(a["elbow_x"]),
				float(ah["elbow_y"]) - float(a["elbow_y"]),
				float(ah["elbow_z"]) - float(a["elbow_z"])])
	quit(0)


func _pad(ray: String, p: Dictionary) -> Vector3:
	var xf: Transform3D = ArmModel.hand_transform(p.get("arm", {}))
	return xf * HandModel.finger_pad(ray, HandModel.finger_fk(ray, p["fingers"][ray]))
