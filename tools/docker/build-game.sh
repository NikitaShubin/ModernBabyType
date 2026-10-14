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
	# Домашний каталог и XDG можно переопределить на тест
	# (MBT_HOME): параллельные тесты не должны делить user://-профили
	# (гость, сохранения уровней) — иначе чтения/записи гоняются.
	local mbt_home="${MBT_HOME:-/tmp/mbt-home}"
	local mbt_cfg="${MBT_XDG_CONFIG:-/home/agent/.config}"
	local mbt_data="${MBT_XDG_DATA:-/home/agent/.local/share}"
	local cmd=(docker run --rm
		--user "$UID_GID"
		-v "$ROOT:/work"
		-v "$ROOT/tools/home:/home/agent"
		-v /tmp/.X11-unix:/tmp/.X11-unix
		-v /tmp/opencode:/tmp/opencode
		-e HOME="$mbt_home"
		-e WINEPREFIX="$mbt_home/.wine"
		-e XDG_CONFIG_HOME="$mbt_cfg"
		-e XDG_DATA_HOME="$mbt_data"
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
	local base
	base="$(basename "$script" .gd)"
	local name="mbt-test-$base-$$"
	local log="/tmp/opencode/$base.log"
	: >"$log"
	docker rm -f "$name" >/dev/null 2>&1 || true
	MBT_CONTAINER_NAME="$name" \
	MBT_HOME="/tmp/mbt-home-$base" \
	MBT_XDG_CONFIG="/tmp/mbt-home-$base/.config" \
	MBT_XDG_DATA="/tmp/mbt-home-$base/.local/share" \
	run_godot --headless --path game \
		--script "res://tests/$script" >"$log" 2>&1 &
	local pid=$!
	_watch_docker "$name" "$log" "$limit" "$pid" || return 1
	grep -E "_TEST: " "$log" | head -n 20 || true
	if [ -s "$log" ] && ! grep -qE "_TEST: PASS" "$log"; then
		echo "ТЕСТ $script: нет строки PASS, последние строки:" >&2
		tail -n 20 "$log" >&2
		return 1
	fi
}


# Сторож одного контейнерного прогона: docker уже запущен в фоне
# (pid — клиентская сторона), ждём его, убиваем контейнер по
# SCRIPT ERROR и потолку времени. Возвращает 0, если контейнер
# доработал сам (успех смотрит вызывающий по логу).
_watch_docker() {
	local name="$1" log="$2" limit="$3" pid="$4"
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
	if [ -n "$killed" ]; then
		echo "ТЕСТ $name: снят сторожем ($killed), последние строки:" >&2
		tail -n 20 "$log" >&2
		return 1
	fi
}


# Один шард погони: свой контейнер, лог и дом (профили!), свой сид.
# Решение о зачёте принимает слияние (run_chase), а не шард.
run_chase_shard() {
	local shard="$1" of="$2" limit="$3"
	local name="mbt-test-chase-s$shard-$$"
	local log="/tmp/opencode/chase-s$shard.log"
	: >"$log"
	docker rm -f "$name" >/dev/null 2>&1 || true
	MBT_CONTAINER_NAME="$name" \
	MBT_HOME="/tmp/mbt-home-chase-s$shard" \
	MBT_XDG_CONFIG="/tmp/mbt-home-chase-s$shard/.config" \
	MBT_XDG_DATA="/tmp/mbt-home-chase-s$shard/.local/share" \
	run_godot --headless --path game \
		--script res://tests/chase_test.gd -- --shard "$shard" --of "$of" >"$log" 2>&1 &
	local pid=$!
	_watch_docker "$name" "$log" "$limit" "$pid" || return 1
}


