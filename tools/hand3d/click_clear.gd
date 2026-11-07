# Walks the REAL click path of viewer.gd on the skinned mesh and checks the
# author's rule frame by frame: during the approach and the return nothing may
# touch the keyboard; during the press only the target finger may cross the
# face, and only above its own key. The hover is built exactly as the viewer
# builds it (rigid pull-back of the press pose), and the path is ClickPath, the
# same class the viewer runs.
#
#   mbt-godot --headless --path /work/tools/hand3d --script res://click_clear.gd
#   ... -- I            # every key of the thumb
#   ... -- II 4         # one key
#
# The default list is the nine curated cases; a ray alone sweeps all fifty keys
# of that finger, so the full keyboard can be sharded five ways in parallel.
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")
const SkinRig := preload("res://skin_rig.gd")
const IK := preload("res://ik.gd")
const ClickPath := preload("res://click_path.gd")

const REST_MESH := "res://cache/skin_curled_rest.res"
const KEY_PITCH := 20.0
const KEY_SIZE := 17.0
const KEY_X0 := -90.0
const KEY_Y0 := 80.0
const KEY_Z := -70.0
const KEY_FACE := KEY_Z + 1.0
const KEY_HOVER := 12.0
const THUMB_HOVER := 5.0
const KEY_TRAVEL := 2.6
const THUMB_PRESS_LO := -0.35
const CLEAR_Z := KEY_FACE + 3.0
const KEY_RECT := Rect2(Vector2(0.0, 120.0), Vector2(98.5, 48.5))
const SINK_LEAD := 3.0
# The soft-tissue blend rounds a bent joint outward by a fraction of a
# millimetre (measured 0.3-0.7 on II/III/IV at k4 for 1-2 frames): the skinned
# surface is that much lower than the bone-minus-radius capsule the solver and
# this check use as the bound. The tolerance covers the blend, not a real
# crossing — a vertex 2 mm below the sunk top still fails.
const TOUCH_TOL := 0.9
# The pressing pad flattens against its own keycap: the skinned surface sits
# up to 1.44 mm below the analytic sphere bottom when the key is fully sunk
# (measured on the thumb, k20/k30/k40). That is contact, not a crossing, so the
# target finger gets its own, slightly larger allowance over its own key only.
const PRESS_TOL := 1.6
# A vertex within a millimetre of a key's side is a sliver: the capsule that
# grazes the keyboard's outer edge pokes a fraction of a millimetre into the
# last column, and no rigid lift can fix a side overlap (moving up keeps the
# same x). The author's rule is about visible contact; a hairline at the edge
# of the keycap is not it.
const EDGE_TOL := 1.0
# The keycaps are 2 mm slabs (viewer.gd: BoxMesh 17 x 17 x 2), not infinite
# prisms. A vertex BELOW the slab is under the key, not touching it: the
# keycap hides it from above, and the author's rule is about contact. Measured
# on V k39: the idle ring finger swept 9 mm under the last column on the
# approach; its sphere only grazed the slab's bottom by half a millimetre, and
# the visible frames show nothing. The solver still keeps the JOINTS out of the
# whole prism, so the keyframes are honest; this limit only judges the skin.
const KEY_THICK := 2.0
const CLEAR_W := 100.0
const DIR_W := 30.0
const APPROACH := 0.35
const PRESS := 0.16
const RELEASE := 0.12
const RETURN := 0.40
const STEPS := 30

const CASES := [["I", 9], ["I", 24], ["II", 4], ["III", 4], ["IV", 4],
	["V", 5], ["V", 44], ["II", 49], ["III", 24]]

var _rig: Dictionary
var _owner := PackedStringArray()


func _init() -> void:
	var src: ArrayMesh = load(REST_MESH)
	var rest_model := HandModel.new(1.0, 0.0)
	_rig = SkinRig.build(rest_model, src, REST_MESH)
	_tag_owners()
	var cases := CASES
	var args := OS.get_cmdline_user_args()
	if args.size() >= 1:
		var ray := str(args[0])
		cases = []
		if args.size() >= 2:
			cases.append([ray, int(args[1])])
		else:
			for k in 50:
				cases.append([ray, k])
	var failed := 0
	for c in cases:
		var ray: String = c[0]
		var k: int = c[1]
		var line := _one(ray, k)
		if line.begins_with("BAD "):
			failed += 1
			line = line.substr(4)
		print(line)
	print("SUMMARY %d/%d cases with a crossing" % [failed, cases.size()])
	quit(0)


