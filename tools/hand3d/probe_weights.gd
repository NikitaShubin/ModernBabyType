# A compact ladder for tuning the prior weights. Prints the level split and
# the residual for targets that should be answered by different joints.
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const IK := preload("res://ik.gd")


func _row(tag: String, ray: String, target: Vector3, rest: Dictionary) -> void:
	var r: Dictionary = IK.solve_chain(ray, target, rest, {"arm": true})
	var lev: Dictionary = r["levels"]
	var a: Dictionary = r["arm"]
	print("%-6s err %7.2f it %2d | finger %3.0f fan %3.0f wrist %3.0f pron %3.0f elbow %3.0f shoulder %3.0f | fl %4.0f dv %4.0f pr %4.0f el %4.0f tw %4.0f sf %4.0f sa %4.0f" % [
		tag, float(r["error"]), int(r["iterations"]),
		float(lev.get("finger", 0)), float(lev.get("fan", 0)),
		float(lev.get("wrist", 0)), float(lev.get("pronation", 0)),
		float(lev.get("elbow", 0)), float(lev.get("shoulder", 0)),
		float(a["wrist_flex"]), float(a["wrist_dev"]), float(a["pronation"]),
		float(a["elbow"]), float(a["shoulder_twist"]), float(a["shoulder_flex"]),
		float(a["shoulder_abd"])])


func _init() -> void:
	var rest := HandModel.rest_pose()
	var pad := HandModel.finger_pad("II", HandModel.finger_fk("II", rest["fingers"]["II"]))
	var out := (pad - Vector3.ZERO).normalized()
	_row("A arc-", "II", pad - out * 10.0, rest)
	_row("B palm3", "II", pad + Vector3(0, 0, -30), rest)
	_row("C palm6", "II", pad + Vector3(0, 0, -60), rest)
	_row("D wrist", "II", pad + Vector3(0, -60, 0), rest)
	_row("E near", "II", pad + Vector3(0, -160, 0), rest)
	_row("F far", "II", Vector3(0, -80, -80), rest)
	_row("G side", "II", Vector3(150, -100, -50), rest)
	_row("H opp", "II", Vector3(-100, -100, -100), rest)
	var tpad := HandModel.thumb_pad(HandModel.thumb_fk(0.0))
	_row("T1", "I", tpad + Vector3(0, 0, -30), rest)
	_row("T2", "I", tpad + Vector3(0, -60, 0), rest)
	_row("T3", "I", Vector3(120, -80, -80), rest)
	quit()
