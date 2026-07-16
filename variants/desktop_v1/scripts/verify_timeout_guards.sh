#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$project_root/scripts/timeout_gate.sh"
hanging_command="$project_root/tests/hanging_process.sh"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/xenogenesis-timeout-guards.XXXXXX")"
guards_complete=0
ensure_hard_timeout_registry
find "$HARD_TIMEOUT_REGISTRY_ROOT" -maxdepth 1 -type f -name '*.record' -printf '%f\n' | sort > "$test_root/registry-baseline"

read_pid_snapshot() {
	local path="$1"
	local snapshot=""
	if ! IFS= read -r snapshot 2>/dev/null < "$path"; then
		return 1
	fi
	if [[ ! "$snapshot" =~ ^[0-9]+$ ]]; then
		return 1
	fi
	printf '%s\n' "$snapshot"
}

cleanup_timeout_guards() {
	if [[ "$guards_complete" -ne 1 ]]; then
		local pgid_file
		while IFS= read -r pgid_file; do
			local pgid_snapshot=""
			if pgid_snapshot="$(read_pid_snapshot "$pgid_file")"; then
				terminate_process_group "$pgid_snapshot" 1 || true
			fi
		done < <(find "$test_root" -type f -name '*.pid.pgid' 2>/dev/null)
	fi
	cleanup_hard_timeout_processes || true
	rm -rf "$test_root"
}
trap cleanup_timeout_guards EXIT

assert_process_group_gone() {
	local pid_file="$1"
	local child_pid=""
	local child_pgid=""
	if ! child_pid="$(read_pid_snapshot "$pid_file")" || ! child_pgid="$(read_pid_snapshot "$pid_file.pgid")"; then
		echo "Fixture did not publish PID and PGID: $pid_file" >&2
		return 1
	fi
	if ! kill -0 "$child_pid" 2>/dev/null && ! process_group_exists "$child_pgid"; then
		return 0
	fi
	echo "Gate left a descendant or process group alive: pid=$child_pid pgid=$child_pgid" >&2
	return 1
}

assert_scratch_empty() {
	local label="$1"
	local scratch_parent="$2"
	if [[ -n "$(find "$scratch_parent" -mindepth 1 -print -quit)" ]]; then
		echo "$label left scratch content under $scratch_parent" >&2
		return 1
	fi
}

assert_release_screenshot_trace() {
	local trace_file="$1"
	local outer_line=""
	local screenshot_line=""
	outer_line="$(awk '$1 == "release-health-overall" { line = $0 } END { print line }' "$trace_file")"
	screenshot_line="$(awk '$1 == "screenshots" { line = $0 } END { print line }' "$trace_file")"
	if [[ ! "$outer_line" =~ ^release-health-overall\ [1-9][0-9]*\ [1-9][0-9]*\ [0-9]+$ ]] || \
		[[ ! "$screenshot_line" =~ ^screenshots\ [1-9][0-9]*\ [1-9][0-9]*\ [0-9]+$ ]]; then
		echo "Release screenshot chain did not record actual outer and nested PID/PGID values." >&2
		cat "$trace_file" >&2
		return 1
	fi
	local outer_gate outer_pid outer_pgid outer_parent
	local screenshot_gate screenshot_pid screenshot_pgid screenshot_parent
	read -r outer_gate outer_pid outer_pgid outer_parent <<< "$outer_line"
	read -r screenshot_gate screenshot_pid screenshot_pgid screenshot_parent <<< "$screenshot_line"
	if [[ "$screenshot_parent" != "$outer_pid" ]]; then
		echo "Nested screenshot timeout was not registered under the outer timeout PID." >&2
		return 1
	fi
	if kill -0 "$outer_pid" 2>/dev/null || process_group_exists "$outer_pgid" || \
		kill -0 "$screenshot_pid" 2>/dev/null || process_group_exists "$screenshot_pgid"; then
		echo "Recorded release screenshot timeout PID/PGID survived gate return." >&2
		return 1
	fi
}

expect_timeout() {
	local label="$1"
	local scratch_parent="$2"
	local pid_file="$3"
	shift 3
	mkdir -p "$scratch_parent"
	rm -f "$pid_file" "$pid_file.pgid"
	local started_ns
	started_ns="$(date +%s%N)"
	local status=0
	"$@" || status=$?
	local elapsed_ns=$(( $(date +%s%N) - started_ns ))
	if [[ "$status" -ne 70 && "$status" -ne 124 && "$status" -ne 137 ]]; then
		echo "$label returned $status instead of a timeout status." >&2
		return 1
	fi
	if [[ "$elapsed_ns" -gt 6000000000 ]]; then
		echo "$label exceeded the bounded timeout margin: elapsed_ns=$elapsed_ns" >&2
		return 1
	fi
	assert_process_group_gone "$pid_file"
	assert_scratch_empty "$label" "$scratch_parent"
}

