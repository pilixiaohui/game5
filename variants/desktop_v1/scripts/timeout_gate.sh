#!/usr/bin/env bash

declare -ag HARD_TIMEOUT_ACTIVE_PIDS=()
declare -ag HARD_TIMEOUT_ACTIVE_PGIDS=()
declare -ag HARD_TIMEOUT_ACTIVE_RECORDS=()
HARD_TIMEOUT_LAST_RECORD=""

ensure_hard_timeout_registry() {
	if [[ -n "${HARD_TIMEOUT_REGISTRY_ROOT:-}" ]]; then
		return 0
	fi
	local registry_parent="${HARD_TIMEOUT_REGISTRY_PARENT:-${TMPDIR:-/tmp}}"
	mkdir -p "$registry_parent"
	HARD_TIMEOUT_REGISTRY_ROOT="$(mktemp -d "$registry_parent/xenogenesis-timeout-registry.XXXXXX")"
	HARD_TIMEOUT_REGISTRY_OWNER_PID="$BASHPID"
	export HARD_TIMEOUT_REGISTRY_ROOT HARD_TIMEOUT_REGISTRY_OWNER_PID
}

process_exists() {
	local pid="$1"
	kill -0 "$pid" 2>/dev/null
}

process_group_exists() {
	local pgid="$1"
	kill -0 -- "-$pgid" 2>/dev/null
}

read_process_group() {
	local pid="$1"
	local pgid=""
	for _attempt in $(seq 1 100); do
		pgid="$(ps -o pgid= -p "$pid" 2>/dev/null | tr -d ' ')"
		if [[ "$pgid" == "$pid" ]]; then
			printf '%s\n' "$pgid"
			return 0
		fi
		if ! process_exists "$pid" && process_group_exists "$pid"; then
			printf '%s\n' "$pid"
			return 0
		fi
		if ! process_exists "$pid" && ! process_group_exists "$pid"; then
			return 1
		fi
		sleep 0.01
	done
	return 1
}

reap_direct_child_if_zombie() {
	local pid="$1"
	local state=""
	state="$(ps -o stat= -p "$pid" 2>/dev/null | tr -d ' ')"
	if [[ "$state" == Z* ]]; then
		wait "$pid" 2>/dev/null || true
	fi
}

