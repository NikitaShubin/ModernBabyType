extends SceneTree

const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")


func _init() -> void:
	var p := HandModel.rest_pose()
	var xf := ArmModel.hand_transform(p["arm"])
	print("wrist origin %s" % str(xf.origin))
	for ray in ["II", "III", "IV", "V"]:
		var fk := HandModel.finger_fk(ray, p["fingers"][ray])
		var pad: Vector3 = xf * HandModel.finger_pad(ray, fk)
		var tip: Vector3 = xf * (fk["pts"][3] as Vector3)
		var mcp: Vector3 = xf * (fk["pts"][0] as Vector3)
		print("%s mcp (%6.1f %6.1f %6.1f) tip (%6.1f %6.1f %6.1f) pad (%6.1f %6.1f %6.1f)" % [
			ray, mcp.x, mcp.y, mcp.z, tip.x, tip.y, tip.z, pad.x, pad.y, pad.z])
	var tfk := HandModel.thumb_fk(0.0)
	var tpad: Vector3 = xf * HandModel.thumb_pad(tfk)
	var ttip: Vector3 = xf * (tfk["pts"][3] as Vector3)
	print("I  base (%6.1f %6.1f %6.1f) tip (%6.1f %6.1f %6.1f) pad (%6.1f %6.1f %6.1f)" % [
		(xf * (tfk["pts"][0] as Vector3)).x, (xf * (tfk["pts"][0] as Vector3)).y,
		(xf * (tfk["pts"][0] as Vector3)).z, ttip.x, ttip.y, ttip.z,
		tpad.x, tpad.y, tpad.z])
	quit(0)
