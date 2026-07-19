#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output_dir="$project_root/artifacts/art_m1/captures"
mkdir -p "$output_dir"
find "$output_dir" -maxdepth 1 -type f -name '*.png' -delete

godot_bin="${M1_GODOT_BIN:-godot4}"
timeout_seconds="${M1_CAPTURE_TIMEOUT_SECONDS:-120}"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/xenogenesis-m1-capture.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT

command=(
	env HOME="$scratch/home" XDG_CONFIG_HOME="$scratch/config" XDG_CACHE_HOME="$scratch/cache" XDG_DATA_HOME="$scratch/data"
	xvfb-run -a
	"$godot_bin" --audio-driver Dummy --path "$project_root"
	-s res://tests/m1_world_slice_capture.gd -- --m1-capture-child
)

timeout --signal=TERM --kill-after=5s "$timeout_seconds" "${command[@]}"

count="$(find "$output_dir" -maxdepth 1 -type f -name '*.png' | wc -l)"
if [[ "$count" -ne 9 ]]; then
	echo "M1 capture produced $count images instead of 9." >&2
	exit 1
fi
echo "M1_CAPTURE_SCRIPT_OK count=9 sizes=1280x720,1600x900,1920x1080 phases=operations,engagement,retreat"
