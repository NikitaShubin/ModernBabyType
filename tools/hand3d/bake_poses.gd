extends SceneTree
## Запекание поз нажатий из 3D-исследования кисти в данные игры.
##
## Игра не решает IK (нажатие стоило бы 0.5–3.4 с): поза каждого нажатия
## решается ЗДЕСЬ, тем же кодом, что и в просмотрщике доски
## (board_viewer.gd._sim_stroke), и кладётся в game/scripts/hands_poses.gd.
## В игре остаётся FK и проекция силуэта.
##
## Запуск (образ тот же, что у игры):
##   docker run --rm --user $(id -u):$(id -g) -v $PWD:/work \
##     -e HOME=/tmp/mbt-home -w /work/tools/hand3d mbt-godot \
##     --headless --path /work/tools/hand3d --script res://bake_poses.gd
##
## Файл данных — сгенерированный: правки руками затрёт следующее запекание.

const HandModel := preload("res://hand_model.gd")
const ArmModel := preload("res://arm_model.gd")
const HomePose := preload("res://home_pose.gd")
const IK := preload("res://ik.gd")
const Kbd3D := preload("res://kbd3d.gd")

const OUT := "/work/game/scripts/hands_poses.gd"

## Клавиши, которые игра не нажимает: они заблокированы (подпись
## приглушена, тап мимо), поза им не нужна.
const BLOCKED := ["Tab", "Caps", "Ctrl", "Win", "Alt"]

## Радиусы кожи большого пальца — из board_viewer.gd (там же THUMB_R).
const THUMB_R := [11.8, 10.8, 9.6, 6.6]

## Числа траектории нажатия — из board_viewer.gd (там же и объяснения).
const SIM_HOVER_DIV := 30.0
const SIM_HOVER_MIN := 4.0
const SIM_SETTLE_EPS := 0.2
const KEY_HOVER := 12.0
const THUMB_HOVER := 5.0
const BOT_W := {"elbow_x": 10.0, "elbow_y": 10.0, "forearm_abd": 10.0}
const BOT_PRIOR := 2.0

## КИСТЬ В НАЖАТИИ ДЕРЖИТ ПОЗУ (автор 06.11.2026: «пальцы остаются
## скрюченными, как будто держат свои клавиши»). Решатель поворачивал кисть
## пронацией/сгибом запястья, потому что это дешёвый способ дотянуться
## (вес пронации 4 против веса локтя 16000): на «н» пронация уходила на
## −22°, и те же углы пальцев, что в покое, проецировались крючками —
## кисть-то повернулась. Дотягиваться должна САМА РУКА (перенос локтя) и
## свой палец, а не поворот кисти: тогда поза нажатия — это покой,
## сдвинутый и с одним вытянутым пальцем, и она читается покоем.
## Вес выше локтя (16000) в 60 раз — поворот не выбирается никогда.
const HOLD_W := {"wrist_flex": 1.0e6, "wrist_dev": 1.0e6,
	"pronation": 1.0e6, "forearm_flex": 1.0e6, "forearm_abd": 1.0e6}

var _keys: Array = []


