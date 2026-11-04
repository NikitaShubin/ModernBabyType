extends SceneTree
## Диагностика зеркала: покой левой vs правой руки — дельты по всем
## пальцам (XY корней/кончиков и углы). Рабочий экран как в драйвере.

const KB_FRAC := 0.46


func _area_at(wh: Vector2) -> Rect2:
	var view_w := wh.x
	var view_h := wh.y
	var m := 16.0 + Ui.bottom_inset(view_h)
	var hmax := maxf(160.0, (view_h - m) * KB_FRAC)
	var w := view_w - 32.0
	var h := Kbd.height_for(w)
	if h > hmax:
		w = clampf(Kbd.width_for(hmax), 240.0, view_w - 32.0)
		h = Kbd.height_for(w)
	return Rect2((view_w - w) * 0.5, view_h - h - m, w, h)


func _initialize() -> void:
	for wh in [Vector2(540, 1140), Vector2(1140, 540), Vector2(1280, 800)]:
		var area := _area_at(wh)
		var bs := Kbd.buttons(area, false, false)
		var pitch := Hands.pitch_of(bs)
		var rest := Hands.rest_both(bs)
		# Ось зеркала — ЦЕНТР ДОМ-ГРУППЫ («ф»↔«ж»), а не доски: доска
		# асимметрична по служебным, дом-клавиши зеркальны между собой.
		var axs := 0.5 * (Hands.key_rect(bs, "ф").get_center().x
			+ Hands.key_rect(bs, "ж").get_center().x)
		print("== %dx%d pitch=%.1f зеркало-ось=%.1f центр-доски=%.1f" % [
			int(wh.x), int(wh.y), pitch, axs, area.get_center().x])
		for f in [Hands.PINKY, Hands.RING, Hands.MIDDLE, Hands.INDEX,
				Hands.THUMB]:
			var fl: Dictionary = rest[Hands.LEFT]["fingers"][f]
			var fr: Dictionary = rest[Hands.RIGHT]["fingers"][f]
			var cl: Array = fl["chain"] as Array
			var cr: Array = fr["chain"] as Array
			var l0: Vector3 = cl[0]
			var l3: Vector3 = cl[cl.size() - 1]
			var r0: Vector3 = cr[0]
			var r3: Vector3 = cr[cr.size() - 1]
			var d0x := absf((l0.x - axs) + (r0.x - axs))
			var d3x := absf((l3.x - axs) + (r3.x - axs))
			var d0y := absf(l0.y - r0.y)
			var d3y := absf(l3.y - r3.y)
			var d3z := absf(l3.z - r3.z)
			var al: Array = fl.get("angles", []) as Array
			var ar: Array = fr.get("angles", []) as Array
			# Углы-сгибы (нечётные индексы — отведение, оно знаковое)
			# обязаны совпадать, отведение — совпадать ПО МОДУЛЮ.
			var d_ang := 0.0
			for i in al.size():
				var av: float = al[i] if i < al.size() else 0.0
				var bv: float = ar[i] if i < ar.size() else 0.0
				if i % 2 == 1:
					continue  # отведение знаковое — сравним модуль ниже
				d_ang = maxf(d_ang, absf(av - bv))
			var d_ab := 0.0
			for i in al.size():
				var av2: float = al[i] if i < al.size() else 0.0
				var bv2: float = ar[i] if i < ar.size() else 0.0
				if i % 2 == 1:
					d_ab = maxf(d_ab, absf(absf(av2) - absf(bv2)))
			print("  f=%d корень dX=%.2f dY=%.2f кончик dX=%.2f dY=%.2f dZ=%.2f сгибы d=%.3f отв d=%.3f"
				% [f, d0x, d0y, d3x, d3y, d3z, d_ang, d_ab])
			if f == Hands.THUMB:
				print("    углы L=%s" % str(al))
				print("    углы R=%s" % str(ar))
		# Все суставы цепей подряд: визуальная асимметрия (26.10.2026)
		# может сидеть в промежуточных точках, а не в корне/кончике.
		var worst := 0.0
		var worst_s := ""
		for f2 in [Hands.INDEX, Hands.MIDDLE, Hands.RING, Hands.PINKY,
				Hands.THUMB]:
			var cl2: Array = rest[Hands.LEFT]["fingers"][f2]["chain"]
			var cr2: Array = rest[Hands.RIGHT]["fingers"][f2]["chain"]
			for j in cl2.size():
				var lp: Vector3 = cl2[j]
				var rp: Vector3 = cr2[j]
				var dx := absf((lp.x - axs) + (rp.x - axs))
				if dx > worst:
					worst = dx
					worst_s = "f=%d сустав %d dX=%.3f" % [f2, j, dx]
		print("  ВСЕ суставы: макс-дельта %s" % worst_s)
		# Вскрытие: MIDDLE — углы и точки поштучно (26.10.2026).
		var fm: Dictionary = rest[Hands.LEFT]["fingers"][Hands.MIDDLE]
		var fmr: Dictionary = rest[Hands.RIGHT]["fingers"][Hands.MIDDLE]
		print("    MIDDLE углы L=%s R=%s" % [
			str(fm["angles"]), str(fmr["angles"])])
		var cm: Array = fm["chain"] as Array
		var crm: Array = fmr["chain"] as Array
		for j in cm.size():
			print("    сустав %d L=%s R=%s зерк-x=%.1f" % [
				j, str(cm[j]), str(crm[j]),
				2.0 * axs - (cm[j] as Vector3).x])
		# Дом-клавиши и точки пресса (центр ли клавиши — меряем сами).
		for k in ["в", "л", "а", "о", "ф", "ж"]:
			var kr := Hands.key_rect(bs, k)
			var pp := Hands.press_point(bs, k, Vector2.ZERO)
			print("    клавиша '%s' rect=%s центр=%s press0=%s" % [
				k, str(kr), str(kr.get_center()), str(pp)])
		# Пары домов: зеркальны ли они относительно оси «ф»↔«ж» и
		# относительно центра доски (вот где сидит визуальная асимметрия).
		var ax_fr := 0.5 * (Hands.key_rect(bs, "ф").get_center().x
			+ Hands.key_rect(bs, "ж").get_center().x)
		print("    ось «ф»↔«ж» = %.2f, центр доски = %.2f" % [
			ax_fr, axs])
		for pr in [["а", "о"], ["ф", "ж"], ["в", "л"]]:
			var xa := Hands.key_rect(bs, pr[0]).get_center().x
			var xb := Hands.key_rect(bs, pr[1]).get_center().x
			print("    пара «%s»+«%s» = %.2f (ось %.2f, дельта %.2f)" % [
				pr[0], pr[1], xa + xb, ax_fr, xa + xb - 2.0 * ax_fr])
	quit()
