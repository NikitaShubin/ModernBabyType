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
const K := preload("res://scripts/kbd.gd")
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
	_part15_update()
	_part16_touch_sizes()
	_part17_sys_keyboard()
	_part18_touch_targets()
	_part19_menu_typing()
	_part20_upd_progress()
	_part21_own_keyboard()
	_part22_compose_name()
	_part23_portrait_dense()
	_part24_rounded_corners()
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
	# Строгая ё: по умолчанию строго, переключается и переживает сохранение.
	_check(S.get_yo_strict("Иван"), "yo is strict by default")
	_check(not S.user_exists("нет такого"), "no such user before set_yo_strict")
	S.set_yo_strict("нет такого", false)
	_check(
		not S.user_exists("нет такого"),
		"set_yo_strict on an unknown user does not create it"
	)
	S.set_yo_strict("Иван", false)
	_check(not S.get_yo_strict("Иван"), "yo leniency turns on")
	S.save_profile("Иван", {"difficulty": 5, "yo_strict": false})
	_check(not S.get_yo_strict("Иван"), "yo leniency survives a profile save")
	S.set_yo_strict("Иван", true)


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
	_check(
		String(_menu.confirm_name) == "", "no confirm while the field is active"
	)
	_menu.input_active = false
	# Удаление теперь двухшаговое: Delete только спрашивает, список
	# и диск целы, пока не сказали «Да».
	_menu.call("_delete")
	_check(
		String(_menu.confirm_name) == first, "delete arms the confirm modal"
	)
	_check(
		_menu.users.has(first), "armed delete keeps the user in the list"
	)
	_check(
		S.user_exists(first), "armed delete keeps the user on disk"
	)
	# «Нет» — профиль цел, модалка гаснет.
	_menu.call("_cancel_confirm")
	_check(
		String(_menu.confirm_name) == "", "cancel closes the confirm modal"
	)
	_check(
		_menu.users.has(first), "cancel keeps the user in the list"
	)
	# Разрушительные пути — на одноразовых профилях, чтобы дальше
	# по тесту список остался тем же: среди живых относительный
	# порядок не меняется (сортировка по last_played).
	S.create_user("Снос1")
	S.create_user("Снос2")
	S.create_user("Снос3")
	_menu.call("_reload")
	_menu.input_active = false
	# Прямой вызов: «Да» сносит из списка и с диска.
	_menu.sel = _menu.users.find("Снос1")
	_menu.call("_delete")
	_menu.call("_confirm_delete")
	_check(not _menu.users.has("Снос1"), "confirm removes the selected user")
	_check(
		not S.user_exists("Снос1"), "confirm removed the user from disk too"
	)
	_check(
		S.user_list().size() == n + 2, "confirm shrinks the list by one"
	)
	# Клавиатурный путь: Delete спрашивает, Enter подтверждает.
	_menu.sel = _menu.users.find("Снос2")
	_menu.call("_unhandled_key_input", _key(KEY_DELETE))
	_check(
		String(_menu.confirm_name) == "Снос2", "Delete key arms the confirm"
	)
	_menu.call("_unhandled_key_input", _key(KEY_ENTER))
	_check(
		not _menu.users.has("Снос2"), "Enter confirms the delete"
	)
	# Отмена с клавиатуры — на живом: Delete спрашивает, Esc отпускает.
	_menu.sel = 0
	var third := String(_menu.users[0])
	_menu.call("_unhandled_key_input", _key(KEY_DELETE))
	_menu.call("_unhandled_key_input", _key(KEY_ESCAPE))
	_check(
		String(_menu.confirm_name) == "", "Escape cancels the confirm"
	)
	_check(_menu.users.has(third), "Escape keeps the user")
	# Тач-путь: крестик спрашивает, «Нет» отпускает, «Да» сносит.
	# Тап по строке при открытой модалке глотается и никого не играет.
	if not _menu.chosen.is_connected(_on_chosen):
		_menu.chosen.connect(_on_chosen)
	var ti: int = _menu.users.find("Снос3")
	_menu.sel = ti
	_menu.call("_input", _tap(_menu.call("_del_tap_rect", ti).get_center()))
	printerr("DBG vw=", _menu.view_w, " k=", _menu.k, " touch=", Ui.force_touch, " cols=", _menu._table_cols(), " del=", Rect2(_menu.call("_del_tap_rect", ti)))
	_check(
		String(_menu.confirm_name) == "Снос3", "cross tap arms the confirm"
	)
	_picked = ""
	_menu.call("_input", _tap(_menu.call("_row_tap_rect", ti).get_center()))
	_check(
		_picked == "", "row tap is swallowed while confirming"
	)
	_check(
		_menu.users.has("Снос3"), "row tap while confirming deletes nothing"
	)
	_menu.call("_input", _tap(_menu.call("_confirm_no_rect").get_center()))
	_check(_menu.users.has("Снос3"), "No button keeps the user")
	_menu.call("_input", _tap(_menu.call("_del_tap_rect", ti).get_center()))
	_menu.call("_input", _tap(_menu.call("_confirm_yes_rect").get_center()))
	_check(not _menu.users.has("Снос3"), "Yes button removes the user")
	_check(
		_menu.users.size() == n, "temp profiles are gone, list is intact"
	)


