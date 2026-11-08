#!/usr/bin/env bash
# Стенд Android-эмулятора: гоняет собранный APK на телефоне-эмуляторе.
#
# Правила (AGENTS.md §6):
#   * окно эмулятора — на :0 ТОЛЬКО по просьбе автора; для себя стенд
#     поднимается с --display :99 (виртуальный экран) или --headless;
#   * SDK и образы — tools/emulator/sdk (в .gitignore), AVD —
#     tools/emulator/avd; скрипт поднимает их САМ (sdkmanager качает
#     образы, AVD собирается из профиля), с чистого клона стенд ставится
#     одной командой;
#   * KVM пробрасывается устройством + --group-add: пользователя в
#     группе kvm нет, наружу ничего не ставится;
#   * свежий game/dist/ModernBabyType.apk ставится сам;
#   * эмулятор жрёт гигабайты RAM: закончил — `docker stop mbt-emu`,
#     между проверками — `docker pause mbt-emu`.
#
# Использование:
#   tools/emulator/run-emu.sh                  # окно на :0 (автор смотрит)
#   tools/emulator/run-emu.sh --display :99    # окно на тестовом экране
#   tools/emulator/run-emu.sh --headless       # без окна, кадры через adb
#   tools/emulator/run-emu.sh --play           # Play-образ (Gboard с русским)
#   tools/emulator/run-emu.sh --no-install     # не ставить APK
#   tools/emulator/run-emu.sh --shot NAME      # снять кадр в /tmp/opencode/NAME.png
#   tools/emulator/run-emu.sh --stop           # погасить стенд
#   tools/emulator/run-emu.sh --pause / --resume
#
# Кадры (и в headless, и в окне): `--shot` или вручную
#   docker exec mbt-emu /sdk/platform-tools/adb exec-out screencap -p \
#     > /tmp/opencode/emu.png
#
# Ввод: `adb shell input tap` в госте НЕ работает, зато настоящие клики
# мышью в окне доходят как тачи (проверено через getevent). Поэтому
# сценарии с тапами гоняются с окном (--display :99) и xdotool'ом:
#   DISPLAY=:99 xdotool mousemove X Y click 1
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
SDK="$ROOT/tools/emulator/sdk"
AVD_HOME="$ROOT/tools/emulator/avd"
APK="$ROOT/game/dist/ModernBabyType.apk"
NAME=mbt-emu
IMAGE=${MBT_EMU_IMAGE:-mbt-godot}
AVD=mbt
DISPLAY_ID=${MBT_EMU_DISPLAY:-:0}
HEADLESS=0
INSTALL=1
SHOT=""
TAP_X=""
TAP_Y=""

die() { echo "run-emu: $*" >&2; exit 1; }

while [ $# -gt 0 ]; do
	case "$1" in
	--headless) HEADLESS=1 ;;
	--display) shift; DISPLAY_ID=${1:?--display ждёт номер экрана} ;;
	--play) AVD=mbt-play ;;
	--avd) shift; AVD=${1:?--avd ждёт имя AVD} ;;
	--no-install) INSTALL=0 ;;
	--shot) shift; SHOT=${1:?--shot ждёт имя кадра} ;;
	--tap) shift; TAP_X=${1:?--tap ждёт X}; shift; TAP_Y=${1:?--tap ждёт Y} ;;
	--stop)
		docker stop "$NAME" >/dev/null 2>&1 || true
		echo "run-emu: стенд погашен"
		exit 0 ;;
	--pause)
		docker pause "$NAME" >/dev/null 2>&1 || true
		echo "run-emu: стенд на паузе (CPU=0, память и состояние гостя целы)"
		exit 0 ;;
	--resume)
		docker unpause "$NAME" >/dev/null 2>&1 || true
		echo "run-emu: стенд снят с паузы"
		exit 0 ;;
	-h|--help) sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
	*) die "неизвестный флаг: $1" ;;
	esac
	shift
done

