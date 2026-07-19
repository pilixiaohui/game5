#!/usr/bin/env bash
set -euo pipefail

project_root="${M1_ASSET_LIFECYCLE_PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$project_root/scripts/timeout_gate.sh"
"$project_root/scripts/verify_post_import_ready.sh"

scratch_parent="${M1_ASSET_LIFECYCLE_SCRATCH_PARENT:-${TMPDIR:-/tmp}}"
test_root="$(mktemp -d "$scratch_parent/xenogenesis-m1-asset-lifecycle.XXXXXX")"
cleanup_lifecycle() {
	cleanup_hard_timeout_processes || true
	rm -rf "$test_root"
}
trap cleanup_lifecycle EXIT
trap 'exit 143' TERM INT

log="$test_root/asset-lifecycle.log"
pid_file="$test_root/supervisor.pid"
status=0
HARD_TIMEOUT_TEST_SPAWN_PID_FILE="$pid_file" \
run_with_hard_timeout "m1-asset-lifecycle" "${M1_ASSET_LIFECYCLE_TIMEOUT_SECONDS:-15}" \
	"${M1_ASSET_LIFECYCLE_KILL_AFTER_SECONDS:-3}" \
	env \
		HOME="$test_root/home" \
		XDG_CONFIG_HOME="$test_root/config" \
		XDG_CACHE_HOME="$test_root/cache" \
		XDG_DATA_HOME="$test_root/data" \
		godot4 --headless --path "$project_root" -s res://tests/m1_asset_contract_runner.gd \
		> "$log" 2>&1 || status=$?
cat "$log"

supervisor_pid="$(<"$pid_file")"
supervisor_pgid="$(<"$pid_file.pgid")"
if process_exists "$supervisor_pid" || process_group_exists "$supervisor_pgid"; then
	echo "M1_ASSET_LIFECYCLE_RED reason=process-tree-live status=$status pid=$supervisor_pid pgid=$supervisor_pgid" >&2
	exit 1
fi
if [[ "$status" -ne 0 ]]; then
	echo "M1_ASSET_LIFECYCLE_RED reason=runner-status status=$status process_tree=gone" >&2
	exit "$status"
fi

mapfile -t phases < <(sed -n 's/^M1_ASSET_LIFECYCLE phase=\([^ ]*\).*/\1/p' "$log")
if [[ "${phases[*]:-}" != "start complete teardown quit" ]]; then
	echo "M1_ASSET_LIFECYCLE_RED reason=ordered-markers expected=start,complete,teardown,quit actual=${phases[*]:-none} process_tree=gone" >&2
	exit 1
fi
if ! rg -q '^M1_ASSET_CONTRACT_OK files=31 assets=16 captures=9 annotations=6 imports=16 rail=78-100 vfx=action-field sources=verified checked=33$' "$log"; then
	echo "M1_ASSET_LIFECYCLE_RED reason=contract-marker-missing process_tree=gone" >&2
	exit 1
fi
if ! rg -q '^M1_ASSET_LIFECYCLE phase=teardown .*nodes=0 signals=0$' "$log"; then
	echo "M1_ASSET_LIFECYCLE_RED reason=node-signal-teardown process_tree=gone" >&2
	exit 1
fi

complete_line="$(rg '^M1_ASSET_LIFECYCLE phase=complete ' "$log")"
quit_line="$(rg '^M1_ASSET_LIFECYCLE phase=quit ' "$log")"
complete_ms="$(sed -E 's/.*total_ms=([0-9]+).*/\1/' <<< "$complete_line")"
quit_ms="$(sed -E 's/.*total_ms=([0-9]+).*/\1/' <<< "$quit_line")"
if [[ ! "$complete_ms" =~ ^[0-9]+$ || ! "$quit_ms" =~ ^[0-9]+$ || "$quit_ms" -lt "$complete_ms" ]]; then
	echo "M1_ASSET_LIFECYCLE_RED reason=invalid-timing complete_ms=$complete_ms quit_ms=$quit_ms" >&2
	exit 1
fi
quit_delay_ms=$((quit_ms - complete_ms))
if [[ "$quit_delay_ms" -gt 5000 ]]; then
	echo "M1_ASSET_LIFECYCLE_RED reason=quit-delay delay_ms=$quit_delay_ms budget_ms=5000" >&2
	exit 1
fi

echo "VERIFY_M1_ASSET_LIFECYCLE_OK phases=start,complete,teardown,quit contract=31-file quit_delay_ms=$quit_delay_ms nodes=0 signals=0 process_tree=gone scratch=clean-on-exit"
