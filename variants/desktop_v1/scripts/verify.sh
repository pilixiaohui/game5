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
if [[ "${VERIFY_RELEASE_SPLIT_GATES:-0}" != "1" ]]; then
	./scripts/verify_art_v1_capture_atomic.sh
fi
./scripts/verify_cold_import.sh
godot4 --headless --path . -s res://tests/test_runner.gd
./scripts/verify_acceptance_regressions.sh
./scripts/verify_retreat_window.sh
./scripts/verify_ascension_render.sh
./scripts/verify_screenshots.sh
./scripts/verify_save_process.sh
./scripts/verify_transaction_reconciliation.sh
./scripts/verify_save_preflight_recovery.sh
./scripts/verify_primary_read_io.sh
godot4 --headless --path . -s res://tests/persistence_guard_runner.gd -- "--scratch-data-root=$test_root/data"
godot4 --headless --path . -s res://tests/persistence_fault_runner.gd -- "--scratch-data-root=$test_root/data"
if [[ "${VERIFY_RELEASE_SPLIT_GATES:-0}" != "1" ]]; then
	./scripts/verify_timeout_guards.sh
fi