# SDK и AVD создаются САМИ, если их нет: с чистого клона стенд
# поднимается одной командой (SDK качается разово, ~2.5 ГБ).
ensure_sdk() {
	if [ -x "$SDK/emulator/emulator" ] && [ -x "$SDK/platform-tools/adb" ] &&
		[ -d "$SDK/system-images/android-34/default/x86_64" ]; then
		return 0
	fi
	echo "run-emu: качаю SDK в $SDK (разово, ~2.5 ГБ)"
	mkdir -p "$SDK"
	docker run --rm --user "$(id -u):$(id -g)" -v "$ROOT:/work" -w /work \
		-e HOME=/tmp/mbt-home \
		--entrypoint bash "$IMAGE" -lc '
			set -e
			S=/work/tools/emulator/sdk
			SM=/usr/lib/android-sdk/cmdline-tools/latest/bin/sdkmanager
			yes | "$SM" --sdk_root="$S" --licenses >/dev/null 2>&1 || true
			"$SM" --sdk_root="$S" --install platform-tools emulator \
				"system-images;android-34;default;x86_64"
		' || die "sdkmanager не смог поставить SDK"
}

# AVD: собирается ПРЯМО ИЗ ПРОФИЛЯ (tools/emulator/avd/<имя>.config.ini —
# геометрия телефона 1080x2280, dpi 420, swiftshader), без avdmanager:
# он ищет системные образы в том SDK, из которого запущен (образ движка),
# и наш tools/emulator/sdk не видит. Эмулятору хватает config.ini и
# <имя>.ini, остальное (userdata, hardware-qemu.ini) он создаёт сам при
# первом запуске. Без профиля гость поднимается другим экраном, и кадры
# с тапами не совпадают с тем, что видел автор.
ensure_avd() {
	[ -d "$AVD_HOME/$AVD.avd" ] && return 0
	[ -f "$AVD_HOME/$AVD.config.ini" ] ||
		die "нет профиля $AVD_HOME/$AVD.config.ini"
	echo "run-emu: создаю AVD $AVD из профиля"
	mkdir -p "$AVD_HOME/$AVD.avd"
	cp "$AVD_HOME/$AVD.config.ini" "$AVD_HOME/$AVD.avd/config.ini"
	# Путь в .ini — КОНТЕЙНЕРНЫЙ: эмулятор всегда живёт в контейнере, где
	# репозиторий смонтирован в /work.
	cat >"$AVD_HOME/$AVD.ini" <<EOF
avd.ini.encoding=UTF-8
path=/work/tools/emulator/avd/$AVD.avd
target=android-34
EOF
}

# Без образа ни sdkmanager, ни эмулятор не запустятся: собирается он тем же
# скриптом, что и вся сборка (Dockerfile — источник правды).
docker image inspect "$IMAGE" >/dev/null 2>&1 ||
	die "нет образа $IMAGE — собери: tools/docker/build-game.sh --test-only"

ensure_sdk
ensure_avd

# --- тап по окну эмулятора: клик мышью = настоящее касание в госте -------
# `adb shell input tap` в этом госте не работает (AGENTS.md §6), а клики
# мышью в окне доходят как тачи. Координаты задаются в пикселях ГОСТЯ
# (1080x2280 из config.ini) — пересчёт в экранные делает скрипт.
if [ -n "$TAP_X" ]; then
	command -v xdotool >/dev/null || die "нужен xdotool"
	GW=$(sed -n 's/^hw\.lcd\.width *= *\([0-9]*\).*/\1/p' \
		"$AVD_HOME/$AVD.avd/config.ini" | head -1)
	GH=$(sed -n 's/^hw\.lcd\.height *= *\([0-9]*\).*/\1/p' \
		"$AVD_HOME/$AVD.avd/config.ini" | head -1)
	GW=${GW:-1080}
	GH=${GH:-2280}
	WID=$(DISPLAY="$DISPLAY_ID" xdotool search --onlyvisible \
		--name "Android Emulator" 2>/dev/null | head -1 || true)
	[ -n "${WID:-}" ] || WID=$(DISPLAY="$DISPLAY_ID" xdotool search \
		--onlyvisible --classname "Emulator" 2>/dev/null | head -1 || true)
	[ -n "${WID:-}" ] || die "не нашёл окно эмулятора на $DISPLAY_ID"
	eval "$(DISPLAY="$DISPLAY_ID" xdotool getwindowgeometry --shell "$WID")"
	px=$((X + TAP_X * WIDTH / GW))
	py=$((Y + TAP_Y * HEIGHT / GH))
	DISPLAY="$DISPLAY_ID" xdotool mousemove --sync "$px" "$py" click 1
	echo "run-emu: тап ($TAP_X,$TAP_Y) гостя → экран ($px,$py)"
	exit 0
fi