expect_leader_exit_cleanup() {
	local scratch_parent="$1"
	local pid_file="$2"
	mkdir -p "$scratch_parent"
	rm -f "$pid_file" "$pid_file.pgid"
	local status=0
	env \
		AUTOSAVE_TIMEOUT_SECONDS=5 \
		AUTOSAVE_KILL_AFTER_SECONDS=1 \
		AUTOSAVE_SCRATCH_PARENT="$scratch_parent" \
		AUTOSAVE_GODOT_BIN="$hanging_command" \
		HANG_MODE=leader_exit \
		HANG_PID_FILE="$pid_file" \
		./scripts/verify_autosave_scheduler.sh || status=$?
	test "$status" -eq 0
	assert_process_group_gone "$pid_file"
	assert_scratch_empty leader-exit "$scratch_parent"
}

expect_screenshot_leader_exit_cleanup() {
	local scratch_parent="$1"
	local project_fixture="$2"
	local pid_file="$3"
	mkdir -p "$scratch_parent" "$project_fixture"
	rm -f "$pid_file" "$pid_file.pgid"
	local started_ns
	started_ns="$(date +%s%N)"
	local status=0
	env \
		SCREENSHOT_TIMEOUT_SECONDS=5 \
		SCREENSHOT_KILL_AFTER_SECONDS=1 \
		SCREENSHOT_SCRATCH_PARENT="$scratch_parent" \
		SCREENSHOT_PROJECT_ROOT="$project_fixture" \
		SCREENSHOT_GODOT_BIN="$hanging_command" \
		HANG_MODE=leader_exit \
		HANG_PID_FILE="$pid_file" \
		./scripts/verify_screenshots.sh || status=$?
	local elapsed_ns=$(( $(date +%s%N) - started_ns ))
	if [[ "$status" -eq 0 ]]; then
		echo "Screenshot leader-exit fixture passed without producing screenshots." >&2
		return 1
	fi
	if [[ "$elapsed_ns" -gt 6000000000 ]]; then
		echo "Screenshot leader-exit cleanup exceeded its bound: elapsed_ns=$elapsed_ns" >&2
		return 1
	fi
	assert_process_group_gone "$pid_file"
	assert_scratch_empty screenshot-leader-exit "$scratch_parent"
}

expect_term_cleanup() {
	local scratch_parent="$1"
	local pid_file="$2"
	mkdir -p "$scratch_parent"
	rm -f "$pid_file" "$pid_file.pgid"
	env \
		AUTOSAVE_TIMEOUT_SECONDS=20 \
		AUTOSAVE_KILL_AFTER_SECONDS=1 \
		AUTOSAVE_SCRATCH_PARENT="$scratch_parent" \
		AUTOSAVE_GODOT_BIN="$hanging_command" \
		HANG_MODE=wait \
		HANG_PID_FILE="$pid_file" \
		./scripts/verify_autosave_scheduler.sh &
	local wrapper_pid=$!
	for _attempt in $(seq 1 100); do
		if [[ -s "$pid_file.pgid" ]]; then
			break
		fi
		sleep 0.02
	done
	test -s "$pid_file.pgid"
	kill -TERM "$wrapper_pid"
	local status=0
	wait "$wrapper_pid" || status=$?
	test "$status" -eq 143
	assert_process_group_gone "$pid_file"
	assert_scratch_empty external-term "$scratch_parent"
}

expect_release_cold_import_term_cleanup() {
	local scratch_parent="$1"
	local pid_file="$2"
	mkdir -p "$scratch_parent"
	rm -f "$pid_file" "$pid_file.pgid"
	env \
		RELEASE_HEALTH_SCRATCH_PARENT="$scratch_parent" \
		RELEASE_HEALTH_OVERALL_TIMEOUT_SECONDS=20 \
		RELEASE_HEALTH_COLD_IMPORT_TIMEOUT_SECONDS=15 \
		RELEASE_HEALTH_KILL_AFTER_SECONDS=1 \
		RELEASE_HEALTH_TEST_ONLY_GATE=cold-import \
		RELEASE_HEALTH_TEST_HANG_GATE=cold-import \
		RELEASE_HEALTH_TEST_HANG_COMMAND="$hanging_command" \
		HANG_MODE=wait \
		HANG_PID_FILE="$pid_file" \
		./scripts/release_health.sh &
	local wrapper_pid=$!
	for _attempt in $(seq 1 100); do
		if [[ -s "$pid_file.pgid" ]]; then
			break
		fi
		sleep 0.02
	done
	test -s "$pid_file.pgid"
	kill -TERM "$wrapper_pid"
	local status=0
	wait "$wrapper_pid" || status=$?
	test "$status" -eq 143
	assert_process_group_gone "$pid_file"
	assert_scratch_empty release-cold-import-term "$scratch_parent"
}

