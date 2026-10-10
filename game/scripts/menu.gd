extends Node2D
## Меню игроков: список профилей, поле ввода имени, гостевой режим.
##
## Управление:
##   ↑ / ↓      прокрутка списка, с перехватом через конец
##   Enter      в поле ввода — создать профиль (или войти, если имя есть),
##              без поля — войти выбранным
##   Tab        показать / спрятать поле ввода
##   A          все клавиши у выбранного профиля (взрослый режим:
##              активны все знаки сразу). Работает только при неактивном
##              поле ввода, поэтому не мешает набору имени
##   Delete     удалить выбранный профиль
##   Backspace  стереть символ в поле ввода
##   Esc        гость — играть без профиля, прогресс не сохраняется
##   Системная клавиатура Android шлёт события без keycode: Enter ловим
##   ещё и по unicode 10/13, Backspace — по unicode 8 (игру см. в main.gd).
##
## Сигналы: chosen(name) — пустое имя означает гостя.

const S := preload("res://scripts/save.gd")

signal chosen(user_name: String)

const BASE_W := 1100.0
const BASE_H := 650.0
const ROW_H := 62.0
const FONT_TITLE := 40
const FONT_ROW := 30
const FONT_SMALL := 20
const PAPER := Color("#f7f3e8")
const INK := Color("#1c1a16")
const UI_TEXT := Color("#4a4438")
const DIM := Color("#8d8778")
const HERO_TEX: Texture2D = preload("res://assets/hero.png")

var users: Array[String] = []
var sel := 0
var input_active := false
var input_text := ""
## Флаг «все клавиши» для имени, которое прямо сейчас вводится (списка
## ещё нет — применять не к кому). При создании профиля переносится
## в него, затем сбрасывается.
var input_all_keys := false
## То же для строгой ё (колонка «Ё»): ждёт создания профиля.
var input_yo_strict := true
## Самообновление с GitHub: только по кнопке (никакой фоновой магии).
## Состояния: "" покой, "checking" проверка, "latest" всё свежее,
## "error" ошибка с текстом, "downloading" качаем. Модалка «Вышла X?»
## — флагом _upd_open (только Да/Нет, как подтверждение удаления).
var _upd: Updater = null
var _upd_state := ""
var _upd_msg := ""
## Прогресс закачки: процент (-1 — размер неизвестен) и сколько байт.
var _upd_pct := -1
var _upd_done := 0
var _upd_total := 0
var _upd_poll := 0.0
const UPD_POLL := 0.2
var _upd_tag := ""
var _upd_url := ""
var _upd_notes: Array[String] = []
var _upd_open := false
## Выбранная колонка флагов: 0 — «Про», 1 — «Ё». Стрелки ←/→ двигают,
## пробел переключает. Видна подсветкой заголовка.
var sel_col := 0
## Подсказка по заголовку колонки («pro»/«yo»): тап по заголовку
## объясняет, что за галка. Пусто — молчим.
var hint_header := ""
## Игрок, ради которого меню открыли: F2 возвращает в игру с ним.
var resume_user := ""
## Удаление на подтверждении: имя профиля, ждущего «Да». Пусто — модалки
## нет, меню живёт как обычно. Пока висит — весь остальной ввод глушим.
var confirm_name := ""
var view_w := BASE_W
var view_h := BASE_H
var k := 1.0
## Своя клавиатура (модуль Kbd): видна, когда вводится имя, на сенсорных
## устройствах. Высоту считаем сами от view_h — игра свою высоту больше
## не ставит (у неё своя политика показа). Слой держит kb_layer.
## Отступ от верха под вырез камеры (как в игре, см. Ui.top_inset).
var top_safe := 0.0
var kb_layer := "ru"
var kb_lang := "ru"
var kb_shift := false
## Высота системной клавиатуры (ставит игра своим замером, только при
## её галке). Своя высота считается отдельно (_own_h).
var _lp_act := ""
var _lp_t0 := 0
var kb_key_sb: StyleBoxFlat
## Ручной режим ночи из настроек: 0 день, 1 ночь, -1 авто (система).
## Кнопка крутит по кругу день → ночь → авто.
var nmode := -1
var mono: Font
## Оформление (только картинка): скруглённые чипсы под строками,
## рамка поля ввода и пилюля подсказки. Строки и тексты не меняются —
## их проверяют тесты, поэтому здесь лишь рамки вокруг тех же слов.
var row_sb: StyleBoxFlat
var row_idle_sb: StyleBoxFlat
var box_sb: StyleBoxFlat
## Своя клавиатура (модуль Kbd): клавиши прямо дают символы в поле
## ввода, без IME.
func _draw_own_kb() -> void:
	if not _own_shown():
		return
	Kbd.draw(
		self, _own_rect(), kb_layer, kb_lang, kb_shift, true, mono,
		int(30.0 * k), kb_key_sb, selbox_sb, _uitext()
	)


func _own_press(pos: Vector2) -> bool:
	if not _own_shown() or not input_active:
		return false
	var act := Kbd.hit(_own_rect(), kb_layer, kb_lang, kb_shift, true, pos)
	if act == "":
		return false
	_lp_act = ""

	if act == "стереть":
		input_text = input_text.left(maxi(0, input_text.length() - 1))
	elif act == "слой":
		# Из знаков — назад на свой язык, иначе — в знаки.
		kb_layer = kb_lang if kb_layer == "sym" else "sym"
	elif act == "язык":
		kb_lang = "en" if kb_lang == "ru" else "ru"
		kb_layer = kb_lang
	elif act == "шифт":
		kb_shift = not kb_shift
	elif act == "ввод":
		_enter()
	elif act == "пробел":
		pass  # в имени пробелов не бывает
	elif Kbd.long_alt(act) != "":
		kb_shift = false
		if input_text.length() < S.MAX_NAME_LENGTH:
			input_text += act
		_lp_act = act
		_lp_t0 = Time.get_ticks_msec()
	else:
		kb_shift = false
		if input_text.length() < S.MAX_NAME_LENGTH:
			input_text += act
	queue_redraw()
	get_viewport().set_input_as_handled()
	return true


## Отпускание после долгого нажатия на е/ь: введённую букву меняем на ё/ъ.
func _own_release(pos: Vector2) -> bool:
	if _lp_act == "" or not input_active:
		_lp_act = ""
		return false
	var done := false
	if Time.get_ticks_msec() - _lp_t0 >= 500:
		var act := Kbd.hit(_own_rect(), kb_layer, kb_lang, false, true, pos)
		if act == _lp_act and input_text.ends_with(_lp_act):
			input_text = input_text.left(input_text.length() - 1) + Kbd.long_alt(_lp_act)

			done = true
	_lp_act = ""
	if done:
		queue_redraw()
		get_viewport().set_input_as_handled()
	return done


## Бокс выбранной стрелками галки: залит цветом вместо рамки.
var selbox_sb: StyleBoxFlat
var hint_sb: StyleBoxFlat
## Ночь (S.resolve_night: ручной выбор или система). Краски берутся
## из хелперов _ink/_uitext/_dim, панели мутируют в _apply_night.
var night := false
var _meadow: Meadow = null


func _ready() -> void:
	mono = load("res://fonts/DejaVuSansMono.ttf")
	if mono == null:
		var fallback := SystemFont.new()
		fallback.font_names = PackedStringArray(["monospace"])
		mono = fallback
	row_sb = Ui.panel_sb(Color("#f0d98a"), 12.0)
	row_idle_sb = Ui.panel_sb(Color(1, 1, 1, 0.45), 12.0)
	box_sb = Ui.panel_sb(Color("#ffffff"), 10.0, INK, 2.0, false)
	kb_key_sb = Ui.panel_sb(Color("#ffffff"), 10.0, INK, 2.0, false)
	selbox_sb = Ui.panel_sb(Color("#a9c6ec"), 10.0, INK, 2.0, false)
	hint_sb = Ui.panel_sb(Color(1, 1, 1, 0.72), 14.0, Color("#e0d5bd"), 1.5, false)
	_meadow = Meadow.new()
	add_child(_meadow)
	nmode = S.get_night_mode()
	_apply_night()
	get_tree().root.size_changed.connect(_relayout)
	_relayout()
	_reload()


