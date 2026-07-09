extends Control

signal command_requested(action: String)

const BattleDirectorScript := preload("res://scripts/battle/BattleDirector.gd")

const BG_COLOR := Color(0.045, 0.055, 0.065)
const LANE_COLOR := Color(0.12, 0.14, 0.16)
const HIVE_COLOR := Color(0.16, 0.48, 0.30)
const ENEMY_COLOR := Color(0.55, 0.17, 0.16)
const FRONT_ADVANCE := Color(0.25, 0.85, 0.42)
const FRONT_STALLED := Color(0.95, 0.35, 0.22)
const FRONT_IDLE := Color(0.72, 0.78, 0.62)
const ZERGLING_COLOR := Color(0.44, 0.95, 0.58)
const HYDRALISK_COLOR := Color(0.34, 0.74, 1.0)

var _snapshot: Dictionary = {}
var _pulse: float = 0.0
var _retreat_hold_remaining: float = 0.0
var _held_retreat_return: int = 0
var _held_retreat_field_before: int = 0
var _held_preserved_loss: int = 0
var _battle_director

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(0.0, 304.0)
	_battle_director = BattleDirectorScript.new()
	_battle_director.name = "BattleDirector"
	add_child(_battle_director)
	set_process(true)

func set_snapshot(snapshot: Dictionary) -> void:
	_snapshot = snapshot
	_sync_presentation_layer()
	if String(snapshot.get("mode", "")) == "complete":
		_retreat_hold_remaining = 0.0
		_held_retreat_return = 0
		_held_retreat_field_before = 0
		_held_preserved_loss = 0
		queue_redraw()
		return
	var current_return: int = maxi(int(snapshot.get("returned", 0)), int(snapshot.get("retreat_value", 0)))
	var current_field_before: int = int(snapshot.get("retreat_field_before", 0))
	if current_return > 0 and current_field_before > 0:
		_retreat_hold_remaining = 3.0
		_held_retreat_return = current_return
		_held_retreat_field_before = current_field_before
		_held_preserved_loss = int(snapshot.get("preserved_loss_estimate", 0))
	queue_redraw()

func _process(delta: float) -> void:
	_pulse = fmod(_pulse + delta * 1.6, 1.0)
	if _retreat_hold_remaining > 0.0:
		_retreat_hold_remaining = maxf(0.0, _retreat_hold_remaining - delta)
		if _retreat_hold_remaining <= 0.0:
			_held_retreat_return = 0
			_held_retreat_field_before = 0
			_held_preserved_loss = 0
	queue_redraw()

func presentation_active_count() -> int:
	if _battle_director == null:
		return 0
	return _battle_director.active_count()

func presentation_stats() -> Dictionary:
	if _battle_director == null:
		return {}
	return _battle_director.presentation_stats()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			if String(_snapshot.get("mode", "")) == "complete" and String(_snapshot.get("next_region_id", "")) != "":
				command_requested.emit("next_region")
				accept_event()
				return
			var third: float = size.x / 3.0
			if mouse_event.position.x < third:
				command_requested.emit("prepare")
			elif mouse_event.position.x < third * 2.0:
				command_requested.emit("assault")
			else:
				command_requested.emit("retreat")
			accept_event()

