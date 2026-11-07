# Is the TEST's own rule violated by the approved home pose? Measures the
# same pairs intersect_test checks, on the rest pose of both hands (no click at
# all). A pair that already crosses at rest cannot be fixed by any solver — the
# rule itself is then wrong for that pair.
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")
const Kbd3D := preload("res://kbd3d.gd")
const HomePose := preload("res://home_pose.gd")

const ROOTS := {"L": -72.51, "R": 43.94}
const THUMB_R := [11.8, 10.8, 9.6, 6.6]
const MC_R := 10.0
const APART := [["II", "IV"], ["II", "V"], ["III", "V"]]
const ADJACENT := [["II", "III"], ["III", "IV"], ["IV", "V"]]


func _world(side: String, q: Vector3) -> Vector3:
	if side == "R":
		return Vector3(float(ROOTS[side]) - q.x, q.y, q.z)
	return Vector3(float(ROOTS[side]) + q.x, q.y, q.z)


func _caps(pose: Dictionary, side: String) -> Dictionary:
	var out := {}
	var xf := ArmModel.hand_transform(pose.get("arm", {}))
	for ray in HandModel.FINGERS:
		var fk: Dictionary = HandModel.finger_fk(ray, pose["fingers"][ray])
		var pts: PackedVector3Array = fk["pts"]
		var rr: Array = HandModel.SKIN_R[ray]
		var cs := []
		for i in 3:
			cs.append({"a": _world(side, xf * pts[i]),
				"b": _world(side, xf * pts[i + 1]),
				"r": maxf(float(rr[i]), float(rr[i + 1])),
				"seg": i, "tag": "%s_%d" % [ray, i]})
		out[ray] = cs
	var tfk: Dictionary = HandModel.thumb_fk(HandModel.thumb_of_pose(pose))
	var tpts: PackedVector3Array = tfk["pts"]
	var tc := []
	for i in 3:
		tc.append({"a": _world(side, xf * tpts[i]),
			"b": _world(side, xf * tpts[i + 1]),
			"r": maxf(float(THUMB_R[i]), float(THUMB_R[i + 1])),
			"seg": i, "tag": "I_%d" % i})
	out["I"] = tc
	var mc := []
	for ray in HandModel.FINGERS:
		mc.append({"a": _world(side, xf * HandModel.MC_BASE[ray]),
			"b": _world(side, xf * HandModel.metacarpal_head(ray)),
			"r": MC_R, "seg": 0, "tag": "MC_%s" % ray})
	out["MC"] = mc
	return out


func _seg_dist(p1: Vector3, q1: Vector3, p2: Vector3, q2: Vector3) -> float:
	var d1 := q1 - p1
	var d2 := q2 - p2
	var r := p1 - p2
	var a := d1.dot(d1)
	var e := d2.dot(d2)
	var f := d2.dot(r)
	var s := 0.0
	var t := 0.0
	if a <= 1e-12 and e <= 1e-12:
		return r.length()
	if a <= 1e-12:
		t = clampf(f / e, 0.0, 1.0)
	elif e <= 1e-12:
		s = clampf(-d1.dot(r) / a, 0.0, 1.0)
	else:
		var c := d1.dot(r)
		var b := d1.dot(d2)
		var denom := a * e - b * b
		if absf(denom) > 1e-12:
			s = clampf((b * f - c * e) / denom, 0.0, 1.0)
		t = (b * s + f) / e
		if t < 0.0:
			t = 0.0
			s = clampf(-c / a, 0.0, 1.0)
		elif t > 1.0:
			t = 1.0
			s = clampf((b - c) / a, 0.0, 1.0)
	return (p1 + d1 * s).distance_to(p2 + d2 * t)


func _pen(ca: Dictionary, cb: Dictionary) -> float:
	return maxf(0.0, float(ca["r"]) + float(cb["r"]) -
		_seg_dist(ca["a"], ca["b"], cb["a"], cb["b"]))


func _same(caps: Dictionary) -> void:
	var worst := 0.0
	var tag := ""
	for pair in APART:
		for ca in caps[pair[0]]:
			for cb in caps[pair[1]]:
				var p := _pen(ca, cb)
				if p > worst:
					worst = p
					tag = "%s/%s" % [ca["tag"], cb["tag"]]
	for pair in ADJACENT:
		for ca in caps[pair[0]]:
			if int(ca["seg"]) < 1:
				continue
			for cb in caps[pair[1]]:
				if int(cb["seg"]) < 1:
					continue
				var p := _pen(ca, cb)
				if p > worst:
					worst = p
					tag = "%s/%s" % [ca["tag"], cb["tag"]]
	for ray in HandModel.FINGERS:
		for ca in caps["I"]:
			for cb in caps[ray]:
				var p := _pen(ca, cb)
				if p > worst:
					worst = p
					tag = "I/%s" % cb["tag"]
	print("  own  worst %.2f  %s" % [worst, tag])


func _cross(a: Dictionary, b: Dictionary) -> void:
	var worst := 0.0
	var tag := ""
	var tags: Array = []
	tags.append_array(HandModel.FINGERS)
	tags.append("I")
	tags.append("MC")
	for ra in tags:
		for ca in a[ra]:
			for rb in tags:
				for cb in b[rb]:
					var p := _pen(ca, cb)
					if p > worst:
						worst = p
						tag = "%s/%s" % [ca["tag"], cb["tag"]]
	print("  hands worst %.2f  %s" % [worst, tag])


func _init() -> void:
	var l: Dictionary = HomePose.build("L", float(ROOTS["L"]))
	var r: Dictionary = HomePose.build("R", float(ROOTS["R"]))
	var cl := _caps(l, "L")
	var cr := _caps(r, "R")
	print("=== rest pose")
	print("L:")
	_same(cl)
	print("R:")
	_same(cr)
	print("L/R:")
	_cross(cl, cr)
	quit(0)
