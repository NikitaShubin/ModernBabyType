# The home thumb: angles, joint positions and the pad, against its target.
# The question: why is the IP at 88 degrees (its stop), and how far is the pad
# from the space bar?
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")
const Kbd3D := preload("res://kbd3d.gd")
const HomePose := preload("res://home_pose.gd")

const ROOTS := {"L": -72.51, "R": 43.94}


func _init() -> void:
	for side in ["L", "R"]:
		var root_x: float = ROOTS[side]
		var home: Dictionary = HomePose.build(side, root_x)
		var xf := ArmModel.hand_transform(home["arm"])
		var th: Dictionary = HandModel.thumb_of_pose(home)
		var fk: Dictionary = HandModel.thumb_fk(th)
		var pts: PackedVector3Array = fk["pts"]
		var tgt: Vector3 = HomePose.target(side, "I", root_x)
		print("=== %s thumb %s" % [side, str(th)])
		for i in 4:
			var w: Vector3 = xf * pts[i]
			print("  joint %d %s" % [i, str(_w(w, side, root_x))])
		var pad: Vector3 = xf * HandModel.thumb_pad(fk)
		print("  pad %s target %s" % [str(_w(pad, side, root_x)),
			str(_w(tgt, side, root_x))])
		var mc: Vector3 = xf * HandModel.metacarpal_head("I")
		print("  mcp-head %s" % str(_w(mc, side, root_x)))
	quit(0)


func _w(v: Vector3, side: String, root_x: float) -> Vector3:
	var x := -v.x if side == "R" else v.x
	return Vector3(snappedf(root_x + x, 0.01), snappedf(v.y, 0.01),
		snappedf(v.z, 0.01))