## Поле ввода: Tab, набор, Backspace, Enter создаёт, Enter с готовым
## именем просто входит.
func _part7_edit_name() -> void:
	_menu.call("_reload")
	var users_before: int = S.count_users()
	_menu.call("_toggle_input")
	_check(_menu.input_active, "tab opens the name field")
	for ch in "Петя":
		_menu.call("_unhandled_key_input", _key_event(ch))
	_menu.call("_cbuf_flush")
	_check(_menu.input_text == "Петя", "typing appends to the name field")
	_menu.call("_unhandled_key_input", _key(KEY_BACKSPACE))
	_check(_menu.input_text == "Пет", "backspace erases one char")
	_menu.call("_unhandled_key_input", _key_event("я"))
	_menu.call("_cbuf_flush")
	_check(_menu.input_text == "Петя", "typing continues after backspace")
	_picked = ""
	if not _menu.chosen.is_connected(_on_chosen):
		_menu.chosen.connect(_on_chosen)
	_menu.call("_unhandled_key_input", _key(KEY_ENTER))
	_check(S.user_exists("Петя"), "enter creates the typed profile")
	_check(_picked == "Петя", "menu emits the chosen profile")
	_check(not _menu.input_active, "name field closes after creating")
	# Пробел в имени не печатается, чтобы не плодить невидимые дубли.
	_menu.call("_reload")
	_menu.call("_toggle_input")
	_menu.call("_unhandled_key_input", _key_event(" "))
	_menu.call("_cbuf_flush")
	_check(_menu.input_text == "", "space is not typed into the name field")
	for ch in "Петя":
		_menu.call("_unhandled_key_input", _key_event(ch))
	_menu.call("_cbuf_flush")
	_menu.call("_unhandled_key_input", _key(KEY_ENTER))
	_check(
		S.count_users() == users_before + 1,
		"re-entering an existing name makes no duplicate"
	)
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
	_menu.call("_cbuf_flush")
	_check(_menu.input_text == "a", "space in the name field is still ignored")
	_menu.input_active = false


