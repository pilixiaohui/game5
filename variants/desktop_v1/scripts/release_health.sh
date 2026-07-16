#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$project_root/scripts/timeout_gate.sh"

handle_release_health_signal() {
	trap - TERM INT
	cleanup_hard_timeout_processes || true
	exit 143
}

run_clean_clone() {
	local release_root="$1"
	local repo_root="$2"
	local source_head="$3"
	git clone --quiet --no-local "$repo_root" "$release_root/clean-clone"
	git -C "$release_root/clean-clone" checkout --quiet --detach "$source_head"
}

reject_godot_errors() {
	local label="$1"
	local log_path="$2"
	if rg -n 'SCRIPT ERROR:|ERROR:|Parse Error|Failed loading resource|Failed to load|Unable to open' "$log_path"; then
		echo "$label log contains a resource or script error." >&2
		return 1
	fi
}

assert_art_v1_imports() {
	local clean_project="$1"
	local import_file
	local imported_path
	local imported_count=0
	while IFS= read -r import_file; do
		imported_path="$(awk -F'"' '/^path="res:\/\/\.godot\/imported\/.*\.ctex"/ { print $2; exit }' "$import_file")"
		if [[ -z "$imported_path" || ! -s "$clean_project/${imported_path#res://}" ]]; then
			echo "Cold-import did not produce the required texture for $import_file." >&2
			return 1
		fi
		imported_count=$((imported_count + 1))
	done < <(find "$clean_project/assets/art_v1" -maxdepth 1 -type f -name '*.png.import' | sort)
	if [[ "$imported_count" -ne 12 ]]; then
		echo "Cold-import verified $imported_count art textures instead of 12." >&2
		return 1
	fi
	echo "COLD_IMPORT_OK textures=$imported_count cache=project-local"
}

run_cold_import() {
	local release_root="$1"
	local clean_project="$release_root/clean-clone/variants/desktop_v1"
	local import_log="$release_root/cold-import.log"
	local status=0
	env \
		HOME="$release_root/import-home" \
		XDG_CONFIG_HOME="$release_root/import-config" \
		XDG_CACHE_HOME="$release_root/import-cache" \
		XDG_DATA_HOME="$release_root/import-data" \
		godot4 --headless --editor --path "$clean_project" --quit >"$import_log" 2>&1 || status=$?
	cat "$import_log"
	if [[ "$status" -ne 0 ]]; then
		return "$status"
	fi
	reject_godot_errors "Cold-import" "$import_log"
	assert_art_v1_imports "$clean_project"
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
	reject_godot_errors "Cold-start" "$brand_log"
}

run_screenshots() {
	local release_root="$1"
	local clean_project="$release_root/clean-clone/variants/desktop_v1"
	env \
		SCREENSHOT_PROJECT_ROOT="$clean_project" \
		SCREENSHOT_SCRATCH_PARENT="$release_root" \
		SCREENSHOT_TIMEOUT_SECONDS="${RELEASE_HEALTH_SCREENSHOT_INNER_TIMEOUT_SECONDS:-90}" \
		SCREENSHOT_KILL_AFTER_SECONDS="${RELEASE_HEALTH_KILL_AFTER_SECONDS:-5}" \
		"$project_root/scripts/verify_screenshots.sh"
}

if [[ "${1:-}" == "--clean-clone" ]]; then
	run_clean_clone "$2" "$3" "$4"
	exit $?
fi

if [[ "${1:-}" == "--cold-start" ]]; then
	run_cold_start "$2"
	exit $?
fi

