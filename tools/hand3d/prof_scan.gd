# TEMP: profile matrix for the BASELINE table (#11 follow-up).
extends SceneTree

const Kbd3D := preload("res://kbd3d.gd")
const ArmModel := preload("res://arm_model.gd")

var v: Node
var done := false

const PROFILES := [
	["approved", {}, 0.05],
	["e10 p2.0", {"elbow_x": 10.0, "elbow_y": 10.0, "forearm_abd": 10.0}, 2.0],
	["e30 p2.0", {"elbow_x": 30.0, "elbow_y": 30.0, "forearm_abd": 10.0}, 2.0],
	["e5 p2.0", {"elbow_x": 5.0, "elbow_y": 5.0, "forearm_abd": 10.0}, 2.0],
	["e1000 p0.5", {"elbow_x": 1000.0, "elbow_y": 1000.0, "forearm_abd": 10.0}, 0.5],
	["e10 p0.5", {"elbow_x": 10.0, "elbow_y": 10.0, "forearm_abd": 10.0}, 0.5],
	["e10 p1.0", {"elbow_x": 10.0, "elbow_y": 10.0, "forearm_abd": 10.0}, 1.0],
	["e10 p3.0", {"elbow_x": 10.0, "elbow_y": 10.0, "forearm_abd": 10.0}, 3.0],
	["e10 p2.0 abd30", {"elbow_x": 10.0, "elbow_y": 10.0, "forearm_abd": 30.0}, 2.0],
]


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
		var line := "%-16s" % String(cfg[0])
		for pick in picks:
			var i := int(pick[0])
			var s := String(pick[1])
			var side := String(pick[2])
			var rx := float(v._sim_rest_rx[side])
			var home: Dictionary = (v._sim_rest_home[side] as Dictionary).duplicate(true)
			var pr: Dictionary = v._sim_stroke(side, i, home.duplicate(true), rx,
				v._foreign_rest(side))["press"]
			var ray := String(Kbd3D.hand_finger(s, 0.0)[1])
			var a0: Dictionary = home["arm"]
			var a2: Dictionary = pr["arm"]
			var w0: Vector3 = ArmModel.frames(a0)["wrist"]
			var w2: Vector3 = ArmModel.frames(a2)["wrist"]
			var mcp := "  -"
			if ray != "I":
				mcp = "%3.0f" % float((pr["fingers"][ray] as Dictionary)["mcp"])
			line += " | %s/%s %4.1fmm %+5.1f %s" % [side, s.left(3),
				(w2 - w0).length(), float(a2["wrist_dev"]), mcp]
		print(line)
	quit()
	return true
