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
	_part25_corrupt_file()
	_part26_update_modal_keys()
	_part28_cards()
	_part29_card_scroll()
	_part30_bunny_strip()
	_part31_menu_no_overlap()
	_part32_pre_ready_geometry()
	_part33_tap_and_bunny()
	_part34_menu_bounds()
	_part27_menu_chaos()
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
	# Явный размер: в headless вьюпорт 64x64, строки уезжают за окно
	# списка, и тапы по ним не доходят — маска режет их, как и на экране.
	_menu.view_w = 1100.0
	_menu.view_h = 650.0
	_menu.top_safe = 0.0
	_menu.k = 1.0
	_menu.call("_reload")
	_menu.sel = 0
	var n: int = _menu.users.size()
	_check(n == 2, "menu lists users after deletes")
	_menu.call("_nav", -1)
	_menu.call("_nav", 1)
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
	_end_edit(_menu)
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
	_end_edit(_menu)
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
	# Строка обязана быть в окне: тап за окном список игнорирует (как глаз
	# — маска), поэтому сначала крутим к выбранному, как стрелки.
	_menu.call("_scroll_to_sel")

	var del_r := Rect2(_menu.call("_del_tap_rect", ti))
	_menu_tap(del_r.get_center())
	_check(
		String(_menu.confirm_name) == "Снос3",
		"cross tap arms the confirm (%s)" % str(_menu.confirm_name)
	)
	_picked = ""
	_menu_tap(_menu.call("_row_tap_rect", ti).get_center())
	_check(
		_picked == "", "row tap is swallowed while confirming"
	)
	_check(
		_menu.users.has("Снос3"), "row tap while confirming deletes nothing"
	)
	_menu_tap(_menu.call("_confirm_no_rect").get_center())
	_check(_menu.users.has("Снос3"), "No button keeps the user")
	_menu_tap(_menu.call("_del_tap_rect", ti).get_center())
	_menu_tap(_menu.call("_confirm_yes_rect").get_center())
	_check(not _menu.users.has("Снос3"), "Yes button removes the user")
	_check(
		_menu.users.size() == n, "temp profiles are gone, list is intact"
	)


## Поле ввода: Tab, набор, Backspace, Enter создаёт, Enter с готовым
## именем просто входит.
func _part7_edit_name() -> void:
	_menu.call("_reload")
	var users_before: int = S.count_users()
	_menu.call("_start_edit", _menu.users.size())
	_check(_menu.input_active, "tab opens the name field")
	for ch in "Петя":
		_menu.call("_unhandled_key_input", _key_event(ch))
	_check(_menu.input_text == "Петя", "typing appends to the name field")
	_menu.call("_unhandled_key_input", _key(KEY_BACKSPACE))
	_check(_menu.input_text == "Пет", "backspace erases one char")
	_menu.call("_unhandled_key_input", _key_event("я"))
	_check(_menu.input_text == "Петя", "typing continues after backspace")
	_picked = ""
	if not _menu.chosen.is_connected(_on_chosen):
		_menu.chosen.connect(_on_chosen)
	_menu.call("_unhandled_key_input", _key(KEY_ENTER))
	_check(S.user_exists("Петя"), "enter creates the typed profile")
	_check(_picked == "", "creating a profile does not start the game")
	_check(not _menu.input_active, "name field closes after creating")
	# Пробел в имени не печатается, чтобы не плодить невидимые дубли.
	_menu.call("_reload")
	_menu.call("_start_edit", _menu.users.size())
	_menu.call("_unhandled_key_input", _key_event(" "))
	_check(_menu.input_text == "", "space is not typed into the name field")
	for ch in "Петя":
		_menu.call("_unhandled_key_input", _key_event(ch))
	_menu.call("_unhandled_key_input", _key(KEY_ENTER))
	_check(
		S.count_users() == users_before + 1,
		"re-entering an existing name makes no duplicate"
	)
	_check(_picked == "", "an existing name is not created again")
	_check(bool(_menu.input_active), "a taken name keeps the field open")
	_menu.call("_cancel_edit")


