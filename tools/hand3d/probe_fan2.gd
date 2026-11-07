# The little finger's sideways target: how much of the answer is the fan and
# how much the wrist, and does a comfort polish push the wrist out?
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")
const IK := preload("res://ik.gd")


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
		var q := []
		if ray == "I":
			q.append(0.0)
		else:
			q += IK.shares_of(ray, p["fingers"][ray])
		q += ArmModel.shares_of(p["arm"])
		q = IK._project_chain(q, ray, true)
		var seed: Array = IK._chain_seed(ray, target, p)
		var comfort: Dictionary = IK._chain_run(ray, target, p, seed, true, true)
		print("%s warm  fan %+6.2f wrist %5.2f fore %5.2f err %.3f | comfort fan %+6.2f wrist %5.2f fore %5.2f err %.3f" % [
			ray,
			float(warm["angles"]["fan"]), maxf(absf(float(warm["arm"]["wrist_flex"])), absf(float(warm["arm"]["wrist_dev"]))),
			maxf(absf(float(warm["arm"]["forearm_flex"])), absf(float(warm["arm"]["forearm_abd"]))), float(warm["error"]),
			float(comfort["cur"]["pose"]["fingers"][ray]["fan"]),
			maxf(absf(float(comfort["cur"]["pose"]["arm"]["wrist_flex"])), absf(float(comfort["cur"]["pose"]["arm"]["wrist_dev"]))),
			maxf(absf(float(comfort["cur"]["pose"]["arm"]["forearm_flex"])), absf(float(comfort["cur"]["pose"]["arm"]["forearm_abd"]))),
			float(comfort["cur"]["reach"])])
	quit()
