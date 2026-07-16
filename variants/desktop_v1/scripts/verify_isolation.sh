#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$project_root/scripts/timeout_gate.sh"
"$project_root/scripts/verify_post_import_ready.sh"

caller_root="$(mktemp -d "${TMPDIR:-/tmp}/xenogenesis-caller.XXXXXX")"
scratch_parent="$(mktemp -d "${TMPDIR:-/tmp}/xenogenesis-scratch-parent.XXXXXX")"
cleanup_isolation() {
	cleanup_hard_timeout_processes || true
	rm -rf "$caller_root" "$scratch_parent"
}
trap cleanup_isolation EXIT
trap 'exit 143' TERM INT

save_dir="$caller_root/data/godot/app_userdata/异种起源：无尽洪流/saves"
primary="$save_dir/slot_01.json"
backup="$primary.bak"
temp="$primary.tmp"
mkdir -p "$save_dir"
printf '%s\n' 'caller-primary-sentinel' > "$primary"
printf '%s\n' 'caller-backup-sentinel' > "$backup"
printf '%s\n' 'caller-temp-sentinel' > "$temp"
touch -m -d '@1700000000.123456789' "$primary"
touch -m -d '@1700000001.234567891' "$backup"
touch -m -d '@1700000002.345678912' "$temp"

hashes_before="$(sha256sum "$primary" "$backup" "$temp")"
mtimes_before="$(stat -c '%n %y' "$primary" "$backup" "$temp")"
repo_root="$(git -C "$project_root" rev-parse --show-toplevel)"
root_status_before="$(git -C "$repo_root" status --porcelain=v1 --untracked-files=all)"
owned_root="$scratch_parent/owned"
mkdir -p "$owned_root/tmp"
isolation_log="$owned_root/isolation.log"

cd "$project_root"
status=0
run_with_hard_timeout "isolation-production-entry" "${ISOLATION_ENTRY_TIMEOUT_SECONDS:-30}" "${ISOLATION_ENTRY_KILL_AFTER_SECONDS:-5}" \
	env \
		TMPDIR="$owned_root/tmp" \
		HOME="$owned_root/home" \
		XDG_CONFIG_HOME="$owned_root/config" \
		XDG_CACHE_HOME="$owned_root/cache" \
		XDG_DATA_HOME="$owned_root/data" \
		godot4 --headless --path . -s res://tests/isolation_runner.gd -- \
		"--scratch-data-root=$owned_root/data" > "$isolation_log" 2>&1 || status=$?
cat "$isolation_log"
if [[ "$status" -ne 0 ]]; then
	exit "$status"
fi
if ! rg -q '^ISOLATION_PRODUCTION_ENTRY_OK assertions=' "$isolation_log"; then
	echo "Isolation production entry exited without its success marker." >&2
	exit 1
fi

hashes_after="$(sha256sum "$primary" "$backup" "$temp")"
mtimes_after="$(stat -c '%n %y' "$primary" "$backup" "$temp")"
test "$hashes_after" = "$hashes_before"
test "$mtimes_after" = "$mtimes_before"
root_status_after="$(git -C "$repo_root" status --porcelain=v1 --untracked-files=all)"
test "$root_status_after" = "$root_status_before"
rm -rf "$owned_root"
test -z "$(find "$scratch_parent" -mindepth 1 -maxdepth 1 -print -quit)"

echo "VERIFY_ISOLATION_OK production_entry=save-load caller_slots=3 bytes_mtime_ns_paths=unchanged xdg=owned root_status=unchanged scratch=clean"
