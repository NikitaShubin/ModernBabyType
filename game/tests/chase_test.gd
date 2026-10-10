extends SceneTree
## Инвариантный тест погони: гоняем НАСТОЯЩИЙ цикл игры с живым вводом
## (верные клавиши, опечатки с кумулятивным откатом, Backspace) и на
## каждом кадре проверяем правило укола целиком:
##  * игра НЕ ИДЁТ ни одного кадра в состоянии «строка ежа > строки
##    зайца» — по правилу это уже укол (жалоба: откат через угол строк
##    проходил бесплатно, заяц уходил из погони);
##  * укол невозможен, пока строка ежа меньше строки зайца: там ежу
##    ещё целая строка миль (жалоба «ёж уколол с разных строк»);
##  * на кадре укола ёж не сдвинулся, а табло застыла: на одной строке
##    заяц ровно в Д от ежа (с капами), после отката через угол — строго
##    на строке ежа и тоже ровно в Д.
##
## Запуск: godot --headless --path game --script res://tests/chase_test.gd
## Код выхода 0 — инвариант ни разу не нарушен.

var _main: Node = null
var _frame := 0
var _failures: Array[String] = []
var _rng := RandomNumberGenerator.new()
## Сколько «ходов» героя уже сделано (для выбора ввода).
var _turn := 0
## Состояние до конца эпизода: ждём, пока ёж догонит.
var _running := false
var _episodes := 0
var _pricks := 0
## Уколы по видам: 1 — одна строка (чистая геометрия),
## 2 — откат через угол строк (строка ежа впереди строки зайца).
var _prick_same := 0
var _prick_cross := 0
## Сколько угловых табло проверено «заяц на строке ежа, ровно в Д».
var _corner_checked := 0
## Табло застывшего укола: снимок первого кадра проигрыша.
var _lost_ex := -1.0
var _lost_hero := Vector2.ZERO
## Позиция ежа на прошлом кадре — чтобы поймать сдвиг именно НА кадре
## укола (шаг ежа делается уже после детекции).
var _prev_ex := 0.0
## Самая большая дистанция «ёж впереди по оси, но укола нет»: это
## состояние у края строки, где укол быть НЕ должен (жалоба).
var _closest := -999.0
var _frames_played := 0
## Проверок «заяц на кадре укола стоит на расстоянии контакта» и
## средний зазор на них (px). Ноль проверок — тест прошёл вхолостую.
var _contact_checked := 0
var _touch_gap_sum := 0.0
var _touch_gap_n := 0
## Кадров, проведённых в каждом сценарии (для контроля покрытия).
var _scenario_frames := [0, 0, 0]
var _scenario := 0
## Сколько раз Backspace реально откатил зайца (а не стёр метку).
var _retreats := 0


func _check(cond: bool, what: String) -> void:
	if not cond:
		_failures.append(what)


func _initialize() -> void:
	_rng.seed = 20261003
	var scene: PackedScene = load("res://scenes/main.tscn")
	_main = scene.instantiate()
	# Инвариант погони проверяется на живом цикле, а не в меню игроков.
	_main.skip_menu = true
	_main.all_keys_override = 1
	root.add_child(_main)


## Есть ли сейчас зрительный контакт? Обе координаты на общей сквозной
## оси, дистанция укола D. Контакт по правилу игры — ровно это.
func _d() -> float:
	var h: float = _main._lin(_main.cursor_line, float(_main.cursor_pos))
	var e: float = _main._lin(_main.enemy_line, (_main.enemy_x - _main.margin) / _main.char_w)
	return e - h


func _D() -> float:
	return _main._touch_chars() + _main.CONTACT_SLACK


