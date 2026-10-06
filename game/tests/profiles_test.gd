extends SceneTree
## Тесты профилей игроков и меню: правила имени, создание/удаление,
## последний игрок, сохранение прогресса, гость, взрослый режим
## «все клавиши», навигация меню с клавиатуры, F2 из игры.
## Запуск: godot --headless --path game --script res://tests/profiles_test.gd
## Код выхода 0 — всё сошлось.
##
## Файл профилей подменён на user://profiles_test.cfg: тест не должен
## трогать профиль автора.

const S := preload("res://scripts/save.gd")
const B := preload("res://scripts/balance.gd")

const TEST_PATH := "user://profiles_test.cfg"

var _failures: Array[String] = []
var _main: Node = null
var _menu: Node = null
## Кто выбран в меню. Лямбда в GDScript берёт локальные переменные по
## значению, поэтому приёмник — поле класса, а не локальная переменная.
var _picked := ""


func _check(cond: bool, what: String) -> void:
	if not cond:
		_failures.append(what)


func _on_chosen(user_name: String) -> void:
	_picked = user_name


func _initialize() -> void:
	# Тот же фиксированный сид, что в logic_test: тексты уровней
	# выбираются случайно, сценарии — нет.
	seed(20261006)
	S.PATH = TEST_PATH
	S.wipe()
	var scene: PackedScene = load("res://scenes/menu.tscn")
	_menu = scene.instantiate()
	root.add_child(_menu)


func _process(_dt: float) -> bool:
	_part1_names()
	_part2_last_user()
	_part3_progress()
	_part4_guest()
	_part5_all_keys()
	_part6_navigation()
	_part7_edit_name()
	_part8_all_keys_key()
	_part9_main_game()
	_part10_first_run()
	_part11_hidden_menu()
	_part12_soft_keyboard()
	_part13_touch()
	_part14_night()
	_report()
	return true


## Имя: обрезка пробелов, длина, отказ на пустом и на дубле.
func _part1_names() -> void:
	S.create_user("  Иван  ")
	_check(S.user_exists("Иван"), "leading/trailing spaces trimmed on create")
	_check(not S.user_exists("  Иван  "), "name stored without spaces")
	_check(not S.create_user(""), "empty name refused")
	_check(not S.create_user("   "), "blank name refused")
	_check(not S.create_user("Иван"), "duplicate name refused")
	S.create_user("Анна")
	_check(S.count_users() == 2, "two users after two creates")
	var long := "abcdefghijklmnopqrstuvwxyz"
	_check(S.create_user(long), "long name created")
	_check(
		S.user_exists(long.left(S.MAX_NAME_LENGTH)),
		"long name truncated to max length"
	)
	_check(S.user_list().size() == 3, "three users after long create")
	_check(
		not S.user_exists(long),
		"untruncated long name is not stored as a second user"
	)
	# Граница длины проверяем на самой чистке имени: ровно 15 символов
	# режется как надо, 17 — до 15. Создавать четвёртого игрока не надо.
	_check(
		S.clean_name("абвгдеёжзийклмн").length() == S.MAX_NAME_LENGTH,
		"exactly-max-length name is not shortened"
	)
	_check(
		S.clean_name("абвгдеёжзийклмноп").length() == S.MAX_NAME_LENGTH,
		"name longer than max is cut to max length"
	)
	_check(
		S.clean_name("  Иван  ") == "Иван",
		"clean_name trims spaces itself"
	)


## Последний игрок: последний созданный, валидность, удаление сбрасывает.
func _part2_last_user() -> void:
	_check(S.has_valid_last_user(), "last user valid after create")
	_check(
		S.get_last_user() == "abcdefghijklmno", "last user is the newest"
	)
	S.set_last_user("Анна")
	_check(S.get_last_user() == "Анна", "last user switched")
	S.delete_user("Анна")
	_check(S.get_last_user() == S.GUEST, "deleting last user resets it to guest")
	_check(not S.has_valid_last_user(), "no valid last user after delete")
	_check(not S.delete_user("Анна"), "deleting missing user is a no-op")