## F2 открывает меню из игры, Esc в меню — гость, F2 из меню возвращает
## в игру с тем же игроком.
func _part9_main_game() -> void:
	S.set_last_user("Петя")
	var users_before: int = S.user_list().size()
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
	# Esc в меню — больше не гость, а выход (quit в тесте не зовём —
	# убьёт прогон). Гость — только кнопкой «Без профиля»: вся
	# проводка от тапа до сигнала chosen.
	_picked = ""
	menu.call("_input", _tap(menu.call("_guest_tap_rect").get_center()))
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
		menu.call("_cbuf_flush")
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
	_check(_main._exact(), "all_keys mode is case-sensitive")
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
	_check(not _main._exact(), "progression mode ignores case")
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
	_check("знаков в минуту" in _main.overlay_label.text, "modal shows pace in plain words")
	_check("CPM" not in _main.overlay_label.text, "no anglicism CPM on the modal")
	# Модалка упрощена: ни заголовка, ни «нажми Enter» — только звёзды,
	# скорость и ошибки.
	_check("Уровень" not in _main.overlay_label.text, "won modal has no header")
	_check("Enter" not in _main.overlay_label.text, "won modal has no enter hint")
	_check("★" in _main.overlay_label.text, "won modal keeps the stars")
	# Проигрыш — та же краткость, без «укололся».
	_main._new_level()
	_main._finish(false)
	_check("укололся" not in _main.overlay_label.text, "lost modal has no header")
	_check("Enter" not in _main.overlay_label.text, "lost modal has no enter hint")
	_check("знаков в минуту" in _main.overlay_label.text, "lost modal shows pace")
	_check("★" not in _main.overlay_label.text, "lost modal has no stars")
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
	_check(
		S.user_list().size() == users_before, "guest result creates no profile"
	)
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
	_menu.call("_cbuf_flush")
	_menu.call("_unhandled_key_input", _key(KEY_ENTER))
	_check(S.user_exists("Гри"), "profile created with checkbox on")
	_check(S.get_all_keys("Гри"), "pending flag moved into the profile")
	_check(not _menu.input_all_keys, "pending flag resets after creating")
	S.delete_user("Гри")
	_menu.call("_reload")
	# Компактная галка «Ё»: тап снимает строгость, флаг переезжает
	# в профиль и сбрасывается в строго. Список пуст — поле открыто.
	_menu.call("_input", _tap(_menu.call("_yocheck_tap_rect").get_center()))
	_check(not _menu.input_yo_strict, "yo checkbox disarms strictness")
	for ch in "Гоша":
		_menu.call("_unhandled_key_input", _key_event(ch))
	_menu.call("_cbuf_flush")
	_menu.call("_unhandled_key_input", _key(KEY_ENTER))
	_check(S.user_exists("Гоша"), "profile created with yo off")
	_check(not S.get_yo_strict("Гоша"), "pending yo flag moved into the profile")
	_check(_menu.input_yo_strict, "pending yo flag resets after creating")
	S.delete_user("Гоша")
	_menu.call("_reload")
	# Буквы печатаются сразу, без Tab.
	for ch in "Маша":
		_menu.call("_unhandled_key_input", _key_event(ch))
	_menu.call("_cbuf_flush")
	_check(String(_menu.input_text) == "Маша", "typing works without Tab")
	# Подсказки внизу больше нет (избыточна): кнопки и таблица говорят сами.
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
	_menu.call("_cbuf_flush")
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
	_menu.call("_cbuf_flush")
	_check(String(_menu.input_text) == "Ю", "soft letter typed")
	_menu.call("_unhandled_key_input", _softkey_event(8))
	_menu.call("_cbuf_flush")
	_check(String(_menu.input_text) == "", "unicode backspace erases")
	_picked = ""
	for ch in "Юра":
		_menu.call("_unhandled_key_input", _key_event(ch))
	_menu.call("_cbuf_flush")
	_menu.call("_unhandled_key_input", _softkey_event(13))
	_menu.call("_cbuf_flush")
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
	# Явные размеры: в headless-прогоне вьюпорт мусорный (64x64),
	# _relayout подхватывает его — как и остальные проверки ниже,
	# работаем от заданных величин, а не от окна.
	_menu.view_w = 1100.0
	_menu.view_h = 650.0
	_menu.k = 1.0
	root.size = Vector2i(1100, 650)
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
	# Галочка «Про» в строке: тап переключает флаг ЭТОГО профиля
	# и не играет им (picked пуст).
	_picked = ""
	_menu.call("_input", _tap(_menu.call("_pro_tap_rect", 0).get_center()))
	_check(S.get_all_keys(first), "pro checkbox turns all_keys on")
	_check(_picked == "", "pro tap does not play the profile")
	_menu.call("_input", _tap(_menu.call("_pro_tap_rect", 0).get_center()))
	_check(not S.get_all_keys(first), "pro checkbox turns all_keys off")
	# Галочка «Ё» в строке: тап переключает строгость ЭТОГО профиля.
	_check(S.get_yo_strict(first), "yo is strict by default")
	_menu.call("_input", _tap(_menu.call("_yo_tap_rect", 0).get_center()))
	_check(not S.get_yo_strict(first), "yo tap relaxes strictness")
	_check(_picked == "", "yo tap does not play the profile")
	_menu.call("_input", _tap(_menu.call("_yo_tap_rect", 0).get_center()))
	_check(S.get_yo_strict(first), "yo tap restores strictness")
	# Стрелки ←/→ выбирают колонку, пробел переключает её флаг.
	# Поле ввода гасим: иначе пробел — это ввод, а не переключатель.
	_menu.input_active = false
	_check(_menu.sel_col == 0, "flag column starts at pro")
	_menu.call("_unhandled_key_input", _key(KEY_RIGHT))
	_check(_menu.sel_col == 1, "right arrow moves to the yo column")
	_menu.call("_unhandled_key_input", _key(KEY_SPACE))
	_check(not S.get_yo_strict(first), "space toggles the yo flag")
	_menu.call("_unhandled_key_input", _key(KEY_LEFT))
	_check(_menu.sel_col == 0, "left arrow moves back to pro")
	_menu.call("_unhandled_key_input", _key(KEY_SPACE))
	_check(S.get_all_keys(first), "space toggles the pro flag")
	_menu.call("_unhandled_key_input", _key(KEY_SPACE))
	_check(not S.get_all_keys(first), "space toggles the pro flag back")
	# Тап по заголовку объясняет галку, повторный гасит.
	_menu.call("_input", _tap(_menu.call("_yo_head_rect").get_center()))
	_check(String(_menu.hint_header) == "yo", "yo header tap explains the flag")
	_menu.call("_input", _tap(_menu.call("_yo_head_rect").get_center()))
	_check(String(_menu.hint_header) == "", "yo header tap again hides it")
	_menu.call("_input", _tap(_menu.call("_pro_head_rect").get_center()))
	_check(String(_menu.hint_header) == "pro", "pro header tap explains the flag")
	_menu.call("_input", _tap(_menu.call("_pro_head_rect").get_center()))
	_check(String(_menu.hint_header) == "", "pro header tap again hides it")
	# Тап по второй строке играет вторым (галочки не мешают).
	_picked = ""
	_menu.call("_input", _tap(_menu.call("_row_tap_rect", 1).get_center()))
	_check(_picked == second, "tap on a row plays as that user")
	# Колонки таблицы: галочки обоих строк на одной вертикали.
	var p0 := Rect2(_menu.call("_pro_tap_rect", 0))
	var p1 := Rect2(_menu.call("_pro_tap_rect", 1))
	_check(
		absf(p0.get_center().x - p1.get_center().x) < 1.0,
		"pro column is aligned"
	)
	# Строки не налезают друг на друга и влезают в экран.
	var r0 := Rect2(_menu.call("_row_tap_rect", 0))
	var r1 := Rect2(_menu.call("_row_tap_rect", 1))
	_check(
		r1.position.y >= r0.position.y + r0.size.y - 1.0,
		"rows do not overlap"
	)
	_check(
		r1.position.y + r1.size.y <= _menu.view_h,
		"rows fit on screen"
	)
	# Узкий экран: блок опущен ниже альбомного, шапка на месте.
	_menu.view_w = 1100.0
	_menu.view_h = 650.0
	_menu.k = 1.0
	var y_land: float = _menu.call("_rows_top")
	_menu.view_w = 412.0
	_menu.view_h = 915.0
	_menu.k = 0.736
	_check(_menu.call("_rows_top") > y_land, "portrait block sits lower")
	# Длинное имя режется многоточием в ширину колонки, таблица цела.
	# Чистая функция текста и геометрии — профиль создавать не надо.
	var cut := String(_menu.call("_short_name", "Оченьдлинноеимя12"))
	_check(cut.ends_with("…"), "long name truncates with ellipsis")
	_check(
		_menu.call("_text_size", cut, 30).x <= 412.0,
		"truncated name fits the narrow screen"
	)
	_check(
		String(_menu.call("_short_name", first)) == first,
		"short name passes through"
	)
	# Геометрия блока: строки не налезают, кнопки под полем и на экране.
	# Отдельной галочки между строками и полем больше нет: «Про» живёт
	# в колонке таблицы, на пустом списке — компактной галочкой под полем.
	for case_vw in [1100.0, 412.0]:
		_menu.view_w = case_vw
		_menu.view_h = 915.0 if case_vw < 700.0 else 650.0
		_menu.k = 0.736 if case_vw < 700.0 else 1.0
		# Кнопки под полем не наезжают на поле и остаются на экране.
		var fld := Rect2(_menu.call("_field_tap_rect"))
		var btn := Rect2(_menu.call("_play_tap_rect"))
		_check(
			btn.position.y >= fld.position.y + fld.size.y - 1.0,
			"buttons sit below the field (vw=%.0f)" % case_vw
		)
		_check(
			btn.position.y + btn.size.y <= _menu.view_h,
			"buttons fit on screen (vw=%.0f)" % case_vw
		)
		# Со своей клавиатурой (поле активно) низ меню — не низ экрана:
		# кнопки обязаны влезть ВЫШЕ неё. Высоту ставит само меню
		# (своя политика показа), игра больше ничего не прокидывает.
		_menu.input_active = true
		# Без _relayout: он сбросит ручные view на вьюпорт 64x64.
		# k — формулой из _relayout, высота — из своей клавиатуры.
		_menu.k = clampf(minf(_menu.view_w / 1100.0, _menu.call("_menu_eff_h") / 650.0), 0.5, 2.5)
		var eff2: float = _menu.call("_menu_eff_h")
		var btn2 := Rect2(_menu.call("_play_tap_rect"))
		_check(
			btn2.position.y + btn2.size.y <= eff2 + 1.0,
			"buttons clear the keyboard (vw=%.0f)" % case_vw
		)
		_menu.input_active = false
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
	_menu.nmode = S.NIGHT_DAY
	# Кнопка крутит по кругу день → ночь → авто → день.
	_menu.call("_input", _tap(_menu.call("_night_tap_rect").get_center()))
	_check(_menu.night, "night button flips the mode on")
	_check(S.get_night_mode() == 1, "flip persists as night")
	_check(_menu.nmode == S.NIGHT_ON, "mode tracks night")
	_menu.call("_input", _tap(_menu.call("_night_tap_rect").get_center()))
	_check(S.get_night_mode() == -1, "second flip goes auto")
	_check(_menu.nmode == S.NIGHT_AUTO, "mode tracks auto")
	_menu.call("_input", _tap(_menu.call("_night_tap_rect").get_center()))
	_check(not _menu.night, "third flip returns to day")
	_check(S.get_night_mode() == 0, "day persists after the full circle")


