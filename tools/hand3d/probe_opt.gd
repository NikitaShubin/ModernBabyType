# Brute-force the cheapest zero-residual arm pose for a target: sample the
# wrist sphere, aim the hand, keep what fits the ROM, and report the best.
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


func _ok(arm: Dictionary) -> bool:
	var s := ArmModel.shares_of(arm)
	for v in s:
		if absf(float(v)) > 1.0001:
			return false
	return true


func _search(target: Vector3, pad: Vector3, n: int) -> void:
	var pad_len := pad.length()
	var from := pad / pad_len
	var best := {}
	var best_c := INF
	var valid := 0
	var bad_wrist := 0
	var bad_rom := 0
	var first_bad := ""
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
			bad_wrist += 1
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
		if not _ok(arm):
			bad_rom += 1
			if first_bad == "":
				first_bad = "w %s arm %s" % [str(w), str(arm)]
			continue
		valid += 1
		var c := _cost(arm)
		if c < best_c:
			best_c = c
			best = arm
	print("target %s: %d valid, %d bad wrist, %d bad rom, best cost %.2f %s" % [
		str(target), valid, bad_wrist, bad_rom, best_c, str(best)])
	print("  first bad: %s" % first_bad)


func _init() -> void:
	var rest := HandModel.rest_pose()
	var pad := HandModel.finger_pad("II", HandModel.finger_fk("II", rest["fingers"]["II"]))
	for t in [Vector3(0, -80, -80), Vector3(150, -100, -50), Vector3(-100, -100, -100)]:
		_search(t, pad, 600)
		var r: Dictionary = IK.solve_chain("II", t, rest, {"arm": true})
		print("  solver err %.2f cost %.2f" % [float(r["error"]),
			float(_cost(r["arm"]))])
	quit()
