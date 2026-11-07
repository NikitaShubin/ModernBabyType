# The shared home pose on both hands: pad errors against the home targets,
# the thumb's own reach on each side, and the plane clearance.
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")
const Kbd3D := preload("res://kbd3d.gd")
const HomePose := preload("res://home_pose.gd")
const IK := preload("res://ik.gd")


func _pad(p: Dictionary, ray: String) -> Vector3:
	var xf := ArmModel.hand_transform(p.get("arm", {}))
	if ray == "I":
		return xf * HandModel.thumb_pad(HandModel.thumb_fk(
			HandModel.thumb_of_pose(p)))
	return xf * HandModel.finger_pad(ray,
		HandModel.finger_fk(ray, p["fingers"][ray]))


func _init() -> void:
	var ks := Kbd3D.keys()
	var pad_ii := HandModel.finger_pad("II",
		HandModel.finger_fk("II", HandModel.rest_pose()["fingers"]["II"])).x
	var a := Kbd3D.centre(ks[Kbd3D.index_of(ks, "а")]).x
	var o := Kbd3D.centre(ks[Kbd3D.index_of(ks, "о")]).x
	var roots := {"L": a - pad_ii, "R": o + pad_ii}
	print("roots L %.2f R %.2f  pad_ii %.2f" % [roots["L"], roots["R"], pad_ii])
	for side in ["L", "R"]:
		var rx: float = roots[side]
		var p := HomePose.build(side, rx)
		print("%s hand:" % side)
		for ray in ["I", "II", "III", "IV", "V"]:
			var t := HomePose.target(side, ray, rx)
			var pad := _pad(p, ray)
			var xy := Vector2(pad.x - t.x, pad.y - t.y).length()
			print("  %s key xy err %.3f  z %.2f (target plane %.2f)" % [ray,
				xy, pad.z, t.z])
		print("  thumb %s" % str(HandModel.thumb_of_pose(p)))
		print("  arm %s" % str(p["arm"]))
		print("  clearance %.3f" % IK.clearance("I", p,
			Kbd3D.FACE_Z + 3.0, Rect2(), 0.0))
	quit(0)
