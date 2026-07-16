#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$project_root/scripts/timeout_gate.sh"
fixture="$project_root/tests/art_v1_capture_fixture.sh"
output_dir="$project_root/artifacts/art_v1/captures"
output_parent="$(dirname "$output_dir")"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/xenogenesis-art-v1-atomic.XXXXXX")"
original_capture="$test_root/original-capture"
gate_complete=0
cp -a "$output_dir" "$original_capture"
exec {capture_gate_lock_fd}<"$output_parent"
flock -x "$capture_gate_lock_fd"
export ART_V1_CAPTURE_LOCK_HELD=1

read_pid_snapshot() {
	local path="$1"
	local snapshot=""
	if ! IFS= read -r snapshot 2>/dev/null < "$path"; then
		return 1
	fi
	if [[ ! "$snapshot" =~ ^[1-9][0-9]*$ ]]; then
		return 1
	fi
	printf '%s\n' "$snapshot"
}

cleanup_atomic_gate() {
	if [[ "$gate_complete" -ne 1 ]]; then
		local pgid_file
		while IFS= read -r pgid_file; do
			local pgid=""
			if pgid="$(read_pid_snapshot "$pgid_file")"; then
				terminate_process_group "$pgid" 1 || true
			fi
		done < <(find "$test_root" -type f -name '*.pid.pgid' 2>/dev/null)
	fi
	cleanup_hard_timeout_processes || true
	if [[ -d "$original_capture" ]]; then
		rm -rf "$output_dir"
		mv "$original_capture" "$output_dir"
	fi
	rm -rf "$test_root"
}
trap cleanup_atomic_gate EXIT

capture_fingerprint() {
	local destination="$1"
	capture_root_fingerprint "$output_dir" "$destination"
}

capture_root_fingerprint() {
	local root="$1"
	local destination="$2"
	local file
	while IFS= read -r file; do
		printf '%s|' "${file#$root/}"
		sha256sum "$file" | awk '{printf "%s|", $1}'
		stat -c '%s|%y' "$file"
	done < <(find "$root" -maxdepth 1 -type f -name '*.png' | sort) > "$destination"
}

assert_capture_unchanged() {
	local label="$1"
	local before="$2"
	local after="$test_root/$label-after.fingerprint"
	capture_fingerprint "$after"
	if ! cmp -s "$before" "$after"; then
		echo "$label changed committed capture paths, bytes, size, or nanosecond mtime." >&2
		diff -u "$before" "$after" >&2 || true
		return 1
	fi
	if [[ "$(find "$output_dir" -maxdepth 1 -type f -name '*.png' | wc -l)" -ne 15 ]]; then
		echo "$label left a partial committed capture set." >&2
		return 1
	fi
	if find "$(dirname "$output_dir")" -maxdepth 1 -type d \( -name '.captures-stage.*' -o -name '.captures-rollback.*' -o -name '.captures-failed.*' \) -print -quit | grep -q .; then
		echo "$label left a capture transaction directory." >&2
		return 1
	fi
}

assert_fixture_process_gone() {
	local pid_file="$1"
	if [[ ! -e "$pid_file" ]]; then
		return 0
	fi
	local pid
	local pgid
	pid="$(read_pid_snapshot "$pid_file")"
	pgid="$(read_pid_snapshot "$pid_file.pgid")"
	if kill -0 "$pid" 2>/dev/null || process_group_exists "$pgid"; then
		echo "Capture fault left a process alive: pid=$pid pgid=$pgid" >&2
		return 1
	fi
}

