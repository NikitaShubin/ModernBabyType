#!/bin/sh
# Обёртка над движком для контейнера сборки. Ставится как ENTRYPOINT
# образа, поэтому вызывается на месте `godot`:
#
#   docker run ... mbt-godot --headless --path game --script res://tests/logic_test.gd
#
# Зачем она: три вещи, без которых экспорт на всех платформах не
# проходит, а делать их в скриптах CI значит тащить их в каждый вызов.
#
# 1) editor_settings-4.3.tres: пути к rcedit, wine, JDK и Android SDK.
#    Godot берёт их оттуда при экспорте и при отсутствии НЕ ругается —
#    молча собирает .exe с иконкой движка и версией 0.0.0. Проверено на
#    собственном билде. Ключи из этих путей диктует контейнер, поэтому
#    они перезаписываются, а остальные настройки редактора не трогаются.
#
# 2) Переменные GODOT_ANDROID_KEYSTORE_* с путём к ключу подписи.
#    Android требует подписи даже для --export-release, и для релиза
#    Godot берёт ключ НЕ из настроек редактора, а из пресета
#    (keystore/release) либо из переменной окружения — см.
#    EditorExportPlatformAndroid::_get_keystore_path() и sign_apk() в
#    Godot 4.3. Пресет в репозитории остаётся переносимым (путь ключа
#    на машине разработчика свой), а контейнер подставляет свой.
#
# 3) debug-keystore в /opt/mbt. Своего ключа у проекта нет и быть не
#    должно: в репозиторий ключи не кладут. Ключ генерируется при
#    сборке образа и лежит в образе — в репозиторий и в артефакты
#    релиза не попадает. Отладочный ключ по определению несекретный:
#    чужим ключом в Google Play подпись не пройдёт, для публикации
#    нужен свой, см. README.
#
# Пути к rcedit и wine можно переопределить GODOT_RCEDIT / GODOT_WINE:
# в barichello/godot-ci лежат свои, путь может отличаться.
#
# Скрипт зовётся на каждом docker run, поэтому должен быть идемпотентным
# и дешёвым: перезаписывает только своё, остальное не трогает.
set -eu

: "${HOME:=/home/agent}"
SETTINGS_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/godot"
SETTINGS="$SETTINGS_DIR/editor_settings-4.3.tres"
# Ключ лежит в образе и не зависит от HOME: примонтированный каталог на
# Windows-диске выглядит принадлежащим root, и часть инструментов
# (например wine) на таком отказывается работать.
KEYSTORE="${MBT_KEYSTORE:-/opt/mbt/debug.keystore}"
KEY_ALIAS="${MBT_KEY_ALIAS:-androiddebugkey}"
KEY_PASS="${MBT_KEY_PASS:-android}"
RCEDIT="${GODOT_RCEDIT:-/opt/rcedit.exe}"
WINE="${GODOT_WINE:-/usr/bin/wine64-stable}"
ANDROID_SDK="${MBT_ANDROID_SDK:-${ANDROID_HOME:-/usr/lib/android-sdk}}"

have() { command -v "$1" >/dev/null 2>&1; }

# Заменить ключ в .tres или дописать в конец. Именно замена, а не
# «если нет»: пустой или хостовый путь в ключе ломает экспорт молча,
# и это ровно тот случай, из-за которого скрипт и нужен.
set_key() {
	key="$1"
	value="$2"
	if grep -q "^$key " "$SETTINGS" 2>/dev/null; then
		tmp="$SETTINGS.mbt.$$"
		sed "s|^$key .*|$key = $value|" "$SETTINGS" >"$tmp"
		mv "$tmp" "$SETTINGS"
	else
		printf '%s = %s\n' "$key" "$value" >>"$SETTINGS"
	fi
}

ensure_settings() {
	mkdir -p "$SETTINGS_DIR"
	[ -f "$SETTINGS" ] || : >"$SETTINGS"
	set_key "export/windows/rcedit" "\"$RCEDIT\""
	set_key "export/windows/wine" "\"$WINE\""
	if have java; then
		JAVA_HOME_GUESS="$(dirname "$(dirname "$(readlink -f "$(command -v java)")")")"
		set_key "export/android/java_sdk_path" "\"$JAVA_HOME_GUESS\""
	fi
	if [ -d "$ANDROID_SDK" ]; then
		set_key "export/android/android_sdk_path" "\"$ANDROID_SDK\""
	fi
}

ensure_debug_keystore() {
	[ -f "$KEYSTORE" ] && return 0
	have keytool || return 0
	mkdir -p "$(dirname "$KEYSTORE")"
	# -storepass/-keypass и -alias/-dname обязательны. Срок 10000 дней:
	# отладочный ключ не должен истечь и не должен спорить с системным.
	keytool -genkeypair \
		-keystore "$KEYSTORE" \
		-alias "$KEY_ALIAS" \
		-keyalg RSA -keysize 2048 -validity 10000 \
		-storepass "$KEY_PASS" -keypass "$KEY_PASS" \
		-dname "CN=ModernBabyType Debug, OU=Dev, O=ModernBabyType, L=Nowhere, ST=Nowhere, C=XX" \
		>/dev/null 2>&1 || {
		echo "mbt-godot: не смог создать keystore $KEYSTORE" >&2
		return 1
	}
}

# Ключ подписи для обеих сборок. Godot читает GODOT_ANDROID_KEYSTORE_*
# только когда соответствующий ключ пуст в пресете: в репозитории он
# пуст, иначе путь из контейнера уехал бы в пресет на машину
# разработчика. Экспортируем, а не пишем в настройки редактора: для
# релиза настройки не спасают (см. пункт 2 в шапке).
export_keystore_env() {
	GODOT_ANDROID_KEYSTORE_DEBUG_PATH="$KEYSTORE"
	GODOT_ANDROID_KEYSTORE_DEBUG_USER="$KEY_ALIAS"
	GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD="$KEY_PASS"
	GODOT_ANDROID_KEYSTORE_RELEASE_PATH="$KEYSTORE"
	GODOT_ANDROID_KEYSTORE_RELEASE_USER="$KEY_ALIAS"
	GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD="$KEY_PASS"
	export GODOT_ANDROID_KEYSTORE_DEBUG_PATH GODOT_ANDROID_KEYSTORE_DEBUG_USER \
		GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD GODOT_ANDROID_KEYSTORE_RELEASE_PATH \
		GODOT_ANDROID_KEYSTORE_RELEASE_USER GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD
}

ensure_debug_keystore
ensure_settings
export_keystore_env

# Дальше — чистый godot со всеми аргументами как есть.
if have godot; then
	exec godot "$@"
fi
for candidate in /usr/local/bin/godot /opt/godot/godot; do
	[ -x "$candidate" ] && exec "$candidate" "$@"
done
echo "mbt-godot: движок godot не найден в образе" >&2
exit 127
