extends SceneTree

const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")
const IK := preload("res://ik.gd")

const KEY_PITCH := 20.0
const KEY_X0 := -90.0
const KEY_Y0 := 80.0
const KEY_Z := -70.0
const KEY_FACE := KEY_Z + 1.0
const KEY_TRAVEL := 2.6
const CLEAR_Z := KEY_FACE + 3.0


func _init() -> void:
	var rest := HandModel.rest_pose()
	for k in [5, 4, 6, 15, 14, 25]:
		var ix: int = k % 10
		var iy: int = k / 10
		var face := Vector3(KEY_X0 + float(ix) * KEY_PITCH,
			KEY_Y0 + float(iy) * KEY_PITCH, KEY_FACE)
		var deep := Vector3(face.x, face.y, KEY_FACE - KEY_TRAVEL)
		var pr: Dictionary = IK.solve_chain("V", deep, rest,
			{"arm": true, "f_lo": -1.0, "clear_z": CLEAR_Z,
			"clear_w": 100.0, "dir_w": 30.0})
		var p: Dictionary = pr["pose"]
		var xf := ArmModel.hand_transform(p.get("arm", {}))
		var rows := []
		for other in ["II", "III", "IV", "V"]:
			var pts: PackedVector3Array = HandModel.finger_fk(other,
				p["fingers"][other])["pts"]
			var radii: Array = HandModel.SKIN_R[other]
			var last := 3 if other == "V" else 4
			for j in last:
				var w: Vector3 = xf * pts[j]
				rows.append([w.z - float(radii[j]), "%s_%d (%.1f %.1f)" % [
					other, j, w.x, w.y]])
		var tpts: PackedVector3Array = HandModel.thumb_fk(
			float(p["thumb_f"]))["pts"]
		var rr := [11.8, 10.8, 9.6, 6.6]
		for j in 4:
			var w2: Vector3 = xf * tpts[j]
			rows.append([w2.z - float(rr[j]), "I_%d (%.1f %.1f)" % [
				j, w2.x, w2.y]])
		rows.sort()
		var pad := xf * HandModel.finger_pad("V", HandModel.finger_fk("V",
			p["fingers"]["V"]))
		var s := ""
		for i in 5:
			s += "%s z%.2f | " % [rows[i][1], float(rows[i][0])]
		print("V k%-2d err %5.2f pad (%5.1f %5.1f %6.1f) %s" % [k,
			float(pr["error"]), pad.x, pad.y, pad.z, s])
	quit(0)
