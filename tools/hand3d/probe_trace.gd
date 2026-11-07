# Prints the LM trace for one far target, to see where the elbow gets stuck.
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const IK := preload("res://ik.gd")


func _init() -> void:
	var rest := HandModel.rest_pose()
	var target := Vector3(0, -80, -80)
	var r: Dictionary = IK.solve_chain("II", target, rest, {"arm": true})
	print("err %.2f it %d" % [float(r["error"]), int(r["iterations"])])
	print("arm ", r["arm"])
	var tr: Array = r["trace"]
	for row in tr:
		print("  it %2d reach %7.2f lam %10.4f step %6.3f %s" % [int(row[0]),
			float(row[1]), float(row[2]), float(row[3]), "ok" if bool(row[4]) else ""])
	quit()
