extends SceneTree
## Тест производительности (автор 16.10.2026): меню тянуло сохранения с
## диска на КАЖДЫЙ кадр (103 чтения на кадр, ~14 мс на кадр в headless)
## — анимация зайца шла рывками. Проверяем, чтобы это не вернулось
## молча.
##
## ГЛАВНЫЕ ворота — машинонезависимые счётчики, а не миллисекунды: на
## двух ядрах GitHub кадр гуляет втрое, и тест на время там краснел бы
## на ровном месте (ловил 16.10.2026 на CI: 17.4 и 25.3 мс при норме
## 1.9/3.3 на машине автора). За кадром следим так:
##   1) конфиг не читается на кадрах меню;
##   2) объекты не плодятся кадрами (аллокаций StyleBox/словарей);
##   3) КЕШИ РАБОТАЮТ: `Kbd.buttons()` зовётся по чуть-чуть, а не по
##      шестьдесят на кадр; `Kbd.legends()` и `Ui.text_size()` после
##      первого кадра не промахиваются; `Ui.panel_sb()` на кадрах не
##      вызывается вовсе (панели создаются раз за жизнь);
##   4) лучший кадр — в очень грубом потолке (ловушка на порядок
##      величины, не на скорость машины).
##
## Меряем НАСТОЯЩИЕ кадры (меню и игра перерисовывают себя сами), а не
## прямой вызов `_draw`: тот вне NOTIFICATION_DRAW сыплет в лог
## «Drawing is only allowed…» и меряет не то, что видит человек.
##
## Запуск: godot --headless --path game --script res://tests/perf_test.gd

const S := preload("res://scripts/save.gd")
const K := preload("res://scripts/kbd.gd")
const U := preload("res://scripts/ui.gd")
const FRAMES := 120
## Потолок лучшего кадра: на порядок величины. Норма — единицы мс, CI
## после загрузки — десятки; поломка «чтение файла на кадр» на этой
## машине даёт ~25 мс, но её ловят счётчики выше, а не этот порог.
const CEIL_MS := 60.0
## Сколько вызовов кэшированных функций допустимо на 120 кадров.
const CALLS_SLACK := 8

var _failures: Array[String] = []
var _menu: Node = null
var _game: Node = null
var _phase := 0
var _n := 0
var _t0 := 0
var _samples: Array[float] = []
var _snap: Dictionary = {}
var _menu_stats := PackedFloat32Array()
var _game_stats := PackedFloat32Array()


func _check(cond: bool, what: String) -> void:
	if not cond:
		_failures.append(what)


func _initialize() -> void:
	var menu_scene: PackedScene = load("res://scenes/menu.tscn")
	_menu = menu_scene.instantiate()
	root.add_child(_menu)
	_menu.visible = true
	_seed_users(10)
	_menu.view_w = 1000.0
	_menu.view_h = 700.0
	_menu.k = 1.8


## Фазы: 0 — раскладка, 1 — меню, 2 — игра.
func _process(_dt: float) -> bool:
	match _phase:
		0:
			_phase = 1
			_n = 0
			_menu.queue_redraw()
			return false
		1:
			if _n == 0:
				_snap = _counters()
				_t0 = Time.get_ticks_usec()
			elif _n >= 2:
				_samples.append(_ms_since())
			if _n > FRAMES:
				_menu_stats = _stats()
				_check_menu()
				_phase = 2
				_n = 0
				_samples = []
				_start_game()
				_menu.visible = false
				_game.queue_redraw()
				return false
			_n += 1
			_menu.queue_redraw()
			return false
		2:
			if _n == 0:
				_snap = _counters()
				_t0 = Time.get_ticks_usec()
			elif _n >= 2:
				_samples.append(_ms_since())
			if _n > FRAMES:
				_game_stats = _stats()
				_check_game()
				_report()
				return true
			_n += 1
			_game.queue_redraw()
			return false
	return false


func _ms_since() -> float:
	var now := Time.get_ticks_usec()
	var dt := float(now - _t0) / 1000.0
	_t0 = now
	return dt


## Снимок счётчиков перед серией кадров.
func _counters() -> Dictionary:
	return {
		"cfg": S.cfg_loads,
		"objs": Performance.get_monitor(Performance.OBJECT_COUNT),
		"buttons": K.buttons_misses,
		"legends": K.legends_misses,
		"text": U.text_size_misses,
		"panels": U.panel_sb_calls,
	}


