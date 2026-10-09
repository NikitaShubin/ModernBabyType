class_name Updater
extends Node
## Проверка обновлений и закачка релизов с GitHub. Только по кнопке
## «Проверить обновления» — никакой фоновой магии: для удобства
## хватает ручной проверки, а не автомата.
##
## Поток: check() → сигнал checked(ok, tag, notes, url). Если есть
## новее — меню спрашивает «Скачать и установить?» → download(url)
## (сигналы progress/downloaded) → platform_install(path).
## Дальше — дело платформы (см. _install_linux/_install_windows,
## на Android — передача в браузер: свой установщик без плагина
## невозможен, а браузер скачает и позовёт системный установщик сам).
##
## Чистые функции (parse/compare/pick) — статики, их гоняет
## tests/update_test.gd. Сеть в тестах не трогаем (хрупко).

signal checked(ok: bool, tag: String, notes: String, url: String)
signal downloaded(path: String)
signal failed(what: String)
## Прогресс закачки: (скачано байт, всего байт, процент). Процент < 0 —
## размер ещё неизвестен (сервер не прислал Content-Length).
signal progress(done: int, total: int, percent: int)

const REPO := "NikitaShubin/ModernBabyType"
const API_LATEST := "https://api.github.com/repos/" + REPO + "/releases/latest"

var _http: HTTPRequest
var _dl: HTTPRequest
var _pending_tag := ""
var _pending_notes := ""
var _pending_url := ""


static func current_version() -> String:
	return ProjectSettings.get_setting("application/config/version", "0.0.0")


## "v0.0.10" -> [0, 0, 10]. Мусор вокруг цифр игнорируем.
static func parse_version(v: String) -> Array[int]:
	var out: Array[int] = []
	var cur := ""
	for i in v.length():
		var ch := v[i]
		if ch >= "0" and ch <= "9":
			cur += ch
		elif not cur.is_empty():
			out.append(int(cur))
			cur = ""
	if not cur.is_empty():
		out.append(int(cur))
	while out.size() < 3:
		out.append(0)
	return out.slice(0, 3)


## True, если distant новее local. Сравнение по сегментам.
static func is_newer(local: String, distant: String) -> bool:
	var a := parse_version(local)
	var b := parse_version(distant)
	for i in 3:
		if b[i] != a[i]:
			return b[i] > a[i]
	return false


## Имя ассета под платформу. Пусто — платформа не поддерживается.
static func asset_name() -> String:
	match OS.get_name():
		"Linux":
			return "ModernBabyType.x86_64"
		"Windows":
			return "ModernBabyType.exe"
		"Android":
			return "ModernBabyType.apk"
	return ""


## Выбрать URL закачки из списка ассетов релиза (asset[] словари
## с name/browser_download_url). Пусто — нет подходящего.
static func pick_asset(assets: Array, want: String) -> String:
	for a in assets:
		if a is Dictionary and String(a.get("name", "")) == want:
			return String(a.get("browser_download_url", ""))
	return ""


## Короткие первые строки changelog для диалога. Служебные строки
## (заголовки, «Full Changelog: ссылка») выкидываем: в карточке это
## шум, а ссылка вдобавок не влезает по ширине. Markdown-маркеры
## снимаем — в игре их видно как мусор.
static func short_notes(body: String, max_lines := 4) -> String:
	var lines: Array[String] = []
	for ln in body.split("\n"):
		var t := ln.strip_edges()
		if t.is_empty() or t.begins_with("#"):
			continue
		if t.find("http://") >= 0 or t.find("https://") >= 0:
			continue
		t = t.trim_prefix("*").trim_prefix("-").strip_edges()
		if t.is_empty():
			continue
		lines.append(t)
		if lines.size() >= max_lines:
			break
	return "\n".join(lines)


func _ready() -> void:
	_http = HTTPRequest.new()
	# Таймаут обязателен: иначе висящая сеть оставит «Проверяю…» навсегда.
	_http.timeout = 20.0
	add_child(_http)
	_http.request_completed.connect(_on_checked)
	_dl = HTTPRequest.new()
	_dl.timeout = 900.0
	add_child(_dl)
	_dl.request_completed.connect(_on_downloaded)


## True, если платформа ставит обновление сама (свой бинарь рядом).
## На Android — нет: свой установщик без нативного плагина невозможен,
## отдаём URL браузеру (см. download).
static func self_installs() -> bool:
	return OS.get_name() == "Linux" or OS.get_name() == "Windows"


## Спросить GitHub о последнем релизе.
func check() -> void:
	_pending_tag = ""
	_pending_notes = ""
	_pending_url = ""
	var err := _http.request(API_LATEST, ["User-Agent: ModernBabyType"])
	if err != OK:
		failed.emit("нет сети")
		return