## Прогресс переживает сохранение и не зависит от соседей по файлу.
func _part3_progress() -> void:
	S.save_profile("Иван", {
		"difficulty": 4,
		"wins_in_row": 2,
		"ema_cpm": 77.0,
		"ema_acc": 0.91,
		"enemy_cps": 3.5,
		"total_games": 12,
		"total_wins": 9,
	})
	var p := S.load_profile("Иван")
	_check(int(p["difficulty"]) == 4, "difficulty round-trips")
	_check(int(p["wins_in_row"]) == 2, "wins_in_row round-trips")
	_check(is_equal_approx(float(p["ema_cpm"]), 77.0), "ema_cpm round-trips")
	_check(int(p["total_games"]) == 12, "total_games round-trips")
	_check(
		int(S.load_profile("abcdefghij")["difficulty"]) == 0,
		"other profile untouched by save"
	)
	_check(
		int(S.load_profile("нет такого")["difficulty"]) == 0,
		"unknown profile gets defaults"
	)
	_check(
		is_equal_approx(float(S.load_profile("нет такого")["ema_cpm"]), 0.0),
		"unknown profile default ema_cpm is zero"
	)


## Гость ничего не пишет: пустое имя и S.GUEST.
func _part4_guest() -> void:
	var before := S.count_users()
	S.save_profile(S.GUEST, {"difficulty": 9})
	S.save_profile("", {"difficulty": 9})
	_check(S.count_users() == before, "guest save does not create a profile")
	_check(
		int(S.load_profile(S.GUEST)["difficulty"]) == 0,
		"guest profile is always default"
	)


## Взрослый режим «все клавиши»: переключается и переживает сохранение.
func _part5_all_keys() -> void:
	_check(not S.get_all_keys("Иван"), "all_keys off by default")
	_check(not S.user_exists("нет такого"), "no such user before set_all_keys")
	S.set_all_keys("нет такого", true)
	_check(
		not S.user_exists("нет такого"),
		"set_all_keys on an unknown user does not create it"
	)
	S.set_all_keys("Иван", true)
	_check(S.get_all_keys("Иван"), "all_keys turns on")
	S.save_profile("Иван", {"difficulty": 5, "all_keys": true})
	_check(S.get_all_keys("Иван"), "all_keys survives a profile save")
	S.save_profile("Иван", {"difficulty": 6, "all_keys": false})
	_check(not S.get_all_keys("Иван"), "all_keys survives a profile save off")
	S.set_all_keys("Иван", false)


## Навигация списка: ↑↓ с перехватом, Delete удаляет, Enter входит.
func _part6_navigation() -> void:
	_menu.call("_reload")
	_menu.sel = 0
	var n: int = _menu.users.size()
	_check(n == 2, "menu lists users after deletes")
	_menu.call("_nav", -1)
	_check(_menu.sel == n - 1, "up from first wraps to last")
	_menu.call("_nav", 1)
	_check(_menu.sel == 0, "down from last wraps to first")
	_menu.sel = 0
	var first := String(_menu.users[0])
	# Удаляем без записи в файл: last_played у всех одинаковый, порядок
	# не изменится, и первый в списке будет предсказуем.
	_menu.input_active = true
	_menu.call("_delete")
	_check(
		_menu.users.has(first), "delete ignored while the name field is active"
	)
	_menu.input_active = false
	_menu.call("_delete")
	_check(not _menu.users.has(first), "delete removes the selected user")
	_check(
		not S.user_exists(first), "delete removed the user from disk too"
	)
	_check(S.user_list().size() == n - 1, "delete shrinks the list by one")