func _relayout() -> void:
	var s := get_viewport_rect().size
	if s.x <= 0.0 or s.y <= 0.0:
		return
	view_w = s.x
	view_h = s.y
	top_safe = Ui.top_inset(view_h)
	# Масштаб — от эффективной высоты (минус клавиатура), как в игре:
	# иначе в альбомной с клавиатурой блок меню не влезает над ней.
	# Пол на телефоне выше (0.7 против 0.5): пальцем по мелкому не попасть,
	# а читаться должно без лупы (жалоба автора 10.2026). Влезаемость
	# блока при поднятом поле проверяет profiles_test.
	# На сенсорных умножаем на плотность экрана: меню считает в физических
	# пикселях, а на телефоне они в 2–3 раза мельче — иначе весь интерфейс
	# в портрете мелкий (жалоба автора 10.2026). Десктоп не меняется.
	var kmin := 0.5 if Ui.is_desktop() else 0.7
	var want := minf(view_w / BASE_W, _menu_eff_h() / BASE_H) * Ui.dpr()
	k = _fit_k(clampf(want, kmin, 2.5), kmin)
	queue_redraw()


## Ужать k, чтобы блок влез в эффективную высоту: с поднятой плотностью
## контент растёт, а экран — нет. Две итерации: шаг строк с полом 64px
## нелинеен, одной формулой не взять. Ниже kmin не уходим.
func _fit_k(k0: float, kmin: float) -> float:
	var kk := k0
	for _i in 2:
		var step := ROW_H * kk
		if not Ui.is_desktop():
			step = maxf(step, 64.0)
		var top := 160.0 * kk + top_safe
		var need := top + float(maxi(users.size(), 1)) * step + 340.0 * kk
		if need <= _menu_eff_h() or kk <= kmin:
			break
		kk = maxf(kmin, kk * _menu_eff_h() / need)
	return kk


## Открыть меню поверх игры. Видимость и процесс — только здесь:
## скрытое меню глухо и слепо архитектурно (process выключен),
## а не только проверками visible.
func open(resume: String) -> void:
	resume_user = resume
	visible = true
	process_mode = Node.PROCESS_MODE_INHERIT
	_apply_night()
	_reload()
	queue_redraw()


## Закрыть меню: скрыть и заглушить процесс до следующего open().
func close() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_DISABLED
	queue_redraw()


## Перечитать список с диска и встать на разумную позицию.
func _reload() -> void:
	users = S.user_list()
	if sel >= users.size():
		sel = maxi(0, users.size() - 1)
	# Режим ночи — из настроек (кнопка могла его сменить, файл — тоже).
	nmode = S.get_night_mode()
	# Модалка список не переживает: ушли из меню через F2 посреди
	# подтверждения — при следующем открытии чистый список, а не
	# вчерашний вопрос.
	confirm_name = ""
	# Пустой список — это первый запуск: курсор сразу в поле имени.
	# Иначе буквы уходят в никуда, и кажется, что игра не реагирует.
	# Набирать имя при пустом списке больше нечем, так что неактивное
	# поле здесь — просто ловушка.
	if users.is_empty():
		input_active = true
		input_text = ""
	queue_redraw()


func _unhandled_key_input(event: InputEvent) -> void:
	var ke := event as InputEventKey
	if ke == null:
		return
	if not ke.pressed or ke.echo:
		return
	# Скрытое меню клавиш не видит: иначе оно перехватывает ввод раньше
	# игры (оно добавлено позже и получает _unhandled_key_input первым).
	# Без этого F2 во время игры не открывал меню, а молча перезапускал
	# гостя, буква Ф на русской раскладке (тот же keycode, что и A)
	# переключала «все клавиши», а Tab уводил буквы в невидимое поле.
	if not visible:
		return
	# Модалка подтверждения — только свои клавиши, остальное мимо:
	# Enter/Д — «Да», Esc/N — «Нет». Д — та же физическая клавиша,
	# что L (раскладка не важна, смотрим keycode), N — KEY_N.
	if confirm_name != "":
		if (
			ke.keycode == KEY_ENTER or ke.keycode == KEY_KP_ENTER
			or ke.unicode == 10 or ke.unicode == 13
			or ke.keycode == KEY_L
		):
			_confirm_delete()
		elif ke.keycode == KEY_ESCAPE or ke.keycode == KEY_N:
			_cancel_confirm()
		_eaten()
		return
	# Модалка обновления: Enter — «Скачать», Esc или N — «Не сейчас».
	# Раньше с клавиатуры был только Enter, а всё остальное съедалось:
	# на экране кнопка «Не сейчас» есть, с клавиш до неё не дойти, и
	# Esc уходил из ИГРЫ (жалоба автора: на десктопе и на эмуляторе с
	# внешней клавиатурой отказ от обновления был недостижим).
	if _upd_open:
		if (
			ke.keycode == KEY_ENTER or ke.keycode == KEY_KP_ENTER
			or ke.unicode == 10 or ke.unicode == 13
		):
			_upd_yes()
		elif ke.keycode == KEY_ESCAPE or ke.keycode == KEY_N:
			_upd_no()
		_eaten()
		return
	# F2 — вернуться в игру тем же игроком, кого открыли меню.
	if ke.keycode == KEY_F2:
		chosen.emit(resume_user)
		_eaten()
		return
	if ke.keycode == KEY_UP:
		_nav(-1)
		_eaten()
		return
	if ke.keycode == KEY_DOWN:
		_nav(1)
		_eaten()
		return
	# Стрелки ←/→ — выбор колонки флагов (Про/Ё), пробел — переключить
	# флаг у выбранной строки. В поле ввода пробел молчит (имени
	# с пробелами не бывает), модалку стрелки не трогают (она выше).
	if ke.keycode == KEY_LEFT:
		sel_col = (sel_col + 1) % 2
		queue_redraw()
		_eaten()
		return
	if ke.keycode == KEY_RIGHT:
		sel_col = (sel_col + 1) % 2
		queue_redraw()
		_eaten()
		return
	if ke.keycode == KEY_SPACE:
		_toggle_flag()
		_eaten()
		return
	if ke.keycode == KEY_ENTER or ke.keycode == KEY_KP_ENTER or ke.unicode == 10 or ke.unicode == 13:
		_enter()
		_eaten()
		return
	if ke.keycode == KEY_TAB:
		_toggle_input()
		_eaten()
		return
	if ke.keycode == KEY_DELETE:
		_delete()
		_eaten()
		return
	if ke.keycode == KEY_ESCAPE:
		# Esc в меню — выход из игры, а не гость. Гость — только
		# кнопкой «Без профиля» (тап или Enter по пустому списку).
		get_tree().quit()
		_eaten()
		return
	# Стирание — одно простое: урезать имя на символ. Серий IME
	# (DEL + перепись региона) больше нет: ввод — только своей
	# клавиатурой (решение 10.2026).
	if ke.keycode == KEY_BACKSPACE or ke.unicode == 8:
		if not input_active:
			return
		input_text = input_text.left(maxi(0, input_text.length() - 1))
		queue_redraw()
		_eaten()
		return
	# Взрослый режим — только когда поле ввода неактивно, иначе это буква.
	if not input_active and _letter(ke) == "a":
		_toggle_all_keys()
		_eaten()
		return
	if not input_active or ke.unicode == 0:
		return
	var ch := String.chr(ke.unicode)
	# Пропускаем управляющие символы (меньше пробела) и пробелы: в имени
	# их быть не должно, а имя всё равно обрежется по краям.
	if ke.unicode < 32 or ch == " " or input_text.length() >= S.MAX_NAME_LENGTH:
		return
	input_text += ch

	queue_redraw()
	_eaten()
