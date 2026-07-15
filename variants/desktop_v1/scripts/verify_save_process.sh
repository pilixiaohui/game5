#!/usr/bin/env bash
set -euo pipefail

test_root="$(mktemp -d "${TMPDIR:-/tmp}/xenogenesis-save-process.XXXXXX")"
trap 'rm -rf "$test_root"' EXIT

run_phase() {
  env \
    HOME="$test_root/home" \
    XDG_CONFIG_HOME="$test_root/config" \
    XDG_CACHE_HOME="$test_root/cache" \
    XDG_DATA_HOME="$test_root/data" \
    godot4 --headless --path . -s res://tests/save_process_runner.gd -- "--phase=$1"
}

run_phase seed
run_phase load-progress-autosave
run_phase reload
