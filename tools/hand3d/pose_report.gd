# TEMP probe: what the four fingertips actually do in world space — the distal
# phalanx's angle to the key plane, and how far its VOLAR face is from looking
# straight down at the keys (the "twist" the author asked about).
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")
const HomePose := preload("res://home_pose.gd")
const Kbd3D := preload("res://kbd3d.gd")

const ROOT0 := {"L": -122.51, "R": 93.94}
const HOME_LABELS := {
	"L": {"II": "а", "III": "в", "IV": "ы", "V": "ф"},
	"R": {"II": "о", "III": "л", "IV": "д", "V": "ж"},
}


func _root(side: String) -> float:
	var e := OS.get_environment("MBT_ROOT_" + side)
	if e != "":
		return float(e)
	return float(ROOT0[side])


func _world_dir(side: String, p: Dictionary, local: Vector3) -> Vector3:
	var hb: Basis = ArmModel.hand_transform(p.get("arm", {})).basis
	var q := hb * local
	if side == "R":
		return Vector3(-q.x, q.y, q.z)
	return q


func _world(side: String, p: Dictionary, local: Vector3) -> Vector3:
	var xf := ArmModel.hand_transform(p.get("arm", {}))
	var q := xf * local
	var rx := _root(side)
	if side == "R":
		return Vector3(rx - q.x, q.y, q.z)
	return Vector3(rx + q.x, q.y, q.z)


func _key_cx(label: String) -> float:
	var ks := Kbd3D.keys()
	return Kbd3D.centre(ks[Kbd3D.index_of(ks, label)]).x


func _init() -> void:
	print("ARM ", str(HomePose.ARM))
	for side in ["L", "R"]:
		var p := HomePose.build(side, _root(side))
		var arm: Dictionary = p["arm"]
		var f := ArmModel.frames(arm)
		var hb: Basis = ArmModel.hand_transform(arm).basis
		var fwd := hb * Vector3(0, 1, 0)
		var palm := hb * Vector3(0, 0, -1)
		var el: Vector3 = f["elbow"]
		var w: Vector3 = f["wrist"]
		print("%s: hand yaw %.1f  hand ext %.1f  palm tilt %.1f | elbow x %.1f wrist x %.1f"
			% [side, rad_to_deg(atan2(fwd.x, fwd.y)),
			rad_to_deg(asin(clampf(fwd.z, -1.0, 1.0))),
			rad_to_deg(atan2(palm.x, -palm.z)), el.x, w.x])
		for ray in ["II", "III", "IV", "V"]:
			var a: Dictionary = p["fingers"][ray]
			var fk := HandModel.finger_fk(ray, a)
			var d3: Vector3 = fk["dirs"][2]
			var axis: Vector3 = fk["axis"]
			var volar: Vector3 = (axis.cross(d3)).normalized()
			var wd := _world_dir(side, p, d3)
			var wv := _world_dir(side, p, volar)
			var pad := _world(side, p, HandModel.finger_pad(ray, fk))
			var cx := _key_cx((HOME_LABELS[side] as Dictionary)[ray])
			var tilt := rad_to_deg(asin(clampf(absf(wd.z), 0.0, 1.0)))
			var twist := rad_to_deg(acos(clampf(wv.dot(Vector3(0, 0, -1)), -1.0, 1.0)))
			print("  %s fan %6.2f mcp %5.1f pip %5.1f dip %5.1f | distal-to-plane %5.1f  volar-off-down %5.1f | pad x %6.2f (key %6.2f) y %6.2f z %6.2f"
				% [ray, float(a["fan"]), float(a["mcp"]), float(a["pip"]),
				float(a["dip"]), tilt, twist, pad.x, cx, pad.y, pad.z])
		var th := HandModel.thumb_of_pose(p)
		var tfk := HandModel.thumb_fk(th)
		var td2: Vector3 = tfk["dirs"][2]
		var wtd := _world_dir(side, p, td2)
		var tpad := _world(side, p, HandModel.thumb_pad(tfk))
		print("  I angles %s | distal-to-plane %.1f | pad x %.2f y %.2f z %.2f"
			% [str(th), rad_to_deg(asin(clampf(absf(wtd.z), 0.0, 1.0))),
			tpad.x, tpad.y, tpad.z])
	quit(0)