## Поле ввода: Tab, набор, Backspace, Enter создаёт, Enter с готовым
## именем просто входит.
func _part7_edit_name() -> void:
	_menu.call("_reload")
	_menu.call("_toggle_input")
	_check(_menu.input_active, "tab opens the name field")
	for ch in "Петя":
		_menu.call("_unhandled_key_input", _key_event(ch))
	_check(_menu.input_text == "Петя", "typing appends to the name field")
	_menu.call("_unhandled_key_input", _key(KEY_BACKSPACE))
	_check(_menu.input_text == "Пет", "backspace erases one char")
	_menu.call("_unhandled_key_input", _key_event("я"))
	_check(_menu.input_text == "Петя", "typing continues after backspace")
	_picked = ""
	_menu.chosen.connect(_on_chosen)
	_menu.call("_unhandled_key_input", _key(KEY_ENTER))
	_check(S.user_exists("Петя"), "enter creates the typed profile")
	_check(_picked == "Петя", "menu emits the chosen profile")
	_check(not _menu.input_active, "name field closes after creating")
	# Пробел в имени не печатается, чтобы не плодить невидимые дубли.
	_menu.call("_reload")
	_menu.call("_toggle_input")
	_menu.call("_unhandled_key_input", _key_event(" "))
	_check(_menu.input_text == "", "space is not typed into the name field")
	for ch in "Петя":
		_menu.call("_unhandled_key_input", _key_event(ch))
	_menu.call("_unhandled_key_input", _key(KEY_ENTER))
	_check(S.count_users() == 2, "re-entering an existing name makes no duplicate")
	_check(_picked == "Петя", "an existing name is entered, not created again")


## Клавиша A в меню переключает взрослый режим, но только когда поле
## ввода неактивно (иначе это буква в имени).
func _part8_all_keys_key() -> void:
	_menu.call("_reload")
	_menu.sel = 0
	var who := String(_menu.users[0])
	_check(
		not S.get_all_keys(who), "menu target starts with all_keys off"
	)
	_menu.input_active = false
	_menu.call("_unhandled_key_input", _key(KEY_A))
	_check(S.get_all_keys(who), "A turns all_keys on in the menu")
	_menu.call("_unhandled_key_input", _key(KEY_A))
	_check(not S.get_all_keys(who), "A turns all_keys off in the menu")
	# При активном поле ввода клавиша A — это буква, а не переключатель
	# режима. Событие полное: и keycode, и unicode, как от живой клавиатуры.
	_menu.call("_toggle_input")
	_menu.input_text = ""
	_menu.call("_unhandled_key_input", _typed_key(KEY_A, "a"))
	_check(_menu.input_text == "a", "A types a letter while the field is active")
	_check(
		not S.get_all_keys(who), "A in the name field does not toggle all_keys"
	)
	_menu.call("_unhandled_key_input", _key_event(" "))
	_check(_menu.input_text == "a", "space in the name field is still ignored")
	_menu.input_active = false


