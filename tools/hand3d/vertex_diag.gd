# One frame of a click, vertex by vertex: which skinned vertices are behind the
# key face over a key, who owns them, where they sit relative to their own bone
# segment, and how much the path's clearance guard lifted the hand. This is how
# a real capsule crossing is told apart from a linear-blend bulge between two
# keyframes.
#   mbt-godot --headless --path /work/tools/hand3d --script res://vertex_diag.gd -- V 19 0.24
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
const APPROACH := 0.35
const PRESS := 0.16
const RELEASE := 0.12
const RETURN := 0.40

var _rig: Dictionary
var _owner := PackedStringArray()
var _names: Array


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var ray := "V"
	var k := 19
	var frac := 0.24
	if args.size() >= 3:
		ray = str(args[0])
		k = int(args[1])
		frac = float(args[2])
	var src: ArrayMesh = load(REST_MESH)
	_rig = SkinRig.build(HandModel.new(1.0, 0.0), src, REST_MESH)
	_tag_owners()
	var rest := HandModel.rest_pose()
	var ix: int = k % 10
	var iy: int = k / 10
	var face := Vector3(KEY_X0 + float(ix) * KEY_PITCH,
		KEY_Y0 + float(iy) * KEY_PITCH, KEY_FACE)
	var deep := Vector3(face.x, face.y, KEY_FACE - KEY_TRAVEL)
	var flo := THUMB_PRESS_LO if ray == "I" else -1.0
	var pr: Dictionary = IK.solve_chain(ray, deep, rest,
		{"arm": true, "f_lo": flo, "clear_z": CLEAR_Z,
		"clear_w": 100.0, "dir_w": 30.0, "clear_rect": KEY_RECT})
	var pp: Dictionary = pr["pose"]
	var ppad := _pad(ray, pp)
	var hov := THUMB_HOVER if ray == "I" else KEY_HOVER
	var lift: float = maxf(0.0, (KEY_FACE + hov) - ppad.z)
	var hp: Dictionary = pp.duplicate(true)
	hp["arm"]["elbow_z"] = float(hp["arm"].get("elbow_z", 0.0)) + lift
	var raw: Dictionary = ClickPath.build(rest, hp, pp,
		APPROACH, PRESS, RELEASE, RETURN)
	var path: Dictionary = ClickPath.build(rest, hp, pp,
		APPROACH, PRESS, RELEASE, RETURN,
		{"ray": ray, "clear_z": CLEAR_Z, "clear_rect": KEY_RECT,
		"key": k})
	var total := float(path["total"])
	var t := total * frac
	var raw_pose: Dictionary = ClickPath.at(raw, t)
	var p: Dictionary = ClickPath.at(path, t)
	var guard := float(p["arm"].get("elbow_z", 0.0)) \
		- float(raw_pose["arm"].get("elbow_z", 0.0))
	print("t %.3f guard lift %.2f | elbow_z %.2f" % [
		t, guard, float(p["arm"].get("elbow_z", 0.0))])
	print("fingers " + _angles(p))
	var pad := _pad(ray, p)
	print("target pad %7.2f %7.2f %7.2f | target key %d" % [pad.x, pad.y, pad.z, k])
	var verts := SkinRig.cpu_positions(_rig, HandModel.new(1.0, 0.0, p))
	var shown := 0
	for vi in verts.size():
		var v := verts[vi]
		if v.z >= KEY_FACE:
			continue
		var kk := _key_at(v)
		if kk < 0:
			continue
		var bone := _owner[vi]
		var mine := bone.begins_with(ray + "_")
		if kk == k and mine and v.z >= KEY_FACE - 3.6:
			continue
		shown += 1
		if shown > 12:
			continue
		print("  v%-6d %-5s k%-2d at %7.2f %7.2f %7.2f | own seg dist %6.2f | %s" % [
			vi, bone, kk, v.x, v.y, v.z, _seg_dist(bone, v, p),
			_sdf_info(bone, v, p)])
	print("total offenders %d" % shown)
	quit(0)


