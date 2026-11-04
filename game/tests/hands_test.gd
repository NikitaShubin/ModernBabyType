extends SceneTree
## Скелет кистей — ЧИСТАЯ 3D-КИНЕМАТИКА (26.10.2026), headless не рисует:
## карта палец↔клавиша покрывает ВСЮ доску; кости —антропометрия и НЕ
## растягиваются в FK/IK; покой выведен ИЗ АНАТОМИИ — корни пястной дуги
## НИЖЕ кончиков (пальцы растут от ладони), пястная дуга выпукла к клави-
## шам и НЕ дотягивается до цифрового ряда; пресс — аргмин отклонений от
## покоя, цели в 3D (z живёт в механике); обе кисти симметричны модельно.
## Пробы каждого правила: правило ломается руками — тест краснеет со
## своим сообщением (правило этого репозитория).
##
## Геометрия доски: живой узел не нужен — buttons() чистый. Окно
## ставим (headless по умолчанию 64×64 — доска вырожденная).

const KB_FRAC := 0.46


func _initialize() -> void:
	main_window_setup()
	_hands_test()
	if _fails == 0:
		print("HANDS_TEST: PASS")
	quit(0 if _fails == 0 else 1)


var _fails := 0


func main_window_setup() -> void:
	DisplayServer.window_set_size(Vector2i(540, 1140))
	root.size = Vector2i(540, 1140)


func _check(ok: bool, msg: String) -> void:
	if not ok:
		print("HANDS: FAIL: ", msg)
		_fails += 1


func _board() -> Array:
	var wh := root.size
	var m := 16.0 + Ui.bottom_inset(float(wh.y))
	var hmax := maxf(160.0, (float(wh.y) - m) * KB_FRAC)
	var w := float(wh.x) - 32.0
	var h := Kbd.height_for(w)
	if h > hmax:
		w = clampf(Kbd.width_for(hmax), 240.0, float(wh.x) - 32.0)
		h = Kbd.height_for(w)
	return Kbd.buttons(Rect2((float(wh.x) - w) * 0.5, float(wh.y) - h - m, w, h), false, false)


func _hands_test() -> void:
	var bs: Array = _board()
	_check(Hands.pitch_of(bs) > 0.0, "pitch from buttons is positive")
	_map_covers_board(bs)
	_map_spot_checks(bs)
	_ik_invariants(bs)
	_fk_stability_checks(bs)
	_rest_anatomy_checks(bs)
	_energy_checks(bs)
	_micro_checks(bs)
	_mirror_checks(bs)
	_press_checks(bs)
	_z_checks(bs)
	_hint_checks(bs)
	_contour_checks(bs)


## Каждая клавиша ДОСКИ имеет палец: карта не может отстать от
## раскладки — новая клавиша без пальца должна ломать тест.
func _map_covers_board(bs: Array) -> void:
	for b in bs:
		var s := String(b["s"])
		var f := Hands.finger_of(s)
		_check(f[0] >= 0,
			"key '%s' has a finger in the map (%s)" % [s, str(Hands.finger_of(s))])


## Точечные правила карты: дом-ряд, крайние колонки, служебные.
func _map_spot_checks(bs: Array) -> void:
	_check(Hands.finger_of("ф") == [Hands.LEFT, Hands.PINKY], "ф is left pinky")
	_check(Hands.finger_of("ы") == [Hands.LEFT, Hands.RING], "ы is left ring")
	_check(Hands.finger_of("в") == [Hands.LEFT, Hands.MIDDLE], "в is left middle")
	_check(Hands.finger_of("а") == [Hands.LEFT, Hands.INDEX], "а is left index")
	_check(Hands.finger_of("и") == [Hands.LEFT, Hands.INDEX],
		"и is left index (key b is under the LEFT palm)")
	_check(Hands.finger_of("о") == [Hands.RIGHT, Hands.INDEX], "о is right index")
	_check(Hands.finger_of("л") == [Hands.RIGHT, Hands.MIDDLE], "л is right middle")
	_check(Hands.finger_of("б") == [Hands.RIGHT, Hands.MIDDLE],
		"б is right middle (key , is under the RIGHT palm)")
	_check(Hands.finger_of("ъ") == [Hands.RIGHT, Hands.PINKY], "ъ is right pinky")
	_check(Hands.finger_of("Shift") == [Hands.LEFT, Hands.PINKY], "left shift is left pinky")
	_check(Hands.finger_of("ShiftR") == [Hands.RIGHT, Hands.PINKY], "right shift is right pinky")
	_check(Hands.finger_of("↵") == [Hands.RIGHT, Hands.PINKY], "enter is right pinky")
	_check(Hands.finger_of("←") == [Hands.RIGHT, Hands.PINKY], "backspace is right pinky")
	_check(Hands.finger_of("4") == [Hands.LEFT, Hands.INDEX], "4 is left index")
	_check(Hands.finger_of("5") == [Hands.LEFT, Hands.INDEX], "5 is left index")
	_check(Hands.finger_of("6") == [Hands.RIGHT, Hands.INDEX], "6 is right index")
	_check(Hands.finger_of("7") == [Hands.RIGHT, Hands.INDEX], "7 is right index")


