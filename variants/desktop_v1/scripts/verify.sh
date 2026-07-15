#!/usr/bin/env bash
set -euo pipefail

test_root="$(mktemp -d "${TMPDIR:-/tmp}/xenogenesis-verify.XXXXXX")"
trap 'rm -rf "$test_root"' EXIT

export HOME="$test_root/home"
export XDG_CONFIG_HOME="$test_root/config"
export XDG_CACHE_HOME="$test_root/cache"
export XDG_DATA_HOME="$test_root/data"

godot4 --headless --editor --path . --quit
./scripts/verify_persistence_io_contract.sh
./scripts/verify_screenshot_contract.sh
godot4 --headless --path . -s res://tests/test_runner.gd
./scripts/verify_acceptance_regressions.sh
./scripts/verify_screenshots.sh
./scripts/verify_save_process.sh
./scripts/verify_primary_read_io.sh
godot4 --headless --path . -s res://tests/persistence_guard_runner.gd -- "--scratch-data-root=$test_root/data"
godot4 --headless --path . -s res://tests/persistence_fault_runner.gd -- "--scratch-data-root=$test_root/data"
./scripts/verify_timeout_guards.sh
