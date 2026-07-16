#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$project_root/scripts/timeout_gate.sh"

scratch_parent="${ART_V1_SCRATCH_PARENT:-${TMPDIR:-/tmp}}"
control_root="$(mktemp -d "$scratch_parent/xenogenesis-art-v1-control.XXXXXX")"
work_root="$(mktemp -d "$scratch_parent/xenogenesis-art-v1-work.XXXXXX")"
output_dir="$project_root/artifacts/art_v1/captures"
output_parent="$(dirname "$output_dir")"
stage_dir=""
rollback_dir=""
commit_active=0

recover_capture_commit() {
	if [[ "$commit_active" -ne 1 || -z "$rollback_dir" || ! -d "$rollback_dir" ]]; then
		return 0
	fi
	local failed_dir=""
	if [[ -d "$output_dir" ]]; then
		failed_dir="$(mktemp -d "$output_parent/.captures-failed.XXXXXX")"
		rmdir "$failed_dir"
		if ! mv "$output_dir" "$failed_dir"; then
			echo "Could not quarantine the uncommitted capture directory." >&2
			return 1
		fi
	fi
	if ! mv "$rollback_dir" "$output_dir"; then
		echo "Could not restore the committed capture directory." >&2
		if [[ -n "$failed_dir" && -d "$failed_dir" && ! -d "$output_dir" ]]; then
			mv "$failed_dir" "$output_dir" || true
		fi
		return 1
	fi
	rollback_dir=""
	commit_active=0
	if [[ -n "$failed_dir" ]]; then
		rm -rf "$failed_dir"
	fi
}

cleanup_art_v1_capture() {
	recover_capture_commit || true
	cleanup_hard_timeout_processes || true
	if [[ -n "$stage_dir" ]]; then
		rm -rf "$stage_dir"
	fi
	if [[ -n "$rollback_dir" && "$commit_active" -eq 0 ]]; then
		rm -rf "$rollback_dir"
	fi
	rm -rf "$control_root" "$work_root"
}

handle_capture_signal() {
	local status=143
	recover_capture_commit || status=71
	cleanup_hard_timeout_processes || status=71
	exit "$status"
}

trap cleanup_art_v1_capture EXIT
trap handle_capture_signal TERM INT

mkdir -p "$output_parent" "$work_root/pass-first/captures" "$work_root/pass-second/captures"

expected_files=(
	battle_1280x720.png battle_1600x900.png battle_1920x1080.png
	hive_1280x720.png hive_1600x900.png hive_1920x1080.png
	map_1280x720.png map_1600x900.png map_1920x1080.png
	swarm_1280x720.png swarm_1600x900.png swarm_1920x1080.png
	title_1280x720.png title_1600x900.png title_1920x1080.png
)
printf '%s\n' "${expected_files[@]}" | sort > "$control_root/expected-files"

godot_bin="${ART_V1_GODOT_BIN:-godot4}"
validator_bin="${ART_V1_VALIDATOR_BIN:-godot4}"
timeout_seconds="${ART_V1_TIMEOUT_SECONDS:-120}"
validator_timeout_seconds="${ART_V1_VALIDATOR_TIMEOUT_SECONDS:-20}"
kill_after_seconds="${ART_V1_KILL_AFTER_SECONDS:-5}"

assert_capture_set() {
	local label="$1"
	local capture_root="$2"
	find "$capture_root" -maxdepth 1 -type f -printf '%f\n' | sort > "$control_root/$label-files"
	if ! cmp -s "$control_root/expected-files" "$control_root/$label-files"; then
		echo "$label did not produce the exact 15-file capture set." >&2
		diff -u "$control_root/expected-files" "$control_root/$label-files" >&2 || true
		return 1
	fi
	local filename
	for filename in "${expected_files[@]}"; do
		if [[ ! -s "$capture_root/$filename" ]]; then
			echo "$label produced a missing or empty image: $filename" >&2
			return 1
		fi
	done
}

