# Where does the thumb solve spend its time, and who does the work? One target
# at a time, timed, with the joint deltas against the home pose.
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")
const IK := preload("res://ik.gd")
const Kbd3D := preload("res://kbd3d.gd")
const HomePose := preload("res://home_pose.gd")

const CLEAR_Z := Kbd3D.FACE_Z + 3.0
const ARM_KEYS := ["wrist_flex", "wrist_dev", "pronation", "forearm_flex",
	"forearm_abd", "elbow_x", "elbow_y", "elbow_z"]


func _pad(side: String, ray: String, p: Dictionary) -> Vector3:
	var xf := ArmModel.hand_transform(p.get("arm", {}))
	if ray == "I":
		return xf * HandModel.thumb_pad(HandModel.thumb_fk(
			HandModel.thumb_of_pose(p)))
	return xf * HandModel.finger_pad(ray,
		HandModel.finger_fk(ray, p["fingers"][ray]))


func _init() -> void:
	for side in ["L", "R"]:
		var root_x := -72.51 if side == "L" else 43.94
		var sgn := 1.0 if side == "L" else -1.0
		var t0 := Time.get_ticks_msec()
		var home: Dictionary = HomePose.build(side, root_x)
		printerr("=== %s home in %d ms" % [side, Time.get_ticks_msec() - t0])
		var rest_thumb := _pad(side, "I", home)
		var rest_ii := _pad(side, "II", home)
		var th0: Dictionary = HandModel.thumb_of_pose(home)
		var arm0: Dictionary = home["arm"]
		var cases := {
			"space near": -23.0 if side == "L" else 23.0,
			"alt": -111.0 if side == "L" else 68.0,
			"ctrl": -126.9 if side == "L" else 126.9,
			"globe": 0.0,
		}
		for nm in cases:
			var wx: float = cases[nm]
			if nm == "globe":
				if side == "L":
					continue
				wx = 94.9
			var t := Vector3((wx - root_x) * sgn, Kbd3D.row_y(4),
				Kbd3D.FACE_Z - Kbd3D.TRAVEL)
			var t0b := Time.get_ticks_msec()
			var r: Dictionary = IK.solve_chain("I", t, home,
				{"arm": true, "thumb_dof": 4, "clear_z": CLEAR_Z,
				"clear_w": 100.0, "dir_w": 30.0})
			var ms := Time.get_ticks_msec() - t0b
			var pose: Dictionary = r["pose"]
			var pad := _pad(side, "I", pose)
			var ii := _pad(side, "II", pose)
			var th: Dictionary = HandModel.thumb_of_pose(pose)
			var arm: Dictionary = pose["arm"]
			var dth := []
			for j in HandModel.THUMB_JOINTS:
				dth.append("%+.1f" % (float(th[j]) - float(th0[j])))
			var darm := []
			for j in ARM_KEYS:
				darm.append("%+.1f" % (float(arm.get(j, 0.0))
					- float(arm0.get(j, 0.0))))
			printerr("  %-10s %4d ms err %.3f it %2d  thumb %6.1f hand %6.1f"
				% [nm, ms, float(r["error"]), int(r["iterations"]),
				pad.distance_to(rest_thumb), ii.distance_to(rest_ii)])
			printerr("      dthumb %s" % " ".join(dth))
			printerr("      darm   %s" % " ".join(darm))
	quit(0)
