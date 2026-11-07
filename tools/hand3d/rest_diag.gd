# Where the rest hand is relative to the key grid: every finger's joints in
# world millimetres and the deepest surface point of each.
#   mbt-godot --headless --path /work/tools/hand3d --script res://rest_diag.gd
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")

const KEY_X0 := -90.0
const KEY_Y0 := 80.0
const KEY_Z := -70.0
const KEY_FACE := KEY_Z + 1.0


func _init() -> void:
	var p := HandModel.rest_pose()
	var xf := ArmModel.hand_transform(p.get("arm", {}))
	print("rest arm identity? %s" % str(xf))
	for ray in ["II", "III", "IV", "V"]:
		var fk := HandModel.finger_fk(ray, p["fingers"][ray])
		var pts: PackedVector3Array = fk["pts"]
		var radii: Array = HandModel.SKIN_R[ray]
		var s := ""
		for j in 4:
			var w: Vector3 = xf * pts[j]
			s += " j%d(%.1f,%.1f,%.1f r%.1f)" % [j, w.x, w.y, w.z,
				float(radii[j])]
		var pad: Vector3 = xf * HandModel.finger_pad(ray, fk)
		print("%s%s pad(%.1f,%.1f,%.1f)" % [ray, s, pad.x, pad.y, pad.z])
	var tf := HandModel.thumb_fk(float(p["thumb_f"]))
	var tpts: PackedVector3Array = tf["pts"]
	var tradii := [11.8, 10.8, 9.6, 6.6]
	var ts := ""
	for j in 4:
		var w2: Vector3 = xf * tpts[j]
		ts += " j%d(%.1f,%.1f,%.1f r%.1f)" % [j, w2.x, w2.y, w2.z,
			float(tradii[j])]
	var tpad: Vector3 = xf * HandModel.thumb_pad(tf)
	print("I%s pad(%.1f,%.1f,%.1f)" % [ts, tpad.x, tpad.y, tpad.z])
	print("keys y %.0f..%.0f, face z %.0f" % [KEY_Y0, KEY_Y0 + 4.0 * 20.0,
		KEY_FACE])
	quit(0)
