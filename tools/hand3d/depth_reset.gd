# The II depth for the straight-wrist whole-shifted hands (SS50 family).
# The author (02.11.2026): shift the arms so the fingers rest on their own
# home columns with minimal curl. At dev 0 the index chain cannot both reach
# its D-era depth (y 154) and touch the key face (dz +4.0); this probe scans
# the target depth y for every home finger and prints where the pad's x/z hit
# the column/face exactly — the ladder's honest values for THIS arm.
extends SceneTree

const HomePose := preload("res://home_pose.gd")
const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")
const IK := preload("res://ik.gd")
const Kbd3D := preload("res://kbd3d.gd")

const ROOT := -122.51
const RAYS := ["II", "III", "IV", "V"]
const HOME_X := {"II": -42.86, "III": -61.91, "IV": -80.96, "V": -100.01}


func _init() -> void:
	var rays: int = RAYS.size()
	for ri in rays:
		var ray: String = RAYS[ri]
		var row: String = ray + ": "
		for yi in range(0, 12):
			var y := 146.0 + float(yi)
			var p := HandModel.rest_pose()
			p["arm"] = (HomePose.ARM as Dictionary).duplicate(true)
			p["thumb_f"] = 0.0
			p["thumb"] = HandModel.thumb_at(0.0)
			p["thumb_dof"] = 4
			var hx: float = float(HOME_X[ray])
			var t := Vector3(hx - ROOT, y, float(Kbd3D.FACE_Z)
				+ float(HomePose.TOUCH))
			var r: Dictionary = IK.solve_chain(ray, t, p,
				HomePose._opts(ray))
			var pose: Dictionary = r["pose"]
			var fingers: Dictionary = pose["fingers"]
			var angles: Dictionary = fingers[ray]
			var q := HandModel.finger_pad(ray,
				HandModel.finger_fk(ray, angles))
			var wp: Vector3 = ArmModel.hand_transform(p["arm"]) * q
			wp = Vector3(ROOT + wp.x, wp.y, wp.z)
			var dx: float = wp.x - hx
			var dz: float = wp.z - (float(Kbd3D.FACE_Z) + float(HomePose.TOUCH))
			row += "| %3.0f: %+.2f/%+.2f " % [y, dx, dz]
		print(row)
	quit(0)
