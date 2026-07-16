#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$project_root/scripts/timeout_gate.sh"

scratch_parent="${ACCEPTANCE_SCRATCH_PARENT:-${TMPDIR:-/tmp}}"
test_root="$(mktemp -d "$scratch_parent/xenogenesis-acceptance.XXXXXX")"
cleanup_acceptance() {
	cleanup_hard_timeout_processes || true
	rm -rf "$test_root"
}
trap cleanup_acceptance EXIT
trap 'exit 143' TERM INT

cd "$project_root"
status=0
acceptance_log="$test_root/acceptance.log"
exit_ready_file="$test_root/exit-ready"
timeout_pid_file="$test_root/timeout.pid"
HARD_TIMEOUT_TEST_SPAWN_PID_FILE="$timeout_pid_file" \
run_with_hard_timeout "acceptance-regressions" "${ACCEPTANCE_TIMEOUT_SECONDS:-80}" "${ACCEPTANCE_KILL_AFTER_SECONDS:-5}" \
	xvfb-run -a env \
		HOME="$test_root/home" \
		XDG_CONFIG_HOME="$test_root/config" \
		XDG_CACHE_HOME="$test_root/cache" \
		XDG_DATA_HOME="$test_root/data" \
		godot4 --audio-driver Dummy --path . -s res://tests/acceptance_regression_runner.gd -- \
		"--scratch-data-root=$test_root/data" "--exit-ready-file=$exit_ready_file" > "$acceptance_log" 2>&1 || status=$?
cat "$acceptance_log"
if [[ "$status" -ne 0 ]]; then
	exit "$status"
fi

if [[ ! -s "$exit_ready_file" ]] || ! rg -q '^ACCEPTANCE_ASSERTIONS_OK cases=5 resolutions=3 assertions=' "$acceptance_log"; then
	echo "Acceptance process exited without publishing its post-cleanup lifecycle marker." >&2
	exit 1
fi
timeout_pid="$(<"$timeout_pid_file")"
timeout_pgid="$(<"$timeout_pid_file.pgid")"
if process_exists "$timeout_pid" || process_group_exists "$timeout_pgid"; then
	echo "Acceptance success marker was followed by a live process tree: pid=$timeout_pid pgid=$timeout_pgid" >&2
	exit 1
fi
exit_ready_epoch="$(stat -c '%Y' "$exit_ready_file")"
exit_observed_epoch="$(date +%s)"
exit_delay_seconds=$((exit_observed_epoch - exit_ready_epoch))
if [[ "$exit_delay_seconds" -gt 5 ]]; then
	echo "Acceptance process tree took too long to exit after its success marker: ${exit_delay_seconds}s" >&2
	exit 1
fi

assertion_summary="$(rg '^ACCEPTANCE_ASSERTIONS_OK cases=5 resolutions=3 assertions=' "$acceptance_log" | tail -n 1)"
echo "${assertion_summary/ACCEPTANCE_ASSERTIONS_OK/ACCEPTANCE_REGRESSIONS_OK} lifecycle_exit_seconds=$exit_delay_seconds process_tree=gone"
echo "VERIFY_ACCEPTANCE_REGRESSIONS_OK timeout=${ACCEPTANCE_TIMEOUT_SECONDS:-80}s scratch=clean-on-exit"
