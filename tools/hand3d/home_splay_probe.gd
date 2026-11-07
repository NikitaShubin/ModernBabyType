# Can a SPLAYED home arm put the four pads on the key faces and the thumbs on
# their own halves of the space bar? This probe tries a handful of candidate
# arms and prints, per digit, the pad error against the full 3D target.
#
# The author (31.10.2026): "в реальной позиции предплечья не параллельны, а
# разведены, чтобы между локтями было куда бОльшее расстояние... Пальцы, кроме
# больших, лежат едва касаясь клавиш «фываолдж»... большие ... на ±20–23 мм с
# зазором ≥15–20 мм".
#
#   mbt-godot --headless --path /work/tools/hand3d --script res://home_splay_probe.gd
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
const TOUCH := 0.3          # mm above the face: "едва касаясь"
const THUMB_X := 20.5       # world mm from the split
const THUMB_LIFT := 2.0


func _xf(p: Dictionary) -> Transform3D:
	return ArmModel.hand_transform(p.get("arm", {}))


func _pad_world(side: String, ray: String, p: Dictionary) -> Vector3:
	var rx: float = ROOT_L if side == "L" else ROOT_R
	var xf := _xf(p)
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


func _opts(ray: String) -> Dictionary:
	var o := {"arm": false, "tuck": false, "clear_w": 0.0, "dir_w": 0.0}
	if ray == "I":
		o["thumb_dof"] = 4
	return o


func _run(side: String, arm: Dictionary, verbose: bool) -> Dictionary:
	var rx: float = ROOT_L if side == "L" else ROOT_R
	var p := HandModel.rest_pose()
	p["arm"] = arm.duplicate(true)
	p["thumb_f"] = 0.0
	p["thumb"] = HandModel.thumb_at(0.0)
	p["thumb_dof"] = 4
	var pads := {}
	var errs := {}
	var worst := 0.0
	for ray in ["II", "III", "IV", "V", "I"]:
		var t := _target(side, ray)
		var tw := Vector3(rx + t.x if side == "L" else rx - t.x, t.y, t.z)
		var r: Dictionary = IK.solve_chain(ray, t, p, _opts(ray))
		p = r["pose"]
		var pad := _pad_world(side, ray, p)
		pads[ray] = pad
		var e := (pad - tw).length()
		errs[ray] = e
		worst = maxf(worst, e)
		if verbose:
			print("    %-3s target %s pad %s err %6.2f angles %s" % [ray,
				str(tw), str(pad), e, str(r["angles"])])
	var elbow := ArmModel.elbow_of(arm)
	var ew: float = ROOT_L + elbow.x if side == "L" else ROOT_R - elbow.x
	var wl := _xf(p).origin
	var ww: float = ROOT_L + wl.x if side == "L" else ROOT_R - wl.x
	return {"worst": worst, "errs": errs, "pads": pads, "pose": p,
		"elbow_x": ew, "wrist_x": ww, "wrist": wl}


func _candidate(name: String, abd: float, dev: float, flex: float,
		pron: float, wrist_y: float, wrist_z: float) -> void:
	var arm := ArmModel.rest_arm()
	arm["forearm_abd"] = abd
	arm["wrist_dev"] = dev
	arm["wrist_flex"] = flex
	arm["pronation"] = pron
	arm["elbow_x"] = -ArmModel.FOREARM_L * sin(deg_to_rad(abd))
	arm["elbow_y"] = wrist_y + ArmModel.FOREARM_L \
		- ArmModel.FOREARM_L * cos(deg_to_rad(abd))
	arm["elbow_z"] = wrist_z
	var w := ArmModel.hand_transform(arm).origin
	print("== %s abd %.1f dev %.1f flex %.1f pron %.1f -> wrist %s" % [name,
		abd, dev, flex, pron, str(w)])
	var res := {}
	for side in ["L", "R"]:
		print("  %s:" % side)
		res[side] = _run(side, arm, true)
	var gap := absf(float(res["R"]["elbow_x"]) - float(res["L"]["elbow_x"]))
	var tgap: float = (res["L"]["pads"]["I"] as Vector3).distance_to(
		res["R"]["pads"]["I"])
	print("  worst L %.2f R %.2f  elbows %.1f .. %.1f gap %.1f  thumb gap %.2f"
		% [float(res["L"]["worst"]), float(res["R"]["worst"]),
		float(res["L"]["elbow_x"]), float(res["R"]["elbow_x"]), gap, tgap])


func _init() -> void:
	_candidate("A straight", 0.0, 0.0, -20.0, -6.875, 12.5, -35.0)
	_candidate("B splay 22", 22.0, -22.0, -15.0, 0.0, 12.5, -45.0)
	_candidate("C splay 22 lower", 22.0, -22.0, -10.0, 0.0, 12.5, -50.0)
	_candidate("D splay 26", 26.0, -26.0, -12.0, -4.0, 12.5, -48.0)
	_candidate("E splay 22 more flex", 22.0, -22.0, -20.0, 0.0, 12.5, -42.0)
	# Around E: roll the little-finger side down with pronation and move the
	# wrist a little. Printed as a compact table, one line per candidate.
	for pron in [-24.0, -20.0, -16.0, -12.0, -8.0, -4.0, 0.0, 4.0]:
		for wz in [-44.0, -42.0, -40.0]:
			for wy in [10.5, 12.5, 14.5]:
				var arm := ArmModel.rest_arm()
				arm["forearm_abd"] = 22.0
				arm["wrist_dev"] = -22.0
				arm["wrist_flex"] = -20.0
				arm["pronation"] = pron
				arm["elbow_x"] = -ArmModel.FOREARM_L * sin(deg_to_rad(22.0))
				arm["elbow_y"] = wy + ArmModel.FOREARM_L \
					- ArmModel.FOREARM_L * cos(deg_to_rad(22.0))
				arm["elbow_z"] = wz
				var l := _run("L", arm, false)
				var r := _run("R", arm, false)
				print("pron %5.1f wz %5.1f wy %5.1f  worst %5.2f  II %5.2f III %5.2f IV %5.2f V %5.2f I %5.2f"
					% [pron, wz, wy, maxf(float(l["worst"]), float(r["worst"])),
					float(l["errs"]["II"]), float(l["errs"]["III"]),
					float(l["errs"]["IV"]), float(l["errs"]["V"]),
					float(l["errs"]["I"])])
	quit(0)
