#!/usr/bin/env bash
set -euo pipefail

project_root="${ACCEPTANCE_RECOVERY_PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$project_root/scripts/timeout_gate.sh"
"$project_root/scripts/verify_post_import_ready.sh"

scratch_parent="${ACCEPTANCE_RECOVERY_SCRATCH_PARENT:-${TMPDIR:-/tmp}}"
test_root="$(mktemp -d "$scratch_parent/xenogenesis-acceptance-recovery.XXXXXX")"
mkdir -p "$test_root/home" "$test_root/config" "$test_root/cache" "$test_root/data"
cleanup_recovery() {
	cleanup_hard_timeout_processes || true
	rm -rf "$test_root"
}
trap cleanup_recovery EXIT
trap 'exit 143' TERM INT

log="$test_root/recovery.log"
exit_ready_file="$test_root/exit-ready"
pid_file="$test_root/supervisor.pid"
runner_path="${ACCEPTANCE_RECOVERY_RUNNER_PATH:-res://tests/acceptance_regression_runner.gd}"
status=0
HARD_TIMEOUT_TEST_SPAWN_PID_FILE="$pid_file" \
run_with_hard_timeout "acceptance-recovery-lifecycle" "${ACCEPTANCE_RECOVERY_TIMEOUT_SECONDS:-55}" \
	"${ACCEPTANCE_RECOVERY_KILL_AFTER_SECONDS:-5}" \
	xvfb-run -a env \
		HOME="$test_root/home" \
		XDG_CONFIG_HOME="$test_root/config" \
		XDG_CACHE_HOME="$test_root/cache" \
		XDG_DATA_HOME="$test_root/data" \
		godot4 --audio-driver Dummy --path "$project_root" -s "$runner_path" -- \
		"--scratch-data-root=$test_root/data" "--exit-ready-file=$exit_ready_file" "--segment=recovery" "--renderer-mode=rendered" \
		> "$log" 2>&1 || status=$?
cat "$log"

supervisor_pid="$(<"$pid_file")"
supervisor_pgid="$(<"$pid_file.pgid")"
if process_exists "$supervisor_pid" || process_group_exists "$supervisor_pgid"; then
	echo "ACCEPTANCE_RECOVERY_LIFECYCLE_RED reason=process-tree-live status=$status pid=$supervisor_pid pgid=$supervisor_pgid" >&2
	exit 1
fi
if [[ "$status" -ne 0 ]]; then
	echo "ACCEPTANCE_RECOVERY_LIFECYCLE_RED reason=runner-status status=$status process_tree=gone" >&2
	exit "$status"
fi

mapfile -t phases < <(sed -n 's/^ACCEPTANCE_RECOVERY_LIFECYCLE phase=\([^ ]*\).*/\1/p' "$log")
expected_phases="start ctrl-s-resolved system-page-resolved autosave-boundary autosave-resolved first-save-resolved complete teardown quit"
if [[ "${phases[*]:-}" != "$expected_phases" ]]; then
	echo "ACCEPTANCE_RECOVERY_LIFECYCLE_RED reason=ordered-markers expected=${expected_phases// /,} actual=${phases[*]:-none} process_tree=gone" >&2
	exit 1
fi
if ! rg -q '^ACCEPTANCE_RECOVERY_ASSERTIONS_OK cases=1 assertions=97 lifecycle_assertions=[0-9]+$' "$log"; then
	echo "ACCEPTANCE_RECOVERY_LIFECYCLE_RED reason=assertion-marker-missing process_tree=gone" >&2
	exit 1
fi
if ! rg -q '^ACCEPTANCE_RECOVERY_LIFECYCLE phase=teardown .*nodes=0 signals=0$' "$log"; then
	echo "ACCEPTANCE_RECOVERY_LIFECYCLE_RED reason=node-signal-teardown process_tree=gone" >&2
	exit 1
fi
if ! rg -q '^ACCEPTANCE_SEGMENT_IDENTITY segment=recovery home=/[^ ]+ config=/[^ ]+ cache=/[^ ]+ data=/[^ ]+ save=/[^ ]+ display=:[0-9]+ renderer=rendered$' "$log"; then
	echo "ACCEPTANCE_RECOVERY_LIFECYCLE_RED reason=canonical-identity-missing process_tree=gone" >&2
	exit 1