## Самообновление: кнопка, состояния и модалка. Тап по кнопке шлёт
## настоящий запрос (асинхронный, тест его не ждёт), приёмники дёргаем
## напрямую. Чистые функции — в update_test.
func _part15_update() -> void:
	_menu.visible = true
	_menu.confirm_name = ""
	# Кнопка на экране, карточка влезает, Да/Нет не пересекаются.
	var ub := Rect2(_menu.call("_upd_button_rect"))
	_check(ub.position.x >= 0.0 and ub.end.x <= _menu.view_w, "update button fits")
	_menu._upd_tag = "v0.0.10"
	_menu._upd_notes = ["a", "b"] as Array[String]
	var card := Rect2(_menu.call("_upd_card_rect"))
	_check(
		card.position.x >= 0.0 and card.end.x <= _menu.view_w,
		"update card fits"
	)
	_check(
		card.position.y >= 0.0 and card.end.y <= _menu.view_h,
		"update card fits vertically"
	)
	var yes := Rect2(_menu.call("_upd_yes_rect"))
	var no := Rect2(_menu.call("_upd_no_rect"))
	_check(not yes.intersects(no), "update buttons do not overlap")
	_check(
		yes.position.y >= card.position.y and yes.end.y <= card.end.y,
		"update buttons sit inside the card"
	)
	# Тап по кнопке — проверка (сеть не трогаем: дальше вызываем
	# приёмники напрямую).
	_menu.call("_input", _tap(ub.get_center()))
	_check(String(_menu._upd_state) == "checking", "update tap starts checking")
	_check(String(_menu._upd_msg) != "", "checking shows a status")
	# Свежее — строкой, модалки нет.
	_menu.call("_on_upd_checked", false, "v0.0.9", "", "")
	_check(not bool(_menu._upd_open), "latest opens no modal")
	_check(String(_menu._upd_msg).find("последняя") >= 0, "latest says so")
	# Есть новее — модалка с тегом и заметками.
	_menu.call("_on_upd_checked", true, "v0.0.10", "a\nb", "http://x")
	_check(bool(_menu._upd_open), "available opens the modal")
	_check(String(_menu._upd_tag) == "v0.0.10", "modal carries the tag")
	# «Позже» гасит модалку.
	_menu.call("_input", _tap(yes.get_center()))
	_check(String(_menu._upd_state) == "error", "yes without URL fails loudly")
	_menu.call("_on_upd_checked", true, "v0.0.10", "a\nb", "http://x")
	_menu.call("_input", _tap(no.get_center()))
	_check(not bool(_menu._upd_open), "no button closes the modal")
	# Ошибка сети — строкой.
	_menu.call("_on_upd_failed", "нет сети")
	_check(String(_menu._upd_msg) == "нет сети", "error shows the reason")
	# Android-ветка (файл качает браузер): вместо молчания — инструкция,
	# иначе игрок ждёт установки, которая сама не запустится.
	_menu.call("_on_upd_downloaded", "")
	_check(
		String(_menu._upd_msg).find("Загрузк") >= 0,
		"browser download explains itself"
	)