func _process(_dt: float) -> void:
	_poll_update()


## Клавиша обслужена меню: игре её не отдавать, иначе Backspace
## в поле имени заодно откатывал бы зайца, а A-переключатель —
## печатался. Остальное (F3, F11) меню не трогает — их разбирает игра.
func _eaten() -> void:
	get_viewport().set_input_as_handled()


## Тач и мышь: строки, поле, кнопки. Скрытое меню тычков не видит —
## тот же урок, что с клавишами.
func _input(event: InputEvent) -> void:
	if not visible:
		return
	# Координаты тычка могут быть и отрицательными (узкое окно, край
	# экрана), поэтому признак «тычка не было» — отдельный флаг,
	# а не сентинел в координатах. Слушаем только мышь: палец на
	# Android сам превращается в клик, а двойная обработка касания
	# и клика давала бы двойные срабатывания (галочка вкл-выкл
	# за один палец). На десктопе касаний нет — ничего не меняется.
	var has_pos := false
	var pos := Vector2.ZERO
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			pos = mb.position
			has_pos = true
		elif mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			# Отпускание после долгого нажатия (е→ё, ь→ъ).
			_own_release(mb.position)
			return
	if not has_pos:
		return


	# Модалка — только свои две кнопки, остальное мимо.
	if confirm_name != "":
		if _confirm_yes_rect().has_point(pos):
			_confirm_delete()
			get_viewport().set_input_as_handled()
		elif _confirm_no_rect().has_point(pos):
			_cancel_confirm()
			get_viewport().set_input_as_handled()
		return
	# Модалка обновления — только свои две кнопки (удаление первее).
	if _upd_open:
		if _upd_yes_rect().has_point(pos):
			_upd_yes()
			get_viewport().set_input_as_handled()
		elif _upd_no_rect().has_point(pos):
			_upd_no()
			get_viewport().set_input_as_handled()
		return
	# Прямоугольники — из тех же хелперов, что рисует _draw: единый
	# источник геометрии, работает и без отрисовки (тесты headless).
	# Внутри строки сначала точечные цели (галочка, крестик), потом
	# сама строка: иначе тап по галочке играл бы этим профилем.
	for i in users.size():
		if _pro_tap_rect(i).has_point(pos):
			_toggle_pro(i)
			get_viewport().set_input_as_handled()
			return
		if _yo_tap_rect(i).has_point(pos):
			_toggle_yo(i)
			get_viewport().set_input_as_handled()
			return
		if _del_tap_rect(i).has_point(pos):
			confirm_name = users[i]
			queue_redraw()
			get_viewport().set_input_as_handled()
			return
	for i in users.size():
		if _row_tap_rect(i).has_point(pos):
			chosen.emit(users[i])
			get_viewport().set_input_as_handled()
			return
	# Заголовки «Про»/«Ё» — подсказка, что за галка. Повторный тап гасит.
	if not users.is_empty() and _pro_head_rect().has_point(pos):
		hint_header = "" if hint_header == "pro" else "pro"
		queue_redraw()
		get_viewport().set_input_as_handled()
		return
	if not users.is_empty() and _yo_head_rect().has_point(pos):
		hint_header = "" if hint_header == "yo" else "yo"
		queue_redraw()
		get_viewport().set_input_as_handled()
		return
	# Кнопка обновлений: проверить релизы на GitHub.
	if _upd_button_rect().has_point(pos):
		_upd_check()
		get_viewport().set_input_as_handled()
		return
	if users.is_empty() and _check_tap_rect().has_point(pos):
		_toggle_all_keys()
		get_viewport().set_input_as_handled()
		return
	if users.is_empty() and _yocheck_tap_rect().has_point(pos):
		input_yo_strict = not input_yo_strict
		queue_redraw()
		get_viewport().set_input_as_handled()
		return
	if _field_tap_rect().has_point(pos):
		if not input_active:
			_toggle_input()
		get_viewport().set_input_as_handled()
		return
	# Своя клавиатура: клавиши раньше остального (тап по клавише — ввод).
	if _own_press(pos):
		return
	if _play_tap_rect().has_point(pos):
		_enter()
		get_viewport().set_input_as_handled()
		return
	if _guest_tap_rect().has_point(pos):
		_guest()
		get_viewport().set_input_as_handled()
		return
	if _night_tap_rect().has_point(pos):
		_toggle_night()
		get_viewport().set_input_as_handled()
		return



## Десктоп — там, где нет системной клавиатуры: поле ввода работает
## с физической. Буква по коду клавиши: «A» без физической раскладки (в латинице на
## русской раскладке KeyA тоже проходит). Ручная раскладка не важна:
## клавиша одна и та же.
func _letter(ke: InputEventKey) -> String:
	if ke.keycode == KEY_A:
		return "a"
	return ""


func _nav(direction: int) -> void:
	if users.is_empty():
		return
	sel = (sel + direction + users.size()) % users.size()
	queue_redraw()


func _toggle_input() -> void:
	input_active = not input_active
	if not input_active:
		input_text = ""
	_relayout()
	queue_redraw()


func _enter() -> void:
	if input_active and not input_text.strip_edges().is_empty():
		var name := S.clean_name(input_text)
		# Новое имя — создать, существующее — просто войти. Флаги
		# вводимого имени переезжают в созданный профиль.
		if not S.user_exists(name):
			S.create_user(name)
			S.set_all_keys(name, input_all_keys)
			S.set_yo_strict(name, input_yo_strict)
		else:
			S.touch(name)
		input_text = ""
		input_active = false
		input_all_keys = false
		input_yo_strict = true
		chosen.emit(name)
		return
	if not users.is_empty():
		chosen.emit(users[sel])
		return
	# Список пуст и ввод выключен — единственный выход, гость.
	_guest()


func _delete() -> void:
	if input_active or users.is_empty():
		return
	# Удаление непоправимо — только через подтверждение.
	confirm_name = users[sel]
	queue_redraw()


## Подтверждено: снести и вернуться в список.
func _confirm_delete() -> void:
	if confirm_name != "":
		S.delete_user(confirm_name)
	confirm_name = ""
	_reload()


## Отмена: профиль цел, модалка гаснет.
func _cancel_confirm() -> void:
	confirm_name = ""
	queue_redraw()


## Ленивый узел проверки обновлений + сигналы в состояние меню.
func _upd_ensure() -> void:
	if _upd != null:
		return
	_upd = Updater.new()
	add_child(_upd)
	_upd.checked.connect(_on_upd_checked)
	_upd.failed.connect(_on_upd_failed)
	_upd.downloaded.connect(_on_upd_downloaded)
	_upd.progress.connect(_on_upd_progress)


## Кнопка «Обновления»: спросить GitHub.
func _upd_check() -> void:
	_upd_ensure()
	_upd_state = "checking"
	_upd_msg = "Проверяю…"
	_upd_open = false
	queue_redraw()
	_upd.check()


func _on_upd_checked(has: bool, tag: String, notes: String, _url: String) -> void:
	if has:
		_upd_tag = tag
		_upd_notes.clear()
		for ln in notes.split("\n"):
			_upd_notes.append(ln)
		_upd_state = ""
		_upd_msg = ""
		_upd_open = true
	else:
		_upd_state = "latest"
		_upd_msg = "У вас последняя (%s)" % tag
		_upd_open = false
	queue_redraw()