func _on_checked(_result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if code != 200:
		failed.emit("GitHub молчит (%d)" % code)
		return
	var data: Dictionary = JSON.parse_string(body.get_string_from_utf8())
	if data.is_empty():
		failed.emit("непонятный ответ")
		return
	var tag := String(data.get("tag_name", ""))
	var want := asset_name()
	if want.is_empty():
		failed.emit("эта платформа сама не обновляется")
		return
	var url := pick_asset(data.get("assets", []), want)
	if tag.is_empty() or url.is_empty():
		failed.emit("в релизе нет файла для нас")
		return
	if not is_newer(current_version(), tag):
		checked.emit(false, tag, "", "")
		return
	_pending_tag = tag
	_pending_notes = short_notes(String(data.get("body", "")))
	_pending_url = url
	checked.emit(true, tag, _pending_notes, url)


## Качать pending-URL в user://updates/. Имя файла — из URL.
## Android с плагином: качаем сами во внутренний каталог и зовём
## системный установщик (флоу «Загрузить → Установить» из игры).
## Android без плагина (старые сборки): отдаём ссылку браузеру.
func download() -> void:
	if _pending_url.is_empty():
		failed.emit("нечего качать")
		return
	# Повторное нажатие «Загрузить» во время закачки сбивало HTTPRequest
	# (жалоба автора 10.2026: «закачка сбоит, если нажать обновление в
	# процессе закачки»). Второй запрос не начинаем — просто молчим.
	if downloading():
		progress.emit(_dl.get_downloaded_bytes(), _dl.get_body_size(), -1)
		return
	if OS.get_name() == "Android" and Mbt.has_plugin():
		DirAccess.make_dir_recursive_absolute("user://updates")
		var fname := _pending_url.get_file()
		_dl.download_file = "user://updates/" + fname
		var err := _dl.request(_pending_url, ["User-Agent: ModernBabyType"])
		if err != OK:
			failed.emit("закачка не стартовала")
		return
	if not self_installs():
		# Android без плагина: качать своё бессмысленно — файл всё равно
		# ставит система через браузер. Отдаём ссылку и молчим.
		OS.shell_open(_pending_url)
		downloaded.emit("")
		return
	DirAccess.make_dir_recursive_absolute("user://updates")
	var fname2 := _pending_url.get_file()
	_dl.download_file = "user://updates/" + fname2
	var err2 := _dl.request(_pending_url, ["User-Agent: ModernBabyType"])
	if err2 != OK:
		failed.emit("закачка не стартовала")


## Идёт ли сейчас закачка. До _ready (_dl ещё нет) — спокойно false:
## иначе прямой вызов из теста роняет игру (падало в CI 10.2026).
func downloading() -> bool:
	if _dl == null:
		return false
	return _dl.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED


## Размер заказанного файла (0 — сервер не прислал).
func total_bytes() -> int:
	if _dl == null:
		return 0
	return _dl.get_body_size()


## Сколько уже скачано.
func done_bytes() -> int:
	if _dl == null:
		return 0
	return _dl.get_downloaded_bytes()


func _on_downloaded(_result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	if code != 200:
		failed.emit("оборвалось (%d)" % code)
		return
	var path: String = ProjectSettings.globalize_path("user://updates/" + _pending_url.get_file())
	if OS.get_name() == "Android" and Mbt.has_plugin():
		# Файл скачан самими — зовём системный установщик прямо из игры.
		# Дальше штатный диалог «Установить» (молча ставить запрещено).
		if Mbt.install_apk(path):
			downloaded.emit(path)
		else:
			failed.emit("установщик не открылся")
		return
	_platform_install(path)


## Дальше — дело платформы (сюда попадают только self_installs).
func _platform_install(path: String) -> void:
	match OS.get_name():
		"Linux":
			_install_linux(path)
		"Windows":
			_install_windows(path)
		_:
			failed.emit("эта платформа сама не обновляется")


## Linux: подмена бинаря на месте (rename переживает занятый файл),
## запуск нового, выход. Если каталог только для чтения — новый
## остаётся в закачке, запускаем оттуда и ругаемся в лог.
func _install_linux(path: String) -> void:
	var exe := OS.get_executable_path()
	var target := exe
	var staged := exe + ".new"
	DirAccess.copy_absolute(path, staged)
	if FileAccess.file_exists(staged):
		# rename атомарен и не смотрит на занятость старого inode.
		var derr := DirAccess.rename_absolute(staged, exe)
		if derr == OK:
			target = exe
		else:
			push_warning("ModernBabyType: не заменил %s (%d)" % [exe, derr])
	else:
		push_warning("ModernBabyType: не скопировал закачку в %s" % staged)
		target = path
	OS.execute("chmod", ["+x", target])
	OS.execute(target, [])
	downloaded.emit(target)
	get_tree().quit()


## Windows: бегущий .exe занят — пишет .bat-стейджер рядом.
## Стейджер ждёт выход игры, меняет файлы, стартует новую,
## удаляется сам. Текст батника — чистая генерация (тестируется
## без запуска): _stager_text().
func _install_windows(path: String) -> void:
	var exe_dir := OS.get_executable_path().get_base_dir()
	var bat := exe_dir + "/mbt_update.bat"
	var f := FileAccess.open(bat, FileAccess.WRITE)
	if f == null:
		failed.emit("не пишу стейджер")
		return
	f.store_string(_stager_text(path, OS.get_executable_path()))
	f.close()
	# .bat через CreateProcess не запускается — нужен cmd /c.
	OS.execute("cmd", ["/c", bat])
	downloaded.emit(path)
	get_tree().quit()


## Текст windows-стейджера: ждёт PID игры, подменяет exe, стартует.
## Только ASCII: cmd читает .bat в OEM-кодировке, UTF-8 превращается
## в мусор. Сообщения пользователю — по-английски, это единственная
## строка, которую он увидит, если замена не удалась.
static func _stager_text(new_path: String, exe_path: String) -> String:
	var pid := OS.get_process_id()
	var lines := [
		"@echo off",
		"rem ModernBabyType updater: wait for the game to exit, swap exe.",
		":waitloop",
		"tasklist /FI \"PID eq %d\" 2>NUL | find \"%d\" >NUL" % [pid, pid],
		"if not errorlevel 1 goto waitloop",
		"timeout /t 1 /nobreak >NUL",
		"move /Y \"%s\" \"%s\"" % [new_path, exe_path],
		"if errorlevel 1 goto failed",
		"start \"\" \"%s\"" % exe_path,
		"del \"%~f0\"",
		"exit /b 0",
		":failed",
		"echo Could not replace the game file.",
		"echo Copy it by hand from: %s" % new_path,
		"pause",
		"del \"%~f0\"",
	]
	return "\n".join(lines) + "\n"
