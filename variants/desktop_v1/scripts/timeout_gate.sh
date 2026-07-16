#!/usr/bin/env bash

declare -ag HARD_TIMEOUT_ACTIVE_PIDS=()
declare -ag HARD_TIMEOUT_ACTIVE_PGIDS=()
declare -ag HARD_TIMEOUT_ACTIVE_RECORDS=()
declare -ag HARD_TIMEOUT_ACTIVE_START_TIMES=()
declare -ag HARD_TIMEOUT_ACTIVE_BOOT_IDS=()
declare -ag HARD_TIMEOUT_ACTIVE_PID_NAMESPACES=()
HARD_TIMEOUT_LAST_RECORD=""
HARD_TIMEOUT_LAST_START_TIME=""
HARD_TIMEOUT_LAST_BOOT_ID=""
HARD_TIMEOUT_LAST_PID_NAMESPACE=""

validate_hard_timeout_registry() {
	local root="${HARD_TIMEOUT_REGISTRY_ROOT:-}"
	if [[ -z "$root" || ! -d "$root" || -L "$root" ]]; then
		echo "Timeout registry is missing or is not a real directory: ${root:-<unset>}" >&2
		return 1
	fi
	local probe=""
	if ! probe="$(mktemp "$root/.handshake.XXXXXX")"; then
		echo "Timeout registry is not writable: $root" >&2
		return 1
	fi
	local nonce="${BASHPID}-$(date +%s%N)"
	local observed=""
	if ! printf '%s\n' "$nonce" > "$probe" || ! IFS= read -r observed < "$probe" || [[ "$observed" != "$nonce" ]]; then
		rm -f "$probe"
		echo "Timeout registry handshake failed: $root" >&2
		return 1
	fi
	rm -f "$probe"
}

ensure_hard_timeout_registry() {
	if [[ -n "${HARD_TIMEOUT_REGISTRY_ROOT:-}" ]]; then
		validate_hard_timeout_registry
		return $?
	fi
	local registry_parent="${HARD_TIMEOUT_REGISTRY_PARENT:-${TMPDIR:-/tmp}}"
	mkdir -p "$registry_parent" || return 1
	HARD_TIMEOUT_REGISTRY_ROOT="$(mktemp -d "$registry_parent/xenogenesis-timeout-registry.XXXXXX")" || return 1
	HARD_TIMEOUT_REGISTRY_OWNER_PID="$BASHPID"
	export HARD_TIMEOUT_REGISTRY_ROOT HARD_TIMEOUT_REGISTRY_OWNER_PID
	validate_hard_timeout_registry
}

process_exists() {
	local pid="$1"
	kill -0 "$pid" 2>/dev/null
}

process_group_exists() {
	local pgid="$1"
	kill -0 -- "-$pgid" 2>/dev/null
}

read_process_stat_fields() {
	local pid="$1"
	local stat_line=""
	if [[ ! "$pid" =~ ^[1-9][0-9]*$ ]] || ! { IFS= read -r stat_line < "/proc/$pid/stat"; } 2>/dev/null; then
		return 1
	fi
	local fields="${stat_line##*) }"
	local -a values=()
	read -r -a values <<< "$fields"
	if [[ "${#values[@]}" -lt 20 ]]; then
		return 1
	fi
	printf '%s %s %s %s\n' "${values[2]}" "${values[3]}" "${values[19]}" "${values[0]}"
}

read_process_identity() {
	local pid="$1"
	local boot_id=""
	local pid_namespace=""
	local stat_fields=""
	if ! IFS= read -r boot_id < /proc/sys/kernel/random/boot_id || \
		! pid_namespace="$(readlink "/proc/$pid/ns/pid")" || \
		! stat_fields="$(read_process_stat_fields "$pid")"; then
		return 1
	fi
	local pgrp session start_time state
	read -r pgrp session start_time state <<< "$stat_fields"
	if [[ ! "$boot_id" =~ ^[0-9a-fA-F-]+$ || ! "$pid_namespace" =~ ^pid:\[[0-9]+\]$ || ! "$start_time" =~ ^[0-9]+$ ]]; then
		return 1
	fi
	printf '%s %s %s\n' "$boot_id" "$pid_namespace" "$start_time"
}

