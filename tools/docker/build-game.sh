#!/usr/bin/env bash
# Сборка, тесты и съёмка кадров игры в контейнере.
# Движок, export templates, Android SDK, Mesa и rcedit живут только в
# образе — в систему (/usr, apt) ничего не ставится.
#
#   tools/docker/build-game.sh --test-only   # импорт + все тесты
#   tools/docker/build-game.sh --all         # тесты + экспорт 4 платформ
#   tools/docker/build-game.sh --shot        # кадры анимации в /tmp/opencode
#   tools/docker/build-game.sh --preset NAME # только экспорт одного пресета
#
# Образ тот же, что в .github/workflows/release.yml: правила сборки не
# должны расходиться между машиной автора и CI.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
IMAGE="${GODOT_IMAGE:-mbt-godot}"
MODE="${1:---all}"
UID_GID="$(id -u):$(id -g)"

# HOME внутри контейнера — во временном каталоге, а не в примонтированном
# tools/home: wine (нужен rcedit для иконки в .exe) отказывается работать
# в каталоге, который ему не принадлежит, а примонтированные с хоста
# каталоги на Windows-диске выглядят принадлежащими root. Настройки
# редактора и export templates берём из примонтированного по XDG —
# они лежат именно там, где Godot их ищет.
mkdir -p "$ROOT/tools/home" /tmp/opencode

# Сборка образа идёт из закоммиченного Dockerfile — тот же, что и в CI,
# поэтому правила не расходятся. Хвост вывода оставляем, чтобы в логе
# было видно, какой образ и из чего получился; подробности сборки Godot
# и apt при такой сборке всё равно кэшированные.
docker build -t "$IMAGE" -f "$ROOT/tools/docker/Dockerfile" "$ROOT/tools/docker" 2>&1 | tail -n 4

run_godot() {
	# --timeout SECONDS перед остальными аргументами — потолок по
	# времени на один запуск движка (нужно тестам: см. run_test).
	local secs=""
	if [ "${1:-}" = "--timeout" ]; then
		secs="$2"
		shift 2
	fi
	# Локальные переопределения — только если каталоги есть: на машине
	# автора SDK и кэш gradle лежат в tools/ (в git не входят), а в CI
	# их нет и должны работать умолчания образа. Безусловный -e с
	# несуществующим путём ломал бы gradle-сборку в CI.
	local extra_env=()
	if [ -d "$ROOT/tools/gradle-home" ]; then
		extra_env+=(-e "GRADLE_USER_HOME=/work/tools/gradle-home")
	fi
	if [ -d "$ROOT/tools/emulator/sdk" ]; then
		extra_env+=(-e "ANDROID_HOME=/work/tools/emulator/sdk")
		extra_env+=(-e "ANDROID_SDK_ROOT=/work/tools/emulator/sdk")
	fi
	local cmd=(docker run --rm
		--user "$UID_GID"
		-v "$ROOT:/work"
		-v "$ROOT/tools/home:/home/agent"
		-v /tmp/.X11-unix:/tmp/.X11-unix
		-v /tmp/opencode:/tmp/opencode
		-e HOME=/tmp/mbt-home
		-e WINEPREFIX=/tmp/mbt-home/.wine
		-e XDG_CONFIG_HOME=/home/agent/.config
		-e XDG_DATA_HOME=/home/agent/.local/share
		-e DISPLAY="${DISPLAY:-:99}"
		-e MBT_KEYSTORE="${MBT_KEYSTORE:-}"
		-e MBT_KEY_ALIAS="${MBT_KEY_ALIAS:-}"
		-e MBT_KEY_PASS="${MBT_KEY_PASS:-}"
		"${extra_env[@]}"
		-w /work)
	# Имя нужно только тестам: сторож в run_test снимает контейнер по
	# имени, убийство локального docker-клиента контейнер не гасит
	# (правило §5 AGENTS.md: зависший godot жил 15 часов).
	if [ -n "${MBT_CONTAINER_NAME:-}" ]; then
		cmd+=(--name "$MBT_CONTAINER_NAME")
	fi
	cmd+=("$IMAGE" "$@")
	if [ -n "$secs" ]; then
		# --foreground: иначе timeout не убьёт группу движка и контейнер
		# останется висеть после «упавшего» теста (правило §5 AGENTS.md).
		timeout --foreground -k 10 "$secs" "${cmd[@]}"
	else
		"${cmd[@]}"
	fi
}

