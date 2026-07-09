class_name UnitPool2D
extends Node2D

const DEFAULT_COLOR := Color(0.44, 0.95, 0.58)

var _pool: Array[Node2D] = []
var _spawned_total: int = 0
var _recycled_total: int = 0
var _lost_recycled_total: int = 0
var _retreat_recycled_total: int = 0
var _max_active_seen: int = 0

func _exit_tree() -> void:
	clear_pool()

func fetch() -> Node2D:
	if _pool.is_empty():
		_spawned_total += 1
		return _create_unit_node()
	var node: Node2D = _pool.pop_back()
	node.visible = true
	return node

func spawn_unit(unit_id: String, position: Vector2, color: Color = DEFAULT_COLOR, lane_index: int = 0) -> Node2D:
	var node := fetch()
	node.name = "Unit_%s" % unit_id
	node.position = position
	node.visible = true
	node.set_meta("unit_id", unit_id)
	node.set_meta("lane_index", lane_index)
	node.set_meta("state", "active")
	node.set_meta("age", 0.0)
	node.set_meta("speed", 48.0 + float((_spawned_total + lane_index * 11) % 30))
	_paint_unit(node, color, unit_id)
	add_child(node)
	_max_active_seen = maxi(_max_active_seen, active_count())
	return node

func recycle(node: Node2D, reason: String = "generic") -> void:
	if node == null:
		return
	if _pool.has(node):
		return
	node.visible = false
	if node.get_parent() != null:
		node.get_parent().remove_child(node)
	node.position = Vector2.ZERO
	node.set_meta("state", "pooled")
	_pool.append(node)
	_recycled_total += 1
	if reason == "loss":
		_lost_recycled_total += 1
	elif reason == "retreat":
		_retreat_recycled_total += 1

func recycle_all(reason: String = "generic") -> void:
	var active := active_units()
	for node in active:
		recycle(node, reason)

func clear_pool() -> void:
	for node in _pool:
		if not is_instance_valid(node):
			continue
		if node.get_parent() != null:
			node.get_parent().remove_child(node)
		node.free()
	_pool.clear()

func active_units() -> Array[Node2D]:
	var nodes: Array[Node2D] = []
	for child in get_children():
		if child is Node2D and child.visible:
			nodes.append(child as Node2D)
	return nodes

func active_count() -> int:
	return active_units().size()

func pool_count() -> int:
	return _pool.size()

func stats() -> Dictionary:
	return {
		"active_count": active_count(),
		"pool_count": pool_count(),
		"spawned_total": _spawned_total,
		"recycled_total": _recycled_total,
		"lost_recycled_total": _lost_recycled_total,
		"retreat_recycled_total": _retreat_recycled_total,
		"max_active_seen": _max_active_seen
	}

func _create_unit_node() -> Node2D:
	var node := Node2D.new()
	var shadow := Polygon2D.new()
	shadow.name = "Shadow"
	shadow.polygon = _body_points()
	shadow.position = Vector2(1.5, 2.5)
	shadow.color = Color(0.0, 0.0, 0.0, 0.28)
	node.add_child(shadow)
	var body := Polygon2D.new()
	body.name = "Body"
	body.polygon = _body_points()
	body.color = DEFAULT_COLOR
	node.add_child(body)
	return node

func _paint_unit(node: Node2D, color: Color, unit_id: String) -> void:
	var body := node.get_node_or_null("Body") as Polygon2D
	if body != null:
		body.color = color
		body.scale = _unit_scale(unit_id)
	var shadow := node.get_node_or_null("Shadow") as Polygon2D
	if shadow != null:
		shadow.scale = _unit_scale(unit_id)

func _unit_scale(unit_id: String) -> Vector2:
	match unit_id:
		"hydralisk":
			return Vector2(1.15, 1.35)
		"baneling":
			return Vector2(1.25, 1.0)
		"carapace_guard", "roach":
			return Vector2(1.35, 1.25)
		"mutalisk":
			return Vector2(1.25, 0.85)
		_:
			return Vector2.ONE

func _body_points() -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(0.0, -5.0),
		Vector2(7.0, -1.0),
		Vector2(5.0, 5.0),
		Vector2(-6.0, 4.0),
		Vector2(-7.0, -2.0)
	])
