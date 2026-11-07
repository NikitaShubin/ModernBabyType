# Diagnoses the press poses: where the target finger's joints and directions
# are, how deep each non-target part goes, and which vertices cross a key.
#   mbt-godot --headless --path /work/tools/hand3d --script res://press_diag.gd
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
const CLEAR_Z := KEY_FACE + 3.0
const CLEAR_W := 100.0
const THUMB_PRESS_LO := -0.35

const CASES := [["I", 9], ["I", 24], ["II", 4], ["III", 4], ["IV", 4],
	["V", 5], ["V", 44], ["II", 49]]

var _rig: Dictionary
var _owner := PackedStringArray()


func _init() -> void:
	var src: ArrayMesh = load(REST_MESH)
	var rest_model := HandModel.new(1.0, 0.0)
	_rig = SkinRig.build(rest_model, src, REST_MESH)
	_tag_owners()
	for c in CASES:
		var ray: String = c[0]
		var k: int = c[1]
		var ix: int = k % 10
		var iy: int = k / 10
		var face := Vector3(KEY_X0 + float(ix) * KEY_PITCH,
			KEY_Y0 + float(iy) * KEY_PITCH, KEY_FACE)
		var deep := Vector3(face.x, face.y, KEY_FACE - 3.6)
		var flo := THUMB_PRESS_LO if ray == "I" else -1.0
		var pr: Dictionary = IK.solve_chain(ray, deep, HandModel.rest_pose(),
			{"arm": true, "f_lo": flo, "clear_z": CLEAR_Z, "clear_w": CLEAR_W,
			"dir_w": 30.0})
		var p: Dictionary = pr["pose"]
		var xf := ArmModel.hand_transform(p.get("arm", {}))
		print("== %s k%d err %.2f pad_d %.2f" % [ray, k,
			float(pr["error"]), _pad(ray, p).distance_to(face)])
		if ray == "I":
			var fk := HandModel.thumb_fk(float(p["thumb_f"]))
			var pts: PackedVector3Array = fk["pts"]
			var dirs: Array = fk["dirs"]
			for j in 4:
				var w: Vector3 = xf * pts[j]
				print("   I j%d (%7.2f %7.2f %7.2f)" % [j, w.x, w.y, w.z])
			for j in 3:
				var d: Vector3 = (xf.basis * (dirs[j] as Vector3)).normalized()
				print("   I d%d (%6.3f %6.3f %6.3f)" % [j, d.x, d.y, d.z])
		else:
			var fk2 := HandModel.finger_fk(ray, p["fingers"][ray])
			var pts2: PackedVector3Array = fk2["pts"]
			var dirs2: Array = fk2["dirs"]
			for j in 4:
				var w2: Vector3 = xf * pts2[j]
				print("   %s j%d (%7.2f %7.2f %7.2f)" % [
					ray, j, w2.x, w2.y, w2.z])
			for j in 3:
				var d2: Vector3 = (xf.basis * (dirs2[j] as Vector3)).normalized()
				print("   %s d%d (%6.3f %6.3f %6.3f)" % [ray, j, d2.x, d2.y, d2.z])
		_deep(ray, p, xf)
		_cross(ray, k, p)
	quit(0)


func _pad(ray: String, p: Dictionary) -> Vector3:
	var xf := ArmModel.hand_transform(p.get("arm", {}))
	if ray == "I":
		return xf * HandModel.thumb_pad(HandModel.thumb_fk(float(p["thumb_f"])))
	return xf * HandModel.finger_pad(ray,
		HandModel.finger_fk(ray, p["fingers"][ray]))


func _deep(ray: String, p: Dictionary, xf: Transform3D) -> void:
	var fingers: Dictionary = p["fingers"]
	var parts := []
	for other in ["II", "III", "IV", "V"]:
		if other == ray:
			continue
		var pts: PackedVector3Array = HandModel.finger_fk(other,
			fingers[other])["pts"]
		var radii: Array = HandModel.SKIN_R[other]
		var deep := 1e9
		var at := ""
		for j in 4:
			var w: Vector3 = xf * pts[j]
			var z := w.z - float(radii[j])
			if z < deep:
				deep = z
				at = "%s j%d (%.1f %.1f)" % [other, j, w.x, w.y]
		parts.append("%s %.2f %s" % [other, deep, at])
	if ray != "I":
		var tpts: PackedVector3Array = HandModel.thumb_fk(
			float(p["thumb_f"]))["pts"]
		var tradii := [11.8, 10.8, 9.6, 6.6]
		var tdeep := 1e9
		var tat := ""
		for j in 4:
			var w2: Vector3 = xf * tpts[j]
			var z2 := w2.z - float(tradii[j])
			if z2 < tdeep:
				tdeep = z2
				tat = "I j%d (%.1f %.1f)" % [j, w2.x, w2.y]
		parts.append("I %.2f %s" % [tdeep, tat])
	print("   deep: %s" % " | ".join(parts))


func _cross(ray: String, target: int, p: Dictionary) -> void:
	var model := HandModel.new(1.0, 0.0, p)
	var pts := SkinRig.cpu_positions(_rig, model)
	var by := {}
	for vi in pts.size():
		var v := pts[vi]
		if v.z >= KEY_FACE:
			continue
		var k := _key_at(v)
		if k < 0 or k == target:
			continue
		var bone := _owner[vi]
		var key := "%s k%d" % [bone, k]
		var e: Array = by.get(key, [0, 1e9, Vector3.ZERO])
		e[0] = int(e[0]) + 1
		if v.z < float(e[1]):
			e[1] = v.z
			e[2] = v
		by[key] = e
	var keys := by.keys()
	keys.sort()
	for key in keys:
		var e2: Array = by[key]
		var v2: Vector3 = e2[2]
		print("   cross %s n%d z%.2f at (%.1f %.1f)" % [key, int(e2[0]),
			float(e2[1]), v2.x, v2.y])


func _tag_owners() -> void:
	var w: Dictionary = _rig["weights"]
	var idx: PackedInt32Array = w["indices"]
	var names: Array = _rig["names"]
	_owner.resize(idx.size() / SkinRig.MAX_W)
	for vi in _owner.size():
		_owner[vi] = str(names[idx[vi * SkinRig.MAX_W]])


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
