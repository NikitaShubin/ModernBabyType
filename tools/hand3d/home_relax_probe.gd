# ВРЕМЕННАЯ проба: насколько покой перекручен и что даст расслабленный покой.
#   mbt-godot --headless --path /work/tools/hand3d --script res://home_relax_probe.gd
extends SceneTree

const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")
const HomePose := preload("res://home_pose.gd")
const Kbd3D := preload("res://kbd3d.gd")


func _pad(side: String, ray: String, p: Dictionary, rx: float) -> Vector3:
	var xf := ArmModel.hand_transform(p.get("arm", {}))
	if ray == "I":
		return xf * HandModel.thumb_pad(HandModel.thumb_fk(
			HandModel.thumb_of_pose(p)))
	return xf * HandModel.finger_pad(ray, HandModel.finger_fk(ray,
		p["fingers"][ray]))


func _initialize() -> void:
	var keys := Kbd3D.keys()
	var rx := {"L": float(HomePose.HOME_ROOTS["L"]),
		"R": float(HomePose.HOME_ROOTS["R"])}
	for side in ["L", "R"]:
		var sgn := -1.0 if side == "R" else 1.0
		print("\n==== %s ====" % side)
		var home := HomePose.build(side, float(rx[side]))
		# Расслабленная: углы модели, плечо то же.
		var flex := HandModel.rest_pose()
		flex["arm"] = (HomePose.ARM as Dictionary).duplicate(true)
		flex["thumb"] = (home["thumb"] as Dictionary).duplicate(true)
		flex["thumb_dof"] = 4
		flex["thumb_hold"] = (home.get("thumb_hold", {}) as Dictionary).duplicate(true)
		for ray in ["II", "III", "IV", "V", "I"]:
			var label: String = String((HomePose.HOME_LABELS[side] as Dictionary)[ray]) \
				if ray != "I" else "пробел"
			var ks: Array = keys
			var kc := Vector3.ZERO
			if ray != "I":
				var ki := Kbd3D.index_of(ks, label)
				kc = Kbd3D.centre(ks[ki])
			else:
				kc = Vector3(22.51 if side == "L" else -6.06, 112.0, 0.0)
			var tgt := HomePose.target(side, ray, float(rx[side]))
			var ph := _pad(side, ray, home, float(rx[side]))
			var pf := _pad(side, ray, flex, float(rx[side]))
			var ah: Dictionary = home["fingers"][ray] if ray != "I" else (home["thumb"] as Dictionary)
			var af: Dictionary = flex["fingers"][ray] if ray != "I" else (flex["thumb"] as Dictionary)
			print("%s  HOME  mcp %5.1f pip %5.1f dip %5.1f fan %6.1f | pad %s" % [
				ray, float(ah.get("mcp", 0)), float(ah.get("pip", 0)),
				float(ah.get("dip", 0)), float(ah.get("fan", 0)), str(ph)])
			print("    FLEX  mcp %5.1f pip %5.1f dip %5.1f fan %6.1f | pad %s" % [
				ray, float(af.get("mcp", 0)), float(af.get("pip", 0)),
				float(af.get("dip", 0)), float(af.get("fan", 0)), str(pf)])
			if ray != "I":
				print("    target(локальная) %s  HOME miss %.2f  FLEX miss %.2f" % [
					str(tgt), Vector2(ph.x - tgt.x, ph.y - tgt.y).length(),
					Vector2(pf.x - tgt.x, pf.y - tgt.y).length()])
		# Разброс подушечек FLEX относительно ключей: сдвиг по x,y один на кисть.
		var acc := Vector2.ZERO
		var n := 0
		var pads := {}
		for ray in ["II", "III", "IV", "V"]:
			var label: String = String((HomePose.HOME_LABELS[side] as Dictionary)[ray])
			var ki := Kbd3D.index_of(keys, label)
			var kc := Kbd3D.centre(keys[ki])
			var pf := _pad(side, ray, flex, float(rx[side]))
			var key_local := Vector3((kc.x - float(rx[side])) * sgn, kc.y, 0.0)
			pads[ray] = [pf, key_local]
			acc += Vector2(key_local.x - pf.x, key_local.y - pf.y)
			n += 1
		acc /= float(n)
		print("  сдвиг кисти под ключи: %s" % str(acc))
		var worst := 0.0
		var zmin := 1e9
		for ray in pads.keys():
			var pr: Array = pads[ray]
			var pf: Vector3 = pr[0]
			var kl: Vector3 = pr[1]
			var d := Vector2(pf.x + acc.x - kl.x, pf.y + acc.y - kl.y).length()
			worst = maxf(worst, d)
			zmin = minf(zmin, pf.z)
			print("    %s: невязка после сдвига %.2f мм, z подушечки %.1f" % [
				ray, d, pf.z])
		print("  худшая невязка %.2f мм; FACE_Z %.1f; ниже лица на %.1f" % [
			worst, Kbd3D.FACE_Z, Kbd3D.FACE_Z - zmin])
		var arm: Dictionary = flex["arm"]
		print("  подъём кисти (elbow_z += %.1f) даст зазор 6 мм" % [
			6.0 - (Kbd3D.FACE_Z - zmin)])
	quit(0)
