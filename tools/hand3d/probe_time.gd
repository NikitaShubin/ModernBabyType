# Times the hierarchical solve, because the viewer calls it on every drag and
# a comfort run is 90 iterations of an 11-variable Jacobian.
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const IK := preload("res://ik.gd")


func _init() -> void:
	var rest := HandModel.rest_pose()
	var pad := HandModel.finger_pad("II", HandModel.finger_fk("II", rest["fingers"]["II"]))
	var cases := [pad + Vector3(0, 0, -30), Vector3(0, -80, -80),
		Vector3(150, -100, -50), Vector3(-100, -100, -100)]
	for t in cases:
		var t0 := Time.get_ticks_usec()
		var r: Dictionary = IK.solve_chain("II", t, rest, {"arm": true})
		var dt := Time.get_ticks_usec() - t0
		print("target %s: %.1f ms err %.2f it %d" % [str(t), dt / 1000.0,
			float(r["error"]), int(r["iterations"])])
	# A drag is a sequence of small moves from the previous pose, which is the
	# warm path. Time that too.
	var pose := rest.duplicate(true)
	var t1 := Time.get_ticks_usec()
	for i in 30:
		var target := Vector3(0, -80, -80) + Vector3(float(i), 0, 0)
		pose = IK.solve_chain("II", target, pose, {"arm": true})["pose"]
	print("drag 30 steps: %.1f ms total, %.1f ms each" % [
		(Time.get_ticks_usec() - t1) / 1000.0, (Time.get_ticks_usec() - t1) / 30000.0])
	quit()
