#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$project_root/scripts/timeout_gate.sh"

run_clean_clone() {
	local release_root="$1"
	local repo_root="$2"
	local source_head="$3"
	git clone --quiet --no-local "$repo_root" "$release_root/clean-clone"
	git -C "$release_root/clean-clone" checkout --quiet --detach "$source_head"
}

run_cold_start() {
	local release_root="$1"
	local clean_project="$release_root/clean-clone/variants/desktop_v1"
	local brand_log="$release_root/cold-start-brand.log"
	local status=0
	xvfb-run -a env \
		HOME="$release_root/brand-home" \
		XDG_CONFIG_HOME="$release_root/brand-config" \
		XDG_CACHE_HOME="$release_root/brand-cache" \
		XDG_DATA_HOME="$release_root/brand-data" \
		godot4 --audio-driver Dummy --path "$clean_project" -s res://tests/clean_start_runner.gd >"$brand_log" 2>&1 || status=$?
	cat "$brand_log"
	if [[ "$status" -ne 0 ]]; then
		return "$status"
	fi
	if rg -n 'ERROR:|Parse Error|Failed loading resource|Failed to load' "$brand_log"; then
		echo "Cold-start log contains a resource or script error." >&2
		return 1
	fi
}

run_screenshots() {
	local release_root="$1"
	local clean_project="$release_root/clean-clone/variants/desktop_v1"
	local screenshot_log="$release_root/screenshots.log"
	local status=0
	env \
		HOME="$release_root/screenshot-home" \
		XDG_CONFIG_HOME="$release_root/screenshot-config" \
		XDG_CACHE_HOME="$release_root/screenshot-cache" \
		XDG_DATA_HOME="$release_root/screenshot-data" \
		godot4 --headless --path "$clean_project" -s res://tests/screenshot_runner.gd >"$screenshot_log" 2>&1 || status=$?
	cat "$screenshot_log"
	if [[ "$status" -ne 0 ]]; then
		return "$status"
	fi
	local screenshot_count
	screenshot_count="$(find "$clean_project/screenshots" -maxdepth 1 -type f -name '*.png' | wc -l)"
	if [[ "$screenshot_count" -ne 6 ]]; then
		echo "Screenshot gate produced $screenshot_count images instead of 6." >&2
		return 1
	fi
}

if [[ "${1:-}" == "--clean-clone" ]]; then
	run_clean_clone "$2" "$3" "$4"
	exit $?
fi

if [[ "${1:-}" == "--cold-start" ]]; then
	run_cold_start "$2"
	exit $?
fi

if [[ "${1:-}" == "--screenshots" ]]; then
	run_screenshots "$2"
	exit $?
fi

run_gate() {
	local gate_name="$1"
	local timeout_seconds="$2"
	shift 2
	local command=("$@")
	if [[ "${RELEASE_HEALTH_TEST_HANG_GATE:-}" == "$gate_name" ]]; then
		if [[ -z "${RELEASE_HEALTH_TEST_HANG_COMMAND:-}" ]]; then
			echo "Missing RELEASE_HEALTH_TEST_HANG_COMMAND for $gate_name." >&2
			return 2
		fi
		command=("$RELEASE_HEALTH_TEST_HANG_COMMAND")
	fi
	local status=0
	run_with_hard_timeout "$gate_name" "$timeout_seconds" "${RELEASE_HEALTH_KILL_AFTER_SECONDS:-5}" "${command[@]}" || status=$?
	if [[ "$status" -eq 124 || "$status" -eq 137 ]]; then
		return 70
	fi
	return "$status"
}

run_selected_gate() {
	local gate_name="$1"
	local release_root="$2"
	local repo_root="$3"
	local source_head="$4"
	case "$gate_name" in
		isolation)
			run_gate "isolation" "${RELEASE_HEALTH_ISOLATION_TIMEOUT_SECONDS:-120}" "$project_root/scripts/verify_isolation.sh"
			;;
		autosave)
			run_gate "autosave" "${RELEASE_HEALTH_AUTOSAVE_TIMEOUT_SECONDS:-65}" "$project_root/scripts/verify_autosave_scheduler.sh"
			;;
		clean-clone)
			run_gate "clean-clone" "${RELEASE_HEALTH_CLONE_TIMEOUT_SECONDS:-45}" "$project_root/scripts/release_health.sh" --clean-clone "$release_root" "$repo_root" "$source_head"
			;;
		cold-start)
			run_gate "cold-start" "${RELEASE_HEALTH_COLD_START_TIMEOUT_SECONDS:-60}" "$project_root/scripts/release_health.sh" --cold-start "$release_root"
			;;
		screenshots)
			run_gate "screenshots" "${RELEASE_HEALTH_SCREENSHOTS_TIMEOUT_SECONDS:-90}" "$project_root/scripts/release_health.sh" --screenshots "$release_root"
			;;
		*)
			echo "Unknown release-health gate: $gate_name" >&2
			return 2
			;;
	esac
}