func _draw() -> void:
	var bounds := Rect2(Vector2.ZERO, size)
	draw_rect(bounds, BG_COLOR, true)
	draw_rect(bounds, Color(0.25, 0.33, 0.38, 0.7), false, 2.0)

	var font: Font = get_theme_default_font()
	var font_size: int = 13
	var region_name: String = String(_snapshot.get("region_name", "未知战线"))
	var mode: String = String(_snapshot.get("mode", "idle"))
	var progress: float = clampf(float(_snapshot.get("progress", 0.0)), 0.0, 100.0)
	var power: float = float(_snapshot.get("power", 0.0))
	var pressure: float = float(_snapshot.get("pressure", 0.0))
	var reinforced: int = int(_snapshot.get("reinforced", 0))
	var lost: int = int(_snapshot.get("lost", 0))
	var returned: int = int(_snapshot.get("returned", 0))
	var loss_reason: String = String(_snapshot.get("loss_reason", ""))
	var front_motion: String = String(_snapshot.get("front_motion", "none"))
	var progress_gain: float = float(_snapshot.get("progress_gain", 0.0))
	var projection_unit_name: String = String(_snapshot.get("projection_unit_name", "单位"))
	var prepared_reserve: int = int(_snapshot.get("prepared_reserve", 0))
	var needed_reserve: int = int(_snapshot.get("needed_reserve", 0))
	var projection_needed: int = int(_snapshot.get("projection_needed_reserve", 0))
	if needed_reserve <= 0:
		needed_reserve = projection_needed
	var cause: String = String(_snapshot.get("cause", ""))
	var base_pressure: float = float(_snapshot.get("base_pressure", pressure))
	var effective_pressure: float = float(_snapshot.get("effective_pressure", pressure))
	var support_bonus: float = float(_snapshot.get("support_bonus", 0.0))
	var plugin_bonus: float = float(_snapshot.get("plugin_bonus", 0.0))
	var baseline_needed_reserve: int = int(_snapshot.get("baseline_needed_reserve", needed_reserve))
	var reserve_shortfall: int = int(_snapshot.get("reserve_shortfall", 0))
	var hatch_fill_count: int = int(_snapshot.get("hatch_fill_count", 0))
	var hatch_missing_text: String = String(_snapshot.get("hatch_missing_text", ""))
	var pressure_drop: float = float(_snapshot.get("pressure_drop", 0.0))
	var loss_rate: float = float(_snapshot.get("loss_rate", 0.0))
	var baseline_loss_rate: float = float(_snapshot.get("baseline_loss_rate", 0.0))
	var loss_reduction: float = float(_snapshot.get("loss_reduction", 0.0))
	var loss_saved_estimate: int = int(_snapshot.get("loss_saved_estimate", 0))
	var protected_estimate: int = int(_snapshot.get("protected_estimate", 0))
	var acid_preview_loss_saved: int = int(_snapshot.get("acid_preview_loss_saved", 0))
	var acid_preview_protected: int = int(_snapshot.get("acid_preview_protected", 0))
	var retreat_value: int = int(_snapshot.get("retreat_value", 0))
	var retreat_field_before: int = int(_snapshot.get("retreat_field_before", 0))
	var preserved_loss_estimate: int = int(_snapshot.get("preserved_loss_estimate", 0))
	var retreat_display_value: int = _retreat_badge_visible_return(returned, retreat_value)
	var retreat_display_field: int = retreat_field_before if retreat_display_value == maxi(returned, retreat_value) else _held_retreat_field_before
	var retreat_display_preserved: int = preserved_loss_estimate if retreat_display_value == maxi(returned, retreat_value) else _held_preserved_loss
	var next_target: float = float(_snapshot.get("next_target", 4.0))
	var prestige_gain: int = int(_snapshot.get("prestige_gain", 0))
	var prestige_ready: bool = bool(_snapshot.get("prestige_ready", false))
	mode = _display_mode(mode, prepared_reserve, needed_reserve, reserve_shortfall)

	draw_string(font, Vector2(18.0, 26.0), "%s  %.1f%%" % [region_name, progress], HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size + 2, Color(0.90, 0.96, 0.92))
	draw_string(font, Vector2(18.0, 47.0), _mode_text(mode, power, pressure, returned, prepared_reserve, needed_reserve, projection_unit_name), HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, _front_color(mode))
	var command_hint: String = "点击切换下一防线" if mode == "complete" and String(_snapshot.get("next_region_id", "")) != "" else "左蓄兵  中强攻  右撤离"
	draw_string(font, Vector2(maxf(184.0, size.x - 182.0), 26.0), command_hint, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, Color(0.62, 0.78, 0.82))

	var lane := _battle_lane_rect()
	draw_rect(lane, LANE_COLOR, true)
	var front_x: float = lane.position.x + lane.size.x * progress / 100.0
	var hive_rect := Rect2(lane.position, Vector2(max(8.0, front_x - lane.position.x), lane.size.y))
	var enemy_rect := Rect2(Vector2(front_x, lane.position.y), Vector2(max(8.0, lane.end.x - front_x), lane.size.y))
	draw_rect(hive_rect, Color(HIVE_COLOR.r, HIVE_COLOR.g, HIVE_COLOR.b, 0.48), true)
	draw_rect(enemy_rect, Color(ENEMY_COLOR.r, ENEMY_COLOR.g, ENEMY_COLOR.b, 0.38), true)
	draw_line(Vector2(front_x, lane.position.y - 8.0), Vector2(front_x, lane.end.y + 8.0), _front_color(mode), 4.0)
	if mode == "complete":
		_draw_completion_state(font, lane)
		var complete_meter_y: float = lane.end.y + 20.0
		draw_rect(Rect2(lane.position.x, complete_meter_y, lane.size.x, 8.0), Color(0.10, 0.12, 0.13), true)
		draw_rect(Rect2(lane.position.x, complete_meter_y, lane.size.x, 8.0), _front_color(mode), true)
		draw_string(font, Vector2(lane.position.x, complete_meter_y + 34.0), _completion_status_text(), HORIZONTAL_ALIGNMENT_LEFT, lane.size.x, font_size, Color(0.86, 0.92, 0.78))
		return

	_draw_enemy_line(lane, pressure, mode)
	_draw_pressure_meter(lane, base_pressure, effective_pressure, pressure_drop, mode)
	_draw_wave_meter(lane, prepared_reserve, needed_reserve, baseline_needed_reserve, reserve_shortfall, hatch_fill_count, mode)
	_draw_support_icons(lane, support_bonus, plugin_bonus, prestige_ready, baseline_needed_reserve, needed_reserve, pressure_drop, loss_reduction)
	_draw_units(lane, front_x, front_motion, mode, prepared_reserve)
	_draw_event_feedback(lane, front_x, reinforced, lost, returned, mode, front_motion, retreat_display_value, retreat_display_field, retreat_display_preserved)
	_draw_decision_badges(font, lane, projection_unit_name, prepared_reserve, reserve_shortfall, hatch_fill_count, hatch_missing_text, baseline_needed_reserve, needed_reserve, pressure_drop, plugin_bonus, loss_saved_estimate, protected_estimate, acid_preview_loss_saved, acid_preview_protected, retreat_display_value, retreat_display_field)

	var meter_y: float = lane.end.y + 20.0
	draw_rect(Rect2(lane.position.x, meter_y, lane.size.x, 8.0), Color(0.10, 0.12, 0.13), true)
	draw_rect(Rect2(lane.position.x, meter_y, lane.size.x * progress / 100.0, 8.0), _front_color(mode), true)
	_draw_target_marker(font, lane, meter_y, next_target, prestige_gain, prestige_ready)

	var unit_readout_text: String = String(_snapshot.get("unit_readout_text", ""))
	var z_field: int = int(_snapshot.get("zergling_field", 0))
	var h_field: int = int(_snapshot.get("hydralisk_field", 0))
	var z_reserve: int = int(_snapshot.get("zergling_reserve", 0))
	var h_reserve: int = int(_snapshot.get("hydralisk_reserve", 0))
	var plugin_name: String = String(_snapshot.get("plugin_name", ""))
	if unit_readout_text == "":
		unit_readout_text = "场上 跳虫 %d / 刺蛇 %d    储备 %d / %d" % [z_field, h_field, z_reserve, h_reserve]
	draw_string(font, Vector2(lane.position.x, meter_y + 38.0), unit_readout_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, Color(0.82, 0.90, 0.86))
	var event_text: String = _event_text(reinforced, lost, returned, loss_reason, progress_gain, plugin_name, prepared_reserve, needed_reserve, cause, support_bonus, plugin_bonus, effective_pressure, reserve_shortfall, hatch_fill_count, pressure_drop, loss_rate, baseline_loss_rate, loss_reduction, retreat_display_value, loss_saved_estimate, protected_estimate)
	draw_string(font, Vector2(lane.position.x, meter_y + 60.0), event_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, Color(0.78, 0.84, 0.86))