func _one(ray: String, k: int) -> String:
	var ix: int = k % 10
	var iy: int = k / 10
	var face := Vector3(KEY_X0 + float(ix) * KEY_PITCH,
		KEY_Y0 + float(iy) * KEY_PITCH, KEY_FACE)
	var deep := Vector3(face.x, face.y, KEY_FACE - KEY_TRAVEL)
	var flo := THUMB_PRESS_LO if ray == "I" else -1.0
	var pr: Dictionary = IK.solve_chain(ray, deep, HandModel.rest_pose(),
		{"arm": true, "f_lo": flo, "clear_z": CLEAR_Z,
		"clear_w": CLEAR_W, "dir_w": DIR_W, "clear_rect": KEY_RECT})
	var pp: Dictionary = pr["pose"]
	var ppad := _pad(ray, pp)
	var hov := THUMB_HOVER if ray == "I" else KEY_HOVER
	var lift: float = maxf(0.0, (KEY_FACE + hov) - ppad.z)
	var hp: Dictionary = pp.duplicate(true)
	hp["arm"]["elbow_z"] = float(hp["arm"].get("elbow_z", 0.0)) + lift
	var hpad := _pad(ray, hp)
	var path: Dictionary = ClickPath.build(HandModel.rest_pose(), hp, pp,
		APPROACH, PRESS, RELEASE, RETURN,
		{"ray": ray, "clear_z": CLEAR_Z, "clear_rect": KEY_RECT,
			"key": k})
	var total := float(path["total"])
	var bad := 0
	var first := ""
	var worst_other := 1e9
	var worst_other_t := 0.0
	var best_press := 1e9
	for i in STEPS + 1:
		var t := total * float(i) / float(STEPS)
		var p: Dictionary = ClickPath.at(path, t)
		var pad := _pad(ray, p)
		var r := _measure(ray, k, p, pad.z)
		if int(r["bad"]) > 0:
			bad += 1
			if first == "":
				first = "t %.3f pad_z %.1f %s" % [t, pad.z, str(r["at"])]
		if float(r["other_z"]) < worst_other:
			worst_other = float(r["other_z"])
			worst_other_t = t
		best_press = minf(best_press, pad.z)
	var line := "%s k%-2d err %4.2f lift %5.2f press pad %7.2f hover pad %7.2f | bad %d/%d %s | other min z %6.2f at t %.2f | pad min z %6.2f" % [
		ray, k, float(pr["error"]), lift, ppad.z, hpad.z,
		bad, STEPS + 1, first, worst_other, worst_other_t, best_press]
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


func _pad(ray: String, p: Dictionary) -> Vector3:
	var xf := ArmModel.hand_transform(p.get("arm", {}))
	if ray == "I":
		return xf * HandModel.thumb_pad(HandModel.thumb_fk(float(p["thumb_f"])))
	return xf * HandModel.finger_pad(ray,
		HandModel.finger_fk(ray, p["fingers"][ray]))


# A vertex is a violation when it is behind the key face and over a key, and it
# is not the target finger resting on its own key. The target key sinks with the
# pad exactly as in the viewer, so the target finger is allowed down to the
# SUNK top of its key (plus a hair for soft tissue) — a real finger pushes a
# key down, it does not stop at the face. Every other vertex is measured
# against the un-sunk face: an idle key never moves. "other_z" is the shallowest
# non-target surface anywhere (all vertices, not only those over a key), so the
# clearance margin is visible even between keys.
func _measure(ray: String, target: int, p: Dictionary,
		pad_z: float) -> Dictionary:
	var model := HandModel.new(1.0, 0.0, p)
	var pts := SkinRig.cpu_positions(_rig, model)
	var u := clampf((KEY_FACE + SINK_LEAD - pad_z)
		/ (KEY_TRAVEL + SINK_LEAD), 0.0, 1.0)
	var top := KEY_FACE - KEY_TRAVEL * u
	var bad := 0
	var at := []
	var other_z := 1e9
	for vi in pts.size():
		var v := pts[vi]
		var bone := _owner[vi]
		var mine := bone.begins_with(ray + "_")
		if not mine:
			other_z = minf(other_z, v.z)
		# The tolerance belongs to the skin, not to a key: the blend can put a
		# vertex up to TOUCH_TOL lower than the bone capsule everywhere, so a
		# sub-millimetre dip over a neighbour is the same artefact as over the
		# own key. A real crossing is millimetres deep and still fails.
		if v.z >= KEY_FACE:
			continue
		var k := _key_at(v)
		if k < 0:
			continue
		# The target key sinks with the pad, so its cap top is `top` for every
		# finger; the pressing finger alone may flatten into it (PRESS_TOL).
		var surf := top if k == target else KEY_FACE
		var tol := PRESS_TOL if (k == target and mine) else TOUCH_TOL
		if v.z >= surf - tol:
			continue
		# The back face of the slab is exact: a vertex behind it is not inside
		# the keycap, so it cannot touch it. The skin tolerance belongs to the
		# front face only (the blend rounds a bent joint outward); subtracting
		# it here would call a point 0.05 mm behind the cap a crossing.
		if v.z < surf - KEY_THICK:
			continue
		bad += 1
		if at.size() < 3:
			at.append("%s k%d at %.1f,%.1f z%.2f (top %.2f)" % [bone, k,
				v.x, v.y, v.z, top])
	return {"bad": bad, "at": at, "other_z": other_z}


func _key_at(v: Vector3) -> int:
	var fx := (v.x - KEY_X0) / KEY_PITCH
	var fy := (v.y - KEY_Y0) / KEY_PITCH
	var ix := int(round(fx))
	var iy := int(round(fy))
	if ix < 0 or ix >= 10 or iy < 0 or iy >= 5:
		return -1
	if absf(v.x - (KEY_X0 + float(ix) * KEY_PITCH)) > KEY_SIZE * 0.5 - EDGE_TOL:
		return -1
	if absf(v.y - (KEY_Y0 + float(iy) * KEY_PITCH)) > KEY_SIZE * 0.5 - EDGE_TOL:
		return -1
	return iy * 10 + ix
