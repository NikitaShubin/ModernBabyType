class_name Mbt
extends RefCounted
## Мост к нативному плагину MbtInstall (Android): установка APK и шаринг
## файлов. На остальных платформах и без плагина — всегда false, вызыватель
## откатывается на штатный путь (браузер/перезапуск). Методы плагина —
## installApk(path), shareFile(path, mime); пути — глобальные системные.
static func has_plugin() -> bool:
	if OS.get_name() != "Android":
		return false
	return Engine.has_singleton("MbtInstall")


static func install_apk(sys_path: String) -> bool:
	if not has_plugin():
		return false
	Engine.get_singleton("MbtInstall").installApk(sys_path)
	return true


static func share_file(sys_path: String, mime := "text/plain") -> bool:
	if not has_plugin():
		return false
	Engine.get_singleton("MbtInstall").shareFile(sys_path, mime)
	return true