run_failure_case() {
	local label="$1"
	local mode="$2"
	local expected_kind="$3"
	local case_root="$test_root/$label"
	local scratch_root="$case_root/scratch"
	local before="$case_root-before.fingerprint"
	local state_file="$case_root/invocations"
	local pid_file="$case_root/fixture.pid"
	mkdir -p "$case_root" "$scratch_root"
	capture_fingerprint "$before"
	local status=0
	if [[ "$mode" == "unavailable" ]]; then
		env \
			ART_V1_SCRATCH_PARENT="$scratch_root" \
			ART_V1_GODOT_BIN=/definitely/missing-godot \
			ART_V1_TIMEOUT_SECONDS=2 \
			ART_V1_KILL_AFTER_SECONDS=1 \
			./scripts/capture_art_v1.sh > "$case_root/output.log" 2>&1 || status=$?
	else
		env \
			ART_V1_SCRATCH_PARENT="$scratch_root" \
			ART_V1_GODOT_BIN="$fixture" \
			ART_V1_FIXTURE_SOURCE_DIR="$output_dir" \
			ART_V1_FIXTURE_STATE_FILE="$state_file" \
			ART_V1_FIXTURE_PID_FILE="$pid_file" \
			ART_V1_FIXTURE_MODE="$mode" \
			ART_V1_TIMEOUT_SECONDS=1 \
			ART_V1_VALIDATOR_TIMEOUT_SECONDS=15 \
			ART_V1_KILL_AFTER_SECONDS=1 \
			./scripts/capture_art_v1.sh > "$case_root/output.log" 2>&1 || status=$?
	fi
	if [[ "$status" -eq 0 ]]; then
		echo "$label unexpectedly succeeded." >&2
		cat "$case_root/output.log" >&2
		return 1
	fi
	if [[ "$expected_kind" == "timeout" && "$status" -ne 124 && "$status" -ne 137 ]]; then
		echo "$label returned $status instead of a timeout status." >&2
		cat "$case_root/output.log" >&2
		return 1
	fi
	if [[ "$expected_kind" == "unavailable" && "$status" -ne 127 ]]; then
		echo "$label returned $status instead of the missing executable status." >&2
		cat "$case_root/output.log" >&2
		return 1
	fi
	assert_capture_unchanged "$label" "$before"
	assert_fixture_process_gone "$pid_file"
	if [[ -n "$(find "$scratch_root" -mindepth 1 -print -quit)" ]]; then
		echo "$label left capture scratch content." >&2
		return 1
	fi
	echo "ART_V1_CAPTURE_FAILURE_OK case=$label status=$status committed_fingerprint=unchanged scratch=clean"
}

run_capture_root_case() {
	local mode="$1"
	local case_root="$test_root/root-$mode"
	local before="$case_root-before.fingerprint"
	mkdir -p "$case_root/scratch"
	capture_fingerprint "$before"
	local status=0
	env \
		ART_V1_SCRATCH_PARENT="$case_root/scratch" \
		ART_V1_GODOT_BIN="$fixture" \
		ART_V1_VALIDATOR_BIN="$fixture" \
		ART_V1_FIXTURE_SOURCE_DIR="$output_dir" \
		ART_V1_FIXTURE_STATE_FILE="$case_root/invocations" \
		ART_V1_FIXTURE_MODE="$mode" \
		ART_V1_TIMEOUT_SECONDS=3 \
		ART_V1_VALIDATOR_TIMEOUT_SECONDS=3 \
		ART_V1_KILL_AFTER_SECONDS=1 \
		./scripts/capture_art_v1.sh > "$case_root/output.log" 2>&1 || status=$?
	if [[ "$status" -eq 0 ]]; then
		echo "Unsafe capture root case $mode unexpectedly succeeded." >&2
		cat "$case_root/output.log" >&2
		return 1
	fi
	assert_capture_unchanged "root-$mode" "$before"
	test -z "$(find "$case_root/scratch" -mindepth 1 -print -quit)"
	echo "ART_V1_CAPTURE_ROOT_REFUSED_OK case=$mode status=$status committed=old"
}