func _on_upd_failed(what: String) -> void:
	_upd_state = "error"
	_upd_msg = what
	_upd_open = false
	queue_redraw()


## «Скачать»: качаем, дальше — дело платформы (см. update.gd).
func _upd_yes() -> void:
	# Повторное нажатие во время закачки: второй запрос сбивал первый
	# (жалоба автора 10.2026 — «сбоит, если нажать в процессе закачки»).
	# Пока качаем — просто не начинаем заново.
	if _upd.downloading():
		_upd_open = false
		_upd_state = "downloading"
		_upd_msg = "Уже качаю…"
		queue_redraw()
		return
	_upd_open = false
	_upd_state = "downloading"
	_upd_pct = -1
	_upd_done = 0
	_upd_total = 0
	_upd_msg = "Качаю…"
	queue_redraw()
	_upd.download()


## «Позже»: модалка гаснет, проверка сброшена. Если закачка УЖЕ идёт —
## её отменяем: иначе файл докачается, и через полминуты системный
## установщик вылезет поверх игры, хотя человек от обновления отказался
## (проба 10.2026).
func _upd_no() -> void:
	_upd.cancel()
	_upd_open = false
	_upd_state = ""
	_upd_msg = ""
	queue_redraw()


## Прогресс закачки: процент и «скачано из». Видно, что дело идёт
## (жалоба автора 10.2026: «было бы здорово видеть прогресс»).
func _on_upd_progress(done: int, total: int, percent: int) -> void:
	_upd_done = done
	_upd_total = total
	_upd_pct = percent
	if _upd_state == "downloading":
		if percent >= 0:
			_upd_msg = "Качаю… %d%%" % percent
		elif total > 0:
			_upd_msg = "Качаю… %d из %d МБ" % [done / 1048576, total / 1048576]
		else:
			_upd_msg = "Качаю… %d МБ" % (done / 1048576)
	queue_redraw()


## Опрос прогресса, пока идёт закачка: HTTPRequest сам событий
## прогресса не шлёт.
func _poll_update() -> void:
	if _upd_state != "downloading" or not _upd.downloading():
		return
	_upd_poll += get_process_delta_time()
	if _upd_poll < UPD_POLL:
		return
	_upd_poll = 0.0
	var total := _upd.total_bytes()
	var done := _upd.done_bytes()
	var pct := -1
	if total > 0:
		pct = clampi(int(float(done) * 100.0 / float(total)), 0, 100)
	_on_upd_progress(done, total, pct)


func _on_upd_downloaded(path: String) -> void:
	if path == "":
		# Android: файл качает браузер в Загрузки — сам он не установится
		# (системе запрещено ставить APK молча). Говорим, что делать:
		# иначе игрок ждёт, а установка «не запускается» (жалоба 10.2026).
		_upd_state = ""
		_upd_msg = "Файл в Загрузках: откройте его и нажмите «Установить»"
		_upd_open = false
		queue_redraw()
		return
	# Платформа забрала файл (установщик / перезапуск): меню молчит.
	_upd_state = ""
	_upd_msg = ""
	_upd_open = false
	queue_redraw()


## Переключить клавиатуру: системная вместо своей (и назад).
## Своя высота пересчитается релэутом (клавиатура показалась/скрылась).
func _toggle_all_keys() -> void:
	if users.is_empty():
		# Пустой список (первый запуск): переключаем флаг для вводимого
		# имени — при создании он переедет в профиль (см. _enter).
		input_all_keys = not input_all_keys
		queue_redraw()
		return
	var name := users[sel]
	S.set_all_keys(name, not S.get_all_keys(name))
	_reload()


## Про-режим строке: все клавиши сразу именно этому игроку.
func _toggle_pro(i: int) -> void:
	if i < 0 or i >= users.size():
		return
	var name := users[i]
	S.set_all_keys(name, not S.get_all_keys(name))
	_reload()


## Строгая ё строке: различать ё и е именно этому игроку.
func _toggle_yo(i: int) -> void:
	if i < 0 or i >= users.size():
		return
	var name := users[i]
	S.set_yo_strict(name, not S.get_yo_strict(name))
	_reload()


## Пробел по флагам: выбранная стрелками колонка (sel_col) у выбранной
## строки — или у вводимого имени, если список пуст.
func _toggle_flag() -> void:
	if input_active or confirm_name != "":
		return
	if users.is_empty():
		if sel_col == 0:
			input_all_keys = not input_all_keys
		else:
			input_yo_strict = not input_yo_strict
		queue_redraw()
		return
	if sel_col == 0:
		_toggle_pro(sel)
	else:
		_toggle_yo(sel)


func _guest() -> void:
	S.set_last_user(S.GUEST)
	chosen.emit(S.GUEST)


## Ячейки строки таблицы: уровень и счёт «побед из игр». Шапка
## объясняет колонки, поэтому в ячейках только цифры.
func _cell_texts(name: String) -> Array[String]:
	var p := S.load_profile(name)
	var res: Array[String] = [
		"ур.%d" % int(p.get("difficulty", 0)),
		"%d/%d" % [int(p.get("total_wins", 0)), int(p.get("total_games", 0))],
	]
	return res


## Колонки таблицы [имя, уровень, счёт, Про, Ё, ✕]: левые края
## и правый край. Имя занимает остаток (длинные режем с многоточием),
## остальные — по самой широкой ячейке. Та же геометрия у отрисовки,
## хит-теста и тестов: мимо не бьёт.
func _table_cols() -> Array[float]:
	var left := 48.0 * k
	var right := view_w - 48.0 * k
	var gap := 12.0 * k
	# Колонки-галочки: не уже пальцевых 64, иначе их не нажать,
	# и визуально галочка сливается с заголовком.
	var col_min := 44.0 * k if Ui.is_desktop() else 64.0
	var del_w := maxf(44.0 * k, col_min)
	var pro_w := maxf(_text_size("Про", FONT_SMALL).x + 44.0 * k, col_min)
	var yo_w := maxf(_text_size("Ё", FONT_SMALL).x + 44.0 * k, col_min)
	var lvl_w := _text_size("Ур", FONT_SMALL).x + 16.0 * k
	var rec_w := _text_size("Победы", FONT_SMALL).x + 16.0 * k
	for u in users:
		var cells := _cell_texts(u)
		lvl_w = maxf(lvl_w, _text_size(cells[0], FONT_ROW).x + 16.0 * k)
		rec_w = maxf(rec_w, _text_size(cells[1], FONT_ROW).x + 16.0 * k)
	# Ширина имени: всё лишнее забирает себе (имя главное в таблице).
	# Если при полных колонках-галочках места не хватает (узкий экран,
	# мелкий k) — сжимаем их, но имя ниже минимума не отдаём: иначе
	# таблица разъезжается, крестик уезжает за край, а любое имя
	# режется в многоточие (проверено тестами на k=0.5 и 412px).
	var avail := right - left
	var min_name := 80.0 * k
	var flag_want := lvl_w + rec_w + pro_w + yo_w + del_w + gap * 5.0
	var name_w := maxf(min_name, avail - flag_want)
	if name_w + flag_want > avail:
		# Совсем тесно (тест жмёт view_w до 64): резервируем имени часть
		# ширины и жмём остальное, иначе колонки уезжают за правый край
		# и их ширина становится отрицательной.
		var name_reserve := minf(min_name, avail * 0.4)
		var squeeze := clampf((avail - name_reserve) / flag_want, 0.0, 1.0)
		pro_w *= squeeze
		yo_w *= squeeze
		del_w *= squeeze
		lvl_w *= squeeze
		rec_w *= squeeze
		gap *= squeeze
		name_w = maxf(0.0, avail - (lvl_w + rec_w + pro_w + yo_w + del_w + gap * 5.0))
	var name_x := left
	var lvl_x := left + name_w + gap
	var rec_x := lvl_x + lvl_w + gap
	var pro_x := rec_x + rec_w + gap
	var yo_x := pro_x + pro_w + gap
	var del_x := yo_x + yo_w + gap
	var cols: Array[float] = [name_x, lvl_x, rec_x, pro_x, yo_x, del_x, right]
	return cols


