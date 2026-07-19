class_name M1HiveHud
extends HBoxContainer

signal command_requested(command: String, payload: Dictionary)

const UI = preload("res://scripts/ui/ui_utils.gd")
const ROOM_ORDER := [
	"thermal_metabolism",
	"biomass_filter",
	"embryo_hatchery",
	"digestive_pool",
	"synapse_analyzer",
	"mutation_culture",
]
const UNIT_ORDER := ["worker", "biter", "root_spore"]

var snapshot: Dictionary = {}
var room_definitions: Dictionary = {}
var unit_definitions: Dictionary = {}
var unlocked_rooms: Dictionary = {}
var room_groups: Array = []
var selected_slot := 0
var slot_panel: PanelContainer
var detail_panel: PanelContainer
var slot_grid: GridContainer
var summary_label: Label
var detail: VBoxContainer
var slot_buttons: Array[Button] = []
var world_slot: MarginContainer
var slot_title: Label
var detail_title: Label
var slot_toggle: Button
var detail_toggle: Button
var detail_margin: MarginContainer
var slot_expanded := true
var detail_expanded := true

func _ready() -> void:
	name = "M1HiveHud"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 8)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 9
	_build_slot_panel()
	world_slot = MarginContainer.new()
	world_slot.name = "M1WorldViewportSlot"
	world_slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	world_slot.size_flags_vertical = Control.SIZE_EXPAND_FILL
	world_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	world_slot.clip_contents = true
	add_child(world_slot)
	_build_detail_panel()
	_apply_dock_state()

func attach_world_viewport(host: SubViewportContainer) -> void:
	if not is_instance_valid(host) or not is_instance_valid(world_slot):
		return
	if host.get_parent() != null:
		host.reparent(world_slot)
	else:
		world_slot.add_child(host)
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.custom_minimum_size = Vector2.ZERO
	host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host.size_flags_vertical = Control.SIZE_EXPAND_FILL

func set_projection(
	value: Dictionary,
	room_defs_value: Dictionary,
	unit_defs_value: Dictionary,
	unlocked_value: Dictionary,
	groups_value: Array
) -> void:
	snapshot = value.duplicate(true)
	room_definitions = room_defs_value.duplicate(true)
	unit_definitions = unit_defs_value.duplicate(true)
	unlocked_rooms = unlocked_value.duplicate(true)
	room_groups = groups_value.duplicate(true)
	var operations_visible := not snapshot.is_empty() and (snapshot.get("active_battle", {}) as Dictionary).is_empty()
	slot_panel.visible = operations_visible
	detail_panel.visible = operations_visible
	if not operations_visible:
		return
	_refresh_slots()
	_rebuild_detail()

func is_operations_visible() -> bool:
	return is_instance_valid(slot_panel) and slot_panel.visible and is_instance_valid(detail_panel) and detail_panel.visible

func ui_contract_snapshot() -> Dictionary:
	var visible_slots := 0
	var focusable_slots := 0
	for button in slot_buttons:
		if button.is_visible_in_tree():
			visible_slots += 1
		if button.focus_mode == Control.FOCUS_ALL:
			focusable_slots += 1
	var build_actions := find_children("M1Build_*", "Button", true, false)
	var enabled_build_actions := 0
	for candidate in build_actions:
		if not (candidate as Button).disabled:
			enabled_build_actions += 1
	return {
		"operations_visible": is_operations_visible(),
		"slot_count": slot_buttons.size(),
		"visible_slot_count": visible_slots,
		"focusable_slot_count": focusable_slots,
		"detail_visible": is_instance_valid(detail_panel) and detail_panel.is_visible_in_tree(),
		"build_action_count": build_actions.size(),
		"enabled_build_action_count": enabled_build_actions,
		"target_action_count": find_children("M1Target_*", "Button", true, false).size(),
		"selected_slot": selected_slot,
		"slot_expanded": slot_expanded,
		"detail_expanded": detail_expanded,
		"slot_dock_rect": slot_panel.get_global_rect() if is_instance_valid(slot_panel) and slot_panel.is_visible_in_tree() else Rect2(),
		"detail_dock_rect": detail_panel.get_global_rect() if is_instance_valid(detail_panel) and detail_panel.is_visible_in_tree() else Rect2(),
		"viewport_slot_rect": world_slot.get_global_rect() if is_instance_valid(world_slot) else Rect2(),
		"slot_toggle_focusable": is_instance_valid(slot_toggle) and slot_toggle.focus_mode == Control.FOCUS_ALL,
		"detail_toggle_focusable": is_instance_valid(detail_toggle) and detail_toggle.focus_mode == Control.FOCUS_ALL,
	}