## F2 открывает меню из игры, Esc в меню — гость, F2 из меню возвращает
## в игру с тем же игроком.
func _part9_main_game() -> void:
	S.set_last_user("Петя")
	var scene: PackedScene = load("res://scenes/main.tscn")
	_main = scene.instantiate()
	root.add_child(_main)
	_main.call("_unhandled_key_input", _key(KEY_F2))
	_check(_main.menu_open, "F2 opens the player menu")
	_check(_main.menu != null and _main.menu.visible, "menu node is visible")
	var menu: Node = _main.menu
	# Тот же приёмник chosen, что и у отдельного меню в _initialize:
	# лямбда в GDScript берёт локальные переменные по значению.
	menu.chosen.connect(_on_chosen)
	# Пока меню открыто, игровые клавиши до main.gd не доходят. Шлём
	# именно ту букву, которую игра ждёт сейчас: иначе main.gd её
	# отбросит и проверка ничего не значит.
	_main.grace_t = 0.0
	var wanted: String = _main._current()
	if wanted.is_empty():
		_failures.append("level has no current letter to type")
	else:
		var typed_before: int = _main.typed_ok
		_main.call("_unhandled_key_input", _key_event(wanted))
		_check(
			int(_main.typed_ok) == typed_before,
			"game keys do not leak into the game while the menu is open"
		)
		_check(
			int(_main.cursor_pos) == 0,
			"the cursor does not move while the menu is open"
		)
	menu.call("_reload")
	menu.input_active = false
	# Именно клавиша Esc, а не прямой вызов _guest(): проверяем всю
	# проводку от клавиатуры до сигнала chosen.
	menu.call("_unhandled_key_input", _key(KEY_ESCAPE))
	_check(not _main.menu_open, "guest choice closes the menu")
	_check(_main.profile_name == S.GUEST, "guest choice switches to guest")
	_check(_main.state == "playing", "guest choice starts the game")
	_check(
		S.get_last_user() == S.GUEST, "guest choice is remembered as last user"
	)
	# F2 из меню возвращает в игру тем же игроком, кого открыли: выбрать
	# другого в списке и нажать F2 — отмена выбора, а не смена игрока.
	_main.profile_name = "Петя"
	_main.call("_unhandled_key_input", _key(KEY_F2))
	_check(_main.menu_open, "F2 reopens the menu from the game")
	menu.call("_reload")
	menu.input_active = false
	menu.sel = 0
	menu.call("_unhandled_key_input", _key(KEY_F2))
	_check(not _main.menu_open, "F2 from the menu returns to the game")
	_check(
		_main.profile_name == "Петя", "F2 from the menu keeps the same player"
	)
	# F2 в меню не должен забывать последнего игрока в файле.
	_check(S.get_last_user() == S.GUEST, "F2 from the menu keeps last user as guest")
	# Enter в списке входит на выбранного профиля, а не на первого.
	# Меню после F2-возврата закрыто, а скрытое меню клавиш не видит
	# (проверка видимости в _unhandled_key_input) — открываем заново,
	# как это делает игрок.
	_main.call("_unhandled_key_input", _key(KEY_F2))
	_check(_main.menu_open, "F2 reopens the menu for the enter test")
	menu.call("_reload")
	menu.input_active = false
	menu.sel = 1
	_picked = ""
	menu.call("_unhandled_key_input", _key(KEY_ENTER))
	_check(_picked == String(menu.users[1]), "enter opens the selected profile")
	_check(
		_main.profile_name == String(menu.users[1]),
		"the game switches to the selected profile"
	)
	_check(not _main.menu_open, "enter closes the menu")
	# Больше MAX_NAME_LENGTH символов в имя не влезает. Меню Enter
	# закрыл, открываем заново: скрытое меню набор не видит.
	_main.call("_unhandled_key_input", _key(KEY_F2))
	menu.call("_reload")
	menu.call("_toggle_input")
	for ch in "абвгдеёжзийклмнопрст":
		menu.call("_unhandled_key_input", _key_event(ch))
	_check(
		String(menu.input_text).length() == S.MAX_NAME_LENGTH,
		"the name field stops at the max length"
	)
	menu.input_active = false
	# Приоритет «все клавиши»: ручной флаг важнее флага профиля, флаг
	# профиля важнее debug-сборки. Все восемь сочетаний — чистая функция,
	# от сборки движка не зависит.
	var ak: Callable = _main.all_keys_on
	_check(not ak.call(-1, false, false), "nothing set: progression")
	_check(ak.call(-1, false, true), "debug build alone: all keys")
	_check(ak.call(-1, true, false), "profile flag alone: all keys")
	_check(ak.call(-1, true, true), "profile flag and debug: all keys")
	_check(not ak.call(0, false, true), "manual off beats debug")
	_check(not ak.call(0, true, true), "manual off beats the profile flag")
	_check(not ak.call(0, true, false), "manual off with nothing else")
	_check(ak.call(1, false, false), "manual on wins over progression")
	_check(ak.call(1, true, false), "manual on keeps the profile flag on")
	# В игре: у профиля с флагом активны все знаки, регистр важен.
	_main.all_keys_override = 1
	S.set_all_keys("Петя", true)
	_main._menu_chosen("Петя")
	_check(_main.profile_all_keys, "profile all_keys reaches the game")
	_check(_main._all_keys(), "all_keys mode is on in the game")
	_check(_main.exact_case, "all_keys mode is case-sensitive")
	_check(
		int(_main.active.size()) == _letters_on_screen(),
		"all_keys mode activates every letter on screen"
	)
	# А без флага — прогрессия от букв, регистр не важен.
	S.set_all_keys("Петя", false)
	_main.all_keys_override = 0
	_main._menu_chosen("Петя")
	_check(not _main.profile_all_keys, "profile all_keys off reaches the game")
	_check(not _main._all_keys(), "progression mode is off in the game")
	_check(not _main.exact_case, "progression mode ignores case")
	_check(
		int(_main.active.size()) == B.INITIAL_ACTIVE_COUNT,
		"progression mode starts with a few active letters, not all"
	)
	_main.all_keys_override = -1
	# Гость никогда не сохраняется: результат партии не должен попасть
	# ни в один профиль. Проверяем жёсткий случай: играем гостем, а
	# последним игроком в файле — «Петя» (так бывает, если файл правили
	# руками или гостя сменили в обход меню). Итог всё равно не пишется.
	var pety_before: Dictionary = S.load_profile("Петя")
	_main._menu_chosen(S.GUEST)
	_check(_main.profile_name == S.GUEST, "guest is playing")
	S.set_last_user("Петя")
	_main.enemy_cps = 9.9
	_main.difficulty = 7
	_main.wins_in_row = 2
	_main._finish(true)
	_check(not _main.fw_parts.is_empty(), "winning spawns fireworks")
	_check("CPM" in _main.overlay_label.text, "modal shows pace stats")
	var pety_after: Dictionary = S.load_profile("Петя")
	_check(
		is_equal_approx(
			float(pety_after["enemy_cps"]), float(pety_before["enemy_cps"])
		),
		"guest result does not write into the last profile"
	)
	_check(
		int(pety_after["difficulty"]) == int(pety_before["difficulty"]),
		"guest result does not change the last profile difficulty"
	)
	_check(
		int(pety_after["wins_in_row"]) == int(pety_before["wins_in_row"]),
		"guest result does not change the last profile win streak"
	)
	_check(S.user_list().size() == 2, "guest result creates no profile")
	_main.queue_free()
	_main = null