func _angles(p: Dictionary) -> String:
	var s := ""
	for r in ["II", "III", "IV", "V"]:
		var a: Dictionary = p["fingers"][r]
		s += "%s m%5.1f p%5.1f d%5.1f | " % [r, float(a["mcp"]),
			float(a["pip"]), float(a["dip"])]
	s += "I f%5.2f" % float(p["thumb_f"])
	return s


# Distance from a vertex to the owner bone's segment, minus the soft-tissue
# radius at that bone's far joint. Negative means the vertex is INSIDE the
# capsule the solver reasons about; positive means the skinned surface bulges
# outside it.
func _seg_dist(bone: String, v: Vector3, p: Dictionary) -> float:
	var ray := bone.substr(0, bone.find("_"))
	var idx := 0
	if bone.ends_with("_P"):
		idx = 0
	elif bone.ends_with("_M"):
		idx = 1
	elif bone.ends_with("_D"):
		idx = 2
	elif bone == "I_MC":
		idx = 0
	elif bone == "I_P":
		idx = 1
	elif bone == "I_D":
		idx = 2
	else:
		return -99.0
	var xf := ArmModel.hand_transform(p.get("arm", {}))
	var pts: PackedVector3Array
	var rr: Array
	if ray == "I":
		pts = HandModel.thumb_fk(float(p["thumb_f"]))["pts"]
		rr = [11.8, 10.8, 9.6, 6.6]
	else:
		pts = HandModel.finger_fk(ray, p["fingers"][ray])["pts"]
		rr = HandModel.SKIN_R[ray]
	var a := xf * pts[idx]
	var b := xf * pts[idx + 1]
	var ab := b - a
	var s := clampf((v - a).dot(ab) / maxf(ab.length_squared(), 0.0001),
		0.0, 1.0)
	var closest := a + ab * s
	return v.distance_to(closest) - float(rr[idx + 1])


# The prism SDF of the owner bone's closest point, exactly as ik.gd measures it:
# qx/qy inside the keyboard footprint, qz below its face.
func _sdf_info(bone: String, v: Vector3, p: Dictionary) -> String:
	var ray := bone.substr(0, bone.find("_"))
	var idx := 2
	var xf := ArmModel.hand_transform(p.get("arm", {}))
	var pts: PackedVector3Array
	var rr: Array
	if ray == "I":
		pts = HandModel.thumb_fk(float(p["thumb_f"]))["pts"]
		rr = [11.8, 10.8, 9.6, 6.6]
	else:
		pts = HandModel.finger_fk(ray, p["fingers"][ray])["pts"]
		rr = HandModel.SKIN_R[ray]
	var a := xf * pts[idx]
	var b := xf * pts[idx + 1]
	var ab := b - a
	var s := clampf((v - a).dot(ab) / maxf(ab.length_squared(), 0.0001),
		0.0, 1.0)
	var c := a + ab * s
	var r := float(rr[idx + 1])
	var qx := absf(c.x) - 98.5
	var qy := absf(c.y - 120.0) - 48.5
	var qz := c.z - (KEY_FACE + 3.0)
	var ox := maxf(qx, 0.0)
	var oy := maxf(qy, 0.0)
	var oz := maxf(qz, 0.0)
	var sdf := sqrt(ox * ox + oy * oy + oz * oz) \
		+ minf(maxf(qx, maxf(qy, qz)), 0.0)
	return "closest %6.2f %6.2f %6.2f r %.1f q %5.2f %5.2f %5.2f sdf %6.2f viol %5.2f" % [
		c.x, c.y, c.z, r, qx, qy, qz, sdf, maxf(0.0, r - sdf)]


func _tag_owners() -> void:
	var w: Dictionary = _rig["weights"]
	var idx: PackedInt32Array = w["indices"]
	_names = _rig["names"]
	_owner.resize(idx.size() / SkinRig.MAX_W)
	for vi in _owner.size():
		_owner[vi] = str(_names[idx[vi * SkinRig.MAX_W]])


func _pad(ray: String, p: Dictionary) -> Vector3:
	var xf := ArmModel.hand_transform(p.get("arm", {}))
	if ray == "I":
		return xf * HandModel.thumb_pad(HandModel.thumb_fk(float(p["thumb_f"])))
	return xf * HandModel.finger_pad(ray,
		HandModel.finger_fk(ray, p["fingers"][ray]))


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
