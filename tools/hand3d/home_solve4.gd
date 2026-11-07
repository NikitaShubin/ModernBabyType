# The home pose with the pads ON THE KEY FACES and their DEPTH left free.
#
# Why free depth: the four pads sit on four keys that are 20.76 mm deep, and the
# author asked for the fingers to rest "едва касаясь" the keys — not for each
# pad to stand on the key's centre. Fixing y forced the hand to a pose where
# the ring finger had to sink 3.3 mm into the key to bring the little finger
# onto its key (home_solve2.gd, worst 3.30 mm). Freeing y along the key removes
# that fight: the target is (key x, key face z), and the pad's own natural y
# stays wherever the finger puts it, as long as it is still over the key.
#
# The solver settles each digit to its own depth: solve to the key centre,
# move the target's y to where the pad actually landed, solve again. The
# residual is then measured in x and z only; |dy| beyond Y_FREE is penalised.
#
#   mbt-godot --headless --path /work/tools/hand3d --script res://home_solve4.gd
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")
const IK := preload("res://ik.gd")
const Kbd3D := preload("res://kbd3d.gd")

const ROOT_L := -72.51
const ROOT_R := 43.94
const HOME_LABELS := {
	"L": {"II": "а", "III": "в", "IV": "ы", "V": "ф"},
	"R": {"II": "о", "III": "л", "IV": "д", "V": "ж"},
}
const TOUCH := 0.3
const THUMB_X := 20.5
const THUMB_LIFT := 2.0
const ELBOW_GAP_MIN := 220.0
const THUMB_GAP_MIN := 18.0
const Y_FREE := 9.0          # half the home key's depth, mm
const W_GAP := 0.01          # score per mm^2 of missing elbow gap
const W_THUMB := 0.02        # score per mm^2 of missing thumb gap
const W_ABD := 0.02          # score per degree^2 below 18 degrees of splay
const W_Y := 0.1             # score per mm^2 of depth beyond the key
const WY0 := 20.0            # the search's depth gauge; fixed, see below
const PARAMS := ["wx", "wz", "abd", "dev", "flex", "pron"]
const SETTLE := 3


func _target(side: String, ray: String) -> Vector3:
	var sgn := -1.0 if side == "R" else 1.0
	var rx: float = ROOT_L if side == "L" else ROOT_R
	if ray == "I":
		var wx := -THUMB_X if side == "L" else THUMB_X
		return Vector3((wx - rx) * sgn, Kbd3D.row_y(4),
			Kbd3D.FACE_Z + THUMB_LIFT)
	var label: String = (HOME_LABELS[side] as Dictionary)[ray]
	var ks := Kbd3D.keys()
	var c := Kbd3D.centre(ks[Kbd3D.index_of(ks, label)])
	return Vector3((c.x - rx) * sgn, c.y, Kbd3D.FACE_Z + TOUCH)


func _arm(par: Dictionary) -> Dictionary:
	var a := ArmModel.rest_arm()
	var abd := deg_to_rad(float(par["abd"]))
	a["forearm_abd"] = float(par["abd"])
	a["forearm_flex"] = 0.0
	a["wrist_dev"] = float(par["dev"])
	a["wrist_flex"] = float(par["flex"])
	a["pronation"] = float(par["pron"])
	a["elbow_x"] = float(par["wx"]) - ArmModel.FOREARM_L * sin(abd)
	a["elbow_y"] = float(par["wy"]) + ArmModel.FOREARM_L \
		- ArmModel.FOREARM_L * cos(abd)
	a["elbow_z"] = float(par["wz"])
	return a


func _pad_world(side: String, ray: String, p: Dictionary) -> Vector3:
	var rx: float = ROOT_L if side == "L" else ROOT_R
	var xf := ArmModel.hand_transform(p.get("arm", {}))
	var local: Vector3
	if ray == "I":
		local = xf * HandModel.thumb_pad(HandModel.thumb_fk(
			HandModel.thumb_of_pose(p)))
	else:
		local = xf * HandModel.finger_pad(ray,
			HandModel.finger_fk(ray, p["fingers"][ray]))
	if side == "R":
		return Vector3(rx - local.x, local.y, local.z)
	return Vector3(rx + local.x, local.y, local.z)


func _opts(ray: String) -> Dictionary:
	var o := {"arm": false, "tuck": false, "clear_w": 0.0, "dir_w": 0.0}
	if ray == "I":
		o["thumb_dof"] = 4
	return o


# The key point the pad must meet: the key's own x and z, and the pad's depth.
func _key_point(side: String, ray: String, t: Vector3, pad: Vector3) -> Vector3:
	var rx: float = ROOT_L if side == "L" else ROOT_R
	var kx := rx + t.x if side == "L" else rx - t.x
	return Vector3(kx, pad.y, t.z)


func _side(side: String, arm: Dictionary) -> Dictionary:
	var p := HandModel.rest_pose()
	p["arm"] = arm.duplicate(true)
	p["thumb_f"] = 0.0
	p["thumb"] = HandModel.thumb_at(0.0)
	p["thumb_dof"] = 4
	var errs := {}
	var comps := {}
	var pads := {}
	var worst := 0.0
	for ray in ["II", "III", "IV", "V", "I"]:
		var t := _target(side, ray)
		var key_y := t.y
		var pad := Vector3.ZERO
		for it in SETTLE:
			var r: Dictionary = IK.solve_chain(ray, t, p, _opts(ray))
			p = r["pose"]
			pad = _pad_world(side, ray, p)
			var dy := pad.y - t.y
			if absf(dy) < 0.005:
				break
			t.y = pad.y
		var kp := _key_point(side, ray, t, pad)
		var ex := pad.x - kp.x
		var ez := pad.z - kp.z
		var e := sqrt(ex * ex + ez * ez)
		comps[ray] = {"ex": ex, "ez": ez, "dy": pad.y - key_y}
		pads[ray] = pad
		errs[ray] = e
		worst = maxf(worst, e)
	return {"worst": worst, "errs": errs, "comps": comps, "pads": pads, "pose": p}


