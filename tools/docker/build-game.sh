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
	docker run --rm \
		--user "$UID_GID" \
		-v "$ROOT:/work" \
		-v "$ROOT/tools/home:/home/agent" \
		-v /tmp/.X11-unix:/tmp/.X11-unix \
		-v /tmp/opencode:/tmp/opencode \
		-e HOME=/tmp/mbt-home \
		-e WINEPREFIX=/tmp/mbt-home/.wine \
		-e XDG_CONFIG_HOME=/home/agent/.config \
		-e XDG_DATA_HOME=/home/agent/.local/share \
		-e DISPLAY="${DISPLAY:-:99}" \
		-e MBT_KEYSTORE="${MBT_KEYSTORE:-}" \
		-e MBT_KEY_ALIAS="${MBT_KEY_ALIAS:-}" \
		-e MBT_KEY_PASS="${MBT_KEY_PASS:-}" \
		"${extra_env[@]}" \
		-w /work \
		"$IMAGE" "$@"
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
	'
}

# Все пять тестов обязательны: логика ввода, обновление, проходимость
# уровня, профили игроков, инвариант погони. Тест, который ни разу не
# падает на сломанном коде, бесполезен: правя геометрию погони,
# сначала ломаем правило руками, убеждаемся, что CHASE_TEST это ловит,
# и только потом ставим исправленное.
run_tests() {
	run_godot --headless --path game --import
	run_godot --headless --path game --script res://tests/logic_test.gd
	run_godot --headless --path game --script res://tests/update_test.gd
	run_godot --headless --path game --script res://tests/end_test.gd
	run_godot --headless --path game --script res://tests/profiles_test.gd
	run_godot --headless --path game --script res://tests/chase_test.gd
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