#!/usr/bin/env bash
set -euo pipefail

project_root="${TIMEOUT_PREREG_PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$project_root/scripts/timeout_gate.sh"

test_root="$(mktemp -d "${TMPDIR:-/tmp}/xenogenesis-timeout-preregistration.XXXXXX")"
current_caller_pid=""
current_supervisor_pid=""
current_supervisor_pgid=""
current_supervisor_boot=""
current_supervisor_namespace=""
current_supervisor_start=""
current_registry=""
unrelated_pid=""

wait_for_file() {
	local path="$1"
	local attempt
	for attempt in $(seq 1 200); do
		[[ -s "$path" ]] && return 0
		sleep 0.01
	done
	return 1
}

count_registry_entries() {
	local pattern="$1"
	if [[ ! -d "$current_registry" ]]; then
		printf '0\n'
		return
	fi
	find "$current_registry" -mindepth 1 -maxdepth 1 -type f -name "$pattern" | wc -l
}

cleanup_current_case() {
	if [[ -n "$current_caller_pid" ]] && process_exists "$current_caller_pid"; then
		kill -KILL "$current_caller_pid" 2>/dev/null || true
	fi
	if [[ -n "$current_caller_pid" ]]; then
		wait "$current_caller_pid" 2>/dev/null || true
	fi
	if [[ -n "$current_supervisor_pid" && -n "$current_supervisor_start" ]] && \
		process_identity_matches "$current_supervisor_pid" "$current_supervisor_boot" \
			"$current_supervisor_namespace" "$current_supervisor_start"; then
		terminate_timeout_identity "$current_supervisor_pid" "$current_supervisor_pgid" \
			"$current_supervisor_boot" "$current_supervisor_namespace" \
			"$current_supervisor_start" 1 || true
	fi
	if [[ -d "$current_registry" ]]; then
		HARD_TIMEOUT_REGISTRY_ROOT="$current_registry"
		HARD_TIMEOUT_OWNER_LEASE=""
		cleanup_hard_timeout_processes 2>/dev/null || true
	fi
	current_caller_pid=""
	current_supervisor_pid=""
	current_supervisor_pgid=""
	current_supervisor_boot=""
	current_supervisor_namespace=""
	current_supervisor_start=""
	current_registry=""
}

cleanup_gate() {
	cleanup_current_case
	if [[ -n "$unrelated_pid" ]] && process_exists "$unrelated_pid"; then
		kill -TERM "$unrelated_pid" 2>/dev/null || true
		wait "$unrelated_pid" 2>/dev/null || true
	fi
	rm -rf "$test_root"
}
trap cleanup_gate EXIT

