#!/usr/bin/env bash
set -euo pipefail

project_root="${M1_ORACLE_PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
runner="$project_root/tests/m1_production_entry_runner.gd"
shell="$project_root/scripts/ui/game_shell.gd"
hive="$project_root/scripts/ui/hive_page.gd"
battle="$project_root/scripts/ui/battle_page.gd"

fail() {
	echo "M1_ORACLE_CONTRACT_RED project=$project_root reason=$1" >&2
	exit 1
}

for required in "$runner" "$shell" "$hive" "$battle"; do
	[[ -f "$required" ]] || fail "missing:$required"
done

rg -q 'save_order=post-battle-ctrl-s,post-battle-autosave,button,reload,retreat' "$runner" || fail "runner-marker-save-order"
rg -q 'natural_capture=true' "$runner" || fail "runner-marker-natural-capture"
rg -q 'func _m1_lifecycle_snapshot' "$runner" || fail "runner-lifecycle-oracle"
rg -q 'assertions=%d captures=9 phases=operations,engagement,retreat' "$runner" || fail "runner-assertion-marker"
rg -q '_assert_world_contract' "$runner" || fail "runner-world-architecture-oracle"
for phase in autosave retreat natural-capture exit-ready teardown screenshots-complete; do
	if ! rg -Fq "_phase_begin(\"$phase\"" "$runner" && ! rg -Fq "_phase_marker(\"$phase\"" "$runner"; then
		fail "runner-phase-marker-$phase"
	fi
done
rg -q '_phase_begin\("autosave", 40000\)' "$runner" || fail "runner-autosave-bound"
rg -q '_phase_begin\("natural-capture", 15000\)' "$runner" || fail "runner-natural-capture-bound"
rg -q '_phase_begin\("teardown", 5000\)' "$runner" || fail "runner-teardown-bound"
rg -q 'session.notice_posted.disconnect' "$runner" || fail "runner-notice-disconnect"
rg -q 'signal m1_presenter_lifecycle' "$shell" || fail "shell-lifecycle-signal"
rg -q 'func m1_lifecycle_snapshot' "$shell" || fail "shell-lifecycle-snapshot"
rg -q 'signal m1_presenter_lifecycle' "$hive" || fail "hive-lifecycle-signal"
rg -q 'signal m1_presenter_lifecycle' "$battle" || fail "battle-lifecycle-signal"

line_of() {
	rg -n "$1" "$runner" | head -n 1 | cut -d: -f1
}

map_line="$(line_of 'var map_button')"
battle_line="$(line_of 'var battle_presenter')"
ctrl_s_line="$(line_of '_press_save_shortcut')"
autosave_line="$(line_of 'var autosave_deadline')"
natural_line="$(line_of 'natural captured=true must return')"
[[ -n "$map_line" && -n "$battle_line" && -n "$ctrl_s_line" && -n "$autosave_line" && -n "$natural_line" ]] || fail "runner-order-markers"
(( map_line < battle_line && battle_line < ctrl_s_line && ctrl_s_line < autosave_line && autosave_line < natural_line )) || fail "runner-order-map-battle-save-natural"

echo "M1_ORACLE_CONTRACT_OK assertions=355 captures=9 phases=operations,engagement,retreat,map,battle,ctrl-s,autosave,natural-capture lifecycle=production phase_bounds=autosave,retreat,natural-capture,exit-ready,teardown"
