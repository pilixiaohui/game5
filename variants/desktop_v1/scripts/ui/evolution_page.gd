extends HSplitContainer

signal open_ascension_requested

const ThemeFactory = preload("res://scripts/ui/theme_factory.gd")
const UI = preload("res://scripts/ui/ui_utils.gd")

var snapshot: Dictionary = {}
var mutation_list: VBoxContainer
var candidate_area: VBoxContainer

func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	split_offset = 390
	var left := PanelContainer.new()
	left.custom_minimum_size.x = 380
	add_child(left)
	mutation_list = VBoxContainer.new()
	mutation_list.add_theme_constant_override("separation", 10)
	left.add_child(mutation_list)
	var right_scroll := ScrollContainer.new()
	right_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(right_scroll)
	candidate_area = VBoxContainer.new()
	candidate_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	candidate_area.add_theme_constant_override("separation", 12)
	right_scroll.add_child(candidate_area)

func set_snapshot(value: Dictionary) -> void:
	snapshot = value
	if snapshot.is_empty():
		return
	_rebuild_mutations()
	_rebuild_candidates()

func _rebuild_mutations() -> void:
	UI.clear(mutation_list)
	mutation_list.add_child(UI.label("进化事实", "PageTitle"))
	mutation_list.add_child(UI.label("已同化突变属于本轮权威状态；拆除房间不会遗忘。", "Muted"))
	mutation_list.add_child(UI.separator())
	mutation_list.add_child(UI.label("已同化 %d" % snapshot.mutations.size(), "Section"))
	if snapshot.mutations.is_empty():
		mutation_list.add_child(UI.label("尚未同化突变", "Muted"))
	else:
		for mutation in snapshot.mutations:
			var item := VBoxContainer.new()
			item.add_child(UI.label(mutation.name, "Section"))
			item.add_child(UI.label("%s\n代价：%s" % [mutation.summary, mutation.pressure], "Muted"))
			mutation_list.add_child(item)
	mutation_list.add_child(UI.spacer())
	mutation_list.add_child(UI.button("飞升只读预览", open_ascension_requested.emit))
	mutation_list.add_child(UI.label("根据当前存档同一快照计算，不执行正式飞升。", "Muted"))

func _rebuild_candidates() -> void:
	UI.clear(candidate_area)
	candidate_area.add_child(UI.label("候选与同化", "PageTitle"))
	var source_row := HBoxContainer.new()
	var source_copy := VBoxContainer.new()
	source_copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	source_copy.add_child(UI.label("普通候选来源", "Section"))
	source_copy.add_child(UI.label("一次机会形成一个全局组，整组占一个槽；同化后其余候选消失。", "Muted"))
	source_row.add_child(source_copy)
	var induce := UI.button("主动诱导 · 8 基因", _induce, "PrimaryButton")
	induce.disabled = not snapshot.unlocks.active_induction or not snapshot.candidate_group.is_empty() or snapshot.resources.genes < 8
	induce.tooltip_text = "完成首次突变后解锁"
	source_row.add_child(induce)
	candidate_area.add_child(source_row)
	if snapshot.candidate_group.is_empty():
		var empty := PanelContainer.new()
		empty.custom_minimum_size.y = 250
		var center := VBoxContainer.new()
		center.alignment = BoxContainer.ALIGNMENT_CENTER
		empty.add_child(center)
		center.add_child(UI.label("候选槽为空", "Section"))
		if snapshot.mutations.is_empty():
			center.add_child(UI.label("保障固定样本，经腐解与突触解析后形成首次组。", "Muted"))
		else:
			center.add_child(UI.label("可使用主动诱导，或在诱变培养腔中形成普通组。", "Muted"))
		candidate_area.add_child(empty)
		return
	candidate_area.add_child(UI.label("来源：%s  ·  %s" % [snapshot.candidate_group.source, "首次受保护组" if snapshot.candidate_group.kind == "first" else "普通组"], "Warning"))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	candidate_area.add_child(grid)
	for candidate in snapshot.candidate_group.options:
		grid.add_child(_candidate_card(candidate))

func _candidate_card(candidate: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(230, 250)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 9)
	panel.add_child(box)
	var stripe := ColorRect.new()
	stripe.color = Color(candidate.accent)
	stripe.custom_minimum_size.y = 5
	box.add_child(stripe)
	box.add_child(UI.label(candidate.name, "Section"))
	box.add_child(UI.label(candidate.summary))
	box.add_child(UI.label("构筑压力", "Muted"))
	box.add_child(UI.label(candidate.pressure, "Warning"))
	box.add_child(UI.spacer())
	var select := UI.button("同化 · %d 基因" % candidate.cost, _select.bind(String(candidate.id)), "PrimaryButton")
	select.disabled = snapshot.resources.genes < float(candidate.cost)
	box.add_child(select)
	return panel

func _induce() -> void:
	GameSession.induce_candidate()

func _select(candidate_id: String) -> void:
	GameSession.select_candidate(candidate_id)