# Погоня в N шардов параллельно + слияние. Эпизоды независимы (каждый
# начинается с чистого уровня), сиды разные, бюджеты делят 120 эпизодов
# полного прогона. Итоговые пороги — те же, что в _report, но на суммах.
run_chase() {
	local shards=4 limit=1800
	local pids=() i
	for i in 0 1 2 3; do
		run_chase_shard "$i" "$shards" "$limit" &
		pids+=($!)
	done
	local failed=0 pid
	for pid in "${pids[@]}"; do
		if ! wait "$pid"; then
			failed=1
		fi
	done
	if [ "$failed" -ne 0 ]; then
		return 1
	fi
	python3 - "$shards" <<'PYEOF_MERGE'
import re, sys

def parse(path):
    txt = open(path, encoding="utf-8", errors="replace").read()
    if "SCRIPT ERROR" in txt:
        return None, ["SCRIPT ERROR в " + path]
    m = re.search(r"шард=(\d+)/(\d+) эпизодов=(\d+) кадров=(\d+) сценарии\(угол_сзади/догон/откат_угол\)=\[(\d+), (\d+), (\d+)\]", txt)
    p = re.search(r"уколов=(\d+) \(одна_строка=(\d+) откат_через_угол=(\d+)\) табло_угла_проверено=(\d+) ближайшая_d=(-?[\d.]+)", txt)
    c = re.search(r"зазор на кадре укола: проверено=(\d+) средний=(-?[\d.]+) px", txt)
    r = re.search(r"откатов Backspace=(\d+)", txt)
    if not (m and p and c and r):
        return None, ["неполный отчёт в " + path]
    fails = [ln for ln in txt.splitlines() if "CHASE_TEST: FAIL: " in ln]
    ok = "CHASE_TEST: PASS" in txt
    return {
        "episodes": int(m.group(3)), "frames": int(m.group(4)),
        "sc": [int(m.group(5)), int(m.group(6)), int(m.group(7))],
        "pricks": int(p.group(1)), "same": int(p.group(2)), "cross": int(p.group(3)),
        "corner": int(p.group(4)), "closest": float(p.group(5)),
        "contact_n": int(c.group(1)), "gap_sum": float(c.group(2)) * int(c.group(1)),
        "retreats": int(r.group(1)), "fails": fails, "ok": ok,
    }, []

n = int(sys.argv[1])
tot = {"episodes": 0, "frames": 0, "sc": [0, 0, 0], "pricks": 0, "same": 0,
       "cross": 0, "corner": 0, "closest": -999.0, "contact_n": 0,
       "gap_sum": 0.0, "retreats": 0}
problems = []
for i in range(n):
    d, errs = parse("/tmp/opencode/chase-s%d.log" % i)
    problems += errs
    if d is None:
        continue
    if not d["ok"] or d["fails"]:
        problems += d["fails"] or ["шард %d без PASS" % i]
    for k in ("episodes", "frames", "pricks", "same", "cross", "corner",
              "contact_n", "retreats"):
        tot[k] += d[k]
    for j in range(3):
        tot["sc"][j] += d["sc"][j]
    tot["closest"] = max(tot["closest"], d["closest"])
    tot["gap_sum"] += d["gap_sum"]
for j, need in ((0, 200), (1, 200), (2, 200)):
    if tot["sc"][j] <= need:
        problems.append("сценарий %d: кадров %d, надо > %d" % (j, tot["sc"][j], need))
if tot["contact_n"] <= 5:
    problems.append("контакт проверен %d раз, надо > 5" % tot["contact_n"])
if tot["corner"] <= 10:
    problems.append("угловых табло %d, надо > 10" % tot["corner"])
if tot["retreats"] <= 20:
    problems.append("откатов %d, надо > 20" % tot["retreats"])
avg = tot["gap_sum"] / tot["contact_n"] if tot["contact_n"] else 0.0
print("CHASE_TEST: шардов=%d эпизодов=%d кадров=%d сценарии(угол_сзади/догон/откат_угол)=%s"
      % (n, tot["episodes"], tot["frames"], tot["sc"]))
print("CHASE_TEST: уколов=%d (одна_строка=%d откат_через_угол=%d) табло_угла_проверено=%d ближайшая_d=%.2f"
      % (tot["pricks"], tot["same"], tot["cross"], tot["corner"], tot["closest"]))
print("CHASE_TEST: зазор на кадре укола: проверено=%d средний=%.2f px (0 = шары ровно касаются)"
      % (tot["contact_n"], avg))
print("CHASE_TEST: откатов Backspace=%d" % tot["retreats"])
if problems:
    seen = set()
    for f in problems:
        key = f[:120]
        if key not in seen:
            seen.add(key)
            print("CHASE_TEST: FAIL: ", f)
    sys.exit(1)
print("CHASE_TEST: PASS")
PYEOF_MERGE
}