func _delta(key: String) -> int:
	var now: int = 0
	match key:
		"cfg":
			now = S.cfg_loads
		"objs":
			now = Performance.get_monitor(Performance.OBJECT_COUNT)
		"buttons":
			now = K.buttons_misses
		"legends":
			now = K.legends_misses
		"text":
			now = U.text_size_misses
		"panels":
			now = U.panel_sb_calls
	return now - int(_snap.get(key, 0))


func _start_game() -> void:
	if _game != null:
		return
	var scene: PackedScene = load("res://scenes/main.tscn")
	_game = scene.instantiate()
	_game.skip_menu = true
	_game.all_keys_override = 1
	root.add_child(_game)
	S.create_user("Тестер")
	_game.profile_name = "Тестер"
	_game._start_game()
	_game.visible = true


## Кадры меню: ни чтений конфига, ни объектов, ни промахов кэша.
func _check_menu() -> void:
	_check(
		_delta("cfg") == 0,
		"%d кадров меню прочитали конфиг %d раз" % [FRAMES, _delta("cfg")]
	)
	var grown: int = _delta("objs")
	_check(grown == 0, "%d кадров меню создали %d объектов" % [FRAMES, grown])
	_check(
		_delta("panels") <= CALLS_SLACK,
		"меню создало %d панелей на %d кадров (панели живут раз за жизнь)"
		% [_delta("panels"), FRAMES]
	)
	_check(
		_delta("buttons") <= CALLS_SLACK,
		"меню собрало доску %d раз на %d кадров (кэш Kbd.buttons не работает)"
		% [_delta("buttons"), FRAMES]
	)
	_check(
		_delta("legends") == 0,
		"меню пересчитало легенды %d раз на %d кадров (кэш не работает)"
		% [_delta("legends"), FRAMES]
	)
	_check(
		_delta("text") <= CALLS_SLACK,
		"меню перемерило строки %d раз на %d кадров (кэш Ui.text_size не работает)"
		% [_delta("text"), FRAMES]
	)
	_check_ceiling("меню", _menu_stats)


## Кадры игры: доска видна всегда, так что те же правила.
func _check_game() -> void:
	_check(
		_delta("cfg") == 0,
		"%d кадров игры прочитали конфиг %d раз" % [FRAMES, _delta("cfg")]
	)
	_check(
		_delta("panels") <= CALLS_SLACK,
		"игра создала %d панелей на %d кадров" % [_delta("panels"), FRAMES]
	)
	_check(
		_delta("buttons") <= CALLS_SLACK,
		"игра собрала доску %d раз на %d кадров" % [_delta("buttons"), FRAMES]
	)
	_check(
		_delta("legends") <= CALLS_SLACK,
		"игра пересчитала легенды %d раз на %d кадров" % [_delta("legends"), FRAMES]
	)
	_check_ceiling("игры", _game_stats)


## Порог времени — только грубая ловушка на порядок величины.
func _check_ceiling(tag: String, st: PackedFloat32Array) -> void:
	if st.is_empty():
		_failures.append("%s: нет ни одного кадра" % tag)
		return
	print(
		"  кадр %s: лучший %.2f мс, медиана %.2f, среднее %.2f (%.0f fps)"
		% [tag, st[0], st[1], st[2], 1000.0 / maxf(st[0], 0.001)]
	)
	_check(
		st[0] < CEIL_MS,
		"кадр %s: лучший %.2f мс — выше потолка %.0f мс" % [tag, st[0], CEIL_MS]
	)


## Лучший, медиана, среднее по отсортированным отсчетам.
func _stats() -> PackedFloat32Array:
	var s := _samples.duplicate()
	s.sort()
	var n := s.size()
	if n == 0:
		return PackedFloat32Array()
	var total := 0.0
	for v in s:
		total += v
	return PackedFloat32Array([s[0], s[n / 2], total / float(n)])


func _seed_users(n: int) -> void:
	for u in S.user_list():
		S.delete_user(u)
	for i in n:
		S.create_user("Игрок%02d" % i)


func _report() -> void:
	if _failures.is_empty():
		print("PERF_TEST: PASS")
	else:
		for f in _failures:
			print("PERF_TEST: FAIL: ", f)
	quit(1 if not _failures.is_empty() else 0)
