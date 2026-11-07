# The thumb's pad path in the hand's own frame: where the pad goes as f runs
# from the far open end (-1) to the far press end (+1). The key plane is at
# z = -70, so the z column says how much of a press the thumb itself can give.
#   mbt-godot --headless --path /work/tools/hand3d --script res://thumb_path.gd
extends SceneTree

const HandModel := preload("res://hand_model.gd")


func _init() -> void:
	for f in [-1.0, -0.75, -0.5, -0.25, 0.0, 0.25, 0.5, 0.75, 1.0]:
		var p := HandModel.thumb_pad(HandModel.thumb_fk(float(f)))
		var a := HandModel.thumb_at(float(f))
		print("f %5.2f  pad (%.2f, %.2f, %.2f)  cmc_flex %.1f cmc_abd %.1f mcp %.1f ip %.1f" % [
			float(f), p.x, p.y, p.z, float(a["cmc_flex"]), float(a["cmc_abd"]),
			float(a["mcp"]), float(a["ip"])])
	var rest := HandModel.rest_pose()
	for ray in ["II", "III", "V"]:
		var q := HandModel.finger_pad(ray, HandModel.finger_fk(ray, rest["fingers"][ray]))
		print("%s rest pad (%.2f, %.2f, %.2f)" % [ray, q.x, q.y, q.z])
	quit(0)