## FK/IK в 3D: кости НЕ растягиваются никогда (длина сегмента по Vector3);
## достижимая цель достигается; недостижимая — цепь в струну ровно на Σbones.
func _ik_invariants(bs: Array) -> void:
	var pitch := Hands.pitch_of(bs)
	_check(pitch > 0.0, "pitch positive before IK")
	_check(Hands.BONES_MM.keys().size() == 5, "BONES_MM covers five fingers")
	# DOF-карта: четыре пальца — 4 угла, большой — 5 (поворот CMC).
	for f in [Hands.THUMB, Hands.INDEX, Hands.MIDDLE, Hands.RING, Hands.PINKY]:
		_check(Hands._dof_count(f) == (5 if f == Hands.THUMB else 4),
			"f=%d has the right DOF count (%d)" % [f, Hands._dof_count(f)])
		_check((Hands.JOINT_LIMITS[f] as Array).size() == Hands._dof_count(f),
			"f=%d JOINT_LIMITS cover every DOF" % f)
		_check((Hands.REST_PRIOR[f] as Array).size() == Hands._dof_count(f),
			"f=%d REST_PRIOR covers every DOF" % f)
	_check((Hands.JOINT_W_THUMB as Array).size() == 5,
		"thumb weights cover five DOF")
	for f in [Hands.THUMB, Hands.INDEX, Hands.MIDDLE, Hands.RING, Hands.PINKY]:
		var bones := Hands.bones_px(f, pitch)
		_check(bones.size() == 3, "f=%d chain has three segments" % f)
		var reach := 0.0
		for b in bones:
			reach += b as float
		var root := Vector3(120.0, 800.0, reach * 0.3)
		# Достижимо: цель ПОРОВДАНА ФК — берём суставы в середине диапа-
		# зонов (анатомическая поза), ГК даёт честно достижимый кончик;
		# решатель обязан найти его ИЗ покоя (легко: покой — тоже доез-
		# жающая поза, в отличие от синтетической диагонали вне конуса,
		# по пределам сустава недостижимой — ловлено 26.10.2026).
		var probe: Array = [0.30, 0.0, 0.45, 0.35]
		if f == Hands.THUMB:
			probe = [0.30, 0.0, 1.20, 0.35, 0.30]
		var fk: Array = Hands.fk_chain(root, bones, probe, f, 1.0)
		var goals := [
			["fk_target", fk[3]],
		]
		for case in goals:
			var res: Array = Hands.ik_chain(root, bones,
				case[1] as Vector3,
				Hands.REST_PRIOR[f], Hands.REST_PRIOR[f], f, 1.0)
			var pts: Array = res[1] as Array
			_check(pts.size() == 4,
				"%s f=%d chain is root+3 joints" % [case[0], f])
			for i in 3:
				var seg: float = (pts[i + 1] as Vector3).distance_to(
					pts[i] as Vector3)
				_check(absf(seg - (bones[i] as float)) < 0.002,
					"%s f=%d bone %d keeps its length (%.4f vs %.4f)" % [
						case[0], f, i, seg, bones[i]])
			var tip: Vector3 = pts[3]
			# Допуск = 2·σ решателя: энергия уравновешивает доезд с
			# сгибом отклонения от покоя, и решатель даёт err ≤ ~2σ.
			_check(tip.distance_to(case[1] as Vector3)
				< 2.0 * Hands.SOLVE_SIG * reach,
				"%s f=%d tip reaches the target (err %.4f, tol %.4f)" % [
					case[0], f, tip.distance_to(case[1] as Vector3),
					2.0 * Hands.SOLVE_SIG * reach])
		# Недостижимо: кончик на Σbones в струну от корня.
		var far := root + Vector3(reach * 2.4, 0.0, 0.0)
		var res2: Array = Hands.ik_chain(root, bones, far,
			Hands.REST_PRIOR[f], Hands.REST_PRIOR[f], f, 1.0)
		var tip2: Vector3 = (res2[1] as Array)[3]
		_check(absf(tip2.distance_to(root) - reach) < 0.012 * reach,
			"f=%d unreachable target stops the chain at full stretch (dist %.3f vs reach %.3f)" %
				[f, tip2.distance_to(root), reach])


## FK сходится с самим собой: длина цепи из костей неизменна И FK честно
## строит интервалы (нет морфинга точек). И разбор позы не меняет длину.
func _fk_stability_checks(bs: Array) -> void:
	var pitch := Hands.pitch_of(bs)
	for f in [Hands.INDEX, Hands.MIDDLE, Hands.RING, Hands.PINKY]:
		var bones := Hands.bones_px(f, pitch)
		var root := Vector3(50.0, 900.0, 60.0)
		for ang in [[0.5, 0.1, 1.0, 0.6], [1.0, -0.3, 1.4, 0.9]]:
			var pts: Array = Hands.fk_chain(root, bones, ang, f, 1.0)
			for i in 3:
				var seg: float = (pts[i + 1] as Vector3).distance_to(
					pts[i] as Vector3)
				_check(absf(seg - (bones[i] as float)) < 1e-4,
					"f=%d FK bone %d keeps length at %s (%.5f vs %.5f)" % [
						f, i, str(ang), seg, bones[i]])
	# Большой — свои 5 углов ([CMC, отведение, поворот, MCP, IP]); FK
	# остаётся честным по костям и при повёрнутой плоскости дистали.
	var tb: Array = Hands.bones_px(Hands.THUMB, pitch)
	var troot := Vector3(70.0, 880.0, 60.0)
	for tang in [Hands.REST_PRIOR[Hands.THUMB],
			[0.5, 0.1, 1.6, 1.2, 1.0]]:
		var tp: Array = Hands.fk_chain(troot, tb, tang, Hands.THUMB, 1.0)
		for i in 3:
			var seg: float = (tp[i + 1] as Vector3).distance_to(
				tp[i] as Vector3)
			_check(absf(seg - (tb[i] as float)) < 1e-4,
				"thumb FK bone %d keeps length at %s (%.5f vs %.5f)" % [
					i, str(tang), seg, tb[i]])


