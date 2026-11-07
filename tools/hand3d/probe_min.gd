# Checks whether the pose the LM stops at is really a local minimum: evaluates
# the cost for small moves of every variable.
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")
const IK := preload("res://ik.gd")


func _init() -> void:
	var rest := HandModel.rest_pose()
	var target := Vector3(0, -80, -80)
	var r: Dictionary = IK.solve_chain("II", target, rest, {"arm": true})
	print("err %.2f" % float(r["error"]))
	var sh: Array = r["shares"]
	var q := [float(sh[0]), float(sh[1]), float(sh[2]), float(r["fan_share"])]
	for v in r["arm_shares"]:
		q.append(float(v))
	var base: Dictionary = IK._chain_res("II", q, target, true, rest)
	var c0: float = IK._cost(base["r"])
	print("cost %.3f reach %.3f q %s" % [c0, float(base["reach"]), str(q)])
	var cols: Array = IK._chain_jacobian("II", q, target, true, rest)
	var g: Array = IK._gradient(cols, base["r"])
	var names := ["mcp", "pip", "dip", "fan", "wflex", "wdev", "pron", "elbow",
		"twist", "shflex", "shabd"]
	for i in q.size():
		var qq: Array = q.duplicate()
		qq[i] = float(qq[i]) - 0.05
		var lo: Dictionary = IK._chain_res("II", qq, target, true, rest)
		var qp: Array = q.duplicate()
		qp[i] = float(qp[i]) + 0.05
		var hi: Dictionary = IK._chain_res("II", qp, target, true, rest)
		print("%-7s q %6.3f  grad %9.2f  cost -0.05 %9.2f  +0.05 %9.2f  reach %6.2f / %6.2f" % [
			names[i], float(q[i]), float(g[i]), IK._cost(lo["r"]), IK._cost(hi["r"]),
			float(lo["reach"]), float(hi["reach"])])
	quit()