## Composing-перепись IME в поле имени (та же беда, что в игре: Яндекс
## каждый тап стирает и вводит заново всё слово). Имя обязано собраться
## ровно из тапов, без дублей. После софт-событий — flush кадра.
## Телефонные минимумы под палец (жалоба автора 10.2026: мелко,
## не попасть). Кнопки действий и строки таблицы не ниже 64px высотой
## на телефоне; на десктопе — как было (геометрию не трогаем).
## Портрет с плотностью телефона: масштаб растёт через DPR, а блок
## влезает в экран (жалоба автора 10.2026: меню мелкое в вертикали).
## _relayout в headless не вызвать с нужным размером (он берёт размер
## вьюпорта), поэтому проверяем его части: Ui.dpr и _fit_k.
func _part23_portrait_dense() -> void:
	var was_dpr: float = Ui.dpr_override
	var saved_users: Array = _menu.users.duplicate()
	# Плотность: без переопределения в headless — 1, с ним — как скажут.
	Ui.dpr_override = 0.0
	_check(Ui.dpr() == 1.0, "density is 1 without an override")
	Ui.dpr_override = 2.6
	_check(Ui.dpr() == 2.6, "density override applies")
	# Хотим масштаб портрета 1080x2280: без плотности — 0.98, с ней — упор.
	_menu.view_w = 1080.0
	_menu.view_h = 2280.0
	_menu.top_safe = 0.0
	var u12: Array[String] = []
	for i in 12:
		u12.append("Ю%d" % i)
	_menu.users = u12
	_menu.k = 1.0
	var want_plain := minf(1080.0 / 1100.0, 2280.0 / 650.0)
	var want_dense := minf(want_plain * 2.6, 2.5)
	_check(want_dense > 2.0, "sanity: density grows the portrait scale")
	# Много строк: полный масштаб не влезает — _fit_k ужимает, но блок
	# остаётся на экране, а не уезжает.
	var k_full: float = _menu.call("_fit_k", 2.5, 0.7)
	_check(k_full < 2.5, "fit shrinks an overflowing portrait (k=%.2f)" % k_full)
	_menu.k = k_full
	var n: int = _menu.users.size()
	var last_y: float = _menu.call("_rows_top") + float(n - 1) * _menu.call("_row_step")
	_check(last_y <= _menu.view_h, "the last of 12 rows stays on screen")
	_check(Rect2(_menu.call("_play_tap_rect")).end.y <= _menu.view_h,
		"action buttons stay on screen after fit")
	# Мало строк: плотность даёт крупный масштаб без ужима.
	var u1: Array[String] = ["Ю"]
	_menu.users = u1
	var k_roomy: float = _menu.call("_fit_k", 2.5, 0.7)
	_check(k_roomy >= 2.0, "a short portrait keeps a big scale (k=%.2f)" % k_roomy)
	_menu.users = saved_users
	Ui.dpr_override = was_dpr


