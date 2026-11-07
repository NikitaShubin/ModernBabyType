# Coordinate descent for the typing home placement: four fingers on their
# home keys and the thumb over its side of the space bar.
#
# The arm has eight coordinates (five rotations, three elbow translations).
# For a candidate arm every digit solves independently with the arm frozen
# (no tuck: a home pose must not move one finger behind another's back). The
# thumb is the same four-joint chain the board viewer uses, and it is solved
# by the same energy rule; its target is the point of its own space-bar half
# nearest the split, which is where a resting thumb actually sits.
#
# The score is the worst pad error; the search walks one coordinate at a time,
# halves the step when a sweep finds nothing better, and prints the trajectory.
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")
const IK := preload("res://ik.gd")
const Kbd3D := preload("res://kbd3d.gd")

const HOVER := 12.0
const THUMB_HOVER := 5.0
const CLEAR_Z := Kbd3D.FACE_Z + 3.0
const ROOT_X := -72.56
const RAYS := ["I", "II", "III", "IV", "V"]
const JOINTS := ["wrist_flex", "wrist_dev", "pronation",
	"forearm_flex", "forearm_abd", "elbow_x", "elbow_y", "elbow_z"]


func _pad(p: Dictionary, ray: String) -> Vector3:
	var xf := ArmModel.hand_transform(p.get("arm", {}))
	if ray == "I":
		return xf * HandModel.thumb_pad(HandModel.thumb_fk(
			HandModel.thumb_of_pose(p)))
	return xf * HandModel.finger_pad(ray,
		HandModel.finger_fk(ray, p["fingers"][ray]))


func _targets() -> Dictionary:
	var ks := Kbd3D.keys()
	var out := {}
	for ray in ["II", "III", "IV", "V"]:
		var label: String = {"II": "а", "III": "в", "IV": "ы", "V": "ф"}[ray]
		var c := Kbd3D.centre(ks[Kbd3D.index_of(ks, label)])
		out[ray] = Vector3(c.x - ROOT_X, c.y, Kbd3D.FACE_Z + HOVER)
	# The thumb hovers over the inner edge of its own half: the left thumb
	# just left of the split, the right one just right of it (the mirrored
	# target is computed by the caller of the right-hand run).
	out["I"] = Vector3(-3.0 - ROOT_X, Kbd3D.row_y(4),
		Kbd3D.FACE_Z + THUMB_HOVER)
	return out


func _home_base(arm: Dictionary) -> Dictionary:
	var p := HandModel.rest_pose()
	p["arm"] = arm.duplicate(true)
	p["thumb_f"] = 0.0
	p["thumb"] = HandModel.thumb_at(0.0)
	p["thumb_dof"] = 4
	return p


func _score(targets: Dictionary, arm: Dictionary) -> Dictionary:
	var p := _home_base(arm)
	for ray in RAYS:
		var opts := {"arm": false, "tuck": false, "clear_z": CLEAR_Z,
			"clear_w": 100.0, "dir_w": 0.0}
		if ray == "I":
			opts["thumb_dof"] = 4
		var r: Dictionary = IK.solve_chain(ray, targets[ray], p, opts)
		p = r["pose"]
	var worst := 0.0
	var sum := 0.0
	var errs := {}
	var axes := {}
	for ray in RAYS:
		var e: Vector3 = targets[ray] - _pad(p, ray)
		errs[ray] = e.length()
		axes[ray] = e
		worst = maxf(worst, e.length())
		sum += e.length_squared()
	return {"worst": worst, "sum": sum, "errs": errs, "axes": axes,
		"pose": p}


func _init() -> void:
	var targets := _targets()
	var arm := ArmModel.rest_arm()
	arm["wrist_flex"] = -20.0
	arm["elbow_y"] = 15.0
	arm["elbow_z"] = -35.0
	var best := _score(targets, arm)
	print("start worst %.2f  %s" % [float(best["worst"]), str(best["errs"])])
	var step := 10.0
	for sweep in 12:
		var improved := false
		for j in JOINTS:
			var base := float(arm[j])
			var best_v := base
			var best_s: Dictionary = best
			for dir in [-1.0, 1.0]:
				var v: float = base + float(dir) * step
				if j.begins_with("elbow_"):
					v = clampf(v, -ArmModel.ELBOW_RANGE, ArmModel.ELBOW_RANGE)
				else:
					var rom: Array = ArmModel.ROM[j]
					v = clampf(v, float(rom[0]), float(rom[1]))
				if is_equal_approx(v, base):
					continue
				arm[j] = v
				var s := _score(targets, arm)
				if float(s["worst"]) < float(best_s["worst"]) - 0.001:
					best_s = s
					best_v = v
			arm[j] = best_v
			if best_v != base:
				improved = true
				best = best_s
		print("sweep %2d step %.1f worst %.3f  arm %s" % [sweep, step,
			float(best["worst"]), str(arm)])
		print("   errs ", best["errs"])
		if not improved:
			step *= 0.5
			if step < 0.5:
				break
	print("BEST worst %.3f sum %.2f" % [float(best["worst"]),
		float(best["sum"])])
	for ray in RAYS:
		print("  ", ray, " err ", best["errs"][ray], " axes ", best["axes"][ray])
	print("  arm ", best["pose"]["arm"])
	print("  thumb ", HandModel.thumb_of_pose(best["pose"]))
	print("  fingers ", best["pose"]["fingers"])
	quit(0)