## Покой выведен ИЗ АНАТОМИИ (26.10.2026): пять пальцев; кончики hover
## над своими дом-клавишами; КОРНИ НИЖЕ кончиков (пальцы растут от ла-
## дони, не против неё); пястная дуга ВЫПУКЛА К КЛАВИШАМ (средний ко-
## рень выше хорды указательный-мизинец); запястье ниже пясти; высоты
## кончиков — hover из констант (пальцы ВИСЯТ, не лежат).
func _rest_anatomy_checks(bs: Array) -> void:
	var pitch := Hands.pitch_of(bs)
	var pose := Hands.rest_both(bs)
	_check(pose.has(Hands.LEFT) and pose.has(Hands.RIGHT), "both hands rest")
	for h in [Hands.LEFT, Hands.RIGHT]:
		var p: Dictionary = pose[h]
		var fl: Dictionary = p["fingers"]
		_check(fl.size() == 5, "hand %d rests with 5 fingers" % h)
		var home_map: Dictionary = Hands.HOME_KEY[h]
		for f in [Hands.INDEX, Hands.MIDDLE, Hands.RING, Hands.PINKY]:
			var fd: Dictionary = fl[f]
			var chain: Array = fd["chain"]
			_check(chain.size() == 4, "hand %d f=%d chain has 4 joints" % [h, f])
			var tip: Vector3 = chain[3]
			var root: Vector3 = chain[0]
			var kr := Hands.key_rect(bs, String(home_map[f]))
			_check(kr.size.x > 0.0, "home key of hand %d f=%d on the board" % [h, f])
			var contact := Hands.press_point(bs, String(home_map[f]),
				Vector2.ZERO)
			# Кончик НА клавише и у её центра (веер: не больше трети).
			_check(kr.has_point(Vector2(tip.x, tip.y)),
				"hand %d f=%d tip touches its home key" % [h, f])
			_check(Vector2(tip.x, tip.y).distance_to(contact) < 0.35 * pitch,
				"hand %d f=%d tip near its home key center (%.2f)" % [
					h, f, Vector2(tip.x, tip.y).distance_to(contact)])
			# Кончик ВИСИТ на hover-высоте из константы (не прилип).
			var zt: float = Hands.Z_TIP
			var want := absf(tip.z - zt * pitch)
			_check(want < 0.05 * pitch,
				"hand %d f=%d tip hovers at Z_TIP (%.2f vs %.2f)" % [
					h, f, tip.z, zt * pitch])
			# Корень НИЖЕ кончика по экрану (пальцы растут от ладони —
			# жалоба автора 26.10.2026 на пальцы «наоборот»).
			_check(root.y > tip.y + 0.9 * pitch,
				"hand %d f=%d knuckle sits BELOW the tip (%.1f vs %.1f)" % [
					h, f, root.y, tip.y])
			# Пясть ВЫШЕ кончика по З (рука приподнята над доской).
			_check(root.z > tip.z + 0.8 * pitch,
				"hand %d f=%d knuckle is above the tip in z (%.2f vs %.2f)" % [
					h, f, root.z, tip.z])
		# Пястная дуга ВЫПУКЛА К КЛАВИШАМ: корень среднего ближе к клави-
		# шам (меньше y), чем хорда указательный–мизинец в его точке.
		for f_thr in [Hands.THUMB]:
			var chain2: Array = (fl[f_thr] as Dictionary)["chain"]
			var tip2: Vector3 = chain2[3]
			var half := Hands.sig_rect(bs,
				"пробел:Л" if h == Hands.LEFT else "пробел:П")
			_check(half.has_point(Vector2(tip2.x, tip2.y)),
				"hand %d thumb touches its space half" % h)
			# Большой — 5 DOF; поворот (оппозиция) уже в покое ВКЛЮ-
			# ЧЁН: дисталь смотрит в ладонь, иначе он не достаёт пробел.
			var tang: Array = (fl[f_thr] as Dictionary)["angles"]
			_check(tang.size() == 5,
				"hand %d thumb rests with 5 DOF" % h)
			_check((tang[2] as float) > 0.05,
				"hand %d thumb rest keeps the opposition twist (%.3f)" % [
					h, tang[2]])
			# Подушечка большого почти ЛЕЖИТ на пробеле (0.08 питча);
			# допуск щедрый на руки (2.3 vs 4.7 px у пары) — анимация
			# лерп к нажатию всё равно ведёт в z = Z_PRESS.
			_check(absf(tip2.z - Hands.Z_TIP_THUMB * pitch) < 0.15 * pitch,
				"hand %d thumb rests near Z_TIP_THUMB (%.2f vs %.2f)" % [
					h, tip2.z, Hands.Z_TIP_THUMB * pitch])
		var roots: Dictionary = {}
		for f2 in [Hands.INDEX, Hands.MIDDLE, Hands.RING, Hands.PINKY]:
			roots[f2] = (((fl[f2] as Dictionary)["chain"]) as Array)[0]
		var rp: Vector3 = roots[Hands.PINKY]
		var rm: Vector3 = roots[Hands.MIDDLE]
		var ri: Vector3 = roots[Hands.INDEX]
		# Выпуклость в ПЛАНЕ (x, y): корень среднего ВЫШЕ хорды
		# указательный–мизинец, взятой в его точке (меньше y — ближе
		# к клавишам: средняя пястная точка кисти выдвинута вперёд).
		var ab := Vector2(ri.x, ri.y) - Vector2(rp.x, rp.y)
		var t := (Vector2(rm.x, rm.y) - Vector2(rp.x, rp.y)).dot(ab) / \
			ab.length_squared()
		var cy := Vector2(rp.x, rp.y) + ab * t
		_check(rm.y < cy.y,
			"hand %d palm arc is convex to the keys (middle above the index-pinky chord)" % h)
		_check((p["wrist"] as Vector2).y > p["knuckle_y"],
			"hand %d wrist sits below the knuckles" % h)