func _start_episode() -> void:
	# Каждый третий эпизод — в обычном режиме (буквы серые, игра проходит
	# их сама). Там шаг назад за ошибку идёт по СВОИМ клеткам, то есть
	# через серые символы, и откаты сильнее: именно такие откаты перебрасывали
	# зайца через угол строк (жалоба автора). На «все клавиши» откат был бы
	# ровно на клетку, и этот случай проверял бы только тривиальный путь.
	if _episodes % 3 == 0:
		_main.all_keys_override = 0
	else:
		_main.all_keys_override = 1
	_main._new_level()
	_main.grace_t = 0.0
	_main.hedge_active = true
	_main.enemy_line = 0
	# Три сценария, чтобы покрыть все виды угла:
	#  0) Ёж ещё на строке 0 (сзади), заяц на строке 1. Строка ежа
	#     меньше строки зайца — укол быть НЕ должен никогда: до зайца
	#     ежу целая строка миль (собственная за post- и pre-туннелем).
	#  1) Обе на строке 1: чистая геометрия, догон.
	#  2) Заяц в конце строки 1, ёж только что перешёл в неё и стоит в
	#     pre-туннеле. Через два десятка ходов роняем зайца на строку
	#     назад — ровно как кумулятивная опечатка. Это и есть жалоба
	#     автора: строка ежа впереди, по оси заяц ещё «впереди», а
	#     укол обязан быть, и табло — честная, заяц у ежа на его строке.
	_scenario = _rng.randi_range(0, 2)
	var l0 := float(_main.display_lines[0].length())
	match _scenario:
		0:
			_main.cursor_line = 1
			_main.cursor_pos = 0
			_main.enemy_line = 0
			_main.enemy_x = _main.margin + l0 * _main.char_w * _rng.randf_range(0.75, 1.15)
		1:
			_main.cursor_line = 1
			_main.cursor_pos = int(_rng.randf_range(3.0, 8.0))
			_main.enemy_line = 1
			_main.enemy_x = _main.margin + _rng.randf_range(0.0, 1.0) * _main.char_w
		2:
			_main.cursor_line = 1
			_main.cursor_pos = _main.display_lines[1].length() - 1
			_main.enemy_line = 1
			_main.enemy_x = _main.margin - _rng.randf_range(1.5, 4.0) * _main.char_w
			_main.hero_r = _main._hero_pos()
	_running = true
	_turn = 0
	_lost_ex = -1.0


func _hero_advance() -> void:
	# Один «ход» героя: верная клавиша, опечатка (откат) или Backspace.
	var roll := _rng.randf()
	if roll < 0.62:
		# Верный ввод: серые символы пропускаются — это прыжок вперёд.
		_main._type_char(_main._current())
	elif roll < 0.90:
		# Опечатка: кумулятивный откат назад. Именно он перебрасывает
		# зайца через границу строк — главный источник жалобы.
		var cur: String = _main._current()
		var bad := "ы" if cur.to_lower() != "ы" else "ж"
		_main._type_char(bad)
	else:
		# Backspace: стирает метку, чинит впереди, а когда стирать нечего —
		# откатывает зайца на клетку назад. Откат опасен по правилу укола
		# так же, как опечатка, поэтому проверяем его последствия сразу.
		_backspace_turn()


## Backspace и проверка отката: курсор уходит РОВНО на клетку назад по
## сквозной оси, клетка снова становится ненабранной (буква появляется
## перед зайцем), счётчики набора не трогаются. Если отката не вышло
## (стирали метку или чинили впереди) — курсор не должен уехать назад.
func _backspace_turn() -> void:
	var before: float = _main._lin(_main.cursor_line, float(_main.cursor_pos))
	var ok0: int = _main.typed_ok
	var bad0: int = _main.typed_bad
	var marks0: int = _main.errors.size()
	_main._backspace()
	var after: float = _main._lin(_main.cursor_line, float(_main.cursor_pos))
	if after < before:
		_retreats += 1
		# Откат Backspace отменяет последнюю НАБРАННУЮ букву и перепрыгивает
		# серые символы (на «все клавиши» шаг равен ровно клетке — там это
		# и проверяем: шаг назад у опечатки тоже ровно символ, см.
		# marks_test). Откат всегда НАЗАД, форсеред разрешён только
		# «починить метку впереди» — он ниже, отдельной веткой.
		if _main.all_keys_override == 1 and absf(after - (before - 1.0)) > 0.001:
			_failures.append("frame %d: retreat moved %.2f chars, expected exactly 1 back"
				% [_frame, before - after])
		if _main.passed.has(_main._key(_main.cursor_line, _main.cursor_pos)):
			_failures.append("frame %d: retreated cell is still marked passed (letter not restored)"
				% _frame)
		if _main.typed_ok != ok0 or _main.typed_bad != bad0:
			_failures.append("frame %d: retreat changed the typing counters" % _frame)
	elif after > before + 0.001:
		# Вперёд — это «починить метку впереди»: заяц встаёт на клетку с
		# меткой, а та сразу проходит серые символы после неё, поэтому
		# расстояние тут не фиксировано. Проверяем суть: снята ровно одна
		# метка, и заяц стоит там, где игра ждёт нажатия (активная буква
		# или клетка с меткой).
		if marks0 - _main.errors.size() != 1:
			_failures.append("frame %d: typo fix forward by %.2f chars did not clear exactly one mark"
				% [_frame, after - before])
		var cur: String = _main._current()
		if cur != "" and not _main._is_active(cur) and not _main.errors.has(_main._key(_main.cursor_line, _main.cursor_pos)):
			_failures.append("frame %d: typo fix left the hare on an auto-passed cell «%s»"
				% [_frame, cur])