## Первый запуск: при пустом списке поле имени открыто сразу, Tab не
## нужен. Иначе буквы уходят в никуда и кажется, что игра не реагирует, —
## именно так автор и застрял: жал буквы, а они не появлялись.
func _part10_first_run() -> void:
	for u in S.user_list():
		S.delete_user(u)
	_check(S.count_users() == 0, "all users deleted for the first-run check")
	_menu.call("_reload")
	_check(_menu.input_active, "name field is open on an empty list")
	_check(String(_menu.input_text) == "", "name field starts empty")
	# Галочка на пустом списке относится к вводимому имени: включаем,
	# набираем, создаём — флаг переезжает в профиль.
	_menu.call("_input", _tap(_menu.call("_check_tap_rect").get_center()))
	_check(_menu.input_all_keys, "checkbox arms the typed name")
	for ch in "Гри":
		_menu.call("_unhandled_key_input", _key_event(ch))
	_menu.call("_unhandled_key_input", _key(KEY_ENTER))
	_check(S.user_exists("Гри"), "profile created with checkbox on")
	_check(S.get_all_keys("Гри"), "pending flag moved into the profile")
	_check(not _menu.input_all_keys, "pending flag resets after creating")
	S.delete_user("Гри")
	_menu.call("_reload")
	# Буквы печатаются сразу, без Tab.
	for ch in "Маша":
		_menu.call("_unhandled_key_input", _key_event(ch))
	_check(String(_menu.input_text) == "Маша", "typing works without Tab")
	# Подсказка не врёт про Tab: поле уже открыто.
	_check(
		String(_menu.call("_hint")).find("Tab") < 0,
		"empty-list hint does not mention Tab"
	)
	# Enter с набранным именем создаёт профиль из автооткрытого поля.
	# Приёмник chosen подключён ещё в седьмой части, второй раз не надо:
	# в Godot 4 повторный connect того же вызова — ошибка.
	_picked = ""
	_menu.call("_unhandled_key_input", _key(KEY_ENTER))
	_check(S.user_exists("Маша"), "enter creates the profile from the open field")
	_check(_picked == "Маша", "menu emits the profile from the open field")
	_check(not _menu.input_active, "name field closes after creating")
	# Удалили последнего — поле снова само открылось, а Enter по пустому
	# полю и пустому списку ведёт в гости: другого выхода нет.
	S.delete_user("Маша")
	_menu.call("_reload")
	_check(
		_menu.input_active, "name field reopens after deleting the last user"
	)
	_picked = ""
	_menu.call("_unhandled_key_input", _key(KEY_ENTER))
	_check(_picked == S.GUEST, "enter on an empty field and list is guest")


