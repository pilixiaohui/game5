#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$project_root/scripts/timeout_gate.sh"

scratch_parent="${COLD_IMPORT_SCRATCH_PARENT:-${TMPDIR:-/tmp}}"
control_root="$(mktemp -d "$scratch_parent/xenogenesis-cold-import-control.XXXXXX")"
work_root="$(mktemp -d "$scratch_parent/xenogenesis-cold-import-work.XXXXXX")"
cleanup_cold_import() {
	cleanup_hard_timeout_processes || true
	rm -rf "$control_root" "$work_root"
}
trap cleanup_cold_import EXIT
trap 'exit 143' TERM INT

repo_root="$(git -C "$project_root" rev-parse --show-toplevel)"
source_head="$(git -C "$repo_root" rev-parse HEAD)"

run_with_hard_timeout cold-import-clone "${COLD_IMPORT_CLONE_TIMEOUT_SECONDS:-30}" "${COLD_IMPORT_KILL_AFTER_SECONDS:-5}" \
	"$project_root/scripts/release_health.sh" --clean-clone "$work_root" "$repo_root" "$source_head"
run_with_hard_timeout cold-import-success "${COLD_IMPORT_TIMEOUT_SECONDS:-40}" "${COLD_IMPORT_KILL_AFTER_SECONDS:-5}" \
	"$project_root/scripts/release_health.sh" --cold-import "$work_root"
run_with_hard_timeout cold-start-after-import "${COLD_START_TIMEOUT_SECONDS:-25}" "${COLD_IMPORT_KILL_AFTER_SECONDS:-5}" \
	"$project_root/scripts/release_health.sh" --cold-start "$work_root"

clean_project="$work_root/clean-clone/variants/desktop_v1"
required_import="$clean_project/assets/art_v1/title_hive_field_manual_v1.png.import"
imported_resource="$(awk -F'"' '/^path="res:\/\/\.godot\/imported\/.*\.ctex"/ { print $2; exit }' "$required_import")"
if [[ -z "$imported_resource" || ! -s "$clean_project/${imported_resource#res://}" ]]; then
	echo "Cold-import negative fixture could not locate the required title texture." >&2
	exit 1
fi
rm -f "$clean_project/${imported_resource#res://}"

negative_log="$control_root/missing-ctex.log"
started_ns="$(date +%s%N)"
negative_status=0
run_with_hard_timeout cold-start-missing-ctex 8 2 \
	"$project_root/scripts/release_health.sh" --cold-start "$work_root" >"$negative_log" 2>&1 || negative_status=$?
elapsed_ns=$(( $(date +%s%N) - started_ns ))
cat "$negative_log"
if [[ "$negative_status" -eq 0 || "$negative_status" -eq 124 || "$negative_status" -eq 137 ]]; then
	echo "Missing imported texture returned $negative_status instead of failing fast." >&2
	exit 1
fi
if [[ "$elapsed_ns" -gt 8000000000 ]]; then
	echo "Missing imported texture exceeded the fail-fast deadline: elapsed_ns=$elapsed_ns" >&2
	exit 1
fi
if ! rg -n 'CLEAN_START_FAILED|Unable to open|Failed loading resource|Failed to load|Parse Error|SCRIPT ERROR:' "$negative_log"; then
	echo "Missing imported texture did not produce a resource or parse failure." >&2
	exit 1
fi

echo "VERIFY_COLD_IMPORT_OK textures=12 import_timeout=${COLD_IMPORT_TIMEOUT_SECONDS:-40}s cold_start_timeout=${COLD_START_TIMEOUT_SECONDS:-25}s missing_ctex=fail-fast elapsed_ms=$((elapsed_ns / 1000000)) scratch=clean-on-exit"
