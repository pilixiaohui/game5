class_name BattleDirector
extends Node2D

signal battle_tick(region_id: String, progress: float)

const UnitPool2DScript := preload("res://scripts/battle/UnitPool2D.gd")

const MAX_ACTIVE_UNITS := 48
const STRONG_VISIBLE_FLOOR := 30
const UNIT_VISUAL_RADIUS := 14.0
const UNIT_COLORS := {
	"zergling": Color(0.44, 0.95, 0.58),
	"hydralisk": Color(0.34, 0.74, 1.0),
	"baneling": Color(0.88, 0.95, 0.30),
	"carapace_guard": Color(0.54, 0.86, 0.96),
	"roach": Color(0.62, 0.78, 0.52),
	"mutalisk": Color(0.82, 0.56, 1.0)
}

var _unit_pool
var _snapshot: Dictionary = {}
var _lane_rect := Rect2(Vector2(24.0, 66.0), Vector2(492.0, 126.0))
var _last_retreat_token: int = 0
var _last_loss_token: int = 0
var _spawn_cursor: int = 0

func _ready() -> void:
	_ensure_pool()
	set_process(true)

func _exit_tree() -> void:
	if _unit_pool != null and _unit_pool.has_method("clear_pool"):
		_unit_pool.clear_pool()

func set_unit_pool(pool) -> void:
	if _unit_pool == pool:
		return
	if _unit_pool != null and _unit_pool.get_parent() == self:
		remove_child(_unit_pool)
	_unit_pool = pool
	if _unit_pool != null and _unit_pool.get_parent() == null:
		add_child(_unit_pool)

func apply_macro_tick(_seconds: float, snapshot: Dictionary = {}) -> void:
	battle_tick.emit(String(snapshot.get("region_id", "")), float(snapshot.get("progress", 0.0)))

func update_snapshot(snapshot: Dictionary, lane_rect: Rect2) -> void:
	_ensure_pool()
	_snapshot = snapshot.duplicate(true)
	_lane_rect = lane_rect
	var mode := String(_snapshot.get("mode", "idle"))
	var retreat_value: int = maxi(int(_snapshot.get("returned", 0)), int(_snapshot.get("retreat_value", 0)))
	var retreat_field: int = int(_snapshot.get("retreat_field_before", 0))
	var retreat_token: int = int(_snapshot.get("retreat_token", 0))
	if retreat_token == 0 and (mode == "retreat" or retreat_value > 0 or retreat_field > 0):
		retreat_token = hash("%s:%d:%d" % [mode, retreat_value, retreat_field])
	if mode == "complete":
		_unit_pool.recycle_all("complete")
		return
	if mode == "retreat" and retreat_token != _last_retreat_token:
		_last_retreat_token = retreat_token
		_unit_pool.recycle_all("retreat")
		return
	var lost := int(_snapshot.get("lost", 0))
	var loss_token: int = hash("%s:%d:%d:%.2f:%d" % [mode, lost, _field_total(), float(_snapshot.get("progress", 0.0)), int(_snapshot.get("reinforced", 0))])
	if lost > 0 and loss_token != _last_loss_token:
		_last_loss_token = loss_token
		_recycle_front_units(lost, "loss")
	_match_active_count(_desired_count())
	_layout_active_units()

func active_count() -> int:
	_ensure_pool()
	return _unit_pool.active_count()

func pool_count() -> int:
	_ensure_pool()
	return _unit_pool.pool_count()

func presentation_stats() -> Dictionary:
	_ensure_pool()
	var stats: Dictionary = _unit_pool.stats()
	stats["max_allowed"] = MAX_ACTIVE_UNITS
	stats["lane_rect"] = _lane_rect
	return stats

func _process(delta: float) -> void:
	if _unit_pool == null:
		return
	var mode := String(_snapshot.get("mode", "idle"))
	var front_motion := String(_snapshot.get("front_motion", "none"))
	var front_x := _front_x()
	for node in _unit_pool.active_units():
		var age := float(node.get_meta("age", 0.0)) + delta
		node.set_meta("age", age)
		var lane_index := int(node.get_meta("lane_index", 0))
		var row_y := _row_y(lane_index)
		var target_x := _target_x_for(node, mode, front_motion, front_x)
		var target := _clamp_to_lane(Vector2(target_x, row_y + sin(age * 3.4 + float(lane_index)) * 3.0))
		var speed := float(node.get_meta("speed", 58.0))
		node.position = _clamp_to_lane(node.position.move_toward(target, speed * delta))

func _ensure_pool() -> void:
	if _unit_pool != null:
		return
	_unit_pool = UnitPool2DScript.new()
	_unit_pool.name = "UnitPool2D"
	add_child(_unit_pool)

