# Measures the new fixed-elbow arm: which targets are reachable, what the
# hierarchy spends on them, and how the fan answers a sideways nudge.
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
	return "err %6.2f it %2d | f %3.0f fan %3.0f wr %3.0f pr %3.0f fo %3.0f | wf %+6.1f wd %+6.1f pr %+6.1f ff %+6.1f fa %+6.1f" % [
		float(r["error"]), int(r["iterations"]),
		float(lev.get("finger", 0)), float(lev.get("fan", 0)),
		float(lev.get("wrist", 0)), float(lev.get("pronation", 0)),
		float(lev.get("forearm", 0)),
		float(a["wrist_flex"]), float(a["wrist_dev"]), float(a["pronation"]),
		float(a["forearm_flex"]), float(a["forearm_abd"])]


func _report(tag: String, ray: String, target: Vector3, rest: Dictionary) -> Dictionary:
	var r: Dictionary = IK.solve_chain(ray, target, rest, {"arm": true})
	print("  %-22s %s" % [tag, _text(r)])
	return r


func _init() -> void:
	var rest := HandModel.rest_pose()
	var pad := _pad("II", rest)
	var out := (pad - Vector3.ZERO).normalized()
	print("rest II pad %s out %s" % [str(pad), str(out)])
	print("elbow %s dist %.1f" % [str(ArmModel.ELBOW), (pad - ArmModel.ELBOW).length()])

	print("== pure wrist flex")
	for q in [-40.0, -20.0, 20.0, 40.0]:
		var p := rest.duplicate(true)
		p["arm"]["wrist_flex"] = q
		_report("wf %+.0f" % q, "II", _pad("II", p), rest)
	print("== pure wrist dev")
	for q in [-25.0, -10.0, 10.0, 20.0]:
		var p := rest.duplicate(true)
		p["arm"]["wrist_dev"] = q
		_report("wd %+.0f" % q, "II", _pad("II", p), rest)
	print("== pure pronation")
	for q in [-60.0, -30.0, 30.0, 60.0]:
		var p := rest.duplicate(true)
		p["arm"]["pronation"] = q
		_report("pron %+.0f" % q, "II", _pad("II", p), rest)
	print("== pure forearm flex")
	for q in [-60.0, -30.0, 30.0, 60.0]:
		var p := rest.duplicate(true)
		p["arm"]["forearm_flex"] = q
		_report("ff %+.0f" % q, "II", _pad("II", p), rest)
	print("== pure forearm abd")
	for q in [-60.0, -30.0, 30.0, 60.0]:
		var p := rest.duplicate(true)
		p["arm"]["forearm_abd"] = q
		_report("fa %+.0f" % q, "II", _pad("II", p), rest)

	print("== sideways fan, II")
	for dx in [5.0, -5.0, 10.0, -10.0, 15.0, -15.0]:
		_report("dx %+.0f" % dx, "II", pad + Vector3(dx, 0, 0), rest)
	print("== sideways fan, V")
	var pad5 := _pad("V", rest)
	for dx in [5.0, -5.0, 10.0, -10.0]:
		_report("dx %+.0f" % dx, "V", pad5 + Vector3(dx, 0, 0), rest)

	print("== thumb")
	var tpad := HandModel.thumb_pad(HandModel.thumb_fk(0.0))
	for d in [Vector3(0, 0, 0), Vector3(0, 0, -30), Vector3(60, 0, 0),
			Vector3(0, -60, 0), Vector3(120, -80, -80), Vector3(0, 120, 0),
			Vector3(0, 0, -80), Vector3(-60, 30, 0)]:
		_report("d %s" % str(d), "I", tpad + d, rest)

	print("== targets from random poses (reachable by construction)")
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261028
	var ok := 0
	var total := 0
	var worst := 0.0
	for i in 120:
		var p := HandModel.rest_pose()
		var ray: String = HandModel.FINGERS[i % 4]
		var sh := [rng.randf_range(-0.6, 0.9), rng.randf_range(-0.6, 0.9),
			rng.randf_range(-0.6, 0.9), rng.randf_range(-0.8, 0.8)]
		p["fingers"][ray] = IK.angles_of_shares(ray, sh)
		for j in ArmModel.JOINTS:
			p["arm"][j] = rng.randf_range(float(ArmModel.ROM[j][0]) * 0.7,
				float(ArmModel.ROM[j][1]) * 0.7)
		var target := _pad(ray, p)
		var r := IK.solve_chain(ray, target, rest, {"arm": true})
		total += 1
		worst = maxf(worst, float(r["error"]))
		if float(r["error"]) < 0.5:
			ok += 1
		elif total - ok <= 12:
			print("  MISS %s target %s -> %s" % [ray, str(target), _text(r)])
	print("  %d/%d reached <0.5 mm, worst %.2f mm" % [ok, total, worst])

	print("== grid around the elbow at 100/160/220/280")
	for dist in [100.0, 160.0, 220.0, 280.0]:
		var reached := 0
		var n := 0
		for iy in [-1, 0, 1]:
			for iz in [-1, 0, 1]:
				for ix in [-1, 0, 1]:
					if ix == 0 and iy == 0 and iz == 0:
						continue
					var d := Vector3(ix, iy, iz).normalized()
					var target: Vector3 = ArmModel.ELBOW + d * dist
					var r := IK.solve_chain("II", target, rest, {"arm": true})
					n += 1
					if float(r["error"]) < 0.5:
						reached += 1
		print("  dist %5.0f: %d/%d" % [dist, reached, n])
	quit()
