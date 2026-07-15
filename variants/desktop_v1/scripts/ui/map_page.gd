extends HSplitContainer

signal open_battle_requested

const UI = preload("res://scripts/ui/ui_utils.gd")
const MapCanvas = preload("res://scripts/ui/map_canvas.gd")

var snapshot: Dictionary = {}
var selected_id := "H"
var canvas: Control
var detail: VBoxContainer

func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	split_offset = -350
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 10)
	add_child(left)
	left.add_child(UI.label("腐殖盆地 · 区域图", "PageTitle"))
	left.add_child(UI.label("内容在存档建立时一次生成；情报只改变显示，不会重抽敌人或来源。", "Muted"))
	var panel := PanelContainer.new()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(panel)
	canvas = MapCanvas.new()
	canvas.node_selected.connect(_select_node)
	panel.add_child(canvas)

	var right := PanelContainer.new()
	right.custom_minimum_size.x = 340
	add_child(right)
	detail = VBoxContainer.new()
	detail.add_theme_constant_override("separation", 10)
	right.add_child(detail)

func set_snapshot(value: Dictionary) -> void:
	snapshot = value
	if snapshot.is_empty():
		return
	canvas.set_snapshot(snapshot, selected_id)
	_rebuild_detail()

func _select_node(node_id: String) -> void:
	selected_id = node_id
	_rebuild_detail()

func _rebuild_detail() -> void:
	UI.clear(detail)
	if snapshot.is_empty():
		return
	var node := _node(selected_id)
	if node.is_empty():
		return
	detail.add_child(UI.label("%s · %s" % [node.id, node.name], "Section"))
	detail.add_child(UI.label(node.role, "Muted"))
	detail.add_child(UI.separator())
	if not node.observed:
		detail.add_child(UI.label("只有轮廓情报。占领相邻节点后才会揭示已提交内容。"))
		return
	detail.add_child(UI.label("状态", "Muted"))
	detail.add_child(UI.label("已占领" if node.owned else ("主动交战" if snapshot.active_battle.get("node_id", "") == node.id else "可观察"), "Metric"))
	detail.add_child(UI.label("活动敌军 %d / %d\n可见结构 %d / %d\n进攻次数 %d" % [node.enemy, node.enemy_max, node.structure_hp, node.structure_max, node.assaults]))
	if node.id == "B":
		detail.add_child(UI.label("占领来源：外源腐殖质 + 抽取容量", "Warning"))
	elif node.id == "W":
		detail.add_child(UI.label("固定样本载体：共振孵育床", "Warning"))
	elif node.id == "X":
		detail.add_child(UI.label("起始区域唯一出口；需要清除边界脉门。", "Warning"))
	if not node.owned:
		var attack := UI.button("提交全部可参战虫群", _attack_selected, "PrimaryButton")
		attack.disabled = not snapshot.active_battle.is_empty() or not _has_owned_neighbor(node.id) or int(snapshot.units.biter) + int(snapshot.units.root_spore) <= 0
		detail.add_child(attack)
		detail.add_child(UI.label("不显示胜率或推荐兵力。确认后，全部合法可参战单位原子转入节点。", "Muted"))
	if snapshot.adjacent_region.unlocked:
		detail.add_child(UI.separator())
		detail.add_child(UI.label("相邻地区概要", "Section"))
		detail.add_child(UI.label("%s\n%s\n资源倾向：%s\n着床条件：%s" % [snapshot.adjacent_region.name, snapshot.adjacent_region.theme, snapshot.adjacent_region.resource, snapshot.adjacent_region.hive_condition]))
		detail.add_child(UI.label("尚未开放", "Warning"))

func _attack_selected() -> void:
	if GameSession.attack_node(selected_id):
		open_battle_requested.emit()

func _node(node_id: String) -> Dictionary:
	for node in snapshot.nodes:
		if node.id == node_id:
			return node
	return {}

func _has_owned_neighbor(node_id: String) -> bool:
	for neighbor in GameSession.neighbors(node_id):
		if _node(neighbor).owned:
			return true
	return false