## Энергетическая модель: покой — аргмин нулевой энергии (решатель,
## получив кончик покоя, возвращает те же углы); прессы соседних кла-
## виш доезжают точно и в пределах гибкости (мягкий штраф: допуск
## 0.12 рад за границей).
func _energy_checks(bs: Array) -> void:
	var pitch := Hands.pitch_of(bs)
	var pose := Hands.rest_both(bs)
	for h in [Hands.LEFT, Hands.RIGHT]:
		var fingers: Dictionary = (pose[h] as Dictionary)["fingers"]
		for f in [Hands.THUMB, Hands.INDEX, Hands.MIDDLE, Hands.RING,
				Hands.PINKY]:
			var fd: Dictionary = fingers[f]
			var chain: Array = fd["chain"]
			var bones: Array = Hands.bones_px(f, pitch)
			var r: Array = fd["angles"]
			var tip: Vector3 = chain[3]
			var root: Vector3 = chain[0]
			# Покой — устойчивая точка решателя: цель = покойному кон-
			# чику, кончик возвращается НА ТО ЖЕ МЕСТО, углы не убега-
			# ют (пологая долина позволяет небольшой дрейф по углам —
			# меряется потолком, скачок ловится).
			var back: Array = Hands.ik_chain(root, bones, tip, r, r,
				f, Hands.side_of(h))
			var bangs: Array = back[0] as Array
			var n: int = (r as Array).size()
			var back_tip: Vector3 = (back[1] as Array)[3]
			_check(back_tip.distance_to(tip) < 0.06 * pitch,
				"hand %d f=%d rest re-solve keeps the tip in place (err %.2f px)" % [
					h, f, back_tip.distance_to(tip)])
			for i in n:
				var dgl: float = absf(Hands._angdiff(
					bangs[i] as float, r[i] as float))
				# Потолок 0.6 рад — от замера: покой большого стоит на
				# углах пределов, и re-solve гуляет по пологой долине
				# (кончик при этом стоит — верхняя проверка). Ловит
				# структурные скачки, а не естественный дрейф.
				_check(dgl < 0.6,
					"hand %d f=%d rest target does not wander the pose (dof %d drift %.4f)" % [
						h, f, i, dgl])
			# Свои прессы: карта решает, кто жмёт; ход кисти — как в игре.
			var sigs: Array = []
			if f == Hands.THUMB:
				for s in ["пробел:Л", "пробел:П", "глобус"]:
					if Hands.finger_of(String(s))[0] == h:
						sigs.append(s)
			else:
				for key_id_v in _letter_sigs(bs):
					var fs: Array = Hands.finger_of(String(key_id_v))
					if fs[0] == h and fs[1] == f:
						sigs.append(key_id_v)
			var lim: Array = Hands.JOINT_LIMITS[f]
			for key_id_v in sigs:
				var key_id := String(key_id_v)
				var c2: Vector2 = Hands.press_point(bs, key_id,
					Vector2(tip.x, tip.y))
				if c2 == Vector2.ZERO:
					continue
				var shift: Vector2 = Hands.shift_goal(pose, h, f, c2,
					pitch)
				var sroot: Vector3 = root + Vector3(shift.x, shift.y, 0.0)
				var tgt: Vector3 = Vector3(c2.x, c2.y,
					Hands.Z_PRESS * pitch)
				var res: Array = Hands.ik_chain(sroot, bones, tgt, r, r,
					f, Hands.side_of(h))
				var ptip: Vector3 = (res[1] as Array)[3]
				var err: float = ptip.distance_to(tgt)
				# Порог = семантике пробы хода (PRESS_TOL): сдвиг принят
				# ровно тогда, когда проба доезжает с этой точностью.
				_check(err < Hands.PRESS_TOL * pitch,
					"hand %d f=%d press of '%s' reaches (3D err %.2f px)" %
						[h, f, key_id, err])
				var pans: Array = res[0] as Array
				for i in n:
					var ang: float = pans[i] as float
					var l2: Vector2 = lim[i]
					_check(ang >= l2.x - 0.12 and ang <= l2.y + 0.12,
						"hand %d f=%d press of '%s' dof %d within flexibility (%.2f in [%.2f..%.2f])" % [
							h, f, key_id, i, ang, l2.x, l2.y])
				# Оппозиция большого: пресс ПРОБЕЛА РАСКРУЧИВАЕТ дисталь
				# (поворот > 0.05) — без поворота седловидный CMC не ра-
				# ботает (ловлено 26.10.2026: без DOF хорда недостижима).
				# «Глобус» жмётся выпрямленным большим — без оппозиции.
				if f == Hands.THUMB and key_id.begins_with("пробел"):
					var tw: float = pans[2] as float
					_check(tw > 0.05,
						"hand %d thumb press engages the opposition twist (%.3f)" % [
							h, tw])


## Микроработа суставов (26.10.2026, модель глубокого покоя): в покое
## дистальные суставы У ПОТОЛКА анатомии (PIP/DIP ~1.6..1.75 рад), по-
## тому «согнуть сильнее в доску» кисть не может — и решатель этого и
## не требует: пресс-глубина идёт ОТ ПЯСТИ (MCP сгиб растёт, дистали
## почти на месте), а разгиб (кончик дальше от корня) идёт ДИСТАЛОМ
## (PIP/DIP раскрываются раньше пястного). Выровненные веса дают кашу
## без этих фокусов — ловятся обеими пробами.
func _micro_checks(bs: Array) -> void:
	var pitch := Hands.pitch_of(bs)
	var pose := Hands.rest_both(bs)
	for h in [Hands.LEFT, Hands.RIGHT]:
		var fingers: Dictionary = (pose[h] as Dictionary)["fingers"]
		for f in [Hands.INDEX, Hands.MIDDLE, Hands.RING, Hands.PINKY]:
			var fd: Dictionary = fingers[f]
			var r: Array = fd["angles"]
			var bones: Array = Hands.bones_px(f, pitch)
			var tip: Vector3 = (fd["chain"] as Array)[3]
			var root: Vector3 = (fd["chain"] as Array)[0]
			var reach := 0.0
			for bn in bones:
				reach += bn as float
			var axis := (tip - root).normalized()
			# Пресс: цель глубже по z при том же xy — пястный сгиб
			# растёт, дистали расходятся меньше (они у потолка).
			var press_t := tip + Vector3(0.0, 0.0, -0.15 * pitch)
			var res: Array = Hands.ik_chain(root, bones, press_t, r, r,
				f, Hands.side_of(h))
			var land: float = ((res[1] as Array)[3] as Vector3) \
				.distance_to(press_t)
			var dpip_extra := (res[0] as Array)[2] as float \
				- (r[2] as float)
			_check(land < 0.06 * pitch,
				"hand %d f=%d pressed goal is reachable (err %.2f px)" % [
					h, f, land])
			# Пресс НЕ требует добора дистального сгиба: в покое PIP
			# у потолка, глубину добирает пястный сгиб.
			_check(dpip_extra < 0.05,
				"hand %d f=%d press does not need extra PIP curl (%.3f)" % [
					h, f, dpip_extra])
			# Перезаход (цель дальше покоя) — дистальный открывается.
			var overt := tip + axis * minf(0.15 * pitch,
				(reach - tip.distance_to(root)) * 0.6)
			var res2: Array = Hands.ik_chain(root, bones, overt, r, r, f,
				Hands.side_of(h))
			var dpip := absf(Hands._angdiff(
				(res2[0] as Array)[2] as float, r[2] as float))
			var ddip := absf(Hands._angdiff(
				(res2[0] as Array)[3] as float, r[3] as float))
			var dmcp2 := absf(Hands._angdiff(
				(res2[0] as Array)[0] as float, r[0] as float))
			_check(ddip + dpip + 0.35 >= dmcp2,
				"hand %d f=%d micro-extension bends distal first (pip %.3f dip %.3f mcp %.3f)" % [
					h, f, dpip, ddip, dmcp2])


