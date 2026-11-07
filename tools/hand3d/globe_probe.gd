# Where the right thumb's pad really is when it presses the globe.
#
# The viewer's HUD reports the solver's pad error in the hand's LOCAL space;
# the eye sees the mirrored world. This probe prints both, so a mismatch
# between "the solver says 0.00" and "the bones show the little finger on the
# key" can be attributed to the solver or to the rendering.
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")
const IK := preload("res://ik.gd")
const Kbd3D := preload("res://kbd3d.gd")
const HomePose := preload("res://home_pose.gd")

const CLEAR_Z := Kbd3D.FACE_Z + 3.0


func _pad(ray: String, p: Dictionary) -> Vector3:
	var xf := ArmModel.hand_transform(p.get("arm", {}))
	if ray == "I":
		return xf * HandModel.thumb_pad(HandModel.thumb_fk(
			HandModel.thumb_of_pose(p)))
	return xf * HandModel.finger_pad(ray,
		HandModel.finger_fk(ray, p["fingers"][ray]))


func _init() -> void:
	var root_x := 43.94
	var home: Dictionary = HomePose.build("R", root_x)
	var ks := Kbd3D.keys()
	var key: Dictionary = ks[Kbd3D.index_of(ks, "глобус")]
	var w := Kbd3D.centre(key)
	var local := Vector3(-(w.x - root_x), w.y, w.z - Kbd3D.TRAVEL)
	printerr("globe world %s local %s" % [str(w), str(local)])
	var r: Dictionary = IK.solve_chain("I", local, home,
		{"arm": true, "thumb_dof": 4, "clear_z": CLEAR_Z, "clear_w": 100.0,
		"dir_w": 30.0})
	var p: Dictionary = r["pose"]
	for ray in ["I", "II", "V"]:
		var pad := _pad(ray, p)
		var world := Vector3(root_x - pad.x, pad.y, pad.z)
		printerr("%s local %s world %s" % [ray, str(pad), str(world)])
	printerr("   err %.3f it %d" % [float(r["error"]), int(r["iterations"])])
	printerr("   thumb %s" % str(HandModel.thumb_of_pose(p)))
	printerr("   arm %s" % str(p["arm"]))
	quit(0)
