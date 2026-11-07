# Checks the IK solver the way the viewer will use it. Headless:
#   mbt-godot --headless --path /work/tools/hand3d --script res://ik_test.gd
#
# The assertions are the promises the viewer makes to the author:
#   · the rest pose is the zero — a rest target returns the rest angles and
#     zero energy, not "some pose with the same fingertip";
#   · a target the chain can reach is reached to well under a millimetre;
#   · a target it cannot reach leaves an honest residual, never a lie;
#   · the joints bend TOGETHER: the share of its own travel spent by MCP,
#     PIP and DIP never staggers beyond the allowed band, and no joint is
#     folded while its neighbour sleeps — that is the rule the author set;
#   · the thumb keeps its single coordinate and equal effort;
#   · the chain climbs: a near target is answered by the finger, a middle one
#     by the wrist, a far one by the pronation and the forearm root, and the
#     pad still lands on the target;
#   · the arm never leaves its clinical ROM and never returns a NaN.
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")
const IK := preload("res://ik.gd")

# Targets are built from share vectors, not from raw degrees: that is the
# space the solver works in, and a target built on the equal-share line is
# reachable by construction.
var _checks := 0
var _fails := 0


func _init() -> void:
	_test_rest()
	_test_reachable()
	_test_extension()
	_test_out_of_reach()
	_test_sideways()
	_test_coordination()
	_test_thumb()
	_test_drag_continuity()
	_test_chain()
	_test_elbow()
	print("ik_test: %d checks, %d failed" % [_checks, _fails])
	quit(1 if _fails > 0 else 0)


