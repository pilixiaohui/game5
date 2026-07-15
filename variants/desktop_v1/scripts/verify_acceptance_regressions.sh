#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$project_root/scripts/timeout_gate.sh"

scratch_parent="${ACCEPTANCE_SCRATCH_PARENT:-${TMPDIR:-/tmp}}"
test_root="$(mktemp -d "$scratch_parent/xenogenesis-acceptance.XXXXXX")"
cleanup_acceptance() {
	cleanup_hard_timeout_processes
	rm -rf "$test_root"
}
trap cleanup_acceptance EXIT
trap 'exit 143' TERM INT

cd "$project_root"
status=0
run_with_hard_timeout "acceptance-regressions" "${ACCEPTANCE_TIMEOUT_SECONDS:-80}" "${ACCEPTANCE_KILL_AFTER_SECONDS:-5}" \
	xvfb-run -a env \
		HOME="$test_root/home" \
		XDG_CONFIG_HOME="$test_root/config" \
		XDG_CACHE_HOME="$test_root/cache" \
		XDG_DATA_HOME="$test_root/data" \
		godot4 --audio-driver Dummy --path . -s res://tests/acceptance_regression_runner.gd -- \
		"--scratch-data-root=$test_root/data" || status=$?
if [[ "$status" -ne 0 ]]; then
	exit "$status"
fi

echo "VERIFY_ACCEPTANCE_REGRESSIONS_OK timeout=${ACCEPTANCE_TIMEOUT_SECONDS:-80}s scratch=clean-on-exit"