run_release_gates() {
	local release_root="$1"
	local repo_root
	repo_root="$(git -C "$project_root" rev-parse --show-toplevel)"
	local source_head
	source_head="$(git -C "$repo_root" rev-parse HEAD)"
	local only_gate="${RELEASE_HEALTH_TEST_ONLY_GATE:-}"
	if [[ -n "$only_gate" ]]; then
		if [[ "${RELEASE_HEALTH_TEST_HANG_GATE:-}" != "$only_gate" ]]; then
			echo "Test-only release gate requires a matching controlled hang gate." >&2
			return 2
		fi
		run_selected_gate "$only_gate" "$release_root" "$repo_root" "$source_head"
		return $?
	fi

	run_selected_gate isolation "$release_root" "$repo_root" "$source_head"
	run_selected_gate autosave "$release_root" "$repo_root" "$source_head"
	run_selected_gate clean-clone "$release_root" "$repo_root" "$source_head"
	run_selected_gate cold-start "$release_root" "$repo_root" "$source_head"
	run_selected_gate screenshots "$release_root" "$repo_root" "$source_head"
}

if [[ "${1:-}" == "--run-gates" ]]; then
	trap cleanup_hard_timeout_processes EXIT
	trap 'exit 143' TERM INT
	run_release_gates "$2"
	exit $?
fi

scratch_parent="${RELEASE_HEALTH_SCRATCH_PARENT:-${TMPDIR:-/tmp}}"
control_root="$(mktemp -d "$scratch_parent/xenogenesis-release-control.XXXXXX")"
release_root=""
cleanup_release_health() {
	cleanup_hard_timeout_processes
	rm -rf "$control_root" "$release_root"
}
trap cleanup_release_health EXIT
trap 'exit 143' TERM INT
release_root="$(mktemp -d "$scratch_parent/xenogenesis-release-work.XXXXXX")"
overall_log="$control_root/release-health.log"
overall_timeout="${RELEASE_HEALTH_OVERALL_TIMEOUT_SECONDS:-420}"
overall_command=("$project_root/scripts/release_health.sh" --run-gates "$release_root")
if [[ "${RELEASE_HEALTH_TEST_HANG_GATE:-}" == "overall" ]]; then
	if [[ -z "${RELEASE_HEALTH_TEST_HANG_COMMAND:-}" ]]; then
		echo "Missing RELEASE_HEALTH_TEST_HANG_COMMAND for overall." >&2
		exit 2
	fi
	overall_command=("$RELEASE_HEALTH_TEST_HANG_COMMAND")
fi

cd "$project_root"
overall_status=0
run_with_hard_timeout "release-health-overall" "$overall_timeout" "${RELEASE_HEALTH_KILL_AFTER_SECONDS:-5}" "${overall_command[@]}" >"$overall_log" 2>&1 || overall_status=$?
cat "$overall_log"
if [[ "$overall_status" -ne 0 ]]; then
	exit "$overall_status"
fi

echo "RELEASE_HEALTH_OK isolation_timeout=${RELEASE_HEALTH_ISOLATION_TIMEOUT_SECONDS:-120}s autosave_timeout=${RELEASE_HEALTH_AUTOSAVE_TIMEOUT_SECONDS:-65}s clone_timeout=${RELEASE_HEALTH_CLONE_TIMEOUT_SECONDS:-45}s cold_start_timeout=${RELEASE_HEALTH_COLD_START_TIMEOUT_SECONDS:-60}s screenshots_timeout=${RELEASE_HEALTH_SCREENSHOTS_TIMEOUT_SECONDS:-90}s overall_timeout=${overall_timeout}s scratch_roots=clean-on-exit"