## Симметрия: правая кисть — ТОЧНОЕ ЗЕРКАЛО анатомии левой. Мерило —
## МОДЕЛЬНЫЙ скелет: вектор корень−кончик (3D) зеркалится по x, y и z
## совпадают, покойные углы ПОДРАЗУМЕВАЮТСЯ ОДНИ И ТЕ ЖЕ. Клавишные
## контакты на доске несимметричны — поэтому мир сверяем не по клавишам.
## Ось зеркала — ЦЕНТР ДОМ-ГРУППЫ «ф»↔«ж» (как в diag_mirror.gd и как
## считает цель большого в hands.gd): доска асимметрична по служебным
## (слева Tab/Caps/Shift = 5.5 питча), а дом-клавиши зеркальны между
## собой. Центр окна НЕ годится: цель большого от него не зеркальна.
func _board_axis(bs: Array) -> float:
	return 0.5 * ((Hands.key_rect(bs, "ф") as Rect2).get_center().x
		+ (Hands.key_rect(bs, "ж") as Rect2).get_center().x)


## Большой В ЦИКЛЕ ТОЖЕ: его зеркало держится на оси поворота (×m,
## докстринг fk_chain) и на зеркале по построению (rest_both) —
## долина twist'а плоская, сам спуск улп-шум разводит (26.10.2026).
func _mirror_checks(bs: Array) -> void:
	var pose := Hands.rest_both(bs)
	var axs := _board_axis(bs)
	# Негативная проба: ось зеркала — дом-группа, а НЕ центр экрана
	# (цель большого считается от «ф»↔«ж»; от центра зеркало краснело
	# на ~1.5 питча — ловится только живой парой значений).
	var axs_win := root.size.x * 0.5
	var th_l := (((pose[Hands.LEFT]["fingers"] as Dictionary)[
		Hands.THUMB] as Dictionary)["chain"] as Array)[3] as Vector3
	var th_r := (((pose[Hands.RIGHT]["fingers"] as Dictionary)[
		Hands.THUMB] as Dictionary)["chain"] as Array)[3] as Vector3
	_check(absf((th_l.x - axs_win) + (th_r.x - axs_win)) > 0.05,
		"mirror axis is the home group, not the screen centre "
			+ "(screen-centre probe must differ)")
	var pl: Dictionary = pose[Hands.LEFT]
	var pr: Dictionary = pose[Hands.RIGHT]
	for f in [Hands.INDEX, Hands.MIDDLE, Hands.RING, Hands.PINKY,
			Hands.THUMB]:
		var lfd: Dictionary = (pl["fingers"] as Dictionary)[f]
		var rfd: Dictionary = (pr["fingers"] as Dictionary)[f]
		var lchain: Array = lfd["chain"]
		var rchain: Array = rfd["chain"]
		var loff: Vector3 = (lchain[0] as Vector3) - (lchain[3] as Vector3)
		var roff: Vector3 = (rchain[0] as Vector3) - (rchain[3] as Vector3)
		_check(absf(roff.x + loff.x) < 0.02,
			"finger %d root offset mirrors by x (%.2f vs %.2f)" % [
				f, roff.x, -loff.x])
		_check(absf(roff.y - loff.y) < 0.02,
			"finger %d root offset keeps y in both hands (%.2f vs %.2f)" % [
				f, roff.y, loff.y])
		_check(absf(roff.z - loff.z) < 0.02,
			"finger %d root offset keeps z in both hands (%.2f vs %.2f)" % [
				f, roff.z, loff.z])
		# Кончик зеркален ТОЛЬКО у большого: его цели (четверти
		# пробела) — зеркальная пара; дом-цели четырёх пальцев лежат
		# на несимметричных столбцах ЙЦУКЕН (зеркало несут корневые
		# смещения выше).
		var ltip: Vector3 = lchain[3] as Vector3
		var rtip: Vector3 = rchain[3] as Vector3
		if f == Hands.THUMB:
			_check(absf((ltip.x - axs) + (rtip.x - axs)) < 0.05,
				"thumb tips mirror across the board axis (%.2f, %.2f)"
					% [ltip.x - axs, rtip.x - axs])
		# Покойные углы идентичны: анатомия оная, зеркало — в FK.
		var lrest: Array = lfd["angles"]
		var rrest: Array = rfd["angles"]
		for i in Hands._dof_count(f):
			var dl: float = absf(Hands._angdiff(
				rrest[i] as float, lrest[i] as float))
			_check(dl < 0.01,
				"finger %d rest angle %d identical for both hands (%.4f)" % [
					f, i, dl])