run_tests() {
	run_godot --headless --path game --import
	# Мёртвый путь не возвращается молча: ввод — только своей экранной
	# клавиатурой (решение 10.2026). Системной клавиатуры, composing-буфера,
	# автозамены, слоя знаков и долгого нажатия в коде игры быть не должно.
	if grep -rnE "virtual_keyboard|set_sys_kb|get_sys_kb|_comp_|KEY_UNKNOWN|KEY_NONE|kb_need_reshow|_sync_keyboard|_poll_keyboard" game/scripts/ | grep -v "sys_kb"; then
		echo "mbt-build: в коде игры остались следы системной клавиатуры" >&2
		return 1
	fi
	if grep -rnE '"\?123"|ROWS_SYM|bottom_sym_row|long_alt|long_base|_long_swap|LONG_PRESS' game/scripts/; then
		echo "mbt-build: в коде игры остались следы слоя знаков или долгого нажатия" >&2
		return 1
	fi
	# Все тесты — параллельно (ядер хватает, каждый лёгкий): общее время
	# определяет самый долгий (chase), а не сумма. Дома и логи у каждого
	# свои (см. run_test), контейнеры — тоже, так что тесты не мешают
	# друг другу. Импорт и линты выше идут строго до — они общие.
	# Погоня гоняет живой цикл кадр за кадром — самый долгий тест.
	local pids=() failed=0
	local s pid
	for s in logic_test.gd update_test.gd end_test.gd profiles_test.gd marks_test.gd combo_test.gd; do
		run_test "$s" 600 &
		pids+=($!)
	done
	# Погоня гоняет живой цикл кадр за кадром — самый долгий тест,
	# поэтому сама идёт шардами (см. run_chase).
	run_chase &
	pids+=($!)
	for pid in "${pids[@]}"; do
		if ! wait "$pid"; then
			failed=1
		fi
	done
	return $failed
}

# Пресеты в том порядке, в каком они лежат в export_presets.cfg.
PRESETS=(Windows Linux macOS Android)

# Версия в артефактах. Пресеты держат СВОИ номера (Godot пишет их как
# есть), а они с 0.0.10 не двигались: в собранном APK было
# versionName=0.0.10 при config/version=0.0.17, и телефон показывал
# «0.0.10» на любой сборке. Ставим версию проекта во все платформы, а
# файл возвращаем как был — дерево остаётся чистым.
stamp_version() {
	local v major minor patch code backup
	v="$(sed -n 's/^config\/version="\(.*\)"$/\1/p' game/project.godot)"
	if [ -z "$v" ]; then
		echo "mbt-build: в project.godot нет config/version" >&2
		return 1
	fi
	major="${v%%.*}"
	minor="$(echo "$v" | cut -d. -f2)"
	patch="$(echo "$v" | cut -d. -f3)"
	code=$(( major * 10000 + minor * 100 + patch ))
	backup="$(mktemp)"
	cp game/export_presets.cfg "$backup"
	sed -i \
		-e "s|^version/name=.*|version/name=\"$v\"|" \
		-e "s|^version/code=.*|version/code=$code|" \
		-e "s|^application/file_version=.*|application/file_version=\"$v.0\"|" \
		-e "s|^application/product_version=.*|application/product_version=\"$v.0\"|" \
		-e "s|^application/short_version=.*|application/short_version=\"$v\"|" \
		-e "s|^application/version=.*|application/version=\"$v\"|" \
		game/export_presets.cfg
	echo "mbt-build: версия сборки $v (version/code=$code)"
	PRESET_BACKUP="$backup"
}

restore_preset() {
	if [ -n "${PRESET_BACKUP:-}" ] && [ -f "$PRESET_BACKUP" ]; then
		cp "$PRESET_BACKUP" game/export_presets.cfg
		rm -f "$PRESET_BACKUP"
		PRESET_BACKUP=""
	fi
}

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
	stamp_version
	trap restore_preset EXIT
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
--visual)
	# Тот же живой рендер, но драйвер ИГРАЕТ партию и снимает экран в
	# ключевые события, печатая рядом состояние модели.
	run_godot --path game --script res://tests/visual_driver.gd
	# И меню тем же рендером: карточки игроков в портрете (их видно
	# только на экране — headless меряет прямоугольники, но не видит,
	# влезает ли в них текст).
	run_godot --path game --script res://tests/menu_driver.gd
	ls -la /tmp/opencode/vis-*.png
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