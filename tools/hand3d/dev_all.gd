# TEMP probe: every key's press-pose wrist deviation, before and after the
# #11 soft stop — which keys the rule actually touches, and by how much.
extends SceneTree

const ArmModel := preload("res://arm_model.gd")

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
	var rows := []
	for i in v._keys.size():
		var s := String((v._keys[i] as Dictionary)["s"])
		var side := String(v._sim_key_side(i))
		if side == "":
			continue
		var rx := float(v._sim_rest_rx[side])
		var home: Dictionary = (v._sim_rest_home[side] as Dictionary).duplicate(true)
		ArmModel.DEV_SOFT = 0.0
		var b: Dictionary = v._sim_stroke(side, i, home.duplicate(true), rx,
			v._foreign_rest(side))["press"]
		ArmModel.DEV_SOFT = 1.5
		var a: Dictionary = v._sim_stroke(side, i, home.duplicate(true), rx,
			v._foreign_rest(side))["press"]
		var ba: Dictionary = b["arm"]
		var aa: Dictionary = a["arm"]
		var dev0 := float(ba["wrist_dev"])
		var dev1 := float(aa["wrist_dev"])
		rows.append({"s": s, "side": side, "dev0": dev0, "dev1": dev1,
			"flex0": float(ba["wrist_flex"]), "flex1": float(aa["wrist_flex"]),
			"abd0": float(ba["forearm_abd"]), "abd1": float(aa["forearm_abd"]),
			"e0": float(ba["elbow_x"]), "e1": float(aa["elbow_x"]),
			"ex0": float(ba["wrist_dev"]) - (-10.0),
			"ex1": float(aa["wrist_dev"]) - (-10.0)})
	rows.sort_custom(func(x, y): return absf(float(y["ex0"])) > absf(float(x["ex0"])))
	for r in rows:
		var mark := "  " if absf(float(r["ex1"]) - float(r["ex0"])) < 0.05 else "->"
		print("%s %-2s %-7s %s dev %+6.1f -> %+6.1f  excess %+5.1f -> %+5.1f  flex %+6.1f -> %+6.1f  abd %+6.1f -> %+6.1f  ex %+6.1f -> %+6.1f"
			% [mark, String(r["side"]), String(r["s"]), " ", float(r["dev0"]),
			float(r["dev1"]), float(r["ex0"]), float(r["ex1"]),
			float(r["flex0"]), float(r["flex1"]), float(r["abd0"]),
			float(r["abd1"]), float(r["e0"]), float(r["e1"])])
	ArmModel.DEV_SOFT = 1.5
	quit()
	return true