## Имя в ширину колонки: длинное режем с многоточием, иначе таблица
## разъезжается (имена до 15 знаков).
func _short_name(name: String) -> String:
	var cols := _table_cols()
	return _clip(name, FONT_ROW, cols[1] - cols[0] - 8.0 * k)


## Обрезать строку по ширине, с многоточием. Нужна для чужих строк
## (длинная ссылка из changelog иначе вылезает за карточку) и для
## имени профиля.
func _clip(txt: String, size_px: int, cap: float) -> String:
	if _text_size(txt, size_px).x <= cap:
		return txt
	var out := txt
	while out.length() > 1 and _text_size(out + "…", size_px).x > cap:
		out = out.left(out.length() - 1)
	return out + "…"


func _text_size(txt: String, size_px: int) -> Vector2:
	# Тот же кегль, что в _text: иначе рамки вокруг строк (чипсы,
	# пилюля подсказки) меряются в одном масштабе, а рисуются в другом.
	return mono.get_string_size(
		txt, HORIZONTAL_ALIGNMENT_LEFT, -1.0, int(float(size_px) * k)
	)


func _text(txt: String, pos: Vector2, size_px: int, col: Color) -> void:
	var fs := int(float(size_px) * k)
	draw_string(
		mono, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs, col
	)


## Строка поля ввода как текст (рамка и хит-тест строятся от неё).
func _field_text() -> String:
	var field := "Имя: " + input_text + ("|" if input_active else "")
	return ("> " if input_active else "  ") + field


## Базовая строка меню: заголовок + строки. Дальше всё считается от неё.
## В портрете блок опускаем, чтобы не кучковался сверху (низ пустой);
## альбом не трогаем. Тапы идут через те же хелперы — мимо не бьют.
## Центрирование — от эффективной высоты (минус клавиатура): иначе
## на телефоне с выездом клавиатуры блок остаётся под ней.
func _menu_eff_h() -> float:
	return Ui.eff_h(view_h, _own_h())


## Своя клавиатура в меню: видна, когда вводится имя, на сенсорных
## устройствах. Высоту для раскладки считаем от неё же.
func _own_shown() -> bool:
	if not visible:
		return false
	if not input_active:
		return false
	return not Ui.is_desktop()


## Область своей клавиатуры: низ экрана.
func _own_rect() -> Rect2:
	var h := Kbd.height_for(view_w)
	# Низ экрана со скруглениями и жестом: клавиатуру поднимаем на
	# безопасный отступ, иначе угловые клавиши обрезаны (жалоба 10.2026).
	var m := 16.0 + Ui.bottom_inset(view_h)
	return Rect2(16.0, view_h - h - m, view_w - 32.0, h)


func _own_h() -> float:
	if not _own_shown():
		return 0.0
	return _own_rect().size.y


func _rows_top() -> float:
	# Весь блок едет вниз под вырез камеры (top_safe): строки, поле
	# и кнопки — вместе, иначе шапка уедет, а поле останется под камерой.
	var y := 90.0 * k + 70.0 * k + top_safe
	if view_h > view_w:
		var eff := _menu_eff_h()
		var need := 170.0 * k + float(maxi(users.size(), 1)) * _row_step() + 220.0 * k
		y += maxf(0.0, (eff - need) * 0.22)
	return y


## Строка поля ввода: после заголовка, строк и отступа. Отдельной
## галочки между строками и полем больше нет: «Про» живёт в колонке
## таблицы, на пустом списке — компактной галочкой под полем.
func _field_line_y() -> float:
	return (
		_rows_top()
		+ float(maxi(users.size(), 1)) * _row_step()
		+ 34.0 * k
	)


## Строка галочки «Про» для вводимого имени (только пустой список):
## под полем ввода.
func _check_line_y() -> float:
	return _field_line_y() + 56.0 * k


## Галочка «Про» для вводимого имени: тот же флаг, что у профилей,
## но до создания — переедет в профиль (см. _enter).
func _check_tap_rect() -> Rect2:
	var y := _check_line_y()
	var w := _text_size("Про", FONT_ROW).x
	return Rect2(48.0 * k, y - _tap_h(48.0 * k) * 0.5, w + 84.0 * k, _tap_h(48.0 * k))


## Компактная галка «Ё» на пустом списке: та же строка, правее.
func _yocheck_tap_rect() -> Rect2:
	var y := _check_line_y()
	var w := _text_size("Ё", FONT_ROW).x
	return Rect2(198.0 * k, y - _tap_h(48.0 * k) * 0.5, w + 84.0 * k, _tap_h(48.0 * k))


## Строка кнопок: под полем ввода, на пустом списке — под галочкой
## «Про» для вводимого имени.
func _buttons_y() -> float:
	return _field_line_y() + 64.0 * k + (56.0 * k if users.is_empty() else 0.0)


## Чипс строки: во всю ширину таблицы. Та же геометрия, что _draw.
## Шаг строк таблицы: на телефоне минимум под палец, иначе
## тап по строке (игра этим игроком) мажет мимо.
func _row_step() -> float:
	if Ui.is_desktop():
		return ROW_H * k
	return maxf(ROW_H * k, 64.0)


func _row_tap_rect(i: int) -> Rect2:
	var cols := _table_cols()
	var row_y := _rows_top() + float(i) * _row_step()
	return Rect2(
		cols[0] - 16.0 * k, row_y - 38.0 * k,
		cols[6] - cols[0] + 32.0 * k, _row_step() - 6.0 * k
	)


## Галочка «Про» в строке: тот же переключатель, что клавиша A,
## но пальцем/мышью. Тап по ней не играет профилем, только флагом.
## Тап-зона кнопки в строке: высотой — вся строка (по вертикали соседи
## не пересекаются: центры через _row_step), шириной — своя колонка
## (иначе перехватит тап соседа).
func _cell_rect(cx: float, row_y: float, col_w: float) -> Rect2:
	var h := _row_step()
	return Rect2(cx - col_w * 0.5, row_y - h * 0.5, col_w, h)


func _pro_tap_rect(i: int) -> Rect2:
	var cols := _table_cols()
	var row_y := _rows_top() + float(i) * _row_step()
	var cx := (cols[3] + cols[4]) * 0.5
	return _cell_rect(cx, row_y, cols[4] - cols[3])


## Галочка «Ё» в строке: строгая ё именно этому игроку.
## Тап не играет профилем, только флагом.
func _yo_tap_rect(i: int) -> Rect2:
	var cols := _table_cols()
	var row_y := _rows_top() + float(i) * _row_step()
	var cx := (cols[4] + cols[5]) * 0.5
	return _cell_rect(cx, row_y, cols[5] - cols[4])


## Крестик удаления в строке: открывает модалку подтверждения.
func _del_tap_rect(i: int) -> Rect2:
	var cols := _table_cols()
	var row_y := _rows_top() + float(i) * _row_step()
	var cx := (cols[5] + cols[6]) * 0.5
	return _cell_rect(cx, row_y, cols[6] - cols[5])


