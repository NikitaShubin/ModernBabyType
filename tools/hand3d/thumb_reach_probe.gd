# How much of a far thumb press do the joints do, and how much does the elbow
# carry? The solver closes the last millimetre with an exact elbow nudge, so a
# reported "error 0.000" says nothing about the division of labour. This probe
# reports the pose BEFORE that nudge (`nudge: false`), the thumb alone with the
# arm frozen, and a grid of thumb angles to see what the thumb could do if the
# hand did not move. It also runs the comfort pass (priors polish) from the
# warm pose, to see whether the elbow's work can be handed back to the thumb.
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")
const IK := preload("res://ik.gd")
const Kbd3D := preload("res://kbd3d.gd")
const HomePose := preload("res://home_pose.gd")

const CLEAR_Z := Kbd3D.FACE_Z + 3.0
const ARM_KEYS := ["wrist_flex", "wrist_dev", "pronation", "forearm_flex",
	"forearm_abd", "elbow_x", "elbow_y", "elbow_z"]


func _pad(ray: String, p: Dictionary) -> Vector3:
	var xf := ArmModel.hand_transform(p.get("arm", {}))
	if ray == "I":
		return xf * HandModel.thumb_pad(HandModel.thumb_fk(
			HandModel.thumb_of_pose(p)))
	# A warm/comfort pose from _chain_run carries only the solved chain, not
	# the other fingers; the caller prints II only to see whether the hand
	# moved, so an absent II is the origin, not a crash.
	var fs: Dictionary = p.get("fingers", {})
	if not fs.has(ray):
		return Vector3.ZERO
	return xf * HandModel.finger_pad(ray,
		HandModel.finger_fk(ray, fs[ray]))


func _report(tag: String, ray: String, r: Dictionary, home: Dictionary,
		root_x: float) -> void:
	var p: Dictionary = r["pose"]
	var pad := _pad(ray, p)
	var world := Vector3(root_x - pad.x, pad.y, pad.z)
	var ii := _pad("II", p)
	var th: Dictionary = HandModel.thumb_of_pose(p)
	var arm: Dictionary = p["arm"]
	var dth := []
	for j in HandModel.THUMB_JOINTS:
		dth.append("%+.1f" % (float(th[j]) - float(HandModel.THUMB_REST[j])))
	var darm := []
	for j in ARM_KEYS:
		darm.append("%+.1f" % float(arm.get(j, 0.0)))
	printerr("  %-18s err %7.2f  pad %s  II %s" % [tag, float(r["error"]),
		str(pad), str(ii)])
	printerr("      dthumb %s" % " ".join(dth))
	printerr("      arm    %s" % " ".join(darm))


func _sweep(home: Dictionary, target: Vector3) -> void:
	var best := 1e9
	var best_t := {}
	var best_pad := Vector3.ZERO
	var a := -10.0
	while a <= 25.01:
		var b := -25.0
		while b <= 30.01:
			var m := -4.0
			while m <= 60.01:
				var i := -4.0
				while i <= 90.01:
					var t := {"cmc_flex": a, "cmc_abd": b, "mcp": m, "ip": i}
					var pad := HandModel.thumb_pad(HandModel.thumb_fk(t))
					var d := pad.distance_to(target)
					if d < best:
						best = d
						best_t = t
						best_pad = pad
					i += 10.0
				m += 8.0
			b += 5.0
		a += 5.0
	printerr("  thumb-only grid best %.2f mm at %s pad %s"
		% [best, str(best_t), str(best_pad)])


func _init() -> void:
	for side in ["R"]:
		var root_x := 43.94
		var home: Dictionary = HomePose.build(side, root_x)
		var ks := Kbd3D.keys()
		var w := Kbd3D.centre(ks[Kbd3D.index_of(ks, "глобус")])
		var local := Vector3(-(w.x - root_x), w.y, w.z - Kbd3D.TRAVEL)
		printerr("=== %s globe local %s (rest pad %s)"
			% [side, str(local), str(_pad("I", home))])
		var opts := {"arm": true, "thumb_dof": 4, "clear_z": CLEAR_Z,
			"clear_w": 100.0, "dir_w": 30.0}
		var with_nudge: Dictionary = IK.solve_chain("I", local, home, opts)
		_report("full+nudge", "I", with_nudge, home, root_x)
		var no_nudge_opts := opts.duplicate(true)
		no_nudge_opts["nudge"] = false
		var no_nudge: Dictionary = IK.solve_chain("I", local, home, no_nudge_opts)
		_report("full no-nudge", "I", no_nudge, home, root_x)
		var arm_frozen: Dictionary = IK.solve_chain("I", local, home,
			{"arm": false, "thumb_dof": 4, "clear_z": CLEAR_Z,
			"clear_w": 100.0, "dir_w": 30.0})
		_report("thumb alone", "I", arm_frozen, home, root_x)
		_sweep(home, local)
		# The warm run as the solver sees it, then a comfort pass from the
		# very pose it reached. The comfort run does not stop at the first
		# reach: it keeps lowering the priors with the reach held at zero.
		var q0 := IK.thumb_shares_of(HandModel.thumb_of_pose(home))
		q0 += ArmModel.shares_of(home["arm"])
		IK.thumb_dof = 4
		IK.clear_z = CLEAR_Z
		IK.clear_w = 100.0
		IK.dir_w = 30.0
		IK.clear_hx = -1.0
		var warm: Dictionary = IK._chain_run("I", local, home, q0, true, false)
		printerr("  warm  cost %.4f fit %.4f it %d" % [
			IK._cost(warm["cur"]["r"]), float(warm["cur"]["fit"]),
			int(warm["iters"])])
		_report("warm", "I", {"pose": warm["cur"]["pose"],
			"error": float(warm["cur"]["reach"])}, home, root_x)
		var com: Dictionary = IK._chain_run("I", local, home, warm["q"], true, true)
		printerr("  comf  cost %.4f fit %.4f it %d" % [
			IK._cost(com["cur"]["r"]), float(com["cur"]["fit"]),
			int(com["iters"])])
		_report("comfort", "I", {"pose": com["cur"]["pose"],
			"error": float(com["cur"]["reach"])}, home, root_x)
		IK.thumb_dof = 1
		IK.clear_z = -1e9
		IK.clear_w = 0.0
		IK.dir_w = 0.0
	quit(0)
