extends VBoxContainer

signal back_requested

const UI = preload("res://scripts/ui/ui_utils.gd")

var content: VBoxContainer

func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 10)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	add_child(header)
	header.add_child(UI.button("返回进化", back_requested.emit))
	var title := UI.label("飞升只读预览", "PageTitle")
	title.name = "AscensionPageTitle"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_child(title)
	var availability := UI.label("尚未开放", "Warning")
	availability.name = "AscensionAvailability"
	availability.autowrap_mode = TextServer.AUTOWRAP_OFF
	availability.custom_minimum_size = Vector2(90, 28)
	availability.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	availability.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(availability)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(scroll)
	content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 16)
	scroll.add_child(content)

func set_snapshot(_value: Dictionary) -> void:
	_rebuild()

func _rebuild() -> void:
	UI.clear(content)
	var preview := GameSession.ascension_preview()
	if preview.is_empty():
		return
	var point_band := PanelContainer.new()
	point_band.custom_minimum_size.y = 86
	content.add_child(point_band)
	var point_row := HBoxContainer.new()
	point_row.add_theme_constant_override("separation", 18)
	point_band.add_child(point_row)
	var copy := VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.add_child(UI.label("预计飞升点", "Section"))
	copy.add_child(UI.label("来自当前存档同一权威快照", "Muted"))
	point_row.add_child(copy)
	var point_total := UI.label(str(preview.points), "Title")
	point_total.name = "AscensionPointTotal"
	point_total.autowrap_mode = TextServer.AUTOWRAP_OFF
	point_total.custom_minimum_size = Vector2(128, 48)
	point_total.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	point_total.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	point_row.add_child(point_total)
	var contribution_grid := GridContainer.new()
	contribution_grid.columns = 6
	contribution_grid.add_theme_constant_override("h_separation", 8)
	content.add_child(contribution_grid)
	for item in preview.contributions:
		var panel := PanelContainer.new()
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var box := VBoxContainer.new()
		panel.add_child(box)
		box.add_child(UI.label(item.name, "Muted"))
		box.add_child(UI.label("+%d" % item.value, "Metric"))
		contribution_grid.add_child(panel)
	content.add_child(UI.label("永久收益预览", "Section"))
	var permanent_grid := GridContainer.new()
	permanent_grid.columns = 3
	permanent_grid.add_theme_constant_override("h_separation", 10)
	permanent_grid.add_theme_constant_override("v_separation", 10)
	content.add_child(permanent_grid)
	for item in preview.permanents:
		var panel := PanelContainer.new()
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var box := VBoxContainer.new()
		panel.add_child(box)
		box.add_child(UI.label(item.name, "Section"))
		box.add_child(UI.label("当前 %s  →  购买后 %s" % [item.current, item.next]))
		box.add_child(UI.label("成本 %d 点" % item.cost, "Muted"))
		permanent_grid.add_child(panel)
	content.add_child(UI.label("虫群领袖预览", "Section"))
	var leader_grid := GridContainer.new()
	leader_grid.columns = 3
	leader_grid.add_theme_constant_override("h_separation", 10)
	leader_grid.add_theme_constant_override("v_separation", 10)
	content.add_child(leader_grid)
	for leader in preview.leaders:
		var panel := PanelContainer.new()
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var box := VBoxContainer.new()
		panel.add_child(box)
		box.add_child(UI.label(leader.name, "Section"))
		box.add_child(UI.label("优势：%s\n弱项：%s" % [leader.strength, leader.weakness]))
		box.add_child(UI.label("专属池将在正式飞升版本开放", "Muted"))
		leader_grid.add_child(panel)
	var lock := UI.label("预览不提供确认飞升、领袖选择或永久收益购买命令。", "Warning")
	lock.name = "AscensionLockNotice"
	lock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(lock)
