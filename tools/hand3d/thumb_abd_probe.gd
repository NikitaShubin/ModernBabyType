# TEMP probe: the home thumb with its column held at different abductions.
# Run: godot --headless --path tools/hand3d --script res://thumb_abd_probe.gd
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const HomePose := preload("res://home_pose.gd")
const ArmModel := preload("res://arm_model.gd")
const IK := preload("res://ik.gd")


func _init() -> void:
	for side in ["L", "R"]:
		var root := float(HomePose.HOME_ROOTS[side])
		var home: Dictionary = HomePose.build(side, root)
		var target: Vector3 = HomePose.target(side, "I", root)
		var xf := ArmModel.hand_transform(home["arm"])
		var t0 := HandModel.thumb_of_pose(home)
		var fk0 := HandModel.thumb_fk(t0)
		var p0: Vector3 = xf * HandModel.thumb_pad(fk0)
		print("=== %s target %s  home thumb %s" % [side, str(target), str(t0)])
		print("    home pad %s  err %.2f" % [str(p0), (p0 - target).length()])
		var ix: Vector3 = xf * HandModel.metacarpal_head("II")
		var vx: Vector3 = xf * HandModel.metacarpal_head("V")
		print("    index mcp %s  pinky mcp %s" % [str(ix), str(vx)])
		for abd in [-15.18, -10.0, -5.0, 0.0, 5.0, 10.0, 15.0, 20.0, 25.0, 30.0, 35.0]:
			var base: Dictionary = home.duplicate(true)
			var hold: Dictionary = {"twist": float(HomePose.THUMB_TWIST[side]),
				"cmc_abd": float(abd)}
			base["thumb_hold"] = hold
			var o := {"arm": false, "tuck": false, "clear_w": 0.0, "dir_w": 0.0,
				"thumb_dof": 4}
			var r: Dictionary = IK.solve_chain("I", target, base, o)
			var p: Dictionary = r["pose"]
			var th := HandModel.thumb_of_pose(p)
			var fk := HandModel.thumb_fk(th)
			var pts: PackedVector3Array = fk["pts"]
			var wp := []
			for v in pts:
				wp.append(xf * (v as Vector3))
			var pad: Vector3 = xf * HandModel.thumb_pad(fk)
			print("abd %6.2f -> flex %6.2f mcp %6.2f ip %6.2f err %5.2f"
				% [abd, float(th["cmc_flex"]), float(th["mcp"]), float(th["ip"]),
					(pad - target).length()])
			# same for the mirrored side: the geometry is identical locally
			print("          base %s mcp %s ip %s tip %s"
				% [str(wp[0]), str(wp[1]), str(wp[2]), str(wp[3])])
	quit()
