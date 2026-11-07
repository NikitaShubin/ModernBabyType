# For one far target and one finger curl, samples the wrist sphere and prints
# the cheapest arm poses whose wrist angles fit the ROM. This tells whether a
# relaxed pose exists at all or the target really demands the limits.
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")
const IK := preload("res://ik.gd")


func _cost(arm: Dictionary) -> float:
	var s := ArmModel.shares_of(arm)
	var c := 0.0
	for i in ArmModel.JOINTS.size():
		var j: String = ArmModel.JOINTS[i]
		c += float(ArmModel.WEIGHT[j]) * float(s[i]) * float(s[i])
	return c


func _search(tag: String, target: Vector3, curl: float, n: int) -> void:
	var rest := HandModel.rest_pose()
	var sh := [curl, curl, curl, 0.0]
	var pad_local := HandModel.finger_pad("II",
		HandModel.finger_fk("II", IK.angles_of_shares("II", sh)))
	var pad_len := pad_local.length()
	var from := pad_local / pad_len
	var best := []
	var valid := 0
	var bad_rom := 0
	for i in n:
		var z := 1.0 - 2.0 * (float(i) + 0.5) / float(n)
		var rr := sqrt(maxf(1.0 - z * z, 0.0))
		var phi := float(i) * PI * (3.0 - sqrt(5.0))
		var dir := Vector3(rr * cos(phi), z, rr * sin(phi))
		var w := target + dir * pad_len
		var arm := ArmModel.seed_for(w)
		var f := ArmModel.frames(arm)
		var ww: Vector3 = f["wrist"]
		if ww.distance_to(w) > 1.0:
			continue
		var aim := target - ww
		if aim.length_squared() < 1e-9:
			continue
		var r_el: Basis = f["r_el"]
		var to := (r_el.inverse() * aim).normalized()
		var axis := from.cross(to)
		var r := Basis.IDENTITY
		if axis.length_squared() > 1e-9:
			r = Basis(axis.normalized(), acos(clampf(from.dot(to), -1.0, 1.0)))
		arm["pronation"] = rad_to_deg(atan2(-r.x.z, r.x.x))
		arm["wrist_dev"] = rad_to_deg(-asin(clampf(r.x.y, -1.0, 1.0)))
		arm["wrist_flex"] = rad_to_deg(atan2(r.z.y, r.y.y))
		var s := ArmModel.shares_of(arm)
		var ok := true
		for v in s:
			if absf(float(v)) > 1.0001:
				ok = false
		if not ok:
			bad_rom += 1
			continue
		valid += 1
		var c := _cost(arm)
		best.append([c, arm, w])
	best.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	print("%s curl %.1f pad_len %.1f: %d valid, %d bad rom" % [tag, curl, pad_len,
		valid, bad_rom])
	for k in mini(4, best.size()):
		var arm: Dictionary = best[k][1]
		var lv := ArmModel.levels(arm)
		print("  #%d cost %.2f | fl %.0f dv %.0f pr %.0f el %.0f tw %.0f sf %.0f sa %.0f | %s" % [
			k, float(best[k][0]), float(lv.get("wrist_flex", 0)), float(lv.get("wrist_dev", 0)),
			float(lv.get("pronation", 0)), float(lv.get("elbow", 0)),
			float(lv.get("shoulder_twist", 0)), float(lv.get("shoulder_flex", 0)),
			float(lv.get("shoulder_abd", 0)), str(arm)])


func _init() -> void:
	for c in [0.0, 0.3, 0.6, 0.9]:
		_search("F far", Vector3(0, -80, -80), c, 800)
	_search("G side", Vector3(150, -100, -50), 0.3, 800)
	quit()
