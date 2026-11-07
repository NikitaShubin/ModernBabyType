# The four-joint thumb through the real chain solver: a press on the left
# half of the space bar at the home arm pose, and a finger click with the
# thumb idle (tucked). Prints the pose, the pad, and the whole-hand clearance.
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")
const IK := preload("res://ik.gd")
const Kbd3D := preload("res://kbd3d.gd")

const ROOT_X := -72.56
const CLEAR_Z := Kbd3D.FACE_Z + 3.0


func _pad(p: Dictionary, ray: String) -> Vector3:
	var xf := ArmModel.hand_transform(p.get("arm", {}))
	if ray == "I":
		return xf * HandModel.thumb_pad(HandModel.thumb_fk(
			HandModel.thumb_of_pose(p)))
	return xf * HandModel.finger_pad(ray,
		HandModel.finger_fk(ray, p["fingers"][ray]))


func _init() -> void:
	var home_arm := ArmModel.rest_arm()
	home_arm["wrist_flex"] = -20.0
	home_arm["wrist_dev"] = 0.625
	home_arm["pronation"] = -6.875
	home_arm["elbow_x"] = 0.625
	home_arm["elbow_y"] = 12.5
	home_arm["elbow_z"] = -35.0
	var base := HandModel.rest_pose()
	base["arm"] = home_arm
	base["thumb"] = HandModel.thumb_at(0.0)
	base["thumb_dof"] = 4
	base["thumb_f"] = 0.0

	var space_y := Kbd3D.row_y(4)
	var targets := {
		"space L half": Vector3(-23.0 - ROOT_X, space_y,
			Kbd3D.FACE_Z - Kbd3D.TRAVEL),
		"space split": Vector3(0.0 - ROOT_X, space_y,
			Kbd3D.FACE_Z - Kbd3D.TRAVEL),
	}
	for name in targets:
		var t: Vector3 = targets[name]
		var r: Dictionary = IK.solve_chain("I", t, base,
			{"arm": true, "thumb_dof": 4, "clear_z": CLEAR_Z,
			"clear_w": 100.0, "dir_w": 30.0})
		var pose: Dictionary = r["pose"]
		var pad := _pad(pose, "I")
		print("%s: target %s" % [name, str(t)])
		print("  err %.3f  pad %s  iters %d" % [float(r["error"]),
			str(pad), int(r["iterations"])])
		print("  angles %s" % str(r["angles"]))
		print("  shares %s  energy %.3f  chain %.4f" % [str(r["shares"]),
			float(r["energy"]), float(r["chain_energy"])])
		print("  arm %s" % str(r["arm"]))
		var model := HandModel.new(1.0, 0.0, pose)
		var mpad := HandModel.thumb_pad(HandModel.thumb_fk(
			model.thumb_angles()))
		print("  model thumb %s pad delta %.6f" % [
			str(model.thumb_angles()), mpad.distance_to(
				HandModel.thumb_pad(HandModel.thumb_fk(
					HandModel.thumb_of_pose(pose))))])
		print("  clearance plane-wide %.3f" % IK.clearance("I", pose,
			CLEAR_Z, Rect2(), 0.0))

	# A finger click with the 4-DOF thumb idle: the thumb must be tucked and
	# still carry the marker, so the model reads its four joints.
	var t2 := Vector3(29.7, Kbd3D.row_y(1), Kbd3D.FACE_Z - Kbd3D.TRAVEL)
	var r2: Dictionary = IK.solve_chain("II", t2, base,
		{"arm": true, "thumb_dof": 4, "clear_z": CLEAR_Z, "clear_w": 100.0,
		"dir_w": 30.0})
	var p2: Dictionary = r2["pose"]
	print("II: err %.3f  thumb_dof %d  thumb_f %.3f" % [float(r2["error"]),
		int(p2.get("thumb_dof", 0)), float(p2.get("thumb_f", 0.0))])
	print("  thumb %s" % str(HandModel.thumb_of_pose(p2)))
	print("  clearance %.3f" % IK.clearance("II", p2, CLEAR_Z, Rect2(), 0.0))
	var m2 := HandModel.new(1.0, 0.0, p2)
	print("  model thumb %s" % str(m2.thumb_angles()))
	quit(0)