## Заголовки «Про»/«Ё»: тап показывает, что за галка (hint_header).
func _pro_head_rect() -> Rect2:
	var cols := _table_cols()
	var cx := (cols[3] + cols[4]) * 0.5
	var y := _rows_top() - 44.0 * k
	return Rect2(cx - 48.0 * k, y - 28.0 * k, 96.0 * k, 40.0 * k)


func _yo_head_rect() -> Rect2:
	var cols := _table_cols()
	var cx := (cols[4] + cols[5]) * 0.5
	var y := _rows_top() - 44.0 * k
	return Rect2(cx - 48.0 * k, y - 28.0 * k, 96.0 * k, 40.0 * k)


## Мелочи, из-за которых кнопку не попасть пальцем, а в чехле — тем
## более (жалоба автора 10.2026 на «Лог»):
##   *_TAP — минимальная сторона кнопки: меньше 64px не для пальца;
##   *_PAD — отступ от края: в чехле край экрана закрыт рукой.
## На десктопе курсором — точность не нужна, там по к=1 всё крупное.
const _TAP_MIN := 64.0
const _PAD_MIN := 22.0


## Высота угловой кнопки: минимум для пальца.
func _tap_h(h: float) -> float:
	return h if Ui.is_desktop() else maxf(h, _TAP_MIN)


## Отступ от края: минимум, чтобы палец не упирался в чехол.
func _pad(p: float) -> float:
	return p if Ui.is_desktop() else maxf(p, _PAD_MIN)


## Кнопка проверки обновлений (слева вверху) и строка состояния.
## Замер — тем же кеглем, каким рисует _button (26, не FONT_SMALL).
## Верхние углы едут под вырез камеры (top_safe).
func _upd_button_rect() -> Rect2:
	var pad := _pad(16.0 * k)
	var h := _tap_h(44.0 * k)
	var w := maxf(_text_size("Обновления", 26).x + 36.0 * k, h)
	return Rect2(pad, top_safe + pad, w, h)


## Карточка «Вышла версия?»: заголовок + заметки + две кнопки.
## Ширина — по самому длинному тексту, кнопки всегда внизу.
func _upd_card_rect() -> Rect2:
	var w := _text_size("Вышла " + _upd_tag, FONT_ROW).x + 96.0 * k
	for ln in _upd_notes:
		w = maxf(w, _text_size(ln, FONT_SMALL).x + 96.0 * k)
	w = clampf(w, 420.0 * k, view_w - 64.0 * k)
	var h := 200.0 * k + 30.0 * k * float(_upd_notes.size())
	return Rect2((view_w - w) * 0.5, (view_h - h) * 0.5, w, h)


func _upd_yes_rect() -> Rect2:
	var card := _upd_card_rect()
	return Rect2(
		Vector2(card.get_center().x - 190.0 * k, card.position.y + card.size.y - 80.0 * k),
		Vector2(170.0 * k, _tap_h(56.0 * k))
	)


func _upd_no_rect() -> Rect2:
	var card := _upd_card_rect()
	return Rect2(
		Vector2(card.get_center().x + 20.0 * k, card.position.y + card.size.y - 80.0 * k),
		Vector2(170.0 * k, _tap_h(56.0 * k))
	)


## Рамка поля ввода (рисуется только когда активно, тыкается всегда).
func _field_tap_rect() -> Rect2:
	var y := _field_line_y()
	var fw := _text_size(_field_text(), FONT_ROW).x
	return Rect2(48.0 * k, y - 38.0 * k, maxf(fw + 48.0 * k, 420.0 * k), 54.0 * k)


## Краски текста под режим: днём константы, ночью светлые.
func _ink() -> Color:
	if night:
		return Color("#f2ede0")
	return INK


func _uitext() -> Color:
	if night:
		return Color("#cfd6e4")
	return UI_TEXT


func _dim() -> Color:
	if night:
		return Color("#8b93a8")
	return DIM


## Спрайт ночью темнее и холоднее — см. Ui.NIGHT_TINT.
## Ночь: ручной выбор из файла важнее системы.
func _night_resolve() -> void:
	night = S.resolve_night(nmode, true, S.system_dark())


## Применить ночь: панели мутируют на месте, фон переключается.
func _apply_night() -> void:
	_night_resolve()
	if night:
		row_idle_sb.bg_color = Color(0.10, 0.12, 0.20, 0.60)
		box_sb.bg_color = Color("#232c44")
		box_sb.border_color = Color("#8b93a8")
		selbox_sb.bg_color = Color("#8ab4e0")
		selbox_sb.border_color = Color("#8b93a8")
		hint_sb.bg_color = Color(0.10, 0.12, 0.20, 0.80)
		hint_sb.border_color = Color("#3a4a6b")
		kb_key_sb.bg_color = Color("#232c44")
		kb_key_sb.border_color = Color("#8b93a8")
	else:
		row_idle_sb.bg_color = Color(1, 1, 1, 0.45)
		box_sb.bg_color = Color("#ffffff")
		box_sb.border_color = INK
		selbox_sb.bg_color = Color("#a9c6ec")
		selbox_sb.border_color = INK
		hint_sb.bg_color = Color(1, 1, 1, 0.72)
		hint_sb.border_color = Color("#e0d5bd")
		kb_key_sb.bg_color = Color("#ffffff")
		kb_key_sb.border_color = INK
	if _meadow != null:
		_meadow.night = night
		_meadow._apply_sky()
	queue_redraw()


## Переключатель ночи по кругу: день → ночь → авто → день.
## Выбор запоминается в настройках.
func _toggle_night() -> void:
	if nmode == S.NIGHT_DAY:
		nmode = S.NIGHT_ON
	elif nmode == S.NIGHT_ON:
		nmode = S.NIGHT_AUTO
	else:
		nmode = S.NIGHT_DAY
	S.set_night_mode(nmode)
	_apply_night()


## Кнопки «Играть», «Без профиля» и день/ночь: тройка по центру.
## Ночная — маленький квадрат: значок-символ в нём, а не вокруг.
## Высота кнопок действий: на телефоне минимум под палец (64px),
## иначе при мелком k кнопки — полоски, в которые не попасть.
func _btn_h() -> float:
	if Ui.is_desktop():
		return 52.0 * k
	return maxf(52.0 * k, 64.0)


func _play_tap_rect() -> Rect2:
	var y := _buttons_y()
	return Rect2(cx_of() - 288.0 * k, y, 230.0 * k, _btn_h())


func _guest_tap_rect() -> Rect2:
	var y := _buttons_y()
	return Rect2(cx_of() - 288.0 * k + 246.0 * k, y, 262.0 * k, _btn_h())


## Строка «Системная клавиатура» с галкой — под кнопками действий.
## Галка в сейве (устройство, как ночь): системная вместо своей.
func _night_tap_rect() -> Rect2:
	var y := _buttons_y()
	return Rect2(cx_of() - 288.0 * k + 524.0 * k, y, 52.0 * k, _btn_h())


func cx_of() -> float:
	return view_w * 0.5


## Кнопки модалки подтверждения: «Да» и «Нет» по центру карточки.
func _confirm_yes_rect() -> Rect2:
	var c := _confirm_card_rect().get_center()
	var h := _tap_h(56.0 * k)
	return Rect2(c + Vector2(-190.0 * k, 24.0 * k), Vector2(170.0 * k, h))


func _confirm_no_rect() -> Rect2:
	var c := _confirm_card_rect().get_center()
	var h := _tap_h(56.0 * k)
	return Rect2(c + Vector2(20.0 * k, 24.0 * k), Vector2(170.0 * k, h))


## Карточка модалки: по центру экрана, по ширине текста вопроса.
func _confirm_card_rect() -> Rect2:
	var t := "Удалить «%s»?" % confirm_name
	var w := maxf(_text_size(t, FONT_ROW).x + 96.0 * k, 420.0 * k)
	var h := 210.0 * k
	return Rect2((view_w - w) * 0.5, (view_h - h) * 0.5, w, h)