func _build_slot_panel() -> void:
	slot_panel = PanelContainer.new()
	slot_panel.name = "M1HiveSlotPanel"
	slot_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	slot_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(slot_panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	slot_panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	margin.add_child(box)
	var header := HBoxContainer.new()
	box.add_child(header)
	slot_title = UI.label("虫巢槽位", "Section")
	slot_title.autowrap_mode = TextServer.AUTOWRAP_OFF
	slot_title.custom_minimum_size.x = 96
	header.add_child(slot_title)
	header.add_child(UI.spacer())
	summary_label = UI.label("0 / 11 已配置", "Muted")
	summary_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	summary_label.custom_minimum_size.x = 110
	summary_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header.add_child(summary_label)
	slot_toggle = UI.button("‹", _toggle_slot_dock)
	slot_toggle.name = "M1ToggleSlotDock"
	slot_toggle.custom_minimum_size = Vector2(34, 34)
	slot_toggle.tooltip_text = "折叠虫巢槽位"
	slot_toggle.focus_mode = Control.FOCUS_ALL
	header.add_child(slot_toggle)
	slot_grid = GridContainer.new()
	slot_grid.columns = 4
	slot_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slot_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	slot_grid.add_theme_constant_override("h_separation", 5)
	slot_grid.add_theme_constant_override("v_separation", 5)
	box.add_child(slot_grid)
	for index in range(12):
		var button := Button.new()
		button.name = "M1RoomSlot_%02d" % (index + 1)
		button.focus_mode = Control.FOCUS_ALL
		button.clip_text = true
		button.custom_minimum_size = Vector2(72, 38)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.size_flags_vertical = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 14)
		button.pressed.connect(_select_slot.bind(index))
		slot_grid.add_child(button)
		slot_buttons.append(button)

