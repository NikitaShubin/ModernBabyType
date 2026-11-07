# The home pose search — stage three: the DIAGONAL.
#
# Stage two (home_solve6.gd) stalled in a local valley at splay +1 deg and
# palm tilt +4.4: plain coordinate descent cannot cross the ridge where the
# wrist moves OUTBOARD while the hand's own deviation UNWINDS towards zero —
# any single-coordinate step first costs five pads × shift² before the
# splay penalty starts paying. So this stage walks that diagonal itself:
#
#   1. a row of hand-picked CORNERS measures the real sensitivity (how the
#      pads, the hand axis and the palm normal answer when dev unwinds and
#      wx opens up);
#   2. a dev × pron × abd lattice runs with wx re-centred BY MEASUREMENT:
#      one eval reads the mean inboard miss ex of the four finger pads and
#      a second eval applies wx -= mean_ex (the pads as a body ride with
#      the wrist; the finger chains absorb the rest);
#   3. the winner is polished with the same bounded descent as before.
#
# The objective keeps stage two's targets: the hand axis leans OUT at least
# SPLAY_MIN (this stage asks 15 — the author wants the hands splayed, not
# just the forearms), the palm tilts towards the centre (TILT_TARGET), the
# elbow gap holds 220 mm, the thumb pads stay >= 18 mm apart, and every pad
# meets its key.
#
#   mbt-godot --headless --path /work/tools/hand3d --script res://home_solve7.gd
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
const THUMB_X := 23.0
const THUMB_LIFT := 2.0
const ELBOW_GAP_MIN := 220.0
const THUMB_GAP_MIN := 18.0
const Y_FREE := 9.0
const W_GAP := 0.01
const W_THUMB := 0.02
const W_ABD := 0.02
const W_Y := 0.1
const WY0 := 20.0
# The hand axis OUT lean that a flat board allows is bought by ulnar
# deviation right up to the ROM wall (the stage-three lattice measured
# d(splay)/d(dev) ~ -0.9: unwinding dev towards 0 turns the axis INBOARD).
# 15 degrees of lean needs ~35 deg of ulnar offset — off the healthy path —
# so this stage does NOT chase the axis: it only refuses to let it collapse
# INBOARD (the band towards 0), and puts the splayed look the author wants
# into the palm's roll instead: the palms tilt towards the centre (the
# "holding a ball" look) and the hands visibly form the V seen from above.
const W_SPLAY := 0.08
const W_STOP := 0.02
const TILT_TARGET := 14.0
const W_TILT := 0.06
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
	return {"worst": worst, "errs": errs, "comps": comps, "pads": pads,
		"pose": p}


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
	var tgap: float = (l["pads"]["I"] as Vector3).distance_to(
		(r["pads"]["I"] as Vector3))
	var xf := ArmModel.hand_transform(arm)
	var d := (xf.basis as Basis) * Vector3(0, 1, 0)
	var splay := rad_to_deg(atan2(-d.x, d.y))
	var n := (xf.basis as Basis) * Vector3(0, 0, -1)
	var tilt := rad_to_deg(atan2(n.x, -n.z))
	var stop := absf(float(par["dev"]))
	var pen := W_GAP * pow(maxf(0.0, ELBOW_GAP_MIN - gap), 2.0) \
		+ W_THUMB * pow(maxf(0.0, THUMB_GAP_MIN - tgap), 2.0) \
		+ W_ABD * pow(maxf(0.0, 18.0 - abd), 2.0) \
		+ W_SPLAY * pow(maxf(0.0, -splay), 2.0) \
		+ W_TILT * pow(maxf(0.0, TILT_TARGET - tilt), 2.0) \
		+ W_STOP * pow(maxf(0.0, stop - 30.0), 2.0)
	return {"score": sum + ypen + pen, "sum": sum, "ypen": ypen, "pen": pen,
		"worst": maxf(float(l["worst"]), float(r["worst"])), "l": l, "r": r,
		"gap": gap, "tgap": tgap, "arm": arm, "splay": splay, "tilt": tilt}


# The mean inboard miss ex of the four finger pads of ONE side, in the
# hand's own frame: the pads ride with the wrist, so the whole hand is
# translated by this much to centre the rest.
func _mean_ex(s: Dictionary) -> float:
	var m := 0.0
	for ray in ["II", "III", "IV", "V"]:
		m += float(s["comps"][ray]["ex"])
	return m / 4.0


func _clamp(par: Dictionary) -> void:
	par["abd"] = clampf(float(par["abd"]), 14.0, 28.0)
	par["dev"] = clampf(float(par["dev"]), -34.0, 6.0)
	par["flex"] = clampf(float(par["flex"]), -35.0, -8.0)
	par["pron"] = clampf(float(par["pron"]), -22.0, 10.0)
	par["wx"] = clampf(float(par["wx"]), -30.0, 40.0)
	par["wz"] = clampf(float(par["wz"]), -55.0, 0.0)


func _report(tag: String, s: Dictionary, par: Dictionary) -> void:
	print("%-14s score %8.3f worst %5.2f sum %7.2f pen %6.2f gap %5.1f splay %5.1f tilt %5.1f | %s"
		% [tag, float(s["score"]), float(s["worst"]), float(s["sum"]),
		float(s["pen"]), float(s["gap"]), float(s["splay"]),
		float(s["tilt"]), str(par)])
	var e: Dictionary = s["l"]["errs"]
	var c: Dictionary = s["l"]["comps"]
	print("   L err II %.2f III %.2f IV %.2f V %.2f I %.3f | dx %.2f %.2f %.2f %.2f | dz %.2f %.2f %.2f %.2f | dy %.2f %.2f %.2f %.2f"
		% [float(e["II"]), float(e["III"]), float(e["IV"]), float(e["V"]),
		float(e["I"]), float(c["II"]["ex"]), float(c["III"]["ex"]),
		float(c["IV"]["ex"]), float(c["V"]["ex"]), float(c["II"]["ez"]),
		float(c["III"]["ez"]), float(c["IV"]["ez"]), float(c["V"]["ez"]),
		float(c["II"]["dy"]), float(c["III"]["dy"]), float(c["IV"]["dy"]),
		float(c["V"]["dy"])])


