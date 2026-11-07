# The drag from rest to the far pose: which joint takes the big step and where?
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")
const IK := preload("res://ik.gd")


func _pad_of_chain(ray: String, p: Dictionary) -> Vector3:
	var xf := ArmModel.hand_transform(p.get("arm", {}))
	if ray == "I":
		return xf * HandModel.thumb_pad(HandModel.thumb_fk(float(p["thumb_f"])))
	return xf * HandModel.finger_pad(ray,
		HandModel.finger_fk(ray, p["fingers"][ray]))


func _init() -> void:
	var far_pose := HandModel.rest_pose()
	far_pose["arm"]["forearm_abd"] = 35.0
	far_pose["arm"]["forearm_flex"] = -25.0
	var pose := HandModel.rest_pose()
	var start := _pad_of_chain("II", pose)
	var end := _pad_of_chain("II", far_pose)
	for i in 25:
		var u := float(i + 1) / 25.0
		var target := start.lerp(end, u)
		var r: Dictionary = IK.solve_chain("II", target, pose, {"arm": true})
		var a: Dictionary = r["arm"]
		var s := ArmModel.shares_of(a)
		print("%2d u %.2f err %6.3f elbow %+7.1f %+7.1f %+7.1f | wf %+6.1f wd %+6.1f pr %+6.1f ff %+6.1f fa %+6.1f | %s" % [
			i + 1, u, float(r["error"]),
			float(a["elbow_x"]), float(a["elbow_y"]), float(a["elbow_z"]),
			float(a["wrist_flex"]), float(a["wrist_dev"]), float(a["pronation"]),
			float(a["forearm_flex"]), float(a["forearm_abd"]),
			_lev(r)])
		pose = r["pose"]
	quit()


func _lev(r: Dictionary) -> String:
	var l: Dictionary = r["levels"]
	return "fing %.0f fan %.0f wrist %.0f pron %.0f fore %.0f elbow %.0f" % [
		float(l["finger"]), float(l["fan"]), float(l["wrist"]),
		float(l["pronation"]), float(l["forearm"]), float(l["elbow"])]
