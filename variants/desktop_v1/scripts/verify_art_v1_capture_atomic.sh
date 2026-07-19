#!/usr/bin/env bash
set -euo pipefail

gate_mode="${1:---all}"
case "$gate_mode" in
	--all|--lock-wait-only|--skip-lock-wait) ;;
	*)
		echo "Unknown capture atomic gate mode: $gate_mode" >&2
		exit 2
		;;
esac

gate_project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -n "${ART_V1_CAPTURE_SUBJECT_ROOT:-}" && "$gate_mode" != "--lock-wait-only" ]]; then
	echo "ART_V1_CAPTURE_SUBJECT_ROOT is restricted to the lock-wait oracle." >&2
	exit 2
fi
project_root="$(realpath "${ART_V1_CAPTURE_SUBJECT_ROOT:-$gate_project_root}")"
source "$gate_project_root/scripts/timeout_gate.sh"
fixture="$gate_project_root/tests/art_v1_capture_fixture.sh"
output_dir="$project_root/artifacts/art_v1/captures"
output_parent="$(dirname "$output_dir")"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/xenogenesis-art-v1-atomic.XXXXXX")"
original_capture="$test_root/original-capture"
gate_complete=0
lock_holder_pid=""
lock_holder_release=""
lock_waiter_pid=""
lock_waiter_pgid=""
lock_waiter_boot_id=""
lock_waiter_pid_namespace=""
lock_waiter_start_time=""
lock_wait_started_ns=0
lock_wait_phase_started_ns=0
lock_wait_child_status=0
atomic_started_ns="$(date +%s%N)"
atomic_phase_started_ns="$atomic_started_ns"
cp -a "$output_dir" "$original_capture"

emit_atomic_phase() {
	local phase="$1"
	local now_ns
	now_ns="$(date +%s%N)"
	printf 'ART_V1_CAPTURE_ATOMIC_PHASE phase=%s elapsed_ms=%d phase_ms=%d\n' \
		"$phase" "$(( (now_ns - atomic_started_ns) / 1000000 ))" \
		"$(( (now_ns - atomic_phase_started_ns) / 1000000 ))"
	atomic_phase_started_ns="$now_ns"
}

emit_lock_wait_phase() {
	local phase="$1"
	local detail="${2:-}"
	local now_ns
	now_ns="$(date +%s%N)"
	printf 'ART_V1_CAPTURE_LOCK_WAIT_PHASE phase=%s elapsed_ms=%d phase_ms=%d' \
		"$phase" "$(( (now_ns - lock_wait_started_ns) / 1000000 ))" \
		"$(( (now_ns - lock_wait_phase_started_ns) / 1000000 ))"
	if [[ -n "$detail" ]]; then
		printf ' %s' "$detail"
	fi
	printf '\n'
	lock_wait_phase_started_ns="$now_ns"
}

wait_for_lock_waiter_status() {
	local pid="$1"
	local wait_seconds="$2"
	local deadline_ns=$(( $(date +%s%N) + wait_seconds * 1000000000 ))
	local state=""
	lock_wait_child_status=0
	while true; do
		state="$(ps -o stat= -p "$pid" 2>/dev/null | tr -d ' ')"
		if [[ -z "$state" || "$state" == Z* ]]; then
			wait "$pid" || lock_wait_child_status=$?
			return 0
		fi
		if (( $(date +%s%N) >= deadline_ns )); then
			return 1
		fi
		sleep 0.02
	done
}

snapshot_lock_waiter_identity() {
	local pid="$1"
	local identity=""
	local stat_fields=""
	local pgrp session start_time state
	local attempt
	for attempt in $(seq 1 100); do
		identity="$(read_process_identity "$pid")" || return 1
		stat_fields="$(read_process_stat_fields "$pid")" || return 1
		read -r pgrp session start_time state <<< "$stat_fields"
		if [[ "$pgrp" == "$pid" && "$session" == "$pid" ]]; then
			read -r lock_waiter_boot_id lock_waiter_pid_namespace lock_waiter_start_time <<< "$identity"
			lock_waiter_pid="$pid"
			lock_waiter_pgid="$pid"
			return 0
		fi
		sleep 0.01
	done
	return 1
}