func _draw_enemy_line(lane: Rect2, pressure: float, mode: String) -> void:
	var count: int = clampi(int(ceil(pressure / 5.0)), 3, 9)
	for i in range(count):
		var t: float = float(i) / max(1.0, float(count - 1))
		var pos := Vector2(lerpf(lane.end.x - 18.0, lane.end.x - lane.size.x * 0.34, t), lane.position.y + 18.0 + float(i % 3) * 22.0)
		var block := Rect2(pos - Vector2(7.0, 7.0), Vector2(14.0, 14.0))
		var alpha: float = 0.24 if mode == "idle" or mode == "retreat" else 1.0
		draw_rect(block, Color(ENEMY_COLOR.r, ENEMY_COLOR.g, ENEMY_COLOR.b, alpha), true)
		draw_rect(block, Color(1.0, 0.78, 0.58, alpha), false, 1.0)

func _draw_pressure_meter(lane: Rect2, base_pressure: float, effective_pressure: float, pressure_drop: float, mode: String) -> void:
	var meter := Rect2(lane.end.x - 84.0, lane.position.y - 18.0, 66.0, 8.0)
	draw_rect(meter, Color(0.11, 0.08, 0.08), true)
	var base_ratio: float = clampf(base_pressure / 42.0, 0.0, 1.0)
	draw_rect(Rect2(meter.position, Vector2(meter.size.x * base_ratio, meter.size.y)), Color(0.30, 0.11, 0.10), true)
	var pressure_ratio: float = clampf(effective_pressure / 42.0, 0.0, 1.0)
	var color: Color = Color(0.75, 0.18, 0.14) if mode != "retreat" and mode != "idle" else Color(0.34, 0.25, 0.24)
	draw_rect(Rect2(meter.position, Vector2(meter.size.x * pressure_ratio, meter.size.y)), color, true)
	if effective_pressure < base_pressure:
		var cut_x: float = meter.position.x + meter.size.x * pressure_ratio
		draw_line(Vector2(cut_x, meter.position.y - 3.0), Vector2(meter.end.x, meter.end.y + 3.0), Color(0.42, 0.90, 0.78, 0.9), 2.0)
		draw_line(Vector2(cut_x + 8.0, meter.position.y - 3.0), Vector2(meter.end.x, meter.position.y - 3.0), Color(0.42, 0.90, 0.78, 0.45 + _pulse * 0.35), 2.0)
	if pressure_drop > 0.01:
		var pulse_x: float = lerpf(meter.end.x - 4.0, meter.position.x + meter.size.x * pressure_ratio + 4.0, _pulse)
		draw_circle(Vector2(pulse_x, meter.position.y + meter.size.y * 0.5), 3.0, Color(0.42, 0.90, 0.78, 0.85))

