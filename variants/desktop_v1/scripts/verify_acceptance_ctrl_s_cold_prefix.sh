#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$project_root/scripts/timeout_gate.sh"

source_repo="${ACCEPTANCE_COLD_PREFIX_SOURCE_REPO:-$(git -C "$project_root" rev-parse --show-toplevel)}"
source_head="${ACCEPTANCE_COLD_PREFIX_SOURCE_HEAD:-$(git -C "$source_repo" rev-parse HEAD)}"
scratch_parent="${ACCEPTANCE_COLD_PREFIX_SCRATCH_PARENT:-${TMPDIR:-/tmp}}"
test_root="$(mktemp -d "$scratch_parent/xenogenesis-acceptance-cold-prefix.XXXXXX")"
clone_root="$test_root/clean-clone"
clean_project="$clone_root/variants/desktop_v1"
runner_path="${ACCEPTANCE_COLD_PREFIX_RUNNER_PATH:-res://tests/acceptance_regression_runner.gd}"

cleanup_cold_prefix() {
	cleanup_hard_timeout_processes || true
	rm -rf "$test_root"
}
trap cleanup_cold_prefix EXIT
trap 'exit 143' TERM INT

run_prefix_gate() {
	local gate_name="$1"
	local timeout_seconds="$2"
	shift 2
	local started_ms status elapsed_ms
	started_ms="$(date +%s%3N)"
	echo "ACCEPTANCE_COLD_PREFIX phase=$gate_name edge=start total_ms=$((started_ms - run_started_ms))"
	status=0
	run_with_hard_timeout "acceptance-cold-prefix-$gate_name" "$timeout_seconds" 5 "$@" || status=$?
	elapsed_ms="$(($(date +%s%3N) - started_ms))"
	echo "ACCEPTANCE_COLD_PREFIX phase=$gate_name edge=end total_ms=$(($(date +%s%3N) - run_started_ms)) elapsed_ms=$elapsed_ms status=$status"
	return "$status"
}

run_started_ms="$(date +%s%3N)"
run_prefix_gate clone 45 git clone --quiet --no-local "$source_repo" "$clone_root"
git -C "$clone_root" checkout --quiet --detach "$source_head"

mkdir -p "$test_root/import-home" "$test_root/import-config" "$test_root/import-cache" "$test_root/import-data"
run_prefix_gate import 40 env \
	HOME="$test_root/import-home" \
	XDG_CONFIG_HOME="$test_root/import-config" \
	XDG_CACHE_HOME="$test_root/import-cache" \
	XDG_DATA_HOME="$test_root/import-data" \
	godot4 --headless --editor --path "$clean_project" --quit
env --chdir="$clean_project" "$clean_project/scripts/verify_post_import_ready.sh"

run_prefix_gate m1-fresh-ui 25 env --chdir="$clean_project" \
	M1_RENDER_CACHE_ROOT="$test_root/m1-render-cache" \
	"$clean_project/scripts/verify_m1_fresh_ui_path.sh"
run_prefix_gate m1-production-entry 70 env --chdir="$clean_project" \
	M1_RENDER_CACHE_ROOT="$test_root/m1-render-cache" \
	"$clean_project/scripts/verify_m1_production_entry.sh"
run_prefix_gate isolation 180 env --chdir="$clean_project" "$clean_project/scripts/verify_isolation.sh"
run_prefix_gate autosave 65 env --chdir="$clean_project" "$clean_project/scripts/verify_autosave_scheduler.sh"

recovery_log="$test_root/recovery.log"
recovery_status=0
run_prefix_gate recovery 55 env \
	ACCEPTANCE_RECOVERY_PROJECT_ROOT="$clean_project" \
	ACCEPTANCE_RECOVERY_RUNNER_PATH="$runner_path" \
	ACCEPTANCE_RECOVERY_SCRATCH_PARENT="$test_root" \
	"$project_root/scripts/verify_acceptance_recovery_lifecycle.sh" > "$recovery_log" 2>&1 || recovery_status=$?
cat "$recovery_log"
if [[ "$recovery_status" -ne 0 ]]; then
	exit "$recovery_status"
fi
if ! rg -q '^VERIFY_ACCEPTANCE_RECOVERY_LIFECYCLE_OK cases=1 assertions=97 .* ctrl_s_msec=[0-9]+ autosave_msec=3[0-6][0-9]{3} .*process_tree=gone scratch=clean-on-exit$' "$recovery_log"; then
	echo "ACCEPTANCE_COLD_PREFIX_RED reason=recovery-summary head=$source_head" >&2
	exit 1
fi

echo "VERIFY_ACCEPTANCE_CTRL_S_COLD_PREFIX_OK head=$source_head budgets_s=25,40,55,65,70,180 ctrl_s_budget_ms=6000 assertions=97 renderer=real pids_pgids=reaped process_tree=gone scratch=clean-on-exit"
