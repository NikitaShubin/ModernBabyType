# The thumbs' targets swept along the space bar, version 2 — judged by
# NATURALNESS, not by the share of the flexible range. The author rejected
# SS50d on 02.11.2026: the right thumb's terminal phalanx was folded far past
# its resting curl (ip 58.6 deg over the resting 34) — anatomically reachable
# (no ROM break), but nothing a hand rests with. The effort metric (a fraction
# of ROM, thumb_effort) stayed small there because the flexible range is wide;
# the eye caught what the fraction did not.
# Every candidate now reports the absolute deviation from THUMB_REST per joint
# in DEGREES and the terminal segment's direction: sweep_x > 0 the tip glides
# on inboard of the mid joint, sweep_x < 0 it doubles back over it — the claw.
# Plus the pure-rest hover: where the idle thumb puts its pad with every joint
# exactly at THUMB_REST (twist held) — the target a hand would pick itself.
#   docker run ... --script res://thumb_in_sweep.gd   (MBT_LIFT=n: hover n mm)
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")
const IK := preload("res://ik.gd")
const HomePose := preload("res://home_pose.gd")
const Kbd3D := preload("res://kbd3d.gd")

const ROOT0 := {"L": -122.51, "R": 93.94}
const BAR_HALF := 46.46     # the space bar spans [-46.46, +46.46] (3u centred)
const PAD_R := 9.6          # the pad capsule's last radius (board_viewer THUMB_R)

# MBT_TWIST_R=<deg>: override the right thumb's held twist, so the sweep can
# ask "what if the right were held like the left" without touching the file.
static var TWIST_R := 999.0

const X_GRID := {
	"L": [31.0],
	"R": [2.0, 4.0, 6.0, 8.0, 10.0, 12.0, 14.0, 16.0],
}
const Y_GRID := {"L": [112.0], "R": [104.0, 107.0, 110.0, 113.0]}


# HomePose.build's opening: rest pose, arm, thumb and hold, then ONLY the four
# finger chains. The returned pose is exactly the state the shipped build
# hands to its own thumb solve.
static func base_for(side: String, root_x: float) -> Dictionary:
	var p := HandModel.rest_pose()
	p["arm"] = (HomePose.ARM as Dictionary).duplicate(true)
	p["thumb_f"] = 0.0
	p["thumb"] = HandModel.thumb_at(0.0)
	p["thumb_dof"] = 4
	var tw: float = float(HomePose.THUMB_TWIST[side])
	if side == "R" and TWIST_R < 900.0:
		tw = TWIST_R
	p["thumb_hold"] = {"twist": tw}
	for ray in ["II", "III", "IV", "V"]:
		var t: Vector3 = HomePose.target(side, ray, root_x)
		var r: Dictionary = IK.solve_chain(ray, t, p, HomePose._opts(ray))
		p = r["pose"]
	return p


static func world(side: String, p: Dictionary, local: Vector3) -> Vector3:
	var xf := ArmModel.hand_transform(p.get("arm", {}))
	var q := xf * local
	var rx := float(ROOT0[side])
	if side == "R":
		return Vector3(rx - q.x, q.y, q.z)
	return Vector3(rx + q.x, q.y, q.z)


# Every thumb joint exactly at THUMB_REST (twist held): where does the idle
# thumb put its pad, without solving anything? This is the tip a natural
# hand would hover with; we print it BEFORE the sweep so the chosen target
# can be compared to it directly.
static func rest_hover(side: String, base: Dictionary) -> void:
	var th: Dictionary = HandModel.THUMB_REST.duplicate(true)
	th["twist"] = float(HomePose.THUMB_TWIST[side])
	if side == "R" and TWIST_R < 900.0:
		th["twist"] = TWIST_R
	var fk := HandModel.thumb_fk(th)
	var pad: Vector3 = HandModel.thumb_pad(fk)
	var pts: PackedVector3Array = fk["pts"]
	var w := world(side, base, pad)
	var wpad2: Vector3 = world(side, base, pts[2])
	print("%s pure-rest pad world (%7.2f, %7.2f, %7.2f) lift-vs-face %5.2f mm; mid-joint world x %7.2f" % [
		side, w.x, w.y, w.z, w.z - Kbd3D.FACE_Z, wpad2.x])


