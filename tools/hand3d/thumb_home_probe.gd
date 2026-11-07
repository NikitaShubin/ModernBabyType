# The thumb at the solved home arm pose: can its one coordinate f reach the
# space bar once the hand is placed for the fingers? Prints the arc and the
# best f for the target just left of the split.
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")
const Kbd3D := preload("res://kbd3d.gd")

const ROOT_X := -72.56


func _init() -> void:
	var arm := ArmModel.rest_arm()
	arm["wrist_flex"] = -20.0
	arm["wrist_dev"] = 0.625
	arm["pronation"] = -6.875
	arm["elbow_x"] = 0.625
	arm["elbow_y"] = 12.5
	arm["elbow_z"] = -35.0
	var xf := ArmModel.hand_transform(arm)
	var target := Vector3(0.0 - ROOT_X - 3.0, Kbd3D.row_y(4),
		Kbd3D.FACE_Z + 5.0)
	print("target ", target)
	var best := 1e9
	var best_f := 0.0
	for i in 41:
		var f := -1.0 + 0.05 * float(i)
		var pad: Vector3 = xf * HandModel.thumb_pad(HandModel.thumb_fk(f))
		var d := pad.distance_to(target)
		if d < best:
			best = d
			best_f = f
		if i % 4 == 0:
			print("  f %5.2f pad %s err %.2f" % [f, str(pad), d])
	print("best f %.2f err %.2f" % [best_f, best])
	quit(0)