func _score(par: Dictionary) -> Dictionary:
	var arm := _arm(par)
	var l := _side("L", arm)
	var r := _side("R", arm)
	var sum := 0.0
	var ypen := 0.0
	for side in [l, r]:
		for ray in ["II", "III", "IV", "V", "I"]:
			sum += float(side["errs"][ray]) * float(side["errs"][ray])
			var dy := absf(float(side["comps"][ray]["dy"]))
			ypen += W_Y * pow(maxf(0.0, dy - Y_FREE), 2.0)
	var abd := float(par["abd"])
	var gap := 116.45 + 2.0 * (ArmModel.FOREARM_L * sin(deg_to_rad(abd))
		- float(par["wx"]))
	var tgap: float = (l["pads"]["I"] as Vector3).distance_to(r["pads"]["I"])
	var pen := W_GAP * pow(maxf(0.0, ELBOW_GAP_MIN - gap), 2.0) \
		+ W_THUMB * pow(maxf(0.0, THUMB_GAP_MIN - tgap), 2.0) \
		+ W_ABD * pow(maxf(0.0, 18.0 - abd), 2.0)
	return {"score": sum + ypen + pen, "sum": sum, "ypen": ypen, "pen": pen,
		"worst": maxf(float(l["worst"]), float(r["worst"])), "l": l, "r": r,
		"gap": gap, "tgap": tgap, "arm": arm}


func _clamp(par: Dictionary) -> void:
	par["abd"] = clampf(float(par["abd"]), 0.0, 40.0)
	par["dev"] = clampf(float(par["dev"]), -35.0, 20.0)
	par["flex"] = clampf(float(par["flex"]), -70.0, 75.0)
	par["pron"] = clampf(float(par["pron"]), -85.0, 70.0)
	par["wx"] = clampf(float(par["wx"]), -60.0, 60.0)
	par["wy"] = clampf(float(par["wy"]), -60.0, 80.0)
	par["wz"] = clampf(float(par["wz"]), -70.0, 0.0)


func _report(tag: String, s: Dictionary, par: Dictionary) -> void:
	print("%-14s score %8.3f worst %5.2f sum %7.2f ypen %6.3f pen %6.2f gap %5.1f tgap %5.1f %s"
		% [tag, float(s["score"]), float(s["worst"]), float(s["sum"]),
		float(s["ypen"]), float(s["pen"]), float(s["gap"]), float(s["tgap"]),
		str(par)])
	var e: Dictionary = s["l"]["errs"]
	var c: Dictionary = s["l"]["comps"]
	print("   L err II %.2f III %.2f IV %.2f V %.2f I %.3f | dx %.2f %.2f %.2f %.2f | dz %.2f %.2f %.2f %.2f | dy %.2f %.2f %.2f %.2f"
		% [float(e["II"]), float(e["III"]), float(e["IV"]), float(e["V"]),
		float(e["I"]), float(c["II"]["ex"]), float(c["III"]["ex"]),
		float(c["IV"]["ex"]), float(c["V"]["ex"]), float(c["II"]["ez"]),
		float(c["III"]["ez"]), float(c["IV"]["ez"]), float(c["V"]["ez"]),
		float(c["II"]["dy"]), float(c["III"]["dy"]), float(c["IV"]["dy"]),
		float(c["V"]["dy"])])


func _init() -> void:
	var par := {"wx": 0.0, "wy": WY0, "wz": -44.0, "abd": 22.0,
		"dev": -20.0, "flex": -20.0, "pron": 0.0}
	var best := _score(par)
	_report("start", best, par)
	var step := 4.0
	for sweep in 40:
		var improved := false
		for j in PARAMS:
			var base := float(par[j])
			var best_v := base
			var best_s: Dictionary = best
			for dir in [-1.0, 1.0]:
				var v: float = base + float(dir) * step
				par[j] = v
				_clamp(par)
				if is_equal_approx(float(par[j]), base):
					continue
				var s := _score(par)
				if float(s["score"]) < float(best_s["score"]) - 0.0005:
					best_s = s
					best_v = float(par[j])
			par[j] = best_v
			if not is_equal_approx(best_v, base):
				improved = true
				best = best_s
		_report("sweep %d/%.1f" % [sweep, step], best, par)
		if not improved:
			step *= 0.5
			if step < 0.25:
				break
	# The depth gauge is a free translation: shift both wrists by the mean dy
	# of the four fingers so their depths straddle the key centre line.
	var dys := []
	for side in [best["l"], best["r"]]:
		for ray in ["II", "III", "IV", "V"]:
			dys.append(float(side["comps"][ray]["dy"]))
	var mean := 0.0
	for v in dys:
		mean += float(v)
	mean /= float(dys.size())
	par["wy"] = WY0 - mean
	var fin := _score(par)
	_report("FINAL", fin, par)
	print("  dy mean %.2f -> wy %.2f" % [mean, float(par["wy"])])
	print("  arm ", fin["arm"])
	for side in ["l", "r"]:
		print("  %s errs %s" % [side, str(fin[side]["errs"])])
		print("  %s comps %s" % [side, str(fin[side]["comps"])])
		print("  %s pads %s" % [side, str(fin[side]["pads"])])
	print("  L thumb %s" % str(HandModel.thumb_of_pose(fin["l"]["pose"])))
	print("  L fingers %s" % str(fin["l"]["pose"]["fingers"]))
	quit(0)