## Клавиша A в меню переключает взрослый режим, но только когда поле
## ввода неактивно (иначе это буква в имени).
func _part8_all_keys_key() -> void:
	_menu.call("_reload")
	_menu.sel = 0
	var who := String(_menu.users[0])
	_check(
		not S.get_all_keys(who), "menu target starts with all_keys off"
	)
	_end_edit(_menu)
	_menu.call("_unhandled_key_input", _key(KEY_A))
	_check(S.get_all_keys(who), "A turns all_keys on in the menu")
	_menu.call("_unhandled_key_input", _key(KEY_A))
	_check(not S.get_all_keys(who), "A turns all_keys off in the menu")
	# При активном поле ввода клавиша A — это буква, а не переключатель
	# режима. Событие полное: и keycode, и unicode, как от живой клавиатуры.
	_menu.call("_start_edit", _menu.users.size())
	_menu.input_text = ""
	_menu.call("_unhandled_key_input", _typed_key(KEY_A, "a"))
	_check(_menu.input_text == "a", "A types a letter while the field is active")
	_check(
		not S.get_all_keys(who), "A in the name field does not toggle all_keys"
	)
	_menu.call("_unhandled_key_input", _key_event(" "))
	_check(_menu.input_text == "a", "space in the name field is still ignored")
	_end_edit(_menu)


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
	_end_edit(menu)
	# Esc в меню — больше не гость, а выход (quit в тесте не зовём —
	# убьёт прогон). Гость — только кнопкой «Без профиля»: вся
	# проводка от тапа до сигнала chosen.
	_picked = ""
	var gpos: Vector2 = menu.call("_guest_tap_rect").get_center()

	menu.call("_input", _tap(gpos))
	menu.call("_input", _release(gpos))

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
	_end_edit(menu)
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
	_end_edit(menu)
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
	menu.call("_start_edit", menu.users.size())
	for ch in "абвгдеёжзийклмнопрст":
		menu.call("_unhandled_key_input", _key_event(ch))
	_check(
		String(menu.input_text).length() == S.MAX_NAME_LENGTH,
		"the name field stops at the max length"
	)
	_end_edit(menu)
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
	# Звёзды — крупно на самом игровом поле, а не в модалке (автор
	# 15.10.2026): в модалке они лезли на текст.
	_check("★" not in _main.overlay_label.text, "won modal has no stars inside")
	_check(
		"★" in _main.stars_label.text and _main.stars_label.visible,
		"won stars live big on the field"
	)
	var star_fs: int = _main._star_fs
	_check(
		star_fs > _main._over_fs,
		"field stars are bigger than the modal font (%d > %d)" % [star_fs, _main._over_fs]
	)
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
	_menu_tap(_menu.call("_pro_tap_rect", _menu.users.size()).get_center())
	_check(_menu.input_all_keys, "checkbox arms the typed name")
	for ch in "Гри":
		_menu.call("_unhandled_key_input", _key_event(ch))
	_menu.call("_unhandled_key_input", _key(KEY_ENTER))
	_check(S.user_exists("Гри"), "profile created with checkbox on")
	_check(S.get_all_keys("Гри"), "pending flag moved into the profile")
	_check(not _menu.input_all_keys, "pending flag resets after creating")
	S.delete_user("Гри")
	_menu.call("_reload")
	# Компактная галка «Ё»: тап снимает строгость, флаг переезжает
	# в профиль и сбрасывается в строго. Список пуст — поле открыто.
	_menu_tap(_menu.call("_yo_tap_rect", _menu.users.size()).get_center())
	_check(not _menu.input_yo_strict, "yo checkbox disarms strictness")
	for ch in "Гоша":
		_menu.call("_unhandled_key_input", _key_event(ch))
	_menu.call("_unhandled_key_input", _key(KEY_ENTER))
	_check(S.user_exists("Гоша"), "profile created with yo off")
	_check(not S.get_yo_strict("Гоша"), "pending yo flag moved into the profile")
	_check(_menu.input_yo_strict, "pending yo flag resets after creating")
	S.delete_user("Гоша")
	_menu.call("_reload")
	# Буквы печатаются сразу, без Tab.
	for ch in "Маша":
		_menu.call("_unhandled_key_input", _key_event(ch))
	_check(String(_menu.input_text) == "Маша", "typing works without Tab")
	# Подсказки внизу больше нет (избыточна): кнопки и таблица говорят сами.
	# Enter с набранным именем создаёт профиль из автооткрытого поля.
	# Приёмник chosen подключён ещё в седьмой части, второй раз не надо:
	# в Godot 4 повторный connect того же вызова — ошибка.
	_picked = ""
	_menu.call("_unhandled_key_input", _key(KEY_ENTER))
	_check(S.user_exists("Маша"), "enter creates the profile from the open field")
	_check(_picked == "", "creating from the open field does not start the game")
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
	_end_edit(_menu)
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
	_check(_picked == "", "unicode enter does not start the game either")
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
	_end_edit(_menu)
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
	_menu_tap(_menu.call("_row_tap_rect", 1).get_center())
	_check(_picked == second, "a single tap plays as that user")
	_menu_double_tap(_menu.call("_row_tap_rect", 1).get_center())
	_check(_picked == second, "a double tap plays as that user")
	_menu_tap(_menu.call("_new_tap_rect").get_center())
	_check(_menu.input_active, "tap on new player opens input")
	_menu.call("_cancel_edit")
	_picked = ""
	_menu_tap(_menu.call("_guest_tap_rect").get_center())
	_check(_picked == S.GUEST, "guest button enters as guest")
	_menu.sel = 0
	_picked = ""
	_menu_double_tap(_menu.call("_row_tap_rect", 0).get_center())
	_check(_picked == first, "a double tap enters the selected profile")
	# Галочка «Про» в строке: тап переключает флаг ЭТОГО профиля
	# и не играет им (picked пуст).
	_picked = ""
	_menu_tap(_menu.call("_pro_tap_rect", 0).get_center())
	_check(S.get_all_keys(first), "pro checkbox turns all_keys on")
	_check(_picked == "", "pro tap does not play the profile")
	_menu_tap(_menu.call("_pro_tap_rect", 0).get_center())
	_check(not S.get_all_keys(first), "pro checkbox turns all_keys off")
	# Галочка «Ё» в строке: тап переключает строгость ЭТОГО профиля.
	_check(S.get_yo_strict(first), "yo is strict by default")
	_menu_tap(_menu.call("_yo_tap_rect", 0).get_center())
	_check(not S.get_yo_strict(first), "yo tap relaxes strictness")
	_check(_picked == "", "yo tap does not play the profile")
	_menu_tap(_menu.call("_yo_tap_rect", 0).get_center())
	_check(S.get_yo_strict(first), "yo tap restores strictness")
	# Стрелки ←/→ выбирают колонку, пробел переключает её флаг.
	# Поле ввода гасим: иначе пробел — это ввод, а не переключатель.
	_end_edit(_menu)
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
	_menu_tap(_menu.call("_yo_head_rect").get_center())
	_check(String(_menu.hint_header) == "yo", "yo header tap explains the flag")
	_menu_tap(_menu.call("_yo_head_rect").get_center())
	_check(String(_menu.hint_header) == "", "yo header tap again hides it")
	_menu_tap(_menu.call("_pro_head_rect").get_center())
	_check(String(_menu.hint_header) == "pro", "pro header tap explains the flag")
	_menu_tap(_menu.call("_pro_head_rect").get_center())
	_check(String(_menu.hint_header) == "", "pro header tap again hides it")
	# Дабл-клик по второй строке играет вторым (галочки не мешают).
	_picked = ""
	_menu_double_tap(_menu.call("_row_tap_rect", 1).get_center())
	_check(_picked == second, "a double tap on a row plays as that user")
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
	# Портрет: список занимает ВСЮ середину экрана — от шапки до поля
	# ввода. Прежде блок «опускался» и оставлял дыру снизу (жалоба
	# автора 10.2026), теперь растягивается на окно.
	var view_p := Rect2(_menu.call("_list_rect"))
	# Зазор до ряда кнопок РОВНО 20k (_buttons_y ставит их под списком), и
	# на равных величинах решает float — берём допуск в пиксель. Раньше
	# кнопки были ниже и зазор выходил больше, строгое сравнение проходило;
	# после роста кнопок под палец (автор 16.10.2026) величины сравнялись.
	_check(
		view_p.end.y <= float(_menu.call("_buttons_y")) - 20.0 * _menu.k + 1.0,
		"the portrait list ends above the buttons"
	)
	_check(
		view_p.position.y >= float(_menu.call("_rows_top")) - 1.0,
		"the portrait list starts under the header"
	)
	_check(
		view_p.size.y > 160.0,
		"the portrait list is taller than the header, not a strip"
	)
	# Длинное имя и ширина. Геометрия чистая: профиль создавать не надо,
	# меряем только текст и прямоугольники.
	#   — таблица (узкий альбом) режет имя многоточием;
	#   — карточка (портрет) держит даже самое длинное имя, какое игра
	#     вообще может создать (жалоба автора 10.2026: в портрете имя
	#     уходило в многоточие из двух букв, колонок было шесть).
	_menu.view_w = 700.0
	_menu.view_h = 500.0
	_menu.k = 1.0
	var cut := String(_menu.call("_short_name", "Оченьдлинноеимя12"))
	_check(cut.ends_with("…"), "long name truncates with ellipsis")
	_check(
		_menu.call("_text_size", cut, 30).x <= 700.0,
		"truncated name fits the narrow screen"
	)
	_check(
		String(_menu.call("_short_name", first)) == first,
		"short name passes through"
	)
	_menu.view_w = 412.0
	_menu.view_h = 915.0
	_menu.k = 0.736
	var whole := String(_menu.call("_short_name", "Оченьдлинноеимя12"))
	_check(
		whole == "Оченьдлинноеимя12",
		"the card keeps a long name whole (got «%s»)" % whole
	)
	_check(
		_menu.call("_text_size", whole, 30).x <= 412.0,
		"the card keeps it inside the screen"
	)
	# Геометрия блока: строки не налезают, кнопки под полем и на экране.
	# Отдельной галочки между строками и полем больше нет: «Про» живёт
	# в колонке таблицы, на пустом списке — компактной галочкой под полем.
	for case_vw in [1100.0, 412.0]:
		_menu.view_w = case_vw
		_menu.view_h = 915.0 if case_vw < 700.0 else 650.0
		_menu.k = 0.736 if case_vw < 700.0 else 1.0
		# Ряд кнопок на экране и под списком.
		var view_here := Rect2(_menu.call("_list_rect"))
		var btn := Rect2(_menu.call("_btn_row"))
		_check(
			btn.position.y >= view_here.end.y - 1.0,
			"buttons sit below the list (vw=%.0f)" % case_vw
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
		var btn2 := Rect2(_menu.call("_btn_row"))
		_check(
			btn2.position.y + btn2.size.y <= eff2 + 1.0,
			"buttons clear the keyboard (vw=%.0f)" % case_vw
		)
		_end_edit(_menu)
	# Скрытое меню тычков не видит.
	_menu.visible = false
	_picked = ""
	_menu_tap(_menu.call("_row_tap_rect", 0).get_center())
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
	_menu_tap(_menu.call("_night_tap_rect").get_center())
	_check(_menu.night, "night button flips the mode on")
	_check(S.get_night_mode() == 1, "flip persists as night")
	_check(_menu.nmode == S.NIGHT_ON, "mode tracks night")
	_menu_tap(_menu.call("_night_tap_rect").get_center())
	_check(S.get_night_mode() == -1, "second flip goes auto")
	_check(_menu.nmode == S.NIGHT_AUTO, "mode tracks auto")
	_menu_tap(_menu.call("_night_tap_rect").get_center())
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
	_menu_tap(ub.get_center())
	_check(String(_menu._upd_state) == "checking", "update tap starts checking")
	_check(String(_menu.call("_upd_label")) != "", "checking shows a status")
	# Свежее — строкой, модалки нет.
	_menu.call("_on_upd_checked", false, "v0.0.9", "", "")
	_check(not bool(_menu._upd_open), "latest opens no modal")
	_check(
		String(_menu.call("_upd_label")).find("Обновлений нет") >= 0,
		"latest says so (got «%s»)" % _menu.call("_upd_label")
	)
	# Есть новее — модалка с тегом и заметками.
	_menu.call("_on_upd_checked", true, "v0.0.10", "a\nb", "http://x")
	_check(bool(_menu._upd_open), "available opens the modal")
	_check(String(_menu._upd_tag) == "v0.0.10", "modal carries the tag")
	# «Позже» гасит модалку.
	_menu_tap(yes.get_center())
	_check(String(_menu._upd_state) == "error", "yes without URL fails loudly")
	_menu.call("_on_upd_checked", true, "v0.0.10", "a\nb", "http://x")
	_menu_tap(no.get_center())
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
	# Много игроков: масштаб НЕ ужимается — список листается. Раньше
	# двенадцать карточек ужимали весь интерфейс до нечитаемого (жалоба
	# автора 10.2026: в портрете всё мелкое), теперь интерфейс крупный,
	# а лишнее листается пальцем.
	var k_full: float = _menu.call("_fit_k", 2.5, 0.7)
	_check(
		k_full >= 2.0,
		"a crowded portrait keeps the big scale (k=%.2f)" % k_full
	)
	_menu.k = k_full
	var n: int = _menu.users.size()
	var step: float = _menu.call("_row_step")
	var card_h: float = _menu.call("_card_h")
	var list_h: float = Rect2(_menu.call("_list_rect")).size.y
	_check(
		float(_menu.call("_list_max_scroll")) >= float(n - 1) * step + card_h - list_h,
		"the twelfth player is reachable by scrolling"
	)
	_check(
		Rect2(_menu.call("_btn_row")).end.y <= _menu.view_h,
		"action buttons stay on screen with twelve players"
	)
	# Карточка не мельчает от числа игроков: при десяти и при трёх
	# высота почти одна (иначе список снова станет нечитаемым).
	_menu.users = u12
	var h12: float = _menu.call("_card_h")
	var u3: Array[String] = ["Ю1", "Ю2", "Ю3"]
	_menu.users = u3
	var h3: float = _menu.call("_card_h")
	_check(
		h3 <= h12 * 1.35,
		"cards grow with free space, not with the player count (%.0f vs %.0f)" % [h3, h12]
	)
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
## свои клавиши ё/ъ. Тапы — через _own_press напрямую (как живые клики),
## без key-событий.
## Галка системной клавиатуры УБРАНА из игры: ввод — только своей
## экранной клавиатурой (решение 10.2026, жалобы на сбитый курсор).
## Остатки мёртвого флага в старых профилях вычищает drop_legacy_guest:
## проверяем, что он за собой убирает, а чтение файла в кадре не идёт.
func _part17_sys_keyboard() -> void:
	_menu.visible = true
	_menu.confirm_name = ""
	# Мёртвый флаг в сейве — чистится при старте (не лежит годами).
	var cfg := ConfigFile.new()
	cfg.load(S.PATH)
	cfg.set_value("display", "sys_kb", true)
	cfg.save(S.PATH)
	S.invalidate()  # файл правили руками — кэш разбора протух
	S.drop_legacy_guest()
	var after := ConfigFile.new()
	after.load(S.PATH)
	_check(
		not after.has_section_key("display", "sys_kb"),
		"the dead system-keyboard flag is cleaned from old saves"
	)
	# Своя клавиатура меню рисуется при вводе имени и работает без
	# системной галки.
	_menu.input_active = true
	_menu.call("_relayout")
	_check(_menu.call("_own_shown"), "the own keyboard shows while typing a name")
	# Профиль читается на старте уровня, а не на каждом кадре: счётчик
	# чтений файла не растёт просто от тишины.
	_end_edit(_menu)
	_menu.call("_relayout")


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
	_menu.call("_unhandled_key_input", _key_event("я"))
	_check(_menu.input_text == "я", "menu char reaches the field at once")
	var key_at := Vector2(-1.0, -1.0)
	for b in Kbd.buttons(
		Rect2(_menu.call("_own_rect")), _menu.kb_shift, true
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
	# Доска меню следует за раскладкой системы по пришедшей букве, а не
	# по сочетанию клавиш: переключатель у человека какой угодно
	# (требование автора 10.2026).
	_menu.kb_lang = "ru"
	_menu.input_active = true
	_menu.call("_unhandled_key_input", _key_event("b"))
	_check(String(_menu.kb_lang) == "en", "a latin key switches the menu board")
	_check(float(_menu.kb_morph) < 1.0, "and starts the legend morph")
	_menu.call("_unhandled_key_input", _key_event("б"))
	_check(String(_menu.kb_lang) == "ru", "a cyrillic key brings it back")
	_menu.input_text = ""
	_end_edit(_menu)


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
	_check("40" in String(_menu.call("_upd_label")), "progress is shown to the player")
	# Размер неизвестен (сервер не прислал Content-Length) — процент -1,
	# показываем мегабайты, а не «0%».
	_menu.call("_on_upd_progress", 12 * 1048576, 0, -1)
	_check(int(_menu._upd_pct) < 0, "unknown size means no percent")
	_check(
		String(_menu.call("_upd_label")).find("%") < 0,
		"unknown size shows no percent (got «%s»)" % _menu.call("_upd_label")
	)
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
		_menu.call("_start_edit", _menu.users.size())
	Ui.force_touch = true
	_menu.view_w = 1100.0
	_menu.view_h = 650.0
	_menu.kb_lang = "ru"
	var area: Rect2 = _menu.call("_own_rect")
	_check(area.size.y > 0.0, "menu keyboard has height")
	# Шифт + буква: заглавная в имени.
	_menu.call("_own_press", _mkey(area, false, "Shift"))
	_check(bool(_menu.kb_shift), "left shift arms")
	# Клавиша не переименовывается при шифте (тождество стабильно), ищем
	# по основе, регистр проверяем через press_out.
	_menu.call("_own_press", _mkey(area, true, "п"))
	_check(
		String(K.press_out("п", String(_menu.kb_lang), true)) == "П"
			and String(_menu.input_text) == "П",
		"shift gives uppercase (got «%s»)" % _menu.input_text
	)
	# Глобус туда-обратно (слоя знаков больше нет).
	_menu.call("_own_press", _mkey(area, false, "глобус"))
	_check(String(_menu.kb_lang) == "en", "globe switches to latin")
	# Глобус реально меняет язык ввода: та же клавиша «ф» даёт «a».
	# Ряды при этом не меняются (доска одна) — синонимичные действия.
	_menu.call("_own_press", _mkey(area, false, "ф"))
	_check(String(_menu.input_text) == "Пa", "latin input types latin (got «%s»)" % _menu.input_text)
	_menu.call("_own_press", _mkey(area, false, "глобус"))
	_check(String(_menu.kb_lang) == "ru", "globe switches back to russian")
	# Латинскую «a» стираем: дальше имя по-русски.
	_menu.call("_own_press", _mkey(area, false, "←"))
	_check(String(_menu.input_text) == "П", "erase removes the latin letter")
	# Своя клавиша ё (как на настоящей клавиатуре).
	_menu.call("_own_press", _mkey(area, false, "ё"))
	_check(String(_menu.input_text) == "Пё", "own yo key types yo")
	# Ввод (↵) создаёт профиль и закрывает поле.
	_menu.call("_own_press", _mkey(area, false, "↵"))
	_check(S.user_exists("Пё"), "enter key creates the profile")
	_check(not bool(_menu.input_active), "enter key closes the field")
	S.delete_user("Пё")
	Ui.force_touch = false


func _part22_compose_name() -> void:
	# Прямой ввод в поле имени: клавиша без кода — как даёт своя экранная
	# клавиатура. Буквы вводятся по одной, стирание урезает имя.
	_menu.visible = true
	_menu.confirm_name = ""
	_menu.input_text = ""
	if not bool(_menu.input_active):
		_menu.call("_start_edit", _menu.users.size())
	for ch in "Мама":
		_menu.call("_unhandled_key_input", _unknown_event(ch.unicode_at(0)))
	_check(String(_menu.input_text) == "Мама", "the name spells once (got «%s»)" % _menu.input_text)
	# Ручное стирание + новая буква: стёртое не воскресает.
	_menu.call("_unhandled_key_input", _unknown_event(8))
	_menu.call("_unhandled_key_input", _unknown_event("б".unicode_at(0)))
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


## Модификаторное событие как от настоящей клавиатуры (Ctrl+Shift,
## Alt+Shift — так в Windows переключают язык ввода).
func _mod(code: int, ctrl: bool, alt: bool) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.ctrl_pressed = ctrl
	ev.alt_pressed = alt
	ev.shift_pressed = ctrl or alt
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


## Клавиша без кода: чистый символ, как даёт своя экранная клавиатура.
func _unknown_event(code: int) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = KEY_UNKNOWN
	ev.unicode = code
	ev.pressed = true
	return ev


## Клик мыши с координатами. Палец на Android сам превращается в клик,
## поэтому касания отдельно не тестируем: обработчик их не слушает.
## Центр клавиши своей клавиатуры в меню (для прямых тапов).
func _mkey(area: Rect2, shift: bool, label: String) -> Vector2:
	for b in K.buttons(area, shift, true):
		if String(b["s"]) == label:
			return (b["r"] as Rect2).get_center()
	return Vector2(-1.0, -1.0)


func _tap(pos: Vector2) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = pos
	return ev


## Полный тап: нажатие и отпускание. По листаемому списку меню ждёт
## отпускания (иначе жест прокрутки успевал бы выбрать игрока), поэтому
## одним нажатием тап больше не проходит.
## Дабл-клик по строке — играть (автор 16.10.2026: одинарный тап только
## выделяет). Событие то же, что у пальца, но с двойным флагом.
## Догнать цель прокрутки: список едет плавно (18/с), а в headless
## кадров нет — крутим _process меню, пока факт не сравнялся с целью.
func _settle_scroll() -> void:
	for _i in 300:
		_menu.call("_process", 1.0 / 60.0)
		if absf(_menu._scroll - _menu._scroll_target) < 0.5:
			return


## Закрыть правку имени. Именно поля, а не только input_active: строка
## создания живёт в editing, и при editing >= 0 любая проверка тапа идёт
## в правку, а не в список (ловилось на каскаде 16.10.2026). Без
## _cancel_edit намеренно: тот зовёт _relayout, а он перечитывает
## размер вьюпорта (64x64 в headless) и сбивает ручные view.
func _end_edit(m: Node) -> void:
	m.editing = -1
	m.editing_new = false
	m.input_text = ""
	m.input_active = false


func _menu_double_tap(pos: Vector2) -> void:
	_menu.call("_input", _double(pos))


func _double(pos: Vector2) -> InputEventMouseButton:
	var mb := _tap(pos)
	mb.double_click = true
	return mb


func _menu_tap(pos: Vector2) -> void:
	_menu.call("_input", _tap(pos))
	_menu.call("_input", _release(pos))


func _release(pos: Vector2) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = false
	ev.position = pos
	return ev


## Движение пальца с зажатой левой кнопкой — так приходит прокрутка.
func _motion(from: Vector2, to: Vector2) -> InputEventMouseMotion:
	var ev := InputEventMouseMotion.new()
	ev.position = to
	ev.relative = to - from
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT
	return ev


func _wheel(pos: Vector2, up: bool) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN
	ev.pressed = true
	ev.position = pos
	return ev


## Прокрутка списка игроков в портрете: карточек много, окно одно —
## листается пальцем (автор 10.2026: в портрете либо всё мелкое, либо
## половина игроков не влезает). Проверяем числами: на сколько уехал
## список, чем он зажат, и что тап после жеста игрока не выбирает.
func _part29_card_scroll() -> void:
	var was_touch := Ui.force_touch
	Ui.force_touch = true
	var saved_users: Array = _menu.users.duplicate()
	_menu.users = saved_users.duplicate()
	_menu.visible = true
	_menu.confirm_name = ""
	_menu.hint_header = ""
	_end_edit(_menu)
	_menu.view_w = 1080.0
	_menu.view_h = 1900.0
	_menu.top_safe = 0.0
	_menu.k = _menu.call("_fit_k", 2.5, 0.7)
	var many: Array[String] = []
	for i in 12:
		many.append("Пок%d" % i)
	_menu.users = many
	_menu._scroll = 0.0
	var view := Rect2(_menu.call("_list_rect"))
	var max_scroll: float = _menu.call("_list_max_scroll")
	_check(max_scroll > 0.0, "twelve cards do not fit and scroll")
	_check(
		Rect2(_menu.call("_card_rect", 0)).position.y >= view.position.y - 1.0,
		"the first card starts at the top of the window"
	)
	# Палец вверх на 240px — список вниз на 240 (список едет за пальцем).
	var at := view.get_center()
	_menu.call("_input", _tap(at))
	_menu.call("_input", _motion(at, at - Vector2(0.0, 240.0)))
	_check(
		absf(_menu._scroll - 240.0) < 1.0,
		"a 240px drag scrolls the list by 240px (got %.1f)" % _menu._scroll
	)
	_check(
		absf(
			Rect2(_menu.call("_card_rect", 0)).position.y - view.position.y + 240.0
		) < 1.0,
		"cards moved up together with the window"
	)
	# Жест до упора — зажим ПО НОМЕРАМ СПИСКА [0, max] (автор 17.10.2026:
	# свап ведёт полный ход, «выбранный в окне» остаётся у клавиатуры).
	# Дальше дна палец не едет, но выбранная строка может уехать
	# за маску — её возвращает навигация (_scroll_to_sel) и open().
	var topb: float = _menu.call("_list_max_scroll")
	_menu.call("_input", _motion(at - Vector2(0.0, 240.0), at - Vector2(0.0, 9000.0)))
	_check(
		absf(_menu._scroll - topb) < 1.0,
		"the drag stops at the scroll bound (%.1f of max %.1f)" % [_menu._scroll, topb]
	)
	# Тап после жеста игрока НЕ выбирает: это была прокрутка.
	_picked = ""
	var last := Rect2(_menu.call("_card_rect", 11))
	_menu.call("_input", _tap(last.get_center()))
	_menu.call("_input", _motion(last.get_center(), last.get_center() - Vector2(0.0, 60.0)))
	_menu.call("_input", _release(last.get_center() - Vector2(0.0, 60.0)))
	_check(_picked == "", "a drag over a card does not play that profile")
	# Короткий тап: пресс сам по себе молчит — тап доигрывает на
	# отпускании. В компактном списке (автор 18.10.2026) ПЕРВЫЙ тап
	# по свёрнутому ряду только разворачивает его; повторный тап по
	# уже развёрнутому играет.
	_menu._scroll = max_scroll
	var tap_at := Rect2(_menu.call("_card_rect", 11)).get_center()
	_picked = ""
	_menu.call("_input", _tap(tap_at))
	_check(_picked == "", "a press alone does not play yet (waits for release)")
	_menu.call("_input", _release(tap_at))
	_check(_picked == "", "the first tap on a collapsed row only expands it")
	_check(int(_menu.sel) == 11, "the first tap selects that profile")
	_menu_tap(Rect2(_menu.call("_card_rect", 11)).get_center())
	_check(_picked != "", "a second tap on the expanded row plays")
	# Вниз до упора — тоже зажим, в ноль не уходит.
	_menu._scroll = max_scroll
	var at2 := view.get_center()
	_menu.call("_input", _tap(at2))
	_menu.call("_input", _motion(at2, at2 + Vector2(0.0, 9000.0)))
	_check(
		absf(_menu._scroll) < 1.0,
		"the list stops at the top bound (%.1f, bound 0.0)" % _menu._scroll
	)
	_menu.call("_input", _release(at2 + Vector2(0.0, 9000.0)))
	# Колесо мыши (десктоп) листает список так же — и задаёт ЦЕЛЬ:
	# фактическая прокрутка догоняет её в _process (18/с).
	_menu._scroll = 0.0
	_menu._scroll_target = 0.0
	_menu.sel = 5
	_menu.call("_input", _wheel(at2, false))
	for _i in 12:
		_menu.call("_input", _wheel(at2, false))
	var b_hi: float = Vector2(_menu.call("_focus_scroll_bounds")).y
	_check(
		_menu._scroll_target >= b_hi - 1.0 and b_hi > 0.0,
		"the wheel down reaches the scroll bound (%.1f of %.1f)"
		% [_menu._scroll_target, b_hi]
	)
	for _i in 24:
		_menu.call("_input", _wheel(at2, true))
	var b_lo: float = Vector2(_menu.call("_focus_scroll_bounds")).x
	_check(
		_menu._scroll_target <= b_lo + 1.0,
		"the wheel scrolls back to the top bound (%.1f of %.1f)"
		% [_menu._scroll_target, b_lo]
	)
	# Стрелки держат выбранного в окне.
	_menu._scroll = 0.0
	_menu._scroll_target = 0.0
	_menu.sel = 10
	_menu.call("_nav", 1)
	_settle_scroll()
	_check(_menu.sel == 11, "arrow keys move the selection on")
	var view_now := Rect2(_menu.call("_list_rect"))
	var sel_card := Rect2(_menu.call("_card_rect", 11))
	_check(
		sel_card.end.y <= view_now.end.y + 1.0
			and sel_card.position.y >= view_now.position.y - 1.0,
		"arrow keys keep the selected card inside the window (%.0f..%.0f of %.0f..%.0f)"
		% [sel_card.position.y, sel_card.end.y, view_now.position.y, view_now.end.y]
	)
	# Прокрутка не ломает раскладку: окно между шапкой и полем.
	_menu._scroll = max_scroll
	_check(
		Rect2(_menu.call("_list_rect")).end.y
			<= float(_menu.call("_buttons_y")) + 1.0,
		"the window still ends above the buttons when scrolled"
	)
	# Пояснение галки не ложится на поле ввода и на свою клавиатуру:
	# в карточках оно над полем, внутри окна списка (ловил на кадре
	# «name-field» — текст был на верхнем ряду клавиш).
	_menu.input_active = true
	var expl_y: float = _menu.call("_chip_hint_y")
	var btns: Rect2 = Rect2(_menu.call("_btn_row"))
	var expl_top: float = expl_y - 24.0 * _menu.k
	_check(
		expl_top <= btns.position.y,
		"the chip explanation stays above the buttons (%.0f <= %.0f)" % [
			expl_top, btns.position.y]
	)
	# Поднять пояснение к нижнему краю экрана нельзя: там своя
	# клавиатура, и текст ложился на верхний ряд клавиш.
	_check(
		expl_y < _menu.view_h - _menu.call("_own_h"),
		"the chip explanation does not reach the own keyboard"
	)
	_end_edit(_menu)
	# В альбомной прокрутки нет: таблица вся на экране или ужата по k.
	_menu.view_w = 2280.0
	_menu.view_h = 1080.0
	_menu.k = 1.0
	_menu.users = saved_users.duplicate()
	_check(
		float(_menu.call("_list_max_scroll")) == 0.0,
		"the landscape table never scrolls"
	)
	_menu.users = saved_users.duplicate()
	_menu.view_w = 1080.0
	_menu.view_h = 1900.0
	_menu._scroll = 0.0
	Ui.force_touch = was_touch


## Зайчик в своей полосе слева от списка и прыжок за выделением
## (автор 15.10.2026: «не удалять и не уменьшать кролика, отвести под
## него столбик и пусть он прыгает от строки к строке»). Прежде он стоял
## у заголовка и закрывал имя первого игрока.
func _part30_bunny_strip() -> void:
	var was_touch := Ui.force_touch
	Ui.force_touch = true
	var saved_users: Array = _menu.users.duplicate()
	_menu.visible = true
	_menu.confirm_name = ""
	_menu.hint_header = ""
	_end_edit(_menu)
	_menu.view_w = 1080.0
	_menu.view_h = 1900.0
	_menu.top_safe = 0.0
	_menu.k = _menu.call("_fit_k", 2.5, 0.7)
	var many: Array[String] = []
	for i in 3:
		many.append("Игрок%d" % i)
	_menu.users = many
	_menu.sel = 0
	_menu._scroll = 0.0
	_menu._bunny_t = 1.0
	# Полоса существует и список начинается за ней: иначе кролик снова
	# наезжает на имя.
	var strip: float = _menu.call("_bunny_strip")
	_check(strip > 0.0, "the bunny gets its own column")
	var card0: Rect2 = Rect2(_menu.call("_card_rect", 0))
	_check(
		absf(card0.position.x - (float(_menu.call("_list_left0")) + strip)) <= 1.0,
		"the list starts after the bunny column"
	)
	var bx: float = _menu.call("_bunny_x")
	var bw: float = _menu.call("_bunny_w")
	_check(
		bx - bw * 0.5 >= float(_menu.call("_list_left0")) - 1.0
			and bx + bw * 0.5 <= card0.position.x + 1.0,
		"the bunny fits its column and does not reach the name"
	)
	# Прыжок за выделением: после стрелки зайчик в полёте и приземляется
	# на середину новой карточки.
	var y0: float = _menu.call("_bunny_y")
	_menu.call("_nav", 1)
	_check(_menu.sel == 1, "the selection moved")
	_check(float(_menu._bunny_t) < 1.0, "the bunny starts hopping")
	var card1: Rect2 = Rect2(_menu.call("_card_rect", 1))
	var dest1: float = card1.position.y + card1.size.y * 0.5
	# Форма прыжка — парабола с ускорением вниз: отклонение от прямой на
	# четверти пути и в середине соотносятся как 4:3 (4h·t(1-t)). Любое
	# сглаживание это ломает — автор просил прыжок, а не сдвиг с горкой.
	var dev := {}
	for tt in [0.25, 0.5, 0.75]:
		_menu._bunny_t = float(tt)
		dev[tt] = lerpf(y0, dest1, float(tt)) - float(_menu.call("_bunny_y"))
	_check(
		absf(float(dev[0.5]) / maxf(1.0, float(dev[0.25])) - 4.0 / 3.0) < 0.05,
		"the hop is a parabola, not an eased slide (%.2f vs 1.33)" % [
			float(dev[0.5]) / maxf(1.0, float(dev[0.25]))]
	)
	_check(
		float(dev[0.25]) > 0.0 and float(dev[0.5]) > float(dev[0.25])
			and float(dev[0.75]) > 0.0,
		"the bunny is off the rows the whole flight"
	)
	# Даже короткий прыжок подпрыгивает, а не ползёт по строке.
	_menu._bunny_t = 0.5
	_check(
		float(dev[0.5]) >= 20.0 * _menu.k,
		"the hop has a visible height (%.0f px)" % float(dev[0.5])
	)
	_menu.call("_bunny_advance", 10.0)
	_check(
		absf(float(_menu.call("_bunny_y")) - dest1) <= 1.0,
		"the bunny lands on the selected card"
	)
	# Скорость: полпути за половину длительности (0.13 с, автор 15.10.2026:
	# «в два раза медленнее, чем надо» — было 0.26 с).
	_menu.call("_nav", -1)
	_menu.call("_bunny_advance", 0.065)
	_check(
		absf(float(_menu._bunny_t) - 0.5) < 0.05,
		"half the time is half the flight (t=%.2f)" % _menu._bunny_t
	)
	_menu.call("_bunny_advance", 10.0)
	# Серия стрелок подряд: второй прыжок начинается с предыдущей ЦЕЛИ,
	# а не с середины полёта — иначе высота складывается и заяц улетает
	# вверх (автор 15.10.2026). Сейчас sel=0, зайчик стоит на карточке 0.
	_menu.call("_nav", 1)
	_check(_menu.sel == 1, "the selection moved on")
	_menu._bunny_t = 0.5
	var mid_air: float = _menu.call("_bunny_y")
	var card2: Rect2 = Rect2(_menu.call("_card_rect", 2))
	var dest2: float = card2.position.y + card2.size.y * 0.5
	_menu.call("_nav", 1)
	_check(_menu.sel == 2, "the selection moved again")
	_check(
		absf(float(_menu._bunny_from) - dest1) <= 1.0,
		"a chained hop starts at the previous target, not mid-air (%.0f vs %.0f)" % [
			_menu._bunny_from, dest1]
	)
	_check(
		absf(float(_menu._bunny_from) - mid_air) > 1.0,
		"mid-air is not the start"
	)
	# Пик цепочки — как у одиночного прыжка на ту же дистанцию, не выше.
	_menu._bunny_t = 0.5
	var single_h: float = _menu.call("_bunny_h", absf(dest2 - dest1))
	var peak: float = lerpf(dest1, dest2, 0.5) - float(_menu.call("_bunny_y"))
	_check(
		peak <= single_h + 1.0,
		"chained hops do not stack height (%.0f <= %.0f)" % [peak, single_h]
	)
	_menu.call("_bunny_advance", 10.0)
	# Деформация прыгучего мячика: присед → вытягивание → присед,
	# горизонталь — обратно (объём сохраняется).
	var sys := {}
	for tt in [0.0, 0.15, 0.45, 0.8, 1.0]:
		sys[tt] = _menu.call("_bunny_sy", float(tt))
	_check(
		absf(float(sys[0.0]) - 1.0) < 0.01
			and absf(float(sys[0.15]) - 0.82) < 0.02
			and absf(float(sys[0.45]) - 1.18) < 0.02
			and absf(float(sys[1.0]) - 0.86) < 0.02,
		"the squash goes crouch-stretch-crouch (%.2f %.2f %.2f %.2f)" % [
			sys[0.0], sys[0.15], sys[0.45], sys[1.0]]
	)
	_menu._bunny_t = 0.45
	var sq: Vector2 = _menu.call("_bunny_sq")
	_check(
		absf(sq.x - (1.0 - (sq.y - 1.0) * 0.75)) < 0.01,
		"width mirrors height"
	)
	# После приземления — пружина к единице, а не щелчок.
	_menu._bunny_land = 99.0
	_check(
		absf(float(_menu.call("_bunny_sy", 1.0)) - 1.0) < 0.01,
		"long landed stays calm"
	)
	_menu.call("_nav", -1)
	_menu.call("_bunny_advance", 10.0)
	# Прыжок назад, к первой карточке.
	_menu.call("_nav", -1)
	# Форма прыжка — парабола: отклонение от прямой на четверти пути и в
	# середине соотносятся как 4:3 (4h·t(1-t)). Любое сглаживание это
	# ломает — автор просил именно прыжок, а не сдвиг с горкой.
	_menu.call("_bunny_advance", 10.0)
	var back: Rect2 = Rect2(_menu.call("_card_rect", 0))
	_check(
		absf(
			float(_menu.call("_bunny_y")) - (back.position.y + back.size.y * 0.5)
		) <= 1.0,
		"the bunny lands back on the first card (%.0f vs %.0f, sel=%d, card0 была %.0f)" % [
			float(_menu.call("_bunny_y")), back.position.y + back.size.y * 0.5,
			_menu.sel, card0.position.y]
	)
	# За полосой прокрутки кролик едет вместе со строкой выделения.
	var empty: Array[String] = []
	_menu.users = empty
	for i in 12:
		_menu.users.append("И%d" % i)
	_menu.sel = 11
	_menu._scroll = float(_menu.call("_list_max_scroll"))
	_menu._bunny_t = 1.0
	var last: Rect2 = Rect2(_menu.call("_card_rect", 11))
	_check(
		absf(float(_menu.call("_bunny_y")) - (last.position.y + last.size.y * 0.5)) <= 1.0,
		"the bunny follows the selection after scrolling"
	)
	var sprite := Rect2(
		Vector2(bx - bw * 0.5, last.position.y), Vector2(bw, last.size.y)
	)
	var name_col := Rect2(
		Vector2(48.0 * _menu.k + strip, last.position.y), Vector2(20.0, last.size.y)
	)
	_check(
		not sprite.intersects(name_col),
		"the bunny column stays free of the list columns"
	)
	# В альбомной раскладке полоса вычитается из доступной ширины, и
	# первая колонка встаёт за ней (иначе кролик сел бы на имя).
	_menu.view_w = 2280.0
	_menu.view_h = 1080.0
	_menu.k = 1.0
	_menu.sel = 0
	_menu._bunny_t = 1.0
	var cols: Array[float] = _menu.call("_table_cols")
	_check(
		cols[0] >= 48.0 * _menu.k + float(_menu.call("_bunny_strip")) - 1.0,
		"the table's name column starts after the bunny column"
	)
	_check(
		absf(float(_menu.call("_bunny_y")) - float(_menu.call("_bunny_target_y"))) <= 1.0,
		"in the table the bunny sits on the selected row"
	)
	# Заголовок не наезжает на шапки колонок: в таблице они стоят на 44k
	# выше первой строки (ловил на кадре 3120x2080: «Кто играет?» лёг на
	# «Ур» и «Победы»).
	var head_top: float = (
		float(_menu.call("_rows_top")) - 44.0 * _menu.k - 20.0 * _menu.k
	)
	# Заголовок рисуется по базовой линии: его строка занимает
	# [y - высота глифа, y], то есть низ заголовка — сама базовая линия.
	var title_fs: int = _menu.call("_title_fs")
	var title_bottom: float = float(_menu.call("_title_y"))
	_check(
		title_bottom - float(_menu.mono.get_height(title_fs)) >= 8.0 * _menu.k
			and title_bottom <= head_top,
		"the title clears the column headers in the table (%.0f <= %.0f)" % [
			title_bottom, head_top]
	)
	_menu.view_w = 1080.0
	_menu.view_h = 1900.0
	_menu.k = _menu.call("_fit_k", 2.5, 0.7)
	_menu._bunny_t = 1.0
	# Пустой список: полосы нет, кролик стоит у заголовка и на имя
	# первого игрока не лезет (списка нет — лезть некуда).
	var none: Array[String] = []
	_menu.users = none
	_check(
		float(_menu.call("_bunny_strip")) == 0.0,
		"an empty list needs no bunny column"
	)
	_check(
		float(_menu.call("_bunny_y")) <= float(_menu.call("_rows_top")),
		"with no players the bunny stays by the title"
	)
	_menu.users = saved_users.duplicate()
	_menu.sel = 0
	_menu._scroll = 0.0
	_menu._bunny_t = 1.0
	Ui.force_touch = was_touch


## Ничего не наезжает друг на друга — ни в портрете, ни в альбоме, ни
## на пустом списке, ни с сообщением об обновлении, ни со своей
## клавиатурой (автор 15.10.2026: «элементы интерфейса теперь накладываются
## друг на друга»). Верхняя панель: «Обновления» слева, «Кто играет?» по
## центру, солнце-луна справа.
func _part31_menu_no_overlap() -> void:
	var was_touch := Ui.force_touch
	Ui.force_touch = true
	var saved_users: Array = _menu.users.duplicate()
	_menu.visible = true
	_menu.confirm_name = ""
	_menu._upd_open = false
	_menu.hint_header = ""
	var sizes := [
		Vector2i(540, 1140), Vector2i(820, 1180), Vector2i(1080, 1900),
		Vector2i(1080, 2280), Vector2i(2280, 1080), Vector2i(1000, 700),
		Vector2i(412, 915),
		# 64x64 НЕ берём: это дефолтный вьюпорт headless, там не влезает
		# даже одна кнопка под палец (64px). Его отдельно жмёт
		# _part16_touch_sizes — на отсутствие наездов, а не на влезание.
	]
	var msgs := ["", "Проверяю… 42%"]
	for sz in sizes:
		for n_users in [0, 3, 12]:
			for msg in msgs:
				for night in [false, true]:
					_overlap_case(sz, n_users, msg, night)
	_menu.users = saved_users.duplicate()
	_menu._upd_msg = ""
	_end_edit(_menu)
	_menu._scroll = 0.0
	_menu._bunny_t = 1.0
	Ui.force_touch = was_touch


## Один случай матрицы: все рисуемые прямоугольники меню попарно не
## пересекаются и стоят с воздухом (автор 15.10.2026: «умеренно плотно»,
## тексты не липнут друг к другу). Пороги в k: тексты ≥12k, боксы ≥10k,
## спрайт зайчика ≥6k. Тап-зоны здесь не меряем: они вложены по
## построению (кнопка в карточке, чип в строке) и проверяются порядком
## в _input, а не геометрией.
func _menu_gap(a: Rect2, b: Rect2) -> float:
	if a.intersects(b):
		return -1.0
	var dx := maxf(0.0, maxf(a.position.x - b.end.x, b.position.x - a.end.x))
	var dy := maxf(0.0, maxf(a.position.y - b.end.y, b.position.y - a.end.y))
	return Vector2(dx, dy).length()


func _overlap_case(sz: Vector2i, n_users: int, msg: String, night: bool) -> void:
	_menu.view_w = float(sz.x)
	_menu.view_h = float(sz.y)
	_menu.top_safe = 0.0
	_menu.night = night
	_menu._upd_msg = msg
	_end_edit(_menu)
	_menu.confirm_name = ""
	_menu.hint_header = ""
	var names: Array[String] = []
	for i in n_users:
		names.append("Игрок%d" % i)
	_menu.users = names
	_menu.sel = 0
	_menu._scroll = 0.0
	_menu._bunny_t = 1.0
	_menu.k = _menu.call("_fit_k", clampf(
		minf(_menu.view_w / 1100.0, _menu.call("_menu_eff_h") / 650.0)
			* Ui.dpr(), 0.7, 2.5), 0.7)
	var tag := "%dx%d n=%d msg=%d night=%d" % [
		sz.x, sz.y, n_users, 0 if msg == "" else 1, 1 if night else 0]
	var k: float = _menu.k
	# Прямоугольники рисуемого (боксы, кнопки, тексты, спрайт).
	var bar := [
		["обновления", Rect2(_menu.call("_upd_button_rect"))],
		["тема", Rect2(_menu.call("_night_tap_rect"))],
	]
	if _menu.call("_title_fs") > 0:
		var tfs: int = _menu.call("_title_fs")
		var tw: float = _menu.call("_text_size", "Кто играет?", tfs).x
		bar.append(["заголовок", Rect2(
			Vector2(float(_menu.call("_title_x")) - tw * 0.5,
				float(_menu.call("_title_y")) - _menu.mono.get_height(tfs)),
			Vector2(tw, _menu.mono.get_height(tfs)))])
	if msg != "":
		var mw: float = _menu.call("_text_size", msg, 20).x
		var mbase: float = _menu.call("_chip_hint_y")
		bar.append(["сообщение", Rect2(
			Vector2((_menu.view_w - mw) * 0.5, mbase - 20.0 * k),
			Vector2(mw, 20.0 * k))])
	# Внутри панели — одна визуальная группа: 6k достаточно, тексты
	# снаружи держат 12k.
	_gap_check(tag, k, bar, 6.0, "панель")
	# Панель и список: заголовок не лезет на шапку/карточки.
	var list_top: float = _menu.call("_rows_top")
	var bar_bottom: float = float(_menu.top_safe) + _menu.call("_bar_h")
	_check(list_top >= bar_bottom + 10.0 * k - 1.0,
		"%s: no air between the bar and the list" % tag)
	if n_users > 0:
		if bool(_menu.call("_cards")):
			_gap_check(tag, k, [
				["карточка", Rect2(_menu.call("_card_rect", 0))],
				["заголовок", _bar_title_rect()],
			], 12.0, "карточка-заголовок")
		else:
			var cols: Array = _menu.call("_table_cols")
			_gap_check(tag, k, [
				["шапка", Rect2(Vector2(cols[0], list_top - 56.0 * k - 20.0 * k), Vector2(cols[6] - cols[0], 20.0 * k))],
				["заголовок", _bar_title_rect()],
			], 12.0, "шапка-заголовок")
			_gap_check(tag, k, [
				["шапка", Rect2(Vector2(cols[0], list_top - 56.0 * k - 20.0 * k), Vector2(cols[6] - cols[0], 20.0 * k))],
				["строка", _row_draw_rect0()],
			], 8.0, "шапка-строка")
	# Низ: ряд кнопок и своя клавиатура — друг над другом с воздухом.
	_gap_check(tag, k, [
		["новый", Rect2(_menu.call("_new_tap_rect"))],
		["без профиля", Rect2(_menu.call("_guest_tap_rect"))],
	], 10.0, "низ")
	# Зайчик в своей полосе: не наезжает на текст и боксы.
	if _menu.call("_bunny_visible"):
		var bp: Vector2 = _menu.call("_bunny_pos")
		var bw: float = _menu.call("_bunny_w")
		var bb := Rect2(bp - Vector2(bw * 0.5, 76.0 * k * 0.5), Vector2(bw, 76.0 * k))
		var foes := [
			["панель-заяц", Rect2(_menu.call("_upd_button_rect"))],
			["заяц", bb],
		]
		_gap_check(tag, k, foes, 6.0, "заяц-панель")
		if n_users > 0:
			var rowbox := Rect2(_menu.call("_card_rect", 0)) if bool(_menu.call("_cards")) else _row_draw_rect0()
			_gap_check(tag, k, [["строка", rowbox], ["заяц", bb]], 6.0, "заяц-строка")
	# Своя клавиатура снизу — кнопки обязаны быть выше неё.
	_menu.input_active = true
	_menu.k = _menu.call("_fit_k", clampf(
		minf(_menu.view_w / 1100.0, _menu.call("_menu_eff_h") / 650.0)
			* Ui.dpr(), 0.7, 2.5), 0.7)
	k = _menu.k
	var eff: float = _menu.call("_menu_eff_h")
	var new_kb := Rect2(_menu.call("_new_tap_rect"))
	var guest_kb := Rect2(_menu.call("_guest_tap_rect"))
	_end_edit(_menu)
	_check(
		new_kb.end.y <= eff + 1.0 and guest_kb.end.y <= eff + 1.0,
		"%s: the buttons stay above the own keyboard (%.0f > %.0f)" % [
			tag, new_kb.end.y, eff]
	)
	_menu._upd_msg = ""


## Прямоугольник заголовка одной строкой (для зазоров).
func _bar_title_rect() -> Rect2:
	var tfs: int = _menu.call("_title_fs")
	if tfs <= 0:
		return Rect2()
	var tw: float = _menu.call("_text_size", "Кто играет?", tfs).x
	var th: float = _menu.mono.get_height(tfs)
	return Rect2(
		Vector2(float(_menu.call("_title_x")) - tw * 0.5, float(_menu.call("_title_y")) - th),
		Vector2(tw, th))


## Нарисованная первая строка таблицы (ужатый бокс, см. _row_draw_rect).
func _row_draw_rect0() -> Rect2:
	var t := Rect2(_menu.call("_row_tap_rect", 0))
	return Rect2(
		t.position + Vector2(0, 5.0 * _menu.k), t.size - Vector2(0, 10.0 * _menu.k)
	)


## Пары прямоугольников: ни пересечений, ни тесноты ниже порога (в k).
func _gap_check(tag: String, k: float, parts: Array, need_k: float, what: String) -> void:
	for a in parts.size():
		for b in range(a + 1, parts.size()):
			var ra: Rect2 = parts[a][1]
			var rb: Rect2 = parts[b][1]
			if ra.size.x <= 1.0 or rb.size.x <= 1.0 or ra.size.y <= 1.0 or rb.size.y <= 1.0:
				continue
			var g := _menu_gap(ra, rb)
			_check(g >= 0.0,
				"%s: %s overlaps %s (%s)" % [tag, String(parts[a][0]), String(parts[b][0]), what])
			_check(g >= need_k * k - 1.0,
				"%s: %s and %s are cramped (%.0fpx, %s)" % [tag, String(parts[a][0]), String(parts[b][0]), g, what])


func _part32_pre_ready_geometry() -> void:
	var was_touch := Ui.force_touch
	Ui.force_touch = true
	var saved_users: Array = _menu.users.duplicate()
	var saved_mono: Font = _menu.mono
	_menu.visible = true
	_menu.view_w = 1080.0
	_menu.view_h = 1900.0
	_menu.top_safe = 0.0
	_menu.mono = null
	var pre: Array[String] = ["Ю1", "Ю2", "Ю3"]
	_menu.users = pre
	_menu.sel = 0
	_menu._scroll = 0.0
	_menu._bunny_t = 1.0
	# Всё, что меряет open()/reload()/fit до _ready — обязано отвечать
	# числами, а не ошибками.
	_menu._reload()
	_menu.k = _menu.call("_fit_k", 2.5, 0.7)
	_check(_menu.k >= 0.7 and _menu.k <= 2.5, "fit answers without a font")
	_check(float(_menu.call("_title_fs")) >= 0, "title scale answers without a font")
	_check(float(_menu.call("_bar_h")) > 0.0, "bar height answers without a font")
	_check(
		Rect2(_menu.call("_list_rect")).size.y > 0.0,
		"list window answers without a font"
	)
	_menu._apply_night()
	_check(true, "night paints without panels survive")
	_menu.mono = saved_mono
	_menu.users = saved_users.duplicate()
	_menu._scroll = 0.0
	_menu._bunny_t = 1.0
	Ui.force_touch = was_touch


## Тап-игра, ряды кнопок и зайчик (автор 17.10.2026): «клик по имени —
## зайчик трясётся, игра не начинается» и «кнопки стали крупными,
## а текст в них мелкий». Держит: прямой тап по игроку ИГРАЕТ (дабл-клик
## и Enter — так же, проверено в _part13 и _part28); на телефоне ряды
## внизу — ДВА, каждый в полную ширину; кегль подписи — от высоты
## кнопки (45%), ниже 24k падать не может; заяц не перезапускает прыжок
## на ту же строку (прыжок-по-месту был дрожью, а не прыжком).
## Границы меню на плотных экранах (скрин автора 18.10.2026, v0.0.33):
## рамка списка внутри экрана, все строки внутри рамки, скроллбар
## внутри рамки, внутренности карточки внутри карточки. Ломалось
## смешиванием масштабов: высота карточки меряется _card_k (от ширины
## экрана), а рисование — общим k (от плотности) — при k > _card_k
## статистика налезала на имя, чипы вылезали за нижнюю грань.
func _part34_menu_bounds() -> void:
	var was_dpr := Ui.dpr_override
	for geo in [[1080, 2340, 2.625], [1080, 2340, 1.0], [2280, 1080, 2.625]]:
		Ui.dpr_override = float(geo[2])
		_menu.view_w = float(geo[0])
		_menu.view_h = float(geo[1])
		_menu.top_safe = 0.0
		_menu.night = false
		_end_edit(_menu)
		_menu.confirm_name = ""
		_menu.hint_header = ""
		var names: Array[String] = []
		for i in 6:
			names.append("Игрок%d" % i)
		_menu.users = names
		_menu.sel = 0
		_menu._scroll = 0.0
		_menu._bunny_t = 1.0
		_menu.k = _menu.call("_fit_k", clampf(
			minf(_menu.view_w / 1100.0, _menu.call("_menu_eff_h") / 650.0)
				* Ui.dpr(), 0.7, 2.5), 0.7)
		var tag := "%dx%d dpr=%.2f" % [geo[0], geo[1], geo[2]]
		var vw: float = _menu.view_w
		var view: Rect2 = _menu.call("_list_rect")
		_check(view.position.x >= -0.5 and view.end.x <= vw + 0.5,
			"%s: list frame inside the screen (%.0f..%.0f of %.0f)" % [
				tag, view.position.x, view.end.x, vw])
		# Скроллбар — внутри рамки, а не у края экрана. Меряют саму
		# меру (_scrollbar_x), а не её зеркало: поломанное рисование
		# ломает меру — и тест это видит.
		var sbw: float = maxf(5.0 * _menu.k, 4.0)
		var sbx: float = _menu.call("_scrollbar_x")
		_check(sbx >= view.position.x and sbx + sbw <= view.end.x + 0.5,
			"%s: scrollbar outside the frame (%.0f..%.0f of %.0f..%.0f)" % [
				tag, sbx, sbx + sbw, view.position.x, view.end.x])
		if not bool(_menu.call("_cards")):
			continue
		# Все карточки внутри рамки по горизонтали.
		for i in _menu.users.size():
			var card: Rect2 = _menu.call("_card_rect", i)
			_check(card.position.x >= view.position.x - 0.5
				and card.end.x <= view.end.x + 0.5,
				"%s: row %d outside the frame (%.0f..%.0f of %.0f..%.0f)" % [
					tag, i, card.position.x, card.end.x,
					view.position.x, view.end.x])
		# Внутренности развёрнутой карточки: статистика ниже имени,
		# чипы ниже статистики и в границах карточки.
		var ck: float = _menu.call("_card_k")
		var c0: Rect2 = _menu.call("_card_rect", 0)
		var nfs: int = _menu.call("_card_name_fs", "Игрок0")
		var nsz: float = float((_menu.call("_text_size_fs", "Игрок0", nfs) as Vector2).y)
		var sfs: int = _menu.call("_card_fs", _menu.FONT_CARD_STATS)
		var ssz: float = float((_menu.call("_text_size_fs", "ур.0 · 0/0", sfs) as Vector2).y)
		var name_bottom: float = c0.position.y + _menu._CARD_PAD * ck + nsz
		var stats_top: float = c0.position.y + _menu._CARD_PAD * ck \
			+ float(_menu.call("_font_h", _menu.call("_card_fs", _menu.FONT_CARD_NAME))) \
			+ 8.0 * ck
		_check(stats_top >= name_bottom - 0.5,
			"%s: stats cross the name (%.0f < %.0f)" % [tag, stats_top, name_bottom])
		var chips_top: float = float(_menu.call("_card_btn_row", 0))
		_check(chips_top >= stats_top + ssz + 2.0,
			"%s: chips cross the stats (%.0f < %.0f)" % [
				tag, chips_top, stats_top + ssz + 2.0])
		for which in ["pro", "yo", "del"]:
			var cr: Rect2 = _menu.call("_card_btn_rect", 0, which)
			_check(cr.position.x >= c0.position.x - 0.5
				and cr.end.x <= c0.end.x + 0.5 and cr.end.y <= c0.end.y + 0.5,
				"%s: chip %s outside the card (%.0f..%.0f of %.0f, x %.0f..%.0f of %.0f)" % [
					tag, which, cr.position.y, cr.end.y, c0.end.y,
					cr.position.x, cr.end.x, c0.end.x])
	Ui.dpr_override = was_dpr


func _part33_tap_and_bunny() -> void:
	var was_touch := Ui.force_touch
	Ui.force_touch = true
	var saved_users: Array = _menu.users.duplicate()
	for u in S.user_list():
		S.delete_user(u)
	S.create_user("Оля")
	S.create_user("Паша")
	_menu.open(S.GUEST)
	root.size = Vector2i(540, 1140)
	# Телефонный портрет: палец, карточки, два ряда кнопок.
	var nr := Rect2(_menu.call("_new_tap_rect"))
	var gr := Rect2(_menu.call("_guest_tap_rect"))
	var h: float = _menu.call("_btn_h")
	var bm: float = _menu.call("_edge")
	_check(_menu.call("_btn_rows") == 2, "two button rows on a phone")
	_check(nr.size.y >= 64.0 and gr.size.y >= 64.0, "button rows fit a finger")
	_check(
		absf(nr.position.x - bm) < 0.5 and nr.size.x >= _menu.view_w - bm * 2.0 - 1.0,
		"new player row spans the full width (%.0f vs %.0f)" % [nr.size.x, _menu.view_w - bm * 2.0]
	)
	_check(gr.size.x >= _menu.view_w - bm * 2.0 - 1.0, "guest row spans the full width")
	_check(
		absf(gr.position.y - (nr.end.y + _menu.call("_btn_gap"))) < 0.5,
		"guest row stands right under the new player row"
	)
	_check(gr.end.y <= _menu.view_h - bm + 1.0, "button block fits on screen")
	# Окно списка заканчивается над блоком кнопок, не поверх него.
	_check(
		Rect2(_menu.call("_list_rect")).end.y <= nr.position.y,
		"the list window sits above the button rows"
	)
	# Кегль от высоты кнопки: пол 24k, подпись влезает в свой ряд.
	for pair in [["+ Новый игрок", nr], ["Без профиля", gr]]:
		var fs: int = _menu.call("_button_fs", pair[1], pair[0])
		var r: Rect2 = pair[1]
		var kfloor: int = int(24.0 * _menu.k)
		_check(fs >= kfloor - 1, "%s label kegl keeps the 24k floor (%d < %d)" % [
			pair[0], fs, kfloor])
		_check(
			fs >= int(floor(r.size.y * 0.45)) - 1,
			"%s label kegl tracks the button height (%d on %.0f tall)" % [
				pair[0], fs, r.size.y]
		)
		var w: Vector2 = _menu.call("_text_size_fs", pair[0], fs)
		_check(
			w.x <= r.size.x - 16.0 * _menu.k,
			"%s label fits its row (%.0f px wide)" % [pair[0], w.x]
		)
	# Компактный список (автор 18.10.2026): невыделенный ряд
	# разворачивается тапом БЕЗ игры; повторный тап по уже
	# развёрнутому играет.
	var second := String(_menu.users[1])
	_picked = ""
	_menu_tap(Rect2(_menu.call("_row_tap_rect", 1)).get_center())
	_check(int(_menu.sel) == 1, "the first tap selects the row")
	_check(_picked == "", "the expansion tap does not play yet")
	_menu_tap(Rect2(_menu.call("_row_tap_rect", 1)).get_center())
	_check(_picked == second, "a tap on the expanded row plays as that user")
	# Заяц: после разворота он честно в полёте — даём ему долететь
	# (в headless кадров нет), а прыжок «на ту же строку» не
	# перезапускается — раньше каждый повторный клик по одному игроку
	# дёргал его (жалоба «трясётся»).
	_menu._bunny_t = 1.0
	_menu._bunny_land = 1.0
	_menu.call("_nav", 0)  # стрелка в ту же строку: цели совпадают
	_check(float(_menu._bunny_t) >= 1.0, "same-row hop does not restart the bunny")
	# А на другую строку прыжок жив: стрелка вниз прыгает заново.
	_menu.call("_nav", 1)
	_check(float(_menu._bunny_t) < 1.0, "a real hop restarts the flight")
	_menu._process(1.5)  # прыжок доиграл
	_menu._bunny_t = 1.0
	# Соло-список: стрелка оборачивается на ту же строку — это тоже
	# прыжок «по месту», и он обязан остаться без прыжка.
	S.delete_user(second)
	_menu._reload()
	_menu.call("_nav", 1)
	_check(float(_menu._bunny_t) >= 1.0, "solo wrap does not restart the bunny")
	for u in S.user_list():
		S.delete_user(u)
	_menu.users = saved_users.duplicate()
	_menu._reload()
	root.size = Vector2i(64, 64)
	_menu._relayout()
	Ui.force_touch = was_touch


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


## 25. Битый файл профилей. На телефоне такое бывает после падения
## посреди записи, а файл ещё и правят руками. Игра обязана подняться:
## гостем, с пустым меню, дефолтными числами — но НЕ упасть.
func _part25_corrupt_file() -> void:
	# (а) Мусор вместо файла целиком.
	var fa := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	fa.store_string("не конфиг " + String.chr(0) + String.chr(1) + " <<<>>> {{")
	fa.close()
	S.PATH = TEST_PATH
	S.invalidate()  # файл писали мимо save.gd — кэш разбора сбрасываем
	_check(S.user_list().is_empty(), "a garbage file yields an empty user list")
	var prof: Dictionary = S.load_profile("кого-то")
	_check(
		int(prof.get("difficulty", 0)) == 0 and float(prof.get("enemy_cps", 1.0)) > 0.0,
		"a garbage file yields the default profile"
	)
	# (б) Профиль есть, но значение не словарь (правка руками).
	var cfg := ConfigFile.new()
	cfg.load(TEST_PATH)
	cfg.set_value(S.SECTION_PROFILES, "число", 5)
	cfg.save(TEST_PATH)
	S.invalidate()
	# Такой профиль в списке остаться может (имя в разделе есть), но
	# читаться обязан без падения — иначе меню не открывается вовсе.
	var every_loads := true
	for n in S.user_list():
		if S.load_profile(n).is_empty():
			every_loads = false
	_check(every_loads, "every profile in the list loads, even a broken one")
	var prof2: Dictionary = S.load_profile("число")
	_check(
		int(prof2.get("difficulty", 0)) == 0,
		"a non-dict profile yields the default numbers"
	)
	# (в) Игра с таким профилем поднимается и даёт уровень. Сцену берём
	# свою: предыдущая часть её освободила (дальше тесты только меню).
	var scene: PackedScene = load("res://scenes/main.tscn")
	var game: Node = scene.instantiate()
	game.skip_menu = true
	game.all_keys_override = 1
	root.add_child(game)
	game.profile_name = "число"
	game._start_game()
	_check(game.state == "playing", "the game starts on a non-dict profile (%s)" % game.state)
	_check(not game.display_lines.is_empty(), "the level is not empty on a non-dict profile")
	# (г) Словарь есть, но поля чужих типов: всё равно не падаем.
	var cfg2 := ConfigFile.new()
	cfg2.load(TEST_PATH)
	cfg2.set_value(S.SECTION_PROFILES, "словарь", {"difficulty": "не число", "ema_acc": "и не доля"})
	cfg2.save(TEST_PATH)
	S.invalidate()
	game.profile_name = "словарь"
	game._start_game()
	_check(game.state == "playing", "the game starts on a wrongly typed profile (%s)" % game.state)
	_check(
		game.ema_acc >= 0.0 and game.ema_acc <= 1.0,
		"a wrongly typed accuracy is clamped (%.2f)" % game.ema_acc
	)
	game.queue_free()


## 26. Модалка обновления с клавиатуры: «Не сейчас» должна быть
## достижима. Кнопка на экране есть, но с клавиш до неё не дойти —
## Enter качает, всё остальное съедается, а Esc в этой модалке уходит
## из ИГРЫ. На десктопе и на эмуляторе с внешней клавиатурой это тупик:
## либо качать, либо закрыть игру (проба 10.2026).
func _part26_update_modal_keys() -> void:
	_end_edit(_menu)  # Esc в правке — это отмена, а не выход из игры
	_menu._upd_open = true
	_menu._upd_tag = "v0.0.10"
	_menu._upd_notes = ["a", "b"] as Array[String]
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	_menu.call("_unhandled_key_input", esc)
	_check(
		not bool(_menu._upd_open),
		"Esc declines the update modal instead of reaching the player list"
	)
	# N — тот же отказ (как в модалке удаления профиля).
	_menu._upd_open = true
	var n := InputEventKey.new()
	n.keycode = KEY_N
	n.pressed = true
	_menu.call("_unhandled_key_input", n)
	_check(not bool(_menu._upd_open), "N declines the update modal")
	# Enter по-прежнему согласие, и Esc в обычном меню доску не трогает.
	# Повторный Esc в меню — полный выход (автор 10.2026): настоящий quit
	# в тесте погашен (убил бы процесс), читаем флаг намерения.
	_menu._upd_open = false
	_menu.quit_enabled = false
	_menu.quit_requested = false
	_menu.call("_unhandled_key_input", esc)
	_check(bool(_menu.visible), "Esc outside the modal does not close the menu")
	_check(bool(_menu.quit_requested), "Esc in the menu requests the full quit")
	_menu.quit_enabled = true
	# Отказ во время закачки гасит закачку: иначе файл докачается и
	# установщик вылезет поверх игры, хотя от обновления отказались.
	_menu._upd._pending_url = "http://x/apk"
	_menu._upd._pending_tag = "v0.0.10"
	_menu._upd_open = true
	_menu.call("_unhandled_key_input", esc)
	_check(
		String(_menu._upd._pending_url) == "" and String(_menu._upd._pending_tag) == "",
		"declining during the download forgets the pending file"
	)
	_check(String(_menu._upd_state) == "", "declining during the download resets the state")


## 27. Хаос по меню: сотни случайных тапов и клавиш по живой доске с
## профилями, модалкой удаления и модалкой обновления. Инварианты после
## каждого события: меню живо, поле ввода и флаги не рассыпались, а
## выход (F2) работает ВСЕГДА — ребёнок не должен остаться в меню
## без возможности вернуться в игру.
## Портрет: список игроков карточками, а не таблицей (решение 10.2026).
## Это не косметика, а другая геометрия: карточка во всю ширину,
## кнопки крупные и не наезжают ни на соседнюю карточку, ни друг на
## друга; тап по карточке играет, тап по чипу — только флаг, шапки
## колонок (объяснение галки) в карточках нет: пояснение приходит из
## самого переключения. И главное — при полном количестве игроков
## блок влезает в экран (карточка выше строки таблицы, поэтому
## масштаб ужимается сильнее).
func _part28_cards() -> void:
	for u in S.user_list():
		S.delete_user(u)
	S.create_user("Таня")
	S.create_user("Федя")
	_menu.call("_reload")
	_menu.visible = true
	_menu.confirm_name = ""
	_end_edit(_menu)
	_menu.sel = 0
	_menu.sel_col = 0
	# Телефон: портрет 1080x2280, тач включён (он и на телефоне).
	# Размеры задаём руками: _relayout в headless подхватил бы мусорный
	# вьюпорт 64x64 (как и остальные проверки здесь).
	var was_touch: bool = Ui.force_touch
	Ui.force_touch = true
	_menu.top_safe = 0.0
	_menu.view_w = 1080.0
	_menu.view_h = 2280.0
	_menu.k = clampf(minf(_menu.view_w / 1100.0, _menu.call("_menu_eff_h") / 650.0), 0.5, 2.5)
	_check(bool(_menu.call("_cards")), "portrait draws cards")
	_check(
		Rect2(_menu.call("_row_tap_rect", 0)).size.x >= _menu.view_w * 0.8,
		"a card spans the screen"
	)
	# Шапки колонок в карточках нет — тап по ней нечего ловить.
	_check(
		Rect2(_menu.call("_pro_head_rect")).size == Vector2.ZERO,
		"no pro header to tap in cards"
	)
	_check(
		Rect2(_menu.call("_yo_head_rect")).size == Vector2.ZERO,
		"no yo header to tap in cards"
	)
	# Геометрия: свёрнутые ряды — одна строка без кнопок; в развёрнутом
	# (сейчас ряд 0 — он выбран) чипы внутри карточки, крупные и не
	# пересекаются (автор 18.10.2026: кнопки только у развёрнутого).
	var c0 := Rect2(_menu.call("_card_rect", 0))
	var c1 := Rect2(_menu.call("_card_rect", 1))
	_check(not c0.intersects(c1), "cards do not overlap")
	_check(c1.end.y <= _menu.view_h, "the last card fits on screen")
	var expanded_h: float = float(_menu.call("_card_h"))
	var collapsed_h: float = float(_menu.call("_compact_h"))
	_check(collapsed_h < expanded_h, "a collapsed row is shorter than a card")
	_check(collapsed_h >= 64.0, "a collapsed row still fits a finger")
	for i in _menu.users.size():
		if not bool(_menu.call("_row_expanded", i)):
			continue
		var card := Rect2(_menu.call("_card_rect", i))
		var pro := Rect2(_menu.call("_pro_tap_rect", i))
		var yo := Rect2(_menu.call("_yo_tap_rect", i))
		var del := Rect2(_menu.call("_del_tap_rect", i))
		for nm in [["Про", pro], ["Ё", yo], ["✕", del]]:
			var r: Rect2 = nm[1]
			_check(r.size.x >= 64.0 and r.size.y >= 64.0,
				"%s in a card fits a finger (%.0fx%.0f)" % [nm[0], r.size.x, r.size.y])
			_check(card.encloses(r), "%s sits inside its card" % nm[0])
		_check(not pro.intersects(yo) and not yo.intersects(del) and not pro.intersects(del),
			"card buttons do not overlap each other")
	# Тап по свёрнутой карточке только разворачивает; тап по
	# развёрнутой (не по чипам) играет; тап по чипу — только флаг
	# (и объясняет галку: шапки-то нет).
	var first := String(_menu.users[0])
	var second := String(_menu.users[1])
	_picked = ""
	_menu_tap(c1.get_center())
	_check(_menu.sel == 1 and _picked == "",
		"a tap on a collapsed card expands it without playing")
	_menu_tap(Rect2(_menu.call("_card_rect", 1)).get_center())
	_check(_picked == second, "a second tap on the expanded card plays as that user")
	# Дабл-клик (мышь) играет и по свёрнутому ряду: жест уже
	# классифицирован, сам по себе игра. sel сейчас на втором — ряд
	# «первый» свёрнут.
	_menu_double_tap(Rect2(_menu.call("_card_rect", 0)).get_center())
	_check(_picked == first, "a double tap on a collapsed card plays too")
	# Чипы развёрнутого ряда: правят флаг, не играют, крестик
	# открывает подтверждение удаления. Ряд 0 уже выбран и развёрнут
	# (дабл-тапом), поэтому тап по нему играет — выравниваем счёт.
	_menu_tap(Rect2(_menu.call("_card_rect", 0)).get_center())
	_picked = ""
	_menu_tap(Rect2(_menu.call("_pro_tap_rect", 0)).get_center())
	_check(S.get_all_keys(first), "card chip turns all_keys on")
	_check(_picked == "", "card chip does not play the profile")
	_check(String(_menu.hint_header) == "pro",
		"the chip explains its flag (cards have no header)")
	_menu_tap(Rect2(_menu.call("_yo_tap_rect", 0)).get_center())
	_check(not S.get_yo_strict(first), "card yo chip relaxes strictness")
	_check(String(_menu.hint_header) == "yo", "the yo chip explains itself too")
	# Тап по зоне чипа свёрнутого ряда флаг НЕ трогает: там кнопок нет,
	# разворачивается сама строка (сел на неё). Ряд «второй» свёрнут
	# после выбора нулевого.
	_menu_tap(Rect2(_menu.call("_card_rect", 1)).get_center())
	var pro0_was: bool = S.get_all_keys(first)
	_menu_tap(Rect2(_menu.call("_pro_tap_rect", 0)).get_center())
	_check(S.get_all_keys(first) == pro0_was, "a collapsed row has no chips to tap")
	_check(int(_menu.sel) == 0, "the chip zone of a collapsed row selects it")
	# Крестик развёрнутого ряда открывает подтверждение удаления.
	_menu_tap(Rect2(_menu.call("_del_tap_rect", 0)).get_center())
	_check(String(_menu.confirm_name) == first,
		"the card cross opens the delete confirmation")
	_menu_tap(Rect2(_menu.call("_confirm_no_rect")).get_center())
	_check(S.user_exists(first), "cancelling the confirmation keeps the profile")
	# Много игроков: интерфейс остаётся крупным, список листается. Низ
	# (поле + кнопки) прижат к экрану и обязан на нём помещаться при
	# любом числе игроков — это то, что раньше ломалось ужимом k.
	var many: Array[String] = []
	for i in 12:
		many.append("Ю%d" % i)
	_menu.users = many
	_end_edit(_menu)
	_menu.confirm_name = ""
	_menu.view_w = 1080.0
	_menu.view_h = 2280.0
	_menu.k = _menu.call("_fit_k", 2.5, 0.7)
	_check(bool(_menu.call("_cards")), "still cards with twelve players")
	_check(
		float(_menu.call("_list_max_scroll")) > 0.0,
		"twelve players make the list scrollable"
	)
	# Кнопки на экране и после прокрутки: список под ними не едет.
	_menu._scroll = float(_menu.call("_list_max_scroll"))
	_check(
		Rect2(_menu.call("_btn_row")).end.y <= _menu.view_h,
		"action buttons fit with cards"
	)
	_check(
		Rect2(_menu.call("_card_rect", 11)).end.y
			<= Rect2(_menu.call("_list_rect")).end.y + 1.0,
		"the twelfth card comes into view when scrolled to the end"
	)
	# Короткий телефон (1080x1900): там запаса мало, и ужим должен
	# дожать не только первые пиксели — шаг карточки зависит от k
	# дважды (высота и кнопка под палец), поэтому одной-двух итераций
	# мало: остаток не влезает.
	for vh in [2280.0, 1900.0]:
		_menu.view_w = 1080.0
		_menu.view_h = vh
		_menu.k = _menu.call("_fit_k", 2.5, 0.7)
		_end_edit(_menu)
		_menu._scroll = 0.0
		# Видимая часть списка — между шапкой и полем ввода, и в неё
		# влезает карточка целиком: карточка не режется полем.
		var view_r := Rect2(_menu.call("_list_rect"))
		_check(
			view_r.position.y >= float(_menu.call("_rows_top")) - 1.0
				and view_r.end.y <= float(_menu.call("_buttons_y")) + 1.0,
			"the list sits between the header and the buttons on a %.0f-tall phone" % vh
		)
		_check(
			view_r.size.y >= float(_menu.call("_card_h")) - 1.0,
			"at least one whole card fits on a %.0f-tall phone" % vh
		)
		_check(
			Rect2(_menu.call("_btn_row")).end.y <= vh,
			"buttons fit on a %.0f-tall phone" % vh
		)
	# Альбом — привычная таблица: карточек нет, шапка колонок есть.
	_menu.users = many
	_menu.view_w = 2280.0
	_menu.view_h = 1080.0
	_menu.k = 1.0
	_check(not bool(_menu.call("_cards")), "landscape keeps the table")
	_check(
		Rect2(_menu.call("_pro_head_rect")).size.x > 0.0,
		"the table still has the pro header"
	)
	# Ряд кнопок действий влезает в экран при ЛЮБОЙ ширине (в том числе
	# в 64px, где рисует headless-тест) и нигде не наезжает друг на друга:
	# раньше кнопки стояли на константах от центра и в портрете ночная
	# уезжала за правый край (видно на кадрах визуального прогона).
	for vw in [64.0, 320.0, 412.0, 700.0, 1080.0, 2280.0]:
		_menu.view_w = vw
		_menu.view_h = 915.0
		_menu.k = 1.0
		var newer := Rect2(_menu.call("_new_tap_rect"))
		var guest := Rect2(_menu.call("_guest_tap_rect"))
		var night := Rect2(_menu.call("_night_tap_rect"))
		_check(
			newer.position.x >= 0.0 and night.end.x <= vw,
			"action buttons fit the screen width (vw=%.0f)" % vw
		)
		_check(
			not newer.intersects(guest) and not guest.intersects(night),
			"action buttons do not overlap (vw=%.0f)" % vw
		)
	for u in S.user_list():
		S.delete_user(u)
	var empty: Array[String] = []
	_menu.users = empty
	Ui.force_touch = was_touch
	_menu.view_w = 1100.0
	_menu.view_h = 650.0
	_menu.k = 1.0
	_menu.top_safe = 0.0


func _part27_menu_chaos() -> void:
	for u in ["хаос-а", "хаос-б"]:
		S.create_user(u)
	_menu.open(S.GUEST)
	var stuck := 0
	var broken := 0
	var seed_v := 12345
	for i in 600:
		seed_v = (seed_v * 1103515245 + 12345) % 2147483648
		var r := float(seed_v % 10000) / 10000.0
		if r < 0.5:
			# Случайный тап по меню (включая мимо кнопок).
			var w: float = 1280.0
			var h: float = 900.0
			var pos := Vector2(r * w, float(seed_v % 900) / 1000.0 * h)
			_menu_tap(pos)
		else:
			var k := String.chr(32 + (seed_v % 90))
			_menu.call("_unhandled_key_input", _key_event(k))
		# Инварианты после события.
		if not bool(_menu.visible):
			broken += 1
			break
		var txt: String = String(_menu.input_text)
		if txt.find("\n") >= 0 or txt.length() > 40:
			broken += 1
			break
		# Выход должен быть на месте: F2 возвращает в игру. Меню само
		# не закрывается — его закрывает игра по сигналу chosen, так что
		# проверяем именно сигнал.
		if i % 50 == 49:
			_menu._upd_open = false
			_menu.confirm_name = ""
			# Метка: пустая строка — это гость, а «сигнала не было»
			# — это вовсе другая пустая строка, поэтому метим событие.
			_picked = "НЕ-ОТПРАВЛЕНО"
			var esc := InputEventKey.new()
			esc.keycode = KEY_F2
			esc.pressed = true
			_menu.call("_unhandled_key_input", esc)
			if _picked == "НЕ-ОТПРАВЛЕНО":
				stuck += 1
			_menu.open(S.GUEST)
	_check(broken == 0, "the menu stayed sane under 600 random events (%d)" % broken)
	_check(stuck == 0, "F2 always returns to the game (%d times it did not)" % stuck)
	# Профили на месте: хаос не унёс никого.
	_check(
		S.user_exists("хаос-а") and S.user_exists("хаос-б"),
		"chaos did not delete the profiles"
	)
	for u in ["хаос-а", "хаос-б"]:
		S.delete_user(u)
