#!/usr/bin/env bash
# Render the standalone hand study inside the same container the game uses.
# Frames: /tmp/opencode/hand3d/*.png. Screen is always the test one (:99).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ARGS=("$@")
docker run --rm --user "$(id -u):$(id -g)" \
	-v "$ROOT:/work" \
	-v /tmp/.X11-unix:/tmp/.X11-unix \
	-v /tmp/opencode:/tmp/opencode \
	-e HOME=/tmp/mbt-home \
	-e DISPLAY="${MBT_DISPLAY:-:99}" \
	-w /work/tools/hand3d \
	mbt-godot --rendering-driver opengl3 --path /work/tools/hand3d -- "${ARGS[@]}"