func _process(_dt: float) -> bool:
	_frame += 1

	# --- Инвариант на КАЖДОМ кадре, независимо от сценария. -------------
	if _main.state == "lost" and _main._last_reason == "behind":
		# Укол состоялся. Проверяем его следствия, а не причину: причину
		# решает игра, мы ловим нарушения правила.
		if _lost_ex < 0.0:
			# Ёж не имеет права сдвинуться НА кадре укола: шаг делается
			# уже после детекции, а состояние стало «проигрыш».
			if absf(_main.enemy_x - _prev_ex) > 0.01:
				_failures.append("frame %d: hedgehog moved ON the prick frame (%.2f px)"
					% [_frame, _main.enemy_x - _prev_ex])
			_lost_ex = _main.enemy_x
			_lost_hero = _main.hero_r
		else:
			# Табло застывшего укола не едет: ни ёж, ни заяц.
			if absf(_main.enemy_x - _lost_ex) > 0.01:
				_failures.append("frame %d: hedgehog moved after the prick (%.2f px)"
					% [_frame, _main.enemy_x - _lost_ex])
			elif _main.hero_r.distance_to(_lost_hero) > 0.01:
				_failures.append("frame %d: prick tableau is not frozen" % _frame)
		var same_row: bool = _main.enemy_line == _main.cursor_line
		if _main.enemy_line < _main.cursor_line:
			# Строка ежа позади: до зайца ежу целая строка миль, укола
			# быть не может ни при каком расстоянии по оси.
			_failures.append("frame %d: prick while hedge row is BEHIND the hero row (hedge_line=%d hero_line=%d d=%.2f D=%.2f)"
				% [_frame, _main.enemy_line, _main.cursor_line, _d(), _D()])
		elif not same_row:
			# Откат через угол строк: укол по самому событию «строка ежа
			# впереди строки зайца», расстояние не проверяется. Но табло
			# обязано быть честной: заяц СТРОГО на строке ежа и ровно в Д
			# от него, шары касаются.
			_prick_cross += 1
			_pricks += 1
			_corner_checked += 1
			var dy: float = _main.hero_r.y - _main._track_cy(_main.enemy_line)
			if absf(dy) > 0.5:
				_failures.append("frame %d: hare not on the hedgehog's row after a corner prick (dy=%.1f px)"
					% [_frame, dy])
			var cgap: float = _main.hero_r.x - (_main.enemy_x + _main._hedge_half())
			if absf(cgap) > 0.5:
				_failures.append("frame %d: corner prick not exactly at contact distance (gap=%.1f px)"
					% [_frame, cgap])
			_touch_gap_sum += cgap
			_touch_gap_n += 1
		else:
			_prick_same += 1
			_pricks += 1
			# На кадре укола заяц обязан стоять РОВНО на расстоянии
			# контакта — всегда, а не когда картинка догнала курсор:
			# табло ставится принудительно (жалоба 10.2026: «заяц
			# останавливается сильно до, а игре уже конец»).
			_contact_checked += 1
			var gap: float = _main.hero_r.x - (_main.enemy_x + _main._hedge_half())
			if absf(gap) > 0.5:
				_failures.append("frame %d: hare not exactly at contact distance (gap=%.1f px)"
					% [_frame, gap])
			else:
				_touch_gap_sum += gap
				_touch_gap_n += 1

	if _main.state != "playing":
		# Укол или победа — начинаем новый эпизод.
		_episodes += 1
		if _failures.size() > 8:
			_report()
			return true
		_start_episode()
		return false

	# --- Пока игра идёт: строка ежа впереди строки зайца — уже укол, --
	# значит такое состояние не должно прожить ни одного кадра. Это и
	# есть жалоба: откат через угол строк проходил бесплатно.
	if _main.hedge_active and _main.grace_t <= 0.0 and _main.enemy_line > _main.cursor_line:
		_failures.append("frame %d: still playing with hedge row AHEAD of the hero row (hedge_line=%d hero_line=%d d=%.2f D=%.2f)"
			% [_frame, _main.enemy_line, _main.cursor_line, _d(), _D()])

	if not _running:
		_start_episode()
		return false

	# --- Ввод героя: не каждый кадр, с паузами. -----------------------
	if _rng.randf() < 0.55:
		# Не даём зайцу убежать за экран: держим его в середине.
		if _scenario == 2 and _turn < 24:
			# Ждём, пока ёж вберётся в строку, — и роняем зайца назад.
			_turn += 1
		elif _scenario == 2 and _main.cursor_line > 0:
			_main.cursor_line -= 1
			_main.cursor_pos = _main.display_lines[_main.cursor_line].length() - 1
			_turn += 1
		elif _main.cursor_pos < 2 and _main.cursor_line > 0:
			# Откатываем куда-то назад: вот и «отпросился на предыдущую
			# строку» из жалобы.
			_main.cursor_line -= 1
			_main.cursor_pos = _main.display_lines[_main.cursor_line].length() - 1
		else:
			_hero_advance()
			_turn += 1
		if _turn > 400:
			_episodes += 1
			_start_episode()

	# --- Покрытие и близость. ------------------------------------------
	# Показываем, что догон реально подходил вплотную (d упирается в
	# −D), и что сценарии не простаивали.
	_frames_played += 1
	_scenario_frames[_scenario] += 1
	_closest = maxf(_closest, _d())
	_prev_ex = _main.enemy_x

	if _failures.size() > 8 or _frame > 60 * 60 * 12:
		_report()
		return true
	return false


