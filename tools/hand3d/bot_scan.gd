# The bottom row's price list, measured (#11 follow-up, 04.11.2026).
#
# The author's report: "Обе руки по-прежнему вообще не двигаются в сторону
# крайних точек, а сильно сгибает лучезапястный сустав, что должно быть
# труднее, чем движение предплечья". This probe presses each bottom-row key
# twice — with the approved hierarchy and with the bottom-row profile — and
# prints, per key: how far the WRIST travelled (the whole hand and forearm
# moving), how far the pressing pad travelled, the wrist deviation, the
# forearm swing, the elbow translation and the pinky's MCP angle (the curl).
#
#   mbt-godot --headless --path /work/tools/hand3d --script res://bot_scan.gd
extends SceneTree

const Kbd3D := preload("res://kbd3d.gd")
const IK := preload("res://ik.gd")
const ArmModel := preload("res://arm_model.gd")

# [name, weight overrides, finger prior]
const PROFILES := [
	["approved", {}, 0.05],
	["bottom row", {"elbow_x": 10.0, "elbow_y": 10.0, "forearm_abd": 10.0}, 2.0],
]

var v: Node
var done := false


func _init() -> void:
	v = load("res://board.tscn").instantiate()
	root.add_child(v)
	v.process_mode = Node.PROCESS_MODE_DISABLED


func _process(_dt: float) -> bool:
	if done:
		return true
	done = true
	var picks := []
	for i in v._keys.size():
		var s := String((v._keys[i] as Dictionary)["s"])
		var side := String(v._sim_key_side(i))
		if side == "" or not (Kbd3D.ROW_BOTTOM as Array).has(s):
			continue
		picks.append([i, s, side])
	for cfg in PROFILES:
		v._sim_bot_w = (cfg[1] as Dictionary).duplicate(true)
		v._sim_bot_prior = float(cfg[2])
		print("=== %s" % String(cfg[0]))
		for pick in picks:
			var i := int(pick[0])
			var s := String(pick[1])
			var side := String(pick[2])
			var rx := float(v._sim_rest_rx[side])
			var home: Dictionary = (v._sim_rest_home[side] as Dictionary).duplicate(true)
			var st: Dictionary = v._sim_stroke(side, i, home.duplicate(true), rx,
				v._foreign_rest(side))
			var pr: Dictionary = st["press"]
			var ray := String(Kbd3D.hand_finger(s, 0.0)[1])
			var a0: Dictionary = home["arm"]
			var a2: Dictionary = pr["arm"]
			var w0: Vector3 = ArmModel.frames(home["arm"])["wrist"]
			var w2: Vector3 = ArmModel.frames(pr["arm"])["wrist"]
			var p0: Vector3 = v._pad_of_pose(side, ray, home)
			var p2: Vector3 = v._pad_of_pose(side, ray, pr)
			var deep: Vector3 = st["deep"]
			var mcp := "-"
			if ray != "I":
				mcp = "%.0f" % float((pr["fingers"][ray] as Dictionary)["mcp"])
			print("  %-2s %-7s hand %5.1f mm | pad %5.1f | dev %+6.1f | abd %+6.1f | flex %+6.1f | elbow %+6.1f %+6.1f %+6.1f | mcp %4s | err %5.2f"
				% [side, s, (w2 - w0).length(), (p2 - p0).length(),
				float(a2["wrist_dev"]), float(a2["forearm_abd"]),
				float(a2["wrist_flex"]),
				float(a2["elbow_x"]) - float(a0["elbow_x"]),
				float(a2["elbow_y"]) - float(a0["elbow_y"]),
				float(a2["elbow_z"]) - float(a0["elbow_z"]),
				mcp, (p2 - deep).length()])
	quit()
	return true
