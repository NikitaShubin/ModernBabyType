# TEMP probe: the home thumb's geometry, digit by digit.
# Run: godot --headless --path tools/hand3d --script res://thumb_probe.gd
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const HomePose := preload("res://home_pose.gd")
const ArmModel := preload("res://arm_model.gd")


func _init() -> void:
	for side in ["L", "R"]:
		var root := float(HomePose.HOME_ROOTS[side])
		var p: Dictionary = HomePose.build(side, root)
		var th := HandModel.thumb_of_pose(p)
		var fk := HandModel.thumb_fk(th)
		var pts: PackedVector3Array = fk["pts"]
		print("---- side ", side, " root ", root)
		print("thumb angles ", str(th))
		print("base ", str(pts[0]), "  mcp ", str(pts[1]), "  ip ", str(pts[2]), "  tip ", str(pts[3]))
		print("d0 ", str(fk["dirs"][0]), " d1 ", str(fk["dirs"][1]), " d2 ", str(fk["dirs"][2]))
		var hm := HandModel.new(1.0, 0.0, p)
		# The palm field around the thumb's metacarpal: sample the SDF along
		# the segment base->mcp and report how deep inside the skin each
		# sample is (negative = inside).
		for i in 9:
			var t := float(i) / 8.0
			var q: Vector3 = pts[0].lerp(pts[1], t)
			print("  mc t %.2f  %s  field %.2f" % [t, str(q), hm.field(q)])
		# The same for the proximal and distal phalanges, to know which
		# segments are outside.
		for i in 5:
			var t := float(i) / 4.0
			var q: Vector3 = pts[1].lerp(pts[2], t)
			print("  pp t %.2f  %s  field %.2f" % [t, str(q), hm.field(q)])
		for i in 5:
			var t := float(i) / 4.0
			var q: Vector3 = pts[2].lerp(pts[3], t)
			print("  dp t %.2f  %s  field %.2f" % [t, str(q), hm.field(q)])
		# World pad and the space bar.
		var xf := ArmModel.hand_transform(p.get("arm", {}))
		var pad: Vector3 = xf * HandModel.thumb_pad(fk)
		var w: Vector3 = Vector3(root - pad.x, pad.y, pad.z) if side == "R" \
			else Vector3(root + pad.x, pad.y, pad.z)
		print("pad local ", str(pad), "  world ", str(w))
	quit()
