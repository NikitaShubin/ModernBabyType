# STALE AS OF SS50h (03.11.2026) — READ sim_trace.gd INSTEAD. This probe
# still builds the OLD arm-free click (the press solved with the whole arm
# free, then the hover pulled straight back). The shipped press is
# board_viewer._sim_press: the finger moves and the hand only settles by the
# depth the finger did not cover (model D2). So the crossings printed here
# are not the shipped behaviour; sim_trace.gd measures the real prism guard
# on the real path and reports no CONTACT. Kept as history of the old click.
#
# The author's rule on the REAL board, frame by frame, on the skinned mesh:
# during the approach and the return nothing may touch the keyboard, and in
# their plane no finger may enter at all — during the press only the target
# finger may cross the face, and only above its own key.
#
# This is the integration twin of click_clear.gd (the old 10x5 grid): the keys
# are the project's own board (kbd3d.gd), the rest is the shared home pose
# (home_pose.gd), and the click is built exactly as board_viewer.gd builds it —
# the press solved with the whole arm free and NO clear_rect, so the idle
# fingers are held above the WHOLE plane, then the hover pulled straight back
# and the path one C1 PCHIP.
#
#   mbt-godot --headless --path /work/tools/hand3d --script res://board_clear.gd
#   ... -- all              # every key of the board
#   ... -- L пробел         # one hand, one key
#
# The right hand is measured in its own (mirrored) local space, which is the
# left model's space: the keys are mirrored about the root exactly as
# board_viewer.gd mirrors them, so one measure serves both hands.
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")
const SkinRig := preload("res://skin_rig.gd")
const IK := preload("res://ik.gd")
const Kbd3D := preload("res://kbd3d.gd")
const ClickPath := preload("res://click_path.gd")
const HomePose := preload("res://home_pose.gd")

const REST_MESH := "res://cache/skin_curled_rest.res"
const KEY_FACE := Kbd3D.FACE_Z
const KEY_TRAVEL := Kbd3D.TRAVEL
const KEY_THICK := Kbd3D.THICK
const KEY_HOVER := 12.0
const THUMB_HOVER := 5.0
const CLEAR_Z := Kbd3D.FACE_Z + 3.0
const SINK_LEAD := 3.0
const CLEAR_W := 100.0
const DIR_W := 30.0
const APPROACH := 0.35
const PRESS := 0.16
const RELEASE := 0.12
const RETURN := 0.40
const STEPS := 24
const TOUCH_TOL := 0.9
const PRESS_TOL := 1.6
const EDGE_TOL := 1.0
# The pressing pad is the only part of the target finger allowed through the
# plane: the flesh that touches a key is a disc about this wide around the
# pad's centre. Exempting the whole finger by its bone name hid a real
# crossing — the thumb's column dipped below the face while its pad was still
# hovering (measured on the left space bar before the skin followed the
# 4-joint thumb: `I_D` 6 mm below the pad).
const PAD_R := 12.0
const ROOTS := {"L": -122.51, "R": 93.94}

const CASES := [["L", "4"], ["L", "ё"], ["L", "я"], ["L", "пробел"],
	["R", "0"], ["R", "ShiftR"], ["R", "глобус"], ["R", "пробел"]]

var _rig: Dictionary
var _owner := PackedStringArray()
var _keys: Array


func _init() -> void:
	var src: ArrayMesh = load(REST_MESH)
	var rest_model := HandModel.new(1.0, 0.0)
	_rig = SkinRig.build(rest_model, src, REST_MESH)
	_tag_owners()
	_keys = Kbd3D.keys()
	var cases := CASES
	var args := OS.get_cmdline_user_args()
	if args.size() >= 1 and str(args[0]) == "all":
		cases = []
		for k in _keys:
			var s := String(k["s"])
			if s == "Caps" or s == "Shift" or s == "Tab":
				continue
			var r: Rect2 = k["r"]
			# A wide key is pressed off-centre, so each half is its own case —
			# the space bar's centre lies exactly on the split, and taking it
			# as "the" click would silently test only one hand.
			for side in ["L", "R"]:
				var hx := r.get_center().x
				if r.size.x > Kbd3D.KEY_W * 1.05:
					hx = r.get_center().x + (-0.6 if side == "L" else 0.6) \
						* r.size.x * 0.5
				var hf := Kbd3D.hand_finger(s, hx)
				if int(hf[0]) != (0 if side == "L" else 1):
					continue
				if String(hf[1]) == "":
					continue
				cases.append([side, s])
	elif args.size() >= 2:
		cases = [[str(args[0]), str(args[1])]]
	var failed := 0
	for c in cases:
		var line := _one(String(c[0]), String(c[1]))
		if line.begins_with("BAD "):
			failed += 1
			line = line.substr(4)
		print(line)
	print("SUMMARY %d/%d cases with a crossing" % [failed, cases.size()])
	quit(0)


