#!/usr/bin/env bash
set -euo pipefail

project_root="${M1_VISUAL_PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
world="$project_root/scripts/art_m1/m1_world_slice.gd"
unit="$project_root/scripts/art_m1/m1_unit_entity.gd"
vfx="$project_root/scripts/art_m1/m1_vfx_entity.gd"
runner="$project_root/tests/m1_production_entry_runner.gd"

fail() {
	echo "M1_VISUAL_SCALE_RED project=$project_root reason=$1" >&2
	exit 1
}

for required in "$world" "$unit" "$vfx" "$runner"; do
	[[ -f "$required" ]] || fail "missing:$required"
done

rg -q 'func visual_landmark_contract\(\)' "$world" || fail "world-landmark-contract"
rg -q 'visual_landmarks.*visual_landmark_contract' "$world" || fail "world-landmark-projection"
rg -q 'Vector2\(216, 216\)' "$world" || fail "biter-scale"
rg -q 'Vector2\(200, 200\)' "$world" || fail "enemy-scale"
rg -q 'Vector2\(194, 194\)' "$world" || fail "contact-scale"
rg -q 'Vector2\(270, 270\).*static_capture, -1' "$world" || fail "retreat-scale-direction"
rg -q 'set_facing_left\(phase == "retreat"\)' "$world" || fail "biter-retreat-direction"
rg -q 'if image.get_pixel\(x, y\).a >= 0.08' "$unit" || fail "unit-alpha-bbox"
rg -q 'if image.get_pixel\(x, y\).a >= 0.08' "$vfx" || fail "vfx-alpha-bbox"
rg -q 'VISUAL_MIN_UNIT_BBOX_PX := 48.0' "$runner" || fail "unit-screen-bbox-threshold"
rg -q 'VISUAL_MIN_VFX_BBOX_PX := 46.0' "$runner" || fail "vfx-screen-bbox-threshold"
rg -q 'VISUAL_MIN_LOCAL_CONTRAST := 0.04' "$runner" || fail "local-contrast-threshold"
rg -q 'M1_VISUAL_SCALE_OK phase=' "$runner" || fail "production-capture-marker"

echo "M1_VISUAL_SCALE_CONTRACT_OK viewport=1280x720 alpha=0.08 unit_min_px=48 vfx_min_px=46 local_contrast=0.04 direction=engagement-right,retreat-left capture=production"
