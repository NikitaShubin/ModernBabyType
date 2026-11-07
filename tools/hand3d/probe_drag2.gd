# Walks the chain drag from the rest pad to the far corner and prints every
# step, so a snap can be traced to the joint and the moment it happens.
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")
const IK := preload("res://ik.gd")


func _pad(ray: String, p: Dictionary) -> Vector3:
	var xf := ArmModel.hand_transform(p.get("arm", {}))
	return xf * HandModel.finger_pad(ray,
		HandModel.finger_fk(ray, p["fingers"][ray]))


func _init() -> void:
	var pose := HandModel.rest_pose()
	var prev: Dictionary = pose["arm"].duplicate(true)
	var start := _pad("II", pose)
	var end := Vector3(0, -80, -80)
	for i in 25:
		var u := float(i + 1) / 25.0
		var target := start.lerp(end, u)
		var r: Dictionary = IK.solve_chain("II", target, pose, {"arm": true})
		pose = r["pose"]
		var a: Dictionary = pose["arm"]
		var worst := 0.0
		var wj := ""
		for j in ArmModel.JOINTS:
			var d := absf(float(a[j]) - float(prev[j]))
			if d > worst:
				worst = d
				wj = j
		var lev: Dictionary = r["levels"]
		print("%2d err %5.2f step %5.1f %-14s | wf %5.1f wd %5.1f pr %5.1f el %5.1f tw %5.1f sf %5.1f sa %5.1f | f %3.0f w %3.0f e %3.0f s %3.0f it %d" % [
			i + 1, float(r["error"]), worst, wj,
			float(a["wrist_flex"]), float(a["wrist_dev"]), float(a["pronation"]),
			float(a["elbow"]), float(a["shoulder_twist"]), float(a["shoulder_flex"]),
			float(a["shoulder_abd"]), float(lev["finger"]), float(lev["wrist"]),
			float(lev["elbow"]), float(lev["shoulder"]), int(r["iterations"])])
		prev = a
	quit()