# Произвольная команда в том же контейнере (без обёртки движка):
# нужна для подготовки gradle-шаблона — Godot её не делает сам.
run_sh() {
	local extra_env=()
	if [ -d "$ROOT/tools/gradle-home" ]; then
		extra_env+=(-e "GRADLE_USER_HOME=/work/tools/gradle-home")
	fi
	if [ -d "$ROOT/tools/emulator/sdk" ]; then
		extra_env+=(-e "ANDROID_HOME=/work/tools/emulator/sdk")
		extra_env+=(-e "ANDROID_SDK_ROOT=/work/tools/emulator/sdk")
	fi
	docker run --rm \
		--user "$UID_GID" \
		-v "$ROOT:/work" \
		-v "$ROOT/tools/home:/home/agent" \
		-e HOME=/tmp/mbt-home \
		-w /work \
		--entrypoint "$1" \
		"$IMAGE" "${@:2}"
}

# Gradle-шаблон Android (game/android/build) в репозиторий НЕ входит:
# генерированное (90МБ godot-lib, ассеты, .import-мусор). Перед первым
# Android-экспортом разворачиваем его из android_source.zip образа,
# кладём наш AAR плагина MbtInstall и помечаем версию шаблона.
# Идемпотентно: если каталог уже есть (машина автора), только
# обновляем AAR и метки. Без этого экспорт падает «no version info»
# или давится дублями классов из build/assets.
ensure_android_build() {
	run_sh sh -c '
		set -eu
		if [ ! -f /work/game/android/build/build.gradle ]; then
			tpl=""
			for d in /home/agent/.local/share/godot/export_templates /root/.local/share/godot/export_templates; do
				if [ -f "$d/4.3.stable/android_source.zip" ]; then tpl="$d/4.3.stable/android_source.zip"; break; fi
			done
			if [ -z "$tpl" ]; then echo "ensure_android_build: нет android_source.zip" >&2; exit 3; fi
			mkdir -p /work/game/android/build
			unzip -q -o "$tpl" -d /work/game/android/build
		fi
		mkdir -p /work/game/android/build/libs/release /work/game/android/build/libs/debug
		cp -f /work/tools/plugin/mbt-install/aar/MbtInstall.release.aar /work/game/android/build/libs/release/MbtInstall.aar
		cp -f /work/tools/plugin/mbt-install/aar/MbtInstall.debug.aar /work/game/android/build/libs/debug/MbtInstall.aar
		echo "4.3.stable" > /work/game/android/.build_version
		touch /work/game/android/build/.gdignore
		find /work/game/android/build/res -name "*.import" -delete 2>/dev/null || true
		# Недостающие пакеты шаблона (platforms;android-34,
		# build-tools;34.0.0): в образе их нет, gradle без них падает
		# «Failed to install the following SDK components» (CI 10.2026).
		# Ставим заранее через sdkmanager: лицензии — yes, сеть в CI есть.
		# SDK пишемый для всех (см. Dockerfile chmod), иначе та же
		# ошибка уже на записи. Локально пакеты уже стоят — шаг пустой.
		for s in /usr/lib/android-sdk /opt/android-sdk /sdk "${ANDROID_HOME:-}" "${ANDROID_SDK_ROOT:-}"; do
			if [ -n "$s" ] && [ -d "$s/cmdline-tools" ]; then SDK="$s"; break; fi
		done
		if [ -n "${SDK:-}" ]; then
			SM="$(find "$SDK/cmdline-tools" -maxdepth 3 -name sdkmanager -type f 2>/dev/null | head -1)"
			if [ -n "${SM:-}" ]; then
				yes 2>/dev/null | sh "$SM" --sdk_root="$SDK" --licenses >/dev/null 2>&1 || true
				sh "$SM" --sdk_root="$SDK" "platforms;android-34" "build-tools;34.0.0" >/dev/null 2>&1 || true
			fi
		fi
	'
}

# Все пять тестов обязательны: логика ввода, обновление, проходимость
# уровня, профили игроков, инвариант погони. Тест, который ни разу не
# падает на сломанном коде, бесполезен: правя геометрию погони,
# сначала ломаем правило руками, убеждаемся, что CHASE_TEST это ловит,
# и только потом ставим исправленное.
run_tests() {
	run_godot --headless --path game --import
	run_test logic_test.gd
	run_test update_test.gd
	run_test end_test.gd
	run_test profiles_test.gd
	# Погоня гоняет живой цикл кадр за кадром — самый долгий тест.
	run_test chase_test.gd 1800
}