expect_release_screenshot_timeout() {
	local label="$1"
	local scratch_parent="$2"
	local pid_file="$3"
	local trace_file="$4"
	rm -f "$trace_file"
	expect_timeout "$label" "$scratch_parent" "$pid_file" \
		env \
			HARD_TIMEOUT_TRACE_FILE="$trace_file" \
			RELEASE_HEALTH_SCRATCH_PARENT="$scratch_parent" \
			RELEASE_HEALTH_OVERALL_TIMEOUT_SECONDS=6 \
			RELEASE_HEALTH_SCREENSHOTS_TIMEOUT_SECONDS=1 \
			RELEASE_HEALTH_KILL_AFTER_SECONDS=1 \
			RELEASE_HEALTH_TEST_ONLY_GATE=screenshots \
			RELEASE_HEALTH_TEST_HANG_GATE=screenshots \
			RELEASE_HEALTH_TEST_HANG_COMMAND="$hanging_command" \
			HANG_MODE=wait \
			HANG_PID_FILE="$pid_file" \
			./scripts/release_health.sh
	assert_release_screenshot_trace "$trace_file"
}

cd "$project_root"
normal_status=0
run_with_hard_timeout normal-no-descendant 2 1 env HANG_MODE=normal "$hanging_command" || normal_status=$?
test "$normal_status" -eq 0
test "${#HARD_TIMEOUT_ACTIVE_PGIDS[@]}" -eq 0

scheduler_parent="$test_root/scheduler-parent"
expect_timeout scheduler "$scheduler_parent" "$test_root/scheduler.pid" \
	env \
		AUTOSAVE_TIMEOUT_SECONDS=1 \
		AUTOSAVE_KILL_AFTER_SECONDS=1 \
		AUTOSAVE_SCRATCH_PARENT="$scheduler_parent" \
		AUTOSAVE_GODOT_BIN="$hanging_command" \
		HANG_MODE=wait \
		HANG_PID_FILE="$test_root/scheduler.pid" \
		./scripts/verify_autosave_scheduler.sh

stubborn_parent="$test_root/stubborn-parent"
expect_timeout stubborn-scheduler "$stubborn_parent" "$test_root/stubborn.pid" \
	env \
		AUTOSAVE_TIMEOUT_SECONDS=1 \
		AUTOSAVE_KILL_AFTER_SECONDS=1 \
		AUTOSAVE_SCRATCH_PARENT="$stubborn_parent" \
		AUTOSAVE_GODOT_BIN="$hanging_command" \
		HANG_MODE=ignore_term \
		HANG_PID_FILE="$test_root/stubborn.pid" \
		./scripts/verify_autosave_scheduler.sh

leader_parent="$test_root/leader-parent"
expect_leader_exit_cleanup "$leader_parent" "$test_root/leader.pid"

term_parent="$test_root/term-parent"
expect_term_cleanup "$term_parent" "$test_root/term.pid"

screenshot_parent="$test_root/screenshot-parent"
screenshot_project="$test_root/screenshot-project"
expect_timeout screenshot-real-chain "$screenshot_parent" "$test_root/screenshot-timeout.pid" \
	env \
		SCREENSHOT_TIMEOUT_SECONDS=1 \
		SCREENSHOT_KILL_AFTER_SECONDS=1 \
		SCREENSHOT_SCRATCH_PARENT="$screenshot_parent" \
		SCREENSHOT_PROJECT_ROOT="$screenshot_project" \
		SCREENSHOT_GODOT_BIN="$hanging_command" \
		HANG_MODE=wait \
		HANG_PID_FILE="$test_root/screenshot-timeout.pid" \
		./scripts/verify_screenshots.sh

screenshot_leader_parent="$test_root/screenshot-leader-parent"
expect_screenshot_leader_exit_cleanup "$screenshot_leader_parent" "$screenshot_project" "$test_root/screenshot-leader.pid"

