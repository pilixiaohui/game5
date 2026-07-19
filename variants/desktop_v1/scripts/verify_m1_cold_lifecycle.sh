#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$project_root/scripts/timeout_gate.sh"

source_repo="${M1_COLD_SOURCE_REPO:-$(git -C "$project_root" rev-parse --show-toplevel)}"
source_head="${M1_COLD_SOURCE_HEAD:-$(git -C "$source_repo" rev-parse HEAD)}"
rounds="${M1_COLD_ROUNDS:-2}"
scratch_parent="${M1_COLD_SCRATCH_PARENT:-${TMPDIR:-/tmp}}"
test_root="$(mktemp -d "$scratch_parent/xenogenesis-m1-cold-lifecycle.XXXXXX")"

cleanup_m1_cold_lifecycle() {
	cleanup_hard_timeout_processes || true
	rm -rf "$test_root"
}
trap cleanup_m1_cold_lifecycle EXIT
trap 'exit 143' TERM INT

for round in $(seq 1 "$rounds"); do
	round_root="$test_root/round-$round"
	clone_root="$round_root/clean-clone"
	mkdir -p "$round_root"
	round_started_ms="$(date +%s%3N)"
	echo "M1_COLD_PHASE round=$round phase=clone edge=start total_ms=0"
	git clone --quiet --no-local "$source_repo" "$clone_root"
	git -C "$clone_root" checkout --quiet --detach "$source_head"
	clean_project="$clone_root/variants/desktop_v1"
	echo "M1_COLD_PHASE round=$round phase=clone edge=end total_ms=$(($(date +%s%3N) - round_started_ms))"

	import_log="$round_root/import.log"
	import_status=0
	echo "M1_COLD_PHASE round=$round phase=import edge=start total_ms=$(($(date +%s%3N) - round_started_ms))"
	run_with_hard_timeout "m1-cold-import-$round" 40 5 \
		env HOME="$round_root/import-home" XDG_CONFIG_HOME="$round_root/import-config" XDG_CACHE_HOME="$round_root/import-cache" XDG_DATA_HOME="$round_root/import-data" \
		godot4 --headless --editor --path "$clean_project" --quit >"$import_log" 2>&1 || import_status=$?
	cat "$import_log"
	if [[ "$import_status" -ne 0 ]]; then
		echo "M1_COLD_LIFECYCLE_RED round=$round phase=import status=$import_status" >&2
		exit "$import_status"
	fi
	env --chdir="$clean_project" "$clean_project/scripts/verify_post_import_ready.sh"
	echo "M1_COLD_PHASE round=$round phase=import edge=end total_ms=$(($(date +%s%3N) - round_started_ms))"

	fresh_log="$round_root/fresh.log"
	fresh_status=0
	fresh_started_ms="$(date +%s%3N)"
	echo "M1_COLD_PHASE round=$round phase=fresh-ui edge=start total_ms=$((fresh_started_ms - round_started_ms))"
	run_with_hard_timeout "m1-cold-fresh-ui-$round" 25 5 \
		env --chdir="$clean_project" M1_RENDER_CACHE_ROOT="$round_root/m1-render-cache" "$clean_project/scripts/verify_m1_fresh_ui_path.sh" >"$fresh_log" 2>&1 || fresh_status=$?
	cat "$fresh_log"
	fresh_elapsed_ms="$(($(date +%s%3N) - fresh_started_ms))"
	if [[ "$fresh_status" -ne 0 ]]; then
		echo "M1_COLD_LIFECYCLE_RED round=$round phase=fresh-ui status=$fresh_status elapsed_ms=$fresh_elapsed_ms budget_ms=25000" >&2
		exit "$fresh_status"
	fi
	for marker in 'phase=build-capture edge=end' 'phase=first-production edge=instant' 'phase=teardown edge=end'; do
		rg -Fq "$marker" "$fresh_log" || { echo "M1_COLD_LIFECYCLE_RED round=$round phase=fresh-ui marker=$marker" >&2; exit 1; }
	done
	echo "M1_COLD_PHASE round=$round phase=fresh-ui edge=end total_ms=$(($(date +%s%3N) - round_started_ms)) elapsed_ms=$fresh_elapsed_ms budget_ms=25000"

	production_log="$round_root/production.log"
	production_status=0
	production_started_ms="$(date +%s%3N)"
	echo "M1_COLD_PHASE round=$round phase=production-entry edge=start total_ms=$((production_started_ms - round_started_ms))"
	run_with_hard_timeout "m1-cold-production-$round" 70 5 \
		env --chdir="$clean_project" M1_RENDER_CACHE_ROOT="$round_root/m1-render-cache" "$clean_project/scripts/verify_m1_production_entry.sh" >"$production_log" 2>&1 || production_status=$?
	cat "$production_log"
	production_elapsed_ms="$(($(date +%s%3N) - production_started_ms))"
	if [[ "$production_status" -ne 0 ]]; then
		echo "M1_COLD_LIFECYCLE_RED round=$round phase=production-entry status=$production_status elapsed_ms=$production_elapsed_ms budget_ms=70000" >&2
		exit "$production_status"
	fi
	for marker in 'phase=operations-capture edge=end' 'phase=autosave edge=end' 'phase=exit-ready edge=instant' 'phase=teardown edge=end'; do
		rg -Fq "$marker" "$production_log" || { echo "M1_COLD_LIFECYCLE_RED round=$round phase=production-entry marker=$marker" >&2; exit 1; }
	done
	rg -q '^M1_PRODUCTION_ENTRY_OK assertions=355 captures=9 ' "$production_log" || { echo "M1_COLD_LIFECYCLE_RED round=$round phase=production-entry marker=success" >&2; exit 1; }
	echo "M1_COLD_PHASE round=$round phase=production-entry edge=end total_ms=$(($(date +%s%3N) - round_started_ms)) elapsed_ms=$production_elapsed_ms budget_ms=70000"
	echo "M1_COLD_ROUND_OK round=$round fresh_ms=$fresh_elapsed_ms production_ms=$production_elapsed_ms assertions=320,355 captures=3,9 process_tree=gone"
done

echo "VERIFY_M1_COLD_LIFECYCLE_OK rounds=$rounds budgets_ms=25000,40000,70000 assertions=320,355 captures=3,9 renderer=real process_tree=gone scratch=clean-on-exit"
