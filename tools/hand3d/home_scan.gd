# The home target is at the EDGE of the thumb's reachable set: a full scan of
# the four joints finds one pose within 1 mm, and that pose hooks the IP joint
# inboard (world x -5.0 / +9.0), so the two middle phalanges cross by 7.4 mm.
# The pad's own numbers (41 mm apart) never saw it.
#
# The reach is not a property of the thumb alone — the hand's PITCH, YAW and
# PRONATION decide where the space bar sits in the thumb's own frame. This
# probe rebuilds the whole home pose for a grid of placements and scores each
# by (1) the four fingers' pad errors and (2) the two thumbs' FLESH gap, the
# capsule distance that the intersection test uses.
#
#   mbt-godot --headless --path /work/tools/hand3d --script res://home_scan.gd
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")
const IK := preload("res://ik.gd")
const Kbd3D := preload("res://kbd3d.gd")
const HomePose := preload("res://home_pose.gd")

const ROOTS := {"L": -72.51, "R": 43.94}
const THUMB_R := [11.8, 10.8, 9.6, 6.6]
const LABELS := {
	"L": {"II": "а", "III": "в", "IV": "ы", "V": "ф"},
	"R": {"II": "о", "III": "л", "IV": "д", "V": "ж"},
}

var _keys: Array


func _world(side: String, q: Vector3) -> Vector3:
	if side == "R":
		return Vector3(float(ROOTS[side]) - q.x, q.y, q.z)
	return Vector3(float(ROOTS[side]) + q.x, q.y, q.z)


func _pad(side: String, ray: String, p: Dictionary) -> Vector3:
	var xf := ArmModel.hand_transform(p.get("arm", {}))
	if ray == "I":
		return _world(side, xf * HandModel.thumb_pad(HandModel.thumb_fk(
			HandModel.thumb_of_pose(p))))
	return _world(side, xf * HandModel.finger_pad(ray,
		HandModel.finger_fk(ray, p["fingers"][ray])))


func _build(side: String, arm: Dictionary) -> Dictionary:
	var p := HandModel.rest_pose()
	p["arm"] = arm.duplicate(true)
	p["thumb_f"] = 0.0
	p["thumb"] = HandModel.thumb_at(0.0)
	p["thumb_dof"] = 4
	for ray in ["II", "III", "IV", "V", "I"]:
		var r: Dictionary = IK.solve_chain(ray, HomePose.target(side, ray,
			float(ROOTS[side])), p, HomePose._opts(ray))
		p = r["pose"]
	return p


# The four fingers' worst error in x and z (depth along the key is free).
func _fingers_err(side: String, p: Dictionary) -> float:
	var worst := 0.0
	for ray in ["II", "III", "IV", "V"]:
		var label: String = (LABELS[side] as Dictionary)[ray]
		var c: Vector3 = Kbd3D.centre(_keys[Kbd3D.index_of(_keys, label)])
		var pad := _pad(side, ray, p)
		var dx := pad.x - c.x
		var dz := pad.z - (Kbd3D.FACE_Z + HomePose.TOUCH)
		worst = maxf(worst, sqrt(dx * dx + dz * dz))
	return worst


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


func _gap(pl: Dictionary, pr: Dictionary) -> float:
	var xl := ArmModel.hand_transform(pl["arm"])
	var xr := ArmModel.hand_transform(pr["arm"])
	var jl: PackedVector3Array = HandModel.thumb_fk(
		HandModel.thumb_of_pose(pl))["pts"]
	var jr: PackedVector3Array = HandModel.thumb_fk(
		HandModel.thumb_of_pose(pr))["pts"]
	var worst := 1e9
	for i in 3:
		for k in 3:
			var d := _seg_dist(_world("L", xl * jl[i]), _world("L", xl * jl[i + 1]),
				_world("R", xr * jr[k]), _world("R", xr * jr[k + 1]))
			worst = minf(worst, d - maxf(float(THUMB_R[i]), float(THUMB_R[i + 1]))
				- maxf(float(THUMB_R[k]), float(THUMB_R[k + 1])))
	return worst


func _ip(side: String, p: Dictionary) -> float:
	var xf := ArmModel.hand_transform(p["arm"])
	var fk: Dictionary = HandModel.thumb_fk(HandModel.thumb_of_pose(p))
	return _world(side, xf * (fk["pts"] as PackedVector3Array)[2]).x


func _try(tag: String, par: Dictionary) -> Dictionary:
	var arm: Dictionary = HomePose.ARM.duplicate(true)
	for k in par:
		arm[k] = float(par[k])
	var pl := _build("L", arm)
	var pr := _build("R", arm)
	var el := _fingers_err("L", pl)
	var er := _fingers_err("R", pr)
	var gap := _gap(pl, pr)
	var out := {"tag": tag, "par": par, "err": maxf(el, er), "gap": gap,
		"ipl": _ip("L", pl), "ipr": _ip("R", pr),
		"tl": HandModel.thumb_of_pose(pl), "tr": HandModel.thumb_of_pose(pr),
		"arm": arm}
	return out


func _init() -> void:
	_keys = Kbd3D.keys()
	var rows := []
	print("flex dev pron wz    | ferr  gap    ipL     ipR")
	for flex in [-40.0, -30.0, -20.0, -10.0, 0.0]:
		for dev in [-30.0, -20.0, -10.0, 0.0]:
			for pron in [-40.0, -20.0, 0.0, 20.0, 40.0]:
				for wz in [-56.0, -44.0, -32.0]:
					var par := {"wrist_flex": flex, "wrist_dev": dev,
						"pronation": pron, "elbow_z": wz}
					var r := _try("", par)
					rows.append(r)
					if float(r["err"]) < 0.6:
						print("%5.0f %5.0f %5.0f %5.0f | %5.2f %6.2f %7.2f %7.2f"
							% [flex, dev, pron, wz, float(r["err"]),
							float(r["gap"]), float(r["ipl"]), float(r["ipr"])])
	var best := []
	for r in rows:
		if float(r["err"]) < 0.6:
			best.append(r)
	best.sort_custom(func(a, b): return float(a["gap"]) > float(b["gap"]))
	print("-- best by gap among placements whose fingers reach:")
	for i in mini(8, best.size()):
		var r: Dictionary = best[i]
		print("   gap %6.2f  ferr %5.2f  %s  L %s  R %s" % [float(r["gap"]),
			float(r["err"]), str(r["par"]), str(r["tl"]), str(r["tr"])])
	quit(0)
