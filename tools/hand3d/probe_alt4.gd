# Which capsule pair is the constant 0.79 mm on L Alt?
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")
const IK := preload("res://ik.gd")
const Kbd3D := preload("res://kbd3d.gd")
const HomePose := preload("res://home_pose.gd")

const ROOTS := {"L": -72.51, "R": 43.94}
const THUMB_R := [11.8, 10.8, 9.6, 6.6]
const MC_R := 10.0


func _init() -> void:
	var side := "L"
	var want := "Alt"
	var keys := Kbd3D.keys()
	var idx := Kbd3D.index_of(keys, want)
	var key: Dictionary = keys[idx]
	var r: Rect2 = key["r"]
	var hit := Vector2(r.get_center().x - 0.6 * r.size.x * 0.5,
		r.get_center().y)
	var ray := String(Kbd3D.hand_finger(want, hit.x)[1])
	var root_x: float = ROOTS[side]
	var deep := Vector3(hit.x - root_x, hit.y, Kbd3D.FACE_Z - Kbd3D.TRAVEL)
	var home: Dictionary = HomePose.build(side, root_x)
	var other := "R"
	var idle: Dictionary = HomePose.build(other, float(ROOTS[other]))
	var pr: Dictionary = IK.solve_chain(ray, deep, home,
		{"arm": true, "thumb_dof": 4, "clear_z": Kbd3D.FACE_Z,
		"clear_w": 100.0, "dir_w": 30.0,
		"foreign": _caps_foreign(idle, other, side, root_x),
		"hover_z": Kbd3D.FACE_Z + 12.0})
	var p: Dictionary = pr["pose"]
	var xf := ArmModel.hand_transform(p["arm"])
	print("thumb %s arm %s" % [str(HandModel.thumb_of_pose(p)), str(p["arm"])])
	print("idle thumb %s" % str(HandModel.thumb_of_pose(idle)))
	var a: Dictionary = HandModel.thumb_of_pose(p).duplicate()
	for abd in [-25.0, 0.0, 10.0]:
		a["cmc_abd"] = abd
		var tpts: PackedVector3Array = HandModel.thumb_fk(a)["pts"]
		var caps := _caps(idle, other)
		var worst := 0.0
		var tag := ""
		for i in 3:
			var q := _w(side, root_x, xf * tpts[i])
			var q2 := _w(side, root_x, xf * tpts[i + 1])
			var rr := maxf(float(THUMB_R[i]), float(THUMB_R[i + 1]))
			for ray2 in caps:
				for c in caps[ray2]:
					var d := _seg_dist(q, q2, c["a"], c["b"])
					var pen := rr + float(c["r"]) - d
					if pen > worst:
						worst = pen
						tag = "I_%d/%s" % [i, c["tag"]]
		print("abd %6.1f worst %5.2f %s" % [abd, worst, tag])
	quit(0)


func _caps(pose: Dictionary, side: String) -> Dictionary:
	var out := {}
	var xf := ArmModel.hand_transform(pose.get("arm", {}))
	for ray in HandModel.FINGERS:
		var fk: Dictionary = HandModel.finger_fk(ray, pose["fingers"][ray])
		var pts: PackedVector3Array = fk["pts"]
		var rr: Array = HandModel.SKIN_R[ray]
		var cs := []
		for i in 3:
			cs.append({"a": _w(side, float(ROOTS[side]), xf * pts[i]),
				"b": _w(side, float(ROOTS[side]), xf * pts[i + 1]),
				"r": maxf(float(rr[i]), float(rr[i + 1])),
				"tag": "%s_%d" % [ray, i]})
		out[ray] = cs
	var tpts: PackedVector3Array = HandModel.thumb_fk(
		HandModel.thumb_of_pose(pose))["pts"]
	var tc := []
	for i in 3:
		tc.append({"a": _w(side, float(ROOTS[side]), xf * tpts[i]),
			"b": _w(side, float(ROOTS[side]), xf * tpts[i + 1]),
			"r": maxf(float(THUMB_R[i]), float(THUMB_R[i + 1])),
			"tag": "I_%d" % i})
	out["I"] = tc
	var mc := []
	for ray in HandModel.FINGERS:
		mc.append({"a": _w(side, float(ROOTS[side]), xf * HandModel.MC_BASE[ray]),
			"b": _w(side, float(ROOTS[side]), xf * HandModel.metacarpal_head(ray)),
			"r": MC_R, "tag": "MC_%s" % ray})
	out["MC"] = mc
	return out


func _caps_foreign(idle: Dictionary, other: String, side: String,
		root_x: float) -> Array:
	var caps := _caps(idle, other)
	var sgn := -1.0 if side == "R" else 1.0
	var out := []
	for ray in caps:
		for c in caps[ray]:
			var a: Vector3 = c["a"]
			var b: Vector3 = c["b"]
			out.append({"a": Vector3((a.x - root_x) * sgn, a.y, a.z),
				"b": Vector3((b.x - root_x) * sgn, b.y, b.z),
				"r": float(c["r"])})
	return out


func _w(side: String, root_x: float, q: Vector3) -> Vector3:
	if side == "R":
		return Vector3(root_x - q.x, q.y, q.z)
	return Vector3(root_x + q.x, q.y, q.z)


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
	var c1 := p1 + d1 * s
	var c2 := p2 + d2 * t
	return c1.distance_to(c2)