# One cell: evaluate as placed, then re-centre wx by the measured mean ex
# and keep the better of the two rows. Returns the better score dict and
# the parameters it was scored with (par is updated in place too).
func _cell(par: Dictionary) -> Dictionary:
	_clamp(par)
	var s0 := _score(par)
	var par2 := par.duplicate(true)
	par2["wx"] = float(par["wx"]) - _mean_ex(s0["l"])
	var s1 := _score(par2)
	if float(s1["score"]) < float(s0["score"]):
		par["wx"] = float(par2["wx"])
		return s1
	return s0


# The hand-picked corners: a coarse map of how the objective answers the
# dev-unwinds-wrist-opens diagonal, before the lattice runs.
func _corners() -> Dictionary:
	var list := [
		{"abd": 20.0, "dev": -14.0, "pron": -6.0, "wx": 0.0, "wz": -42.0,
			"flex": -20.0},
		{"abd": 20.0, "dev": -14.0, "pron": -10.0, "wx": 0.0, "wz": -42.0,
			"flex": -20.0},
		{"abd": 20.0, "dev": -14.0, "pron": -14.0, "wx": 0.0, "wz": -42.0,
			"flex": -20.0},
		{"abd": 22.0, "dev": -18.0, "pron": -6.0, "wx": 0.0, "wz": -42.0,
			"flex": -20.0},
		{"abd": 22.0, "dev": -18.0, "pron": -10.0, "wx": 0.0, "wz": -42.0,
			"flex": -20.0},
		{"abd": 22.0, "dev": -18.0, "pron": -14.0, "wx": 0.0, "wz": -42.0,
			"flex": -20.0},
		{"abd": 20.0, "dev": -22.0, "pron": -6.0, "wx": 0.0, "wz": -42.0,
			"flex": -20.0},
		{"abd": 20.0, "dev": -22.0, "pron": -10.0, "wx": 0.0, "wz": -42.0,
			"flex": -20.0},
		{"abd": 22.0, "dev": -22.0, "pron": -12.0, "wx": 0.0, "wz": -42.0,
			"flex": -20.0},
	]
	var best: Dictionary = {}
	var best_par: Dictionary = {}
	for i in list.size():
		var par := {
			"wx": float(list[i]["wx"]), "wy": WY0, "wz": float(list[i]["wz"]),
			"abd": float(list[i]["abd"]), "dev": float(list[i]["dev"]),
			"flex": float(list[i]["flex"]), "pron": float(list[i]["pron"]),
		}
		var s := _cell(par)
		_report("corner %d" % (i + 1), s, par)
		if best.is_empty() or float(s["score"]) < float(best["score"]):
			best = s
			best_par = par.duplicate(true)
	print("CORNER BEST ", str(best_par))
	return {"best": best, "par": best_par}


func _polish(par: Dictionary, best: Dictionary) -> Dictionary:
	var params := ["wx", "wz", "abd", "dev", "flex", "pron"]
	var step := 1.0
	var sweeps := 0
	while step >= 0.25 and sweeps < 26:
		var improved := false
		for j in params:
			var base := float(par[j])
			var best_v := base
			var best_s: Dictionary = best
			for d in [-1.0, 1.0]:
				var v: float = base + float(d) * step
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
		_report("polish step %.1f" % step, best, par)
		if not improved:
			step *= 0.5
		sweeps += 1
	return best


func _init() -> void:
	var c := _corners()
	var par: Dictionary = c["par"]
	var best: Dictionary = c["best"]
	_report("polish start", best, par)
	best = _polish(par, best)
	# The depth gauge, MADE SAFE: shift wy by the mean dy only when the
	# shift really scores better, never over the found optimum.
	var dys := []
	for side in [best["l"], best["r"]]:
		for ray in ["II", "III", "IV", "V"]:
			dys.append(float(side["comps"][ray]["dy"]))
	var mean := 0.0
	for v in dys:
		mean += float(v)
	mean /= float(dys.size())
	var par2 := par.duplicate(true)
	par2["wy"] = WY0 - mean
	var s2 := _score(par2)
	if float(s2["score"]) < float(best["score"]):
		best = s2
		par = par2
		_report("FINAL (shifted)", best, par)
		print("  dy mean %.2f -> wy %.2f" % [mean, float(par["wy"])])
	else:
		_report("FINAL (no shift - the gauge would have hurt)", best, par)
	print("  arm ", str(best["arm"]))
	print("  elbow_x %.3f elbow_y %.3f" % [float(best["arm"]["elbow_x"]),
		float(best["arm"]["elbow_y"])])
	for key in ["l", "r"]:
		var pads_r: Dictionary = best[key]["pads"]
		var pose: Dictionary = best[key]["pose"]
		for ray in ["II", "III", "IV", "V"]:
			var pv: Vector3 = pads_r[ray]
			print("  %s %s world x %.2f y %.2f z %.2f (dy %.2f)" % [key,
				ray, pv.x, pv.y, pv.z, float(best[key]["comps"][ray]["dy"])])
		for ray in ["II", "III", "IV", "V", "I"]:
			if ray == "I":
				print("  %s I thumb angles %s" % [key,
					str(HandModel.thumb_of_pose(pose))])
			else:
				print("  %s %s finger joints %s" % [key, ray,
					str(pose["fingers"][ray])])
	quit(0)
