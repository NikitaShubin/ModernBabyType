# Why does a far target stay far? Prints the analytic seed and the LM runs
# from the warm start and from the seed.
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")
const IK := preload("res://ik.gd")


func _init() -> void:
	var rest := HandModel.rest_pose()
	var pad := HandModel.finger_pad("II", HandModel.finger_fk("II", rest["fingers"]["II"]))
	for target in [Vector3(0, -80, -80), Vector3(150, -100, -50),
			Vector3(-100, -100, -100), Vector3(0, -80, 0)]:
		var seed := ArmModel.seed_hand(pad, target)
		var sf := ArmModel.frames(seed)
		var w: Vector3 = sf["wrist"]
		print("target %s" % str(target))
		print("  seed %s" % str(seed))
		print("  seed wrist %s |w| %.1f | pad %s err %.2f" % [str(w),
			(w - ArmModel.SHOULDER).length(),
			str((sf["r_wrist"] as Basis) * pad + w),
			((sf["r_wrist"] as Basis) * pad + w).distance_to(target)])
		var r0: Dictionary = IK.solve_chain("II", target, rest, {"arm": true})
		print("  warm err %.2f cost %.2f arm %s" % [float(r0["error"]),
			float(IK._cost(IK._chain_res("II",
				_shares(r0), target, true, rest)["r"])), str(r0["arm"])])
		var s2 := rest.duplicate(true)
		s2["arm"] = seed
		var r1: Dictionary = IK.solve_chain("II", target, s2, {"arm": true})
		print("  seed err %.2f cost %.2f arm %s" % [float(r1["error"]),
			float(IK._cost(IK._chain_res("II",
				_shares(r1), target, true, rest)["r"])), str(r1["arm"])])
	quit()


func _shares(r: Dictionary) -> Array:
	var q := []
	for v in r["shares"]:
		q.append(float(v))
	q.append(float(r["fan_share"]))
	for v in r["arm_shares"]:
		q.append(float(v))
	return q