run_interrupt_case() {
	local signal_name="$1"
	local expected_status="$2"
	local label="${signal_name,,}"
	local case_root="$test_root/$label"
	current_registry="$case_root/registry"
	local pid_file="$case_root/supervisor.pid"
	local cleanup_log="$case_root/cleanup.log"
	local freeze_marker="$case_root/registration-entered"
	local deferred_marker="$case_root/deferred-signal"
	mkdir -p "$current_registry"

	setsid env --default-signal=TERM --default-signal=INT \
		HARD_TIMEOUT_REGISTRY_ROOT="$current_registry" \
		HARD_TIMEOUT_TEST_SPAWN_PID_FILE="$pid_file" \
		HARD_TIMEOUT_TEST_REGISTRATION_FAILURE=1 \
		HARD_TIMEOUT_TEST_REGISTRATION_FAILURE_WAIT_FILE="$case_root/never-release" \
		HARD_TIMEOUT_TEST_REGISTRATION_FAILURE_ENTERED_FILE="$freeze_marker" \
		HARD_TIMEOUT_TEST_DEFERRED_SIGNAL_FILE="$deferred_marker" \
		HARD_TIMEOUT_PREREG_CLEANUP_LOG="$cleanup_log" \
		bash -c '
			source "$1"
			on_interrupt() {
				local signal_name="$1"
				local exit_status="$2"
				local cleanup_status=0
				cleanup_hard_timeout_processes || cleanup_status=$?
				local supervisor_pid=""
				local supervisor_pgid=""
				IFS= read -r supervisor_pid < "$HARD_TIMEOUT_TEST_SPAWN_PID_FILE" 2>/dev/null || true
				IFS= read -r supervisor_pgid < "$HARD_TIMEOUT_TEST_SPAWN_PID_FILE.pgid" 2>/dev/null || true
				local supervisor_alive=0
				local group_alive=0
				[[ -n "$supervisor_pid" ]] && process_exists "$supervisor_pid" && supervisor_alive=1
				[[ -n "$supervisor_pgid" ]] && process_group_exists "$supervisor_pgid" && group_alive=1
				printf "signal=%s cleanup=%d supervisor=%d group=%d\n" \
					"$signal_name" "$cleanup_status" "$supervisor_alive" "$group_alive" \
					> "$HARD_TIMEOUT_PREREG_CLEANUP_LOG"
				printf "TIMEOUT_PREREGISTRATION_FORWARD_MARKER signal=%s status=%s cleanup=%s\n" \
					"$signal_name" "$exit_status" "$cleanup_status"
				exit "$exit_status"
			}
			trap "on_interrupt TERM 143" TERM
			trap "on_interrupt INT 130" INT
			run_with_hard_timeout preregistration-interrupt 30 1 sleep 30
		' timeout-preregistration-caller "$project_root/scripts/timeout_gate.sh" \
		> "$case_root/caller.log" 2>&1 &
	current_caller_pid=$!

	if ! wait_for_file "$pid_file" || ! wait_for_file "$pid_file.pgid"; then
		echo "TIMEOUT_PREREGISTRATION_RED signal=$signal_name reason=spawn-identity-marker-missing" >&2
		cat "$case_root/caller.log" >&2
		return 1
	fi
	IFS= read -r current_supervisor_pid < "$pid_file"
	IFS= read -r current_supervisor_pgid < "$pid_file.pgid"
	local identity=""
	identity="$(read_process_identity "$current_supervisor_pid")" || {
		echo "TIMEOUT_PREREGISTRATION_RED signal=$signal_name reason=spawn-identity-unreadable" >&2
		return 1
	}
	read -r current_supervisor_boot current_supervisor_namespace current_supervisor_start <<< "$identity"

	if ! wait_for_file "$freeze_marker"; then
		echo "TIMEOUT_PREREGISTRATION_RED signal=$signal_name reason=registration-freeze-marker-missing" >&2
		cat "$case_root/caller.log" >&2
		return 1
	fi
	echo "TIMEOUT_PREREGISTRATION_FREEZE_MARKER signal=$signal_name pending=v2 records=0 phase=registration-failure"
	echo "TIMEOUT_PREREGISTRATION_INJECTION_MARKER signal=$signal_name caller=$current_caller_pid identity=exact"
	kill -s "$signal_name" "$current_caller_pid"
	if ! wait_for_file "$deferred_marker" || [[ "$(<"$deferred_marker")" != "$signal_name" ]]; then
		echo "TIMEOUT_PREREGISTRATION_RED signal=$signal_name reason=deferred-signal-marker-missing" >&2
		cat "$case_root/caller.log" >&2
		return 1
	fi
	echo "TIMEOUT_PREREGISTRATION_DEFERRED_MARKER signal=$signal_name captured=true"
	local caller_status=0
	wait "$current_caller_pid" || caller_status=$?
	current_caller_pid=""

	local cleanup_status=-1
	local logged_signal=""
	local logged_supervisor=-1
	local logged_group=-1
	local forward_marker=0
	if [[ -s "$cleanup_log" ]]; then
		local cleanup_field supervisor_field group_field
		read -r logged_signal cleanup_field supervisor_field group_field < "$cleanup_log"
		cleanup_status="${cleanup_field#cleanup=}"
		logged_supervisor="${supervisor_field#supervisor=}"
		logged_group="${group_field#group=}"
	fi
	if rg -q "^TIMEOUT_PREREGISTRATION_FORWARD_MARKER signal=$signal_name status=$expected_status cleanup=0$" \
		"$case_root/caller.log"; then
		forward_marker=1
	fi
	local supervisor_alive=0
	local group_alive=0
	process_identity_matches "$current_supervisor_pid" "$current_supervisor_boot" \
		"$current_supervisor_namespace" "$current_supervisor_start" && supervisor_alive=1
	process_group_exists "$current_supervisor_pgid" && group_alive=1
	local pending_count record_count owner_count
	pending_count="$(count_registry_entries '.pending.*')"
	record_count="$(count_registry_entries '*.record')"
	owner_count="$(count_registry_entries '.owner.*')"
	local registry_count=0
	[[ -d "$current_registry" ]] && registry_count=1
	local unrelated_alive=0
	process_exists "$unrelated_pid" && unrelated_alive=1

	if [[ "$caller_status" -ne "$expected_status" || "$cleanup_status" -ne 0 || "$forward_marker" -ne 1 || \
		"$logged_signal" != "signal=$signal_name" || "$logged_supervisor" -ne 0 || "$logged_group" -ne 0 || \
		"$supervisor_alive" -ne 0 || "$group_alive" -ne 0 || \
		"$pending_count" -ne 0 || "$record_count" -ne 0 || "$owner_count" -ne 0 || \
		"$registry_count" -ne 0 || "$unrelated_alive" -ne 1 ]]; then
		echo "TIMEOUT_PREREGISTRATION_RED signal=$signal_name caller=$caller_status cleanup=$cleanup_status supervisor=$supervisor_alive/$logged_supervisor group=$group_alive/$logged_group pending=$pending_count records=$record_count owners=$owner_count registry=$registry_count unrelated=$unrelated_alive" >&2
		cleanup_current_case
		return 1
	fi

	echo "TIMEOUT_PREREGISTRATION_FORWARD_MARKER signal=$signal_name status=$expected_status cleanup=0"
	echo "TIMEOUT_PREREGISTRATION_CLEANUP_MARKER signal=$signal_name cleanup=$cleanup_status supervisor=0 group=0 pending=0 records=0 owners=0 registry=0 unrelated=alive"
	echo "TIMEOUT_PREREGISTRATION_CASE_OK signal=$signal_name caller=$caller_status cleanup=$cleanup_status supervisor=0 group=0 pending=0 records=0 owners=0 registry=0 unrelated=alive"
	current_supervisor_pid=""
	current_supervisor_pgid=""
	current_supervisor_boot=""
	current_supervisor_namespace=""
	current_supervisor_start=""
	current_registry=""
	rm -rf "$case_root"
}

sleep 30 &
unrelated_pid=$!
run_interrupt_case TERM 143
run_interrupt_case INT 130

echo "VERIFY_TIMEOUT_PREREGISTRATION_INTERRUPT_OK signals=TERM,INT entrypoint=run_with_hard_timeout handshake=freeze,injection,deferred,forward,cleanup identities=exact processes=gone registry=pending,record,owner-zero unrelated=alive scratch=clean-on-exit"