validate_capture_root() {
	local label="$1"
	local capture_root="$2"
	assert_capture_set "$label" "$capture_root"
	local validation_root="$work_root/validation-$label"
	mkdir -p "$validation_root/tmp"
	local log_path="$control_root/$label-validation.log"
	local command=(
		env TMPDIR="$validation_root/tmp"
		HOME="$validation_root/home"
		XDG_CONFIG_HOME="$validation_root/config"
		XDG_CACHE_HOME="$validation_root/cache"
		XDG_DATA_HOME="$validation_root/data"
		ART_V1_CAPTURE_WORK_ROOT="$capture_root"
		"$validator_bin" --headless --audio-driver Dummy --path "$project_root"
		-s res://tests/art_v1_capture_runner.gd -- --validate-art-v1-child "--capture-root=$capture_root"
	)
	local status=0
	run_with_hard_timeout "art-v1-validate-$label" "$validator_timeout_seconds" "$kill_after_seconds" "${command[@]}" > "$log_path" 2>&1 || status=$?
	cat "$log_path"
	if [[ "$status" -ne 0 ]]; then
		return "$status"
	fi
}

run_capture_pass() {
	local pass_name="$1"
	local pass_root="$2"
	local capture_root="$pass_root/captures"
	local log_path="$control_root/art-v1-capture-$pass_name.log"
	mkdir -p "$pass_root/tmp" "$capture_root"
	local command=(
		env TMPDIR="$pass_root/tmp"
		xvfb-run -a env
		HOME="$pass_root/home"
		XDG_CONFIG_HOME="$pass_root/config"
		XDG_CACHE_HOME="$pass_root/cache"
		XDG_DATA_HOME="$pass_root/data"
		ART_V1_CAPTURE_WORK_ROOT="$pass_root"
		"$godot_bin" --audio-driver Dummy --path "$project_root"
		-s res://tests/art_v1_capture_runner.gd -- --capture-art-v1-child "--capture-root=$capture_root"
	)
	local status=0
	run_with_hard_timeout "art-v1-capture-$pass_name" "$timeout_seconds" "$kill_after_seconds" "${command[@]}" > "$log_path" 2>&1 || status=$?
	cat "$log_path"
	if [[ "$status" -ne 0 ]]; then
		return "$status"
	fi
	validate_capture_root "$pass_name" "$capture_root"
}

write_battle_hashes() {
	local capture_root="$1"
	local destination="$2"
	local filename
	for filename in battle_1280x720.png battle_1600x900.png battle_1920x1080.png; do
		printf '%s %s\n' "$(sha256sum "$capture_root/$filename" | awk '{print $1}')" "$filename"
	done > "$destination"
}

commit_capture_directory() {
	local verified_root="$1"
	stage_dir="$(mktemp -d "$output_parent/.captures-stage.XXXXXX")"
	cp -a "$verified_root/." "$stage_dir/"
	validate_capture_root commit-candidate "$stage_dir"
	rollback_dir="$(mktemp -d "$output_parent/.captures-rollback.XXXXXX")"
	rmdir "$rollback_dir"
	commit_active=1
	if ! mv "$output_dir" "$rollback_dir"; then
		commit_active=0
		rollback_dir=""
		echo "Could not stage the previous capture directory for rollback." >&2
		return 1
	fi
	if ! mv "$stage_dir" "$output_dir"; then
		echo "Could not install the verified capture directory." >&2
		recover_capture_commit
		return 1
	fi
	stage_dir=""
	if ! rm -rf "$rollback_dir"; then
		echo "Could not finalize the capture directory transaction." >&2
		recover_capture_commit
		return 1
	fi
	rollback_dir=""
	commit_active=0
}

first_root="$work_root/pass-first"
second_root="$work_root/pass-second"
run_capture_pass first "$first_root"
write_battle_hashes "$first_root/captures" "$control_root/battle-first.sha256"
run_capture_pass second "$second_root"
write_battle_hashes "$second_root/captures" "$control_root/battle-second.sha256"
if ! cmp -s "$control_root/battle-first.sha256" "$control_root/battle-second.sha256"; then
	echo "Battle evidence changed across consecutive fixed-phase captures." >&2
	diff -u "$control_root/battle-first.sha256" "$control_root/battle-second.sha256" >&2 || true
	exit 1
fi

commit_capture_directory "$second_root/captures"
cat "$control_root/battle-second.sha256"
echo "CAPTURE_ART_V1_OK count=15 passes=2 battle_bytes=stable commit=directory-transaction sizes=1280x720,1600x900,1920x1080 pages=title,hive,swarm,map,battle"
