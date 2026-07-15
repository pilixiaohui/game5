#!/usr/bin/env bash
set -euo pipefail

caller_root="$(mktemp -d "${TMPDIR:-/tmp}/xenogenesis-caller.XXXXXX")"
scratch_parent="$(mktemp -d "${TMPDIR:-/tmp}/xenogenesis-scratch-parent.XXXXXX")"
trap 'rm -rf "$caller_root" "$scratch_parent"' EXIT

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

env \
  TMPDIR="$scratch_parent" \
  HOME="$caller_root/home" \
  XDG_CONFIG_HOME="$caller_root/config" \
  XDG_CACHE_HOME="$caller_root/cache" \
  XDG_DATA_HOME="$caller_root/data" \
  ./scripts/verify.sh

hashes_after="$(sha256sum "$primary" "$backup" "$temp")"
mtimes_after="$(stat -c '%n %y' "$primary" "$backup" "$temp")"
test "$hashes_after" = "$hashes_before"
test "$mtimes_after" = "$mtimes_before"
test -z "$(find "$scratch_parent" -mindepth 1 -maxdepth 1 -print -quit)"

echo "VERIFY_ISOLATION_OK caller_slots=3 bytes_mtime_ns_paths=unchanged scratch=clean"
