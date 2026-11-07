# The thumb's home pose in the HAND's own frame, where the joints' geometry can
# be read: where the CMC base sits, where the target is, and which way the
# thumb's own axes point. The world numbers alone hide the cause of the hook.
#
#   mbt-godot --headless --path /work/tools/hand3d --script res://thumb_local_probe.gd
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")
const IK := preload("res://ik.gd")
const Kbd3D := preload("res://kbd3d.gd")
const HomePose := preload("res://home_pose.gd")

const ROOTS := {"L": -72.51, "R": 43.94}


func _scan(side: String) -> void:
	var root_x: float = ROOTS[side]
	var home: Dictionary = HomePose.build(side, root_x)
	var xf := ArmModel.hand_transform(home["arm"])
	var inv := xf.affine_inverse()
	var tgt: Vector3 = HomePose.target(side, "I", root_x)
	var lt := inv * tgt
	print("=== %s  arm %s" % [side, str(home["arm"])])
	print("  xf origin %s  basis x %s y %s z %s" % [str(xf.origin),
		str(xf.basis.x), str(xf.basis.y), str(xf.basis.z)])
	print("  target local %s" % str(lt))
	var rest: Dictionary = HandModel.rest_pose()
	rest["arm"] = (home["arm"] as Dictionary).duplicate(true)
	for tag in ["rest", "home"]:
		var p: Dictionary = rest if tag == "rest" else home
		var th: Dictionary = HandModel.thumb_of_pose(p)
		var fk: Dictionary = HandModel.thumb_fk(th)
		var pts: PackedVector3Array = fk["pts"]
		print("  -- %s %s" % [tag, str(th)])
		for i in 4:
			print("     %d %s" % [i, str(pts[i])])
		print("     pad %s" % str(HandModel.thumb_pad(fk)))
		var d2: Vector3 = (fk["dirs"] as Array)[2]
		print("     dir2 %s  (local)" % str(d2))
	# The thumb's bone lengths, for scale.
	var rf: Dictionary = HandModel.thumb_fk(HandModel.thumb_at(0.0))
	var rp: PackedVector3Array = rf["pts"]
	print("  bone lengths %.2f %.2f %.2f" % [rp[0].distance_to(rp[1]),
		rp[1].distance_to(rp[2]), rp[2].distance_to(rp[3])])
	print("  base local %s" % str(rp[0]))


func _init() -> void:
	_scan("L")
	_scan("R")
	quit(0)