## Низ со скруглением: своя клавиатура поднимается на безопасный
## отступ, угловые клавиши не обрезаны (жалоба автора 10.2026).
func _part24_rounded_corners() -> void:
	var was_override: float = Ui.bottom_override
	_menu.view_w = 1080.0
	_menu.view_h = 2280.0
	Ui.bottom_override = 0.0
	var plain: Rect2 = Rect2(_menu.call("_own_rect"))
	Ui.bottom_override = 96.0
	var lifted: Rect2 = Rect2(_menu.call("_own_rect"))
	_check(
		is_equal_approx(plain.position.y - lifted.position.y, 96.0),
		"the keyboard rises above the rounded corners"
	)
	_check(
		lifted.end.y <= _menu.view_h - 96.0 + 0.001,
		"the keyboard bottom clears the unsafe strip"
	)
	_check(
		lifted.size == plain.size,
		"lifting does not resize the keys"
	)
	Ui.bottom_override = was_override


func _part16_touch_sizes() -> void:
	var was_desktop := Ui.is_desktop()
	Ui.force_touch = true
	_menu.view_w = 480.0
	_menu.view_h = 900.0
	_menu.call("_relayout")
	_check(_menu.call("_btn_h") >= 64.0, "action buttons fit a finger")
	_check(_menu.call("_row_step") >= 64.0, "table rows fit a finger")
	Ui.force_touch = was_desktop
	_menu.call("_relayout")


## Своя клавиатура в меню: слои, шифт, ввод (↵ создаёт профиль),
## долгое нажатие е→ё. Тапы — через _own_press/_own_release напрямую
## (как живые клики), без key-событий.
## Галка системной клавиатуры: тап по строке переключает флаг в сейве,
## своя клавиатура прячется/возвращается, релэут не падает.
func _part17_sys_keyboard() -> void:
	_menu.visible = true
	_menu.confirm_name = ""
	S.set_sys_kb(false)
	_menu.call("_input", _tap(Rect2(_menu.call("_syskb_tap_rect")).get_center()))
	_check(S.get_sys_kb(), "tap enables the system keyboard")
	_menu.input_active = true
	_menu.call("_relayout")
	_check(not _menu.call("_own_shown"), "system keyboard hides the own one")
	_menu.call("_input", _tap(Rect2(_menu.call("_syskb_tap_rect")).get_center()))
	_check(not S.get_sys_kb(), "tap disables it back")
	S.set_sys_kb(false)


