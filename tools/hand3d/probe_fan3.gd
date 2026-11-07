# Does polishing the WARM answer's nullspace (not the analytic seed) push the
# wrist out of a sideways target? And how far does the pose move?
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")
const IK := preload("res://ik.gd")


func _q_of(ray: String, p: Dictionary) -> Array:
	var q := []
	if ray == "I":
		q.append(float(p.get("thumb_f", 0.0)))
	else:
		q += IK.shares_of(ray, p["fingers"][ray])
	q += ArmModel.shares_of(p.get("arm", {}))
	return IK._project_chain(q, ray, true)


func _init() -> void:
	var rest := HandModel.rest_pose()
	for ray in HandModel.FINGERS:
		var p := HandModel.rest_pose()
		var xf := ArmModel.hand_transform(p["arm"])
		var base: Vector3 = xf * HandModel.finger_pad(ray,
			HandModel.finger_fk(ray, p["fingers"][ray]))
		var outward := 1.0 if ray in ["II", "III"] else -1.0
		var target: Vector3 = base + Vector3(5.0 * outward, 0.0, 0.0)
		var warm: Dictionary = IK.solve_chain(ray, target, p, {"arm": true})
		var q := _q_of(ray, warm["pose"])
		var pol: Dictionary = IK._chain_run(ray, target, warm["pose"], q, true, true)
		print("%s warm fan %+6.2f wrist %5.2f fore %5.2f err %.3f | polish fan %+6.2f wrist %5.2f fore %5.2f err %.3f it %d" % [
			ray,
			float(warm["angles"]["fan"]), maxf(absf(float(warm["arm"]["wrist_flex"])), absf(float(warm["arm"]["wrist_dev"]))),
			maxf(absf(float(warm["arm"]["forearm_flex"])), absf(float(warm["arm"]["forearm_abd"]))), float(warm["error"]),
			float(pol["cur"]["pose"]["fingers"][ray]["fan"]),
			maxf(absf(float(pol["cur"]["pose"]["arm"]["wrist_flex"])), absf(float(pol["cur"]["pose"]["arm"]["wrist_dev"]))),
			maxf(absf(float(pol["cur"]["pose"]["arm"]["forearm_flex"])), absf(float(pol["cur"]["pose"]["arm"]["forearm_abd"]))),
			float(pol["cur"]["reach"]), int(pol["iters"])])
	quit()