## Правило касания пресса: малая клавиша — ЦЕНТР; большая — ближай-
## ший край с отступом в половину малой клавиши. press_goal — КОН-
## ТАКТ на плоскости, БЕЗ y-просадки: просадка теперь З (Z_PRESS) —
## старое «просаживание по экрану» должно быть мертво. Ход кисти:
## дом-цель стоит с места, низ дальнего столбца уводит кисть, после
## хода палец СГНУТ (COMFY доли размаха).
func _press_checks(bs: Array) -> void:
	var pitch := Hands.pitch_of(bs)
	var pose := Hands.rest_both(bs)
	# Малая: центр ровно.
	var center: Vector2 = Hands.press_point(bs, "а", Vector2.ZERO)
	_check(center.distance_to(
		(Hands.key_rect(bs, "а") as Rect2).get_center()) < 0.001,
		"press of a small key is its exact center")
	# Большая: без кончика — центр клавиши.
	var sh := Hands.key_rect(bs, "Shift") as Rect2
	var sg: Vector2 = Hands.press_point(bs, "Shift", Vector2.ZERO)
	_check((sg - sh.get_center()).length() < 0.01,
		"press of a big key without tip is its center")
	var tip_inside := sh.get_center()
	var sg2: Vector2 = Hands.press_point(bs, "Shift", tip_inside)
	_check(sg2.x >= sh.position.x + 0.5 * pitch - 0.01
		and sg2.x <= sh.end.x - 0.5 * pitch + 0.01,
		"press of a big key clamps tip into the inset zone")
	# press_goal — тот же контакт: просадка МЕРТВА по экрану
	# (она ушла в высоту Z_PRESS), чистое тождество без увода.
	var pg: Vector2 = Hands.press_goal(bs, "а", Vector2.ZERO)
	_check((pg - center).length() < 0.01,
		"press goal is the contact on the plane (dip moved into z)")
	var pgc: Vector2 = Hands.press_goal(bs, "Shift", tip_inside)
	_check((pgc - sg2).length() < 0.01,
		"press goal of a big key matches press point")
	# Пресс над далёкой клавишей решается (цели НЕ нулевые).
	var pinky_tip: Vector3 = (((pose[Hands.LEFT]["fingers"] as Dictionary)[
		Hands.PINKY] as Dictionary)["chain"] as Array)[3]
	var far: Vector2 = Hands.press_goal(bs, "1",
		Vector2(pinky_tip.x, pinky_tip.y))
	_check(far != Vector2.ZERO, "free press goal resolves")
	# Сдвиг кисти: дом-цель стоит с места; низ дальнего столбца уводит
	# кисть ровно к работе; ЦИФРОВОЙ ряд — дальняя ветка с COMFY.
	var pl: Dictionary = pose[Hands.LEFT]
	var home_tip: Vector3 = (((pl["fingers"] as Dictionary)[
		Hands.PINKY] as Dictionary)["chain"] as Array)[3]
	var home_root: Vector3 = (((pl["fingers"] as Dictionary)[
		Hands.PINKY] as Dictionary)["chain"] as Array)[0]
	var home_contact: Vector2 = Hands.press_point(bs, "ф", Vector2.ZERO)
	var home_shift: Vector2 = Hands.shift_goal(pose, Hands.LEFT,
		Hands.PINKY, home_contact, pitch)
	_check(home_shift.is_zero_approx(),
		"home press does not demand a whole-hand shift")
	var far_contact: Vector2 = Hands.press_point(bs, "я", Vector2.ZERO)
	var far_shift: Vector2 = Hands.shift_goal(pose, Hands.LEFT,
		Hands.PINKY, far_contact, pitch)
	_check(far_shift.length() > 0.5 * pitch,
		"bottom-row press moves the whole hand toward the key")
	var tf: Vector2 = far_contact - Vector2(home_root.x, home_root.y)
	_check(absf(Hands._angdiff(far_shift.angle(), tf.angle())) < 0.35,
		"shift drives the hand straight toward the far key")
	# Проба хода: БЕЗ хода мизинец «я» не доезжает (иначе ход не нужен).
	var tgt: Vector3 = Vector3(far_contact.x, far_contact.y,
		Hands.Z_PRESS * pitch)
	var bones: Array = Hands.bones_px(Hands.PINKY, pitch)
	var from_rest: Array = Hands.ik_chain(home_root, bones, tgt,
		((pl["fingers"] as Dictionary)[Hands.PINKY]
			as Dictionary)["angles"], [], Hands.PINKY,
		Hands.side_of(Hands.LEFT))
	var no_shift_err: float = ((from_rest[1] as Array)[3] as Vector3) \
		.distance_to(tgt)
	_check(no_shift_err >= Hands.PRESS_TOL * pitch,
		"pinky 'я' genuinely needs the hand shift without it (err %.2f)" %
			no_shift_err)
	# После хода работающий палец СГНУТ (COMFY доли размаха), а не
	# распрямлён — кисть не обязана прижимать палец в струну (3D).
	# Правило ДАЛЬНЕЙ ветки; меряется на цифре «1» (дальний ряд).
	var one_contact: Vector2 = Hands.press_point(bs, "1",
		Vector2(home_tip.x, home_tip.y))
	var reach := 0.0
	for bn in bones:
		reach += bn as float
	# Дальняя ветка: ход = формула d3 − COMFY·reach; проба решателя
	# обязана ДОЕЗЖАТЬ после хода (иначе формула без толку).
	var one_shift: Vector2 = Hands.shift_goal(pose, Hands.LEFT,
		Hands.PINKY, one_contact, pitch)
	var one_tgt: Vector3 = Vector3(one_contact.x, one_contact.y,
		Hands.Z_PRESS * pitch)
	var one_d: float = home_root.distance_to(one_tgt)
	_check(absf(one_shift.length() - (one_d - Hands.COMFY * reach)) < 0.02,
		"far-row shift mirrors the 3D overshoot beyond COMFY (%.2f vs %.2f)" % [
			one_shift.length(), one_d - Hands.COMFY * reach])
	var sroot: Vector3 = home_root \
		+ Vector3(one_shift.x, one_shift.y, 0.0)
	var land: Array = Hands.ik_chain(sroot, bones, one_tgt,
		((pl["fingers"] as Dictionary)[Hands.PINKY]
			as Dictionary)["angles"], [], Hands.PINKY,
		Hands.side_of(Hands.LEFT))
	var land_err: float = ((land[1] as Array)[3] as Vector3) \
		.distance_to(one_tgt)
	_check(land_err < Hands.PRESS_TOL * pitch,
		"far-row press lands after the shift (err %.2f px)" % [land_err])


