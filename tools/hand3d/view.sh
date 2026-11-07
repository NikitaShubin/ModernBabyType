#!/usr/bin/env bash
# Opens the hand study in a window, so the author can turn it around.
# Same image as the game; the screen is the author's (:0) unless MBT_DISPLAY
# says otherwise — the test screen :99 is for stills only.
#
# The default scene is the integration viewer: the project's own five-row
# keyboard with both hands over it, a click picking the hand and the finger.
# MBT_SCENE=res://viewer.tscn opens the older single-hand study.
#
# The container is detached (-d) on purpose: the window must outlive the
# shell that opened it. Escape (or the window's close button) quits.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
AUTH="${XAUTHORITY:-$HOME/.Xauthority}"
SIZE=()
# The test screen :99 is only 1280x800 tall; MBT_SIZE shrinks the window for
# screenshots there. The author's screen gets the full portrait window.
[ -n "${MBT_SIZE:-}" ] && SIZE=(--resolution "$MBT_SIZE")

# Every other MBT_* variable rides along (MBT_SHOT, MBT_SHOT_DIR, ...): the
# container environment is empty by default and docker -e does not inherit.
PASS=()
while IFS= read -r kv; do
	[ -n "$kv" ] && PASS+=(-e "$kv")
done < <(env | grep '^MBT_' | grep -v '^MBT_DISPLAY')

CID=$(docker run -d --rm --user "$(id -u):$(id -g)" \
	-v "$ROOT:/work" \
	-v /tmp/.X11-unix:/tmp/.X11-unix \
	-v "$AUTH:/tmp/xauth:ro" \
	-e HOME=/tmp/mbt-home \
	-e XAUTHORITY=/tmp/xauth \
	-e DISPLAY="${MBT_DISPLAY:-:0}" \
	-e LIBGL_ALWAYS_SOFTWARE="${LIBGL_ALWAYS_SOFTWARE:-0}" \
	${PASS[@]+"${PASS[@]}"} \
	-w /work/tools/hand3d \
	mbt-godot --rendering-driver opengl3 "${SIZE[@]}" --path /work/tools/hand3d "${MBT_SCENE:-res://board.tscn}" "$@")
echo "viewer: $CID (stop with: docker kill $CID)"