func _desired_count() -> int:
	var mode := String(_snapshot.get("mode", "idle"))
	if mode == "idle" or mode == "empty" or mode == "retreat" or mode == "complete":
		return 0
	var field_total := _field_total()
	var prepared := int(_snapshot.get("prepared_reserve", 0))
	var needed := int(_snapshot.get("needed_reserve", 0))
	var base: int = 0
	if mode == "preparing" or mode == "ready" or mode == "understrength":
		base = prepared * 4
	else:
		base = field_total * 3 + int(_snapshot.get("reinforced", 0))
	var strong: bool = (mode == "committed" or mode == "advance" or mode == "holding" or mode == "stalled") and (field_total > 0 or prepared >= maxi(1, needed))
	if strong:
		base = maxi(base, STRONG_VISIBLE_FLOOR)
	return clampi(base, 0, MAX_ACTIVE_UNITS)

func _match_active_count(desired: int) -> void:
	var active: Array = _unit_pool.active_units()
	while active.size() > desired:
		_unit_pool.recycle(active.pop_back(), "overflow")
	while _unit_pool.active_count() < desired:
		var unit_id := _next_unit_id()
		var lane_index := _spawn_cursor % 6
		var spawn_pos := _clamp_to_lane(Vector2(_lane_rect.position.x + 14.0 + float(lane_index % 3) * 8.0, _row_y(lane_index)))
		_unit_pool.spawn_unit(unit_id, spawn_pos, _unit_color(unit_id), lane_index)
		_spawn_cursor += 1

func _layout_active_units() -> void:
	var i := 0
	for node in _unit_pool.active_units():
		node.set_meta("lane_index", i % 6)
		i += 1

func _recycle_front_units(count: int, reason: String) -> void:
	var active: Array = _unit_pool.active_units()
	active.sort_custom(func(a: Node2D, b: Node2D) -> bool:
		return a.position.x > b.position.x
	)
	for i in range(mini(count, active.size())):
		_unit_pool.recycle(active[i], reason)

func _front_x() -> float:
	var progress := clampf(float(_snapshot.get("progress", 0.0)), 0.0, 100.0)
	return _lane_rect.position.x + _lane_rect.size.x * progress / 100.0

func _row_y(index: int) -> float:
	var rows := 6
	var gap := _lane_rect.size.y / float(rows + 1)
	return _lane_rect.position.y + gap * float((index % rows) + 1)

func _clamp_to_lane(position: Vector2) -> Vector2:
	var min_x := _lane_rect.position.x + UNIT_VISUAL_RADIUS
	var max_x := _lane_rect.end.x - UNIT_VISUAL_RADIUS
	var min_y := _lane_rect.position.y + UNIT_VISUAL_RADIUS
	var max_y := _lane_rect.end.y - UNIT_VISUAL_RADIUS
	if max_x < min_x:
		max_x = min_x
	if max_y < min_y:
		max_y = min_y
	return Vector2(clampf(position.x, min_x, max_x), clampf(position.y, min_y, max_y))

func _target_x_for(node: Node2D, mode: String, front_motion: String, front_x: float) -> float:
	var lane_index := int(node.get_meta("lane_index", 0))
	var stagger := float((lane_index * 17) % 48)
	var left := _lane_rect.position.x + 18.0 + stagger * 0.35
	var front_target := clampf(front_x - 12.0 - stagger, left + 18.0, _lane_rect.end.x - 42.0)
	if mode == "preparing" or mode == "ready" or mode == "understrength":
		return left + float(lane_index % 5) * 17.0
	if front_motion == "back":
		return maxf(left, front_target - 34.0)
	if front_motion == "forward" or mode == "committed" or mode == "advance":
		return minf(_lane_rect.end.x - 38.0, front_target + 38.0)
	return front_target

func _next_unit_id() -> String:
	var fields: Dictionary = _snapshot.get("unit_fields", {})
	var weighted: Array[String] = []
	for unit_id in fields.keys():
		var count := int(fields.get(unit_id, 0))
		for _i in range(clampi(count, 0, 12)):
			weighted.append(String(unit_id))
	if weighted.is_empty():
		var projection_unit := String(_snapshot.get("projection_unit_id", "zergling"))
		weighted.append(projection_unit if projection_unit != "" else "zergling")
	return weighted[_spawn_cursor % weighted.size()]

func _field_total() -> int:
	var explicit := int(_snapshot.get("field_total", -1))
	if explicit >= 0:
		return explicit
	var fields: Dictionary = _snapshot.get("unit_fields", {})
	var total := 0
	for unit_id in fields.keys():
		total += int(fields.get(unit_id, 0))
	if total <= 0:
		total = int(_snapshot.get("zergling_field", 0)) + int(_snapshot.get("hydralisk_field", 0))
	return total

func _unit_color(unit_id: String) -> Color:
	return UNIT_COLORS.get(unit_id, Color(0.44, 0.95, 0.58))