func _report() -> void:
	print("CHASE_TEST: эпизодов=%d кадров=%d сценарии(угол_сзади/догон/откат_угол)=%s"
		% [_episodes, _frames_played, str(_scenario_frames)])
	print("CHASE_TEST: уколов=%d (одна_строка=%d откат_через_угол=%d) табло_угла_проверено=%d ближайшая_d=%.2f (D=%.2f)"
		% [_pricks, _prick_same, _prick_cross, _corner_checked, _closest, _D()])
	print("CHASE_TEST: зазор на кадре укола: проверено=%d средний=%.2f px (0 = шары ровно касаются)"
		% [_contact_checked, 0.0 if _touch_gap_n == 0 else _touch_gap_sum / float(_touch_gap_n)])
	print("CHASE_TEST: откатов Backspace=%d" % _retreats)
	# Покрытие: все три сценарии должны были отработать, иначе тест
	# проходит вхолостую и ничего не проверяет. Порог уколов низкий (5):
	# с медленным ежом органика догонов редкая и гуляет от прогона
	# к прогону (15 против ≤10 на том же коде) — а основная ценность
	# теста всё равно в инвариантах на КАЖДОМ кадре и в десятках
	# угловых табло, а не в счётчике.
	_check(_scenario_frames[0] > 200, "scenario hedge-behind-across-lines exercised")
	_check(_scenario_frames[1] > 200, "scenario plain chase exercised")
	_check(_scenario_frames[2] > 200, "scenario rollback-across-corner exercised")
	_check(_contact_checked > 5, "contact distance checked on prick frames")
	_check(_corner_checked > 10, "corner tableau checked (hare on hedge row, exactly at D)")
	_check(_retreats > 20, "Backspace retreat exercised (not just error erasing)")
	if _failures.is_empty():
		print("CHASE_TEST: PASS")
	else:
		var seen := {}
		for f in _failures:
			# Ключ без номера кадра: иначе тысяча одинаковых нарушений
			# не схлопнется и отчёт засорят.
			var key := f.substr(f.find(":") + 1)
			if not seen.has(key):
				seen[key] = true
				print("CHASE_TEST: FAIL: ", f)
	quit(1 if not _failures.is_empty() else 0)
