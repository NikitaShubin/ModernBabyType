# Measures the keyboard clearance of the click poses on the real skinned mesh.
# For every sampled key and every finger it builds the press pose (whole arm
# free) and the hover pose exactly as viewer.gd does, skins the hand on the CPU
# and counts vertices that have crossed the key face above a key.
#
# A vertex "crosses" a key when z < KEY_FACE (it is behind the front face of
# the 2 mm key slab) and its (x, y) lies inside that key's 17 mm footprint.
# During a press the target finger is expected to cross the TARGET key only:
# everything else crossing anything is a bug. During a hover nothing may cross.
#
#   mbt-godot --headless --path /work/tools/hand3d --script res://clear_probe.gd
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")
const SkinRig := preload("res://skin_rig.gd")
const IK := preload("res://ik.gd")

const REST_MESH := "res://cache/skin_curled_rest.res"
const KEY_PITCH := 20.0
const KEY_SIZE := 17.0
const KEY_X0 := -90.0
const KEY_Y0 := 80.0
const KEY_Z := -70.0
const KEY_FACE := KEY_Z + 1.0
const KEY_HOVER := 12.0
const THUMB_PRESS_LO := -0.35
const THUMB_HOVER_LIFT := 0.30
# The keyboard is a wall at z = KEY_FACE. The solver is told to keep every
# non-target pad at least this far in front of it, with this weight.
const CLEAR_Z := KEY_FACE + 3.0
const CLEAR_W := 100.0

const KEYS := [0, 4, 5, 9, 20, 22, 24, 25, 40, 44, 45, 49]

var _rig: Dictionary
var _owner := PackedStringArray()


func _init() -> void:
	var src: ArrayMesh = load(REST_MESH)
	var rest_model := HandModel.new(1.0, 0.0)
	var rest := HandModel.rest_pose()
	_rig = SkinRig.build(rest_model, src, REST_MESH)
	_tag_owners()
	print("verts %d, owners %s" % [_owner.size(), str(_count_owners())])
	for ray in ["I", "II", "III", "IV", "V"]:
		for k in KEYS:
			var ix: int = k % 10
			var iy: int = k / 10
			var c := Vector3(KEY_X0 + float(ix) * KEY_PITCH,
				KEY_Y0 + float(iy) * KEY_PITCH, KEY_Z)
			var face := Vector3(c.x, c.y, KEY_FACE)
			var deep := Vector3(c.x, c.y, KEY_FACE - 2.6 - 1.0)
			var flo := THUMB_PRESS_LO if ray == "I" else -1.0
			var pr: Dictionary = IK.solve_chain(ray, deep, rest,
				{"arm": true, "f_lo": flo, "clear_z": CLEAR_Z,
				"clear_w": CLEAR_W})
			var pp: Dictionary = pr["pose"]
			var hp: Dictionary
			if ray == "I":
				hp = pp.duplicate(true)
				hp["thumb_f"] = clampf(float(hp["thumb_f"]) + THUMB_HOVER_LIFT,
					-1.0, 1.0)
			else:
				var h: Dictionary = IK.solve_chain(ray,
					face + Vector3(0.0, 0.0, KEY_HOVER), pp,
					{"arm": true, "clear_z": CLEAR_Z, "clear_w": CLEAR_W})
				hp = h["pose"]
			var press := _measure(ray, k, pp)
			var hover := _measure(ray, k, hp)
			print("%s k%-2d %s | PRESS pad_d %5.2f other %d %s own %d %s | HOVER pad_d %5.2f cross %d %s" % [
				ray, k, "err %4.2f" % float(pr["error"]),
				_pad(ray, pp).distance_to(face), int(press["other"]),
				str(press["other_at"]), int(press["own"]), str(press["own_at"]),
				_pad(ray, hp).distance_to(face), int(hover["cross"]),
				str(hover["cross_at"])])
	quit(0)


func _tag_owners() -> void:
	var w: Dictionary = _rig["weights"]
	var idx: PackedInt32Array = w["indices"]
	var names: Array = _rig["names"]
	_owner.resize(idx.size() / SkinRig.MAX_W)
	for vi in _owner.size():
		_owner[vi] = str(names[idx[vi * SkinRig.MAX_W]])


func _count_owners() -> Dictionary:
	var out := {}
	for o in _owner:
		out[o] = int(out.get(o, 0)) + 1
	return out


func _pad(ray: String, p: Dictionary) -> Vector3:
	var xf := ArmModel.hand_transform(p.get("arm", {}))
	if ray == "I":
		return xf * HandModel.thumb_pad(HandModel.thumb_fk(float(p["thumb_f"])))
	return xf * HandModel.finger_pad(ray,
		HandModel.finger_fk(ray, p["fingers"][ray]))


# What crosses what. "own" is the target finger crossing its own key (expected
# on a press); "other" is any other combination. Both report the worst z and
# where it happened, so a single stray vertex is visible, not just counted.
func _measure(ray: String, target: int, p: Dictionary) -> Dictionary:
	var model := HandModel.new(1.0, 0.0, p)
	var pts := SkinRig.cpu_positions(_rig, model)
	var other := 0
	var own := 0
	var other_at := []
	var own_at := []
	var cross := 0
	var cross_at := []
	var deep := 0
	for vi in pts.size():
		var v := pts[vi]
		if v.z >= KEY_FACE:
			continue
		var k := _key_at(v)
		if k < 0:
			continue
		deep += 1
		var bone := _owner[vi]
		var mine := bone.begins_with(ray + "_")
		if k == target and mine:
			own += 1
			if own_at.size() < 3:
				own_at.append("%s z%.2f" % [bone, v.z])
		else:
			other += 1
			if other_at.size() < 3:
				other_at.append("%s k%d z%.2f" % [bone, k, v.z])
		if k != target and cross_at.size() < 3:
			cross_at.append("%s k%d z%.2f" % [bone, k, v.z])
		cross += 1
	return {"own": own, "own_at": own_at, "other": other,
		"other_at": other_at, "cross": cross, "cross_at": cross_at,
		"deep": deep}


# The key whose 17 mm footprint contains the point, or -1.
func _key_at(v: Vector3) -> int:
	var fx := (v.x - KEY_X0) / KEY_PITCH
	var fy := (v.y - KEY_Y0) / KEY_PITCH
	var ix := int(round(fx))
	var iy := int(round(fy))
	if ix < 0 or ix >= 10 or iy < 0 or iy >= 5:
		return -1
	if absf(v.x - (KEY_X0 + float(ix) * KEY_PITCH)) > KEY_SIZE * 0.5:
		return -1
	if absf(v.y - (KEY_Y0 + float(iy) * KEY_PITCH)) > KEY_SIZE * 0.5:
		return -1
	return iy * 10 + ix
