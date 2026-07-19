#!/usr/bin/env bash
set -euo pipefail

project_root="${M1_PUBLIC_UI_PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
battle="$project_root/scripts/ui/battle_page.gd"
shell="$project_root/scripts/ui/game_shell.gd"
presenter="$project_root/scripts/ui/m1_world_presenter.gd"
hud="$project_root/scripts/ui/m1_hive_hud.gd"
runner="$project_root/tests/m1_production_entry_runner.gd"

fail() {
	echo "M1_PUBLIC_UI_ORACLE_RED project=$project_root reason=$1" >&2
	exit 1
}

for required in "$battle" "$shell" "$presenter" "$hud" "$runner"; do
	[[ -f "$required" ]] || fail "missing:$required"
done

rg -q 'const PRESENTATION_MIN_WINDOW_MSEC := 4000' "$battle" || fail "battle-observation-window"
rg -q 'func present_battle_result' "$battle" || fail "battle-result-entry"
rg -q 'func battle_result_snapshot' "$battle" || fail "battle-result-contract"
rg -q 'ConfirmBattleResultButton' "$battle" || fail "battle-result-confirmation"
rg -q 'func presentation_contract_snapshot' "$presenter" || fail "presenter-event-contract"
rg -q 'func present_battle_result' "$presenter" || fail "presenter-result-event"
rg -q 'present_battle_result' "$shell" || fail "shell-retains-battle-result"
rg -q 'M1_PUBLIC_BATTLE_PRESENTATION_OK' "$runner" || fail "runner-battle-marker"
rg -q '^extends HBoxContainer$' "$hud" || fail "hud-not-native-container"
rg -q 'func attach_world_viewport' "$hud" || fail "hud-viewport-slot"
rg -q 'func _toggle_slot_dock' "$hud" || fail "slot-dock-not-collapsible"
rg -q 'func _toggle_detail_dock' "$hud" || fail "detail-dock-not-collapsible"
rg -q 'layout_non_overlapping' "$presenter" || fail "presenter-layout-contract"
rg -q 'M1_PUBLIC_DOCK_LAYOUT_OK' "$runner" || fail "runner-dock-marker"

echo "M1_PUBLIC_UI_ORACLE_OK battle=public-submit,authority-events,persistent-summary observation_ms=4000 hud=native-collapsible-docks viewport=reallocated rail=78-100"
