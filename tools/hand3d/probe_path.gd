# Where along the L Alt path does the other hand get hit, and how much of it is
# the path's own clearance lift? Prints, per sample: the lift the guard adds,
# the worst cross-hand penetration and the left thumb's joints in world space.
extends SceneTree
const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")
const IK := preload("res://ik.gd")
const Kbd3D := preload("res://kbd3d.gd")
const ClickPath := preload("res://click_path.gd")
const HomePose := preload("res://home_pose.gd")

const ROOTS := {"L": -72.51, "R": 43.94}
const KEY_HOVER := 12.0
const STEPS := 24
const THUMB_R := [11.8, 10.8, 9.6, 6.6]
const MC_R := 10.0
var _keys: Array

func _init() -> void:
	_keys = Kbd3D.keys()
	var side := "L"
	var want := "Alt"
	var idx := Kbd3D.index_of(_keys, want)
	var r: Rect2 = _keys[idx]["r"]
	var hx := r.get_center().x - 0.6 * r.size.x * 0.5
	var ray := String(Kbd3D.hand_finger(want, hx)[1])
	var root_x: float = ROOTS[side]
	var deep := Vector3(hx - root_x, r.get_center().y,
		Kbd3D.FACE_Z - Kbd3D.TRAVEL)
	var home: Dictionary = HomePose.build(side, root_x)
	var idle: Dictionary = HomePose.build("R", ROOTS["R"])
	var pr: Dictionary = IK.solve_chain(ray, deep, home,
		{"arm": true, "thumb_dof": 4, "clear_z": Kbd3D.FACE_Z,
		"clear_w": 100.0, "dir_w": 30.0, "foreign": _foreign(idle, "R", side, root_x),
		"hover_z": Kbd3D.FACE_Z + KEY_HOVER})
	var pp: Dictionary = pr["pose"]
	var ppad := _pad(ray, pp)
	var lift := maxf(0.0, (Kbd3D.FACE_Z + KEY_HOVER) - ppad.z)
	var hp: Dictionary = pp.duplicate(true)
	hp["arm"]["elbow_z"] = float(hp["arm"].get("elbow_z", 0.0)) + lift
	var path: Dictionary = ClickPath.build(home, hp, pp, 0.35, 0.16, 0.12, 0.40,
		{"ray": ray, "clear_z": Kbd3D.FACE_Z,
		"key_rects": _local_keys(side, root_x), "own": idx})
	var total := float(path["total"])
	var idle_caps := _caps(idle, "R")
	print("lift %.2f total %.2f" % [lift, total])
	for i in STEPS + 1:
		var t := total * float(i) / float(STEPS)
		var p: Dictionary = ClickPath.at(path, t)
		var caps := _caps(p, side)
		var c := _cross(caps, idle_caps)
		var xf := ArmModel.hand_transform(p["arm"])
		var tp: PackedVector3Array = HandModel.thumb_fk(HandModel.thumb_of_pose(p))["pts"]
		var e: Vector3 = ArmModel.hand_transform(hp["arm"]) * HandModel.finger_pad(ray,
			HandModel.finger_fk(ray, hp["fingers"][ray]))
		var pad: Vector3 = xf * HandModel.finger_pad(ray,
			HandModel.finger_fk(ray, p["fingers"][ray]))
		var raw: Dictionary = p.duplicate(true)
		raw["arm"]["elbow_z"] = float(raw["arm"]["elbow_z"]) - _lift_of(p, ray, side, root_x, idx)
		var per := ""
		var xr := ArmModel.hand_transform(raw["arm"])
		for f in HandModel.FINGERS:
			per += " %s%4.1f" % [f, IK._finger_violation(xr, f, raw["fingers"][f], 2.0)]
		var tv := 0.0
		var tpts2: PackedVector3Array = HandModel.thumb_fk(HandModel.thumb_of_pose(raw))["pts"]
		var tr := [11.8, 10.8, 9.6, 6.6]
		for j in 4:
			var w: Vector3 = xr * tpts2[j]
			tv = maxf(tv, IK._joint_violation(w.x, w.y, w.z + 0.5, float(tr[j]), Kbd3D.FACE_Z))
		print("t %5.3f  lift %5.2f  padz %7.2f  worst %6.2f %-14s |%s  I%4.1f  thumb IP z %6.1f" % [
			t, _lift_of(p, ray, side, root_x, idx), pad.z, float(c[0]), String(c[1]),
			per, tv, (_world(side, xf * tp[2])).z])
	quit(0)

func _lift_of(p: Dictionary, ray: String, side: String, root_x: float, idx: int) -> float:
	var cz := Kbd3D.FACE_Z
	var l := IK.clearance(ray, p, cz, Rect2(), 2.0)
	l = maxf(l, IK.clearance(ray, p, cz, Rect2(), 2.0))
	return l

func _pad(ray: String, p: Dictionary) -> Vector3:
	var xf := ArmModel.hand_transform(p.get("arm", {}))
	return xf * HandModel.finger_pad(ray, HandModel.finger_fk(ray, p["fingers"][ray]))

func _local_keys(side: String, root_x: float) -> Array:
	var out := []
	for k in _keys:
		var r: Rect2 = k["r"]
		out.append(Rect2(r.position.x - root_x, r.position.y, r.size.x, r.size.y))
	return out

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
			cs.append({"a": _world(side, xf * pts[i]), "b": _world(side, xf * pts[i + 1]),
				"r": maxf(float(rr[i]), float(rr[i + 1])), "seg": i, "tag": "%s_%d" % [ray, i]})
		out[ray] = cs
	var tfk: Dictionary = HandModel.thumb_fk(HandModel.thumb_of_pose(pose))
	var tpts: PackedVector3Array = tfk["pts"]
	var tc := []
	for i in 3:
		tc.append({"a": _world(side, xf * tpts[i]), "b": _world(side, xf * tpts[i + 1]),
			"r": maxf(float(THUMB_R[i]), float(THUMB_R[i + 1])), "seg": i, "tag": "I_%d" % i})
	out["I"] = tc
	var mc := []
	for ray in HandModel.FINGERS:
		mc.append({"a": _world(side, xf * HandModel.MC_BASE[ray]),
			"b": _world(side, xf * HandModel.metacarpal_head(ray)),
			"r": MC_R, "seg": 0, "tag": "MC_%s" % ray})
	out["MC"] = mc
	return out

func _foreign(idle: Dictionary, other: String, side: String, root_x: float) -> Array:
	var caps := _caps(idle, other)
	var out := []
	for ray in caps:
		for c in caps[ray]:
			var a: Vector3 = c["a"]
			var b: Vector3 = c["b"]
			out.append({"a": Vector3(a.x - root_x, a.y, a.z),
				"b": Vector3(b.x - root_x, b.y, b.z), "r": float(c["r"])})
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

func _cross(a: Dictionary, b: Dictionary) -> Array:
	var worst := 0.0
	var tag := ""
	var tags: Array = ["II", "III", "IV", "V", "I", "MC"]
	for ra in tags:
		for ca in a[ra]:
			for rb in tags:
				for cb in b[rb]:
					var d := _seg_dist(ca["a"], ca["b"], cb["a"], cb["b"])
					var p: float = maxf(0.0, float(ca["r"]) + float(cb["r"]) - d)
					if p > worst:
						worst = p
						tag = "%s/%s" % [ca["tag"], cb["tag"]]
	return [worst, tag]