static func measure(side: String, base: Dictionary, tx: float, ty: float,
		lift: float) -> Dictionary:
	var sgn := -1.0 if side == "R" else 1.0
	var p: Dictionary = base.duplicate(true)
	var wtx := -tx if side == "L" else tx
	var tI := Vector3((wtx - float(ROOT0[side])) * sgn, ty,
		Kbd3D.FACE_Z + lift)
	var r := IK.solve_chain("I", tI, p, HomePose._opts("I"))
	p = r["pose"]
	var th := HandModel.thumb_of_pose(p)
	var fk := HandModel.thumb_fk(th)
	var pad_local: Vector3 = HandModel.thumb_pad(fk)
	var pad := world(side, p, pad_local)
	var pts: PackedVector3Array = fk["pts"]
	var mid := world(side, p, pts[2])
	var sweep_x: float = pad.x - mid.x
	var eff: Dictionary = HandModel.thumb_effort(th)
	var breaks := []
	var maxdev := 0.0
	var ip_abs := 0.0
	var mcp_abs := 0.0
	var abd_abs := 0.0
	for j in HandModel.THUMB_ROM:
		var rom: Array = HandModel.THUMB_ROM[j]
		var a: float = float(th.get(j, 0.0))
		if a < float(rom[0]) - 1e-6 or a > float(rom[1]) + 1e-6:
			breaks.append(String(j) + " " + String.num(a, 1))
		if String(j) != "twist":
			var dev: float = a - float(HandModel.THUMB_REST[j])
			maxdev = maxf(maxdev, absf(dev))
		if String(j) == "ip":
			ip_abs = a
		elif String(j) == "mcp":
			mcp_abs = a
		elif String(j) == "cmc_abd":
			abd_abs = a
	var peak := maxf(float(eff.get("cmc", 0.0)),
		maxf(float(eff.get("mcp", 0.0)), float(eff.get("ip", 0.0))))
	var head_ii := world(side, p, HandModel.metacarpal_head("II"))
	var inboard := 1.0 if side == "R" else -1.0
	var margin_i: float = inboard * (pad.x - head_ii.x)
	var overhang: float = absf(pad.x) + PAD_R - BAR_HALF
	var want := Vector3(wtx, ty, Kbd3D.FACE_Z + lift)
	return {"pad": pad, "err": pad.distance_to(want), "eff": eff,
		"breaks": breaks, "margin_i": margin_i, "overhang": overhang,
		"peak": peak, "maxdev": maxdev, "ip_abs": ip_abs,
		"mcp_abs": mcp_abs, "abd_abs": abd_abs, "sweep_x": sweep_x,
		"tx": tx, "ty": ty}


func _init() -> void:
	var t0 := Time.get_ticks_msec()
	if OS.get_environment("MBT_TWIST_R") != "":
		TWIST_R = float(OS.get_environment("MBT_TWIST_R"))
	var twtxt := "shipped" if TWIST_R > 900.0 else String.num(TWIST_R, 0)
	print("## R twist override: ", twtxt)
	var lift: float = float(HomePose.THUMB_LIFT)
	if OS.get_environment("MBT_LIFT") != "":
		lift = float(OS.get_environment("MBT_LIFT"))
	var bases := {
		"L": base_for("L", float(ROOT0["L"])),
		"R": base_for("R", float(ROOT0["R"])),
	}
	print("## bases built in ", (Time.get_ticks_msec() - t0) * 1e-3,
		" s, lift ", lift)
	rest_hover("L", bases["L"])
	rest_hover("R", bases["R"])
	var ip_rest: float = float(HandModel.THUMB_REST["ip"])
	var feasible := {"L": [], "R": []}
	for side in ["L", "R"]:
		var base: Dictionary = bases[side]
		print("=== ", side, " ===")
		for tx in (X_GRID.get(side, []) as Array):
			for ty in (Y_GRID.get(side, []) as Array):
				var m := measure(side, base, float(tx), float(ty), lift)
				var err := float(m["err"])
				var over := float(m["overhang"])
				var breaks: Array = m["breaks"]
				var pad: Vector3 = m["pad"]
				var feas := err <= 1.0 and breaks.is_empty() and over <= 0.0
				var ok := "ok  " if feas else "NOTE"
				print("%s tx %5.1f ty %5.1f | pad x %7.2f y %7.2f | ip %5.1f (dev %5.1f) mcp %5.1f abd %6.1f | maxdev %4.1f sweep_x %6.2f | err %5.2f over %6.2f" % [
					ok, float(tx), float(ty), pad.x, pad.y,
					float(m["ip_abs"]), float(m["ip_abs"]) - ip_rest,
					float(m["mcp_abs"]), float(m["abd_abs"]),
					float(m["maxdev"]), float(m["sweep_x"]), err, over])
				if feas:
					(feasible[side] as Array).append(m)
	print("=== pair table: worse-hand maxdev (deg), ascending ===")
	var pairs := []
	for ML in feasible["L"]:
		var ml: Dictionary = ML
		for MR in feasible["R"]:
			var mr: Dictionary = MR
			var gap: float = (ml["pad"] as Vector3).distance_to(
				mr["pad"] as Vector3
			)
			var score: float = maxf(float(ml["maxdev"]), float(mr["maxdev"]))
			pairs.append([score, gap, float(ml["tx"]), float(mr["tx"]),
				float(ml["ty"]), float(mr["ty"]), float(mr["ip_abs"])])
	pairs.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	for i in mini(pairs.size(), 14):
		var row: Array = pairs[i]
		print("pair L %5.1f / R %5.1f ty %5.1f/%5.1f gap %6.2f maxdev %5.2f R-ip %5.1f" % [
			float(row[2]), float(row[3]), float(row[4]), float(row[5]),
			float(row[1]), float(row[0]), float(row[6])])
	print("sweep done in ", (Time.get_ticks_msec() - t0) * 1e-3, " s")
	quit(0)
