#!/usr/bin/env bash
set -euo pipefail

project_root="${TIMEOUT_OWNER_PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
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

launch_completion_caller() {
	local label="$1"
	local pid_file="$test_root/$label.pid"
	local ready_file="$test_root/$label.completion-ready"
	local release_file="$test_root/$label.completion-release"
	local landed_file="$test_root/$label.completion-landed"
	env \
		HARD_TIMEOUT_REGISTRY_ROOT="$HARD_TIMEOUT_REGISTRY_ROOT" \
		HARD_TIMEOUT_REGISTRY_OWNER_PID="${HARD_TIMEOUT_REGISTRY_OWNER_PID:-}" \
		HARD_TIMEOUT_TEST_SPAWN_PID_FILE="$pid_file" \
		HARD_TIMEOUT_TEST_COMPLETION_READY_FILE="$ready_file" \
		HARD_TIMEOUT_TEST_COMPLETION_RELEASE_FILE="$release_file" \
		HARD_TIMEOUT_TEST_COMPLETION_LANDED_FILE="$landed_file" \
		bash -c '
			source "$1"
			run_with_hard_timeout "$2" 5 1 true
		' timeout-owner-completion-caller "$project_root/scripts/timeout_gate.sh" "$label" \
		> "$test_root/$label.log" 2>&1 &
	caller_pids+=("$!")
	if ! wait_for_file "$pid_file" || ! wait_for_file "$pid_file.pgid" || ! wait_for_file "$ready_file"; then
		echo "TIMEOUT_OWNER_COMPLETION_RED case=$label reason=completion-ready-marker-missing" >&2
		cat "$test_root/$label.log" >&2
		return 1
	fi
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

unset HARD_TIMEOUT_REGISTRY_ROOT HARD_TIMEOUT_REGISTRY_OWNER_PID HARD_TIMEOUT_PARENT_PID
ensure_hard_timeout_registry
completion_registry_root="$HARD_TIMEOUT_REGISTRY_ROOT"
launch_completion_caller completion-first
launch_completion_caller completion-second

completion_checkpoint_status=0
cleanup_hard_timeout_processes || completion_checkpoint_status=$?
checkpoint_records=0
checkpoint_pending=0
checkpoint_owners=0
if [[ -d "$completion_registry_root" ]]; then
	checkpoint_records="$(find "$completion_registry_root" -maxdepth 1 -type f -name '*.record' | wc -l)"
	checkpoint_pending="$(find "$completion_registry_root" -maxdepth 1 -type f -name '.pending.*' | wc -l)"
	checkpoint_owners="$(find "$completion_registry_root" -maxdepth 1 -type f -name '.owner.*' | wc -l)"
fi
if [[ "$completion_checkpoint_status" -ne 0 || ! -d "$completion_registry_root" || \
	"$checkpoint_records" -ne 2 || "$checkpoint_pending" -ne 2 || "$checkpoint_owners" -lt 2 || \
	-s "$test_root/completion-first.completion-landed" || -s "$test_root/completion-second.completion-landed" ]]; then
	echo "Timeout registry crossed a pending multi-owner completion boundary: status=$completion_checkpoint_status records=$checkpoint_records pending=$checkpoint_pending owners=$checkpoint_owners registry_exists=$([[ -d "$completion_registry_root" ]] && echo true || echo false)" >&2
	exit 1
fi

printf '%s\n' release > "$test_root/completion-first.completion-release"
first_completion_status=0
wait "${caller_pids[2]}" || first_completion_status=$?
if ! wait_for_file "$test_root/completion-first.completion-landed"; then
	echo "First supervisor did not publish its completion record: caller_status=$first_completion_status" >&2
	cat "$test_root/completion-first.log" >&2
	exit 1
fi
cleanup_hard_timeout_processes
mid_records="$(find "$completion_registry_root" -maxdepth 1 -type f -name '*.record' | wc -l)"
mid_pending="$(find "$completion_registry_root" -maxdepth 1 -type f -name '.pending.*' | wc -l)"
if [[ "$first_completion_status" -ne 0 || ! -d "$completion_registry_root" || "$mid_records" -ne 1 || "$mid_pending" -ne 1 || \
	! -s "$test_root/completion-first.completion-landed" || -s "$test_root/completion-second.completion-landed" ]]; then
	echo "First completion incorrectly released the shared registry: status=$first_completion_status records=$mid_records pending=$mid_pending" >&2
	exit 1
fi

printf '%s\n' release > "$test_root/completion-second.completion-release"
second_completion_status=0
wait "${caller_pids[3]}" || second_completion_status=$?
if ! wait_for_file "$test_root/completion-second.completion-landed"; then
	echo "Second supervisor did not publish its completion record: caller_status=$second_completion_status" >&2
	cat "$test_root/completion-second.log" >&2
	exit 1
fi
final_completion_cleanup_status=0
cleanup_hard_timeout_processes || final_completion_cleanup_status=$?
completion_alive_count=0
for ((index = 2; index < ${#supervisor_pids[@]}; index += 1)); do
	if process_identity_matches \
		"${supervisor_pids[$index]}" "${supervisor_boots[$index]}" \
		"${supervisor_namespaces[$index]}" "${supervisor_starts[$index]}" || \
		process_group_exists "${supervisor_pgids[$index]}"; then
		completion_alive_count=$((completion_alive_count + 1))
	fi
done
if [[ "$second_completion_status" -ne 0 || "$final_completion_cleanup_status" -ne 0 || "$completion_alive_count" -ne 0 || \
	! -s "$test_root/completion-second.completion-landed" || -d "$completion_registry_root" ]]; then
	echo "Last completion did not converge registry ownership: caller=$second_completion_status cleanup=$final_completion_cleanup_status alive=$completion_alive_count registry_exists=$([[ -d "$completion_registry_root" ]] && echo true || echo false)" >&2
	exit 1
fi

gate_complete=1
echo "VERIFY_TIMEOUT_OWNER_RECORDS_OK supervisors=4 callers=interrupted,completed first_status=$first_cleanup_status retry_record=retained completion=pending-until-landed owners=multiple,last records=0 registry=removed identities=gone"
