# One click, frame by frame, cheaply: where every pad is, and how much the
# path's clearance guard lifted the hand. The skinned mesh is not built here;
# this is to see the SHAPE of an idle finger's excursion along the approach.
#   mbt-godot --headless --path /work/tools/hand3d --script res://dip_probe.gd -- V 39
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")
const IK := preload("res://ik.gd")
const ClickPath := preload("res://click_path.gd")

const KEY_PITCH := 20.0
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
const STEPS := 40


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var ray := "V" if args.size() < 1 else str(args[0])
	var k := 39 if args.size() < 2 else int(args[1])
	var ix: int = k % 10
	var iy: int = k / 10
	var face := Vector3(KEY_X0 + float(ix) * KEY_PITCH,
		KEY_Y0 + float(iy) * KEY_PITCH, KEY_FACE)
	var deep := Vector3(face.x, face.y, KEY_FACE - KEY_TRAVEL)
	var flo := THUMB_PRESS_LO if ray == "I" else -1.0
	var pr: Dictionary = IK.solve_chain(ray, deep, HandModel.rest_pose(),
		{"arm": true, "f_lo": flo, "clear_z": CLEAR_Z,
		"clear_w": 100.0, "dir_w": 30.0, "clear_rect": KEY_RECT})
	var pp: Dictionary = pr["pose"]
	var ppad := _pad(ray, pp)
	var hov := THUMB_HOVER if ray == "I" else KEY_HOVER
	var lift: float = maxf(0.0, (KEY_FACE + hov) - ppad.z)
	var hp: Dictionary = pp.duplicate(true)
	hp["arm"]["elbow_z"] = float(hp["arm"].get("elbow_z", 0.0)) + lift
	var raw: Dictionary = ClickPath.build(HandModel.rest_pose(), hp, pp,
		APPROACH, PRESS, RELEASE, RETURN)
	var path: Dictionary = ClickPath.build(HandModel.rest_pose(), hp, pp,
		APPROACH, PRESS, RELEASE, RETURN,
		{"ray": ray, "clear_z": CLEAR_Z, "clear_rect": KEY_RECT,
			"key": k})
	var total := float(path["total"])
	print("%s k%d total %.3f | rest->hover->press" % [ray, k, total])
	for r in ["II", "III", "IV", "V"]:
		var line: String = str(r)
		for pv in [HandModel.rest_pose(), hp, pp]:
			var a: Dictionary = pv["fingers"][r]
			line += " | m%5.1f p%5.1f d%5.1f f%5.1f" % [float(a["mcp"]),
				float(a["pip"]), float(a["dip"]), float(a["fan"])]
		print(line)
	print("wrist rest  " + _xf(HandModel.rest_pose()))
	print("wrist hover " + _xf(hp))
	print("wrist press " + _xf(pp))
	print("arm rest  " + _arm(HandModel.rest_pose()))
	print("arm hover " + _arm(hp))
	print("arm press " + _arm(pp))
	for i in STEPS + 1:
		var t := total * float(i) / float(STEPS)
		var rp: Dictionary = ClickPath.at(raw, t)
		var p: Dictionary = ClickPath.at(path, t)
		var gl := float(p["arm"].get("elbow_z", 0.0)) \
			- float(rp["arm"].get("elbow_z", 0.0))
		var s := "t %5.3f lift %5.2f |" % [t, gl]
		for r in ["II", "III", "IV", "V"]:
			var q := _pad(r, p)
			s += " %s %7.1f %6.1f %7.1f |" % [r, q.x, q.y, q.z]
		var q := _pad("I", p)
		s += " I %7.1f %6.1f %7.1f" % [q.x, q.y, q.z]
		print(s)
	quit(0)


func _xf(p: Dictionary) -> String:
	var xf := ArmModel.hand_transform(p.get("arm", {}))
	var o := xf.origin
	var e := xf.basis * Vector3(0.0, 0.0, 1.0)
	return "o %7.1f %7.1f %7.1f | z-axis %5.2f %5.2f %5.2f" % [o.x, o.y, o.z,
		e.x, e.y, e.z]


func _arm(p: Dictionary) -> String:
	var a: Dictionary = p["arm"]
	return "wf %5.1f wd %5.1f pr %5.1f ff %5.1f fa %5.1f ex %6.1f ey %6.1f ez %6.1f" % [
		float(a["wrist_flex"]), float(a["wrist_dev"]),
		float(a["pronation"]), float(a["forearm_flex"]),
		float(a["forearm_abd"]), float(a["elbow_x"]),
		float(a["elbow_y"]), float(a["elbow_z"])]


func _pad(ray: String, p: Dictionary) -> Vector3:
	var xf := ArmModel.hand_transform(p.get("arm", {}))
	if ray == "I":
		return xf * HandModel.thumb_pad(HandModel.thumb_fk(float(p["thumb_f"])))
	return xf * HandModel.finger_pad(ray,
		HandModel.finger_fk(ray, p["fingers"][ray]))