## Кнопка «Лог»: открывает просмотр, тап листает, на последней закрывает.
## Размер кнопок на телефоне: палец должен попадать (жалоба автора
## 10.2026 — «Лог» в 31px у самого края, в чехле не нажать).
## На десктопе точных попаданий не нужно, там проверяем только то,
func _part18_touch_targets() -> void:
	_menu.visible = true
	_menu.confirm_name = ""
	_menu.view_w = 1100.0
	_menu.view_h = 650.0
	var was_touch: bool = Ui.force_touch
	Ui.force_touch = true
	_menu.k = 0.7
	_menu.top_safe = 0.0
	var min_side := 64.0
	var rects := {
		"обновления": Rect2(_menu.call("_upd_button_rect")),
	}
	for name in rects.keys():
		var r: Rect2 = rects[name]
		_check(r.size.x >= min_side and r.size.y >= min_side,
			"%s: не меньше 64px с обеих сторон (%.0fx%.0f)" % [name, r.size.x, r.size.y])
	_check(Rect2(_menu.call("_upd_button_rect")).position.x >= 22.0,
		"кнопка от края отодвинута для чехла")
	# Кнопки строк игроков: галочки и крестик — тоже пальцем.
	for i in maxi(_menu.users.size(), 1):
		var pro: Rect2 = Rect2(_menu.call("_pro_tap_rect", i - 1))
		var yo: Rect2 = Rect2(_menu.call("_yo_tap_rect", i - 1))
		var del: Rect2 = Rect2(_menu.call("_del_tap_rect", i - 1))
		_check(pro.size.x >= min_side and pro.size.y >= min_side,
			"галочка «Про» крупная (%.0fx%.0f)" % [pro.size.x, pro.size.y])
		_check(yo.size.x >= min_side and yo.size.y >= min_side,
			"галочка «Ё» крупная (%.0fx%.0f)" % [yo.size.x, yo.size.y])
		_check(del.size.x >= min_side and del.size.y >= min_side,
			"крестик крупный (%.0fx%.0f)" % [del.size.x, del.size.y])
		# Соседи не перехватывают тап друг друга.
		_check(not pro.intersects(yo) and not yo.intersects(del),
			"кнопки строки не перекрываются")
		if i > 0:
			break
	Ui.force_touch = was_touch
	_menu.k = 1.0


## Ввод в меню: клавиша печатает в поле, своя клавиатура — тоже.
func _part19_menu_typing() -> void:
	_menu.visible = true
	_menu.confirm_name = ""
	_menu.input_active = true
	_menu._upd_open = false
	_menu.view_w = 1100.0
	_menu.view_h = 650.0
	_menu.k = 1.0
	_menu.top_safe = 0.0
	_menu.input_text = ""
	_menu.set("_cbuf_active", false)
	_menu.call("_unhandled_key_input", _key_event("я"))
	_menu.call("_process", 0.016)
	_check(_menu.input_text == "я", "menu char reaches the field after the buffer flushes")
	var key_at := Vector2(-1.0, -1.0)
	for b in Kbd.buttons(
		Rect2(_menu.call("_own_rect")), _menu.kb_layer, _menu.kb_lang, _menu.kb_shift, true
	):
		if String(b["s"]).length() == 1:
			key_at = (b["r"] as Rect2).get_center()
			break
	_check(key_at.x > 0.0, "own keyboard has a letter key to tap")
	var text_before := String(_menu.input_text)
	_menu.call("_own_press", key_at)
	_check(String(_menu.input_text) != text_before or String(_menu.input_text).length() >= 1,
		"own keyboard types into the field")
	_menu.input_text = ""
	_menu.input_active = false


func _part20_upd_progress() -> void:
	_menu.visible = true
	_menu.confirm_name = ""
	_menu._upd_state = "downloading"
	_menu._upd_msg = "Качаю…"
	_menu._upd_pct = -1
	_menu._upd_done = 0
	_menu._upd_total = 0
	_menu.call("_on_upd_progress", 40 * 1048576, 100 * 1048576, 40)
	_check(int(_menu._upd_pct) == 40, "progress percent is kept")
	_check("40" in String(_menu._upd_msg), "progress is shown to the player")
	# Размер неизвестен (сервер не прислал Content-Length) — процент -1,
	# показываем мегабайты, а не «0%».
	_menu.call("_on_upd_progress", 12 * 1048576, 0, -1)
	_check(int(_menu._upd_pct) < 0, "unknown size means no percent")
	_check("12" in String(_menu._upd_msg), "unknown size shows megabytes")
	# Повторное «Загрузить» во время закачки: ветка «уже качаю» включается
	# по _upd.downloading(). Само «идёт закачка» в headless не
	# воспроизвести (нужен живой HTTPRequest), поэтому здесь проверяем
	# вторую половину: при отсутствии файла нажатие честно сообщает об
	# ошибке, а не зависает в состоянии «качаю».
	_menu._upd_state = "downloading"
	_menu.call("_upd_yes")
	_check(
		String(_menu._upd_state) != "downloading",
		"a download with nothing to fetch reports an error instead of hanging"
	)
	_menu._upd_state = ""
	_menu._upd_msg = ""
	_menu._upd_pct = -1
	_menu._upd_done = 0
	_menu._upd_total = 0
	_menu._upd_poll = 0.0


