#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$project_root/scripts/timeout_gate.sh"

scratch_parent="${FRESH_SOURCE_SCRATCH_PARENT:-${TMPDIR:-/tmp}}"
control_root="$(mktemp -d "$scratch_parent/xenogenesis-fresh-lifecycle-control.XXXXXX")"
work_root="$(mktemp -d "$scratch_parent/xenogenesis-fresh-lifecycle-work.XXXXXX")"
cleanup_fresh_source() {
	cleanup_hard_timeout_processes || true
	rm -rf "$control_root" "$work_root"
}
trap cleanup_fresh_source EXIT
trap 'exit 143' TERM INT

repo_root="$(git -C "$project_root" rev-parse --show-toplevel)"
source_head="$(git -C "$repo_root" rev-parse HEAD)"
source_status_before="$(git -C "$repo_root" status --porcelain=v1 --untracked-files=all)"

run_with_hard_timeout fresh-source-clone "${FRESH_SOURCE_CLONE_TIMEOUT_SECONDS:-45}" "${FRESH_SOURCE_KILL_AFTER_SECONDS:-5}" \
	"$project_root/scripts/release_health.sh" --clean-clone "$work_root" "$repo_root" "$source_head"

clean_repo="$work_root/clean-clone"
clean_project="$clean_repo/variants/desktop_v1"
if [[ -e "$clean_project/.godot" ]]; then
	echo "Fresh-source clone unexpectedly contained a .godot cache before import." >&2
	exit 1
fi
if [[ "$(git -C "$clean_repo" rev-parse HEAD)" != "$source_head" || -n "$(git -C "$clean_repo" status --porcelain=v1 --untracked-files=all)" ]]; then
	echo "Fresh-source clone does not match the exact clean source commit." >&2
	exit 1
fi
echo "FRESH_SOURCE_CLONE_OK head=$source_head godot_cache=absent root=clean"

import_log="$control_root/cold-import.log"
import_started_ns="$(date +%s%N)"
run_with_hard_timeout fresh-source-cold-import "${FRESH_SOURCE_IMPORT_TIMEOUT_SECONDS:-40}" "${FRESH_SOURCE_KILL_AFTER_SECONDS:-5}" \
	"$project_root/scripts/release_health.sh" --cold-import "$work_root" >"$import_log" 2>&1
import_elapsed_ms=$(( ($(date +%s%N) - import_started_ns) / 1000000 ))
cat "$import_log"
cold_import_count="$(rg -c '^COLD_IMPORT_OK textures=12 cache=project-local$' "$import_log" || true)"
if [[ "$cold_import_count" != "1" ]]; then
	echo "Fresh-source lifecycle requires exactly one successful cold import; observed ${cold_import_count:-0}." >&2
	exit 1
fi

isolation_log="$control_root/isolation.log"
isolation_started_ns="$(date +%s%N)"
run_with_hard_timeout fresh-source-isolation "${FRESH_SOURCE_ISOLATION_TIMEOUT_SECONDS:-180}" "${FRESH_SOURCE_KILL_AFTER_SECONDS:-5}" \
	env --chdir="$clean_project" "$clean_project/scripts/verify_isolation.sh" >"$isolation_log" 2>&1
isolation_elapsed_ms=$(( ($(date +%s%N) - isolation_started_ns) / 1000000 ))
cat "$isolation_log"
if ! rg -q '^ISOLATION_PRODUCTION_ENTRY_OK assertions=14 ' "$isolation_log" || ! rg -q '^VERIFY_ISOLATION_OK ' "$isolation_log"; then
	echo "Fresh-source post-import isolation did not prove all 14 assertions." >&2
	exit 1
fi

acceptance_log="$control_root/acceptance.log"
run_with_hard_timeout fresh-source-acceptance "${FRESH_SOURCE_ACCEPTANCE_OUTER_TIMEOUT_SECONDS:-95}" "${FRESH_SOURCE_KILL_AFTER_SECONDS:-5}" \
	env --chdir="$clean_project" "$clean_project/scripts/verify_acceptance_regressions.sh" >"$acceptance_log" 2>&1
cat "$acceptance_log"
if ! rg -q '^ACCEPTANCE_REGRESSIONS_OK cases=5 resolutions=3 assertions=487 lifecycle_exit_seconds=[0-5] process_tree=gone$' "$acceptance_log"; then
	echo "Fresh-source acceptance did not prove 487 assertions and bounded process-tree exit." >&2
	exit 1
fi

source_status_after="$(git -C "$repo_root" status --porcelain=v1 --untracked-files=all)"
clean_status_after="$(git -C "$clean_repo" status --porcelain=v1 --untracked-files=all)"
if [[ "$source_status_after" != "$source_status_before" || -n "$clean_status_after" ]]; then
	echo "Fresh-source lifecycle changed the source or clean-clone worktree." >&2
	exit 1
fi

rm -rf "$work_root"
if [[ -e "$work_root" ]]; then
	echo "Fresh-source lifecycle work scratch was not removed." >&2
	exit 1
fi

echo "VERIFY_FRESH_SOURCE_LIFECYCLE_OK cold_imports=1 import_timeout=${FRESH_SOURCE_IMPORT_TIMEOUT_SECONDS:-40}s import_elapsed_ms=$import_elapsed_ms isolation_assertions=14 isolation_timeout=${FRESH_SOURCE_ISOLATION_TIMEOUT_SECONDS:-180}s isolation_elapsed_ms=$isolation_elapsed_ms acceptance_assertions=487 acceptance_timeout=80s exit_ready_window=5s process_tree=gone root=clean xdg=owned scratch=clean-on-exit"
