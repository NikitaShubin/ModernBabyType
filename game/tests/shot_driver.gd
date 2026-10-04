extends SceneTree
## Визуальный драйвер: дёргает настоящую игру напрямую (без X11-ввода),
## кадры — по wall-clock (на быстрых машинах сотни fps, счёт кадров врёт).
## Снимает в /tmp/opencode/ все кадры анимаций: подставляя `time` и таймеры
## вручную, получаем ровно тот кадр цикла, который нужен.
## Запуск: DISPLAY=:99 godot --path game --script res://tests/shot_driver.gd
## (НЕ headless — нужен реальный рендер).

const FPS := 10.0
## Частота покачивания ежа — из main.gd, иначе фазы в кадрах съезжают.
const HEDGE_WOB_W := 8.0
const START_POS := 6

var _frame := 0
var _main: Node = null
var _jobs: Array = []
var _pending: Array = []
var _done := false


func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	_main = scene.instantiate()
	# Снимаем игровой экран, а не меню игроков; все знаки активны.
	_main.skip_menu = true
	_main.all_keys_override = 1
	root.add_child(_main)


func _setup() -> void:
	# Настройка строго после _ready сцены: _new_level() сбрасывает курсор.
	_main.grace_t = 0.0
	_main.state = "playing"
	_main.cursor_line = 0
	_main.cursor_pos = START_POS
	_main.hedge_active = true
	_main.grace_t = 0.0
	_main.enemy_line = 0
	for i in 3:
		_main._type_char(_main._current())
	# [имя, chomp_t, time, shake, lunge, отступ ежа в k]
	for i in 4:
		_jobs.append(["run%d" % i, 0.0, float(i) / FPS, 0.0, 0.0, 170.0])
	# Шесть шагов цикла еды: 0 — бег, 1-4 — укус и жевание, 5 — бег.
	# Середина каждого шестого дробного шага, чтобы int() не срезал границу.
	for i in 6:
		var f := 1.0 - (float(i) + 0.5) / 6.0
		_jobs.append(["eat%d" % i, _main.CHOMP_T * f, 0.0, 0.0, 0.0, 170.0])
	# Две фазы качения ежа: касание (0) и верх прыжка (четверть периода).
	for i in 2:
		var ph := 0.0 if i == 0 else PI * 0.5 / HEDGE_WOB_W
		_jobs.append(["hedge%d" % i, 0.0, ph, 0.0, 0.0, 170.0])
	_jobs.append(["fear", 0.0, 0.0, _main.SHAKE_T * 0.5, 0.0, 110.0])
	_jobs.append(["lunge", 0.0, 0.0, 0.0, _main.LUNGE_T * 0.85, 60.0])
	# Укол: то же сближение, но state lost — у зайца шок на лице.
	_jobs.append(["shock", 0.0, 0.0, 0.0, _main.LUNGE_T * 0.85, 60.0])


func _process(_dt: float) -> bool:
	_frame += 1
	if _frame < 3:
		return false
	if _frame == 3:
		_setup()
		return false
	if not _pending.is_empty():
		# Снимаем то, что отрисовалось в предыдущем кадре.
		_render(_pending.pop_front())
		if _jobs.is_empty():
			_done = true
			return false
	if _done:
		quit(0)
		return true
	if _jobs.is_empty():
		quit(0)
		return true
	var job: Array = _jobs.pop_front()
	# Каждый кадр ставим своё состояние: логика успевает сдвинуть курсор.
	_main.grace_t = 0.0
	_main.state = "lost" if job[0] == "shock" else "playing"
	_main.cursor_line = 0
	_main.cursor_pos = START_POS + 3
	_main.hedge_active = true
	_main.enemy_line = 0
	_main.time = job[2]
	# Прыжки зайца в кадрах: фаза от времени job'а, чтобы run-кадры
	# различались высотой прыжка (в игре фаза идёт от пути).
	_main.hop_ph = job[2] * 8.0
	_main.chomp_t = job[1]
	_main.shake_t = job[3]
	_main.lunge_t = job[4]
	_main.enemy_x = _main._cursor_cx() - job[5] * _main.k
	_main.puffs.clear()
	_main.hero_r = _main._hero_pos()
	# Снапшот текстуры — это предыдущий кадр, поэтому имя кадра
	# запоминаем и снимаем на следующем проходе, когда переменные
	# уже отрисованы. Иначе каждый кадр отстаёт на один job
	# (для шока это критично: state lost виден только так).
	_pending.append(job[0])
	return false


func _render(shot_name: String) -> void:
	var img := root.get_texture().get_image()
	img.save_png("/tmp/opencode/" + shot_name + ".png")
	print("SHOT saved: ", shot_name)