## Z-механика (26.10.2026): ход кисти меряется ТРЁХМЕРНОЙ дистанцией
## корень→контакт. ДАЛЬНИЕ клавиши (за размах) — ход ЖИВОЙ ФОРМУЛЫ
## d3 − COMFY·reach; ближние — ход ПЕРВОЙ ДОЕЗЖАЮЩЕЙ пробы сетки
## SHIFT_TRIES, не длиннее её максимума.
func _z_checks(bs: Array) -> void:
	var pitch := Hands.pitch_of(bs)
	var pose := Hands.rest_both(bs)
	var contact: Vector2 = Hands.press_point(bs, "1", Vector2.ZERO)
	var root: Vector3 = (((pose[Hands.LEFT]["fingers"] as Dictionary)[
		Hands.PINKY] as Dictionary)["chain"] as Array)[0]
	var reach := 0.0
	for bn in Hands.bones_px(Hands.PINKY, pitch):
		reach += bn as float
	var tgt := Vector3(contact.x, contact.y, Hands.Z_PRESS * pitch)
	var d := root.distance_to(tgt)
	var shift: Vector2 = Hands.shift_goal(pose, Hands.LEFT, Hands.PINKY,
		contact, pitch)
	var want := maxf(d - Hands.COMFY * reach, 0.0)
	_check(absf(shift.length() - want) < 0.02,
		"far-row shift magnitude mirrors the 3D overshoot beyond COMFY (%.2f vs %.2f)" % [
			shift.length(), want])
	# Ближняя «я»: ход — ДОЕЗЖАЮЩАЯ проба сетки, ненулевой и не длин-
	# нее последней пробы (первый ток сетки вывел бы ход за пределы).
	var bottom: Vector2 = Hands.press_point(bs, "я", Vector2.ZERO)
	var bshift: Vector2 = Hands.shift_goal(pose, Hands.LEFT,
		Hands.PINKY, bottom, pitch)
	var tmax: float = (Hands.SHIFT_TRIES[Hands.SHIFT_TRIES.size() - 1]
		as float) * pitch
	_check(bshift.length() > 0.5 * pitch and bshift.length() <= tmax,
		"near-key shift is a working trial step, not the max (%.2f in (0..%.2f])" % [
			bshift.length(), tmax])
	# Высоты покоя в порядке: большой лежит ниже остальных (подушечка
	# на пробеле), кончики hover — над доской.
	_check(Hands.Z_TIP_THUMB > 0.0 and Hands.Z_TIP_THUMB < Hands.Z_TIP,
		"thumb hovers lower than the fingers (%.2f < %.2f)" % [
			Hands.Z_TIP_THUMB, Hands.Z_TIP])
	# Константная просадка пальца при прессе одна для ВСЕХ клавиш: z —
	# параметр модели, а не клавиши; экранная просадка retired.
	_check(Hands.Z_PRESS < 0.0 and Hands.Z_PRESS > -0.6,
		"Z_PRESS is a small dip into the key (%.2f)" % Hands.Z_PRESS)
	# Экранная просадка retired: константы PRESS_DIP больше нет —
	# старое «просаживание по экрану» не должно вернуться.
	# Экранная просадка retired: константы PRESS_DIP больше нет —
	# старое «просаживание по экрану» не должно вернуться.
	_check(not "PRESS_DIP" in load("res://scripts/hands.gd")
		.get_script_constant_map(),
		"screen-space dip constant is retired (PRESS_DIP is gone)")


## Буквенные подписи доски (прессы меряются по ним).
func _letter_sigs(bs: Array) -> Array:
	var out: Array = []
	for b in bs:
		var s := String(b["s"])
		if Kbd.is_plain_letter(s) and s != " ":
			out.append(s)
	return out


## Подсказка ведёт руки: сигнатура из _hint_keys → [рука, палец] и
## точка нажатия. Шифты — мизинцы, «←»/«↵» — правый мизинец, пробел —
## половиной своего бока; точки — центры; половины пробела — по своей
## стороне. Ширины [у пясти, у кончика] в пределах полов и потолков.
func _hint_checks(bs: Array) -> void:
	_check(Hands.hint_finger("Shift") == [Hands.LEFT, Hands.PINKY],
		"hint Shift is the left pinky")
	_check(Hands.hint_finger("ShiftR") == [Hands.RIGHT, Hands.PINKY],
		"hint ShiftR is the right pinky")
	_check(Hands.hint_finger("←") == [Hands.RIGHT, Hands.PINKY],
		"hint backspace is the right pinky")
	_check(Hands.hint_finger("↵") == [Hands.RIGHT, Hands.PINKY],
		"hint enter is the right pinky")
	_check(Hands.hint_finger("в") == [Hands.LEFT, Hands.MIDDLE],
		"hint letter uses its mapped finger")
	_check(Hands.hint_finger("чужое") == [-1, -1],
		"hint of a foreign sig does not move a hand")
	var pitch := Hands.pitch_of(bs)
	# Шифт+буква — ДВЕ руки: обе подсказки дают пальцы (автор 18.10).
	var shift_f := Hands.hint_finger("Shift")
	var key_f := Hands.hint_finger("о")
	_check(shift_f[0] != key_f[0],
		"hint Shift+letter goes to two different hands")
	# Точки: центр клавиши; половины пробела — по своей стороне.
	var vo := Hands.key_rect(bs, "о")
	_check((Hands.hint_point(bs, "о") as Vector2).distance_to(
		vo.get_center()) < 0.001, "hint point is the key center")
	var sp := Hands.key_rect(bs, "пробел")
	var pl: Vector2 = Hands.hint_point(bs, "пробел:Л") as Vector2
	var pr: Vector2 = Hands.hint_point(bs, "пробел:П") as Vector2
	_check(pl.x < sp.get_center().x and pr.x > sp.get_center().x,
		"space halves hint by opposite hand on its own side")
	_check(absf(pl.y - sp.get_center().y) < 0.001 * pitch
		and absf(pr.y - sp.get_center().y) < 0.001 * pitch,
		"space halves hint at the row height")
	# Точка отсутствующей клавиши — ноль: рука не реагирует.
	_check(Hands.hint_point(bs, "чужое") == Vector2.ZERO,
		"foreign hint point is ZERO")
	# Тело кисти меряется ширинами [у пясти, у кончика]: полы НЕ
	# теряются на мелкой доске, потолки НЕ мешают на крупной.
	var wb: Array = Hands.widths_of(pitch)
	_check((wb[0] as float) >= 9.0 and (wb[0] as float) <= 21.0,
		"palm width in bounds on the test board")
	_check((wb[1] as float) >= 6.0 and (wb[1] as float) <= 12.0,
		"tip width in bounds on the test board")
	_check((Hands.widths_of(20.0)[0] as float) >= 9.0
		and (Hands.widths_of(20.0)[1] as float) >= 6.0,
		"width floor holds on a small board")
	_check((Hands.widths_of(400.0)[0] as float) <= 21.0
		and (Hands.widths_of(400.0)[1] as float) <= 12.0,
		"width ceiling holds on a big board")
	_check((wb[0] as float) > (wb[1] as float), "finger is tapered")


