# TEMP probe: what a press does to the hand — arm travel vs finger work.
# Run: godot --headless --path tools/hand3d --script res://press_probe.gd
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")
const Kbd3D := preload("res://kbd3d.gd")
const IK := preload("res://ik.gd")
const HomePose := preload("res://home_pose.gd")

const THUMB_R := [11.8, 10.8, 9.6, 6.6]
const CLEAR_Z := Kbd3D.FACE_Z + 3.0


func _loc(side: String, root_x: float, w: Vector3) -> Vector3:
	if side == "R":
		return Vector3(-(w.x - root_x), w.y, w.z)
	return Vector3(w.x - root_x, w.y, w.z)


func _w(side: String, root_x: float, q: Vector3) -> Vector3:
	if side == "R":
		return Vector3(root_x - q.x, q.y, q.z)
	return Vector3(root_x + q.x, q.y, q.z)


func _caps(side: String, root_x: float, p: Dictionary, other: String,
		other_root: float) -> Array:
	var xo := ArmModel.hand_transform(p.get("arm", {}))
	var out := []
	var it: PackedVector3Array = HandModel.thumb_fk(
		HandModel.thumb_of_pose(p))["pts"]
	for i in 3:
		out.append({"a": _loc(side, root_x, _w(other, other_root, xo * it[i])),
			"b": _loc(side, root_x, _w(other, other_root, xo * it[i + 1])),
			"r": maxf(float(THUMB_R[i]), float(THUMB_R[i + 1]))})
	for f in HandModel.FINGERS:
		var fp: PackedVector3Array = HandModel.finger_fk(
			f, p["fingers"][f])["pts"]
		for i in 3:
			out.append({"a": _loc(side, root_x, _w(other, other_root, xo * fp[i])),
				"b": _loc(side, root_x, _w(other, other_root, xo * fp[i + 1])),
				"r": maxf(float(HandModel.SKIN_R[f][i]),
					float(HandModel.SKIN_R[f][i + 1]))})
	return out


func _pad(side: String, ray: String, p: Dictionary, root_x: float) -> Vector3:
	var xf := ArmModel.hand_transform(p.get("arm", {}))
	var q: Vector3
	if ray == "I":
		q = xf * HandModel.thumb_pad(HandModel.thumb_fk(
			HandModel.thumb_of_pose(p)))
	else:
		q = xf * HandModel.finger_pad(ray,
			HandModel.finger_fk(ray, p["fingers"][ray]))
	return _w(side, root_x, q)


func _run(label: String, side: String, ray: String, world: Vector3,
		opts: Dictionary, homes: Dictionary, roots: Dictionary,
		others: Dictionary) -> void:
	var root_x := float(roots[side])
	var home: Dictionary = homes[side]
	var local := _loc(side, root_x, world)
	var o := opts.duplicate(true)
	o["thumb_dof"] = 4
	o["foreign"] = _caps(side, root_x, homes[others[side]],
		others[side], float(roots[others[side]]))
	var solved: Dictionary = IK.solve_chain(ray, local, home, o)
	var p: Dictionary = solved["pose"]
	var ha: Dictionary = home["arm"]
	var pa: Dictionary = p["arm"]
	var wrist0: Vector3 = ArmModel.hand_transform(ha).origin
	var wrist1: Vector3 = ArmModel.hand_transform(pa).origin
	var pad0 := _pad(side, ray, home, root_x)
	var pad1 := _pad(side, ray, p, root_x)
	print("== %s  %s %s  target %s" % [label, side, ray, str(world)])
	print("   wrist travel %.2f mm (elbow %.2f, %.2f, %.2f)  pad err %.3f"
		% [(wrist1 - wrist0).length(),
			float(pa["elbow_x"]) - float(ha["elbow_x"]),
			float(pa["elbow_y"]) - float(ha["elbow_y"]),
			float(pa["elbow_z"]) - float(ha["elbow_z"]),
			(pad1 - world).length()])
	print("   arm d: flex %.2f dev %.2f pron %.2f fflex %.2f fabd %.2f"
		% [float(pa["wrist_flex"]) - float(ha["wrist_flex"]),
			float(pa["wrist_dev"]) - float(ha["wrist_dev"]),
			float(pa["pronation"]) - float(ha["pronation"]),
			float(pa["forearm_flex"]) - float(ha["forearm_flex"]),
			float(pa["forearm_abd"]) - float(ha["forearm_abd"])])
	if ray == "I":
		var t0: Dictionary = HandModel.thumb_of_pose(home)
		var t1: Dictionary = HandModel.thumb_of_pose(p)
		print("   thumb d: flex %.2f abd %.2f twist %.2f mcp %.2f ip %.2f"
			% [float(t1["cmc_flex"]) - float(t0["cmc_flex"]),
				float(t1["cmc_abd"]) - float(t0["cmc_abd"]),
				float(t1["twist"]) - float(t0["twist"]),
				float(t1["mcp"]) - float(t0["mcp"]),
				float(t1["ip"]) - float(t0["ip"])])
	else:
		var a0: Dictionary = home["fingers"][ray]
		var a1: Dictionary = p["fingers"][ray]
		print("   finger d: mcp %.2f pip %.2f dip %.2f fan %.2f"
			% [float(a1["mcp"]) - float(a0["mcp"]),
				float(a1["pip"]) - float(a0["pip"]),
				float(a1["dip"]) - float(a0["dip"]),
				float(a1["fan"]) - float(a0["fan"])])
	print("   pad world home %s  press %s" % [str(pad0), str(pad1)])