## Скрытое меню глухое: пока идёт игра, клавиши разбирает она, а не
## меню (оно добавлено позже и получает _unhandled_key_input первым).
## Без проверки видимости F2 во время игры молча перезапускал гостя,
## а буква Ф (тот же keycode, что и A) переключала «все клавиши».
func _part11_hidden_menu() -> void:
	S.create_user("Жора")
	_menu.call("_reload")
	_menu.sel = 0
	# Как после возврата в игру по F2: меню скрыто, но поле ввода
	# осталось включённым, а resume_user — от прошлого открытия.
	_menu.input_active = true
	_menu.resume_user = "Жора"
	_menu.visible = false
	_picked = ""
	_menu.call("_unhandled_key_input", _key(KEY_F2))
	_check(_picked == "", "hidden menu ignores F2")
	_menu.call("_unhandled_key_input", _key_event("Ф"))
	_check(String(_menu.input_text) == "", "hidden menu ignores typing")
	_menu.input_active = false
	_menu.call("_unhandled_key_input", _typed_key(KEY_A, "a"))
	_check(
		not S.get_all_keys("Жора"), "hidden menu does not toggle all_keys"
	)
	_menu.visible = true
	# resume_user ставит игра при открытии меню (_open_menu): проверяем
	# ту же связку — F2 возвращает того, с кем меню открыли.
	_menu.resume_user = "Жора"
	_menu.call("_unhandled_key_input", _key(KEY_F2))
	_check(_picked == "Жора", "visible menu answers F2 with resume_user")
	S.delete_user("Жора")


## Системная клавиатура Android: события без keycode, один unicode.
## Буквы печатаются как обычно, Backspace — unicode 8, Enter — unicode 10/13.
func _part12_soft_keyboard() -> void:
	for u in S.user_list():
		S.delete_user(u)
	_menu.call("_reload")
	_check(_menu.input_active, "empty list opens the field for typing")
	for ch in "Ю":
		_menu.call("_unhandled_key_input", _key_event(ch))
	_check(String(_menu.input_text) == "Ю", "soft letter typed")
	_menu.call("_unhandled_key_input", _softkey_event(8))
	_check(String(_menu.input_text) == "", "unicode backspace erases")
	_picked = ""
	for ch in "Юра":
		_menu.call("_unhandled_key_input", _key_event(ch))
	_menu.call("_unhandled_key_input", _softkey_event(13))
	_check(S.user_exists("Юра"), "unicode enter creates the profile")
	_check(_picked == "Юра", "unicode enter emits the profile")
	S.delete_user("Юра")


