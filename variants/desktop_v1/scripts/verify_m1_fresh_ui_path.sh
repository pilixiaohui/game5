#!/usr/bin/env bash
set -euo pipefail

project_root="${M1_FRESH_UI_PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$project_root/scripts/timeout_gate.sh"

script_started_ms="$(date +%s%3N)"
fresh_phase() {
	local phase="$1"
	local edge="$2"
	local now_ms
	now_ms="$(date +%s%3N)"
	echo "M1_FRESH_UI_GATE phase=$phase edge=$edge total_ms=$((now_ms - script_started_ms))"
}

fresh_phase import-ready start
"$project_root/scripts/verify_post_import_ready.sh"
fresh_phase import-ready end

runner="$project_root/tests/m1_fresh_ui_path_runner.gd"
if rg -n 'session\.state|session\.(new_game|build_room|set_unit_target|attack_node|advance_one_tick|advance_steps|set_paused)' "$runner"; then
	echo "M1_FRESH_UI_RED reason=runner-bypasses-public-ui" >&2
	exit 1
fi

scratch_parent="${M1_FRESH_UI_SCRATCH_PARENT:-${TMPDIR:-/tmp}}"
test_root="$(mktemp -d "$scratch_parent/xenogenesis-m1-fresh-ui.XXXXXX")"
cleanup_m1_fresh_ui() {
	cleanup_hard_timeout_processes || true
	rm -rf "$test_root"
}
trap cleanup_m1_fresh_ui EXIT
trap 'exit 143' TERM INT

log="$test_root/fresh-ui.log"
status=0
render_cache_root="${M1_RENDER_CACHE_ROOT:-$test_root/render-cache}"
mkdir -p "$render_cache_root/mesa"
fresh_phase runner start
run_with_hard_timeout "m1-fresh-ui" "${M1_FRESH_UI_TIMEOUT_SECONDS:-25}" "${M1_FRESH_UI_KILL_AFTER_SECONDS:-5}" \
	env \
		HOME="$test_root/home" \
		XDG_CONFIG_HOME="$test_root/config" \
		XDG_CACHE_HOME="$test_root/cache" \
		XDG_DATA_HOME="$test_root/data" \
		MESA_SHADER_CACHE_DIR="$render_cache_root/mesa" \
		LP_NUM_THREADS="${M1_RENDER_THREADS:-4}" \
		xvfb-run -a godot4 --audio-driver Dummy --single-window --disable-vsync --delta-smoothing disable --max-fps 60 --path "$project_root" -s res://tests/m1_fresh_ui_path_runner.gd -- \
		"--capture-root=$test_root/captures" >"$log" 2>&1 || status=$?
cat "$log"
fresh_phase runner end
if [[ "$status" -ne 0 ]]; then
	echo "M1_FRESH_UI_RED reason=runner-status status=$status" >&2
	exit "$status"
fi
if ! rg -q '^M1_FRESH_UI_OK assertions=[0-9]+ captures=3 path=new-game,slot,build,production,map,assault,battle,save ' "$log"; then
	echo "M1_FRESH_UI_RED reason=success-marker-missing" >&2
	exit 1
fi
for marker in \
	'M1_FRESH_UI_PHASE phase=startup edge=start ' \
	'M1_FRESH_UI_PHASE phase=build-capture edge=end ' \
	'M1_FRESH_UI_PHASE phase=first-production edge=instant ' \
	'M1_FRESH_UI_PHASE phase=exit-ready edge=instant ' \
	'M1_FRESH_UI_PHASE phase=teardown edge=end '; do
	if ! rg -Fq "$marker" "$log"; then
		echo "M1_FRESH_UI_RED reason=phase-marker-missing marker=$marker" >&2
		exit 1
	fi
done
if [[ "$(find "$test_root/captures" -maxdepth 1 -type f -name 'm1-fresh-*.png' | wc -l)" -ne 3 ]]; then
	echo "M1_FRESH_UI_RED reason=capture-count" >&2
	exit 1
fi
if [[ -n "${M1_FRESH_UI_EVIDENCE_DIR:-}" ]]; then
	mkdir -p "$M1_FRESH_UI_EVIDENCE_DIR"
	cp "$test_root"/captures/m1-fresh-*.png "$M1_FRESH_UI_EVIDENCE_DIR"/
fi
fresh_phase complete instant
echo "VERIFY_M1_FRESH_UI_OK captures=3 resolutions=1280x720,1600x900,1920x1080 input=mouse,focus path=new-game,slot,build,production,map,assault,battle,save authority=primary,backup scratch=clean-on-exit"