func _init() -> void:
	var roots := {"L": float(HomePose.HOME_ROOTS["L"]),
		"R": float(HomePose.HOME_ROOTS["R"])}
	var homes := {}
	for side in ["L", "R"]:
		homes[side] = HomePose.build(side, float(roots[side]))
	var others := {"L": "R", "R": "L"}
	var ks: Array = Kbd3D.keys()
	var deep := Kbd3D.FACE_Z - Kbd3D.TRAVEL
	var cases := [["backspace", "R", "V", "←"], ["zero", "R", "V", "0"],
		["o", "R", "II", "о"], ["a", "L", "II", "а"],
		["one", "L", "V", "1"]]
	for c in cases:
		var k: Dictionary = ks[Kbd3D.index_of(ks, String(c[3]))]
		var cen := Kbd3D.centre(k)
		var target := Vector3(cen.x, cen.y, deep)
		var base := {"arm": true, "clear_z": CLEAR_Z, "clear_w": 100.0,
			"dir_w": 30.0, "hover_z": Kbd3D.FACE_Z + 12.0}
		var names := ["A now (clear -66, dir30)", "B clear face, dir30",
			"C clear face, dir0", "D no clear, dir0", "E frozen arm, dir0"]
		var variants := [base,
			{"arm": true, "clear_z": Kbd3D.FACE_Z, "clear_w": 100.0,
				"dir_w": 30.0, "hover_z": Kbd3D.FACE_Z + 12.0},
			{"arm": true, "clear_z": Kbd3D.FACE_Z, "clear_w": 100.0,
				"dir_w": 0.0},
			{"arm": true, "dir_w": 0.0},
			{"arm": false, "dir_w": 0.0}]
		for i in variants.size():
			_run("%s / %s" % [String(c[0]), names[i]], String(c[1]),
				String(c[2]), target, variants[i], homes, roots, others)
	# The space bar: the quarter point (as the viewer does now) and the pad.
	var sp: Dictionary = ks[Kbd3D.index_of(ks, "пробел")]
	var r: Rect2 = sp["r"]
	for side in ["L", "R"]:
		var pad0 := _pad(side, "I", homes[side], float(roots[side]))
		var qx := r.position.x + r.size.x * 0.25
		if side == "R":
			qx = r.end.x - r.size.x * 0.25
		var q := Vector3(qx, r.get_center().y, deep)
		var pd := Vector3(pad0.x, pad0.y, deep)
		var base := {"arm": true, "clear_z": CLEAR_Z, "clear_w": 100.0,
			"dir_w": 30.0, "hover_z": Kbd3D.FACE_Z + 5.0}
		_run("space quarter / A now", side, "I", q, base, homes, roots, others)
		_run("space under pad / A now", side, "I", pd, base, homes, roots, others)
		_run("space under pad / C face dir0", side, "I", pd,
			{"arm": true, "clear_z": Kbd3D.FACE_Z, "clear_w": 100.0,
				"dir_w": 0.0}, homes, roots, others)
	quit()