clear_lock_waiter_identity() {
	lock_waiter_pid=""
	lock_waiter_pgid=""
	lock_waiter_boot_id=""
	lock_waiter_pid_namespace=""
	lock_waiter_start_time=""
}

cleanup_authenticated_lock_waiter() {
	if [[ -z "$lock_waiter_pid" || -z "$lock_waiter_pgid" ]]; then
		return 0
	fi
	if ! process_group_exists "$lock_waiter_pgid"; then
		wait "$lock_waiter_pid" 2>/dev/null || true
		clear_lock_waiter_identity
		return 0
	fi
	if ! group_identity_matches "$lock_waiter_pid" "$lock_waiter_pgid" \
		"$lock_waiter_boot_id" "$lock_waiter_pid_namespace" "$lock_waiter_start_time"; then
		echo "Refused capture waiter group cleanup after identity mismatch: pid=$lock_waiter_pid pgid=$lock_waiter_pgid" >&2
		return 1
	fi
	kill -TERM -- "-$lock_waiter_pgid" 2>/dev/null || true
	if ! wait_for_timeout_group_members_exit "$lock_waiter_pid" "$lock_waiter_pgid" 1; then
		if ! group_identity_matches "$lock_waiter_pid" "$lock_waiter_pgid" \
			"$lock_waiter_boot_id" "$lock_waiter_pid_namespace" "$lock_waiter_start_time"; then
			echo "Refused capture waiter KILL after identity mismatch: pid=$lock_waiter_pid pgid=$lock_waiter_pgid" >&2
			return 1
		fi
		kill -KILL -- "-$lock_waiter_pgid" 2>/dev/null || true
		if ! wait_for_timeout_group_members_exit "$lock_waiter_pid" "$lock_waiter_pgid" 1; then
			echo "Capture waiter descendants survived authenticated cleanup: pgid=$lock_waiter_pgid" >&2
			return 1
		fi
	fi
	if ! wait_for_lock_waiter_status "$lock_waiter_pid" 1; then
		echo "Capture waiter leader survived authenticated cleanup: pid=$lock_waiter_pid" >&2
		return 1
	fi
	if process_group_exists "$lock_waiter_pgid"; then
		echo "Capture waiter process group survived authenticated cleanup: pgid=$lock_waiter_pgid" >&2
		return 1
	fi
	clear_lock_waiter_identity
}

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
	if [[ -n "$lock_holder_release" ]]; then
		: > "$lock_holder_release"
	fi
	if [[ -n "$lock_holder_pid" ]] && kill -0 "$lock_holder_pid" 2>/dev/null; then
		kill -TERM "$lock_holder_pid" 2>/dev/null || true
		wait "$lock_holder_pid" 2>/dev/null || true
	fi
	if [[ -n "$lock_waiter_pgid" ]] && process_group_exists "$lock_waiter_pgid"; then
		cleanup_authenticated_lock_waiter || true
	fi
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

wait_for_capture_lock_boundary() {
	local pid="$1"
	local wait_channel=""
	local child_pid=""
	local child_name=""
	local child_fields=""
	local child_pgrp child_session child_start child_state
	for _attempt in $(seq 1 200); do
		if ! process_exists "$pid"; then
			return 1
		fi
		IFS= read -r wait_channel < "/proc/$pid/wchan" || true
		if [[ "$wait_channel" == *nanosleep* ]]; then
			return 0
		fi
		for child_pid in $(< "/proc/$pid/task/$pid/children"); do
			IFS= read -r child_name 2>/dev/null < "/proc/$child_pid/comm" || continue
			[[ "$child_name" == "flock" || "$child_name" == "sleep" ]] || continue
			child_fields="$(read_process_stat_fields "$child_pid")" || continue
			read -r child_pgrp child_session child_start child_state <<< "$child_fields"
			if [[ "$child_pgrp" == "$pid" && "$child_session" == "$pid" ]]; then
				return 0
			fi
		done
		sleep 0.01
	done
	return 1
}

assert_capture_lock_case_clean() {
	local label="$1"
	local scratch_root="$2"
	local before="$3"
	assert_capture_unchanged "$label" "$before"
	if [[ -n "$(find "$scratch_root" -mindepth 1 -print -quit)" ]]; then
		echo "$label left capture control/work scratch after lock wait interruption." >&2
		find "$scratch_root" -mindepth 1 -maxdepth 2 -print >&2
		return 1
	fi
}

