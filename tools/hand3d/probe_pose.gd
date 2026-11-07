# Prints every joint, bone end, thenar frame and thumb effort of the six baked
# states with six decimals. Its job is to prove that a refactor (the pose
# dictionary, static FK) left the approved geometry untouched: run it on the
# baseline snapshot and on the working tree, diff the output.
#   mbt-godot --headless --path /work/tools/hand3d --script res://probe_pose.gd
extends SceneTree

const HandModel := preload("res://hand_model.gd")

const STATES := [["curled_rest", 1.0, 0.0], ["curled_open", 1.0, -1.0],
	["curled_press", 1.0, 0.4], ["straight_rest", 0.0, 0.0],
	["straight_open", 0.0, -1.0], ["straight_press", 0.0, 0.4]]


func _init() -> void:
	for s in STATES:
		var m := HandModel.new(float(s[1]), float(s[2]))
		print("== ", s[0])
		var keys := m.joints.keys()
		keys.sort()
		for k in keys:
			print("%s %s" % [k, _v(m.joints[k])])
		for b in m.bones:
			print("bone %s %s %s" % [b["name"], _v(b["a"]), _v(b["b"])])
		print("thenar %s %s %s" % [_v(m._thenar_c), _v(m._thenar_ax[0]),
			_v(m._thenar_ax[1])])
		print("thumb %s" % str(m.thumb_angles()))
		var e := HandModel.thumb_effort(m.thumb_angles())
		print("effort %.4f %.4f %.4f" % [e["cmc"], e["mcp"], e["ip"]])
		print("nails %d skins %d knuckles %d" % [m.nails.size(), m._skins.size(),
			m._knuckles.size()])
	quit()


func _v(p: Vector3) -> String:
	return "%.6f %.6f %.6f" % [p.x, p.y, p.z]