fi

mapfile -t ctrl_s_phases < <(sed -n 's/^ACCEPTANCE_CTRL_S_BOUNDARY phase=\([^ ]*\).*/\1/p' "$log")
expected_ctrl_s_phases="window-ready focus-ready input-dispatch-ready ctrl-s-injected save-request durable-completion teardown"
if [[ "${ctrl_s_phases[*]:-}" != "$expected_ctrl_s_phases" ]]; then
	echo "ACCEPTANCE_RECOVERY_LIFECYCLE_RED reason=ctrl-s-boundary-order expected=${expected_ctrl_s_phases// /,} actual=${ctrl_s_phases[*]:-none} process_tree=gone" >&2
	exit 1
fi
previous_boundary_ms=-1
while IFS= read -r boundary_ms; do
	if [[ ! "$boundary_ms" =~ ^[0-9]+$ || "$boundary_ms" -lt "$previous_boundary_ms" ]]; then
		echo "ACCEPTANCE_RECOVERY_LIFECYCLE_RED reason=ctrl-s-boundary-nonmonotonic value=${boundary_ms:-missing} previous=$previous_boundary_ms" >&2
		exit 1
	fi
	previous_boundary_ms="$boundary_ms"
done < <(sed -n -E 's/^ACCEPTANCE_CTRL_S_BOUNDARY .* boundary_ms=([0-9]+) .*/\1/p' "$log")
if [[ "$previous_boundary_ms" -lt 0 || "$previous_boundary_ms" -gt 6000 ]]; then
	echo "ACCEPTANCE_RECOVERY_LIFECYCLE_RED reason=ctrl-s-boundary-budget elapsed_ms=$previous_boundary_ms budget_ms=6000" >&2
	exit 1
fi
if ! rg -q '^ACCEPTANCE_CTRL_S_BOUNDARY phase=save-request .* operation=[^ ]+$' "$log" || \
	! rg -q '^ACCEPTANCE_CTRL_S_BOUNDARY phase=durable-completion .* outcome=uncertain reload_required=true$' "$log" || \
	! rg -q '^ACCEPTANCE_CTRL_S_BOUNDARY phase=teardown .* main_alive=false$' "$log"; then
	echo "ACCEPTANCE_RECOVERY_LIFECYCLE_RED reason=ctrl-s-production-contract process_tree=gone" >&2
	exit 1
fi

autosave_line="$(rg '^RECOVERY_UI_REAL_AUTOSAVE elapsed_msec=' "$log")"
autosave_msec="$(sed -E 's/.*elapsed_msec=([0-9]+).*/\1/' <<< "$autosave_line")"
if [[ ! "$autosave_msec" =~ ^[0-9]+$ || "$autosave_msec" -lt 30000 || "$autosave_msec" -ge 37000 ]]; then
	echo "ACCEPTANCE_RECOVERY_LIFECYCLE_RED reason=autosave-boundary elapsed_msec=${autosave_msec:-invalid}" >&2
	exit 1
fi
if [[ ! -s "$exit_ready_file" ]]; then
	echo "ACCEPTANCE_RECOVERY_LIFECYCLE_RED reason=exit-ready-missing process_tree=gone" >&2
	exit 1
fi
exit_ready_epoch="$(stat -c '%Y' "$exit_ready_file")"
exit_delay_seconds=$(( $(date +%s) - exit_ready_epoch ))
if [[ "$exit_delay_seconds" -gt 5 ]]; then
	echo "ACCEPTANCE_RECOVERY_LIFECYCLE_RED reason=exit-delay delay_seconds=$exit_delay_seconds budget_seconds=5" >&2
	exit 1
fi

summary="$(rg '^ACCEPTANCE_RECOVERY_ASSERTIONS_OK ' "$log")"
echo "VERIFY_ACCEPTANCE_RECOVERY_LIFECYCLE_OK ${summary#ACCEPTANCE_RECOVERY_ASSERTIONS_OK } ctrl_s_msec=$previous_boundary_ms autosave_msec=$autosave_msec exit_delay_seconds=$exit_delay_seconds nodes=0 signals=0 process_tree=gone scratch=clean-on-exit"
