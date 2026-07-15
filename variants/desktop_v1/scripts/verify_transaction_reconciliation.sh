#!/usr/bin/env bash
set -euo pipefail

test_root="$(mktemp -d "${TMPDIR:-/tmp}/xenogenesis-transaction-reconciliation.XXXXXX")"
trap 'rm -rf "$test_root"' EXIT

run_phase() {
	local case_name="$1"
	local phase="$2"
	local case_root="$test_root/$case_name"
	mkdir -p "$case_root"
	xvfb-run -a env \
		HOME="$case_root/home" \
		XDG_CONFIG_HOME="$case_root/config" \
		XDG_CACHE_HOME="$case_root/cache" \
		XDG_DATA_HOME="$case_root/data" \
		godot4 --audio-driver Dummy --path . -s res://tests/transaction_reconciliation_runner.gd -- \
		"--case=$case_name" "--phase=$phase"
}

failures=0
for case_name in no_backup old_backup candidate_committed candidate_corrupt restored_validation_io; do
	run_phase "$case_name" seed || failures=$((failures + 1))
	run_phase "$case_name" recover || failures=$((failures + 1))
done

if [[ "$failures" -ne 0 ]]; then
	echo "VERIFY_TRANSACTION_RECONCILIATION_FAILED cases=5 processes=10 failures=$failures" >&2
	exit 1
fi

echo "VERIFY_TRANSACTION_RECONCILIATION_OK cases=5 processes=10 authority=exact fingerprints=sha,size,mtime_ns continue=production-ui scratch=clean"