## Опасное действие (крестик удаления): красный в обеих темах.
func _danger() -> Color:
	if night:
		return Color("#ff7a6b")
	return Color("#b02323")


## Включён ли взрослый режим: у выбранного — его флаг, на пустом
## списке — флаг вводимого имени.
func _check_on() -> bool:
	if users.is_empty():
		return input_all_keys
	return bool(S.load_profile(users[sel]).get("all_keys", false))


## Кнопка-пилюля с подписью по центру.
func _button(r: Rect2, label: String) -> void:
	draw_style_box(hint_sb, r)
	var fs := int(26.0 * k)
	var w := _text_size(label, 26).x
	_text(label, Vector2(r.get_center().x - w * 0.5, r.position.y + 36.0 * k), 26, _ink())


## Кнопка день/ночь/авто: показывает ТЕКУЩИЙ режим. Все три значка —
## векторный композит с явными границами (строго внутри кнопки):
## солнце — диск с лучами, ночь — залитый месяц (диск + вырез),
## авто — полдиска (тёмная/светлая, как системная авто-тема).
## Шрифтовые ☀/◐ вылезали за кнопку, а эмоджи-лун в DejaVu нет
## вовсе (проверено по cmap — тофу на половине платформ).
func _draw_daynight(r: Rect2) -> void:
	draw_style_box(hint_sb, r)
	var c := r.get_center()
	var bg := hint_sb.bg_color
	if nmode == S.NIGHT_ON:
		# Залитый месяц: диск чернилами, вырез цветом кнопки со сдвигом.
		var mr := 11.0 * k
		draw_circle(c, mr, _ink())
		draw_circle(c + Vector2(mr * 0.42, -mr * 0.38), mr * 0.82, bg)
	elif nmode == S.NIGHT_AUTO:
		# Полдиска: левая чернилами, правая вырезана под кнопку.
		var ar := 11.0 * k
		draw_circle(c, ar, _ink())
		draw_rect(Rect2(c + Vector2(0.0, -ar), Vector2(ar, ar * 2.0)), bg)
	else:
		# Солнце: диск плюс 8 лучей, всё в радиусе 15k.
		var sr := 7.0 * k
		draw_circle(c, sr, _ink())
		for i in 8:
			var a := TAU * float(i) / 8.0
			var dir := Vector2(cos(a), sin(a))
			draw_line(c + dir * 10.5 * k, c + dir * 15.0 * k, _ink(), 2.5 * k)