release_capture_lock_holder() {
	local holder_done="$1"
	: > "$lock_holder_release"
	emit_lock_wait_phase holder-release-sent
	for _attempt in $(seq 1 100); do
		[[ -s "$holder_done" ]] && break
		sleep 0.01
	done
	if [[ ! -s "$holder_done" ]]; then
		kill -TERM "$lock_holder_pid" 2>/dev/null || true
		wait "$lock_holder_pid" 2>/dev/null || true
		echo "Capture lock holder exceeded its one-second release bound." >&2
		return 1
	fi
	wait "$lock_holder_pid"
	lock_holder_pid=""
	lock_holder_release=""
	emit_lock_wait_phase holder-reaped
}

run_capture_lock_contention_cases() {
	local case_root="$test_root/lock-contention"
	local ready_file="$case_root/holder-ready"
	lock_holder_release="$case_root/holder-release"
	local holder_done="$case_root/holder-done"
	lock_wait_started_ns="$(date +%s%N)"
	lock_wait_phase_started_ns="$lock_wait_started_ns"
	mkdir -p "$case_root"
	bash -c '
		exec 9<"$1"
		flock -x 9
		printf "%s\n" ready > "$2"
		while [[ ! -e "$3" ]]; do sleep 0.02; done
		printf "%s\n" done > "$4"
	' capture-lock-holder "$output_parent" "$ready_file" "$lock_holder_release" "$holder_done" &
	lock_holder_pid=$!
	for _attempt in $(seq 1 100); do
		[[ -s "$ready_file" ]] && break
		sleep 0.01
	done
	test -s "$ready_file"
	emit_lock_wait_phase holder-ready

	local term_scratch="$case_root/term-scratch"
	local term_before="$case_root/term-before.fingerprint"
	mkdir -p "$term_scratch"
	capture_fingerprint "$term_before"
	emit_lock_wait_phase term-case-start fingerprint=recorded
	setsid env ART_V1_CAPTURE_LOCK_HELD=0 ART_V1_SCRATCH_PARENT="$term_scratch" \
		ART_V1_GODOT_BIN=/definitely/missing-godot ./scripts/capture_art_v1.sh > "$case_root/term.log" 2>&1 &
	local waiter_pid=$!
	if ! snapshot_lock_waiter_identity "$waiter_pid"; then
		echo "Capture TERM waiter did not become an authenticated session leader: pid=$waiter_pid" >&2
		return 1
	fi
	if ! wait_for_capture_lock_boundary "$waiter_pid"; then
		local waiter_wchan=""
		IFS= read -r waiter_wchan < "/proc/$waiter_pid/wchan" 2>/dev/null || true
		echo "Capture TERM waiter did not reach an authenticated lock boundary: wchan=${waiter_wchan:-gone}" >&2
		return 1
	fi
	emit_lock_wait_phase term-wait-observed
	kill -TERM "$waiter_pid"
	emit_lock_wait_phase term-leader-signal-sent
	if ! wait_for_lock_waiter_status "$waiter_pid" 1; then
		local failed_waiter_pgid="$lock_waiter_pgid"
		emit_lock_wait_phase term-leader-exit-timeout cleanup=authenticated-group
		if ! cleanup_authenticated_lock_waiter; then
			echo "Capture TERM waiter cleanup failed after its one-second exit bound: pgid=$failed_waiter_pgid" >&2
			return 1
		fi
		release_capture_lock_holder "$holder_done"
		assert_capture_lock_case_clean lock-wait-term-failed "$term_scratch" "$term_before"
		emit_lock_wait_phase term-failure-cleanup-verified committed=unchanged,scratch=clean,processes=gone
		echo "Capture TERM waiter exceeded its one-second exit bound: pgid=$failed_waiter_pgid cleanup=complete" >&2
		return 1
	fi
	local term_status="$lock_wait_child_status"
	if process_group_exists "$lock_waiter_pgid"; then
		echo "Capture TERM waiter process group survived direct-child reap: pgid=$lock_waiter_pgid" >&2
		return 1
	fi
	clear_lock_waiter_identity
	emit_lock_wait_phase term-case-reaped "status=$term_status"
	if [[ "$term_status" -eq 0 ]]; then
		echo "Capture TERM waiter unexpectedly succeeded." >&2
		return 1
	fi
	assert_capture_lock_case_clean lock-wait-term "$term_scratch" "$term_before"
	emit_lock_wait_phase term-fingerprint-verified scratch=clean

	local timeout_scratch="$case_root/timeout-scratch"
	local timeout_before="$case_root/timeout-before.fingerprint"
	mkdir -p "$timeout_scratch"
	capture_fingerprint "$timeout_before"
	emit_lock_wait_phase hard-timeout-start fingerprint=recorded
	local timeout_status=0
	run_with_hard_timeout capture-lock-wait 1 1 env \
		ART_V1_CAPTURE_LOCK_HELD=0 \
		ART_V1_SCRATCH_PARENT="$timeout_scratch" \
		ART_V1_GODOT_BIN=/definitely/missing-godot \
		./scripts/capture_art_v1.sh > "$case_root/timeout.log" 2>&1 || timeout_status=$?
	emit_lock_wait_phase hard-timeout-returned "status=$timeout_status"
	if [[ "$timeout_status" -ne 124 && "$timeout_status" -ne 137 ]]; then
		echo "Capture hard-timeout waiter returned unexpected status: $timeout_status" >&2
		cat "$case_root/timeout.log" >&2
		return 1
	fi
	assert_capture_lock_case_clean lock-wait-timeout "$timeout_scratch" "$timeout_before"
	emit_lock_wait_phase hard-timeout-fingerprint-verified scratch=clean

	release_capture_lock_holder "$holder_done"
	echo "ART_V1_CAPTURE_LOCK_WAIT_OK term_status=$term_status timeout_status=$timeout_status committed=unchanged scratch=clean processes=gone"
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
		ART_V1_CAPTURE_FIXTURE_DIRECT=1 \
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
		ART_V1_CAPTURE_FIXTURE_DIRECT=1 \
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

lock_wait_interruptions=0
if [[ "$gate_mode" != "--skip-lock-wait" ]]; then
	run_capture_lock_contention_cases
	lock_wait_interruptions=2
fi
if [[ "$gate_mode" == "--lock-wait-only" ]]; then
	gate_complete=1
	echo "VERIFY_ART_V1_CAPTURE_LOCK_WAIT_OK interruptions=2 committed=unchanged processes=gone scratch=clean"
	exit 0
fi
exec {capture_gate_lock_fd}<"$output_parent"
flock -x "$capture_gate_lock_fd"
export ART_V1_CAPTURE_LOCK_HELD=1

run_failure_case godot-unavailable unavailable unavailable
emit_atomic_phase godot-unavailable
run_failure_case first-pass-interrupt first_interrupt timeout
emit_atomic_phase first-pass-interrupt
run_failure_case second-pass-interrupt second_interrupt timeout
emit_atomic_phase second-pass-interrupt
run_failure_case validation-failure validation_failure nonzero
emit_atomic_phase validation-failure
run_capture_root_case extra_directory
emit_atomic_phase extra-directory
run_capture_root_case extra_symlink
emit_atomic_phase extra-symlink
run_capture_root_case extra_fifo
emit_atomic_phase extra-fifo
run_capture_root_case capture_root_symlink
emit_atomic_phase capture-root-symlink

run_transaction_fault rename-old old 1
emit_atomic_phase rename-old
run_transaction_fault rename-publish old 2
emit_atomic_phase rename-publish
run_transaction_fault quarantine new 3
emit_atomic_phase quarantine
run_transaction_fault restore old 4
emit_atomic_phase restore
run_transaction_fault rollback-quarantine new 5
emit_atomic_phase rollback-quarantine
run_transaction_fault rollback-partial-delete new 6
emit_atomic_phase rollback-partial-delete

gate_complete=1
echo "VERIFY_ART_V1_CAPTURE_ATOMIC_OK lock_wait_interruptions=$lock_wait_interruptions precommit_cases=8 transaction_faults=6 files=15 fingerprints=path,sha256,size,mtime_ns generations=old-or-new capture_root=canonical-owned-exact-regular processes=gone scratch=clean"