func _part21_own_keyboard() -> void:
	_menu.visible = true
	_menu.confirm_name = ""
	_menu.input_text = ""
	if not bool(_menu.input_active):
		_menu.call("_toggle_input")
	Ui.force_touch = true
	_menu.view_w = 1100.0
	_menu.view_h = 650.0
	_menu.kb_layer = "ru"
	_menu.kb_lang = "ru"
	var area: Rect2 = _menu.call("_own_rect")
	_check(area.size.y > 0.0, "menu keyboard has height")
	# Шифт + буква: заглавная в имени.
	_menu.call("_own_press", _mkey(area, "ru", false, "⇧"))
	_menu.call("_own_press", _mkey(area, "ru", true, "П"))
	_check(String(_menu.input_text) == "П", "shift gives uppercase")
	# Слой знаков и обратно.
	_menu.call("_own_press", _mkey(area, "ru", false, "?123"))
	_check(String(_menu.kb_layer) == "sym", "menu switches to symbols")
	_menu.call("_own_press", _mkey(area, "sym", false, "РУ"))
	_check(String(_menu.kb_layer) == "ru", "symbols return to russian")
	_menu.call("_own_press", _mkey(area, "ru", false, "глобус"))
	_check(String(_menu.kb_layer) == "en", "globe switches to latin")
	_menu.call("_own_press", _mkey(area, "en", false, "глобус"))
	_check(String(_menu.kb_layer) == "ru", "globe switches back to russian")
	# Долгое е→ё.
	_menu.call("_own_press", _mkey(area, "ru", false, "е"))
	_menu._lp_t0 = Time.get_ticks_msec() - 600
	_menu.call("_own_release", _mkey(area, "ru", false, "е"))
	_check(String(_menu.input_text) == "Пё", "long press gives yo")
	# Ввод (↵) создаёт профиль и закрывает поле.
	_menu.call("_own_press", _mkey(area, "ru", false, "↵"))
	_check(S.user_exists("Пё"), "enter key creates the profile")
	_check(not bool(_menu.input_active), "enter key closes the field")
	S.delete_user("Пё")
	Ui.force_touch = false


func _part22_compose_name() -> void:
	_menu.visible = true
	_menu.confirm_name = ""
	_menu.input_text = ""
	if not bool(_menu.input_active):
		_menu.call("_toggle_input")
	var taps := ""
	for ch in "Мама":
		taps += ch
		for _j in taps.length() - 1:
			_menu.call("_unhandled_key_input", _unknown_event(8))
		for j in taps.length():
			_menu.call("_unhandled_key_input", _unknown_event(taps.unicode_at(j)))
		_menu.call("_cbuf_flush")
	_check(String(_menu.input_text) == "Мама", "compose spells the name once (got «%s»)" % _menu.input_text)
	# Ручное стирание + новая буква одним махом (без flush между — так IME
	# шлёт пачку): одиночка — не переписка, стёртое не воскресает.
	# Ловит снятие порога «схлопываются только серии из 2+ символов».
	_menu.call("_unhandled_key_input", _unknown_event(8))
	_menu.call("_unhandled_key_input", _unknown_event("б".unicode_at(0)))
	_menu.call("_cbuf_flush")
	_check(String(_menu.input_text) == "Мамб", "erased letter stays erased (got «%s»)" % _menu.input_text)


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


## Событие системной клавиатуры со словарём: keycode неизвестен
## (Яндекс — KEY_UNKNOWN, Gboard — KEY_NONE), только unicode.
func _unknown_event(code: int) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = KEY_UNKNOWN
	ev.unicode = code
	ev.pressed = true
	return ev


## Клик мыши с координатами. Палец на Android сам превращается в клик,
## поэтому касания отдельно не тестируем: обработчик их не слушает.
## Центр клавиши своей клавиатуры в меню (для прямых тапов).
func _mkey(area: Rect2, layer: String, shift: bool, label: String) -> Vector2:
	for b in K.buttons(area, layer, "ru", shift, true):
		if String(b["s"]) == label:
			return (b["r"] as Rect2).get_center()
	return Vector2(-1.0, -1.0)


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
