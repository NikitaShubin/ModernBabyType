# Why does a target below the elbow stop a fraction of a millimetre short?
# Solves the same target and prints the last iterations of the solver.
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")
const IK := preload("res://ik.gd")


func _init() -> void:
	var rest := HandModel.rest_pose()
	for t in [Vector3(0, -300, 0), Vector3(0, 300, 0), Vector3(0, -260, 0)]:
		var r: Dictionary = IK.solve_chain("II", t, rest, {"arm": true})
		var a: Dictionary = r["arm"]
		print("%s err %.3f it %d elbow %.1f %.1f %.1f | %s" % [
			str(t), float(r["error"]), int(r["iterations"]),
			float(a["elbow_x"]), float(a["elbow_y"]), float(a["elbow_z"]),
			_lev(r)])
		var tr: Array = r["trace"]
		for i in range(maxi(0, tr.size() - 5), tr.size()):
			print("   it %d reach %f lam %f step %f ok %s" % [
				int(tr[i][0]), float(tr[i][1]), float(tr[i][2]),
				float(tr[i][3]), str(tr[i][4])])
	quit()


func _lev(r: Dictionary) -> String:
	var l: Dictionary = r["levels"]
	return "finger %.0f fan %.0f wrist %.0f pron %.0f fore %.0f elbow %.0f" % [
		float(l["finger"]), float(l["fan"]), float(l["wrist"]),
		float(l["pronation"]), float(l["forearm"]), float(l["elbow"])]