func _build_detail_panel() -> void:
	detail_panel = PanelContainer.new()
	detail_panel.name = "M1HiveDetailPanel"
	detail_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	detail_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(detail_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	detail_panel.add_child(box)
	var header := HBoxContainer.new()
	box.add_child(header)
	detail_title = UI.label("槽位详情", "Section")
	detail_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(detail_title)
	detail_toggle = UI.button("›", _toggle_detail_dock)
	detail_toggle.name = "M1ToggleDetailDock"
	detail_toggle.custom_minimum_size = Vector2(34, 34)
	detail_toggle.tooltip_text = "折叠槽位详情"
	detail_toggle.focus_mode = Control.FOCUS_ALL
	header.add_child(detail_toggle)
	detail_margin = MarginContainer.new()
	detail_margin.add_theme_constant_override("margin_left", 10)
	detail_margin.add_theme_constant_override("margin_right", 10)
	detail_margin.add_theme_constant_override("margin_bottom", 8)
	detail_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(detail_margin)
	var scroll := ScrollContainer.new()
	scroll.name = "M1HiveDetailScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_margin.add_child(scroll)
	detail = VBoxContainer.new()
	detail.name = "M1HiveRoomDetail"
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.add_theme_constant_override("separation", 5)
	scroll.add_child(detail)

func _toggle_slot_dock() -> void:
	slot_expanded = not slot_expanded
	_apply_dock_state()

func _toggle_detail_dock() -> void:
	detail_expanded = not detail_expanded
	_apply_dock_state()

func _apply_dock_state() -> void:
	if not is_instance_valid(slot_panel) or not is_instance_valid(detail_panel):
		return
	slot_panel.custom_minimum_size.x = 336.0 if slot_expanded else 44.0
	detail_panel.custom_minimum_size.x = 284.0 if detail_expanded else 44.0
	slot_title.visible = slot_expanded
	summary_label.visible = slot_expanded
	slot_grid.visible = slot_expanded
	detail_title.visible = detail_expanded
	detail_margin.visible = detail_expanded
	slot_toggle.text = "‹" if slot_expanded else "›"
	slot_toggle.tooltip_text = "折叠虫巢槽位" if slot_expanded else "展开虫巢槽位"
	detail_toggle.text = "›" if detail_expanded else "‹"
	detail_toggle.tooltip_text = "折叠槽位详情" if detail_expanded else "展开槽位详情"

func _refresh_slots() -> void:
	var configured := 0
	for index in range(mini(slot_buttons.size(), snapshot.rooms.size())):
		var room: Dictionary = snapshot.rooms[index]
		var kind := String(room.get("kind", ""))
		if kind not in ["", "core"]:
			configured += 1
		var label := "空槽"
		if kind == "core":
			label = "核心巢室"
		elif not kind.is_empty() and room_definitions.has(kind):
			label = String(room_definitions[kind].name)
		var button := slot_buttons[index]
		button.text = "%02d · %s" % [index + 1, label]
		button.tooltip_text = "%s；%s" % [label, _room_status(room)]
		button.theme_type_variation = "NavActiveButton" if index == selected_slot else "NavButton"
	summary_label.text = "%d / 11 已配置" % configured

func _select_slot(index: int) -> void:
	selected_slot = clampi(index, 0, 11)
	_refresh_slots()
	_rebuild_detail()

func _rebuild_detail() -> void:
	UI.clear(detail)
	if snapshot.is_empty() or selected_slot < 0 or selected_slot >= snapshot.rooms.size():
		return
	var room: Dictionary = snapshot.rooms[selected_slot]
	var kind := String(room.get("kind", ""))
	if kind.is_empty():
		_build_empty_detail()
	else:
		_build_room_detail(room)

func _build_empty_detail() -> void:
	detail.add_child(UI.label("自由空槽 %02d" % (selected_slot + 1), "Section"))
	detail.add_child(UI.label("选择已发现蓝图；投入、构筑和取消均由权威规则结算。", "Muted"))
	for kind in ROOM_ORDER:
		var definition: Dictionary = room_definitions.get(kind, {})
		var unlocked := bool(unlocked_rooms.get(kind, false))
		var button := UI.button("%s · %d 生物质" % [String(definition.get("name", kind)), int(definition.get("cost", 0))], _request_build.bind(kind), "PrimaryButton" if unlocked else "")
		button.name = "M1Build_%s" % kind
		button.custom_minimum_size.y = 34
		button.disabled = not unlocked or float(snapshot.resources.biomass) < float(definition.get("cost", 0))
		button.tooltip_text = "蓝图尚未发现" if not unlocked else "在槽位 %02d 构筑" % (selected_slot + 1)
		detail.add_child(button)

func _build_room_detail(room: Dictionary) -> void:
	var kind := String(room.get("kind", ""))
	var room_name := "核心巢室" if kind == "core" else String((room_definitions.get(kind, {}) as Dictionary).get("name", kind))
	detail.add_child(UI.label(room_name, "Section"))
	detail.add_child(UI.label("槽位 %02d · %s" % [selected_slot + 1, _room_status(room)], "Muted"))
	if kind == "core":
		_add_energy_summary()
		return
	if String(room.get("state", "")) == "building":
		detail.add_child(UI.progress(float(room.get("progress", 0.0)) * 100.0))
		detail.add_child(UI.label("构筑进度 %d%%" % int(float(room.get("progress", 0.0)) * 100.0), "Muted"))
		var cancel := UI.button("取消建设并释放预留", _request_simple.bind("cancel_room"), "DangerButton")
		cancel.name = "M1CancelRoom"
		detail.add_child(cancel)
		return
	if kind == "embryo_hatchery":
		_add_target_controls()
	elif kind == "thermal_metabolism":
		_add_energy_summary()
	elif kind == "digestive_pool":
		detail.add_child(UI.label("待处理残骸 %.0f · 样本 %.0f" % [snapshot.processing.secured_carcass, snapshot.processing.secured_sample]))
	elif kind == "synapse_analyzer":
		detail.add_child(UI.label("待解析样本组织 %.0f" % snapshot.processing.sample_tissue))
	elif kind == "mutation_culture":
		var culture := UI.button("培养普通候选组 · 18 生物质", _request_simple.bind("culture_candidate"), "PrimaryButton")
		culture.name = "M1CultureCandidate"
		culture.disabled = not snapshot.candidate_group.is_empty() or float(snapshot.resources.biomass) < 18.0
		detail.add_child(culture)
	detail.add_child(UI.separator())
	var pause := UI.button("恢复运行" if bool(room.get("paused", false)) else "暂停房间", _request_pause.bind(not bool(room.get("paused", false))))
	pause.name = "M1ToggleRoomPause"
	detail.add_child(pause)
	var demolish := UI.button("拆除并回收结构投入", _request_simple.bind("demolish_room"), "DangerButton")
	demolish.name = "M1DemolishRoom"
	detail.add_child(demolish)

func _add_target_controls() -> void:
	detail.add_child(UI.label("自动孵化目标", "Section"))
	var minimal := UI.button("最小出征编组 · 1 噬咬体", _request_minimal_formation, "PrimaryButton")
	minimal.name = "M1Target_MinimalFormation"
	minimal.tooltip_text = "将工蜂、噬咬体、根脉孢体目标设为 0 / 1 / 0；孵化仍按正常房间规则推进。"
	detail.add_child(minimal)
	for kind in UNIT_ORDER:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		var unit_name := UI.label(String((unit_definitions.get(kind, {}) as Dictionary).get("name", kind)))
		unit_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(unit_name)
		var minus := UI.button("−", _request_target.bind(kind, -1))
		minus.name = "M1Target_%s_Minus" % kind
		minus.custom_minimum_size.x = 38
		minus.disabled = int(snapshot.targets.get(kind, 0)) <= 0
		row.add_child(minus)
		var value := UI.label(str(snapshot.targets.get(kind, 0)), "Metric")
		value.custom_minimum_size.x = 34
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_child(value)
		var plus := UI.button("+", _request_target.bind(kind, 1))
		plus.name = "M1Target_%s_Plus" % kind
		plus.custom_minimum_size.x = 38
		row.add_child(plus)
		detail.add_child(row)
	detail.add_child(UI.label("工蜂 → 噬咬体 → 根脉孢体；仅补齐目标缺口。", "Muted"))

func _add_energy_summary() -> void:
	detail.add_child(UI.label("供给 %.1f · 任务负载 %.1f · 净变化 %+.1f" % [snapshot.energy.supply, snapshot.energy.task_load, snapshot.energy.net]))
	detail.add_child(UI.progress(float(snapshot.resources.energy), float(snapshot.energy.capacity)))
	detail.add_child(UI.label("储能 %.0f / %.0f" % [snapshot.resources.energy, snapshot.energy.capacity], "Muted"))

func _request_build(kind: String) -> void:
	command_requested.emit("build_room", {"slot": selected_slot, "kind": kind})

func _request_simple(command: String) -> void:
	command_requested.emit(command, {"slot": selected_slot})

func _request_pause(value: bool) -> void:
	command_requested.emit("set_room_paused", {"slot": selected_slot, "value": value})

func _request_target(kind: String, delta: int) -> void:
	command_requested.emit("set_unit_target", {"kind": kind, "delta": delta})

func _request_minimal_formation() -> void:
	command_requested.emit("set_unit_targets", {"targets": {"worker": 0, "biter": 1, "root_spore": 0}})

func _room_status(room: Dictionary) -> String:
	if String(room.get("state", "")) == "building":
		return "构筑中"
	if bool(room.get("paused", false)):
		return "已暂停"
	return "运行中"
