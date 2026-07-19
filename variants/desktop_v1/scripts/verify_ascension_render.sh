#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/xenogenesis-ascension-render.XXXXXX")"
trap 'rm -rf "$test_root"' EXIT
mkdir -p "$test_root/tmp"

env TMPDIR="$test_root/tmp" xvfb-run -a env \
	HOME="$test_root/home" \
	XDG_CONFIG_HOME="$test_root/config" \
	XDG_CACHE_HOME="$test_root/cache" \
	XDG_DATA_HOME="$test_root/data" \
	godot4 --audio-driver Dummy --path "$project_root" -s res://tests/ascension_render_runner.gd -- \
	"--scratch-data-root=$test_root/data" \
	"--capture-root=$test_root/captures"

capture_count="$(find "$test_root/captures" -maxdepth 1 -type f -name 'ascension_*.png' | wc -l)"
if [[ "$capture_count" -ne 3 ]]; then
	echo "Ascension render gate produced $capture_count images instead of 3." >&2
	exit 1
fi

echo "VERIFY_ASCENSION_RENDER_OK resolutions=1280x720,1600x900,1920x1080 captures=3 scratch=clean-on-exit"
