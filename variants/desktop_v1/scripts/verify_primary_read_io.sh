#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/xenogenesis-primary-read-io.XXXXXX")"
trap 'rm -rf "$test_root"' EXIT

export HOME="$test_root/home"
export XDG_CONFIG_HOME="$test_root/config"
export XDG_CACHE_HOME="$test_root/cache"
export XDG_DATA_HOME="$test_root/data"

run_phase() {
	timeout --signal=TERM --kill-after=5s 30s \
		godot4 --headless --path "$project_root" -s res://tests/primary_read_io_runner.gd -- \
		"--scratch-data-root=$test_root/data" "--phase=$1"
}

run_phase seed
save_dir="$test_root/data/godot/app_userdata/异种起源：无尽洪流/saves"
primary="$save_dir/slot_01.json"
backup="$primary.bak"
touch -m -d '@1700000100.123456789' "$primary"
touch -m -d '@1700000101.987654321' "$backup"
hashes_before="$(sha256sum "$primary" "$backup")"
mtimes_before="$(stat -c '%n %y' "$primary" "$backup")"

for phase in exists open read; do
	run_phase "$phase"
	test "$(sha256sum "$primary" "$backup")" = "$hashes_before"
	test "$(stat -c '%n %y' "$primary" "$backup")" = "$mtimes_before"
done

echo "VERIFY_PRIMARY_READ_IO_OK phases=exists,open,read bytes_mtime_ns=unchanged persistence=blocked"