run_transaction_fault() {
	local fault="$1"
	local expected_generation="$2"
	local generation_index="$3"
	local case_root="$test_root/transaction-$fault"
	local old_fingerprint="$case_root-old.fingerprint"
	local new_root="$case_root/expected-new"
	local new_fingerprint="$case_root-new.fingerprint"
	local actual_fingerprint="$case_root-actual.fingerprint"
	local generation_mtime="19000000${generation_index}.123456789"
	mkdir -p "$case_root/scratch"
	capture_fingerprint "$old_fingerprint"
	cp -a "$output_dir" "$new_root"
	find "$new_root" -maxdepth 1 -type f -name '*.png' -exec touch -m -d "@$generation_mtime" {} +
	capture_root_fingerprint "$new_root" "$new_fingerprint"

	local status=0
	env \
		ART_V1_SCRATCH_PARENT="$case_root/scratch" \
		ART_V1_GODOT_BIN="$fixture" \
		ART_V1_VALIDATOR_BIN="$fixture" \
		ART_V1_FIXTURE_SOURCE_DIR="$output_dir" \
		ART_V1_FIXTURE_STATE_FILE="$case_root/invocations" \
		ART_V1_FIXTURE_GENERATION_MTIME="$generation_mtime" \
		ART_V1_CAPTURE_FAULT="$fault" \
		ART_V1_TIMEOUT_SECONDS=3 \
		ART_V1_VALIDATOR_TIMEOUT_SECONDS=3 \
		ART_V1_KILL_AFTER_SECONDS=1 \
		./scripts/capture_art_v1.sh > "$case_root/output.log" 2>&1 || status=$?
	if [[ "$status" -eq 0 ]]; then
		echo "Capture transaction fault $fault unexpectedly succeeded." >&2
		cat "$case_root/output.log" >&2
		return 1
	fi
	capture_fingerprint "$actual_fingerprint"
	local expected_fingerprint="$old_fingerprint"
	if [[ "$expected_generation" == "new" ]]; then
		expected_fingerprint="$new_fingerprint"
	fi
	if ! cmp -s "$expected_fingerprint" "$actual_fingerprint"; then
		echo "Capture transaction fault $fault did not retain the complete $expected_generation generation." >&2
		cat "$case_root/output.log" >&2
		diff -u "$expected_fingerprint" "$actual_fingerprint" >&2 || true
		return 1
	fi
	if [[ "$(find "$output_dir" -mindepth 1 -maxdepth 1 -type f | wc -l)" -ne 15 ]] || \
		find "$output_dir" -mindepth 1 -maxdepth 1 ! -type f -print -quit | grep -q .; then
		echo "Capture transaction fault $fault left a partial or non-regular public generation." >&2
		return 1
	fi
	if find "$(dirname "$output_dir")" -maxdepth 1 -type d \( -name '.captures-stage.*' -o -name '.captures-rollback.*' -o -name '.captures-failed.*' \) -print -quit | grep -q .; then
		echo "Capture transaction fault $fault left transaction scratch beside the public generation." >&2
		return 1
	fi
	test -z "$(find "$case_root/scratch" -mindepth 1 -print -quit)"
	echo "ART_V1_CAPTURE_TRANSACTION_OK fault=$fault status=$status generation=$expected_generation files=15 fingerprint=exact"
}

cd "$project_root"
baseline="$test_root/baseline.fingerprint"
capture_fingerprint "$baseline"
if [[ "$(wc -l < "$baseline")" -ne 15 ]]; then
	echo "Atomic capture gate requires the committed 15-file evidence set." >&2
	exit 1
fi

run_failure_case godot-unavailable unavailable unavailable
run_failure_case first-pass-interrupt first_interrupt timeout
run_failure_case second-pass-interrupt second_interrupt timeout
run_failure_case validation-failure validation_failure nonzero
run_capture_root_case extra_directory
run_capture_root_case extra_symlink
run_capture_root_case extra_fifo
run_capture_root_case capture_root_symlink

run_transaction_fault rename-old old 1
run_transaction_fault rename-publish old 2
run_transaction_fault quarantine new 3
run_transaction_fault restore old 4
run_transaction_fault rollback-quarantine new 5
run_transaction_fault rollback-partial-delete new 6

gate_complete=1
echo "VERIFY_ART_V1_CAPTURE_ATOMIC_OK precommit_cases=8 transaction_faults=6 files=15 fingerprints=path,sha256,size,mtime_ns generations=old-or-new capture_root=canonical-owned-exact-regular processes=gone scratch=clean"
