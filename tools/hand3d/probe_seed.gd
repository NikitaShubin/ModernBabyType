# Checks that seed_hand() aims the pad at the target from a reachable wrist,
# and prints the pose it starts from.
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")


func _init() -> void:
	var rest := HandModel.rest_pose()
	var pad := HandModel.finger_pad("II", HandModel.finger_fk("II", rest["fingers"]["II"]))
	print("rest pad II ", pad)
	for d in [Vector3(0, 0, 0), Vector3(0, 0, -30), Vector3(0, 0, -80),
			Vector3(0, 0, -160), Vector3(0, 60, 0), Vector3(60, 0, 0),
			Vector3(-60, 0, 0), Vector3(0, -80, 0), Vector3(0, -80, -80),
			Vector3(150, -100, -50), Vector3(0, 0, -260)]:
		var target: Vector3 = pad + d
		var s := ArmModel.seed_hand(pad, target)
		var f := ArmModel.frames(s)
		var w: Vector3 = f["wrist"]
		var aim: Vector3 = (f["r_wrist"] * pad).normalized()
		var want: Vector3 = (target - w).normalized()
		var got: Vector3 = w + aim * pad.length()
		print("d %s wrist %s |pad err %.2f dir err %.3f | %s" % [str(d),
			str(w), got.distance_to(target), rad_to_deg(aim.angle_to(want)),
			str(s)])
	quit()
