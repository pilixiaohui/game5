#!/usr/bin/env bash
set -euo pipefail

project_root="${M1_ARCH_PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
scene="$project_root/scenes/art_m1/m1_hive_battle_world_slice.tscn"
world="$project_root/scripts/art_m1/m1_world_slice.gd"
presenter="$project_root/scripts/ui/m1_world_presenter.gd"
hud="$project_root/scripts/ui/m1_hive_hud.gd"

fail() {
	echo "M1_WORLD_ARCHITECTURE_RED project=$project_root reason=$1" >&2
	exit 1
}

for required in "$scene" "$world" "$presenter" "$hud" \
	"$project_root/scenes/art_m1/m1_room_entity.tscn" \
	"$project_root/scenes/art_m1/m1_unit_entity.tscn" \
	"$project_root/scenes/art_m1/m1_vfx_entity.tscn"; do
	[[ -f "$required" ]] || fail "missing:$required"
done

rg -q '\[node name="WorldRoot" type="Node2D"\]' "$scene" || fail "world-root-not-node2d"
rg -q '\[node name="Camera2D" type="Camera2D" parent="\."\]' "$scene" || fail "camera2d-missing"
[[ "$(rg -c 'type="Sprite2D" parent="Environment"' "$scene")" -eq 3 ]] || fail "environment-sprite-count"
if rg -n 'func _draw\(|queue_redraw\(|draw_texture|draw_line|draw_rect' "$world"; then
	fail "production-world-immediate-draw"
fi
rg -q 'var view_model: M1WorldViewModel' "$world" || fail "typed-view-model-missing"
rg -q 'SubViewportContainer' "$presenter" || fail "subviewport-host-missing"
rg -q 'rail_panel.anchor_top = 0.78' "$presenter" || fail "rail78-layout-missing"
rg -q 'signal command_requested' "$hud" || fail "native-hud-command-boundary-missing"
if rg -n 'GameSession|/root/GameSession|session\.' "$hud"; then
	fail "native-hud-direct-session-access"
fi
for entity in room unit vfx; do
	rg -q '\[node name="M1.*Entity" type="Node2D"\]' "$project_root/scenes/art_m1/m1_${entity}_entity.tscn" || fail "${entity}-scene-not-node2d"
	rg -q '\[node name="Sprite2D" type="Sprite2D" parent="\."\]' "$project_root/scenes/art_m1/m1_${entity}_entity.tscn" || fail "${entity}-sprite-missing"
done
rg -q 'create_tween\(\)' "$project_root/scripts/art_m1/m1_vfx_entity.gd" || fail "bounded-vfx-tween-missing"
if find "$project_root/assets/art_m1" "$project_root/artifacts/art_m1" "$project_root/docs/art_m1_sources" -type l -print -quit | rg -q .; then
	fail "asset-contract-symlink"
fi

echo "M1_WORLD_ARCHITECTURE_OK root=Node2D camera=Camera2D environment=3xSprite2D entities=room,unit,vfx-packed control=hud,rail,overlay redraw=none vm=typed-read-only rail=78-100"
