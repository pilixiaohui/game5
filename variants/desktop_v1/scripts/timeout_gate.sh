#!/usr/bin/env bash

declare -ag HARD_TIMEOUT_ACTIVE_PGIDS=()

process_group_exists() {
	local pgid="$1"
	kill -0 -- "-$pgid" 2>/dev/null
}

wait_for_process_group_exit() {
	local pgid="$1"
	local wait_seconds="$2"
	local deadline_ns=$(( $(date +%s%N) + wait_seconds * 1000000000 ))
	while process_group_exists "$pgid"; do
		if (( $(date +%s%N) >= deadline_ns )); then
			return 1
		fi
		sleep 0.02
	done
}

terminate_process_group() {
	local pgid="$1"
	local grace_seconds="$2"
	if ! process_group_exists "$pgid"; then
		return 0
	fi
	kill -TERM -- "-$pgid" 2>/dev/null || true
	if wait_for_process_group_exit "$pgid" "$grace_seconds"; then
		return 0
	fi
	kill -KILL -- "-$pgid" 2>/dev/null || true
	if wait_for_process_group_exit "$pgid" "$grace_seconds"; then
		return 0
	fi
	echo "Failed to reap timeout process group: pgid=$pgid" >&2
	return 1
}

remove_active_timeout_pgid() {
	local completed_pgid="$1"
	local remaining=()
	local active_pgid
	for active_pgid in "${HARD_TIMEOUT_ACTIVE_PGIDS[@]}"; do
		if [[ "$active_pgid" != "$completed_pgid" ]]; then
			remaining+=("$active_pgid")
		fi
	done
	HARD_TIMEOUT_ACTIVE_PGIDS=("${remaining[@]}")
}

cleanup_hard_timeout_processes() {
	local active_pgid
	local cleanup_status=0
	local grace_seconds="${HARD_TIMEOUT_CLEANUP_GRACE_SECONDS:-1}"
	local active_snapshot=("${HARD_TIMEOUT_ACTIVE_PGIDS[@]}")
	for active_pgid in "${active_snapshot[@]}"; do
		if terminate_process_group "$active_pgid" "$grace_seconds"; then
			wait "$active_pgid" 2>/dev/null || true
			remove_active_timeout_pgid "$active_pgid"
		else
			cleanup_status=1
		fi
	done
	return "$cleanup_status"
}

run_with_hard_timeout() {
	local gate_name="$1"
	local timeout_seconds="$2"
	local kill_after_seconds="$3"
	shift 3

	if [[ ! "$timeout_seconds" =~ ^[1-9][0-9]*$ ]] || [[ ! "$kill_after_seconds" =~ ^[1-9][0-9]*$ ]]; then
		echo "Invalid timeout for $gate_name: timeout=$timeout_seconds kill_after=$kill_after_seconds" >&2
		return 2
	fi
	if ! command -v timeout >/dev/null 2>&1; then
		echo "GNU timeout is required for $gate_name." >&2
		return 2
	fi

	echo "TIMEOUT_GATE_START gate=$gate_name timeout=${timeout_seconds}s kill_after=${kill_after_seconds}s"
	local status=0
	timeout --signal=TERM --kill-after="${kill_after_seconds}s" "${timeout_seconds}s" "$@" &
	local timeout_pid=$!
	local timeout_pgid="$timeout_pid"
	HARD_TIMEOUT_ACTIVE_PGIDS+=("$timeout_pgid")
	wait "$timeout_pid" || status=$?
	local cleanup_status=0
	terminate_process_group "$timeout_pgid" "$kill_after_seconds" || cleanup_status=$?
	if [[ "$cleanup_status" -ne 0 ]]; then
		return 71
	fi
	remove_active_timeout_pgid "$timeout_pgid"
	if [[ "$status" -eq 124 || "$status" -eq 137 ]]; then
		echo "TIMEOUT_GATE_EXPIRED gate=$gate_name status=$status timeout=${timeout_seconds}s" >&2
	fi
	return "$status"
}