func _draw_wave_meter(lane: Rect2, prepared_reserve: int, needed_reserve: int, baseline_needed_reserve: int, reserve_shortfall: int, hatch_fill_count: int, mode: String) -> void:
	if needed_reserve <= 0:
		return
	var meter := Rect2(lane.position.x + 14.0, lane.position.y - 18.0, 118.0, 10.0)
	draw_rect(meter, Color(0.08, 0.11, 0.11), true)
	var ratio: float = clampf(float(prepared_reserve) / float(maxi(1, needed_reserve)), 0.0, 1.0)
	var color: Color = Color(0.38, 0.78, 0.92) if mode != "understrength" else Color(0.95, 0.58, 0.22)
	draw_rect(Rect2(meter.position, Vector2(meter.size.x * ratio, meter.size.y)), color, true)
	var baseline_slots: int = clampi(maxi(baseline_needed_reserve, needed_reserve), 1, 8)
	if baseline_slots > needed_reserve:
		var baseline_gap: float = meter.size.x / float(baseline_slots)
		for i in range(baseline_slots):
			var ghost_center := Vector2(meter.position.x + baseline_gap * (float(i) + 0.5), meter.position.y - 8.0)
			var ghost_color := Color(0.70, 0.52, 0.32, 0.45) if i >= needed_reserve else Color(0.42, 0.90, 0.78, 0.45)
			draw_circle(ghost_center, 3.0, ghost_color)
	var slots: int = clampi(needed_reserve, 1, 8)
	var slot_gap: float = meter.size.x / float(slots)
	for i in range(slots):
		var center := Vector2(meter.position.x + slot_gap * (float(i) + 0.5), meter.position.y + meter.size.y * 0.5)
		var filled: bool = i < prepared_reserve
		var slot_color: Color = color if filled else Color(0.42, 0.30, 0.24) if mode == "understrength" else Color(0.22, 0.30, 0.32)
		draw_circle(center, 4.0, slot_color)
		draw_circle(center, 4.2, Color(1.0, 0.92, 0.62, 0.7), false, 1.0)
		if not filled and i < prepared_reserve + hatch_fill_count:
			var lift: float = 2.0 + sin(_pulse * TAU + float(i)) * 2.0
			var plus_center := center + Vector2(0.0, 12.0 + lift)
			draw_line(plus_center + Vector2(-4.0, 0.0), plus_center + Vector2(4.0, 0.0), Color(0.40, 1.0, 0.64, 0.95), 2.0)
			draw_line(plus_center + Vector2(0.0, -4.0), plus_center + Vector2(0.0, 4.0), Color(0.40, 1.0, 0.64, 0.95), 2.0)
	if prepared_reserve < needed_reserve:
		var missing_slots: int = clampi(reserve_shortfall, 1, slots)
		for i in range(missing_slots):
			var slot_index: int = clampi(prepared_reserve + i, 0, slots - 1)
			var miss_center := Vector2(meter.position.x + slot_gap * (float(slot_index) + 0.5), meter.position.y + meter.size.y * 0.5)
			var miss_color := Color(1.0, 0.42, 0.24, 0.75 + _pulse * 0.2)
			draw_line(miss_center + Vector2(-5.0, -5.0), miss_center + Vector2(5.0, 5.0), miss_color, 2.0)
			draw_line(miss_center + Vector2(-5.0, 5.0), miss_center + Vector2(5.0, -5.0), miss_color, 2.0)