func _initialize() -> void:
	_keys = Kbd3D.keys()
	var roots := {}
	for side in ["L", "R"]:
		roots[side] = float(HomePose.HOME_ROOTS[side])
	print("bake: roots ", roots)

	var home := {}
	for side in ["L", "R"]:
		var t0 := Time.get_ticks_msec()
		home[side] = HomePose.build(side, float(roots[side]))
		print("bake: home %s built in %.1f s" % [side,
			(Time.get_ticks_msec() - t0) / 1000.0])

	var press := {"L": {}, "R": {}}
	var total := 0
	for side in ["L", "R"]:
		var other := "R" if side == "L" else "L"
		var rx := float(roots[side])
		var ro := float(roots[other])
		var foreign := _foreign_pose(side, rx, ro, home[other])
		for k in _keys.size():
			var key: Dictionary = _keys[k]
			var s := String(key["s"])
			if BLOCKED.has(s):
				continue
			if s == "пробел":
				# Пробел жмут ОБЕ руки своей половиной: у каждой свой
				# запечённый пресс, подпись — как у игры.
				s = "пробел:Л" if side == "L" else "пробел:П"
			var t0 := Time.get_ticks_msec()
			var stroke := _sim_stroke(side, k, home[side], rx, foreign)
			# Двигается ТОЛЬКО нажимающий палец: остальные пальцы и
			# большой в позе нажатия — ровно как в покое. Решатель
			# подгибает соседние пальцы под клиренс клавиш (pair
			# clearance) — в 3D это верно, но в проекции сверху
			# подгиб безымянного читался сильнее, чем ход среднего, и
			# казалось, что нажали не ту клавишу (автор 06.11.2026: «в» и
			# «л» дёргают безымянный). Поза — данные, поэтому правка
			# живёт здесь, в 3D-позе, а 2D лишь наследует.
			_still_idle(stroke["press"], home[side], String(stroke["ray"]))
			var flat := _flat(stroke["press"])
			if flat.size() != 29:
				push_error("bake: '%s' side %s gave %d angles" % [
					s, side, flat.size()])
				quit(1)
				return
			press[side][s] = flat
			total += 1
			print("bake: %s %-9s %.2f s glide %.1f mm" % [side, s,
				(Time.get_ticks_msec() - t0) / 1000.0,
				float(stroke["glide"])])
	_write(roots, home, press)
	print("bake: %d presses written to %s" % [total, OUT])
	quit(0)


## Оставить в позе нажатия без движения всё, кроме нажимающего пальца.
##
## Решатель нажатия подгибает соседние пальцы (клиренс клавиш и зазор
## между пальцами) — в 3D это физически верно, но в проекции сверху
## подгиб читается как нажатие чужого пальца (автор 06.11.2026: «в» и
## «л» дёргают безымянный). Игра смешивает позу нажатия с покоем,
## поэтому достаточно вернуть соседям углы покоя: тогда при нажатии
## движется ровно нажимающий палец плюс жёсткий ход кисти от плеча.
##
## Это правка 3D-ПОЗЫ, а не 2D: запечённые данные и есть модель, игра
## лишь проецирует их.
func _still_idle(p: Dictionary, home: Dictionary, target: String) -> void:
	var hf: Dictionary = home["fingers"] as Dictionary
	for ray in HandModel.FINGERS:
		if ray == target:
			continue
		(p["fingers"] as Dictionary)[ray] = \
			(hf[ray] as Dictionary).duplicate(true)
	if target != "I":
		p["thumb"] = (home["thumb"] as Dictionary).duplicate(true)
		p["thumb_dof"] = int(home.get("thumb_dof", 4))


## Поза → плоский список 29 чисел: [8] плечо, [4×4] пальцы II..V,
## [5] большой. Лерпится покоординатно — потому и плоская.
func _flat(p: Dictionary) -> Array:
	var out := []
	var arm: Dictionary = p.get("arm", {}) as Dictionary
	for j in ArmModel.ALL_JOINTS:
		out.append(float(arm.get(j, 0.0)))
	for ray in HandModel.FINGERS:
		var a: Dictionary = (p["fingers"] as Dictionary)[ray] as Dictionary
		var fl: Array = HandModel.FLEX[ray]
		var fan: float = float(HandModel.FAN[ray])
		out.append(float(a.get("mcp", fl[0])))
		out.append(float(a.get("pip", fl[1])))
		out.append(float(a.get("dip", fl[2])))
		out.append(float(a.get("fan", fan)))
	var t := HandModel.thumb_of_pose(p)
	for j in HandModel.THUMB_JOINTS:
		out.append(float(t.get(j, HandModel.THUMB_REST[j])))
	return out