## Тач и мышь: тап по строке играет этим игроком, тап по полю включает
## ввод, кнопки «Играть»/«Без профиля» дублируют Enter/Esc. Прямоугольники
## считает то же меню (хелперы tap_rect), тест только тыкает в них.
func _part13_touch() -> void:
	for u in S.user_list():
		S.delete_user(u)
	S.create_user("Таня")
	S.create_user("Федя")
	_menu.call("_reload")
	_menu.visible = true
	_menu.input_active = false
	# Прямоугольники из тех же хелперов, что рисует _draw: хит-тест честный.
	var first := String(_menu.users[0])
	var second := String(_menu.users[1])
	_picked = ""
	_menu.call("_input", _tap(_menu.call("_row_tap_rect", 1).get_center()))
	_check(_picked == second, "tap on a row plays as that user")
	_menu.call("_input", _tap(_menu.call("_field_tap_rect").get_center()))
	_check(_menu.input_active, "tap on the field opens input")
	_picked = ""
	_menu.call("_input", _tap(_menu.call("_guest_tap_rect").get_center()))
	_check(_picked == S.GUEST, "guest button enters as guest")
	_menu.sel = 0
	_picked = ""
	_menu.call("_input", _tap(_menu.call("_play_tap_rect").get_center()))
	_check(_picked == first, "play button enters the selected profile")
	# Галочка «все клавиши»: тап переключает флаг выбранного.
	_menu.call("_input", _tap(_menu.call("_check_tap_rect").get_center()))
	_check(S.get_all_keys(first), "checkbox turns all_keys on")
	_menu.call("_input", _tap(_menu.call("_check_tap_rect").get_center()))
	_check(not S.get_all_keys(first), "checkbox turns all_keys off")
	# Узкий экран: ужатая подпись влезает, строки подсказки влезают,
	# блок опущен ниже альбомного.
	_menu.view_w = 1100.0
	_menu.view_h = 650.0
	_menu.k = 1.0
	var y_land: float = _menu.call("_rows_top")
	_menu.view_w = 412.0
	_menu.view_h = 915.0
	_menu.k = 0.736
	_check(_menu.call("_rows_top") > y_land, "portrait block sits lower")
	var cap := String(_menu.call("_row_caption", first))
	_check(not ("побед" in cap), "narrow caption drops the long words")
	_check(
		_menu.call("_text_size", cap, 30).x <= 412.0,
		"narrow caption fits the screen"
	)
	for ln in _menu.call("_hint_lines"):
		_check(
			_menu.call("_text_size", String(ln), 20).x <= 412.0,
			"hint lines fit the narrow screen"
		)
	# Галочка «все клавиши» и рамка поля ввода не наезжают друг на друга
	# НИ НА ПУСТОМ СПИСКЕ ИГРОКОВ: галочка есть и там (относится к
	# вводимому имени), а поле раньше получало запас под неё только
	# при непустом списке — и рамка накрывала подпись (видел на
	# эмуляторе, строка читалась как «Расскажи»).
	for case_vw in [1100.0, 412.0]:
		_menu.view_w = case_vw
		_menu.view_h = 915.0 if case_vw < 700.0 else 650.0
		_menu.k = 0.736 if case_vw < 700.0 else 1.0
		var chk := Rect2(_menu.call("_check_tap_rect"))
		var fld := Rect2(_menu.call("_field_tap_rect"))
		_check(
			fld.position.y >= chk.position.y + chk.size.y - 1.0,
			"field frame clears the all-keys checkbox (vw=%.0f)" % case_vw
		)
		# Кнопки под полем не наезжают на поле и остаются на экране.
		var btn := Rect2(_menu.call("_play_tap_rect"))
		_check(
			btn.position.y >= fld.position.y + fld.size.y - 1.0,
			"buttons sit below the field (vw=%.0f)" % case_vw
		)
		_check(
			btn.position.y + btn.size.y <= _menu.view_h,
			"buttons fit on screen (vw=%.0f)" % case_vw
		)
		# С открытой клавиатурой (kb_h) низ меню — не низ экрана: кнопки
		# и подсказка обязаны влезть ВЫШЕ неё, иначе на телефоне поле ввода
		# и кнопки уезжают под Gboard. Было: меню про kb_h не знало вообще.
		_menu.set("kb_h", _menu.view_h * 0.42)
		# k — как в _relayout (от эффективной высоты): иначе проверка
		# бессмысленна, в проде k жмётся именно там.
		_menu.k = clampf(minf(_menu.view_w / 1100.0, (_menu.view_h - float(_menu.get("kb_h"))) / 650.0), 0.5, 2.5)
		var eff: float = _menu.view_h - float(_menu.get("kb_h"))
		var btn2 := Rect2(_menu.call("_play_tap_rect"))
		_check(
			btn2.position.y + btn2.size.y <= eff + 1.0,
			"buttons clear the keyboard (vw=%.0f)" % case_vw
		)
		var hpill := Rect2(_menu.call("_hint_rect"))
		_check(
			hpill.position.y + hpill.size.y <= eff + 1.0,
			"hint pill clears the keyboard (vw=%.0f)" % case_vw
		)
		_menu.set("kb_h", 0.0)
	# Скрытое меню тычков не видит.
	_menu.visible = false
	_picked = ""
	_menu.call("_input", _tap(_menu.call("_row_tap_rect", 0).get_center()))
	_check(_picked == "", "hidden menu ignores taps")
	_menu.visible = true
	for u in S.user_list():
		S.delete_user(u)