# Один тест под предохранителями.
#
# Сырой запуск движка опасен: тест, у которого на каждый кадр летит
# SCRIPT ERROR (забыли синхронизировать константу с кодом), сам НЕ
# падает — сценарий молча крутится до лимита кадров. Именно так прогон
# CI 09.10.2026 висел 2 часа 9 минут: chase_test.gd в репозитории ещё
# держал SNAP_CAP_CHARS, которого в main.gd уже не было. Сторож
# смотрит лог на лету и снимает контейнер, как только ошибка пошла
# (плюс потолок по времени на случай тихого зацикливания).
# Лог каждого теста остаётся в /tmp/opencode/<имя>.log.
run_test() {
	local script="$1"
	local limit="${2:-600}"
	local name="mbt-test-$(basename "$script" .gd)-$$"
	local log="/tmp/opencode/$(basename "$script" .gd).log"
	: >"$log"
	docker rm -f "$name" >/dev/null 2>&1 || true
	MBT_CONTAINER_NAME="$name" run_godot --headless --path game \
		--script "res://tests/$script" >"$log" 2>&1 &
	local pid=$!
	local waited=0 killed=""
	while kill -0 "$pid" 2>/dev/null; do
		if grep -q "SCRIPT ERROR" "$log"; then
			killed="ошибки скрипта"
			docker rm -f "$name" >/dev/null 2>&1 || true
			break
		fi
		if [ "$waited" -ge "$limit" ]; then
			killed="превышено ${limit}s"
			docker rm -f "$name" >/dev/null 2>&1 || true
			break
		fi
		sleep 5
		waited=$((waited + 5))
	done
	wait "$pid" || true
	docker rm -f "$name" >/dev/null 2>&1 || true
	grep -E "_TEST: " "$log" | head -n 20 || true
	if [ -n "$killed" ]; then
		echo "ТЕСТ $script: снят сторожем ($killed), последние строки:" >&2
		tail -n 20 "$log" >&2
		return 1
	fi
	if [ -s "$log" ] && ! grep -qE "_TEST: PASS" "$log"; then
		echo "ТЕСТ $script: нет строки PASS, последние строки:" >&2
		tail -n 20 "$log" >&2
		return 1
	fi
}

run_tests() {
	run_godot --headless --path game --import
	run_test logic_test.gd
	run_test update_test.gd
	run_test end_test.gd
	run_test profiles_test.gd
	# Погоня гоняет живой цикл кадр за кадром — самый долгий тест.
	run_test chase_test.gd 1800
}

# Пресеты в том порядке, в каком они лежат в export_presets.cfg.
PRESETS=(Windows Linux macOS Android)

run_exports() {
	if [ "$#" -gt 0 ]; then
		PRESETS=("$@")
	fi
	# Gradle-шаблон нужен только Android-пресетам — остальным он лишний.
	for preset in "${PRESETS[@]}"; do
		case "$preset" in
		Android*) ensure_android_build; break ;;
		esac
	done
	# game/dist в git не входит (см. .gitignore): на чистом раннере его
	# нет, а Godot не создаёт каталог под файл экспорта и падает
	# «The given export path doesn't exist».
	mkdir -p game/dist
	for preset in "${PRESETS[@]}"; do
		echo "--- экспорт: $preset"
		case "$preset" in
		Windows) out=dist/ModernBabyType.exe ;;
		Linux) out=dist/ModernBabyType.x86_64 ;;
		macOS) out=dist/ModernBabyType.zip ;;
		Android) out=dist/ModernBabyType.apk ;;
		AndroidEmu) out=dist/ModernBabyType.emu.apk ;;
		*) echo "неизвестный пресет: $preset" >&2; exit 2 ;;
		esac
		run_godot --headless --path game --export-release "$preset" "$out"
		if [ "$preset" = "Android" ]; then
			# apksigner рядом с .apk кладёт подпись v4 (idsig) — она для
			# установки через adb, а не для раздачи людям. В релиз не
			# попадает, иначе в артефактах лишний файл.
			rm -f "game/$out.idsig"
		fi
	done
}

case "$MODE" in
--test-only)
	run_tests
	;;
--shot)
	# Нужен настоящий OpenGL, поэтому окно, а не --headless: фиктивный
	# рендерер отдаёт null вместо картинки.
	run_godot --path game --script res://tests/shot_driver.gd
	ls -la /tmp/opencode/*.png
	;;
--preset)
	shift
	run_godot --headless --path game --import
	run_exports "$@"
	ls -la game/dist/
	;;
--all)
	run_tests
	run_exports
	ls -la game/dist/
	;;
*)
	echo "неизвестный режим: $MODE" >&2
	exit 2
	;;
esac