func _ck(ok: bool, msg: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
		print("FAIL: ", msg)


func _angles_text(a: Dictionary) -> String:
	return "mcp %.2f pip %.2f dip %.2f fan %+.2f" % [
		float(a["mcp"]), float(a["pip"]), float(a["dip"]), float(a["fan"])]


func _shares_text(s: Array) -> String:
	return "%+.0f%% / %+.0f%% / %+.0f%%" % [float(s[0]) * 100.0,
		float(s[1]) * 100.0, float(s[2]) * 100.0]


func _in_rom(ray: String, a: Dictionary) -> bool:
	var rom: Dictionary = HandModel.ROM[ray]
	for j in ["mcp", "pip", "dip", "fan"]:
		if float(a[j]) < float(rom[j][0]) - 0.001 or float(a[j]) > float(rom[j][1]) + 0.001:
			return false
	return true


# A pose from one share vector: the natural way to build a reachable target.
func _pose_of(ray: String, sm: float, sp: float, sd: float, fan: float = 0.0) -> Dictionary:
	var p := HandModel.rest_pose()
	p["fingers"][ray] = IK.angles_of_shares(ray, [sm, sp, sd, fan])
	return p


# A rest hand with the arm set to a pose. Targets built from it are reachable
# by construction, which the fixed-elbow arm needs: there is no shoulder to
# swing the whole hand around any more.
func _arm_pose(arm: Dictionary) -> Dictionary:
	var p := HandModel.rest_pose()
	for j in arm:
		p["arm"][j] = float(arm[j])
	return p


func _pad_of(ray: String, p: Dictionary) -> Vector3:
	return HandModel.finger_pad(ray, HandModel.finger_fk(ray, p["fingers"][ray]))


func _test_rest() -> void:
	print("== rest is the zero")
	for ray in HandModel.FINGERS:
		var p := HandModel.rest_pose()
		var pad := _pad_of(ray, p)
		var r := IK.solve_finger(ray, pad, p)
		var a: Dictionary = r["angles"]
		_ck(float(r["error"]) < 0.01, "%s rest target error %.4f" % [ray, float(r["error"])])
		_ck(float(r["energy"]) < 0.0001, "%s rest energy %.5f" % [ray, float(r["energy"])])
		_ck(_in_rom(ray, a), "%s rest angles out of ROM: %s" % [ray, _angles_text(a)])
		for j in ["mcp", "pip", "dip", "fan"]:
			_ck(absf(float(a[j]) - float(p["fingers"][ray][j])) < 0.02,
				"%s rest %s moved to %.3f" % [ray, j, float(a[j])])
		print("   %s: error %.4f mm, energy %.5f, %s" % [ray, float(r["error"]),
			float(r["energy"]), _shares_text(r["shares"])])

	var tp := HandModel.thumb_pad(HandModel.thumb_fk(0.0))
	var rt := IK.solve_thumb(tp, HandModel.rest_pose())
	_ck(absf(float(rt["thumb_f"])) < 0.02, "thumb rest f %.4f" % float(rt["thumb_f"]))
	_ck(float(rt["error"]) < 0.05, "thumb rest error %.4f" % float(rt["error"]))
	print("   thumb: f %.4f, error %.4f mm" % [float(rt["thumb_f"]), float(rt["error"])])


func _test_reachable() -> void:
	print("== reachable targets")
	for ray in HandModel.FINGERS:
		var p0 := HandModel.rest_pose()
		# On the equal-share line: the pose the author calls coordinated.
		var a := _pose_of(ray, 0.45, 0.45, 0.45)
		var target := _pad_of(ray, a)
		var r := IK.solve_finger(ray, target, p0)
		_ck(float(r["error"]) < 0.02, "%s equal-share target error %.4f" % [ray, float(r["error"])])
		_ck(float(r["spread"]) < 0.02, "%s equal-share spread %.3f (%s)" % [ray,
			float(r["spread"]), _shares_text(r["shares"])])
		_ck(_in_rom(ray, r["angles"]), "%s equal-share angles out of ROM" % ray)
		print("   %s: error %.4f mm, %s, shares %s, spread %.3f, %d it%s" % [ray,
			float(r["error"]), _angles_text(r["angles"]), _shares_text(r["shares"]),
			float(r["spread"]), int(r["iterations"]),
			" (at ROM)" if (r["at_rom"] as Dictionary).values().has(true) else ""])

		# Inside the band the joints may stagger; the target is still exact.
		var b := _pose_of(ray, 0.55, 0.45, 0.50)
		var tb := _pad_of(ray, b)
		var rb := IK.solve_finger(ray, tb, p0)
		_ck(float(rb["error"]) < 0.02, "%s staggered target error %.4f" % [ray, float(rb["error"])])
		_ck(float(rb["spread"]) <= IK.BAND + 0.02, "%s staggered spread %.3f (%s)" % [ray,
			float(rb["spread"]), _shares_text(rb["shares"])])
		print("   %s staggered: error %.4f mm, shares %s, spread %.3f" % [ray,
			float(rb["error"]), _shares_text(rb["shares"]), float(rb["spread"])])


# Straightening: shares go negative, and all three still move together. The
# target is built from equal shares, so it must be hit — to the comfort
# polish's own promise (IK's `pol` keeps a pose only while its reach grows by
# at most 0.05 mm). The polish spends that slack on the cheapest posture, and
# on V it spends all of it; a tighter bound here would forbid the rule the
# author asked for (any movement obeys the energy minimum).
func _test_extension() -> void:
	print("== straightening")
	for ray in HandModel.FINGERS:
		var p0 := HandModel.rest_pose()
		var a := _pose_of(ray, -0.60, -0.58, -0.56)
		var target := _pad_of(ray, a)
		var r := IK.solve_finger(ray, target, p0)
		_ck(float(r["error"]) <= 0.05, "%s extension target error %.4f" % [ray, float(r["error"])])
		_ck(float(r["spread"]) < 0.08, "%s extension spread %.3f (%s)" % [ray,
			float(r["spread"]), _shares_text(r["shares"])])
		_ck(float(r["spread"]) <= IK.BAND + 0.001, "%s extension spread breaks the band" % ray)
		_ck(_in_rom(ray, r["angles"]), "%s extension angles out of ROM" % ray)
		print("   %s: error %.4f mm, %s, shares %s, spread %.3f" % [ray, float(r["error"]),
			_angles_text(r["angles"]), _shares_text(r["shares"]), float(r["spread"])])


func _test_out_of_reach() -> void:
	print("== out of reach")
	for ray in HandModel.FINGERS:
		var p := HandModel.rest_pose()
		var pad := _pad_of(ray, p)
		var target := pad + Vector3(0, 90, 0)       # far above the fingertips
		var r := IK.solve_finger(ray, target, p)
		var a: Dictionary = r["angles"]
		_ck(float(r["error"]) > 10.0, "%s unreachable error only %.2f" % [ray, float(r["error"])])
		_ck(_in_rom(ray, a), "%s unreachable angles out of ROM" % ray)
		_ck(is_finite(float(r["error"])), "%s unreachable error is not finite" % ray)
		# The hand reaches toward the target, it does not break itself to
		# chase it: the joints stay within the coordination band.
		_ck(float(r["spread"]) <= IK.BAND + 0.001, "%s unreachable spread %.3f (%s)" % [
			ray, float(r["spread"]), _shares_text(r["shares"])])
		print("   %s: residual %.2f mm, %s, shares %s, spread %.3f" % [ray,
			float(r["error"]), _angles_text(a), _shares_text(r["shares"]), float(r["spread"])])


func _test_sideways() -> void:
	print("== sideways (the fan)")
	for ray in HandModel.FINGERS:
		var p := HandModel.rest_pose()
		# A target the fan can actually reach: three quarters of its own range
		# away from rest. (Nine millimetres of pure +X is beyond the V's fan —
		# its whole range is only eight degrees.)
		var fan_share := 0.75
		var target := _pad_of(ray, _pose_of(ray, 0.0, 0.0, 0.0, fan_share))
		var r := IK.solve_finger(ray, target, p)
		var a: Dictionary = r["angles"]
		var dfan := absf(float(a["fan"]) - float(p["fingers"][ray]["fan"]))
		_ck(float(r["error"]) < 0.5, "%s sideways error %.3f" % [ray, float(r["error"])])
		_ck(dfan > 0.5, "%s sideways did not use the fan (%.2f deg)" % [ray, dfan])
		_ck(float(r["spread"]) <= IK.BAND + 0.001, "%s sideways spread %.3f (%s)" % [ray,
			float(r["spread"]), _shares_text(r["shares"])])
		_ck(_in_rom(ray, a), "%s sideways angles out of ROM" % ray)
		print("   %s: error %.3f mm, fan %+.1f -> %+.1f, shares %s, spread %.3f" % [ray,
			float(r["error"]), float(p["fingers"][ray]["fan"]), float(a["fan"]),
			_shares_text(r["shares"]), float(r["spread"])])


# The rule the author set: a pose may stagger a little, never a lot. Sweep a
# grid of targets around the finger (near, mid, far, in every direction) and
# demand that no answer ever shows one joint folded while its neighbour is
# almost straight.
func _test_coordination() -> void:
	print("== coordination band")
	var worst := 0.0
	var worst_at := ""
	var total := 0
	var dirs := []
	for iy in [-1, 0, 1]:
		for iz in [-1, 0, 1]:
			for ix in [-1, 0, 1]:
				if ix == 0 and iy == 0 and iz == 0:
					continue
				dirs.append(Vector3(ix, iy, iz).normalized())
	for ray in HandModel.FINGERS:
		var p := HandModel.rest_pose()
		var pad := _pad_of(ray, p)
		var mcp := HandModel.metacarpal_head(ray)
		for d in dirs:
			for reach in [25.0, 55.0, 85.0, 120.0]:
				var target: Vector3 = mcp + (d as Vector3) * reach
				var r := IK.solve_finger(ray, target, p)
				total += 1
				var sp := float(r["spread"])
				if sp > worst:
					worst = sp
					worst_at = "%s target %s" % [ray, str(target)]
				_ck(_in_rom(ray, r["angles"]), "%s %s angles out of ROM" % [ray, str(target)])
				_ck(is_finite(float(r["error"])), "%s %s error not finite" % [ray, str(target)])
	_ck(worst <= IK.BAND + 0.001, "worst spread %.3f over the grid (allowed %.2f): %s" % [
		worst, IK.BAND, worst_at])
	print("   %d targets, worst spread %.3f of the band %.2f (%s)" % [total, worst,
		IK.BAND, worst_at if worst_at != "" else "-"])


func _test_thumb() -> void:
	print("== thumb: one coordinate")
	var p := HandModel.rest_pose()
	# A target the thumb's path passes through: press at f = 0.4.
	var press := float(HandModel.POSE_THUMBS["press"])
	var t_press := HandModel.thumb_pad(HandModel.thumb_fk(press))
	var r := IK.solve_thumb(t_press, p)
	_ck(absf(float(r["thumb_f"]) - press) < 0.03,
		"thumb press f %.3f instead of %.2f" % [float(r["thumb_f"]), press])
	_ck(float(r["error"]) < 0.1, "thumb press error %.3f" % float(r["error"]))
	var eff: Dictionary = r["effort"]
	_ck(absf(float(eff["cmc"]) - float(eff["mcp"])) < 0.01 \
		and absf(float(eff["mcp"]) - float(eff["ip"])) < 0.01,
		"thumb effort is not shared: %s" % str(eff))
	print("   press: f %.3f, error %.3f mm, effort %.0f/%.0f/%.0f%%" % [
		float(r["thumb_f"]), float(r["error"]), float(eff["cmc"]),
		float(eff["mcp"]), float(eff["ip"])])

	# Off the path by a long way: the honest answer is the nearest point on
	# the path, compared against a brute-force scan.
	var far := HandModel.thumb_pad(HandModel.thumb_fk(0.0)) + Vector3(0, 0, -120)
	var rf := IK.solve_thumb(far, p)
	var oracle := _thumb_oracle(far)
	_ck(float(rf["error"]) > 10.0, "thumb unreachable error only %.2f" % float(rf["error"]))
	_ck(absf(float(rf["thumb_f"]) - float(oracle[0])) < 0.01,
		"thumb far f %.4f, oracle %.4f" % [float(rf["thumb_f"]), float(oracle[0])])
	_ck(absf(float(rf["cost"]) - float(oracle[1])) < 0.05,
		"thumb far cost %.3f, oracle %.3f" % [float(rf["cost"]), float(oracle[1])])
	print("   far: f %+.3f (oracle %+.3f), residual %.1f mm" % [float(rf["thumb_f"]),
		float(oracle[0]), float(rf["error"])])

	# Close by: a target a few millimetres off the path still finds the nearest
	# point on it.
	var near := HandModel.thumb_pad(HandModel.thumb_fk(0.25)) + Vector3(0, 2, 0)
	var rn := IK.solve_thumb(near, p)
	_ck(float(rn["error"]) < 2.5, "thumb near error %.2f" % float(rn["error"]))
	print("   near: f %+.3f, residual %.2f mm" % [float(rn["thumb_f"]), float(rn["error"])])


func _thumb_oracle(target: Vector3) -> Array:
	var best_f := 0.0
	var best_c := INF
	for i in 4001:
		var f := -1.0 + 2.0 * float(i) / 4000.0
		var c := IK._thumb_cost(f, target)
		if c < best_c:
			best_c = c
			best_f = f
	return [best_f, best_c]


# Dragging must not snap: walk the target along the natural path (equal
# shares 0 → 0.5) and watch each joint from the previous solution. Every step
# must be reached exactly, keep the shares together, and move smoothly.
func _test_drag_continuity() -> void:
	print("== drag continuity")
	for ray in HandModel.FINGERS:
		var p := HandModel.rest_pose()
		var prev: Dictionary = p["fingers"][ray]
		var worst_step := 0.0
		var worst_err := 0.0
		var worst_spread := 0.0
		for i in 11:
			var s := 0.05 * float(i)
			var target := _pad_of(ray, _pose_of(ray, s, s, s))
			var r := IK.solve_finger(ray, target, p)
			p = r["pose"]
			var a: Dictionary = p["fingers"][ray]
			worst_err = maxf(worst_err, float(r["error"]))
			worst_spread = maxf(worst_spread, float(r["spread"]))
			for j in ["mcp", "pip", "dip", "fan"]:
				worst_step = maxf(worst_step, absf(float(a[j]) - float(prev[j])))
			prev = a
		_ck(worst_err < 0.02, "%s drag worst error %.4f" % [ray, worst_err])
		_ck(worst_spread < 0.02, "%s drag worst spread %.3f" % [ray, worst_spread])
		_ck(worst_step < 8.0, "%s drag jumped %.1f deg in one step" % [ray, worst_step])
		print("   %s: worst error %.4f mm, worst spread %.3f, largest joint step %.2f deg" % [
			ray, worst_err, worst_spread, worst_step])

	# Off the natural path, towards the palm: the pad cannot follow exactly,
	# but the pose stays coordinated and the residual is honest.
	var ray := "II"
	var p := HandModel.rest_pose()
	var pad := _pad_of(ray, p)
	var r := IK.solve_finger(ray, pad + Vector3(0, 0, -12), p)
	_ck(float(r["spread"]) <= IK.BAND + 0.001, "off-path spread %.3f (%s)" % [
		float(r["spread"]), _shares_text(r["shares"])])
	print("   off-path 12 mm: residual %.2f mm, shares %s, spread %.3f" % [
		float(r["error"]), _shares_text(r["shares"]), float(r["spread"])])


# ---- the hierarchical chain --------------------------------------------
#
# The promises the arm adds: the rest is still the zero (identity arm), a
# target near the pad is answered by the finger, a middle one by the wrist, a
# far one by the forearm root, and the pad lands on the target in every case
# that is physically reachable. The arm angles are always inside the clinical
# ROM, because the shares are clamped there before they become angles.

func _pad_of_chain(ray: String, p: Dictionary) -> Vector3:
	var xf := ArmModel.hand_transform(p.get("arm", {}))
	if ray == "I":
		return xf * HandModel.thumb_pad(HandModel.thumb_fk(float(p["thumb_f"])))
	return xf * HandModel.finger_pad(ray,
		HandModel.finger_fk(ray, p["fingers"][ray]))


func _arm_in_rom(a: Dictionary) -> bool:
	for j in ArmModel.JOINTS:
		if float(a[j]) < float(ArmModel.ROM[j][0]) - 0.001 \
				or float(a[j]) > float(ArmModel.ROM[j][1]) + 0.001:
			return false
	for j in ArmModel.ROOT_JOINTS:
		if absf(float(a[j])) > ArmModel.ELBOW_RANGE + 0.001:
			return false
	return true


func _chain_text(r: Dictionary) -> String:
	var lev: Dictionary = r["levels"]
	return "err %.2f | finger %.0f fan %.0f wrist %.0f pron %.0f forearm %.0f elbow %.0f" % [
		float(r["error"]), float(lev.get("finger", 0)), float(lev.get("fan", 0)),
		float(lev.get("wrist", 0)), float(lev.get("pronation", 0)),
		float(lev.get("forearm", 0)), float(lev.get("elbow", 0))]


func _test_chain() -> void:
	print("== chain: finger → wrist → forearm → moving elbow")
	var rest := HandModel.rest_pose()

	# Rest is the zero of the whole chain: no finger travel, identity arm,
	# zero energy. This is the pose the author approved, so it must not drift.
	for ray in HandModel.FINGERS:
		var pad := _pad_of_chain(ray, rest)
		var r := IK.solve_chain(ray, pad, rest, {"arm": true})
		var lev: Dictionary = r["levels"]
		_ck(float(r["error"]) < 0.6, "%s chain rest error %.3f" % [ray, float(r["error"])])
		_ck(float(r["chain_energy"]) < 0.01, "%s chain rest energy %.4f" % [ray,
			float(r["chain_energy"])])
		_ck(float(lev["forearm"]) < 1.0,
			"%s chain rest bends the forearm: %s" % [ray, _chain_text(r)])
		_ck(_arm_in_rom(r["arm"]), "%s chain rest arm out of ROM" % ray)
		print("   %s rest: %s" % [ray, _chain_text(r)])

	var tpad := HandModel.thumb_pad(HandModel.thumb_fk(0.0))
	var rt := IK.solve_chain("I", tpad, rest, {"arm": true})
	_ck(absf(float(rt["thumb_f"])) < 0.02, "thumb chain rest f %.3f" % float(rt["thumb_f"]))
	_ck(float(rt["chain_energy"]) < 0.01, "thumb chain rest energy %.4f" % float(rt["chain_energy"]))
	_ck(float(rt["levels"]["forearm"]) < 1.0, "thumb chain rest uses the forearm")
	print("   thumb rest: f %.3f, %s" % [float(rt["thumb_f"]), _chain_text(rt)])

	# The ladder: one target per level, each built from a POSE the arm can
	# hold. Reachable by construction is the point: the fixed elbow has no
	# shoulder to swing the whole hand around, and a raw world point that
	# used to be "far" can now sit outside the shell entirely. The thresholds
	# are deliberately loose; the ORDER is the promise.
	var pad := _pad_of_chain("II", rest)
	var out := (pad - Vector3.ZERO).normalized()
	var p0 := HandModel.rest_pose()

	var near := IK.solve_chain("II", pad - out * 10.0, p0, {"arm": true})
	var ln: Dictionary = near["levels"]
	_ck(float(near["error"]) < 0.05, "near target error %.2f" % float(near["error"]))
	_ck(float(ln["finger"]) > 0.0, "near target does not use the finger")
	_ck(float(ln["forearm"]) < 5.0,
		"near target climbs too high: %s" % _chain_text(near))
	print("   near 10 mm: %s" % _chain_text(near))

	var mid := IK.solve_chain("II", pad + Vector3(0, 0, -30), p0, {"arm": true})
	var lm: Dictionary = mid["levels"]
	_ck(float(mid["error"]) < 0.05, "mid target error %.2f" % float(mid["error"]))
	_ck(float(lm["finger"]) > 10.0, "mid target does not use the finger")
	_ck(float(lm["wrist"]) > 5.0, "mid target does not use the wrist: %s" % _chain_text(mid))
	_ck(float(lm["forearm"]) < 5.0, "mid target uses the forearm: %s" % _chain_text(mid))
	print("   mid 30 mm to the palm: %s" % _chain_text(mid))

	# Far: a pose with the forearm swung out and down. The pad is where that
	# pose puts it, so the target is honest, and the answer must climb all the
	# way to the root rather than fold the wrist alone.
	var far_pose := _arm_pose({"forearm_abd": 35.0, "forearm_flex": -25.0})
	var far := IK.solve_chain("II", _pad_of_chain("II", far_pose), p0, {"arm": true})
	var lf: Dictionary = far["levels"]
	_ck(float(far["error"]) < 0.05, "far target error %.2f" % float(far["error"]))
	_ck(float(lf["forearm"]) > 20.0,
		"far target does not climb to the forearm: %s" % _chain_text(far))
	_ck(_arm_in_rom(far["arm"]), "far target arm out of ROM")
	print("   far (pose abd 35, flex -25): %s" % _chain_text(far))

	for arm in [{"forearm_abd": 45.0}, {"forearm_abd": -45.0}]:
		var t := _pad_of_chain("II", _arm_pose(arm))
		var r := IK.solve_chain("II", t, p0, {"arm": true})
		var l: Dictionary = r["levels"]
		_ck(float(r["error"]) < 0.05, "side target %s error %.2f" % [str(arm), float(r["error"])])
		_ck(float(l["forearm"]) > 10.0,
			"side target %s does not climb: %s" % [str(arm), _chain_text(r)])
		_ck(_arm_in_rom(r["arm"]), "side target %s arm out of ROM" % str(arm))
		print("   side %s: %s" % [str(arm), _chain_text(r)])

	# The thumb's chain: the pad can be put on the palmar side, toward the
	# elbow and far to the thumb side; the arm answers when the thumb alone
	# cannot. The old fixed world point (120, -80, -80) is still reachable
	# and asks the wrist for its full flexion, so it stays as the far case.
	for t in [tpad + Vector3(0, 0, -30), tpad + Vector3(0, -60, 0),
			Vector3(120, -80, -80)]:
		var r := IK.solve_chain("I", t, rest, {"arm": true})
		_ck(float(r["error"]) < 0.05, "thumb chain %s error %.2f" % [str(t), float(r["error"])])
		_ck(_arm_in_rom(r["arm"]), "thumb chain %s arm out of ROM" % str(t))
		_ck(absf(float(r["thumb_f"])) <= 1.001, "thumb chain f out of range")
		print("   thumb %s: f %+.2f, %s" % [str(t), float(r["thumb_f"]), _chain_text(r)])

	# Sideways at the base, the gesture the author asked to see: spreading a
	# finger out must be the fan's job, with the hand and the forearm almost
	# still. The target is 5 mm out from the rest pad in the finger's own
	# abduction direction (+X for the radial fingers, -X for the ulnar ones);
	# the fan must take at least ~2 degrees and the arm must stay under half
	# a degree. The full fan range with the arm frozen is proven in
	# _test_sideways.
	for ray in HandModel.FINGERS:
		var p := HandModel.rest_pose()
		var base := _pad_of_chain(ray, p)
		var outward := 1.0 if ray in ["II", "III"] else -1.0
		var target: Vector3 = base + Vector3(5.0 * outward, 0.0, 0.0)
		var r := IK.solve_chain(ray, target, p, {"arm": true})
		var a: Dictionary = r["angles"]
		var ar: Dictionary = r["arm"]
		var dfan := float(a["fan"]) - float(p["fingers"][ray]["fan"])
		var wrist := maxf(absf(float(ar["wrist_flex"])), absf(float(ar["wrist_dev"])))
		var fore := maxf(absf(float(ar["forearm_flex"])), absf(float(ar["forearm_abd"])))
		_ck(float(r["error"]) < 0.05, "%s fan target error %.3f" % [ray, float(r["error"])])
		_ck(dfan * outward >= 1.7,
			"%s fan target moved the fan %.2f deg (outward %.0f)" % [ray, dfan, outward])
		# The wrist may help a little: the little finger's metacarpal is the
		# most tilted of the four, so its fan plane is not the pure sideways
		# direction and a fraction of a degree of deviation takes the rest.
		# The promise is that the hand stays almost still while the finger
		# spreads — a fifth of the fan's own travel is still that.
		_ck(wrist < 0.7, "%s fan target used the wrist %.2f deg" % [ray, wrist])
		_ck(fore < 0.5, "%s fan target used the forearm %.2f deg" % [ray, fore])
		print("   %s fan out: fan %+.1f -> %+.1f (%.2f deg), wrist %.2f, forearm %.2f, %s" % [
			ray, float(p["fingers"][ray]["fan"]), float(a["fan"]), dfan, wrist, fore,
			_chain_text(r)])

	# A grid of directions around the ELBOW at arm's length: every answer must
	# be finite and inside the ROM. Targets outside the shell (closer than the
	# pad's own length or beyond the forearm + finger reach) are allowed to
	# miss; a NaN or an out-of-ROM angle is never allowed.
	var total := 0
	var reached := 0
	for dist in [150.0, 180.0, 220.0, 260.0]:
		for iy in [-1, 0, 1]:
			for iz in [-1, 0, 1]:
				for ix in [-1, 0, 1]:
					if ix == 0 and iy == 0 and iz == 0:
						continue
					var d := Vector3(ix, iy, iz).normalized()
					var target: Vector3 = ArmModel.ELBOW + d * float(dist)
					var r := IK.solve_chain("II", target, p0, {"arm": true})
					total += 1
					if float(r["error"]) < 0.05:
						reached += 1
					_ck(is_finite(float(r["error"])), "grid %s error not finite" % str(target))
					_ck(_arm_in_rom(r["arm"]), "grid %s arm out of ROM" % str(target))
	print("   grid: %d targets, %d reached to 0.05 mm" % [total, reached])
	_ck(reached > total / 2, "grid reached only %d of %d" % [reached, total])

	# Dragging the target from the rest pad to a far pose: every step is
	# solved from the previous pose, so the joints must move smoothly and the
	# pad must stay on the target. One step is allowed to be big and it is
	# not a glitch: when the wrist runs out of travel, the hierarchy can hand
	# the target to the forearm in a single solve. Such a reconfiguration
	# must happen AT the wrist limit and at most once; any other jump would
	# be a snap and fails. The viewer smooths this step over a few frames; the
	# model itself is allowed it.
	var pose := HandModel.rest_pose()
	var prev: Dictionary = pose["arm"]
	var worst_step := 0.0
	var worst_err := 0.0
	var handoffs := 0
	var flex_max := float(ArmModel.ROM["wrist_flex"][1])
	var start := _pad_of_chain("II", pose)
	var end := _pad_of_chain("II", far_pose)
	for i in 25:
		var u := float(i + 1) / 25.0
		var target := start.lerp(end, u)
		var r := IK.solve_chain("II", target, pose, {"arm": true})
		pose = r["pose"]
		worst_err = maxf(worst_err, float(r["error"]))
		var a: Dictionary = pose["arm"]
		# Compare as a fraction of each joint's FULL range: degrees and
		# millimetres then live on one scale, so the elbow's travel is judged
		# like any other level. The share measure cannot be used here — its
		# denominator changes at the rest value (wrist deviation is −35/+20),
		# so a smooth zero crossing would read as a third of the travel and
		# look like a handoff that never happened.
		var step := _range_step(prev, a)
		worst_step = maxf(worst_step, step)
		if step > 25.0:
			handoffs += 1
			_ck(float(a["wrist_flex"]) >= flex_max - 0.5,
				"chain drag reconfigures at wrist_flex %.1f, not at the limit" % float(a["wrist_flex"]))
		prev = a
	_ck(worst_err < 0.05, "chain drag worst error %.2f" % worst_err)
	_ck(handoffs <= 1, "chain drag had %d reconfigurations, expected at most 1" % handoffs)
	print("   drag rest -> far: worst error %.2f mm, largest joint step %.1f%%, %d handoff" % [
		worst_err, worst_step, handoffs])


func _elbow_travel(a: Dictionary) -> float:
	return Vector3(float(a["elbow_x"]), float(a["elbow_y"]),
		float(a["elbow_z"])).length()


# The largest change between two arm states, in percent of each joint's full
# range. Symmetric, unlike the share: the share is measured from the rest value
# and switches its denominator there, which turns a smooth crossing of zero
# into a fake jump.
func _range_step(a: Dictionary, b: Dictionary) -> float:
	var worst := 0.0
	for j in ArmModel.JOINTS:
		var span: float = float(ArmModel.ROM[j][1]) - float(ArmModel.ROM[j][0])
		worst = maxf(worst, absf(float(a.get(j, 0.0)) - float(b.get(j, 0.0))) / span * 100.0)
	for j in ArmModel.ROOT_JOINTS:
		worst = maxf(worst, absf(float(a.get(j, 0.0)) - float(b.get(j, 0.0)))
			/ (2.0 * ArmModel.ELBOW_RANGE) * 100.0)
	return worst


# The author's rule (29.10.2026): a fingertip must reach ANY point, and when
# the rotations run out the elbow travels. The elbow is the dearest level, so
# it stays still for everything the joints above can answer and moves only
# for targets outside the arm's own shell.
func _test_elbow() -> void:
	print("== elbow travel: any point, last resort")
	var rest := HandModel.rest_pose()
	var pad := _pad_of_chain("II", rest)
	var shell := ArmModel.FOREARM_L + pad.length()

	# The old fixed-elbow shell: the wrist on the forearm's sphere plus the
	# pad's own offset. A target inside it must NOT move the elbow.
	for t in [pad, pad + Vector3(0, 0, -30), pad + Vector3(10, 0, 0)]:
		var r := IK.solve_chain("II", t, rest, {"arm": true})
		var e := _elbow_travel(r["arm"])
		_ck(float(r["error"]) < 0.05, "near %s error %.2f" % [str(t), float(r["error"])])
		_ck(e < 1.5, "near %s moved the elbow %.2f mm" % [str(t), e])
		print("   near %s: %s, elbow %.2f mm" % [str(t), _chain_text(r), e])

	# A sphere of targets around the hand: every one must land, including
	# the ones behind the palm and below the elbow that the fixed root could
	# not touch at all.
	var dirs := []
	for ix in [-1, 0, 1]:
		for iy in [-1, 0, 1]:
			for iz in [-1, 0, 1]:
				if ix == 0 and iy == 0 and iz == 0:
					continue
				dirs.append(Vector3(ix, iy, iz).normalized())
	var worst := 0.0
	for d in dirs:
		var t: Vector3 = (d as Vector3) * 300.0
		var r := IK.solve_chain("II", t, rest, {"arm": true})
		worst = maxf(worst, float(r["error"]))
		_ck(float(r["error"]) < 0.2,
			"sphere %s error %.2f (%s)" % [str(t), float(r["error"]), _chain_text(r)])
		_ck(_arm_in_rom(r["arm"]), "sphere %s arm out of ROM" % str(t))
	print("   sphere 300 mm: %d targets, worst error %.2f mm" % [dirs.size(), worst])

	# Outside the old shell the elbow must actually carry the arm, and the
	# pad must still land. The upward directions are outside it by
	# construction: the shell hangs below the origin.
	var far_dirs := [Vector3(0, 1, 0), Vector3(1, 1, 0), Vector3(-1, 1, 0),
		Vector3(0, 1, -1), Vector3(0, 1, 1), Vector3(1, 0.4, -1),
		Vector3(-1, 0.4, -1)]
	var far_worst := 0.0
	var far_moved := 0
	for d in far_dirs:
		var t: Vector3 = (d as Vector3).normalized() * 380.0
		var r := IK.solve_chain("II", t, rest, {"arm": true})
		var e := _elbow_travel(r["arm"])
		far_worst = maxf(far_worst, float(r["error"]))
		if e > 20.0:
			far_moved += 1
		_ck(float(r["error"]) < 0.3,
			"far %s error %.2f (%s)" % [str(t), float(r["error"]), _chain_text(r)])
		_ck(_arm_in_rom(r["arm"]), "far %s arm out of ROM" % str(t))
		print("   far %s: %s, elbow %.0f mm" % [str(t), _chain_text(r), e])
	_ck(far_moved == far_dirs.size(), "the elbow did not take %d of %d far targets" % [
		far_dirs.size() - far_moved, far_dirs.size()])
	print("   far 380 mm: worst error %.2f mm, elbow used on %d of %d" % [
		far_worst, far_moved, far_dirs.size()])
	_ck(shell < 340.0, "the old shell is %.0f mm — the far targets are not outside it" % shell)