## Ночь: ручной выбор важнее системы, запоминается в файле, кнопка
## переключает туда-обратно.
func _part14_night() -> void:
	var rs: Callable = S.resolve_night
	_check(rs.call(1, false, false), "manual night wins")
	_check(not rs.call(0, true, true), "manual day wins over system dark")
	_check(rs.call(-1, true, true), "auto follows the system dark")
	_check(not rs.call(-1, false, false), "no support means day")
	_check(not rs.call(-1, true, false), "auto follows system light")
	S.set_night_mode(5)
	_check(S.get_night_mode() == 1, "mode clamps to night")
	S.set_night_mode(-9)
	_check(S.get_night_mode() == -1, "mode clamps to auto")
	_menu.visible = true
	_menu.night = false
	_menu.call("_input", _tap(_menu.call("_night_tap_rect").get_center()))
	_check(_menu.night, "night button flips the mode on")
	_check(S.get_night_mode() == 1, "flip persists as night")
	_menu.call("_input", _tap(_menu.call("_night_tap_rect").get_center()))
	_check(not _menu.night, "night button flips the mode off")
	_check(S.get_night_mode() == 0, "flip back persists as day")


## RU-клавиатура: печатать русское с латинской (стенд, хромбуки).
## Глобально, как ночь. Тап по галочке и клавиша R при неактивном поле.
func _letters_on_screen() -> int:
	var letters := {}
	for line in _main.display_lines:
		for i in line.length():
			letters[line.substr(i, 1)] = true
	return letters.size()


func _key(code: int) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.pressed = true
	return ev


func _key_event(ch: String) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.unicode = ch.unicode_at(0)
	ev.pressed = true
	return ev


## Событие как от живой клавиатуры: и код клавиши, и символ. Так ведёт
## себя X11, и именно на этом держится разница между «буква A в имени»
## и «переключить взрослый режим».
func _typed_key(code: int, ch: String) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.unicode = ch.unicode_at(0)
	ev.pressed = true
	return ev


## Событие с системной клавиатуры Android: кода клавиши нет, только unicode.
func _softkey_event(code: int) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.unicode = code
	ev.pressed = true
	return ev


## Клик мыши с координатами. Палец на Android сам превращается в клик,
## поэтому касания отдельно не тестируем: обработчик их не слушает.
func _tap(pos: Vector2) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = pos
	return ev


func _report() -> void:
	S.PATH = "user://modern_baby_type.cfg"
	DirAccess.remove_absolute(
		ProjectSettings.globalize_path(TEST_PATH)
	)
	if _failures.is_empty():
		print("PROFILES_TEST: PASS")
		return
	for f in _failures:
		printerr("FAIL: ", f)
	printerr("PROFILES_TEST: FAIL (%d)" % _failures.size())
	quit(1)
