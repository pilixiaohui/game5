#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$project_root/scripts/timeout_gate.sh"

script_started_ms="$(date +%s%3N)"
production_phase() {
	local phase="$1"
	local edge="$2"
	local now_ms
	now_ms="$(date +%s%3N)"
	echo "M1_PRODUCTION_GATE phase=$phase edge=$edge total_ms=$((now_ms - script_started_ms))"
}

production_phase contracts start
"$project_root/scripts/verify_m1_oracle_contract.sh"
"$project_root/scripts/verify_m1_public_ui_oracle.sh"
"$project_root/scripts/verify_m1_world_architecture_contract.sh"
"$project_root/scripts/verify_m1_visual_scale_contract.sh"
production_phase contracts end

# Production-entry is a post-import gate. Refuse an unprepared source tree
# before creating scratch state or starting Godot; cold import is owned by the
# fresh-source/release-health orchestration.
"$project_root/scripts/verify_post_import_ready.sh"
production_phase import-ready instant

scratch_parent="${M1_PRODUCTION_SCRATCH_PARENT:-${TMPDIR:-/tmp}}"
test_root="$(mktemp -d "$scratch_parent/xenogenesis-m1-production.XXXXXX")"
cleanup_m1_production() {
	cleanup_hard_timeout_processes || true
	rm -rf "$test_root"
}
trap cleanup_m1_production EXIT
trap 'exit 143' TERM INT

M1_ASSET_LIFECYCLE_SCRATCH_PARENT="$test_root" \
	"$project_root/scripts/verify_m1_asset_lifecycle.sh"
production_phase asset-lifecycle end

cd "$project_root"
log="$test_root/production.log"
status=0
render_cache_root="${M1_RENDER_CACHE_ROOT:-$test_root/render-cache}"
mkdir -p "$render_cache_root/mesa"
production_phase runner start
run_with_hard_timeout "m1-production-entry" "${M1_PRODUCTION_TIMEOUT_SECONDS:-70}" "${M1_PRODUCTION_KILL_AFTER_SECONDS:-5}" \
	env \
		HOME="$test_root/home" \
		XDG_CONFIG_HOME="$test_root/config" \
		XDG_CACHE_HOME="$test_root/cache" \
		XDG_DATA_HOME="$test_root/data" \
		MESA_SHADER_CACHE_DIR="$render_cache_root/mesa" \
		LP_NUM_THREADS="${M1_RENDER_THREADS:-4}" \
		xvfb-run -a godot4 --audio-driver Dummy --single-window --disable-vsync --delta-smoothing disable --max-fps 60 --path . -s res://tests/m1_production_entry_runner.gd -- \
		"--capture-root=$test_root/captures" >"$log" 2>&1 || status=$?
cat "$log"
production_phase runner end
if [[ "$status" -ne 0 ]]; then
	exit "$status"
fi
if ! rg -q '^M1_PRODUCTION_ENTRY_OK assertions=355 captures=9 phases=operations,engagement,retreat ' "$log"; then
	echo "M1 production entry exited without its success marker." >&2
	exit 1
fi
if ! rg -q '^M1_PUBLIC_BATTLE_PRESENTATION_OK observation_ms=4000 events=contact,hit,hurt,death,retreat summary=deployed,returned,losses,reward,capture,next-node captures=3 authority=readonly$' "$log"; then
	echo "M1 production entry exited without its public battle presentation marker." >&2
	exit 1
fi
if ! rg -q '^M1_PUBLIC_DOCK_LAYOUT_OK resolutions=1280x720,1600x900,1920x1080 slots=12 input=mouse,keyboard viewport=reallocated rail=78-100 overlap=0$' "$log"; then
	echo "M1 production entry exited without its public dock layout marker." >&2
	exit 1
fi
for marker in \
	'M1_PRODUCTION_PHASE phase=startup edge=start ' \
	'M1_PRODUCTION_PHASE phase=operations-capture edge=end ' \
	'M1_PRODUCTION_PHASE phase=autosave edge=end ' \
	'M1_PRODUCTION_PHASE phase=exit-ready edge=instant ' \
	'M1_PRODUCTION_PHASE phase=teardown edge=end '; do
	if ! rg -Fq "$marker" "$log"; then
		echo "M1 production entry missing required phase marker: $marker" >&2
		exit 1
	fi
done
if [[ "$(find "$test_root/captures" -maxdepth 1 -type f -name 'm1-production-*.png' | wc -l)" -ne 9 ]]; then
	echo "M1 production entry did not produce exactly nine operations/engagement/retreat captures." >&2
	exit 1
fi
if [[ "$(find "$test_root/captures" -maxdepth 1 -type f -name 'm1-public-result-*.png' | wc -l)" -ne 3 ]]; then
	echo "M1 production entry did not produce exactly three public result captures." >&2
	exit 1
fi
if [[ -n "${M1_PRODUCTION_EVIDENCE_DIR:-}" ]]; then
	mkdir -p "$M1_PRODUCTION_EVIDENCE_DIR"
	cp "$test_root"/captures/*.png "$M1_PRODUCTION_EVIDENCE_DIR"/
fi
production_phase complete instant
echo "VERIFY_M1_PRODUCTION_ENTRY_OK assertions=355 captures=9 phases=operations,engagement,retreat resolutions=1280x720,1600x900,1920x1080 world=Node2D,Camera2D,PackedScenes save_order=post-battle-ctrl-s,post-battle-autosave,button,reload,retreat natural_capture=true authority=primary,backup-sha-size-ns-mtime scratch=clean-on-exit"
