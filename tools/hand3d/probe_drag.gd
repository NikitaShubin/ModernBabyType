# Follows a 1 mm drag along a far path and prints, for every step, what the
# warm run achieves and how long the full solve takes. A drag must be cheap;
# if the warm run lands short, the retry fires on every step.
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")
const IK := preload("res://ik.gd")


func _shares(r: Dictionary) -> Array:
	var q := []
	for v in r["shares"]:
		q.append(float(v))
	q.append(float(r["fan_share"]))
	for v in r["arm_shares"]:
		q.append(float(v))
	return q


func _init() -> void:
	var rest := HandModel.rest_pose()
	var pose := rest.duplicate(true)
	var t0 := Time.get_ticks_usec()
	for i in 8:
		var target := Vector3(0, -80, -80) + Vector3(float(i), 0, 0)
		var q := []
		q += IK.shares_of("II", pose["fingers"]["II"])
		q += ArmModel.shares_of(pose.get("arm", {}))
		q = IK._project_chain(q, "II", true)
		var warm: Dictionary = IK._chain_run("II", target, pose, q, true)
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		print("step %d warm reach %.3f it %d (%.1f ms)" % [i,
			float(warm["cur"]["reach"]), int(warm["iters"]), ms])
		var r: Dictionary = IK.solve_chain("II", target, pose, {"arm": true})
		pose = r["pose"]
		print("   final err %.3f it %d, total %.1f ms" % [float(r["error"]),
			int(r["iterations"]), (Time.get_ticks_usec() - t0) / 1000.0])
	quit()