process_identity_matches() {
	local pid="$1"
	local expected_boot="$2"
	local expected_namespace="$3"
	local expected_start="$4"
	local actual=""
	actual="$(read_process_identity "$pid")" || return 1
	[[ "$actual" == "$expected_boot $expected_namespace $expected_start" ]]
}

group_identity_matches() {
	local leader_pid="$1"
	local pgid="$2"
	local expected_boot="$3"
	local expected_namespace="$4"
	local expected_start="$5"
	local current_boot=""
	IFS= read -r current_boot < /proc/sys/kernel/random/boot_id || return 1
	[[ "$current_boot" == "$expected_boot" ]] || return 1
	if process_exists "$leader_pid"; then
		process_identity_matches "$leader_pid" "$expected_boot" "$expected_namespace" "$expected_start" || return 1
		local leader_fields=""
		leader_fields="$(read_process_stat_fields "$leader_pid")" || return 1
		local leader_pgrp leader_session leader_start leader_state
		read -r leader_pgrp leader_session leader_start leader_state <<< "$leader_fields"
		[[ "$leader_pgrp" == "$pgid" && "$leader_session" == "$pgid" && "$leader_start" == "$expected_start" ]]
		return $?
	fi
	# A process group ID is reusable. Once its authenticated session leader is
	# gone, membership alone cannot prove that the current group is the one we
	# registered, so group-directed signaling is forbidden.
	return 1
}

