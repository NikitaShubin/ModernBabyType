class_name SaveData
extends RefCounted
## Профили игроков в user://modern_baby_type.cfg (не в папке игры).
##
## Структура файла:
##   [last]      user = "Иван"   # "" — гость, прогресс не сохраняется
##   [profiles]  "Иван" = { ... }
##
## Поведение меню игроков перенесено из pygame-прототипа (git show
## 1a097c0:main.py): имена до 15 символов, пустое имя и дубль отклоняются,
## гостевой режим ничего не пишет.
##
## PATH — не константа, а static var: тесты подставляют свой файл, чтобы
## не портить профиль автора.

const SECTION_PROFILES := "profiles"
const SECTION_LAST := "last"
const KEY_LAST_USER := "user"
const GUEST := ""
const MAX_NAME_LENGTH := 15

static var PATH := "user://modern_baby_type.cfg"


static func default_profile() -> Dictionary:
	return {
		"difficulty": 0,
		"wins_in_row": 0,
		"ema_cpm": 0.0,
		"ema_acc": 1.0,
		"enemy_cps": Balance.BASE_CPS,
		## Взрослый режим: активны все знаки сразу, печать не тормозит
		## из-за прогрессии. Ставится в меню игроков клавишей A.
		"all_keys": false,
		"total_games": 0,
		"total_wins": 0,
		"last_played": 0,
	}


static func clean_name(raw: String) -> String:
	return raw.strip_edges().left(MAX_NAME_LENGTH)


static func _cfg() -> ConfigFile:
	var cfg := ConfigFile.new()
	cfg.load(PATH)
	return cfg


## Имена профилей: сначала те, в кто играл недавно, потом остальные по
## имени. Гость в списке не значится — его и негде хранить.
static func user_list() -> Array[String]:
	var cfg := _cfg()
	if not cfg.has_section(SECTION_PROFILES):
		return []
	var names: Array[String] = []
	for name in cfg.get_section_keys(SECTION_PROFILES):
		names.append(String(name))
	names.sort_custom(_newer_first)
	return names


static func _newer_first(a: String, b: String) -> bool:
	var pa := load_profile(a)
	var pb := load_profile(b)
	var ta := int(pa.get("last_played", 0))
	var tb := int(pb.get("last_played", 0))
	if ta != tb:
		return ta > tb
	return a.naturalnocasecmp_to(b) < 0


static func user_exists(user_name: String) -> bool:
	if user_name == GUEST:
		return false
	return _cfg().has_section_key(SECTION_PROFILES, user_name)


static func count_users() -> int:
	return user_list().size()


## Создать новый профиль. Возвращает false на пустом имени, на имени
## длиннее MAX_NAME_LENGTH после обрезки и на дубле.
static func create_user(raw: String) -> bool:
	var name := clean_name(raw)
	if name.is_empty() or name == GUEST:
		return false
	if user_exists(name):
		return false
	var data := default_profile()
	data["last_played"] = _now()
	var cfg := _cfg()
	cfg.set_value(SECTION_PROFILES, name, data)
	cfg.save(PATH)
	set_last_user(name)
	return true


static func delete_user(user_name: String) -> bool:
	if not user_exists(user_name):
		return false
	var cfg := _cfg()
	cfg.erase_section_key(SECTION_PROFILES, user_name)
	if get_last_user() == user_name:
		cfg.set_value(SECTION_LAST, KEY_LAST_USER, GUEST)
	cfg.save(PATH)
	return true


static func get_last_user() -> String:
	var cfg := _cfg()
	if not cfg.has_section_key(SECTION_LAST, KEY_LAST_USER):
		return GUEST
	return String(cfg.get_value(SECTION_LAST, KEY_LAST_USER, GUEST))


static func set_last_user(user_name: String) -> void:
	var cfg := _cfg()
	cfg.set_value(SECTION_LAST, KEY_LAST_USER, user_name)
	cfg.save(PATH)


static func has_valid_last_user() -> bool:
	return user_exists(get_last_user())


static func load_profile(user_name: String) -> Dictionary:
	var data := default_profile()
	if user_name == GUEST:
		data["last_played"] = _now()
		return data
	var cfg := _cfg()
	if not cfg.has_section_key(SECTION_PROFILES, user_name):
		return data
	var stored: Dictionary = cfg.get_value(SECTION_PROFILES, user_name, {})
	for key in data.keys():
		if stored.has(key):
			data[key] = stored[key]
	return data


## Гость ничего не сохраняет: это «просто поиграть». Пустой user_name —
## тоже гость (защита от записи в файл по ошибке).
static func save_profile(user_name: String, data: Dictionary) -> void:
	if user_name.is_empty():
		return
	var clean := default_profile()
	for key in clean.keys():
		if data.has(key):
			clean[key] = data[key]
	clean["last_played"] = _now()
	var cfg := _cfg()
	cfg.set_value(SECTION_PROFILES, user_name, clean)
	cfg.save(PATH)


## Взрослый режим профиля: активны все знаки.
static func get_all_keys(user_name: String) -> bool:
	return bool(load_profile(user_name).get("all_keys", false))


static func set_all_keys(user_name: String, on: bool) -> void:
	if not user_exists(user_name):
		return
	var data := load_profile(user_name)
	data["all_keys"] = on
	var cfg := _cfg()
	var stored := data
	stored["last_played"] = int(stored.get("last_played", _now()))
	cfg.set_value(SECTION_PROFILES, user_name, stored)
	cfg.save(PATH)


static func touch(user_name: String) -> void:
	if not user_exists(user_name):
		return
	var data := load_profile(user_name)
	data["last_played"] = _now()
	var cfg := _cfg()
	cfg.set_value(SECTION_PROFILES, user_name, data)
	cfg.save(PATH)


static func _now() -> int:
	return int(Time.get_unix_time_from_system())


## Убрать профиль гостя из старых сборок: он был затычкой «один игрок без
## меню». Список профилей его не показывает, но файл пухнет и путает.
static func drop_legacy_guest() -> void:
	var cfg := _cfg()
	if cfg.has_section_key(SECTION_PROFILES, "guest"):
		cfg.erase_section_key(SECTION_PROFILES, "guest")
		if get_last_user() == "guest":
			cfg.set_value(SECTION_LAST, KEY_LAST_USER, GUEST)
		cfg.save(PATH)


static func wipe() -> void:
	var cfg := ConfigFile.new()
	cfg.save(PATH)
