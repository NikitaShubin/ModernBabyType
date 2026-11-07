# TEMP probe: find (space target, held abduction) pairs that still reach AND
# put the thumb's metacarpal out of the palm's silhouette.
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const HomePose := preload("res://home_pose.gd")
const ArmModel := preload("res://arm_model.gd")
const IK := preload("res://ik.gd")


func _init() -> void:
	var side := "L"
	var root := float(HomePose.HOME_ROOTS[side])
	var home: Dictionary = HomePose.build(side, root)
	var xf := ArmModel.hand_transform(home["arm"])
	var best := []
	for tz in [-67.0, -62.0, -57.0, -52.0]:
		for ty in [98.0, 104.0, 110.0]:
			for tx in [76.0, 80.0, 84.0, 88.0, 92.0]:
				for abd in [-15.18, -12.0, -9.0, -6.0, -3.0, 0.0, 3.0, 6.0]:
					var t := Vector3(tx, ty, tz)
					var b: Dictionary = home.duplicate(true)
					b["thumb_hold"] = {
						"twist": float(HomePose.THUMB_TWIST[side]),
						"cmc_abd": float(abd)}
					var r: Dictionary = IK.solve_chain("I", t, b,
						{"arm": false, "tuck": false, "clear_w": 0.0,
						"dir_w": 0.0, "thumb_dof": 4})
					var th := HandModel.thumb_of_pose(r["pose"])
					var fk := HandModel.thumb_fk(th)
					var mcp: Vector3 = fk["pts"][1]
					var tip: Vector3 = xf * (fk["pts"][3] as Vector3)
					if float(r["error"]) < 0.5:
						best.append([mcp.x, tz, ty, tx, abd, mcp.z,
							float(th["cmc_flex"]), float(th["mcp"]),
							float(th["ip"]), tip.z])
	best.sort_custom(func(a, b): return float(a[0]) > float(b[0]))
	print("reaching poses, best radial metacarpal first:")
	for i in mini(24, best.size()):
		var e: Array = best[i]
		print("mcp.x %5.1f  tz %5.1f ty %5.1f tx %5.1f  abd %6.1f  mcp.z %6.1f  flex %5.1f mcp %5.1f ip %5.1f  tipz %5.1f"
			% [e[0], e[1], e[2], e[3], e[4], e[5], e[6], e[7], e[8], e[9]])
	print("total reaching: ", best.size())
	quit()
