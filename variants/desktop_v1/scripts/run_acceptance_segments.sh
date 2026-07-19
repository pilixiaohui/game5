#!/usr/bin/env bash
set -euo pipefail

project_root="$(realpath -e "$1")"
test_root="$(realpath -e "$2")"
active_pid=""
active_pgid=""

process_exists() {
	local pid="$1"
	[[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null
}

process_group_exists() {
	local pgid="$1"
	[[ "$pgid" =~ ^[0-9]+$ ]] && kill -0 -- "-$pgid" 2>/dev/null
}

stop_active_segment() {
	local exit_status="$1"
	trap - TERM INT
	if process_group_exists "$active_pgid"; then
		kill -TERM -- "-$active_pgid" 2>/dev/null || true
		local deadline=$((SECONDS + 2))
		while process_group_exists "$active_pgid" && [[ "$SECONDS" -lt "$deadline" ]]; do
			sleep 0.02
		done
		if process_group_exists "$active_pgid"; then
			kill -KILL -- "-$active_pgid" 2>/dev/null || true
		fi
	fi
	if [[ -n "$active_pid" ]]; then
		wait "$active_pid" 2>/dev/null || true
	fi
	exit "$exit_status"
}
trap 'stop_active_segment 143' TERM
trap 'stop_active_segment 130' INT

canonical_owned_dir() {
	local path="$1"
	mkdir -p "$path"
	local canonical
	canonical="$(realpath -e "$path")"
	if [[ ! -d "$canonical" || -L "$path" || "$canonical" != "$test_root"/* ]]; then
		echo "Acceptance identity is not an owned canonical directory: $path" >&2
		return 1
	fi
	printf '%s\n' "$canonical"
}

project_cache_fingerprint() {
	local cache_root="$project_root/.godot"
	if [[ ! -d "$cache_root" || -L "$cache_root" ]]; then
		echo "Acceptance project cache is missing or not a real directory: $cache_root" >&2
		return 1
	fi
	(
		cd "$cache_root"
		while IFS= read -r -d '' path; do
			printf '%s|%s|%s\n' "$path" "$(sha256sum "$path" | awk '{print $1}')" "$(stat -c '%s|%y' "$path")"
		done < <(find . -type f -print0 | sort -z)
	) | sha256sum | awk '{print $1}'
}

project_cache_file_count() {
	find "$project_root/.godot" -type f -printf '.' | wc -c
}

identity_field() {
	local line="$1"
	local field="$2"
	awk -v key="$field" '{for (field_index = 1; field_index <= NF; field_index++) if ($field_index ~ ("^" key "=")) {sub("^" key "=", "", $field_index); print $field_index; exit}}' <<< "$line"
}

validate_segment_identity() {
	local segment="$1"
	local expected_renderer="$2"
	local log="$3"
	local identity_line
	identity_line="$(rg "^ACCEPTANCE_SEGMENT_IDENTITY segment=$segment " "$log")"
	if [[ -z "$identity_line" || "$(identity_field "$identity_line" renderer)" != "$expected_renderer" ]]; then
		echo "Acceptance $segment did not publish its canonical renderer identity." >&2
		return 1
	fi
	local field value
	for field in home config cache data save; do
		value="$(identity_field "$identity_line" "$field")"
		if [[ -z "$value" || ! -d "$value" || -L "$value" || "$(realpath -e "$value")" != "$value" || "$value" != "$test_root"/* ]]; then
			echo "Acceptance $segment $field identity is not canonical and owned: ${value:-missing}" >&2
			return 1
		fi
	done
	value="$(identity_field "$identity_line" display)"
	if [[ ! "$value" =~ ^:[0-9]+$ ]]; then
		echo "Acceptance $segment display identity is malformed: ${value:-missing}" >&2
		return 1
	fi
}

run_segment() {
	local segment="$1"
	local renderer_mode="$2"
	local display_start="$3"
	local home_root config_root cache_root data_root exit_ready log
	home_root="$(canonical_owned_dir "$test_root/$segment-home")"
	config_root="$(canonical_owned_dir "$test_root/$segment-config")"
	cache_root="$(canonical_owned_dir "$test_root/$segment-cache")"
	data_root="$(canonical_owned_dir "$test_root/$segment-data")"
	exit_ready="$test_root/$segment-exit-ready"
	log="$test_root/$segment.log"
	local -a godot_command=(godot4 --audio-driver Dummy)
	if [[ "$renderer_mode" == "dummy" ]]; then
		godot_command+=(--rendering-driver dummy)
	fi
	godot_command+=(--path "$project_root" -s res://tests/acceptance_regression_runner.gd --
		"--scratch-data-root=$data_root" "--exit-ready-file=$exit_ready" "--segment=$segment" "--renderer-mode=$renderer_mode")
	if [[ "${ACCEPTANCE_ORCHESTRATION_FAULT_TOKEN:-}" == "acceptance-4core-oracle" && \
		"${ACCEPTANCE_TEST_FAIL_SEGMENT:-}" == "$segment" ]]; then
		godot_command=(bash -c 'exit 19')
	fi

	local start_ns status pid pgid elapsed_ms
	start_ns="$(date +%s%N)"
	setsid xvfb-run -a -n "$display_start" env \
		HOME="$home_root" \
		XDG_CONFIG_HOME="$config_root" \
		XDG_CACHE_HOME="$cache_root" \
		XDG_DATA_HOME="$data_root" \
		"${godot_command[@]}" > "$log" 2>&1 &
	pid=$!
	pgid="$pid"
	active_pid="$pid"
	active_pgid="$pgid"
	echo "ACCEPTANCE_SEGMENT_ORCHESTRATION segment=$segment phase=start mode=$renderer_mode pid=$pid pgid=$pgid start_ns=$start_ns"
	status=0
	wait "$pid" || status=$?
	for _ in $(seq 1 100); do
		if ! process_group_exists "$pgid"; then
			break
		fi
		sleep 0.02
	done
	elapsed_ms=$(( ($(date +%s%N) - start_ns) / 1000000 ))
	cat "$log"
	local pid_alive=0
	local pgid_alive=0
	if process_exists "$pid"; then
		pid_alive=1
	fi
	if process_group_exists "$pgid"; then
		pgid_alive=1
	fi
	echo "ACCEPTANCE_SEGMENT_ORCHESTRATION segment=$segment phase=reaped mode=$renderer_mode status=$status pid=$pid pgid=$pgid pid_alive=$pid_alive pgid_alive=$pgid_alive elapsed_ms=$elapsed_ms"
	active_pid=""
	active_pgid=""
	if [[ "$status" -ne 0 ]]; then
		return "$status"
	fi
	if [[ "$pid_alive" -ne 0 || "$pgid_alive" -ne 0 ]]; then
		return 1
	fi
	if [[ ! -s "$exit_ready" ]] || \
		! rg -q "^ACCEPTANCE_SEGMENT_LIFECYCLE segment=$segment phase=teardown .*nodes=0 signals=0$" "$log" || \
		! rg -q "^ACCEPTANCE_SEGMENT_LIFECYCLE segment=$segment phase=quit .*status=0$" "$log"; then
		echo "Acceptance $segment segment exited without complete teardown/quit markers." >&2
		return 1
	fi
	validate_segment_identity "$segment" "$renderer_mode" "$log"
	if [[ "$segment" == "recovery" ]]; then
		local expected_phases="start ctrl-s-resolved system-page-resolved autosave-boundary autosave-resolved first-save-resolved complete teardown quit"
		local -a phases=()
		mapfile -t phases < <(sed -n 's/^ACCEPTANCE_RECOVERY_LIFECYCLE phase=\([^ ]*\).*/\1/p' "$log")
		if [[ "${phases[*]:-}" != "$expected_phases" ]]; then
			echo "Acceptance recovery lifecycle markers are incomplete or out of order: ${phases[*]:-none}" >&2
			return 1
		fi
		local expected_ctrl_s_phases="window-ready focus-ready input-dispatch-ready ctrl-s-injected save-request durable-completion teardown"
		local -a ctrl_s_phases=()
		mapfile -t ctrl_s_phases < <(sed -n 's/^ACCEPTANCE_CTRL_S_BOUNDARY phase=\([^ ]*\).*/\1/p' "$log")
		if [[ "${ctrl_s_phases[*]:-}" != "$expected_ctrl_s_phases" ]]; then
			echo "Acceptance Ctrl+S production boundary markers are incomplete or out of order: ${ctrl_s_phases[*]:-none}" >&2
			return 1
		fi
		local previous_boundary_ms=-1
		local boundary_ms
		while IFS= read -r boundary_ms; do
			if [[ ! "$boundary_ms" =~ ^[0-9]+$ || "$boundary_ms" -lt "$previous_boundary_ms" ]]; then
				echo "Acceptance Ctrl+S production boundary is not monotonic: value=${boundary_ms:-missing} previous=$previous_boundary_ms" >&2
				return 1
			fi
			previous_boundary_ms="$boundary_ms"
		done < <(sed -n -E 's/^ACCEPTANCE_CTRL_S_BOUNDARY .* boundary_ms=([0-9]+) .*/\1/p' "$log")
		if [[ "$previous_boundary_ms" -lt 0 || "$previous_boundary_ms" -gt 6000 ]]; then
			echo "Acceptance Ctrl+S production boundary exceeded 6000ms: $previous_boundary_ms" >&2
			return 1
		fi
		local autosave_msec=""
		autosave_msec="$(sed -n -E 's/^RECOVERY_UI_REAL_AUTOSAVE elapsed_msec=([0-9]+).*/\1/p' "$log")"
		if [[ ! "$autosave_msec" =~ ^[0-9]+$ || "$autosave_msec" -lt 30000 || "$autosave_msec" -ge 37000 ]]; then
			echo "Acceptance recovery did not preserve the real 30-second autosave boundary: ${autosave_msec:-missing}" >&2
			return 1
		fi
	fi
}

assert_distinct_identities() {
	local -a identities=()
	local segment field line
	for segment in recovery core; do
		line="$(rg "^ACCEPTANCE_SEGMENT_IDENTITY segment=$segment " "$test_root/$segment.log")"
		for field in home config cache data save; do
			identities+=("$(identity_field "$line" "$field")")
		done
	done
	if [[ "$(printf '%s\n' "${identities[@]}" | sort -u | wc -l)" -ne 10 ]]; then
		echo "Acceptance segment filesystem identities are not mutually distinct." >&2
		return 1
	fi
	local recovery_display core_display
	recovery_display="$(identity_field "$(rg '^ACCEPTANCE_SEGMENT_IDENTITY segment=recovery ' "$test_root/recovery.log")" display)"
	core_display="$(identity_field "$(rg '^ACCEPTANCE_SEGMENT_IDENTITY segment=core ' "$test_root/core.log")" display)"
	if [[ "$recovery_display" == "$core_display" ]]; then
		echo "Acceptance segment display identities must be distinct: $recovery_display" >&2
		return 1
	fi
	echo "ACCEPTANCE_SEGMENT_ISOLATION_OK filesystems=10-distinct displays=$recovery_display,$core_display renderers=recovery-rendered,core-dummy"
}

cache_before="$(project_cache_fingerprint)"
cache_files_before="$(project_cache_file_count)"
echo "ACCEPTANCE_PROJECT_CACHE phase=before fingerprint=$cache_before files=$cache_files_before"
echo "ACCEPTANCE_CPU_CONSTRAINT allowed=$(awk '/^Cpus_allowed_list:/ {print $2}' /proc/self/status) count=$(nproc)"

# Recovery owns the real renderer while its wall-clock scheduler crosses 30 seconds.
run_segment recovery rendered 91
run_segment core dummy 191
assert_distinct_identities

cache_after="$(project_cache_fingerprint)"
cache_files_after="$(project_cache_file_count)"
echo "ACCEPTANCE_PROJECT_CACHE phase=after fingerprint=$cache_after files=$cache_files_after"
if [[ "$cache_before" != "$cache_after" || "$cache_files_before" -ne "$cache_files_after" ]]; then
	echo "Acceptance segments modified the shared project cache." >&2
	exit 1
fi

core_summary="$(rg '^ACCEPTANCE_CORE_ASSERTIONS_OK cases=4 resolutions=3 assertions=' "$test_root/core.log")"
recovery_summary="$(rg '^ACCEPTANCE_RECOVERY_ASSERTIONS_OK cases=1 assertions=' "$test_root/recovery.log")"
core_assertions="$(sed -E 's/.* assertions=([0-9]+).*/\1/' <<< "$core_summary")"
recovery_assertions="$(sed -E 's/.* assertions=([0-9]+).*/\1/' <<< "$recovery_summary")"
if [[ ! "$core_assertions" =~ ^[0-9]+$ || ! "$recovery_assertions" =~ ^[0-9]+$ ]] || \
	[[ $((core_assertions + recovery_assertions)) -ne 487 ]]; then
	echo "Acceptance segmented assertions did not preserve the 487-assertion contract: core=$core_assertions recovery=$recovery_assertions" >&2
	exit 1
fi

printf 'ready\n' > "$test_root/exit-ready"
echo "ACCEPTANCE_ASSERTIONS_OK cases=5 resolutions=3 assertions=487 segments=recovery,core core_assertions=$core_assertions recovery_assertions=$recovery_assertions"
