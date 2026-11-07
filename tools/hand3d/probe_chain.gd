# Measures candidate targets for the rewritten chain tests: what the
# hierarchy spends on near/mid/far targets built from POSES (reachable by
# construction), the grid around the elbow, and the sideways nudge.
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")
const IK := preload("res://ik.gd")


func _pad(ray: String, p: Dictionary) -> Vector3:
	var xf := ArmModel.hand_transform(p.get("arm", {}))
	if ray == "I":
		return xf * HandModel.thumb_pad(HandModel.thumb_fk(float(p["thumb_f"])))
	return xf * HandModel.finger_pad(ray, HandModel.finger_fk(ray, p["fingers"][ray]))


func _text(r: Dictionary) -> String:
	var lev: Dictionary = r["levels"]
	var a: Dictionary = r["arm"]
	return "err %6.2f | f %3.0f fan %3.0f wr %3.0f pr %3.0f fo %3.0f | wf %+6.1f wd %+6.1f pr %+6.1f ff %+6.1f fa %+6.1f" % [
		float(r["error"]),
		float(lev.get("finger", 0)), float(lev.get("fan", 0)),
		float(lev.get("wrist", 0)), float(lev.get("pronation", 0)),
		float(lev.get("forearm", 0)),
		float(a["wrist_flex"]), float(a["wrist_dev"]), float(a["pronation"]),
		float(a["forearm_flex"]), float(a["forearm_abd"])]


func _report(tag: String, ray: String, target: Vector3, rest: Dictionary) -> Dictionary:
	var r: Dictionary = IK.solve_chain(ray, target, rest, {"arm": true})
	print("  %-28s %s" % [tag, _text(r)])
	return r


func _pose_with(arm: Dictionary) -> Dictionary:
	var p := HandModel.rest_pose()
	for j in arm:
		p["arm"][j] = float(arm[j])
	return p


func _init() -> void:
	var rest := HandModel.rest_pose()
	for ray in HandModel.FINGERS:
		print("rest %s pad %s" % [ray, str(_pad(ray, rest))])
	var tpad := HandModel.thumb_pad(HandModel.thumb_fk(0.0))
	print("rest I pad %s" % str(tpad))

	print("== near: 10 mm behind the pad (finger)")
	var pad := _pad("II", rest)
	var out := (pad - Vector3.ZERO).normalized()
	_report("near -out*10", "II", pad - out * 10.0, rest)

	print("== mid: 30 mm to the palm (-z)")
	_report("mid z-30", "II", pad + Vector3(0, 0, -30), rest)

	print("== far from poses")
	for arm in [
			{"forearm_abd": 30.0},
			{"forearm_abd": -30.0},
			{"forearm_flex": -30.0},
			{"forearm_flex": 30.0},
			{"forearm_abd": 35.0, "forearm_flex": -25.0},
			{"wrist_flex": 40.0},
			{"wrist_dev": 15.0},
			{"wrist_flex": 40.0, "forearm_abd": 20.0},
			]:
		var target := _pad("II", _pose_with(arm))
		_report("pose %s" % str(arm), "II", target, rest)

	print("== grid around the elbow")
	for dist in [90.0, 120.0, 150.0, 180.0, 220.0, 260.0]:
		var reached := 0
		var n := 0
		for iy in [-1, 0, 1]:
			for iz in [-1, 0, 1]:
				for ix in [-1, 0, 1]:
					if ix == 0 and iy == 0 and iz == 0:
						continue
					var d := Vector3(ix, iy, iz).normalized()
					var target: Vector3 = ArmModel.ELBOW + d * float(dist)
					var r: Dictionary = IK.solve_chain("II", target, rest, {"arm": true})
					n += 1
					if float(r["error"]) < 0.5:
						reached += 1
		print("  dist %5.0f: %d/%d" % [dist, reached, n])

	print("== sideways +-5 mm from rest, per finger")
	for ray in HandModel.FINGERS:
		var base := _pad(ray, rest)
		for dx in [5.0, -5.0]:
			var r := _report("%s dx %+.0f" % [ray, dx], ray, base + Vector3(dx, 0, 0), rest)
			var a: Dictionary = r["angles"]
			var da: Dictionary = r["arm"]
			print("      fan %+.2f deg | wf %+.2f wd %+.2f pron %+.2f ff %+.2f fa %+.2f" % [
				float(a["fan"]) - float(rest["fingers"][ray]["fan"]),
				float(da["wrist_flex"]), float(da["wrist_dev"]), float(da["pronation"]),
				float(da["forearm_flex"]), float(da["forearm_abd"])])

	print("== far lateral poses")
	for arm in [
			{"forearm_abd": 45.0},
			{"forearm_abd": -45.0},
			{"forearm_abd": 60.0},
			{"forearm_abd": -60.0},
			{"forearm_flex": -45.0},
			{"forearm_flex": 45.0},
			]:
		var target := _pad("II", _pose_with(arm))
		_report("pose %s" % str(arm), "II", target, rest)

	print("== thumb targets")
	var trest := HandModel.thumb_pad(HandModel.thumb_fk(0.0))
	for t in [trest + Vector3(0, 0, -30), trest + Vector3(0, -60, 0),
			trest + Vector3(60, 0, 0), trest + Vector3(-60, 30, 0),
			Vector3(120, -80, -80), Vector3(0, 0, -80)]:
		_report("t %s" % str(t), "I", t, rest)
	for arm in [{"forearm_abd": 30.0}, {"forearm_abd": -30.0}, {"forearm_flex": -30.0}]:
		var p := _pose_with(arm)
		var t: Vector3 = ArmModel.hand_transform(p["arm"]) * trest
		_report("t pose %s" % str(arm), "I", t, rest)

	print("== drag candidates: handoffs")
	for end in [
			Vector3(0, -80, -80),
			_pad("II", _pose_with({"forearm_abd": 60.0})),
			_pad("II", _pose_with({"forearm_flex": -60.0})),
			_pad("II", _pose_with({"forearm_abd": 35.0, "forearm_flex": -25.0})),
			]:
		var pose := HandModel.rest_pose()
		var prev: Dictionary = pose["arm"]
		var worst_step := 0.0
		var worst_err := 0.0
		var last_err := 0.0
		var handoffs := 0
		var start := _pad("II", pose)
		for i in 25:
			var u := float(i + 1) / 25.0
			var target := start.lerp(end, u)
			var r: Dictionary = IK.solve_chain("II", target, pose, {"arm": true})
			pose = r["pose"]
			worst_err = maxf(worst_err, float(r["error"]))
			last_err = float(r["error"])
			var a: Dictionary = pose["arm"]
			var step := 0.0
			for j in ArmModel.JOINTS:
				step = maxf(step, absf(float(a[j]) - float(prev[j])))
			worst_step = maxf(worst_step, step)
			if step > 20.0:
				handoffs += 1
				print("   step %.1f at u %.2f: %s" % [step, u, _text(r)])
			prev = a
		print("  end %s: worst err %.2f, last %.2f, step %.1f, handoffs %d" % [
			str(end), worst_err, last_err, worst_step, handoffs])
	quit()
