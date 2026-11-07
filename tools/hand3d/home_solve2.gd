# A home-pose search in the coordinates the author's brief is written in:
# where the WRIST is, how far the forearms are splayed, and how the hand is
# turned — not eight raw arm angles whose elbow translations fight the splay.
#
# The author (31.10.2026): "в реальной позиции предплечья не параллельны, а
# разведены, чтобы между локтями было куда бОльшее расстояние... Пальцы, кроме
# больших, лежат едва касаясь клавиш «фываолдж»... большие ... на ±20–23 мм с
# зазором ≥15–20 мм".
#
# Coordinates (all in the left hand's root-relative frame, mm and degrees):
#   wx, wy, wz   the wrist
#   abd          forearm abduction: the elbows splay out by 150*sin(abd)
#   dev, flex    wrist deviation and flexion
#   pron         pronation around the forearm
# The elbow is DERIVED from the wrist and the forearm direction, so changing
# the splay cannot drag the hand off the keys:
#   elbow = wrist - 150 * (sin abd, cos abd, 0)
#
# The score is the worst pad error plus the brief's own constraints: the
# elbow gap and the thumb gap. A pose that reaches every pad wins; among those
# the cheapest one wins.
#
#   mbt-godot --headless --path /work/tools/hand3d --script res://home_solve2.gd
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
const W_GAP := 0.01          # score per mm^2 of missing elbow gap
const W_THUMB := 0.02        # score per mm^2 of missing thumb gap
const W_ABD := 0.02          # score per degree^2 below 18 degrees of splay
const PARAMS := ["wx", "wy", "wz", "abd", "dev", "flex", "pron"]


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


# One side's five pads, solved with the arm frozen. The arm is the placement;
# the digits answer on their own.
func _side(side: String, arm: Dictionary) -> Dictionary:
	var p := HandModel.rest_pose()
	p["arm"] = arm.duplicate(true)
	p["thumb_f"] = 0.0
	p["thumb"] = HandModel.thumb_at(0.0)
	p["thumb_dof"] = 4
	var errs := {}
	var pads := {}
	var worst := 0.0
	var rx: float = ROOT_L if side == "L" else ROOT_R
	for ray in ["II", "III", "IV", "V", "I"]:
		var t := _target(side, ray)
		var r: Dictionary = IK.solve_chain(ray, t, p, _opts(ray))
		p = r["pose"]
		var pad := _pad_world(side, ray, p)
		pads[ray] = pad
		var tw := Vector3(rx + t.x if side == "L" else rx - t.x, t.y, t.z)
		var e := (pad - tw).length()
		errs[ray] = e
		worst = maxf(worst, e)
	return {"worst": worst, "errs": errs, "pads": pads, "pose": p}


func _score(par: Dictionary) -> Dictionary:
	var arm := _arm(par)
	var l := _side("L", arm)
	var r := _side("R", arm)
	var sum := 0.0
	for side in [l, r]:
		for ray in ["II", "III", "IV", "V", "I"]:
			sum += float(side["errs"][ray]) * float(side["errs"][ray])
	var abd := float(par["abd"])
	var gap := 116.45 + 2.0 * (ArmModel.FOREARM_L * sin(deg_to_rad(abd))
		- float(par["wx"]))
	var tgap: float = (l["pads"]["I"] as Vector3).distance_to(r["pads"]["I"])
	var pen := W_GAP * pow(maxf(0.0, ELBOW_GAP_MIN - gap), 2.0) \
		+ W_THUMB * pow(maxf(0.0, THUMB_GAP_MIN - tgap), 2.0) \
		+ W_ABD * pow(maxf(0.0, 18.0 - abd), 2.0)
	return {"score": sum + pen, "sum": sum, "pen": pen, "worst":
		maxf(float(l["worst"]), float(r["worst"])), "l": l, "r": r,
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
	print("%-10s score %8.3f  worst %6.2f  sum %8.2f  pen %7.2f  gap %6.1f  tgap %5.1f  %s"
		% [tag, float(s["score"]), float(s["worst"]), float(s["sum"]),
		float(s["pen"]), float(s["gap"]), float(s["tgap"]), str(par)])
	print("   errs L %s" % str(s["l"]["errs"]))
	print("   errs R %s" % str(s["r"]["errs"]))


func _init() -> void:
	var par := {"wx": 0.0, "wy": 12.5, "wz": -42.0, "abd": 22.0,
		"dev": -22.0, "flex": -20.0, "pron": 0.0}
	var best := _score(par)
	_report("start", best, par)
	var step := 6.0
	for sweep in 30:
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
				if float(s["score"]) < float(best_s["score"]) - 0.001:
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
	print("BEST score %.3f  worst %.2f  sum %.2f" % [float(best["score"]),
		float(best["worst"]), float(best["sum"])])
	print("  par ", par)
	print("  arm ", best["arm"])
	for side in ["l", "r"]:
		print("  %s errs %s" % [side, str(best[side]["errs"])])
		print("  %s pads %s" % [side, str(best[side]["pads"])])
	print("  L thumb %s" % str(HandModel.thumb_of_pose(best["l"]["pose"])))
	print("  R thumb %s" % str(HandModel.thumb_of_pose(best["r"]["pose"])))
	print("  L fingers %s" % str(best["l"]["pose"]["fingers"]))
	quit(0)