release_parent="$test_root/release-parent"
for gate_name in isolation autosave recovery-ui transaction-reconciliation clean-clone cold-import cold-start screenshots; do
	expect_timeout "release-$gate_name" "$release_parent" "$test_root/release-$gate_name.pid" \
		env \
			RELEASE_HEALTH_SCRATCH_PARENT="$release_parent" \
			RELEASE_HEALTH_OVERALL_TIMEOUT_SECONDS=6 \
			RELEASE_HEALTH_ISOLATION_TIMEOUT_SECONDS=1 \
			RELEASE_HEALTH_AUTOSAVE_TIMEOUT_SECONDS=1 \
			RELEASE_HEALTH_RECOVERY_UI_TIMEOUT_SECONDS=1 \
			RELEASE_HEALTH_TRANSACTION_TIMEOUT_SECONDS=1 \
			RELEASE_HEALTH_CLONE_TIMEOUT_SECONDS=1 \
			RELEASE_HEALTH_COLD_IMPORT_TIMEOUT_SECONDS=1 \
			RELEASE_HEALTH_COLD_START_TIMEOUT_SECONDS=1 \
			RELEASE_HEALTH_SCREENSHOTS_TIMEOUT_SECONDS=1 \
			RELEASE_HEALTH_KILL_AFTER_SECONDS=1 \
			RELEASE_HEALTH_TEST_ONLY_GATE="$gate_name" \
			RELEASE_HEALTH_TEST_HANG_GATE="$gate_name" \
			RELEASE_HEALTH_TEST_HANG_COMMAND="$hanging_command" \
			HANG_MODE=wait \
			HANG_PID_FILE="$test_root/release-$gate_name.pid" \
			./scripts/release_health.sh
done

for attempt in 1 2; do
	expect_release_screenshot_timeout \
		"release-screenshots-continuous-$attempt" \
		"$test_root/release-screenshots-continuous-$attempt" \
		"$test_root/release-screenshots-continuous-$attempt.pid" \
		"$test_root/release-screenshots-continuous-$attempt.trace"
done

concurrent_one_status=0
concurrent_two_status=0
expect_release_screenshot_timeout \
	release-screenshots-concurrent-1 \
	"$test_root/release-screenshots-concurrent-1" \
	"$test_root/release-screenshots-concurrent-1.pid" \
	"$test_root/release-screenshots-concurrent-1.trace" &
concurrent_one_pid=$!
expect_release_screenshot_timeout \
	release-screenshots-concurrent-2 \
	"$test_root/release-screenshots-concurrent-2" \
	"$test_root/release-screenshots-concurrent-2.pid" \
	"$test_root/release-screenshots-concurrent-2.trace" &
concurrent_two_pid=$!
wait "$concurrent_one_pid" || concurrent_one_status=$?
wait "$concurrent_two_pid" || concurrent_two_status=$?
if [[ "$concurrent_one_status" -ne 0 || "$concurrent_two_status" -ne 0 ]]; then
	echo "Concurrent release screenshot timeout regression failed: first=$concurrent_one_status second=$concurrent_two_status" >&2
	exit 1
fi

expect_release_cold_import_term_cleanup "$release_parent" "$test_root/release-cold-import-term.pid"

expect_timeout release-overall "$release_parent" "$test_root/release-overall.pid" \
	env \
		RELEASE_HEALTH_SCRATCH_PARENT="$release_parent" \
		RELEASE_HEALTH_OVERALL_TIMEOUT_SECONDS=1 \
		RELEASE_HEALTH_ISOLATION_TIMEOUT_SECONDS=6 \
		RELEASE_HEALTH_KILL_AFTER_SECONDS=1 \
		RELEASE_HEALTH_TEST_ONLY_GATE=isolation \
		RELEASE_HEALTH_TEST_HANG_GATE=isolation \
		RELEASE_HEALTH_TEST_HANG_COMMAND="$hanging_command" \
		HANG_MODE=wait \
		HANG_PID_FILE="$test_root/release-overall.pid" \
		./scripts/release_health.sh

find "$HARD_TIMEOUT_REGISTRY_ROOT" -maxdepth 1 -type f -name '*.record' -printf '%f\n' | sort > "$test_root/registry-final"
if [[ "${#HARD_TIMEOUT_ACTIVE_PIDS[@]}" -ne 0 ]] || \
	! cmp -s "$test_root/registry-baseline" "$test_root/registry-final"; then
	echo "Timeout guards reached completion with a live PID/PGID registry entry." >&2
	diff -u "$test_root/registry-baseline" "$test_root/registry-final" >&2 || true
	exit 1
fi
guards_complete=1
echo "TIMEOUT_GUARDS_OK normal=clean leader_exit=clean timeout=bounded term=clean kill=bounded release_cold_import_term=clean screenshot_nested_timeout=bounded screenshot_leader_exit=clean release_screenshots_continuous=2 release_screenshots_concurrent=2 release_subgates=8 overall=bounded pids=reaped pgids=reaped scratch_roots=clean"
