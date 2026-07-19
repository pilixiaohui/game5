#!/usr/bin/env bash
set -euo pipefail

script_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
default_project_root="$(cd "$script_root/.." && pwd)"
project_root="${SCREENSHOT_PROJECT_ROOT:-$default_project_root}"
source "$script_root/timeout_gate.sh"

scratch_parent="${SCREENSHOT_SCRATCH_PARENT:-${TMPDIR:-/tmp}}"
control_root="$(mktemp -d "$scratch_parent/xenogenesis-screenshot-control.XXXXXX")"
work_root=""

cleanup_screenshot_gate() {
	cleanup_hard_timeout_processes || true
	rm -rf "$control_root" "$work_root"
}
trap cleanup_screenshot_gate EXIT
trap 'exit 143' TERM INT
work_root="$(mktemp -d "$scratch_parent/xenogenesis-screenshot-work.XXXXXX")"
mkdir -p "$work_root/tmp"

screenshots_dir="$project_root/screenshots"
mkdir -p "$screenshots_dir"
for filename in title_1600x900.png hive_1600x900.png map_1600x900.png battle_1600x900.png evolution_1280x720.png system_1280x720.png; do
	rm -f "$screenshots_dir/$filename"
done

godot_bin="${SCREENSHOT_GODOT_BIN:-godot4}"
timeout_seconds="${SCREENSHOT_TIMEOUT_SECONDS:-90}"
kill_after_seconds="${SCREENSHOT_KILL_AFTER_SECONDS:-5}"
log_path="$control_root/screenshots.log"
command=(
	env TMPDIR="$work_root/tmp"
	xvfb-run -a env
	HOME="$work_root/home"
	XDG_CONFIG_HOME="$work_root/config"
	XDG_CACHE_HOME="$work_root/cache"
	XDG_DATA_HOME="$work_root/data"
	"$godot_bin" --audio-driver Dummy --path "$project_root" -s res://tests/screenshot_runner.gd -- --capture-child
)

status=0
run_with_hard_timeout screenshots "$timeout_seconds" "$kill_after_seconds" "${command[@]}" >"$log_path" 2>&1 || status=$?
cat "$log_path"
if [[ "$status" -ne 0 ]]; then
	exit "$status"
fi

screenshot_count="$(find "$screenshots_dir" -maxdepth 1 -type f -name '*.png' | wc -l)"
if [[ "$screenshot_count" -ne 6 ]]; then
	echo "Screenshot gate produced $screenshot_count images instead of 6." >&2
	exit 1
fi
for filename in title_1600x900.png hive_1600x900.png map_1600x900.png battle_1600x900.png evolution_1280x720.png system_1280x720.png; do
	if [[ ! -s "$screenshots_dir/$filename" ]]; then
		echo "Screenshot gate produced a missing or empty image: $filename" >&2
		exit 1
	fi
done

echo "VERIFY_SCREENSHOTS_OK count=6 timeout=${timeout_seconds}s pgid=reaped scratch_roots=clean-on-exit"
