extends SceneTree

## Диагностика 3D-кинетики кистей (26.10.2026): покой из анатомии —
## углы суставов, корень/кончик в 3D; прессы по рядам — 3D-дистанция,
## нужен ли ход кисти (shift_goal), точность доезда решателя.

func _init() -> void:
	DisplayServer.window_set_size(Vector2i(540, 1140))
	root.size = Vector2i(540, 1140)
	var area := Rect2(16, 920, 508, 204)
	var bs: Array = Kbd.buttons(area, false, false)
	var pitch := Hands.pitch_of(bs)
	var pose := Hands.rest_both(bs)
	var board_top := 1e9
	for b in bs:
		board_top = minf(board_top, (b["r"] as Rect2).position.y)
	for h in [Hands.LEFT, Hands.RIGHT]:
		var p: Dictionary = pose[h]
		var fingers: Dictionary = p["fingers"] as Dictionary
		for f in fingers.keys():
			var fd: Dictionary = fingers[f]
			var chain: Array = fd["chain"] as Array
			var r: Array = fd["angles"] as Array
			var root: Vector3 = chain[0]
			var tip: Vector3 = chain[3]
			var bones: Array = Hands.bones_px(f, pitch)
			var total := 0.0
			for b in bones:
				total += b
			# Точность покоя: решатель вернул кончик в цель?
			var back: Array = Hands.ik_chain(root, bones,
				Vector3(tip.x, tip.y, tip.z), r, r, f, Hands.side_of(h))
			var btip: Vector3 = back[1][3]
			print("h", h, " f", f, " L=%.2f" % total,
				" root=", _r3(root), " tip=", _r3(tip),
				" rest_err=%.3f" % btip.distance_to(tip))
			print("    углы=", _round(r),
				" корень ниже кончика по y: ", root.y > tip.y)
			# Прессы: по рядам — цифра, верх, дом, низ.
			for sig in ["1", "й",
					String(Hands.HOME_KEY[h].get(f, "✻")), "я",
					"пробел:" + ("Л" if h == Hands.LEFT else "П")]:
				var pf := Hands.finger_of(sig)
				if pf[0] != h or pf[1] != f:
					continue
				_press_hit(bs, pose, h, f, pitch, tip, r, root, total, sig)
		var wrist: Vector2 = p["wrist"]
		print("hand", h, " knuckle_y=", snappedf(p["knuckle_y"], 0.1),
			" wrist=", wrist.snapped(Vector2(0.1, 0.1)))
	print("ВЕРХ ДОБКИ y=", snappedf(board_top, 1.0),
		" (корни должны быть НИЖЕ этой отметки — тут и сравни)")
	quit()


func _press_hit(bs: Array, pose: Dictionary, h: int, f: int,
		pitch: float, tip: Vector3, r: Array, root: Vector3,
		total: float, sig: String) -> void:
	var c2: Vector2 = Hands.press_point(bs, sig,
		Vector2(tip.x, tip.y))
	if c2 == Vector2.ZERO:
		return
	var tgt := Vector3(c2.x, c2.y, Hands.Z_PRESS * pitch)
	var shift: Vector2 = Hands.shift_goal(pose, h, f, c2, pitch)
	var d := (root - tgt).length()
	var sleep := ""
	if shift != Vector2.ZERO:
		sleep = " ХОД КИСТИ %.2f" % shift.length()
	var sroot := root + Vector3(shift.x, shift.y, 0.0)
	var stgt := tgt
	var res: Array = Hands.ik_chain(sroot, Hands.bones_px(f, pitch),
		stgt, r, r, f, Hands.side_of(h))
	var btip: Vector3 = res[1][3]
	# Разбор проб хода: что именно решатель даёт на каждом кандидате.
	var dbg := ""
	for offer in Hands.SHIFT_TRIES:
		var o: float = (offer as float) * pitch
		var sdir := Vector2(tgt.x - root.x, tgt.y - root.y)
		if sdir.length() > 1e-6:
			sdir = sdir.normalized()
		var tr: Array = Hands._trial(root, sdir, tgt, pitch, f,
			Hands.side_of(h), r, o)
		var ttip: Vector3 = (tr[1] as Array)[3]
		dbg += " [%.0f→%.2f]" % [(offer as float) * 10.0,
			ttip.distance_to(tgt)]
	print("    press %s d=%.2f/%.2f err=%.3f%s углы=%s%s" % [
		sig, d, total, btip.distance_to(stgt), sleep,
		_round(res[0] as Array), dbg])


func _r3(v: Vector3) -> String:
	return "(%.1f %.1f %.1f)" % [v.x, v.y, v.z]


func _round(a: Array) -> String:
	var out := "["
	for v in a:
		out += " %s" % snappedf(v as float, 0.01)
	return out + " ]"