func _draw() -> void:
	# Вуаль вместо глухой заливки: игра позади чуть видна, и понятно,
	# что меню — пауза, а не другой экран. Строки и тексты те же, что
	# были, вокруг них лишь карточки.
	var veil := PAPER
	if night:
		veil = Color("#141a2c")
	veil.a = 0.94
	draw_rect(Rect2(Vector2.ZERO, Vector2(view_w, view_h)), veil)
	var cx := view_w * 0.5
	var y := _rows_top()
	var top := y - 70.0 * k
	var title := "Кто играет?"
	var title_w := _text_size(title, FONT_TITLE).x
	_draw_bunny(Vector2(cx - title_w * 0.5 - 78.0 * k, top - 20.0 * k))
	_text(
		title,
		Vector2(cx - title_w * 0.5, top),
		FONT_TITLE,
		_ink()
	)
	if users.is_empty():
		_text(
			"Пока нет сохранённых игроков",
			Vector2(cx - _text_size("Пока нет сохранённых игроков", FONT_ROW).x * 0.5, y),
			FONT_ROW,
			_dim()
		)
	# Таблица игроков: шапка + строки во всю ширину. Тап по строке
	# сразу играет этим игроком, тап по галочке — только флаг,
	# тап по крестику — удаление с подтверждением. Тап по заголовку
	# «Про»/«Ё» объясняет галку. Выбранная стрелками колонка подсвечена
	# в шапке (пробел переключает её флаг).
	if not users.is_empty():
		var hcols := _table_cols()
		_text("Имя", Vector2(hcols[0], y - 44.0 * k), FONT_SMALL, _dim())
		_text("Ур", Vector2(hcols[1], y - 44.0 * k), FONT_SMALL, _dim())
		_text("Победы", Vector2(hcols[2], y - 44.0 * k), FONT_SMALL, _dim())
		var pro_hw := _text_size("Про", FONT_SMALL).x
		_text(
			"Про",
			Vector2((hcols[3] + hcols[4]) * 0.5 - pro_hw * 0.5, y - 44.0 * k),
			FONT_SMALL, _ink() if sel_col == 0 else _dim()
		)
		var yo_hw := _text_size("Ё", FONT_SMALL).x
		_text(
			"Ё",
			Vector2((hcols[4] + hcols[5]) * 0.5 - yo_hw * 0.5, y - 44.0 * k),
			FONT_SMALL, _ink() if sel_col == 1 else _dim()
		)
	for i in users.size():
		var row_y := y + float(i) * _row_step()
		var cols := _table_cols()
		var chip := _row_tap_rect(i)
		draw_style_box(row_sb if i == sel else row_idle_sb, chip)
		# Выбранная строка всегда на жёлтом — тёмным текстом.
		var tcol := INK if i == sel else _ink()
		_text(
			_short_name(users[i]), Vector2(cols[0], row_y), FONT_ROW, tcol
		)
		var cells := _cell_texts(users[i])
		_text(cells[0], Vector2(cols[1], row_y), FONT_ROW, tcol)
		_text(cells[1], Vector2(cols[2], row_y), FONT_ROW, tcol)
		# Галочка «Про» по центру своей колонки. Цвет — от БОКСА, а не
		# от строки: бокс белый днём и тёмный ночью, а цвет строки
		# (tcol) на выбранной строке тёмный всегда — ночью галочка
		# тонула в тёмном боксе, стоило навести выделение.
		var chk_col := Color("#f2ede0") if night else INK
		# Выбранная стрелками галка залита своим боксом (selbox_sb),
		# заголовок колонки подсвечен выше. Рамки было не видно
		# в длинном списке.
		var pro_box := box_sb
		var yo_box := box_sb
		if i == sel:
			if sel_col == 0:
				pro_box = selbox_sb
			else:
				yo_box = selbox_sb
		var pcx := (cols[3] + cols[4]) * 0.5
		draw_style_box(pro_box, Rect2(pcx - 16.0 * k, row_y - 32.0 * k, 32.0 * k, 32.0 * k))
		# Галка на залитом боксе — тёмная всегда (заливка светлая
		# в обеих темах), на обычном — от темы.
		var pro_chk := INK if pro_box == selbox_sb else chk_col
		if bool(S.load_profile(users[i]).get("all_keys", false)):
			draw_line(
				Vector2(pcx - 10.0 * k, row_y - 12.0 * k),
				Vector2(pcx, row_y - 2.0 * k),
				pro_chk, 4.0 * k
			)
			draw_line(
				Vector2(pcx, row_y - 2.0 * k),
				Vector2(pcx + 16.0 * k, row_y - 26.0 * k),
				pro_chk, 4.0 * k
			)
		# Галочка «Ё» по центру своей колонки: тот же бокс, тот же цвет.
		var ycx := (cols[4] + cols[5]) * 0.5
		draw_style_box(yo_box, Rect2(ycx - 16.0 * k, row_y - 32.0 * k, 32.0 * k, 32.0 * k))
		var yo_chk := INK if yo_box == selbox_sb else chk_col
		if bool(S.load_profile(users[i]).get("yo_strict", true)):
			draw_line(
				Vector2(ycx - 10.0 * k, row_y - 12.0 * k),
				Vector2(ycx, row_y - 2.0 * k),
				yo_chk, 4.0 * k
			)
			draw_line(
				Vector2(ycx, row_y - 2.0 * k),
				Vector2(ycx + 16.0 * k, row_y - 26.0 * k),
				yo_chk, 4.0 * k
			)
		# Крестик удаления по центру своей колонки.
		var dcx := (cols[5] + cols[6]) * 0.5
		var dtxt := "✕"
		var dw := _text_size(dtxt, FONT_ROW)
		_text(dtxt, Vector2(dcx - dw.x * 0.5, row_y), FONT_ROW, _danger())
	y = _field_line_y()
	# Компактные галки для вводимого имени — только когда список пуст
	# (иначе флаги живут в колонках таблицы). Обе в одну строку:
	# места хватает, раскладку не двигаем. Выбранную стрелками колонку
	# обводим (пробел переключает её флаг).
	if users.is_empty():
		var cy := _check_line_y()
		var ychk_col := Color("#f2ede0") if night else INK
		var pro_box0 := selbox_sb if sel_col == 0 else box_sb
		draw_style_box(pro_box0, Rect2(60.0 * k, cy - 32.0 * k, 32.0 * k, 32.0 * k))
		var pro_chk0 := INK if sel_col == 0 else ychk_col
		if _check_on():
			draw_line(
				Vector2(66.0 * k, cy - 12.0 * k), Vector2(76.0 * k, cy - 2.0 * k),
				pro_chk0, 4.0 * k
			)
			draw_line(
				Vector2(76.0 * k, cy - 2.0 * k), Vector2(92.0 * k, cy - 26.0 * k),
				pro_chk0, 4.0 * k
			)
		_text("Про", Vector2(104.0 * k, cy), FONT_ROW, _ink())
		var yob := 210.0 * k
		var yo_box0 := selbox_sb if sel_col == 1 else box_sb
		draw_style_box(yo_box0, Rect2(yob, cy - 32.0 * k, 32.0 * k, 32.0 * k))
		var yo_chk0 := INK if sel_col == 1 else ychk_col
		if input_yo_strict:
			draw_line(
				Vector2(yob + 6.0 * k, cy - 12.0 * k), Vector2(yob + 16.0 * k, cy - 2.0 * k),
				yo_chk0, 4.0 * k
			)
			draw_line(
				Vector2(yob + 16.0 * k, cy - 2.0 * k), Vector2(yob + 32.0 * k, cy - 26.0 * k),
				yo_chk0, 4.0 * k
			)
		_text("Ё", Vector2(yob + 44.0 * k, cy), FONT_ROW, _ink())
	# Поле ввода нового имени. Рамка — только когда активно, а тыкается
	# всегда: тап включает ввод, как Tab.
	var field_txt := _field_text()
	if input_active:
		draw_style_box(box_sb, _field_tap_rect())
	_text(
		field_txt,
		Vector2(60.0 * k, y),
		FONT_ROW,
		_ink() if input_active else _dim()
	)
	# Кнопки действий: та же механика, что Enter и Esc, но пальцем.
	# Третья — ночь: иконка показывает, во что переключит.
	_button(_play_tap_rect(), "Играть")
	_button(_guest_tap_rect(), "Без профиля")
	_draw_daynight(_night_tap_rect())
	_draw_own_kb()
	# Пояснение галки по тапу на заголовок — строкой под кнопками.
	# Модалка его перекрывает (рисуется позже поверх).
	if hint_header != "" and confirm_name == "":
		var expl: Array[String] = []
		if hint_header == "pro":
			expl = ["Про: все буквы сразу,", "важен регистр."]
		else:
			expl = ["Ё: без галки", "е засчитывается за ё."]
		var ey := _buttons_y() + _btn_h() + 30.0 * k
		for li in expl.size():
			var lw := _text_size(expl[li], FONT_SMALL).x
			_text(
				expl[li], Vector2(view_w * 0.5 - lw * 0.5, ey + 30.0 * k * float(li)),
				FONT_SMALL, _uitext()
			)
	# Кнопка проверки обновлений слева вверху + строка состояния.
	# На десктопе и телефоне одинаково: проверка — обычный HTTP.
	var ub := _upd_button_rect()
	_button(ub, "Обновления")
	if _upd_msg != "":
		_text(
			_upd_msg, Vector2(16.0 * k, ub.position.y + ub.size.y + 30.0 * k),
			FONT_SMALL, _uitext()
		)
		# Полоса прогресса закачки: видно, что дело идёт, и сколько ждать
		# (жалоба автора 10.2026: «было бы зорово видеть прогресс»).
		if _upd_state == "downloading" and _upd_pct >= 0:
			var bar := Rect2(
				16.0 * k, ub.position.y + ub.size.y + 66.0 * k,
				view_w - 32.0 * k, 14.0 * k
			)
			draw_rect(bar, Color(0.18, 0.17, 0.14, 0.55))
			var fill := bar
			fill.size.x = bar.size.x * (float(_upd_pct) / 100.0)
			draw_rect(fill, Color(0.35, 0.62, 0.92))
	# Модалка «Вышла версия?» — поверх всего, кроме удаления
	# (удаление первее: его ветка ввода раньше).
	if _upd_open:
		var dimmer := Color(0.05, 0.05, 0.08, 0.55)
		draw_rect(Rect2(Vector2.ZERO, Vector2(view_w, view_h)), dimmer)
		var ucard := _upd_card_rect()
		draw_style_box(box_sb, ucard)
		var ut := "Вышла %s" % _upd_tag
		var uw := _text_size(ut, FONT_ROW).x
		_text(
			ut,
			Vector2(ucard.get_center().x - uw * 0.5, ucard.position.y + 62.0 * k),
			FONT_ROW, _ink()
		)
		var notecap := ucard.size.x - 48.0 * k
		for li in _upd_notes.size():
			var ln := _clip(_upd_notes[li], FONT_SMALL, notecap)
			var lw := _text_size(ln, FONT_SMALL).x
			_text(
				ln,
				Vector2(ucard.get_center().x - lw * 0.5, ucard.position.y + 110.0 * k + 30.0 * k * float(li)),
				FONT_SMALL, _uitext()
			)
		# Кнопка: где игра ставит сама — «Скачать», где качает браузер
		# (Android) — честно «Загрузить»: дальше файл открывают руками.
		_button(_upd_yes_rect(), "Скачать" if Updater.self_installs() else "Загрузить")
		_button(_upd_no_rect(), "Позже")
	# Модалка подтверждения удаления — поверх всего.
	if confirm_name != "":
		var dimmer := Color(0.05, 0.05, 0.08, 0.55)
		draw_rect(Rect2(Vector2.ZERO, Vector2(view_w, view_h)), dimmer)
		var card := _confirm_card_rect()
		draw_style_box(box_sb, card)
		var qt := "Удалить «%s»?" % confirm_name
		var qw := _text_size(qt, FONT_ROW).x
		_text(
			qt,
			Vector2(card.get_center().x - qw * 0.5, card.position.y + 62.0 * k),
			FONT_ROW, _ink()
		)
		_button(_confirm_yes_rect(), "Да")
		_button(_confirm_no_rect(), "Нет")


## Зайчик рядом с заголовком: тот же спрайт, что в игре.
func _draw_bunny(c: Vector2) -> void:
	var s := 76.0 * k / HERO_TEX.get_height()
	draw_set_transform(c, 0.0, Vector2(s, s))
	draw_texture(HERO_TEX, -HERO_TEX.get_size() * 0.5, (Ui.NIGHT_TINT if night else Color.WHITE))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
