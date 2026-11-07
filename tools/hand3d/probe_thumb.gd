# Prints where the thumb's three joints land along its one coordinate f.
# Headless:
#   mbt-godot --headless --path /work/tools/hand3d --script res://probe_thumb.gd
#
# Two things this exists for (the author, 27.10.2026):
#   · every one of CMC, MCP and IP has to MOVE between the states — a joint
#     that stays put prints 0.0 mm;
#   · the joints bend TOGETHER: the share of its own range each one has
#     spent ("effort") must be the same for all three. A pose with the base
#     at 10% and the tip at 90% is the one the author called unnatural.
extends SceneTree

const HandModel := preload("res://hand_model.gd")

const STATES := [["rest", "rest"], ["open", "open"], ["press", "press"], ["limit", 1.0]]


func _init() -> void:
	var seen := {}
	var bad := 0
	for s in STATES:
		var f: float = HandModel.POSE_THUMBS[s[1]] if typeof(s[1]) == TYPE_STRING else float(s[1])
		var t := HandModel.thumb_at(f)
		var m := HandModel.new(1.0, f)
		var a: Dictionary = m.thumb_angles()
		var e := HandModel.thumb_effort(t)
		var base: Vector3 = m.joints["I_BASE"]
		var mcp: Vector3 = m.joints["I_MCP"]
		var ip: Vector3 = m.joints["I_IP"]
		var tip: Vector3 = m.joints["I_TIP"]
		print("%s: f %+.2f   cmc %.1f/%.1f   mcp %.1f   ip %.1f" % [s[0], f,
			float(a["cmc_flex"]), float(a["cmc_abd"]), float(a["mcp"]), float(a["ip"])])
		print("   effort  CMC %.1f%%   MCP %.1f%%   IP %.1f%%" % [
			float(e["cmc"]), float(e["mcp"]), float(e["ip"])])
		print("   MCP %s  IP %s  TIP %s" % [str(mcp), str(ip), str(tip)])
		print("   MC head from base: %.1f mm   column length: %.1f mm" % [
			(mcp - base).length(), (mcp - base).length() + (ip - mcp).length() + (tip - ip).length()])
		# The whole premise: one f, one share for each joint.
		if absf(float(e["cmc"]) - float(e["mcp"])) > 0.01 \
				or absf(float(e["mcp"]) - float(e["ip"])) > 0.01:
			print("   !! joints are NOT coordinated at f %+.2f" % f)
			bad += 1
		seen[s[0]] = {"mcp": mcp, "ip": ip, "tip": tip}

	# How much each joint travels between the states — the whole point.
	for pair in [["rest", "open"], ["open", "press"], ["rest", "press"]]:
		var a: Dictionary = seen[pair[0]]
		var b: Dictionary = seen[pair[1]]
		print("%s -> %s:  MCP moved %.1f mm   IP moved %.1f mm   tip moved %.1f mm" % [
			pair[0], pair[1],
			(a["mcp"] as Vector3).distance_to(b["mcp"]),
			(a["ip"] as Vector3).distance_to(b["ip"]),
			(a["tip"] as Vector3).distance_to(b["tip"])])
	print("coordinated: %s" % ("NO" if bad > 0 else "yes, all joints share one f"))
	quit()