## КОНТУР (автор 27.10.2026): кисть на экране — ОДНА замкнутая внешняя
## граница (объединение ладони и пальцев), а не скелет. Держит: все
## суставы внутри контура (палец не оторвался), нажатие не рвёт контур
## и ставит палец на клавишу, контур не уезжает от доски, демонстрация
## подсказки поднимает палец и возвращается ровно в покой.
func _contour_checks(bs: Array) -> void:
	var pitch := Hands.pitch_of(bs)
	var rest := Hands.rest_both(bs)
	_check(not rest.is_empty(), "contour: rest pose is built")
	if rest.is_empty():
		return
	# Рамка доски — по самим клавишам (buttons — единственный источник).
	var br := Rect2()
	var first := true
	for b in bs:
		var r := b["r"] as Rect2
		if first:
			br = r
			first = false
		else:
			br = br.merge(r)
	for h in [Hands.LEFT, Hands.RIGHT]:
		var poly := Hands.hand_outline(rest, {}, pitch, h)
		_check(poly.size() >= 12,
			"hand %d contour is built (%d points)" % [h, poly.size()])
		_check(absf(Hands._poly_area(poly)) > pitch * pitch,
			"hand %d contour has positive area" % h)
		var fingers: Dictionary = (rest[h] as Dictionary)["fingers"] as Dictionary
		for f in fingers.keys():
			var ch: Array = (fingers[f] as Dictionary)["chain"] as Array
			for i in [0, ch.size() - 1]:
				var p3: Vector3 = ch[i] as Vector3
				_check(Geometry2D.is_point_in_polygon(
					Vector2(p3.x, p3.y), poly),
					"hand %d finger %d joint %d is inside the contour"
					% [h, f, i])
		# Ладонь уходит за нижний ряд (пятка), пальцы — вглубь доски:
		# дальше двух питчей в стороны и трёх с половиной вниз рука не
		# живёт. Выезд за эти поля — сломанная геометрия, а не поза.
		var lo := Vector2(br.position.x - 2.0 * pitch,
			br.position.y - 3.5 * pitch)
		var hi := Vector2(br.end.x + 2.0 * pitch,
			br.end.y + 3.5 * pitch)
		var out := 0
		for p in poly:
			if p.x < lo.x or p.x > hi.x or p.y < lo.y or p.y > hi.y:
				out += 1
		_check(out == 0,
			"hand %d contour stays near the board (%d points out)"
			% [h, out])
		# Нажатие: контур цел, точка контакта внутри, форма изменилась.
		for s in ["а", "о", "в", "л", "ы", "д", "ф", "ж", "я", "ъ",
				"1", "0", "пробел:Л", "пробел:П", "Shift", "ShiftR",
				"←", "↵", "глобус"]:
			var hf := Hands.finger_of(s)
			if (hf[0] as int) != h:
				continue
			var rt := Hands.rest_tip(rest, h, hf[1] as int)
			var c := Hands.press_point(bs, s, rt)
			if c == Vector2.ZERO:
				continue
			# Кисть ходит за работой — как в игре (_hands_hit считает
			# shift_goal); дальняя клавиша без хода недостижима.
			var sh := Hands.shift_goal(rest, h, hf[1] as int, c, pitch)
			var pressed := Hands.hand_outline(rest,
				{h: {(hf[1] as int): [c, 1.0]}}, pitch, h, sh)
			_check(pressed.size() >= 12,
				"pressed '%s' keeps one contour" % s)
			# Кончик решателя может не дотянуться до центра клавиши на
			# пиксели (это пресс, а не телепорт); контур обязан быть РЯДОМ
			# с клавишей — не дальше трети питча.
			_check(_dist_to_poly(c, pressed) <= 0.35 * pitch,
				"pressed '%s' contour reaches the key (%.1f px)"
				% [s, _dist_to_poly(c, pressed)])
			_check(not _same_poly(pressed, poly),
				"pressing '%s' moves the contour" % s)
	# Демонстрация подсказки — чистая фаза: покой, выдержка, пауза,
	# симметрия подъёма/спада, период.
	_check(Hands.hint_depth(0.0) == 0.0, "hint demo starts at rest")
	_check(Hands.hint_depth(Hands.HINT_RISE_T
		+ Hands.HINT_HOLD_T * 0.5) == 1.0, "hint demo holds the key")
	_check(Hands.hint_depth(Hands.HINT_CYCLE_T
		- Hands.HINT_GAP_T * 0.5) == 0.0, "hint demo rests between cycles")
	_check(absf(Hands.hint_depth(Hands.HINT_RISE_T * 0.5)
		- Hands.hint_depth(Hands.HINT_CYCLE_T - Hands.HINT_GAP_T
		- Hands.HINT_FALL_T * 0.5)) < 0.02,
		"hint demo rise and fall are symmetric")
	_check(absf(Hands.hint_depth(0.3)
		- Hands.hint_depth(0.3 + Hands.HINT_CYCLE_T)) < 1e-5,
		"hint demo repeats every cycle")
	var mono := true
	var prev := -1.0
	for i in 21:
		var d := Hands.hint_depth(Hands.HINT_RISE_T * (float(i) / 20.0))
		if d < prev - 1e-6:
			mono = false
		prev = d
	_check(mono, "hint demo rises monotonically")


## Одинаковы ли контуры (порядок вершин у Clipper устойчив: изменилась
## поза — изменились и точки).
func _same_poly(a: PackedVector2Array, b: PackedVector2Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if a[i].distance_to(b[i]) > 0.01:
			return false
	return true


## Расстояние от точки до контура (0 — внутри). Мера «контур дошёл до
## клавиши»: кончик решателя прощает пиксели, поэтому сравниваем не
## попадание, а близость.
func _dist_to_poly(p: Vector2, poly: PackedVector2Array) -> float:
	if poly.size() < 3:
		return INF
	if Geometry2D.is_point_in_polygon(p, poly):
		return 0.0
	var best := INF
	var n := poly.size()
	for i in n:
		var q := Geometry2D.get_closest_point_to_segment(
			p, poly[i], poly[(i + 1) % n])
		best = minf(best, p.distance_to(q))
	return best
