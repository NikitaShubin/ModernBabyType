class_name SaveData
extends RefCounted
## Профили игроков в user://modern_baby_type.cfg (не в папке игры).
##
## Структура файла:
##   [last]      user = "Иван"   # "" — гость, прогресс не сохраняется
##   [profiles]  "Иван" = { ... }
##
## Правила имён: до 15 символов, пустое имя и дубль отклоняются,
## гостевой режим ничего не пишет.
##
## PATH — не константа, а static var: тесты подставляют свой файл, чтобы
## не портить профиль автора.

const SECTION_PROFILES := "profiles"
const SECTION_LAST := "last"
const KEY_LAST_USER := "user"
const GUEST := ""
const MAX_NAME_LENGTH := 15
## Оформление устройства, не игрока: ночной режим. -1 — как у системы,
## 0 — день, 1 — ночь. Ручной выбор запоминается, по умолчанию система.
const SECTION_DISPLAY := "display"
const KEY_NIGHT := "night_mode"
## Системная клавиатура вместо своей (галочка в меню). По умолчанию —
## своя: системные IME коверкают ввод composing-перепиской. Кому нужна
## привычная — включает, борьба с автозаменой уже встроена (comp-буфер).
const NIGHT_AUTO := -1
const NIGHT_DAY := 0
const NIGHT_ON := 1

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
		## Строгая ё: различать ё и е. Без галки е засчитывается за ё
		## (для тех, кто ё не любит). Ставится там же, колонка «Ё».
		"yo_strict": true,
		"total_games": 0,
		"total_wins": 0,
		"last_played": 0,
	}


static func clean_name(raw: String) -> String:
	return raw.strip_edges().left(MAX_NAME_LENGTH)


## Сколько раз файл настроек реально читался с диска. Счётчик для теста:
## профиль читается на старте уровня, а не на каждом кадре (проверяет
## profiles_test — в игре не должно быть обращений к файлу в кадре).
static var cfg_loads := 0


static func _cfg() -> ConfigFile:
	var cfg := ConfigFile.new()
	cfg_loads += 1
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
	var stored: Variant = cfg.get_value(SECTION_PROFILES, user_name, {})
	# Профиль — это СЛОВАРЬ. Если в файле оказалось что-то другое (правка
	# руками, обрыв записи на телефоне), читаем дефолты: раньше здесь был
	# жёсткий тип, и игра падала на чтении, не доходя до экрана
	# (проба 10.2026, profiles_test часть 25).
	if stored is not Dictionary:
		return data
	for key in data.keys():
		if (stored as Dictionary).has(key):
			data[key] = (stored as Dictionary)[key]
	return data


## Гость ничего не сохраняет: это «просто поиграть». Пустой user_name —
## тоже гость (защита от записи в файл по ошибке).
static func save_profile(user_name: String, data: Dictionary) -> void:
	if user_name.is_empty():
		return
	# Слияние, а не замена: читаем сырую запись целиком (включая
	# неизвестные поля будущих версий — они переживают запись),
	# обновляем поданные известные ключи, добиваем дефолты для
	# ключей, которых в старых сейвах ещё не было.
	var cfg := _cfg()
	# Что бы там ни лежало, пишем в СВОЙ словарь: чужой мусор не должен
	# ломать сохранение (теперь читается безопасно, см. load_profile).
	var stored: Dictionary = {}
	var raw: Variant = cfg.get_value(SECTION_PROFILES, user_name, {})
	if raw is Dictionary:
		stored = raw
	var known := default_profile()
	for key in data.keys():
		if known.has(key):
			stored[key] = data[key]
	for key in known.keys():
		if not stored.has(key):
			stored[key] = known[key]
	stored["last_played"] = _now()
	cfg.set_value(SECTION_PROFILES, user_name, stored)
	cfg.save(PATH)


## Взрослый режим профиля: активны все знаки.
static func get_all_keys(user_name: String) -> bool:
	return bool(load_profile(user_name).get("all_keys", false))


static func set_all_keys(user_name: String, on: bool) -> void:
	if not user_exists(user_name):
		return
	save_profile(user_name, {"all_keys": on})


## Строгая ё профиля: различать ё и е. По умолчанию строго (как было).
static func get_yo_strict(user_name: String) -> bool:
	return bool(load_profile(user_name).get("yo_strict", true))


static func set_yo_strict(user_name: String, on: bool) -> void:
	if not user_exists(user_name):
		return
	save_profile(user_name, {"yo_strict": on})


static func touch(user_name: String) -> void:
	if not user_exists(user_name):
		return
	# Пустое слияние: только бамп last_played (порядок «недавних»).
	save_profile(user_name, {})


## Ночной режим устройства: -1 система, 0 день, 1 ночь. Чужое чистим
## клампом, не ошибкой: файл руками правят.
static func get_night_mode() -> int:
	var cfg := _cfg()
	return clampi(int(cfg.get_value(SECTION_DISPLAY, KEY_NIGHT, NIGHT_AUTO)), NIGHT_AUTO, NIGHT_ON)


## Системной клавиатуры больше нет: игра и меню набирают текст только
## своей экранной клавиатурой (Kbd). Флаг «sys_kb» в старых профилях
## игнорируется, а из файла убирается при первой же записи профиля —
## иначе он годами лежит мёртвым полем (решение 10.2026).


static func set_night_mode(mode: int) -> void:
	var cfg := _cfg()
	cfg.set_value(SECTION_DISPLAY, KEY_NIGHT, clampi(mode, NIGHT_AUTO, NIGHT_ON))
	cfg.save(PATH)


## Ночь прямо сейчас: ручной выбор важнее системы, без поддержки —
## всегда день. Чистая функция от трёх флагов — матрица в profiles_test.
static func resolve_night(mode: int, supported: bool, system_dark: bool) -> bool:
	if mode == NIGHT_ON:
		return true
	if mode == NIGHT_DAY:
		return false
	return supported and system_dark


## Темно ли в системе: на десктопе и в headless обычно нет.
static func system_dark() -> bool:
	if not DisplayServer.is_dark_mode_supported():
		return false
	return DisplayServer.is_dark_mode()


static func _now() -> int:
	return int(Time.get_unix_time_from_system())


## Убрать профиль гостя из старых сборок: он был затычкой «один игрок без
## меню». Список профилей его не показывает, но файл пухнет и путает.
## Заодно вычищаем мёртвый флаг системной клавиатуры: своего ввода он
## больше не описывает (решение 10.2026), а в файлах лежит годами.
static func drop_legacy_guest() -> void:
	var cfg := _cfg()
	var touched := false
	if cfg.has_section_key(SECTION_PROFILES, "guest"):
		cfg.erase_section_key(SECTION_PROFILES, "guest")
		if get_last_user() == "guest":
			cfg.set_value(SECTION_LAST, KEY_LAST_USER, GUEST)
		touched = true
	if cfg.has_section_key(SECTION_DISPLAY, "sys_kb"):
		cfg.erase_section_key(SECTION_DISPLAY, "sys_kb")
		touched = true
	if touched:
		cfg.save(PATH)


static func wipe() -> void:
	var cfg := ConfigFile.new()
	cfg.save(PATH)