func _draw_support_icons(lane: Rect2, support_bonus: float, plugin_bonus: float, prestige_ready: bool, baseline_needed_reserve: int, needed_reserve: int, pressure_drop: float, loss_reduction: float) -> void:
	var start := Vector2(lane.position.x + 18.0, lane.position.y + 14.0)
	if support_bonus > 0.001:
		draw_circle(start, 7.0, Color(0.38, 0.90, 0.62, 0.92))
		draw_line(start + Vector2(-4.0, 1.0), start + Vector2(0.0, -5.0), Color(0.05, 0.16, 0.09), 2.0)
		draw_line(start + Vector2(0.0, -5.0), start + Vector2(5.0, 4.0), Color(0.05, 0.16, 0.09), 2.0)
	if plugin_bonus > 0.001:
		var p := start + Vector2(20.0, 0.0)
		var points: PackedVector2Array = PackedVector2Array([p + Vector2(0.0, -8.0), p + Vector2(8.0, 6.0), p + Vector2(-8.0, 6.0)])
		draw_colored_polygon(points, Color(0.88, 0.72, 0.28, 0.94))
		if loss_reduction > 0.001:
			draw_arc(p + Vector2(0.0, 1.0), 11.0, PI * 0.15, PI * 0.85, 12, Color(0.50, 0.82, 1.0, 0.95), 2.0)
	if prestige_ready:
		var r := start + Vector2(42.0, 0.0)
		draw_arc(r, 8.0, 0.1, TAU - 0.6, 18, Color(0.78, 0.58, 1.0, 0.95), 2.0)
		draw_line(r + Vector2(6.0, -4.0), r + Vector2(10.0, -8.0), Color(0.78, 0.58, 1.0, 0.95), 2.0)
	if baseline_needed_reserve > needed_reserve and needed_reserve > 0:
		var t := start + Vector2(64.0, 0.0)
		for i in range(clampi(baseline_needed_reserve, 1, 5)):
			var c := t + Vector2(float(i) * 7.0, 0.0)
			var active_color := Color(0.42, 0.90, 0.78, 0.95) if i < needed_reserve else Color(0.95, 0.34, 0.22, 0.45)
			draw_circle(c, 2.5, active_color)
	if pressure_drop > 0.01:
		var drop_origin := lane.end - Vector2(44.0, 82.0)
		draw_line(drop_origin + Vector2(0.0, -7.0), drop_origin + Vector2(0.0, 7.0), Color(0.42, 0.90, 0.78, 0.9), 2.0)
		draw_line(drop_origin + Vector2(0.0, 7.0), drop_origin + Vector2(-5.0, 2.0), Color(0.42, 0.90, 0.78, 0.9), 2.0)
		draw_line(drop_origin + Vector2(0.0, 7.0), drop_origin + Vector2(5.0, 2.0), Color(0.42, 0.90, 0.78, 0.9), 2.0)

