#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$project_root/scripts/timeout_gate.sh"
"$project_root/scripts/verify_post_import_ready.sh"

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
	"$project_root/scripts/run_acceptance_segments.sh" "$project_root" "$test_root" \
		> "$acceptance_log" 2>&1 || status=$?
cat "$acceptance_log"
if [[ "$status" -ne 0 ]]; then
	exit "$status"
fi

if [[ ! -s "$exit_ready_file" ]] || ! rg -q '^ACCEPTANCE_ASSERTIONS_OK cases=5 resolutions=3 assertions=' "$acceptance_log"; then
	echo "Acceptance process exited without publishing its post-cleanup lifecycle marker." >&2
	exit 1
fi
for segment in recovery core; do
	if ! rg -q "^ACCEPTANCE_SEGMENT_ORCHESTRATION segment=$segment phase=start mode=(rendered|dummy) pid=[0-9]+ pgid=[0-9]+ start_ns=[0-9]+$" "$acceptance_log" || \
		! rg -q "^ACCEPTANCE_SEGMENT_ORCHESTRATION segment=$segment phase=reaped mode=(rendered|dummy) status=0 pid=[0-9]+ pgid=[0-9]+ pid_alive=0 pgid_alive=0 elapsed_ms=[0-9]+$" "$acceptance_log"; then
		echo "Acceptance $segment segment was not started and reaped by the bounded orchestrator." >&2
		exit 1
	fi
done
mapfile -t segment_phases < <(sed -n -E 's/^ACCEPTANCE_SEGMENT_ORCHESTRATION segment=([^ ]+) phase=([^ ]+).*/\1:\2/p' "$acceptance_log")
if [[ "${segment_phases[*]:-}" != "recovery:start recovery:reaped core:start core:reaped" ]]; then
	echo "Acceptance segments did not preserve the exclusive recovery-before-core order: ${segment_phases[*]:-none}" >&2
	exit 1
fi
if ! rg -q '^ACCEPTANCE_SEGMENT_ISOLATION_OK filesystems=10-distinct displays=:[0-9]+,:[0-9]+ renderers=recovery-rendered,core-dummy$' "$acceptance_log"; then
	echo "Acceptance segments did not prove canonical filesystem/display isolation." >&2
	exit 1
fi
cache_before="$(sed -n -E 's/^ACCEPTANCE_PROJECT_CACHE phase=before fingerprint=([0-9a-f]{64}) files=[0-9]+$/\1/p' "$acceptance_log")"
cache_after="$(sed -n -E 's/^ACCEPTANCE_PROJECT_CACHE phase=after fingerprint=([0-9a-f]{64}) files=[0-9]+$/\1/p' "$acceptance_log")"
if [[ -z "$cache_before" || "$cache_before" != "$cache_after" ]]; then
	echo "Acceptance shared project cache fingerprint changed or is missing." >&2
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
echo "${assertion_summary/ACCEPTANCE_ASSERTIONS_OK/ACCEPTANCE_REGRESSIONS_OK} lifecycle_exit_seconds=$exit_delay_seconds isolation=canonical-distinct project_cache=unchanged pids_pgids=reaped process_tree=gone"
echo "VERIFY_ACCEPTANCE_REGRESSIONS_OK timeout=${ACCEPTANCE_TIMEOUT_SECONDS:-80}s scratch=clean-on-exit"
