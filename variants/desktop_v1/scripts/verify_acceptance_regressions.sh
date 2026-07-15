#!/usr/bin/env bash
set -euo pipefail

test_root="$(mktemp -d "${TMPDIR:-/tmp}/xenogenesis-acceptance.XXXXXX")"
trap 'rm -rf "$test_root"' EXIT

xvfb-run -a env \
	HOME="$test_root/home" \
	XDG_CONFIG_HOME="$test_root/config" \
	XDG_CACHE_HOME="$test_root/cache" \
	XDG_DATA_HOME="$test_root/data" \
	godot4 --audio-driver Dummy --path . -s res://tests/acceptance_regression_runner.gd -- \
	"--scratch-data-root=$test_root/data"