func _write(roots: Dictionary, home: Dictionary, press: Dictionary) -> void:
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	if f == null:
		push_error("bake: cannot write %s" % OUT)
		return
	f.store_line("# СГЕНЕРИРОВАНО tools/hand3d/bake_poses.gd — не править руками.")
	f.store_line("#")
	f.store_line("# Позы кистей из 3D-исследования (tools/hand3d) в плоском виде:")
	f.store_line("#   [0..7]  плечо: " + str(ArmModel.ALL_JOINTS))
	f.store_line("#   [8..23] пальцы II..V: mcp, pip, dip, fan (градусы)")
	f.store_line("#   [24..28] большой: " + str(HandModel.THUMB_JOINTS))
	f.store_line("# Перезапекание — см. шапку bake_poses.gd.")
	f.store_line("class_name HandsPoses")
	f.store_line("extends RefCounted")
	f.store_line("")
	f.store_line("const ROOT_MM := {")
	for side in ["L", "R"]:
		f.store_line("\t\"%s\": %.6f," % [side, float(roots[side])])
	f.store_line("}")
	f.store_line("")
	f.store_line("const HOME := {")
	for side in ["L", "R"]:
		f.store_line("\t\"%s\": %s," % [side, _arr(_flat(home[side]))])
	f.store_line("}")
	f.store_line("")
	f.store_line("const PRESS := {")
	for side in ["L", "R"]:
		f.store_line("\t\"%s\": {" % side)
		var d: Dictionary = press[side]
		var keys := d.keys()
		keys.sort()
		for k in keys:
			f.store_line("\t\t\"%s\": %s," % [_esc(String(k)), _arr(d[k])])
		f.store_line("\t},")
	f.store_line("}")
	f.close()


func _arr(a: Array) -> String:
	var parts := []
	for v in a:
		parts.append("%.4f" % float(v))
	return "[" + ", ".join(parts) + "]"


func _esc(s: String) -> String:
	return s.replace("\\", "\\\\").replace("\"", "\\\"")


# ---- мир ↔ локальная рама кисти (как в board_viewer.gd) ----------------

func _w(side: String, root_x: float, q: Vector3) -> Vector3:
	if side == "R":
		return Vector3(root_x - q.x, q.y, q.z)
	return Vector3(root_x + q.x, q.y, q.z)


func _lp(side: String, rx: float, p: Vector3) -> Vector3:
	if side == "R":
		return Vector3(-(p.x - rx), p.y, p.z)
	return Vector3(p.x - rx, p.y, p.z)


func _loc(side: String, root_x: float, w: Vector3) -> Vector3:
	return _lp(side, root_x, w)


func _pad_of_pose(side: String, ray: String, p: Dictionary) -> Vector3:
	var xf := ArmModel.hand_transform(p.get("arm", {}))
	if ray == "I":
		return xf * HandModel.thumb_pad(HandModel.thumb_fk(
			HandModel.thumb_of_pose(p)))
	return xf * HandModel.finger_pad(ray,
		HandModel.finger_fk(ray, p["fingers"][ray]))


## Другая кисть капсулами в локальной раме ЭТОЙ — препятствие решателя.
func _foreign_pose(side: String, rx: float, ro: float,
		p: Dictionary) -> Array:
	var other := "R" if side == "L" else "L"
	var xo := ArmModel.hand_transform(p.get("arm", {}))
	var out := []
	var it: PackedVector3Array = HandModel.thumb_fk(
		HandModel.thumb_of_pose(p))["pts"]
	for i in 3:
		out.append({"a": _loc(side, rx, _w(other, ro, xo * it[i])),
			"b": _loc(side, rx, _w(other, ro, xo * it[i + 1])),
			"r": maxf(float(THUMB_R[i]), float(THUMB_R[i + 1])),
			"ra": float(THUMB_R[i]), "rb": float(THUMB_R[i + 1])})
	for f in HandModel.FINGERS:
		var fp: PackedVector3Array = HandModel.finger_fk(
			f, p["fingers"][f])["pts"]
		for i in 3:
			out.append({"a": _loc(side, rx, _w(other, ro, xo * fp[i])),
				"b": _loc(side, rx, _w(other, ro, xo * fp[i + 1])),
				"r": maxf(float(HandModel.SKIN_R[f][i]),
					float(HandModel.SKIN_R[f][i + 1])),
				"ra": float(HandModel.SKIN_R[f][i]),
				"rb": float(HandModel.SKIN_R[f][i + 1])})
	return out