read_process_group() {
	local pid="$1"
	local pgid=""
	local attempt
	for attempt in $(seq 1 100); do
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

timeout_group_has_live_member_except() {
	local leader_pid="$1"
	local pgid="$2"
	local proc_dir=""
	local member_pid=""
	local fields=""
	local member_pgrp member_session member_start member_state
	for proc_dir in /proc/[0-9]*; do
		member_pid="${proc_dir#/proc/}"
		[[ "$member_pid" == "$leader_pid" ]] && continue
		fields="$(read_process_stat_fields "$member_pid")" || continue
		read -r member_pgrp member_session member_start member_state <<< "$fields"
		if [[ "$member_pgrp" == "$pgid" && "$member_state" != "Z" ]]; then
			return 0
		fi
	done
	return 1
}

wait_for_timeout_group_members_exit() {
	local leader_pid="$1"
	local pgid="$2"
	local wait_seconds="$3"
	local deadline_ns=$(( $(date +%s%N) + wait_seconds * 1000000000 ))
	while timeout_group_has_live_member_except "$leader_pid" "$pgid"; do
		if (( $(date +%s%N) >= deadline_ns )); then
			return 1
		fi
		sleep 0.02
	done
}

# Test cleanup uses this only for process groups created by the same gate run.
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

verify_timeout_target() {
	local pid="$1"
	local pgid="$2"
	local boot_id="$3"
	local pid_namespace="$4"
	local start_time="$5"
	if ! process_exists "$pid" && ! process_group_exists "$pgid"; then
		return 3
	fi
	group_identity_matches "$pid" "$pgid" "$boot_id" "$pid_namespace" "$start_time"
}

terminate_timeout_identity() {
	local pid="$1"
	local pgid="$2"
	local boot_id="$3"
	local pid_namespace="$4"
	local start_time="$5"
	local grace_seconds="$6"
	local identity_status=0
	verify_timeout_target "$pid" "$pgid" "$boot_id" "$pid_namespace" "$start_time" || identity_status=$?
	if [[ "$identity_status" -eq 3 ]]; then
		wait "$pid" 2>/dev/null || true
		return 0
	fi
	if [[ "$identity_status" -ne 0 ]]; then
		echo "Discarded stale timeout identity before TERM: pid=$pid pgid=$pgid" >&2
		return 2
	fi
	kill -TERM -- "-$pgid" 2>/dev/null || true
	if wait_for_timeout_group_members_exit "$pid" "$pgid" "$grace_seconds"; then
		if ! process_identity_matches "$pid" "$boot_id" "$pid_namespace" "$start_time"; then
			echo "Discarded stale timeout identity before supervisor exit: pid=$pid pgid=$pgid" >&2
			return 2
		fi
		kill -USR1 "$pid" 2>/dev/null || true
		if wait_for_timeout_tree_exit "$pid" "$pgid" "$grace_seconds"; then
			wait "$pid" 2>/dev/null || true
			return 0
		fi
	fi
	identity_status=0
	verify_timeout_target "$pid" "$pgid" "$boot_id" "$pid_namespace" "$start_time" || identity_status=$?
	if [[ "$identity_status" -eq 3 ]]; then
		wait "$pid" 2>/dev/null || true
		return 0
	fi
	if [[ "$identity_status" -ne 0 ]]; then
		echo "Discarded stale timeout identity before KILL: pid=$pid pgid=$pgid" >&2
		return 2
	fi
	kill -KILL -- "-$pgid" 2>/dev/null || true
	if wait_for_timeout_tree_exit "$pid" "$pgid" "$grace_seconds"; then
		wait "$pid" 2>/dev/null || true
		return 0
	fi
	echo "Failed to reap timeout identity: pid=$pid pgid=$pgid" >&2
	return 1
}

register_timeout_process() {
	local gate_name="$1"
	local pid="$2"
	local pgid="$3"
	local identity=""
	identity="$(read_process_identity "$pid")" || return 1
	local boot_id pid_namespace start_time
	read -r boot_id pid_namespace start_time <<< "$identity"
	local parent_pid="${HARD_TIMEOUT_PARENT_PID:-0}"
	local parent_start=0
	if [[ "$parent_pid" != "0" ]]; then
		local parent_identity=""
		local _parent_boot _parent_namespace
		parent_identity="$(read_process_identity "$parent_pid")" || return 1
		read -r _parent_boot _parent_namespace parent_start <<< "$parent_identity"
	fi
	if [[ "${HARD_TIMEOUT_TEST_REGISTRATION_FAILURE:-0}" == "1" ]]; then
		local wait_file="${HARD_TIMEOUT_TEST_REGISTRATION_FAILURE_WAIT_FILE:-}"
		local wait_deadline=$(( $(date +%s%N) + 1000000000 ))
		while [[ -n "$wait_file" && ! -s "$wait_file" && $(date +%s%N) -lt $wait_deadline ]]; do
			sleep 0.01
		done
		return 1
	fi
	validate_hard_timeout_registry || return 1
	local record="$HARD_TIMEOUT_REGISTRY_ROOT/$pid.$BASHPID.record"
	local temporary=""
	temporary="$(mktemp "$HARD_TIMEOUT_REGISTRY_ROOT/.record.XXXXXX")" || return 1
	if ! printf 'v1 %s %s %s %s %s %s %s\n' \
		"$pid" "$pgid" "$parent_pid" "$parent_start" "$boot_id" "$pid_namespace" "$start_time" > "$temporary" || \
		! mv "$temporary" "$record"; then
		rm -f "$temporary"
		return 1
	fi
	HARD_TIMEOUT_ACTIVE_PIDS+=("$pid")
	HARD_TIMEOUT_ACTIVE_PGIDS+=("$pgid")
	HARD_TIMEOUT_ACTIVE_RECORDS+=("$record")
	HARD_TIMEOUT_ACTIVE_START_TIMES+=("$start_time")
	HARD_TIMEOUT_ACTIVE_BOOT_IDS+=("$boot_id")
	HARD_TIMEOUT_ACTIVE_PID_NAMESPACES+=("$pid_namespace")
	if [[ -n "${HARD_TIMEOUT_TRACE_FILE:-}" ]]; then
		printf '%s %s %s %s\n' "$gate_name" "$pid" "$pgid" "$parent_pid" >> "$HARD_TIMEOUT_TRACE_FILE"
	fi
	HARD_TIMEOUT_LAST_RECORD="$record"
	HARD_TIMEOUT_LAST_START_TIME="$start_time"
	HARD_TIMEOUT_LAST_BOOT_ID="$boot_id"
	HARD_TIMEOUT_LAST_PID_NAMESPACE="$pid_namespace"
}

read_timeout_record() {
	local record="$1"
	local version extra
	TIMEOUT_RECORD_PID=""
	TIMEOUT_RECORD_PGID=""
	TIMEOUT_RECORD_PARENT_PID=""
	TIMEOUT_RECORD_PARENT_START=""
	TIMEOUT_RECORD_BOOT_ID=""
	TIMEOUT_RECORD_PID_NAMESPACE=""
	TIMEOUT_RECORD_START_TIME=""
	if [[ ! -e "$record" ]]; then
		return 2
	fi
	if [[ ! -f "$record" || -L "$record" ]]; then
		return 1
	fi
	if ! read -r version TIMEOUT_RECORD_PID TIMEOUT_RECORD_PGID TIMEOUT_RECORD_PARENT_PID \
			TIMEOUT_RECORD_PARENT_START TIMEOUT_RECORD_BOOT_ID TIMEOUT_RECORD_PID_NAMESPACE \
			TIMEOUT_RECORD_START_TIME extra < "$record"; then
		[[ ! -e "$record" ]] && return 2
		return 1
	fi
	if [[ "$version" != "v1" || -n "${extra:-}" || \
		! "$TIMEOUT_RECORD_PID" =~ ^[1-9][0-9]*$ || \
		! "$TIMEOUT_RECORD_PGID" =~ ^[1-9][0-9]*$ || \
		! "$TIMEOUT_RECORD_PARENT_PID" =~ ^[0-9]+$ || \
		! "$TIMEOUT_RECORD_PARENT_START" =~ ^[0-9]+$ || \
		! "$TIMEOUT_RECORD_BOOT_ID" =~ ^[0-9a-fA-F-]+$ || \
		! "$TIMEOUT_RECORD_PID_NAMESPACE" =~ ^pid:\[[0-9]+\]$ || \
		! "$TIMEOUT_RECORD_START_TIME" =~ ^[0-9]+$ ]]; then
		return 1
	fi
}

remove_active_timeout() {
	local completed_pid="$1"
	local remaining_pids=()
	local remaining_pgids=()
	local remaining_records=()
	local remaining_starts=()
	local remaining_boots=()
	local remaining_namespaces=()
	local index
	for ((index = 0; index < ${#HARD_TIMEOUT_ACTIVE_PIDS[@]}; index += 1)); do
		if [[ "${HARD_TIMEOUT_ACTIVE_PIDS[$index]}" != "$completed_pid" ]]; then
			remaining_pids+=("${HARD_TIMEOUT_ACTIVE_PIDS[$index]}")
			remaining_pgids+=("${HARD_TIMEOUT_ACTIVE_PGIDS[$index]}")
			remaining_records+=("${HARD_TIMEOUT_ACTIVE_RECORDS[$index]}")
			remaining_starts+=("${HARD_TIMEOUT_ACTIVE_START_TIMES[$index]}")
			remaining_boots+=("${HARD_TIMEOUT_ACTIVE_BOOT_IDS[$index]}")
			remaining_namespaces+=("${HARD_TIMEOUT_ACTIVE_PID_NAMESPACES[$index]}")
		fi
	done
	HARD_TIMEOUT_ACTIVE_PIDS=("${remaining_pids[@]}")
	HARD_TIMEOUT_ACTIVE_PGIDS=("${remaining_pgids[@]}")
	HARD_TIMEOUT_ACTIVE_RECORDS=("${remaining_records[@]}")
	HARD_TIMEOUT_ACTIVE_START_TIMES=("${remaining_starts[@]}")
	HARD_TIMEOUT_ACTIVE_BOOT_IDS=("${remaining_boots[@]}")
	HARD_TIMEOUT_ACTIVE_PID_NAMESPACES=("${remaining_namespaces[@]}")
}

cleanup_registered_timeout_descendants() {
	local parent_pid="$1"
	local parent_start="$2"
	local grace_seconds="$3"
	local max_nodes="${HARD_TIMEOUT_REGISTRY_MAX_NODES:-128}"
	local max_depth="${HARD_TIMEOUT_REGISTRY_MAX_DEPTH:-16}"
	validate_hard_timeout_registry || return 1

	local -a record_paths=()
	mapfile -t record_paths < <(find "$HARD_TIMEOUT_REGISTRY_ROOT" -mindepth 1 -maxdepth 1 -type f -name '*.record' -print | LC_ALL=C sort)
	local -a parsed_record_paths=() pids=() pgids=() parents=() parent_starts=() boots=() namespaces=() starts=()
	local record=""
	for record in "${record_paths[@]}"; do
		local record_status=0
		read_timeout_record "$record" || record_status=$?
		if [[ "$record_status" -eq 2 ]]; then
			continue
		fi
		if [[ "$record_status" -ne 0 ]]; then
			echo "Malformed timeout registry record: $record" >&2
			rm -f "$record"
			return 1
		fi
		parsed_record_paths+=("$record")
		pids+=("$TIMEOUT_RECORD_PID")
		pgids+=("$TIMEOUT_RECORD_PGID")
		parents+=("$TIMEOUT_RECORD_PARENT_PID")
		parent_starts+=("$TIMEOUT_RECORD_PARENT_START")
		boots+=("$TIMEOUT_RECORD_BOOT_ID")
		namespaces+=("$TIMEOUT_RECORD_PID_NAMESPACE")
		starts+=("$TIMEOUT_RECORD_START_TIME")
	done

	local -a queue_pids=("$parent_pid") queue_starts=("$parent_start") queue_depths=(0)
	local -a selected=()
	local queue_index=0
	local child_index child_depth key
	declare -A visited=( ["$parent_pid:$parent_start"]=1 )
	while (( queue_index < ${#queue_pids[@]} )); do
		for ((child_index = 0; child_index < ${#pids[@]}; child_index += 1)); do
			if [[ "${parents[$child_index]}" != "${queue_pids[$queue_index]}" || \
				"${parent_starts[$child_index]}" != "${queue_starts[$queue_index]}" ]]; then
				continue
			fi
			child_depth=$((queue_depths[$queue_index] + 1))
			key="${pids[$child_index]}:${starts[$child_index]}"
			if [[ -n "${visited[$key]:-}" ]]; then
				echo "Cycle or duplicate identity in timeout registry: $key" >&2
				return 1
			fi
			if (( child_depth > max_depth || ${#selected[@]} >= max_nodes )); then
				echo "Timeout registry traversal bound exceeded: depth=$child_depth nodes=${#selected[@]}" >&2
				return 1
			fi
			visited[$key]=1
			selected+=("$child_index")
			queue_pids+=("${pids[$child_index]}")
			queue_starts+=("${starts[$child_index]}")
			queue_depths+=("$child_depth")
		done
		queue_index=$((queue_index + 1))
	done

	local cleanup_status=0
	local selection_index
	for ((selection_index = ${#selected[@]} - 1; selection_index >= 0; selection_index -= 1)); do
		child_index="${selected[$selection_index]}"
		if ! terminate_timeout_identity \
			"${pids[$child_index]}" "${pgids[$child_index]}" "${boots[$child_index]}" \
			"${namespaces[$child_index]}" "${starts[$child_index]}" "$grace_seconds"; then
			cleanup_status=1
		fi
		rm -f "${parsed_record_paths[$child_index]}"
	done
	return "$cleanup_status"
}

cleanup_hard_timeout_processes() {
	local grace_seconds="${HARD_TIMEOUT_CLEANUP_GRACE_SECONDS:-1}"
	local cleanup_status=0
	local active_pids=("${HARD_TIMEOUT_ACTIVE_PIDS[@]}")
	local active_pgids=("${HARD_TIMEOUT_ACTIVE_PGIDS[@]}")
	local active_records=("${HARD_TIMEOUT_ACTIVE_RECORDS[@]}")
	local active_starts=("${HARD_TIMEOUT_ACTIVE_START_TIMES[@]}")
	local active_boots=("${HARD_TIMEOUT_ACTIVE_BOOT_IDS[@]}")
	local active_namespaces=("${HARD_TIMEOUT_ACTIVE_PID_NAMESPACES[@]}")
	local index
	for ((index = 0; index < ${#active_pids[@]}; index += 1)); do
		cleanup_registered_timeout_descendants "${active_pids[$index]}" "${active_starts[$index]}" "$grace_seconds" || cleanup_status=1
		terminate_timeout_identity "${active_pids[$index]}" "${active_pgids[$index]}" \
			"${active_boots[$index]}" "${active_namespaces[$index]}" "${active_starts[$index]}" "$grace_seconds" || cleanup_status=1
		rm -f "${active_records[$index]}"
		remove_active_timeout "${active_pids[$index]}"
	done

	if [[ "${HARD_TIMEOUT_REGISTRY_OWNER_PID:-}" == "$BASHPID" && -d "${HARD_TIMEOUT_REGISTRY_ROOT:-}" ]]; then
		local -a remaining_records=()
		mapfile -t remaining_records < <(find "$HARD_TIMEOUT_REGISTRY_ROOT" -mindepth 1 -maxdepth 1 -type f -name '*.record' -print | LC_ALL=C sort)
		local record
		for record in "${remaining_records[@]}"; do
			local record_status=0
			read_timeout_record "$record" || record_status=$?
			if [[ "$record_status" -eq 2 ]]; then
				continue
			fi
			if [[ "$record_status" -ne 0 ]]; then
				echo "Malformed timeout registry record during owner cleanup: $record" >&2
				rm -f "$record"
				cleanup_status=1
				continue
			fi
			cleanup_registered_timeout_descendants "$TIMEOUT_RECORD_PID" "$TIMEOUT_RECORD_START_TIME" "$grace_seconds" || cleanup_status=1
			terminate_timeout_identity "$TIMEOUT_RECORD_PID" "$TIMEOUT_RECORD_PGID" \
				"$TIMEOUT_RECORD_BOOT_ID" "$TIMEOUT_RECORD_PID_NAMESPACE" "$TIMEOUT_RECORD_START_TIME" "$grace_seconds" || cleanup_status=1
			rm -f "$record"
		done
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
	if ! ensure_hard_timeout_registry; then
		echo "Timeout registry preflight failed before spawning $gate_name." >&2
		return 72
	fi

	echo "TIMEOUT_GATE_START gate=$gate_name timeout=${timeout_seconds}s kill_after=${kill_after_seconds}s"
	local spawn_handshake="$HARD_TIMEOUT_REGISTRY_ROOT/.spawn.$BASHPID.$RANDOM"
	local spawn_ack="$spawn_handshake.ack"
	local completion_file="$spawn_handshake.complete"
	local status=0
	setsid bash -c '
		timeout_seconds="$1"
		kill_after_seconds="$2"
		spawn_handshake="$3"
		spawn_ack="$4"
		completion_file="$5"
		parent_pid="$6"
		shift 6
		trap ":" TERM INT
		trap "exit 0" USR1
		printf "%s\n" "$BASHPID" > "$spawn_handshake" || exit 72
		while [[ ! -s "$spawn_ack" ]]; do
			if ! kill -0 "$PPID" 2>/dev/null; then
				exit 72
			fi
			sleep 0.01
		done
		ack="$(<"$spawn_ack")"
		rm -f "$spawn_handshake" "$spawn_ack"
		if [[ "$ack" != "go" ]]; then
			while kill -0 "$parent_pid" 2>/dev/null; do sleep 0.02; done
			exit 72
		fi
		export HARD_TIMEOUT_PARENT_PID="$BASHPID"
		command_status=0
		timeout --foreground --signal=TERM --kill-after="${kill_after_seconds}s" "${timeout_seconds}s" "$@" || command_status=$?
		temporary="${completion_file}.tmp.$BASHPID"
		printf "%s\n" "$command_status" > "$temporary" || exit 72
		mv "$temporary" "$completion_file" || exit 72
		while kill -0 "$parent_pid" 2>/dev/null; do sleep 0.02; done
		exit 72
	' timeout-supervisor "$timeout_seconds" "$kill_after_seconds" "$spawn_handshake" "$spawn_ack" "$completion_file" "$BASHPID" "$@" &
	local timeout_pid=$!
	local timeout_pgid="$timeout_pid"
	local handshake_deadline=$(( $(date +%s%N) + 1000000000 ))
	while [[ ! -s "$spawn_handshake" && $(date +%s%N) -lt $handshake_deadline ]]; do
		if ! process_exists "$timeout_pid"; then
			break
		fi
		sleep 0.01
	done
	if [[ ! -s "$spawn_handshake" ]]; then
		terminate_process_group "$timeout_pgid" "$kill_after_seconds" || true
		wait "$timeout_pid" 2>/dev/null || true
		rm -f "$spawn_handshake" "$spawn_ack" "$completion_file" "$completion_file".tmp.*
		echo "Timeout process handshake failed after spawning $gate_name." >&2
		return 72
	fi
	local spawn_identity=""
	spawn_identity="$(read_process_identity "$timeout_pid")" || true
	if [[ -n "${HARD_TIMEOUT_TEST_SPAWN_PID_FILE:-}" ]]; then
		printf '%s\n' "$timeout_pid" > "$HARD_TIMEOUT_TEST_SPAWN_PID_FILE"
		printf '%s\n' "$timeout_pgid" > "$HARD_TIMEOUT_TEST_SPAWN_PID_FILE.pgid"
	fi
	if [[ "${HARD_TIMEOUT_TEST_REGISTRY_DELETE_AFTER_SPAWN:-0}" == "1" ]]; then
		rm -rf "$HARD_TIMEOUT_REGISTRY_ROOT"
	fi
	if ! register_timeout_process "$gate_name" "$timeout_pid" "$timeout_pgid"; then
		{ printf '%s\n' stop > "$spawn_ack"; } 2>/dev/null || true
		local boot_id pid_namespace start_time
		if [[ -n "$spawn_identity" ]]; then
			read -r boot_id pid_namespace start_time <<< "$spawn_identity"
			terminate_timeout_identity "$timeout_pid" "$timeout_pgid" "$boot_id" "$pid_namespace" "$start_time" "$kill_after_seconds" || true
		else
			terminate_process_group "$timeout_pgid" "$kill_after_seconds" || true
			wait "$timeout_pid" 2>/dev/null || true
		fi
		rm -f "$spawn_handshake" "$spawn_ack" "$completion_file" "$completion_file".tmp.*
		echo "Timeout process registration failed after spawning $gate_name; spawned tree was reaped." >&2
		return 72
	fi
	local record="$HARD_TIMEOUT_LAST_RECORD"
	local start_time="$HARD_TIMEOUT_LAST_START_TIME"
	local boot_id="$HARD_TIMEOUT_LAST_BOOT_ID"
	local pid_namespace="$HARD_TIMEOUT_LAST_PID_NAMESPACE"
	if ! { printf '%s\n' go > "$spawn_ack"; } 2>/dev/null; then
		terminate_timeout_identity "$timeout_pid" "$timeout_pgid" "$boot_id" "$pid_namespace" "$start_time" "$kill_after_seconds" || true
		rm -f "$record" "$spawn_handshake" "$spawn_ack" "$completion_file" "$completion_file".tmp.*
		remove_active_timeout "$timeout_pid"
		return 72
	fi
	echo "TIMEOUT_GATE_PROCESS gate=$gate_name pid=$timeout_pid pgid=$timeout_pgid"
	local completion_deadline=$(( $(date +%s%N) + (timeout_seconds + kill_after_seconds + 2) * 1000000000 ))
	while [[ ! -s "$completion_file" ]]; do
		if ! process_exists "$timeout_pid" || (( $(date +%s%N) >= completion_deadline )); then
			status=71
			break
		fi
		sleep 0.02
	done
	if [[ "$status" -ne 71 ]]; then
		IFS= read -r status < "$completion_file" || status=71
		if [[ ! "$status" =~ ^[0-9]+$ || "$status" -gt 255 ]]; then
			status=71
		fi
	fi

	local cleanup_status=0
	cleanup_registered_timeout_descendants "$timeout_pid" "$start_time" "$kill_after_seconds" || cleanup_status=1
	terminate_timeout_identity "$timeout_pid" "$timeout_pgid" "$boot_id" "$pid_namespace" "$start_time" "$kill_after_seconds" || cleanup_status=1
	rm -f "$record" "$completion_file" "$completion_file".tmp.*
	remove_active_timeout "$timeout_pid"
	if [[ "$cleanup_status" -ne 0 ]]; then
		return 71
	fi
	if [[ "$status" -eq 124 || "$status" -eq 137 ]]; then
		echo "TIMEOUT_GATE_EXPIRED gate=$gate_name status=$status timeout=${timeout_seconds}s" >&2
	fi
	return "$status"
}