func _draw_target_marker(font: Font, lane: Rect2, meter_y: float, next_target: float, prestige_gain: int, prestige_ready: bool) -> void:
	var target: float = clampf(next_target, 0.0, 100.0)
	var x: float = lane.position.x + lane.size.x * target / 100.0
	draw_line(Vector2(x, meter_y - 13.0), Vector2(x, meter_y - 2.0), Color(1.0, 0.86, 0.38, 0.95), 2.0)
	var label: String = "重置+%d" % prestige_gain if prestige_ready else "%.0f%%目标" % target
	draw_string(font, Vector2(minf(x + 4.0, lane.end.x - 76.0), meter_y - 18.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 11, Color(1.0, 0.88, 0.52))

func _target_marker_line_bottom(meter_y: float) -> float:
	return meter_y - 2.0

func _target_marker_label_y(meter_y: float) -> float:
	return meter_y - 18.0

func _bottom_readout_y(meter_y: float) -> float:
	return meter_y + 38.0

func _draw_completion_state(font: Font, lane: Rect2) -> void:
	draw_rect(lane, Color(0.18, 0.33, 0.24, 0.62), true)
	var clear_x: float = lane.end.x - 18.0
	draw_line(Vector2(lane.position.x + 16.0, lane.position.y + 22.0), Vector2(clear_x, lane.position.y + 22.0), Color(0.78, 0.90, 0.35, 0.95), 4.0)
	draw_line(Vector2(clear_x - 10.0, lane.position.y + 12.0), Vector2(clear_x, lane.position.y + 22.0), Color(0.78, 0.90, 0.35, 0.95), 4.0)
	draw_line(Vector2(clear_x - 10.0, lane.position.y + 32.0), Vector2(clear_x, lane.position.y + 22.0), Color(0.78, 0.90, 0.35, 0.95), 4.0)
	var next_name: String = String(_snapshot.get("next_region_name", ""))
	draw_string(font, lane.position + Vector2(24.0, 62.0), "已吞噬", HORIZONTAL_ALIGNMENT_LEFT, lane.size.x - 48.0, 24, Color(0.94, 1.0, 0.72))
	var action_text: String = "点击切换%s" % next_name if next_name != "" else "查看下一目标"
	draw_string(font, lane.position + Vector2(24.0, 92.0), action_text, HORIZONTAL_ALIGNMENT_LEFT, lane.size.x - 48.0, 17, Color(0.72, 0.92, 0.86))

func _completion_status_text() -> String:
	var next_name: String = String(_snapshot.get("next_region_name", ""))
	return "当前防线已吞噬；下一步：点击战场切换%s" % next_name if next_name != "" else "当前防线已吞噬"

func _draw_decision_badges(font: Font, lane: Rect2, unit_name: String, prepared_reserve: int, reserve_shortfall: int, hatch_fill_count: int, hatch_missing_text: String, baseline_needed_reserve: int, needed_reserve: int, pressure_drop: float, plugin_bonus: float, loss_saved_estimate: int, protected_estimate: int, acid_preview_loss_saved: int, acid_preview_protected: int, retreat_value: int, retreat_field_before: int) -> void:
	var badge_size := Vector2(150.0, 44.0)
	var gap: float = 8.0
	var left_x: float = lane.position.x + 12.0
	var right_x: float = minf(lane.end.x - badge_size.x - 12.0, left_x + badge_size.x + gap)
	var top_y: float = lane.position.y + 10.0
	var bottom_y: float = lane.end.y - badge_size.y - 10.0
	if _should_show_shortfall_badge(prepared_reserve, needed_reserve, reserve_shortfall):
		var fill_text: String = "蓄兵补%d只%s" % [hatch_fill_count, unit_name] if hatch_fill_count > 0 else "缺%s" % hatch_missing_text
		if hatch_fill_count <= 0 and hatch_missing_text == "":
			fill_text = "资源不足"
		_draw_badge(font, Rect2(Vector2(left_x, top_y), badge_size), "%s %d/%d" % [unit_name, prepared_reserve, needed_reserve], fill_text, Color(0.95, 0.47, 0.20))
	if baseline_needed_reserve > needed_reserve and needed_reserve > 0:
		_draw_badge(font, Rect2(Vector2(right_x, top_y), badge_size), "波次 %d→%d" % [baseline_needed_reserve, needed_reserve], "敌压 -%.1f" % pressure_drop, Color(0.40, 0.90, 0.76))
	if plugin_bonus > 0.001 and loss_saved_estimate > 0:
		_draw_badge(font, Rect2(Vector2(left_x, bottom_y), badge_size), "少损%d只" % loss_saved_estimate, "护住%d只" % protected_estimate, Color(0.52, 0.76, 1.0))
	elif acid_preview_loss_saved > 0:
		_draw_badge(font, Rect2(Vector2(left_x, bottom_y), badge_size), "下一目标甲壳", "买后少损%d/护住%d" % [acid_preview_loss_saved, acid_preview_protected], Color(0.52, 0.76, 1.0))
	if retreat_field_before > 0 and retreat_value > 0:
		_draw_badge(font, Rect2(Vector2(right_x, bottom_y), badge_size), "可保全%d只" % retreat_value, "右撤离回流%d" % retreat_value, Color(0.58, 0.78, 1.0))

func _should_show_shortfall_badge(prepared_reserve: int, needed_reserve: int, reserve_shortfall: int) -> bool:
	if needed_reserve > 0 and prepared_reserve >= needed_reserve:
		return false
	return reserve_shortfall > 0

func _draw_badge(font: Font, rect: Rect2, title: String, detail: String, color: Color) -> void:
	draw_rect(rect, Color(0.035, 0.045, 0.05, 0.86), true)
	draw_rect(rect, Color(color.r, color.g, color.b, 0.95), false, 2.0)
	var stripe := Rect2(rect.position, Vector2(5.0, rect.size.y))
	draw_rect(stripe, Color(color.r, color.g, color.b, 0.95), true)
	draw_string(font, rect.position + Vector2(12.0, 19.0), title, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 18.0, 16, Color(0.96, 1.0, 0.96))
	draw_string(font, rect.position + Vector2(12.0, 37.0), detail, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 18.0, 12, Color(color.r, color.g, color.b, 0.95))

func _draw_units(lane: Rect2, front_x: float, front_motion: String, mode: String, prepared_reserve: int) -> void:
	var z_field: int = int(_snapshot.get("zergling_field", 0))
	var h_field: int = int(_snapshot.get("hydralisk_field", 0))
	var z_intensity: int = int(_snapshot.get("zergling_intensity", 0))
	var h_intensity: int = int(_snapshot.get("hydralisk_intensity", 0))
	var z_count: int = clampi(z_field, 0, 14)
	var h_count: int = clampi(h_field, 0, 8)
	var left: float = lane.position.x + 18.0
	var right: float = maxf(left + 16.0, front_x - 18.0)
	var motion_offset: float = 7.0 if front_motion == "forward" else -8.0 if front_motion == "back" else 0.0
	if mode == "preparing" or mode == "understrength" or mode == "committed":
		var staged_count: int = clampi(prepared_reserve, 0, 8)
		for i in range(staged_count):
			var staged_pos := Vector2(left + float(i % 4) * 12.0, lane.end.y - 18.0 - float(i / 4) * 12.0)
			var staged_color: Color = Color(0.38, 0.78, 0.92) if mode != "understrength" else Color(0.96, 0.58, 0.24)
			draw_circle(staged_pos, 4.0, staged_color)
	for i in range(z_count):
		var t: float = float((i * 5) % 13) / 12.0
		var pos := Vector2(lerpf(left, right, t), lane.position.y + 20.0 + float(i % 3) * 21.0)
		pos.x += sin(_pulse * TAU + float(i)) * (2.0 + float(z_intensity)) + motion_offset * _pulse
		draw_circle(pos, 5.0, ZERGLING_COLOR)
	for i in range(h_count):
		var t: float = float((i * 7) % 9) / 8.0
		var pos := Vector2(lerpf(left + 10.0, right, t), lane.position.y + 32.0 + float(i % 2) * 28.0)
		pos.x += sin(_pulse * TAU + float(i) * 0.7) * (1.0 + float(h_intensity)) + motion_offset * _pulse
		var points: PackedVector2Array = PackedVector2Array([
			pos + Vector2(0.0, -7.0),
			pos + Vector2(7.0, 6.0),
			pos + Vector2(-7.0, 6.0)
		])
		draw_colored_polygon(points, HYDRALISK_COLOR)

func _battle_lane_rect() -> Rect2:
	return Rect2(24.0, 66.0, maxf(10.0, size.x - 48.0), 126.0)

func _sync_presentation_layer() -> void:
	if _battle_director == null:
		return
	_battle_director.update_snapshot(_snapshot, _battle_lane_rect())

func _draw_event_feedback(lane: Rect2, front_x: float, reinforced: int, lost: int, returned: int, mode: String, front_motion: String, retreat_value: int, retreat_field_before: int, preserved_loss_estimate: int) -> void:
	if reinforced > 0:
		var origin := Vector2(lane.position.x + 24.0, lane.position.y + 22.0)
		var target := Vector2(max(lane.position.x + 42.0, front_x - 18.0), lane.position.y + 38.0)
		var travel := origin.lerp(target, _pulse)
		draw_line(origin, travel, Color(0.35, 0.86, 1.0, 0.9), 2.0)
		draw_circle(travel, 4.0 + _pulse * 3.0, Color(0.35, 0.86, 1.0, 1.0 - _pulse * 0.4))
	if lost > 0:
		var loss_count: int = clampi(lost, 1, 6)
		for i in range(loss_count):
			var pos := Vector2(front_x - 18.0 - float(i) * 12.0, lane.end.y - 16.0 - float(i % 2) * 16.0)
			draw_line(pos + Vector2(-5.0, -5.0), pos + Vector2(5.0, 5.0), Color(1.0, 0.28, 0.20), 2.0)
			draw_line(pos + Vector2(-5.0, 5.0), pos + Vector2(5.0, -5.0), Color(1.0, 0.28, 0.20), 2.0)
	var visible_return: int = retreat_value
	if visible_return > 0:
		var start := Vector2(max(front_x - 12.0, lane.position.x + 56.0), lane.position.y + 64.0)
		var end := Vector2(lane.position.x + 28.0, lane.position.y + 64.0)
		var travel := start.lerp(end, _pulse)
		var return_color := Color(0.52, 0.76, 1.0, 0.95)
		draw_line(start, travel, return_color, 4.0)
		var dot_count: int = clampi(visible_return, 1, 6)
		for i in range(dot_count):
			var offset := Vector2(-float(i) * 8.0, sin(_pulse * TAU + float(i)) * 4.0)
			draw_circle(travel + offset, 4.0, return_color)
		if retreat_field_before > 0:
			var shield_center := end + Vector2(8.0, -18.0)
			draw_arc(shield_center, 10.0, PI * 0.15, PI * 0.85, 14, Color(0.52, 0.76, 1.0, 0.95), 2.0)
			if preserved_loss_estimate > 0:
				draw_line(shield_center + Vector2(-6.0, 5.0), shield_center + Vector2(6.0, 5.0), Color(0.52, 0.76, 1.0, 0.85), 2.0)
	if mode == "advance" or mode == "committed":
		var strike_x: float = lerpf(front_x, lane.end.x - 16.0, _pulse)
		draw_line(Vector2(front_x + 4.0, lane.position.y + 28.0), Vector2(strike_x, lane.position.y + 18.0), Color(0.68, 1.0, 0.50, 0.8), 2.0)
	elif mode == "stalled" or mode == "understrength":
		draw_arc(Vector2(front_x + 4.0, lane.position.y + lane.size.y * 0.5), 18.0 + _pulse * 8.0, -1.2, 1.2, 16, Color(1.0, 0.33, 0.22, 0.8), 3.0)
	if front_motion == "back" and mode != "retreat":
		draw_line(Vector2(front_x + 12.0, lane.position.y + 46.0), Vector2(front_x - 10.0, lane.position.y + 46.0), Color(1.0, 0.28, 0.20, 0.75), 3.0)

func _mode_text(mode: String, power: float, pressure: float, returned: int, prepared_reserve: int, needed_reserve: int, unit_name: String = "") -> String:
	var label: String = "波次" if unit_name == "" else unit_name
	match mode:
		"advance":
			return "虫群突破  %.1f / %.1f" % [power, pressure]
		"complete":
			var next_name: String = String(_snapshot.get("next_region_name", ""))
			return "已吞噬，切换%s" % next_name if next_name != "" else "已吞噬"
		"stalled":
			return "火力压制  %.1f / %.1f" % [power, pressure]
		"preparing":
			return "%s准备  %d / %d" % [label, prepared_reserve, needed_reserve]
		"ready":
			return "%s已备  %d / %d" % [label, prepared_reserve, needed_reserve]
		"understrength":
			if needed_reserve > 0 and prepared_reserve >= needed_reserve:
				return "%s已备  %d / %d" % [label, prepared_reserve, needed_reserve]
			return "%s不足  %d / %d" % [label, prepared_reserve, needed_reserve]
		"committed":
			return "强攻补位  %.1f / %.1f" % [power, pressure]
		"empty":
			return "阀门已开，前线缺兵"
		"holding":
			return "压制中，等待突破"
		"retreat":
			return "撤离回收  +%d" % returned
		"idle":
			return "等待投放，敌压未接触"
		_:
			return "战线待命  %.1f / %.1f" % [power, pressure]

func _front_color(mode: String) -> Color:
	match mode:
		"advance":
			return FRONT_ADVANCE
		"complete":
			return Color(0.78, 0.88, 0.34)
		"stalled", "empty", "understrength":
			return FRONT_STALLED
		"preparing", "ready", "committed":
			return Color(0.36, 0.74, 0.92)
		"retreat":
			return Color(0.44, 0.68, 1.0)
		"holding":
			return Color(0.35, 0.58, 0.95)
		_:
			return FRONT_IDLE

func _event_text(reinforced: int, lost: int, returned: int, loss_reason: String, progress_gain: float, _plugin_name: String, _prepared_reserve: int, _needed_reserve: int, cause: String, _support_bonus: float, _plugin_bonus: float, _effective_pressure: float, _reserve_shortfall: int, _hatch_fill_count: int, _pressure_drop: float, _loss_rate: float, _baseline_loss_rate: float, _loss_reduction: float, retreat_value: int, _loss_saved_estimate: int, _protected_estimate: int) -> String:
	var parts: Array[String] = []
	if reinforced > 0:
		parts.append("补位 +%d" % reinforced)
	if lost > 0:
		parts.append("损耗 -%d(%s)" % [lost, _loss_reason_text(loss_reason)])
	var visible_return: int = maxi(returned, retreat_value)
	if visible_return > 0:
		parts.append("撤保 +%d" % visible_return)
	if progress_gain > 0.0:
		parts.append("推进 +%.1f%%" % progress_gain)
	var cause_text: String = _cause_text(cause)
	if cause_text != "":
		parts.append(cause_text)
	return " / ".join(parts) if not parts.is_empty() else _loss_reason_text(loss_reason)

func _retreat_badge_visible_return(returned: int = -1, retreat_value: int = -1) -> int:
	var current_return: int = maxi(int(_snapshot.get("returned", 0)), int(_snapshot.get("retreat_value", 0))) if returned < 0 or retreat_value < 0 else maxi(returned, retreat_value)
	if current_return > 0:
		return current_return
	if _retreat_hold_remaining > 0.0:
		return _held_retreat_return
	return 0

func _display_mode(mode: String, prepared_reserve: int, needed_reserve: int, reserve_shortfall: int) -> String:
	if mode == "understrength" and needed_reserve > 0 and prepared_reserve >= needed_reserve and reserve_shortfall <= 0:
		return "ready"
	return mode

func _loss_reason_text(loss_reason: String) -> String:
	match loss_reason:
		"enemy_pressure":
			return "敌压打退"
		"breakthrough_attrition":
			return "突破损耗"
		"no_reserve":
			return "缺兵补位"
		"withdraw":
			return "主动撤离"
		"no_order":
			return "等待命令"
		"preparing_wave":
			return "蓄兵中"
		"understrength":
			return "规模不足"
		"committed_assault":
			return "强攻补位"
		_:
			return "战线待命"

func _cause_text(cause: String) -> String:
	match cause:
		"need_reserve":
			return "需更多储备"
		"ready_wave":
			return "可强攻"
		"commit_push":
			return "提高强度"
		"need_intensity":
			return "提高强度"
		"need_plugin":
			return "换构筑"
		_:
			return ""
