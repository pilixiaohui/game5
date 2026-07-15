extends HSplitContainer

const ThemeFactory = preload("res://scripts/ui/theme_factory.gd")
const UI = preload("res://scripts/ui/ui_utils.gd")
const RoomSlot = preload("res://scripts/ui/room_slot.gd")

var snapshot: Dictionary = {}
var selected_slot := 0
var slot_buttons: Array = []
var grid: GridContainer
var detail: VBoxContainer
var summary_label: Label

func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	split_offset = -360
	_build()

func _build() -> void:
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 12)
	add_child(left)
	left.add_child(UI.label("虫巢剖面", "PageTitle"))
	left.add_child(UI.label("槽位拓扑决定房间群；同类模块正交相邻时自动合并。", "Muted"))

	var hive_band := PanelContainer.new()
	hive_band.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(hive_band)
	var hive_box := VBoxContainer.new()
	hive_box.add_theme_constant_override("separation", 12)
	hive_band.add_child(hive_box)
	grid = GridContainer.new()
	grid.columns = 4
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	hive_box.add_child(grid)
	for index in range(12):
		var slot := RoomSlot.new()
		slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slot.size_flags_vertical = Control.SIZE_EXPAND_FILL
		slot.pressed.connect(_select_slot.bind(index))
		grid.add_child(slot)
		slot_buttons.append(slot)
	summary_label = UI.label("", "Muted")
	hive_box.add_child(summary_label)

	var right_band := PanelContainer.new()
	right_band.custom_minimum_size.x = 350
	add_child(right_band)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right_band.add_child(scroll)
	detail = VBoxContainer.new()
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.add_theme_constant_override("separation", 10)
	scroll.add_child(detail)

func set_snapshot(value: Dictionary) -> void:
	snapshot = value
	if snapshot.is_empty():
		return
	for index in range(min(slot_buttons.size(), snapshot.rooms.size())):
		slot_buttons[index].set_room(snapshot.rooms[index], index == selected_slot)
	var groups := GameSession.room_groups()
	var merged := 0
	for group in groups:
		if group.slots.size() > 1:
			merged += 1
	summary_label.text = "房间群 %d  ·  已合并群 %d  ·  结构任务 %d" % [groups.size(), merged, _count_building()]
	_rebuild_detail()

func _select_slot(index: int) -> void:
	selected_slot = index
	set_snapshot(GameSession.snapshot())

func _rebuild_detail() -> void:
	UI.clear(detail)
	if snapshot.is_empty():
		return
	var room: Dictionary = snapshot.rooms[selected_slot]
	if room.kind == "":
		_build_empty_detail()
	else:
		_build_room_detail(room)

func _build_empty_detail() -> void:
	detail.add_child(UI.label("自由空槽 %02d" % (selected_slot + 1), "Section"))
	detail.add_child(UI.label("选择一个已发现蓝图。结构投入在确认时预留；取消未完成建设会完整释放预留。", "Muted"))
	for kind in GameSession.ROOM_DEFS.keys():
		var definition: Dictionary = GameSession.ROOM_DEFS[kind]
		var unlocked := GameSession.is_room_unlocked(kind)
		var button := UI.button("%s  ·  %d 生物质" % [definition.name, definition.cost], _build_room.bind(kind), "PrimaryButton" if unlocked else "")
		button.disabled = not unlocked or float(snapshot.resources.biomass) < float(definition.cost)
		button.tooltip_text = "蓝图尚未发现" if not unlocked else "在此槽位构筑 %s" % definition.name
		detail.add_child(button)
	detail.add_child(UI.separator())
	detail.add_child(UI.label("蓝图条件", "Section"))
	detail.add_child(UI.label("腐解消化池：保障任意残骸\n突触解析腔：分离出样本组织\n诱变培养腔：完成首次突变", "Muted"))

