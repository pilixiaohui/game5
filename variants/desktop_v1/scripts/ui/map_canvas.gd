extends Control

signal node_selected(node_id: String)

const ThemeFactory = preload("res://scripts/ui/theme_factory.gd")

var snapshot: Dictionary = {}
var selected_id := "H"
var node_buttons := {}

func _ready() -> void:
	custom_minimum_size = Vector2(700, 480)
	resized.connect(_layout_buttons)

func set_snapshot(value: Dictionary, selected: String = "") -> void:
	snapshot = value
	if selected != "":
		selected_id = selected
	_ensure_buttons()
	_layout_buttons()
	queue_redraw()

func _ensure_buttons() -> void:
	if snapshot.is_empty():
		return
	for node in snapshot.nodes:
		if node_buttons.has(node.id):
			continue
		var button := Button.new()
		button.custom_minimum_size = Vector2(118, 70)
		button.focus_mode = Control.FOCUS_ALL
		button.pressed.connect(_on_node_pressed.bind(String(node.id)))
		add_child(button)
		node_buttons[node.id] = button
	_update_buttons()

func _update_buttons() -> void:
	if snapshot.is_empty():
		return
	var active_id := String(snapshot.active_battle.get("node_id", ""))
	for node in snapshot.nodes:
		var button: Button = node_buttons[node.id]
		button.text = "%s  %s\n%s" % [node.id, node.name if node.observed else "未知脉冲", "已占领" if node.owned else ("交战中" if active_id == node.id else (node.role if node.observed else "轮廓已知"))]
		button.disabled = not node.observed
		var accent := ThemeFactory.GREEN if node.owned else (ThemeFactory.RED if active_id == node.id else ThemeFactory.CYAN)
		if selected_id == node.id:
			accent = ThemeFactory.AMBER
		button.add_theme_color_override("font_color", accent)
		button.add_theme_color_override("font_disabled_color", Color(ThemeFactory.MUTED, 0.65))

func _layout_buttons() -> void:
	if snapshot.is_empty():
		return
	for node in snapshot.nodes:
		var button: Button = node_buttons.get(node.id)
		if button == null:
			continue
		var pos := Vector2(float(node.pos[0]) * size.x, float(node.pos[1]) * size.y)
		button.position = pos - Vector2(59, 35)
	_update_buttons()
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("091417"), true)
	for x in range(0, int(size.x), 72):
		draw_line(Vector2(x, 0), Vector2(x, size.y), Color(ThemeFactory.BORDER, 0.16), 1.0)
	for y in range(0, int(size.y), 72):
		draw_line(Vector2(0, y), Vector2(size.x, y), Color(ThemeFactory.BORDER, 0.16), 1.0)
	if snapshot.is_empty():
		return
	for link in snapshot.links:
		var a := _node(link[0])
		var b := _node(link[1])
		if a.is_empty() or b.is_empty():
			continue
		var start := Vector2(float(a.pos[0]) * size.x, float(a.pos[1]) * size.y)
		var end := Vector2(float(b.pos[0]) * size.x, float(b.pos[1]) * size.y)
		var known := bool(a.observed and b.observed)
		var owned := bool(a.owned and b.owned)
		var color := ThemeFactory.GREEN if owned else (ThemeFactory.BORDER if known else Color(ThemeFactory.BORDER, 0.28))
		draw_line(start, end, color, 4.0 if owned else 2.0, true)

func _node(node_id: String) -> Dictionary:
	for node in snapshot.nodes:
		if node.id == node_id:
			return node
	return {}

func _on_node_pressed(node_id: String) -> void:
	selected_id = node_id
	_update_buttons()
	node_selected.emit(node_id)