func _local_keys(side: String, root_x: float) -> Array:
	var out := []
	for k in _keys:
		var r: Rect2 = k["r"]
		if side == "R":
			out.append(Rect2(-(r.end.x - root_x), r.position.y, r.size.x,
				r.size.y))
		else:
			out.append(Rect2(r.position.x - root_x, r.position.y, r.size.x,
				r.size.y))
	return out


func _local(side: String, root_x: float, p: Vector3) -> Vector3:
	if side == "R":
		return Vector3(-(p.x - root_x), p.y, p.z)
	return Vector3(p.x - root_x, p.y, p.z)


func _pad(ray: String, p: Dictionary) -> Vector3:
	var xf := ArmModel.hand_transform(p.get("arm", {}))
	if ray == "I":
		return xf * HandModel.thumb_pad(HandModel.thumb_fk(
			HandModel.thumb_of_pose(p)))
	return xf * HandModel.finger_pad(ray,
		HandModel.finger_fk(ray, p["fingers"][ray]))


func _one(side: String, label: String) -> String:
	var ks := _keys
	var idx := -1
	var hit := Vector2.ZERO
	for i in ks.size():
		var k: Dictionary = ks[i]
		if String(k["s"]) != label:
			continue
		var r: Rect2 = k["r"]
		# The wide keys are pressed off-centre, so each half is its own case.
		var hx := r.get_center().x
		if r.size.x > Kbd3D.KEY_W * 1.05:
			hx = r.get_center().x + (-0.6 if side == "L" else 0.6) \
				* r.size.x * 0.5
		var hf := Kbd3D.hand_finger(label, hx)
		if int(hf[0]) != (0 if side == "L" else 1):
			continue
		idx = i
		hit = Vector2(hx, r.get_center().y)
		break
	if idx < 0:
		return "skip %s %s: no such key for this hand" % [side, label]
	var key: Dictionary = ks[idx]
	var ray := String(Kbd3D.hand_finger(label, hit.x)[1])
	var root_x: float = ROOTS[side]
	var home: Dictionary = HomePose.build(side, root_x)
	var deep := _local(side, root_x, Vector3(hit.x, hit.y,
		Kbd3D.FACE_Z - KEY_TRAVEL))
	var pr: Dictionary = IK.solve_chain(ray, deep, home,
		{"arm": true, "thumb_dof": 4, "clear_z": CLEAR_Z,
		"clear_w": CLEAR_W, "dir_w": DIR_W})
	var pp: Dictionary = pr["pose"]
	var ppad := _pad(ray, pp)
	var hov := THUMB_HOVER if ray == "I" else KEY_HOVER
	var lift := maxf(0.0, (Kbd3D.FACE_Z + hov) - ppad.z)
	var hp: Dictionary = pp.duplicate(true)
	hp["arm"]["elbow_z"] = float(hp["arm"].get("elbow_z", 0.0)) + lift
	var hpad := _pad(ray, hp)
	var rects := _local_keys(side, root_x)
	var own := idx
	var path: Dictionary = ClickPath.build(home, hp, pp, APPROACH, PRESS,
		RELEASE, RETURN, {"ray": ray, "clear_z": CLEAR_Z,
		"key_rects": rects, "own": own})
	var total := float(path["total"])
	var bad := 0
	var first := ""
	var worst_line := ""
	var worst_other := 1e9
	var worst_t := 0.0
	for i in STEPS + 1:
		var t := total * float(i) / float(STEPS)
		var p: Dictionary = ClickPath.at(path, t)
		var pad := _pad(ray, p)
		var r := _measure(ray, own, p, pad.z, rects)
		if int(r["bad"]) > 0:
			bad += 1
			if first == "":
				first = "t %.3f pad_z %.1f %s" % [t, pad.z, str(r["at"])]
			if String(r["worst"]) != "":
				worst_line = String(r["worst"])
		if float(r["other_z"]) < worst_other:
			worst_other = float(r["other_z"])
			worst_t = t
	var line := "%s %-7s %s err %4.2f lift %5.2f press %7.2f hover %7.2f | bad %2d/%2d %s | idle min z %6.2f at t %.2f" % [
		side, label, ray, float(pr["error"]), lift, ppad.z, hpad.z,
		bad, STEPS + 1, first, worst_other, worst_t]
	if worst_line != "":
		line += "\n    deepest: " + worst_line
	if bad > 0:
		return "BAD " + line
	return line


