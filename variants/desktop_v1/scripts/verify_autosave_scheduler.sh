#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$project_root/scripts/timeout_gate.sh"

scratch_parent="${AUTOSAVE_SCRATCH_PARENT:-${TMPDIR:-/tmp}}"
test_root="$(mktemp -d "$scratch_parent/xenogenesis-autosave.XXXXXX")"
cleanup_autosave() {
	cleanup_hard_timeout_processes
	rm -rf "$test_root"
}
trap cleanup_autosave EXIT
trap 'exit 143' TERM INT

timeout_seconds="${AUTOSAVE_TIMEOUT_SECONDS:-50}"
kill_after_seconds="${AUTOSAVE_KILL_AFTER_SECONDS:-5}"
godot_bin="${AUTOSAVE_GODOT_BIN:-godot4}"

cd "$project_root"
status=0
run_with_hard_timeout "autosave-scheduler" "$timeout_seconds" "$kill_after_seconds" \
	env \
		HOME="$test_root/home" \
		XDG_CONFIG_HOME="$test_root/config" \
		XDG_CACHE_HOME="$test_root/cache" \
		XDG_DATA_HOME="$test_root/data" \
		"$godot_bin" --headless --path . -s res://tests/autosave_scheduler_runner.gd || status=$?
if [[ "$status" -ne 0 ]]; then
	exit "$status"
fi

echo "VERIFY_AUTOSAVE_SCHEDULER_OK timeout=${timeout_seconds}s scratch=clean-on-exit"
