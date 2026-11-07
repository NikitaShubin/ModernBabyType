# One candidate arm, every digit: where the metacarpal head is, how far the
# target is from it, what the chain can do, and the residual's components.
#
#   mbt-godot --headless --path /work/tools/hand3d --script res://home_diag.gd
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")
const IK := preload("res://ik.gd")
const Kbd3D := preload("res://kbd3d.gd")

const ROOT_L := -72.51
const HOME_LABELS := {"II": "а", "III": "в", "IV": "ы", "V": "ф"}
const TOUCH := 0.3
const THUMB_X := 20.5
const THUMB_LIFT := 2.0


func _target(ray: String) -> Vector3:
	if ray == "I":
		return Vector3(-THUMB_X - ROOT_L, Kbd3D.row_y(4),
			Kbd3D.FACE_Z + THUMB_LIFT)
	var ks := Kbd3D.keys()
	var c := Kbd3D.centre(ks[Kbd3D.index_of(ks, HOME_LABELS[ray])])
	return Vector3(c.x - ROOT_L, c.y, Kbd3D.FACE_Z + TOUCH)


func _opts(ray: String) -> Dictionary:
	var o := {"arm": false, "tuck": false, "clear_w": 0.0, "dir_w": 0.0}
	if ray == "I":
		o["thumb_dof"] = 4
	return o


func _pad_local(ray: String, p: Dictionary) -> Vector3:
	var xf := ArmModel.hand_transform(p.get("arm", {}))
	if ray == "I":
		return xf * HandModel.thumb_pad(HandModel.thumb_fk(
			HandModel.thumb_of_pose(p)))
	return xf * HandModel.finger_pad(ray,
		HandModel.finger_fk(ray, p["fingers"][ray]))


func _shares(ray: String, a: Dictionary) -> Array:
	var rest: Array = HandModel.FLEX[ray]
	var rom: Dictionary = HandModel.ROM[ray]
	var out := []
	for j in ["mcp", "pip", "dip"]:
		var q := float(a[j])
		var r := float(rest[["mcp", "pip", "dip"].find(j)])
		var lo := float(rom[j][0])
		var hi := float(rom[j][1])
		out.append(IK.share(q, r, lo, hi))
	return out


func _init() -> void:
	var arm := ArmModel.rest_arm()
	arm["forearm_abd"] = 22.0
	arm["wrist_dev"] = -20.0
	arm["wrist_flex"] = -20.0
	arm["pronation"] = 0.0
	arm["elbow_x"] = -ArmModel.FOREARM_L * sin(deg_to_rad(22.0))
	arm["elbow_y"] = 30.0 + ArmModel.FOREARM_L \
		- ArmModel.FOREARM_L * cos(deg_to_rad(22.0))
	arm["elbow_z"] = -41.0
	var xf := ArmModel.hand_transform(arm)
	print("wrist world %s" % str(xf.origin + Vector3(ROOT_L, 0, 0)))
	print("hand basis x %s y %s z %s" % [str(xf.basis.x), str(xf.basis.y),
		str(xf.basis.z)])
	var p := HandModel.rest_pose()
	p["arm"] = arm
	p["thumb_dof"] = 4
	p["thumb"] = HandModel.thumb_at(0.0)
	for ray in ["II", "III", "IV", "V", "I"]:
		var t := _target(ray)
		var tw := Vector3(ROOT_L + t.x, t.y, t.z)
		var mcp_local: Vector3
		if ray == "I":
			mcp_local = HandModel.thumb_fk(HandModel.thumb_of_pose(p))["pts"][1]
		else:
			mcp_local = HandModel.metacarpal_head(ray)
		var mcp_world: Vector3 = xf * mcp_local
		mcp_world.x += ROOT_L
		var r: Dictionary = IK.solve_chain(ray, t, p, _opts(ray))
		p = r["pose"]
		var pad: Vector3 = _pad_local(ray, p)
		pad.x += ROOT_L
		var d := pad - tw
		var reach := mcp_world.distance_to(tw)
		var chain := 0.0
		if ray != "I":
			var lens: Array = HandModel.PH_LEN[ray]
			chain = float(lens[0]) + float(lens[1]) + float(lens[2])
		print("%-3s mcp %s  target %s  mcp-target %6.2f  chain %5.1f  pad %s  d %s"
			% [ray, str(mcp_world), str(tw), reach, chain, str(pad), str(d)])
		if ray != "I":
			print("    angles %s shares %s" % [str(p["fingers"][ray]),
				str(_shares(ray, p["fingers"][ray]))])
		else:
			print("    thumb %s" % str(HandModel.thumb_of_pose(p)))
	quit(0)