func _build_room_detail(room: Dictionary) -> void:
	var name := "核心巢室" if room.kind == "core" else String(GameSession.ROOM_DEFS[room.kind].name)
	detail.add_child(UI.label(name, "Section"))
	detail.add_child(UI.label("槽位 %02d  ·  %s" % [selected_slot + 1, _room_status(room)], "Muted"))
	if room.kind == "core":
		detail.add_child(UI.label("唯一状态根与资源账本接入口。只提供第一能源房间和第一只工蜂的最低恢复保障，不直接生产资源。"))
		_add_energy_block()
		return
	if room.state == "building":
		detail.add_child(UI.progress(float(room.progress) * 100.0))
		detail.add_child(UI.label("构筑进度 %d%%" % int(float(room.progress) * 100.0), "Muted"))
		detail.add_child(UI.button("取消建设并释放预留", _cancel_room, "DangerButton"))
		return
	var group_slots := _group_slots(room.kind, selected_slot)
	detail.add_child(UI.label("房间群：%s" % _slot_list(group_slots)))
	detail.add_child(UI.label("任务、功率、端口和缓冲均保留在模块账目；房间群只是拓扑投影。", "Muted"))
	var pause_button := UI.button("恢复运行" if room.paused else "暂停房间", _toggle_pause)
	detail.add_child(pause_button)
	if room.kind == "embryo_hatchery":
		_add_target_controls()
	elif room.kind == "thermal_metabolism":
		_add_energy_block()
	elif room.kind == "digestive_pool":
		detail.add_child(UI.label("待处理残骸 %.0f  ·  样本 %.0f" % [snapshot.processing.secured_carcass, snapshot.processing.secured_sample]))
	elif room.kind == "synapse_analyzer":
		detail.add_child(UI.label("待解析样本组织 %.0f" % snapshot.processing.sample_tissue))
	elif room.kind == "mutation_culture":
		var culture := UI.button("培养普通候选组  ·  18 生物质", _culture_candidate, "PrimaryButton")
		culture.disabled = not snapshot.candidate_group.is_empty() or snapshot.resources.biomass < 18
		detail.add_child(culture)
	detail.add_child(UI.separator())
	detail.add_child(UI.button("移动到最近空槽", _move_to_empty))
	detail.add_child(UI.button("拆除并回收完整结构投入", _demolish_room, "DangerButton"))

func _add_target_controls() -> void:
	detail.add_child(UI.separator())
	detail.add_child(UI.label("自动孵化目标", "Section"))
	for kind in ["worker", "biter", "root_spore"]:
		var row := HBoxContainer.new()
		var name := UI.label(String(GameSession.UNIT_DEFS[kind].name))
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name)
		row.add_child(UI.button("−", GameSession.set_unit_target.bind(kind, -1)))
		row.add_child(UI.label(str(snapshot.targets[kind]), "Metric"))
		row.add_child(UI.button("+", GameSession.set_unit_target.bind(kind, 1)))
		detail.add_child(row)
	detail.add_child(UI.label("房间会按工蜂 → 噬咬体 → 根脉孢体顺序补齐缺口。", "Muted"))

func _add_energy_block() -> void:
	detail.add_child(UI.separator())
	detail.add_child(UI.label("能源服务", "Section"))
	detail.add_child(UI.label("供给 %.1f  ·  基础负载 %.1f\n任务负载 %.1f  ·  净变化 %+.1f" % [snapshot.energy.supply, snapshot.energy.base_load, snapshot.energy.task_load, snapshot.energy.net]))
	var energy_bar := UI.progress(float(snapshot.resources.energy), float(snapshot.energy.capacity))
	detail.add_child(energy_bar)
	detail.add_child(UI.label("储能 %.0f / %.0f" % [snapshot.resources.energy, snapshot.energy.capacity], "Muted"))

func _build_room(kind: String) -> void:
	GameSession.build_room(selected_slot, kind)

func _cancel_room() -> void:
	GameSession.cancel_room(selected_slot)

func _demolish_room() -> void:
	GameSession.demolish_room(selected_slot)

func _toggle_pause() -> void:
	GameSession.set_room_paused(selected_slot, not bool(snapshot.rooms[selected_slot].paused))

func _move_to_empty() -> void:
	for room in snapshot.rooms:
		if room.kind == "":
			if GameSession.move_room(selected_slot, int(room.slot)):
				selected_slot = int(room.slot)
			return

func _culture_candidate() -> void:
	GameSession.culture_candidate()

func _count_building() -> int:
	var count := 0
	for room in snapshot.rooms:
		if room.state == "building":
			count += 1
	return count

func _group_slots(kind: String, slot: int) -> Array:
	for group in GameSession.room_groups():
		if group.kind == kind and slot in group.slots:
			return group.slots
	return [slot]

func _slot_list(slots: Array) -> String:
	var values: Array[String] = []
	for slot in slots:
		values.append("%02d" % (int(slot) + 1))
	return ", ".join(values)

func _room_status(room: Dictionary) -> String:
	if room.state == "building":
		return "构筑中"
	if room.paused:
		return "已暂停"
	return "运行中"
