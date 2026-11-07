# Reproduces the chain drag of ik_test and prints, step by step, which joint
# took the largest share of its own range and what every joint did.
#   mbt-godot --headless --path /work/tools/hand3d --script res://drag_probe.gd
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")
const IK := preload("res://ik.gd")

const JOINTS := ["wrist_flex", "wrist_dev", "pronation", "forearm_flex",
	"forearm_abd", "elbow_x", "elbow_y", "elbow_z"]


func _init() -> void:
	var pose := HandModel.rest_pose()
	var far := HandModel.rest_pose()
	far["arm"]["forearm_abd"] = 35.0
	far["arm"]["forearm_flex"] = -25.0
	var start := _pad_of("II", pose)
	var end := _pad_of("II", far)
	var prev: Dictionary = pose["arm"]
	print("start ", str(start), " end ", str(end))
	for i in 25:
		var u := float(i + 1) / 25.0
		var r := IK.solve_chain("II", start.lerp(end, u), pose, {"arm": true})
		pose = r["pose"]
		var a: Dictionary = pose["arm"]
		var line := "%2d u %.2f err %.2f" % [i, u, float(r["error"])]
		var worst := 0.0
		var worst_j := ""
		for j in JOINTS:
			var lo := 0.0
			var hi := 1.0
			if ArmModel.ROM.has(j):
				lo = float(ArmModel.ROM[j][0])
				hi = float(ArmModel.ROM[j][1])
			elif j.begins_with("elbow"):
				lo = -ArmModel.ELBOW_RANGE
				hi = ArmModel.ELBOW_RANGE
			var d := absf(float(a[j]) - float(prev[j])) / maxf(hi - lo, 1e-9) * 100.0
			line += " | %s %+.1f (%+.1f%%)" % [j.substr(0, 6), float(a[j]), d]
			if d > worst:
				worst = d
				worst_j = j
		line += "  >> %s %.1f%%" % [worst_j, worst]
		print(line)
		prev = a
	quit(0)


func _pad_of(ray: String, p: Dictionary) -> Vector3:
	var pad := HandModel.finger_pad(ray, HandModel.finger_fk(ray, p["fingers"][ray]))
	return ArmModel.hand_transform(p.get("arm", {})) * pad
