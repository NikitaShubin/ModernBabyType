extends SceneTree

const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")
const HomePose := preload("res://home_pose.gd")


func _init() -> void:
	for side in ["L", "R"]:
		var root := -72.51 if side == "L" else 43.94
		var home: Dictionary = HomePose.build(side, float(root))
		print("=== %s root %.2f" % [side, root])
		var xf := ArmModel.hand_transform(home["arm"])
		for ray in ["II", "III", "IV", "V"]:
			var pad: Vector3 = xf * HandModel.finger_pad(ray,
				HandModel.finger_fk(ray, home["fingers"][ray]))
			var tgt: Vector3 = HomePose.target(side, ray, float(root))
			print("  %s pad %s target %s  dx %5.2f dy %5.2f dz %5.2f" % [
				ray, str(pad), str(tgt), pad.x - tgt.x, pad.y - tgt.y,
				pad.z - tgt.z])
		var tpad: Vector3 = xf * HandModel.thumb_pad(
			HandModel.thumb_fk(HandModel.thumb_of_pose(home)))
		var ttgt: Vector3 = HomePose.target(side, "I", float(root))
		print("  I  pad %s target %s  dx %5.2f dy %5.2f dz %5.2f" % [
			str(tpad), str(ttgt), tpad.x - ttgt.x, tpad.y - ttgt.y,
			tpad.z - ttgt.z])
	quit(0)
