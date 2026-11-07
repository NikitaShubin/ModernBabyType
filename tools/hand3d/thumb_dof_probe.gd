# The thumb's four independent joints: does the dictionary form reproduce the
# old one-coordinate arc, and can the four joints reach a space-bar target at
# the home arm pose? Pure arithmetic, headless.
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")
const Kbd3D := preload("res://kbd3d.gd")

const ROOT_X := -72.56


func _init() -> void:
	print("legacy arc vs dictionary form:")
	for f in [-1.0, -0.4, 0.0, 0.4, 1.0]:
		var a := HandModel.thumb_at(f)
		var p1 := HandModel.thumb_pad(HandModel.thumb_fk(f))
		var p2 := HandModel.thumb_pad(HandModel.thumb_fk(a))
		print("  f %5.2f  delta %.9f  pad %s" % [f, p1.distance_to(p2), str(p1)])

	var arm := ArmModel.rest_arm()
	arm["wrist_flex"] = -20.0
	arm["wrist_dev"] = 0.625
	arm["pronation"] = -6.875
	arm["elbow_x"] = 0.625
	arm["elbow_y"] = 12.5
	arm["elbow_z"] = -35.0
	var xf := ArmModel.hand_transform(arm)
	var targets := {
		"split": Vector3(0.0 - ROOT_X - 3.0, Kbd3D.row_y(4),
			Kbd3D.FACE_Z + 5.0),
		"half": Vector3(-23.0 - ROOT_X, Kbd3D.row_y(4),
			Kbd3D.FACE_Z + 5.0),
	}
	for name in targets:
		var target: Vector3 = targets[name]
		var best := []
		for a1 in 9:
			for a2 in 9:
				for a3 in 9:
					for a4 in 9:
						var d := {}
						for i in HandModel.THUMB_JOINTS.size():
							var j: String = HandModel.THUMB_JOINTS[i]
							var rom: Array = HandModel.THUMB_ROM[j]
							var v: Array = [a1, a2, a3, a4]
							d[j] = float(rom[0]) + float(v[i]) / 8.0 \
								* (float(rom[1]) - float(rom[0]))
						var pad: Vector3 = xf * HandModel.thumb_pad(
							HandModel.thumb_fk(d))
						var e := pad.distance_to(target)
						best.append([e, d.duplicate(true), pad])
		best.sort_custom(func(x, y): return float(x[0]) < float(y[0]))
		print("target %s %s" % [name, str(target)])
		for i in 4:
			var row: Array = best[i]
			print("  err %.2f  angles %s  pad %s" % [float(row[0]),
				str(row[1]), str(row[2])])
	quit(0)
