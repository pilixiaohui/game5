#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$project_root/scripts/timeout_gate.sh"

scratch_parent="${ART_V1_SCRATCH_PARENT:-${TMPDIR:-/tmp}}"
control_root="$(mktemp -d "$scratch_parent/xenogenesis-art-v1-control.XXXXXX")"
work_root="$(mktemp -d "$scratch_parent/xenogenesis-art-v1-work.XXXXXX")"

cleanup_art_v1_capture() {
	cleanup_hard_timeout_processes || true
	rm -rf "$control_root" "$work_root"
}
trap cleanup_art_v1_capture EXIT
trap 'exit 143' TERM INT

output_dir="$project_root/artifacts/art_v1/captures"
mkdir -p "$output_dir" "$work_root/tmp"
find "$output_dir" -maxdepth 1 -type f -name '*.png' -delete

godot_bin="${ART_V1_GODOT_BIN:-godot4}"
timeout_seconds="${ART_V1_TIMEOUT_SECONDS:-120}"
kill_after_seconds="${ART_V1_KILL_AFTER_SECONDS:-5}"
run_capture_pass() {
	local pass_name="$1"
	local log_path="$control_root/art-v1-capture-$pass_name.log"
	local command=(
		env TMPDIR="$work_root/tmp"
		xvfb-run -a env
		HOME="$work_root/home-$pass_name"
		XDG_CONFIG_HOME="$work_root/config-$pass_name"
		XDG_CACHE_HOME="$work_root/cache-$pass_name"
		XDG_DATA_HOME="$work_root/data-$pass_name"
		"$godot_bin" --audio-driver Dummy --path "$project_root"
		-s res://tests/art_v1_capture_runner.gd -- --capture-art-v1-child
	)
	local status=0
	run_with_hard_timeout "art-v1-capture-$pass_name" "$timeout_seconds" "$kill_after_seconds" "${command[@]}" >"$log_path" 2>&1 || status=$?
	cat "$log_path"
	if [[ "$status" -ne 0 ]]; then
		return "$status"
	fi
}

run_capture_pass first

count="$(find "$output_dir" -maxdepth 1 -type f -name '*.png' | wc -l)"
if [[ "$count" -ne 15 ]]; then
	echo "Art v1 capture produced $count images instead of 15." >&2
	exit 1
fi

sha256sum "$output_dir"/battle_*.png | sort >"$control_root/battle-first.sha256"
run_capture_pass second
sha256sum "$output_dir"/battle_*.png | sort >"$control_root/battle-second.sha256"
if ! cmp -s "$control_root/battle-first.sha256" "$control_root/battle-second.sha256"; then
	echo "Battle evidence changed across consecutive fixed-phase captures." >&2
	diff -u "$control_root/battle-first.sha256" "$control_root/battle-second.sha256" >&2 || true
	exit 1
fi
cat "$control_root/battle-second.sha256"

echo "CAPTURE_ART_V1_OK count=15 passes=2 battle_bytes=stable sizes=1280x720,1600x900,1920x1080 pages=title,hive,swarm,map,battle"
