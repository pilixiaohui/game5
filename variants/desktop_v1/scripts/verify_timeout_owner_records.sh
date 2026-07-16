#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$project_root/scripts/timeout_gate.sh"

test_root="$(mktemp -d "${TMPDIR:-/tmp}/xenogenesis-timeout-owner-records.XXXXXX")"
declare -a caller_pids=()
declare -a supervisor_pids=()
declare -a supervisor_pgids=()
declare -a supervisor_boots=()
declare -a supervisor_namespaces=()
declare -a supervisor_starts=()
gate_complete=0

cleanup_owner_record_gate() {
	local caller_pid=""
	for caller_pid in "${caller_pids[@]}"; do
		if process_exists "$caller_pid"; then
			kill -TERM "$caller_pid" 2>/dev/null || true
		fi
		wait "$caller_pid" 2>/dev/null || true
	done
	if [[ "$gate_complete" -ne 1 ]]; then
		local index
		for ((index = 0; index < ${#supervisor_pids[@]}; index += 1)); do
			terminate_timeout_identity \
				"${supervisor_pids[$index]}" "${supervisor_pgids[$index]}" \
				"${supervisor_boots[$index]}" "${supervisor_namespaces[$index]}" \
				"${supervisor_starts[$index]}" 1 || true
		done
	fi
	cleanup_hard_timeout_processes 2>/dev/null || true
	rm -rf "$test_root"
}
trap cleanup_owner_record_gate EXIT

wait_for_file() {
	local path="$1"
	local attempt
	for attempt in $(seq 1 200); do
		[[ -s "$path" ]] && return 0
		sleep 0.01
	done
	return 1
}

launch_production_caller() {
	local label="$1"
	local pid_file="$test_root/$label.pid"
	env \
		HARD_TIMEOUT_REGISTRY_ROOT="$HARD_TIMEOUT_REGISTRY_ROOT" \
		HARD_TIMEOUT_REGISTRY_OWNER_PID="$HARD_TIMEOUT_REGISTRY_OWNER_PID" \
		HARD_TIMEOUT_TEST_SPAWN_PID_FILE="$pid_file" \
		bash -c '
			source "$1"
			run_with_hard_timeout "$2" 30 1 sleep 30
		' timeout-owner-caller "$project_root/scripts/timeout_gate.sh" "$label" \
		> "$test_root/$label.log" 2>&1 &
	caller_pids+=("$!")
	wait_for_file "$pid_file"
	wait_for_file "$pid_file.pgid"
	local supervisor_pid=""
	local supervisor_pgid=""
	IFS= read -r supervisor_pid < "$pid_file"
	IFS= read -r supervisor_pgid < "$pid_file.pgid"
	local identity=""
	identity="$(read_process_identity "$supervisor_pid")"
	local boot_id pid_namespace start_time
	read -r boot_id pid_namespace start_time <<< "$identity"
	supervisor_pids+=("$supervisor_pid")
	supervisor_pgids+=("$supervisor_pgid")
	supervisor_boots+=("$boot_id")
	supervisor_namespaces+=("$pid_namespace")
	supervisor_starts+=("$start_time")
}

cd "$project_root"
unset HARD_TIMEOUT_REGISTRY_ROOT HARD_TIMEOUT_REGISTRY_OWNER_PID HARD_TIMEOUT_PARENT_PID
ensure_hard_timeout_registry
registry_root="$HARD_TIMEOUT_REGISTRY_ROOT"

launch_production_caller owner-record-first
launch_production_caller owner-record-second

for _attempt in $(seq 1 200); do
	if [[ "$(find "$registry_root" -maxdepth 1 -type f -name '*.record' | wc -l)" -eq 2 ]]; then
		break
	fi
	sleep 0.01
done
if [[ "$(find "$registry_root" -maxdepth 1 -type f -name '*.record' | wc -l)" -ne 2 ]]; then
	echo "Owner multi-record fixture did not publish two production records." >&2
	exit 1
fi

caller_statuses=()
for caller_pid in "${caller_pids[@]}"; do
	kill -TERM "$caller_pid"
	caller_status=0
	wait "$caller_pid" || caller_status=$?
	caller_statuses+=("$caller_status")
done
for caller_status in "${caller_statuses[@]}"; do
	if [[ "$caller_status" -eq 0 ]]; then
		echo "Interrupted timeout caller unexpectedly returned success." >&2
		exit 1
	fi
done

HARD_TIMEOUT_TEST_TERMINATION_FAILURE_PID="${supervisor_pids[0]}"
export HARD_TIMEOUT_TEST_TERMINATION_FAILURE_PID
first_cleanup_status=0
cleanup_hard_timeout_processes || first_cleanup_status=$?
unset HARD_TIMEOUT_TEST_TERMINATION_FAILURE_PID

first_record_count=0
if [[ -d "$registry_root" ]]; then
	first_record_count="$(find "$registry_root" -maxdepth 1 -type f -name '*.record' | wc -l)"
fi
first_identity_alive=0
second_identity_alive=0
process_identity_matches "${supervisor_pids[0]}" "${supervisor_boots[0]}" "${supervisor_namespaces[0]}" "${supervisor_starts[0]}" && first_identity_alive=1
process_identity_matches "${supervisor_pids[1]}" "${supervisor_boots[1]}" "${supervisor_namespaces[1]}" "${supervisor_starts[1]}" && second_identity_alive=1
retry_record=""
if [[ -d "$registry_root" ]]; then
	retry_record="$(find "$registry_root" -maxdepth 1 -type f -name "${supervisor_pids[0]}.*.record" -print -quit)"
fi
if [[ "$first_cleanup_status" -eq 0 || "$first_identity_alive" -ne 1 || "$second_identity_alive" -ne 0 || \
	"$first_record_count" -ne 1 || ! -d "$registry_root" || -z "$retry_record" ]]; then
	echo "Owner multi-record cleanup did not retain exactly the retryable identity: status=$first_cleanup_status records=$first_record_count registry_exists=$([[ -d "$registry_root" ]] && echo true || echo false)" >&2
	exit 1
fi

cleanup_status=0
cleanup_hard_timeout_processes || cleanup_status=$?
alive_count=0
for ((index = 0; index < ${#supervisor_pids[@]}; index += 1)); do
	if process_identity_matches \
		"${supervisor_pids[$index]}" "${supervisor_boots[$index]}" \
		"${supervisor_namespaces[$index]}" "${supervisor_starts[$index]}" || \
		process_group_exists "${supervisor_pgids[$index]}"; then
		alive_count=$((alive_count + 1))
	fi
done
record_count=0
if [[ -d "$registry_root" ]]; then
	record_count="$(find "$registry_root" -maxdepth 1 -type f -name '*.record' | wc -l)"
fi

if [[ "$cleanup_status" -ne 0 || "$alive_count" -ne 0 || "$record_count" -ne 0 || -d "$registry_root" ]]; then
	echo "Owner multi-record cleanup was inconsistent: status=$cleanup_status alive=$alive_count records=$record_count registry_exists=$([[ -d "$registry_root" ]] && echo true || echo false)" >&2
	exit 1
fi

gate_complete=1
echo "VERIFY_TIMEOUT_OWNER_RECORDS_OK supervisors=2 callers=interrupted first_status=$first_cleanup_status retry_record=retained retry=success identities=gone records=0 registry=removed"