# AVD без .ini не находится по имени: emulator ищет <name>.ini рядом с
# каталогом <name>.avd. Путь в нём — КОНТЕЙНЕРНЫЙ (/work/...): эмулятор
# всегда живёт в контейнере, где репозиторий смонтирован в /work. С
# хозяйским путём он не читает config.ini и падает «CPU Architecture
# 'arm' is not supported».
if [ ! -f "$AVD_HOME/$AVD.ini" ]; then
	cat >"$AVD_HOME/$AVD.ini" <<EOF
avd.ini.encoding=UTF-8
path=/work/tools/emulator/avd/$AVD.avd
target=android-34
EOF
fi

# Один стенд за раз: старый контейнер (даже на паузе) держит порт.
if docker ps -a --format '{{.Names}}' | grep -qx "$NAME"; then
	docker rm -f "$NAME" >/dev/null 2>&1 || true
fi
# Замки прошлого запуска: контейнер умер, а файлы остались — эмулятор
# откажется стартовать («already running»).
rm -f "$AVD_HOME/$AVD.avd/hardware-qemu.ini.lock" \
	"$AVD_HOME/$AVD.avd/multiinstance.lock" \
	"$AVD_HOME/$AVD.avd/*.lock" 2>/dev/null || true

KVM_GID=$(getent group kvm | cut -d: -f3 || true)
[ -n "$KVM_GID" ] || die "нет группы kvm (нужен /dev/kvm)"
[ -e /dev/kvm ] || die "нет /dev/kvm"

args=(-avd "$AVD" -no-audio -no-metrics -no-snapshot
	-gpu swiftshader_indirect)
if [ "$HEADLESS" = "1" ]; then
	args+=(-no-window)
fi

echo "run-emu: AVD=$AVD экран=$DISPLAY_ID headless=$HEADLESS"
docker run -d --rm --name "$NAME" \
	--device /dev/kvm --group-add "$KVM_GID" \
	-v "$ROOT:/work" \
	-v "$SDK:/sdk" \
	-v /tmp/.X11-unix:/tmp/.X11-unix \
	-e DISPLAY="$DISPLAY_ID" \
	-e ANDROID_SDK_ROOT=/sdk \
	-e ANDROID_HOME=/sdk \
	-e ANDROID_AVD_HOME=/work/tools/emulator/avd \
	-w /work \
	--entrypoint /sdk/emulator/emulator \
	"$IMAGE" "${args[@]}" >/dev/null

ADB=(docker exec "$NAME" /sdk/platform-tools/adb)

echo -n "run-emu: ждём загрузку гостя"
for _ in $(seq 1 180); do
	if ! docker ps --format '{{.Names}}' | grep -qx "$NAME"; then
		echo
		docker logs "$NAME" 2>&1 | tail -30 || true
		die "эмулятор упал при старте"
	fi
	boot=$("${ADB[@]}" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r\n' || true)
	if [ "$boot" = "1" ]; then
		echo " — готово"
		break
	fi
	echo -n "."
	sleep 2
done
[ "${boot:-}" = "1" ] || die "гость не загрузился за 6 минут"

# Экран не должен гаснуть: иначе кадры чёрные, а тапы мимо.
"${ADB[@]}" shell settings put system screen_off_timeout 2147483647 >/dev/null 2>&1 || true
"${ADB[@]}" shell svc power stayon true >/dev/null 2>&1 || true

if [ "$INSTALL" = "1" ]; then
	[ -f "$APK" ] || die "нет $APK — собери tools/docker/build-game.sh --preset Android"
	"${ADB[@]}" install -r /work/game/dist/ModernBabyType.apk 2>&1 |
		grep -Ev '^Performing Streamed Install$' || true
fi

if [ -n "$SHOT" ]; then
	mkdir -p /tmp/opencode
	"${ADB[@]}" exec-out screencap -p >"/tmp/opencode/$SHOT.png"
	echo "run-emu: кадр /tmp/opencode/$SHOT.png"
fi

cat <<EOF
run-emu: стенд работает (контейнер $NAME)
  игра:      ${ADB[*]} shell monkey -p ru.nikitashubin.modernbabytype 1
  кадр:      ${ADB[*]} exec-out screencap -p > /tmp/opencode/emu.png
  пауза:     tools/emulator/run-emu.sh --pause
  погасить:  tools/emulator/run-emu.sh --stop
EOF