func _tag_owners() -> void:
	var w: Dictionary = _rig["weights"]
	var idx: PackedInt32Array = w["indices"]
	var names: Array = _rig["names"]
	_owner.resize(idx.size() / SkinRig.MAX_W)
	for vi in _owner.size():
		_owner[vi] = str(names[idx[vi * SkinRig.MAX_W]])


# A vertex is a violation when it is behind the key face AND over a key, and it
# is not the target finger resting on its own key. `other_z` is the shallowest
# non-target vertex anywhere, so the margin is visible even between keys — the
# author's rule is about the whole PLANE, not only the caps.
func _measure(ray: String, target: int, p: Dictionary, pad_z: float,
		rects: Array) -> Dictionary:
	var model := HandModel.new(1.0, 0.0, p)
	var pts := SkinRig.cpu_positions(_rig, model)
	var u := clampf((Kbd3D.FACE_Z + SINK_LEAD - pad_z)
		/ (KEY_TRAVEL + SINK_LEAD), 0.0, 1.0)
	var top := Kbd3D.FACE_Z - KEY_TRAVEL * u
	var bad := 0
	var at := []
	var other_z := 1e9
	var worst_z := 1e9
	var worst := ""
	var pad := _pad(ray, p)
	for vi in pts.size():
		var v := pts[vi]
		var mine := _owner[vi].begins_with(ray + "_")
		if not mine:
			other_z = minf(other_z, v.z)
		if v.z >= Kbd3D.FACE_Z:
			continue
		if not _over_board(v):
			continue
		var k := _key_at(v, rects)
		var near_pad := mine and Vector2(v.x - pad.x, v.y - pad.y).length() \
			<= PAD_R
		var own_key := k == target and near_pad
		# The author's rule is the PLANE, not only the caps: an idle finger
		# may not enter it anywhere over the board. The target finger may, but
		# only its pad, only above its own key, and only down to that key's
		# sunk top.
		var surf := Kbd3D.FACE_Z
		var tol := TOUCH_TOL
		if own_key:
			surf = top
			tol = PRESS_TOL
		if v.z >= surf - tol:
			continue
		bad += 1
		var line := "%s %s at %.1f,%.1f z%.2f (surf %.2f, %s)" % [_owner[vi],
			("«%s»" % String(_keys[k]["s"])) if k >= 0 else "gap",
			v.x, v.y, v.z, surf,
			"through the slab" if v.z < Kbd3D.FACE_Z - KEY_THICK else "over a cap"]
		if at.size() < 3:
			at.append(line)
		if v.z < worst_z:
			worst_z = v.z
			worst = line
	return {"bad": bad, "at": at, "other_z": other_z, "worst": worst}


# The board's own footprint in hand-local x/y: a finger in front of the board
# (nearer the typist) is not "in the keys' plane", it is beside it.
func _over_board(v: Vector3) -> bool:
	var w := Kbd3D.board_w() * 0.5
	if v.x < -w or v.x > w:
		return false
	# Rows are numbered from the bottom (space) up, and world y grows away from
	# the typist, so the smallest y belongs to the LAST row.
	var y0 := Kbd3D.row_y(4) - Kbd3D.ROW_H * 0.5
	var y1 := Kbd3D.row_y(0) + Kbd3D.ROW_H * 0.5
	return v.y >= y0 and v.y <= y1


func _key_at(v: Vector3, rects: Array) -> int:
	for i in rects.size():
		var r: Rect2 = rects[i]
		if v.x < r.position.x + EDGE_TOL or v.x > r.end.x - EDGE_TOL:
			continue
		if v.y < r.position.y + EDGE_TOL or v.y > r.end.y - EDGE_TOL:
			continue
		return i
	return -1
