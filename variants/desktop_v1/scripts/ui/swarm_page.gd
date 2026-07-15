extends VBoxContainer

const UI = preload("res://scripts/ui/ui_utils.gd")

var snapshot: Dictionary = {}
var content: VBoxContainer

func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 12)
	add_child(UI.label("虫群总账", "PageTitle"))
	add_child(UI.label("这里是数量、构成、唯一位置与生产贡献查询，不提供阵型、驻军或目标权重。", "Muted"))
	content = VBoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 14)
	add_child(content)

func set_snapshot(value: Dictionary) -> void:
	snapshot = value
	if snapshot.is_empty():
		return
	_rebuild()

func _rebuild() -> void:
	UI.clear(content)
	var metrics := GridContainer.new()
	metrics.columns = 4
	metrics.add_theme_constant_override("h_separation", 10)
	metrics.add_theme_constant_override("v_separation", 10)
	content.add_child(metrics)
	_add_metric(metrics, "采质工蜂", int(snapshot.units.worker), "虫巢与领地物流")
	_add_metric(metrics, "噬咬体", _total_biter(), "猎杀 / 结构保底")
	_add_metric(metrics, "根脉形态", _total_roots(), "孢体 + 固定菌毯")
	_add_metric(metrics, "累计形成", int(snapshot.units.formed), "损失 %d" % snapshot.units.lost)
	content.add_child(UI.separator())
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 24)
	content.add_child(columns)
	var location := VBoxContainer.new()
	location.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	location.add_child(UI.label("唯一位置", "Section"))
	location.add_child(UI.label("虫巢内\n  工蜂 %d\n\n虫群大军\n  噬咬体 %d\n  根脉孢体 %d\n\n主动节点\n%s\n\n固定留置\n  根脉菌毯 %d" % [snapshot.units.worker, snapshot.units.biter, snapshot.units.root_spore, _battle_location_text(), snapshot.units.root_mat]))
	columns.add_child(location)
	columns.add_child(UI.separator(true))
	var contribution := VBoxContainer.new()
	contribution.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	contribution.add_child(UI.label("生产贡献", "Section"))
	for room_kind in ["embryo_hatchery", "biomass_filter", "thermal_metabolism"]:
		var count := _room_count(room_kind)
		contribution.add_child(UI.label("%s  × %d" % [GameSession.ROOM_DEFS[room_kind].name, count]))
	contribution.add_child(UI.label("所有单位由初始虫巢形成；第二虫巢尚未开放。", "Muted"))
	columns.add_child(contribution)
	columns.add_child(UI.separator(true))
	var assets := VBoxContainer.new()
	assets.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	assets.add_child(UI.label("过程资产位置", "Section"))
	assets.add_child(UI.label("现场残骸 %.0f\n已保障残骸 %.0f\n现场样本 %.0f\n已保障样本 %.0f\n待解析组织 %.0f" % [snapshot.processing.field_carcass, snapshot.processing.secured_carcass, snapshot.processing.field_sample, snapshot.processing.secured_sample, snapshot.processing.sample_tissue]))
	assets.add_child(UI.label("同一资产不会同时出现在两个阶段。", "Muted"))
	columns.add_child(assets)
	content.add_child(UI.spacer())
	var note := UI.label("战场命令只存在于节点上下文与主动战场带。", "Warning")
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(note)

func _add_metric(parent: GridContainer, name: String, value: int, subtitle: String) -> void:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box := VBoxContainer.new()
	panel.add_child(box)
	box.add_child(UI.label(name, "Muted"))
	box.add_child(UI.label(_format_count(value), "Title"))
	box.add_child(UI.label(subtitle, "Muted"))
	parent.add_child(panel)

func _format_count(value: int) -> String:
	if value >= 1000000:
		return "%.2f M" % (float(value) / 1000000.0)
	if value >= 1000:
		return "%.1f K" % (float(value) / 1000.0)
	return str(value)

func _total_biter() -> int:
	return int(snapshot.units.biter) + int(snapshot.active_battle.get("biter", 0))

func _total_roots() -> int:
	return int(snapshot.units.root_spore) + int(snapshot.units.root_mat) + int(snapshot.active_battle.get("spore", 0)) + int(snapshot.active_battle.get("roots", 0))

func _battle_location_text() -> String:
	if snapshot.active_battle.is_empty():
		return "  无主动战场"
	return "  %s：噬咬体 %d / 孢体 %d / 菌毯 %d" % [snapshot.active_battle.node_id, snapshot.active_battle.biter, snapshot.active_battle.spore, snapshot.active_battle.roots]

func _room_count(kind: String) -> int:
	var count := 0
	for room in snapshot.rooms:
		if room.kind == kind and room.state == "complete":
			count += 1
	return count