## Нижний ряд — своя цена и свой стоп кисти (author #11): см. board_viewer.
func _row_profile(o: Dictionary, s: String) -> Dictionary:
	var w: Dictionary = (o.get("weights", {}) as Dictionary).duplicate(true)
	for j in HOLD_W.keys():
		w[j] = HOLD_W[j]
	o["weights"] = w
	if (Kbd3D.ROW_BOTTOM as Array).has(s):
		o["dev_stop"] = true
		var bw: Dictionary = (o.get("weights", {}) as Dictionary).duplicate(true)
		for j in BOT_W.keys():
			bw[j] = BOT_W[j]
		o["weights"] = bw
		o["prior"] = BOT_PRIOR
	return o


## Полный ход одного нажатия — копия board_viewer.gd._sim_stroke (там же
## все объяснения: наведение, посадка, добор глубины локтём).
func _sim_stroke(side: String, k: int, base: Dictionary, rx: float,
		foreign: Array) -> Dictionary:
	var key: Dictionary = _keys[k]
	var s := String(key["s"])
	var xy := Vector2.ZERO
	var ray := "I"
	if s != "пробел":
		var c := Kbd3D.centre(key)
		xy = Vector2(c.x, c.y)
		ray = String(Kbd3D.hand_finger(s, xy.x)[1])
	else:
		var pad := _pad_of_pose(side, "I", base)
		var w := _w(side, rx, pad)
		var r: Rect2 = key["r"]
		var m := 3.0
		xy = Vector2(clampf(w.x, r.position.x + m, r.end.x - m),
			clampf(w.y, r.position.y + m, r.end.y - m))
	var cur_pad := _pad_of_pose(side, ray, base)
	var lp := _lp(side, rx, Vector3(xy.x, xy.y, 0.0))
	var glide := Vector2(lp.x - cur_pad.x, lp.y - cur_pad.y).length()
	var rise := clampf(glide / SIM_HOVER_DIV, 0.0, 1.0)
	var hz := maxf(cur_pad.z, Kbd3D.FACE_Z
		+ (THUMB_HOVER if ray == "I" else KEY_HOVER) * rise)
	var hover_t := Vector3(lp.x, lp.y, hz)
	var deep := _lp(side, rx, Vector3(xy.x, xy.y, Kbd3D.FACE_Z - Kbd3D.TRAVEL))
	var opts := _row_profile({"arm": true, "thumb_dof": 4,
		"clear_z": Kbd3D.FACE_Z, "clear_w": 100.0, "pair_w": 100.0,
		"dir_w": 0.0, "foreign": foreign, "hover_z": hz}, s)
	var hov: Dictionary
	var pose: Dictionary
	if glide < SIM_HOVER_MIN:
		hov = base.duplicate(true)
	else:
		hov = (IK.solve_chain(ray, hover_t, base, opts)["pose"]
			as Dictionary).duplicate(true)
		var hpad := _pad_of_pose(side, ray, hov)
		hov["arm"]["elbow_z"] = float(hov["arm"].get("elbow_z", 0.0)) \
			+ (hover_t.z - hpad.z)
	var press_opts: Dictionary = opts.duplicate(true)
	press_opts["arm"] = false
	var settled: Dictionary = hov.duplicate(true)
	pose = hov.duplicate(true)
	for i in 4:
		var r2: Dictionary = IK.solve_chain(ray, deep, settled, press_opts)
		pose = (r2["pose"] as Dictionary).duplicate(true)
		var d := deep.z - _pad_of_pose(side, ray, pose).z
		if absf(d) < SIM_SETTLE_EPS:
			break
		settled = pose.duplicate(true)
		settled["arm"]["elbow_z"] = float(settled["arm"]["elbow_z"]) + d
	var pad2 := _pad_of_pose(side, ray, pose)
	if absf(deep.z - pad2.z) > 0.02:
		pose["arm"]["elbow_z"] = float(pose["arm"].get("elbow_z", 0.0)) \
			+ (deep.z - pad2.z)
		pose = (IK.solve_chain(ray, deep, pose, press_opts)["pose"]
			as Dictionary).duplicate(true)
		pad2 = _pad_of_pose(side, ray, pose)
	pose["arm"]["elbow_z"] = float(pose["arm"].get("elbow_z", 0.0)) \
		+ (deep.z - pad2.z)
	return {"hover": hov, "press": pose, "glide": glide, "hz": hz,
		"hover_t": hover_t, "deep": deep, "ray": ray}