if [[ "${1:-}" == "--cold-import" ]]; then
	run_cold_import "$2"
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
	local clean_project="$release_root/clean-clone/variants/desktop_v1"
	case "$gate_name" in
		isolation)
			run_gate "isolation" "${RELEASE_HEALTH_ISOLATION_TIMEOUT_SECONDS:-180}" env --chdir="$clean_project" "$clean_project/scripts/verify_isolation.sh"
			;;
		autosave)
			run_gate "autosave" "${RELEASE_HEALTH_AUTOSAVE_TIMEOUT_SECONDS:-65}" env --chdir="$clean_project" "$clean_project/scripts/verify_autosave_scheduler.sh"
			;;
		recovery-ui)
			run_gate "recovery-ui" "${RELEASE_HEALTH_RECOVERY_UI_TIMEOUT_SECONDS:-95}" env --chdir="$clean_project" "$clean_project/scripts/verify_acceptance_regressions.sh"
			;;
		transaction-reconciliation)
			run_gate "transaction-reconciliation" "${RELEASE_HEALTH_TRANSACTION_TIMEOUT_SECONDS:-45}" env --chdir="$clean_project" "$clean_project/scripts/verify_transaction_reconciliation.sh"
			;;
		capture-lock-wait)
			run_gate "capture-lock-wait" "${RELEASE_HEALTH_CAPTURE_LOCK_WAIT_TIMEOUT_SECONDS:-10}" env --chdir="$clean_project" "$clean_project/scripts/verify_art_v1_capture_lock_wait.sh"
			;;
		capture-atomic)
			run_gate "capture-atomic" "${RELEASE_HEALTH_CAPTURE_ATOMIC_TIMEOUT_SECONDS:-30}" env --chdir="$clean_project" "$clean_project/scripts/verify_art_v1_capture_atomic.sh" --skip-lock-wait
			;;
		timeout-owner-records)
			run_gate "timeout-owner-records" "${RELEASE_HEALTH_TIMEOUT_OWNER_RECORDS_TIMEOUT_SECONDS:-10}" env --chdir="$clean_project" "$clean_project/scripts/verify_timeout_owner_records.sh"
			;;
		timeout-guards)
			run_gate "timeout-guards" "${RELEASE_HEALTH_TIMEOUT_GUARDS_TIMEOUT_SECONDS:-55}" env --chdir="$clean_project" "$clean_project/scripts/verify_timeout_guards.sh"
			;;
		clean-clone)
			run_gate "clean-clone" "${RELEASE_HEALTH_CLONE_TIMEOUT_SECONDS:-45}" "$project_root/scripts/release_health.sh" --clean-clone "$release_root" "$repo_root" "$source_head"
			;;
		cold-import)
			run_gate "cold-import" "${RELEASE_HEALTH_COLD_IMPORT_TIMEOUT_SECONDS:-40}" "$project_root/scripts/release_health.sh" --cold-import "$release_root"
			;;
		cold-start)
			run_gate "cold-start" "${RELEASE_HEALTH_COLD_START_TIMEOUT_SECONDS:-25}" "$project_root/scripts/release_health.sh" --cold-start "$release_root"
			;;
		screenshots)
			run_gate "screenshots" "${RELEASE_HEALTH_SCREENSHOTS_TIMEOUT_SECONDS:-110}" "$project_root/scripts/release_health.sh" --screenshots "$release_root"
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

	run_selected_gate clean-clone "$release_root" "$repo_root" "$source_head"
	run_selected_gate cold-import "$release_root" "$repo_root" "$source_head"
	run_selected_gate isolation "$release_root" "$repo_root" "$source_head"
	run_selected_gate autosave "$release_root" "$repo_root" "$source_head"
	run_selected_gate recovery-ui "$release_root" "$repo_root" "$source_head"
	run_selected_gate transaction-reconciliation "$release_root" "$repo_root" "$source_head"
	run_selected_gate capture-lock-wait "$release_root" "$repo_root" "$source_head"
	run_selected_gate capture-atomic "$release_root" "$repo_root" "$source_head"
	run_selected_gate timeout-owner-records "$release_root" "$repo_root" "$source_head"
	run_selected_gate timeout-guards "$release_root" "$repo_root" "$source_head"
	run_selected_gate cold-start "$release_root" "$repo_root" "$source_head"
	run_selected_gate screenshots "$release_root" "$repo_root" "$source_head"
}

if [[ "${1:-}" == "--run-gates" ]]; then
	trap 'cleanup_hard_timeout_processes || true' EXIT
	trap handle_release_health_signal TERM INT
	run_release_gates "$2"
	exit $?
fi

scratch_parent="${RELEASE_HEALTH_SCRATCH_PARENT:-${TMPDIR:-/tmp}}"
control_root="$(mktemp -d "$scratch_parent/xenogenesis-release-control.XXXXXX")"
release_root=""
cleanup_release_health() {
	cleanup_hard_timeout_processes || true
	rm -rf "$control_root" "$release_root"
}
trap cleanup_release_health EXIT
trap handle_release_health_signal TERM INT
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

echo "RELEASE_HEALTH_OK isolation_timeout=${RELEASE_HEALTH_ISOLATION_TIMEOUT_SECONDS:-180}s autosave_timeout=${RELEASE_HEALTH_AUTOSAVE_TIMEOUT_SECONDS:-65}s recovery_ui_timeout=${RELEASE_HEALTH_RECOVERY_UI_TIMEOUT_SECONDS:-95}s transaction_timeout=${RELEASE_HEALTH_TRANSACTION_TIMEOUT_SECONDS:-45}s capture_lock_wait_timeout=${RELEASE_HEALTH_CAPTURE_LOCK_WAIT_TIMEOUT_SECONDS:-10}s capture_atomic_timeout=${RELEASE_HEALTH_CAPTURE_ATOMIC_TIMEOUT_SECONDS:-30}s timeout_owner_records_timeout=${RELEASE_HEALTH_TIMEOUT_OWNER_RECORDS_TIMEOUT_SECONDS:-10}s timeout_guards_timeout=${RELEASE_HEALTH_TIMEOUT_GUARDS_TIMEOUT_SECONDS:-55}s clone_timeout=${RELEASE_HEALTH_CLONE_TIMEOUT_SECONDS:-45}s cold_import_timeout=${RELEASE_HEALTH_COLD_IMPORT_TIMEOUT_SECONDS:-40}s cold_start_timeout=${RELEASE_HEALTH_COLD_START_TIMEOUT_SECONDS:-25}s screenshots_timeout=${RELEASE_HEALTH_SCREENSHOTS_TIMEOUT_SECONDS:-110}s screenshot_inner_timeout=${RELEASE_HEALTH_SCREENSHOT_INNER_TIMEOUT_SECONDS:-90}s overall_timeout=${overall_timeout}s scratch_roots=clean-on-exit"
