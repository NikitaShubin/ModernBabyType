extends SceneTree
## Тесты самообновления: только чистые функции (версии, выбор ассета,
## текст стейджера). Сеть не трогаем — хрупко и недетерминированно.
## Запуск: godot --headless --path game --script res://tests/update_test.gd

const U := preload("res://scripts/update.gd")

var _failures: Array[String] = []


func _check(cond: bool, what: String) -> void:
	if not cond:
		_failures.append(what)


func _initialize() -> void:
	_check(U.parse_version("v0.0.10") == [0, 0, 10], "tag parses")
	_check(U.parse_version("0.0.9") == [0, 0, 9], "plain parses")
	_check(U.parse_version("v1.2") == [1, 2, 0], "short pads")
	_check(U.is_newer("0.0.9", "v0.0.10"), "patch newer wins")
	_check(not U.is_newer("0.0.10", "v0.0.10"), "equal is not newer")
	_check(not U.is_newer("0.1.0", "v0.0.10"), "older minor loses")
	_check(U.is_newer("0.0.9", "v0.1.0"), "newer minor wins")
	_check(U.is_newer("0.0.9", "v1.0.0"), "newer major wins")
	var assets := [
		{"name": "ModernBabyType.x86_64", "browser_download_url": "http://x/1"},
		{"name": "ModernBabyType.apk", "browser_download_url": "http://x/2"},
	]
	_check(U.pick_asset(assets, "ModernBabyType.apk") == "http://x/2", "apk picked")
	_check(U.pick_asset(assets, "nope") == "", "missing asset is empty")
	_check(U.pick_asset([], "ModernBabyType.apk") == "", "empty list is empty")
	_check(U.short_notes("# H\n\na\n\nb") == "a\nb", "notes skip headers and blanks")
	# Ссылка и markdown в карточке — мусор: ссылка ещё и не влезает.
	_check(
		U.short_notes("**Full Changelog**: https://github.com/a/b") == "",
		"notes drop the changelog link"
	)
	_check(U.short_notes("* пункт один") == "пункт один", "notes drop markdown stars")
	# Диаг-сборки: максимальный номер из кучи имён.
	# Нативный мост: на десктопе плагина нет — всегда false, откат
	# на штатный путь (браузер/перезапуск). Живой плагин — только
	# на устройстве (эмулятор/телефон).
	_check(not Mbt.has_plugin(), "no plugin on desktop")
	_check(not Mbt.install_apk("/nope.apk"), "install refuses without plugin")
	_check(not Mbt.share_file("/nope.txt"), "share refuses without plugin")
	# Повторное нажатие «Загрузить» во время закачки: второй запрос
	# сбивал первый (жалоба автора 10.2026). Пока HTTPRequest занят —
	# повтор игнорируется, закачка не перезапускается. Проверяем
	# состояние и читаемость размеров (их берёт полоска прогресса).
	var up := U.new()
	_check(not up.downloading(), "no download is running at start")
	_check(up.total_bytes() >= 0, "total size is readable")
	_check(up.done_bytes() >= 0, "downloaded size is readable")

	# Самообновление есть ровно там, где игра умеет заменить себя сама.
	_check(
		U.self_installs() == (OS.get_name() == "Linux" or OS.get_name() == "Windows"),
		"self_installs matches the platform"
	)
	var st := U._stager_text("C:/g/new.exe", "C:/g/game.exe")
	_check("tasklist" in st, "stager waits for the pid")
	_check("move /Y" in st, "stager swaps the exe")
	_check("C:/g/new.exe" in st and "C:/g/game.exe" in st, "stager paths inside")
	_check("del " in st, "stager deletes itself")
	_check("if errorlevel 1 goto failed" in st, "stager reports a failed swap")
	# cmd не понимает UTF-8 в .bat: не-ASCII в стейджере быть не должно.
	var ascii_ok := true
	for i in st.length():
		if st.unicode_at(i) > 127:
			ascii_ok = false
			break
	_check(ascii_ok, "stager is pure ASCII")
	_report()


func _report() -> void:
	if _failures.is_empty():
		print("UPDATE_TEST: PASS")
	else:
		for f in _failures:
			print("UPDATE_TEST: FAIL: ", f)
	quit(1 if not _failures.is_empty() else 0)