wait_for_timeout_tree_exit() {
	local pid="$1"
	local pgid="$2"
	local wait_seconds="$3"
	local deadline_ns=$(( $(date +%s%N) + wait_seconds * 1000000000 ))
	while true; do
		reap_direct_child_if_zombie "$pid"
		if ! process_exists "$pid" && ! process_group_exists "$pgid"; then
			return 0
		fi
		if (( $(date +%s%N) >= deadline_ns )); then
			return 1
		fi
		sleep 0.02
	done
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

terminate_timeout_tree() {
	local pid="$1"
	local pgid="$2"
	local grace_seconds="$3"
	if ! process_exists "$pid" && ! process_group_exists "$pgid"; then
		wait "$pid" 2>/dev/null || true
		return 0
	fi
	kill -TERM -- "-$pgid" 2>/dev/null || true
	kill -TERM "$pid" 2>/dev/null || true
	if wait_for_timeout_tree_exit "$pid" "$pgid" "$grace_seconds"; then
		wait "$pid" 2>/dev/null || true
		return 0
	fi
	kill -KILL -- "-$pgid" 2>/dev/null || true
	kill -KILL "$pid" 2>/dev/null || true
	if wait_for_timeout_tree_exit "$pid" "$pgid" "$grace_seconds"; then
		wait "$pid" 2>/dev/null || true
		return 0
	fi
	echo "Failed to reap timeout tree: pid=$pid pgid=$pgid" >&2
	return 1
}

register_timeout_process() {
	local gate_name="$1"
	local pid="$2"
	local pgid="$3"
	local parent_pid="${HARD_TIMEOUT_PARENT_PID:-0}"
	local record="$HARD_TIMEOUT_REGISTRY_ROOT/$pid.$BASHPID.record"
	local temporary="$record.tmp"
	printf '%s %s %s\n' "$pid" "$pgid" "$parent_pid" > "$temporary"
	mv "$temporary" "$record"
	HARD_TIMEOUT_ACTIVE_PIDS+=("$pid")
	HARD_TIMEOUT_ACTIVE_PGIDS+=("$pgid")
	HARD_TIMEOUT_ACTIVE_RECORDS+=("$record")
	if [[ -n "${HARD_TIMEOUT_TRACE_FILE:-}" ]]; then
		printf '%s %s %s %s\n' "$gate_name" "$pid" "$pgid" "$parent_pid" >> "$HARD_TIMEOUT_TRACE_FILE"
	fi
	HARD_TIMEOUT_LAST_RECORD="$record"
}

read_timeout_record() {
	local record="$1"
	local snapshot=""
	if ! IFS= read -r snapshot 2>/dev/null < "$record"; then
		return 1
	fi
	if [[ ! "$snapshot" =~ ^[1-9][0-9]*\ [1-9][0-9]*\ [0-9]+$ ]]; then
		return 1
	fi
	printf '%s\n' "$snapshot"
}

remove_active_timeout() {
	local completed_pid="$1"
	local remaining_pids=()
	local remaining_pgids=()
	local remaining_records=()
	local index
	for ((index = 0; index < ${#HARD_TIMEOUT_ACTIVE_PIDS[@]}; index += 1)); do
		if [[ "${HARD_TIMEOUT_ACTIVE_PIDS[$index]}" != "$completed_pid" ]]; then
			remaining_pids+=("${HARD_TIMEOUT_ACTIVE_PIDS[$index]}")
			remaining_pgids+=("${HARD_TIMEOUT_ACTIVE_PGIDS[$index]}")
			remaining_records+=("${HARD_TIMEOUT_ACTIVE_RECORDS[$index]}")
		fi
	done
	HARD_TIMEOUT_ACTIVE_PIDS=("${remaining_pids[@]}")
	HARD_TIMEOUT_ACTIVE_PGIDS=("${remaining_pgids[@]}")
	HARD_TIMEOUT_ACTIVE_RECORDS=("${remaining_records[@]}")
}

cleanup_registered_timeout_descendants() {
	local parent_pid="$1"
	local grace_seconds="$2"
	local cleanup_status=0
	local record
	local snapshot
	local pid
	local pgid
	local recorded_parent
	local records=()
	while IFS= read -r record; do
		records+=("$record")
	done < <(find "$HARD_TIMEOUT_REGISTRY_ROOT" -maxdepth 1 -type f -name '*.record' 2>/dev/null | sort)
	for record in "${records[@]}"; do
		if ! snapshot="$(read_timeout_record "$record")"; then
			continue
		fi
		read -r pid pgid recorded_parent <<< "$snapshot"
		if [[ "$recorded_parent" != "$parent_pid" ]]; then
			continue
		fi
		cleanup_registered_timeout_descendants "$pid" "$grace_seconds" || cleanup_status=1
		if terminate_timeout_tree "$pid" "$pgid" "$grace_seconds"; then
			rm -f "$record"
		else
			cleanup_status=1
		fi
	done
	return "$cleanup_status"
}

cleanup_hard_timeout_processes() {
	ensure_hard_timeout_registry
	local grace_seconds="${HARD_TIMEOUT_CLEANUP_GRACE_SECONDS:-1}"
	local cleanup_status=0
	local active_pids=("${HARD_TIMEOUT_ACTIVE_PIDS[@]}")
	local active_pgids=("${HARD_TIMEOUT_ACTIVE_PGIDS[@]}")
	local active_records=("${HARD_TIMEOUT_ACTIVE_RECORDS[@]}")
	local index
	for ((index = 0; index < ${#active_pids[@]}; index += 1)); do
		cleanup_registered_timeout_descendants "${active_pids[$index]}" "$grace_seconds" || cleanup_status=1
		if terminate_timeout_tree "${active_pids[$index]}" "${active_pgids[$index]}" "$grace_seconds"; then
			rm -f "${active_records[$index]}"
			remove_active_timeout "${active_pids[$index]}"
		else
			cleanup_status=1
		fi
	done
	if [[ "${HARD_TIMEOUT_REGISTRY_OWNER_PID:-}" == "$BASHPID" ]]; then
		local record
		local snapshot
		local pid
		local pgid
		local parent_pid
		while IFS= read -r record; do
			if ! snapshot="$(read_timeout_record "$record")"; then
				continue
			fi
			read -r pid pgid parent_pid <<< "$snapshot"
			cleanup_registered_timeout_descendants "$pid" "$grace_seconds" || cleanup_status=1
			if terminate_timeout_tree "$pid" "$pgid" "$grace_seconds"; then
				rm -f "$record"
			else
				cleanup_status=1
			fi
		done < <(find "$HARD_TIMEOUT_REGISTRY_ROOT" -maxdepth 1 -type f -name '*.record' 2>/dev/null | sort)
		if [[ "$cleanup_status" -eq 0 ]]; then
			rm -rf "$HARD_TIMEOUT_REGISTRY_ROOT"
			unset HARD_TIMEOUT_REGISTRY_ROOT HARD_TIMEOUT_REGISTRY_OWNER_PID
		fi
	fi
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
	if ! command -v timeout >/dev/null 2>&1 || ! command -v setsid >/dev/null 2>&1; then
		echo "GNU timeout and setsid are required for $gate_name." >&2
		return 2
	fi

	ensure_hard_timeout_registry
	echo "TIMEOUT_GATE_START gate=$gate_name timeout=${timeout_seconds}s kill_after=${kill_after_seconds}s"
	local status=0
	setsid bash -c '
		timeout_seconds="$1"
		kill_after_seconds="$2"
		shift 2
		export HARD_TIMEOUT_PARENT_PID="$BASHPID"
		exec timeout --signal=TERM --kill-after="${kill_after_seconds}s" "${timeout_seconds}s" "$@"
	' timeout-wrapper "$timeout_seconds" "$kill_after_seconds" "$@" &
	local timeout_pid=$!
	local timeout_pgid=""
	if ! timeout_pgid="$(read_process_group "$timeout_pid")"; then
		wait "$timeout_pid" || status=$?
		return "$status"
	fi
	local record
	register_timeout_process "$gate_name" "$timeout_pid" "$timeout_pgid"
	record="$HARD_TIMEOUT_LAST_RECORD"
	echo "TIMEOUT_GATE_PROCESS gate=$gate_name pid=$timeout_pid pgid=$timeout_pgid"
	wait "$timeout_pid" || status=$?

	local cleanup_status=0
	cleanup_registered_timeout_descendants "$timeout_pid" "$kill_after_seconds" || cleanup_status=1
	terminate_timeout_tree "$timeout_pid" "$timeout_pgid" "$kill_after_seconds" || cleanup_status=1
	if [[ "$cleanup_status" -eq 0 ]]; then
		rm -f "$record"
		remove_active_timeout "$timeout_pid"
	else
		return 71
	fi
	if [[ "$status" -eq 124 || "$status" -eq 137 ]]; then
		echo "TIMEOUT_GATE_EXPIRED gate=$gate_name status=$status timeout=${timeout_seconds}s" >&2
	fi
	return "$status"
}
