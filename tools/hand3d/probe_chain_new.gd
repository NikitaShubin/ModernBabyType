# Prints what the hierarchical solver does on a ladder of targets, so the
# weights can be judged before they are frozen in tests.
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")
const IK := preload("res://ik.gd")


func _report(ray: String, target: Vector3, rest: Dictionary) -> void:
	var r: Dictionary = IK.solve_chain(ray, target, rest, {"arm": true})
	var lev: Dictionary = r["levels"]
	var a: Dictionary = r["arm"]
	var f: Dictionary = IK.solve_chain(ray, target, rest, {"arm": false})
	print("  %s err %6.2f it %2d | finger %3.0f fan %3.0f wrist %3.0f pron %3.0f fore %3.0f | flex %.0f dev %.0f pron %.0f ff %.0f fa %.0f | alone %6.2f" % [
		"ok " if float(r["error"]) <= 0.05 else "MISS", float(r["error"]),
		int(r["iterations"]),
		float(lev.get("finger", 0)), float(lev.get("fan", 0)),
		float(lev.get("wrist", 0)), float(lev.get("pronation", 0)),
		float(lev.get("forearm", 0)),
		float(a["wrist_flex"]), float(a["wrist_dev"]), float(a["pronation"]),
		float(a["forearm_flex"]), float(a["forearm_abd"]), float(f["error"])])


func _init() -> void:
	var rest := HandModel.rest_pose()
	var pad := HandModel.finger_pad("II", HandModel.finger_fk("II", rest["fingers"]["II"]))
	var wrist := Vector3.ZERO
	var out := (pad - wrist).normalized()
	print("rest pad II %s  out %s" % [str(pad), str(out)])
	print("== along the finger, outward from the pad")
	for d in [0.0, 10.0, 30.0, 60.0, 100.0, 150.0, 200.0]:
		print(" d %5.1f" % d)
		_report("II", pad + out * d, rest)
	print("== along the finger, inward (toward the wrist)")
	for d in [10.0, 30.0, 60.0, 100.0]:
		print(" d %5.1f" % d)
		_report("II", pad - out * d, rest)
	print("== toward the palm (-z), 30..150")
	for d in [10.0, 30.0, 60.0, 100.0, 150.0]:
		print(" d %5.1f" % d)
		_report("II", pad + Vector3(0, 0, -d), rest)
	print("== sideways (x), 30..150")
	for d in [30.0, 60.0, 100.0, 150.0]:
		print(" +x %5.1f" % d)
		_report("II", pad + Vector3(d, 0, 0), rest)
		print(" -x %5.1f" % d)
		_report("II", pad + Vector3(-d, 0, 0), rest)
	print("== back toward the elbow (-y)")
	for d in [30.0, 80.0, 140.0, 200.0]:
		print(" d %5.1f" % d)
		_report("II", pad + Vector3(0, -d, 0), rest)
	print("== thumb")
	var tpad := HandModel.thumb_pad(HandModel.thumb_fk(0.0))
	for d in [Vector3(0, 0, 0), Vector3(0, 0, -30), Vector3(60, 0, 0),
			Vector3(0, -60, 0), Vector3(120, -80, -80), Vector3(0, 120, 0)]:
		print(" d %s" % str(d))
		_report("I", tpad + d, rest)
	quit()
