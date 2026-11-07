# Compares the analytic skin bound (a joint minus its soft-tissue radius) with
# the actual skinned mesh for poses of one click path, bone by bone, to see
# whether a low vertex is the geometry or the deformation.
#   mbt-godot --headless --path /work/tools/hand3d --script res://mesh_vs_bone.gd -- I 24
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")
const SkinRig := preload("res://skin_rig.gd")
const IK := preload("res://ik.gd")
const ClickPath := preload("res://click_path.gd")

const REST_MESH := "res://cache/skin_curled_rest.res"
const KEY_PITCH := 20.0
const KEY_X0 := -90.0
const KEY_Y0 := 80.0
const KEY_Z := -70.0
const KEY_FACE := KEY_Z + 1.0
const KEY_HOVER := 12.0
const THUMB_HOVER := 5.0
const KEY_TRAVEL := 2.6
const CLEAR_Z := KEY_FACE + 3.0
const CLEAR_W := 100.0
const DIR_W := 30.0
const KEY_RECT := Rect2(Vector2(0.0, 120.0), Vector2(98.5, 48.5))

var _rig: Dictionary
var _owner := PackedStringArray()


func _init() -> void:
	var ray := "I"
	var k := 24
	var args := OS.get_cmdline_user_args()
	if args.size() >= 2:
		ray = str(args[0])
		k = int(args[1])
	var src: ArrayMesh = load(REST_MESH)
	_rig = SkinRig.build(HandModel.new(1.0, 0.0), src, REST_MESH)
	_tag_owners()
	var rest := HandModel.rest_pose()
	var ix: int = k % 10
	var iy: int = k / 10
	var face := Vector3(KEY_X0 + float(ix) * KEY_PITCH,
		KEY_Y0 + float(iy) * KEY_PITCH, KEY_FACE)
	var deep := Vector3(face.x, face.y, KEY_FACE - KEY_TRAVEL)
	var flo := -0.35 if ray == "I" else -1.0
	var pr: Dictionary = IK.solve_chain(ray, deep, rest,
		{"arm": true, "f_lo": flo, "clear_z": CLEAR_Z,
		"clear_w": CLEAR_W, "dir_w": DIR_W, "clear_rect": KEY_RECT})
	var pp: Dictionary = pr["pose"]
	var ppad := _pad(ray, pp)
	var hov := THUMB_HOVER if ray == "I" else KEY_HOVER
	var lift: float = maxf(0.0, (KEY_FACE + hov) - ppad.z)
	var hp: Dictionary = pp.duplicate(true)
	hp["arm"]["elbow_z"] = float(hp["arm"].get("elbow_z", 0.0)) + lift
	var path: Dictionary = ClickPath.build(rest, hp, pp, 0.35, 0.16, 0.12, 0.40,
		{"ray": ray, "clear_z": CLEAR_Z, "clear_rect": KEY_RECT,
		"key": k})
	var total := float(path["total"])
	print("press err %.2f pad %.2f lift %.2f total %.2f" % [
		float(pr["error"]), ppad.z, lift, total])
	for frac in [0.0, 0.1, 0.2, 0.5, 0.7, 0.8, 0.86, 0.9, 1.0]:
		_dump(ray, ClickPath.at(path, total * float(frac)), total * float(frac))
	quit(0)


func _dump(ray: String, p: Dictionary, t: float) -> void:
	print("--- t %.3f" % t)
	var verts := SkinRig.cpu_positions(_rig, HandModel.new(1.0, 0.0, p))
	var xf := ArmModel.hand_transform(p.get("arm", {}))
	for other in ["II", "III", "IV", "V"]:
		var pts: PackedVector3Array = HandModel.finger_fk(other,
			p["fingers"][other])["pts"]
		var radii: Array = HandModel.SKIN_R[other]
		var ana := 1e9
		for j in 4:
			ana = minf(ana, (xf * pts[j]).z - float(radii[j]))
		var mz := _mesh_min(verts, other)
		print("%s analytic %7.2f mesh %7.2f diff %5.2f" % [other, ana, mz,
			mz - ana])
	var tpts: PackedVector3Array = HandModel.thumb_fk(
		float(p["thumb_f"]))["pts"]
	var tradii := [11.8, 10.8, 9.6, 6.6]
	var tana := 1e9
	for j in 4:
		tana = minf(tana, (xf * tpts[j]).z - float(tradii[j]))
	var tmz := _mesh_min(verts, "I")
	print("I  analytic %7.2f mesh %7.2f diff %5.2f" % [tana, tmz, tmz - tana])
	var order := []
	for vi in verts.size():
		order.append([verts[vi].z, vi])
	order.sort()
	var line := ""
	for i in 10:
		var vi: int = order[i][1]
		line += "%s z%.2f " % [_owner[vi], verts[vi].z]
	print("   lowest: %s" % line)


func _mesh_min(verts: PackedVector3Array, bone: String) -> float:
	var m := 1e9
	for vi in verts.size():
		if _owner[vi].begins_with(bone + "_"):
			m = minf(m, verts[vi].z)
	return m


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
