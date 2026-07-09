extends Control

const BattlefieldViewScript := preload("res://scripts/ui/BattlefieldView.gd")
const BattleCommandPanelScript := preload("res://scripts/ui/BattleCommandPanel.gd")
const PlayerCommandServiceScript := preload("res://scripts/services/PlayerCommandService.gd")

var ConfigDB
var GameState
var SaveService
var SimulationService
var _command_service
var _resource_label: Label
var _guide_label: Label
var _feedback_label: Label
var _offline_label: Label
var _prestige_label: Label
var _prestige_button: Button
var _organ_buttons: Dictionary = {}
var _unit_buttons: Dictionary = {}
var _unit_batch_buttons: Dictionary = {}
var _deploy_buttons: Dictionary = {}
var _region_buttons: Dictionary = {}
var _plugin_buttons: Dictionary = {}
var _field_label: Label
var _battle_progress: ProgressBar
var _battle_status_strip: ColorRect
var _battle_flow_label: Label
var _battle_unit_markers: Array[ColorRect] = []
var _battlefield_view
var _battle_command_label: Label

func _enter_tree() -> void:
	_bind_dependencies()

func _ready() -> void:
	_bind_dependencies()
	_build_ui()
	GameState.state_changed.connect(_refresh)
	GameState.feedback_changed.connect(func(_message: String) -> void: _refresh())
	GameState.offline_report_ready.connect(func(_report: Dictionary) -> void: _refresh())
	_refresh()

func _bind_dependencies() -> void:
	if get_tree() == null:
		return
	var root := get_tree().root
	if ConfigDB == null and root.has_node("ConfigDB"):
		ConfigDB = root.get_node("ConfigDB")
	if GameState == null and root.has_node("GameState"):
		GameState = root.get_node("GameState")
	if SaveService == null and root.has_node("SaveService"):
		SaveService = root.get_node("SaveService")
	if SimulationService == null and root.has_node("SimulationService"):
		SimulationService = root.get_node("SimulationService")
	_ensure_command_service()

func _ensure_command_service() -> void:
	if ConfigDB == null or GameState == null or SaveService == null or SimulationService == null:
		return
	if _command_service == null:
		_command_service = PlayerCommandServiceScript.new()
	_command_service.configure(ConfigDB, GameState, SaveService, SimulationService)

func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("save_game"):
		_save_now()
	if Input.is_action_just_pressed("retreat_battle"):
		_ensure_command_service()
		_command_service.retreat()
	if Input.is_action_just_pressed("deploy_primary"):
		_cycle_deployment("zergling")

func _build_ui() -> void:
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 14)
	scroll.add_child(margin)

	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)

	var title := Label.new()
	title.text = "异种起源：无尽洪流"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 25)
	root.add_child(title)

	var promise := Label.new()
	promise.text = "孵化虫群，撕开人类防线，吞噬城市边缘。"
	promise.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	promise.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(promise)

	_guide_label = _make_label("")
	_guide_label.add_theme_color_override("font_color", Color(0.70, 0.88, 1.0))
	root.add_child(_guide_label)

	_resource_label = _make_label("")
	_resource_label.add_theme_font_size_override("font_size", 18)
	root.add_child(_resource_label)

	_battlefield_view = BattlefieldViewScript.new()
	_battlefield_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_battlefield_view.command_requested.connect(_on_battlefield_command)
	root.add_child(_battlefield_view)

	_battle_command_label = _make_label("")
	_battle_command_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_battle_command_label.add_theme_color_override("font_color", Color(0.62, 0.78, 0.82))
	root.add_child(_battle_command_label)

	var command_row = BattleCommandPanelScript.new()
	command_row.command_requested.connect(_on_battlefield_command)
	root.add_child(command_row)

	_feedback_label = _make_label("")
	_feedback_label.add_theme_color_override("font_color", Color(0.90, 0.96, 0.78))
	root.add_child(_feedback_label)

	_offline_label = _make_label("")
	root.add_child(_offline_label)

	_add_section(root, "虫巢器官")
	for organ_id in _organ_ids():
		var button := _make_button("")
		button.pressed.connect(func(id: String = organ_id) -> void:
			_ensure_command_service()
			_command_service.purchase_organ(id)
		)
		_organ_buttons[organ_id] = button
		root.add_child(button)

	_add_section(root, "孵化与储备")
	for unit_id in _unit_ids():
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var hatch_one := _make_button("")
		hatch_one.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hatch_one.pressed.connect(func(id: String = unit_id) -> void:
			_ensure_command_service()
			_command_service.hatch_unit(id, 1)
		)
		var hatch_batch := _make_button("x5")
		hatch_batch.custom_minimum_size = Vector2(68, 48)
		hatch_batch.pressed.connect(func(id: String = unit_id) -> void:
			_ensure_command_service()
			_command_service.hatch_unit(id, 5)
		)
		_unit_buttons[unit_id] = hatch_one
		_unit_batch_buttons[unit_id] = hatch_batch
		row.add_child(hatch_one)
		row.add_child(hatch_batch)
		root.add_child(row)

	_add_section(root, "区域与战斗")
	for region_id in _region_ids():
		var button := _make_button("")
		button.pressed.connect(func(id: String = region_id) -> void:
			_ensure_command_service()
			_command_service.select_region(id)
		)
		_region_buttons[region_id] = button
		root.add_child(button)

	_field_label = _make_label("")
	root.add_child(_field_label)
	_add_battle_visuals(root)

	for unit_id in _unit_ids():
		var button := _make_button("")
		button.pressed.connect(func(id: String = unit_id) -> void:
			_cycle_deployment(id)
		)
		_deploy_buttons[unit_id] = button
		root.add_child(button)

	var retreat_button := _make_button("撤离战场：保留 75% 场上兵力并关闭投放")
	retreat_button.pressed.connect(func() -> void:
		_ensure_command_service()
		_command_service.retreat()
	)
	root.add_child(retreat_button)

	_add_section(root, "构筑插件")
	for plugin_id in _plugin_ids():
		var button := _make_button("")
		button.pressed.connect(func(id: String = plugin_id) -> void:
			_ensure_command_service()
			_command_service.buy_or_equip_plugin(id)
		)
		_plugin_buttons[plugin_id] = button
		root.add_child(button)

	_add_section(root, "吞噬世界")
	_prestige_label = _make_label("")
	root.add_child(_prestige_label)
	_prestige_button = _make_button("执行吞噬世界重置")
	_prestige_button.pressed.connect(func() -> void:
		_ensure_command_service()
		_command_service.perform_prestige()
	)
	root.add_child(_prestige_button)

	_add_section(root, "存档")
	var save_row := HBoxContainer.new()
	var save_button := _make_button("保存")
	save_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_button.pressed.connect(_save_now)
	var load_button := _make_button("读取")
	load_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	load_button.pressed.connect(func() -> void:
		_ensure_command_service()
		_command_service.load_and_settle()
	)
	save_row.add_child(save_button)
	save_row.add_child(load_button)
	root.add_child(save_row)

	var new_button := _make_button("新存档重开（保留 0 突变原）")
	new_button.pressed.connect(func() -> void:
		_ensure_command_service()
		_command_service.new_game_and_save()
	)
	root.add_child(new_button)

func _refresh() -> void:
	GameState.ensure_config_defaults()
	var battle_snapshot: Dictionary = _battlefield_snapshot()
	_resource_label.text = "有机原浆 %.0f   活性酶 %.1f   螺旋序列 %.1f\n幼虫 %.1f   突变原 %.0f   总吞噬 %.1f%%" % [
		GameState.resources.get("pulp", 0.0),
		GameState.resources.get("enzyme", 0.0),
		GameState.resources.get("helix", 0.0),
		GameState.resources.get("larva", 0.0),
		GameState.resources.get("mutation", 0.0),
		GameState.total_devour
	]
	_guide_label.text = _next_step_text()
	_feedback_label.text = "反馈：%s" % _display_feedback(battle_snapshot)
	_offline_label.text = _offline_text()
	_field_label.text = _battle_text()
	_refresh_battlefield(battle_snapshot)
	_refresh_battle_visuals(battle_snapshot)
	_refresh_organs()
	_refresh_units()
	_refresh_regions()
	_refresh_deployments()
	_refresh_plugins()
	_refresh_prestige()

func _refresh_organs() -> void:
	for organ_id in _organ_buttons.keys():
		var organ = ConfigDB.get_organ(organ_id)
		var button: Button = _organ_buttons[organ_id]
		var level := int(GameState.organ_levels.get(organ_id, 0))
		var cost: float = organ.cost_for_level(level)
		var costs: Dictionary = {organ.cost_resource: cost}
		var rate: float = organ.rate_for_level(level, GameState.mutation_multiplier())
		var next_rate: float = organ.rate_for_level(level + 1, GameState.mutation_multiplier())
		button.disabled = not GameState.can_spend(costs)
		button.text = "%s Lv.%d  %.2f/s -> %.2f/s\n升级成本：%.0f %s%s" % [
			organ.display_name,
			level,
			rate,
			next_rate,
			cost,
			_resource_name(organ.cost_resource),
			"" if not button.disabled else "\n还差：%s" % _missing_cost_text(costs)
		]

func _refresh_units() -> void:
	for unit_id in _unit_buttons.keys():
		var unit = ConfigDB.get_unit(unit_id)
		var button: Button = _unit_buttons[unit_id]
		var batch_button: Button = _unit_batch_buttons[unit_id]
		var unlocked: bool = _unit_unlocked(unit)
		var reserve := int(GameState.reserves.get(unit_id, 0))
		var field := int(GameState.field_units.get(unit_id, 0))
		var single_costs: Dictionary = unit.resource_costs()
		var batch_costs: Dictionary = _scaled_costs(single_costs, 5.0)
		button.disabled = not unlocked or not GameState.can_spend(single_costs)
		batch_button.disabled = not unlocked or not GameState.can_spend(batch_costs)
		var shortage_text: String = ""
		if not unlocked:
			shortage_text = "\n未解锁：总吞噬 %.0f%%；%s" % [unit.unlock_devour, _unit_role_tag(unit_id)]
		elif button.disabled:
			shortage_text = "\n还差：%s\n恢复：暂停升级，等自动产出补足后再孵化。" % _missing_cost_text(single_costs)
		button.text = "孵化%s  储备 %d / 场上 %d\n标签：%s\n成本：原浆 %.0f 酶 %.0f 螺旋 %.0f 幼虫 %d\n用途：%s%s" % [
			unit.display_name,
			reserve,
			field,
			_unit_role_tag(unit_id),
			unit.pulp_cost,
			unit.enzyme_cost,
			unit.helix_cost,
			unit.larva_cost,
			unit.description,
			shortage_text
		]
		batch_button.text = "x5" if not batch_button.disabled else "x5\n未解锁" if not unlocked else "x5\n缺资源\n先等补足"

func _refresh_regions() -> void:
	for region_id in _region_buttons.keys():
		var region = ConfigDB.get_region(region_id)
		var button: Button = _region_buttons[region_id]
		var unlocked := bool(GameState.region_unlocked.get(region_id, false))
		var selected: bool = GameState.active_region == region_id
		button.text = "%s%s  吞噬 %.1f%%\n%s\n敌压 %.0f：%s" % [
			"目标：" if selected else "",
			region.display_name,
			GameState.region_progress.get(region_id, 0.0),
			region.description if unlocked else "未解锁：需要总吞噬 %.0f%%" % region.unlock_at_devour,
			region.enemy_pressure,
			_region_enemy_summary(region)
		]
		button.disabled = not unlocked

func _refresh_deployments() -> void:
	for unit_id in _deploy_buttons.keys():
		var unit = ConfigDB.get_unit(unit_id)
		var button: Button = _deploy_buttons[unit_id]
		var unlocked: bool = _unit_unlocked(unit)
		var intensity := int(GameState.deployment_intensity.get(unit_id, 0))
		button.disabled = not unlocked or (int(GameState.reserves.get(unit_id, 0)) <= 0 and intensity <= 0)
		button.text = "%s投放强度：%d\n%s" % [
			unit.display_name,
			intensity,
			"未解锁：需要总吞噬 %.0f%%。" % unit.unlock_devour if not unlocked else "先孵化储备，才可打开投放；若刚升级过早，请等孵化按钮还差项归零。" if button.disabled else "点击循环 0/1/2/3，持续扣储备进入战场"
		]

func _refresh_plugins() -> void:
	for plugin_id in _plugin_buttons.keys():
		var plugin = ConfigDB.get_plugin(plugin_id)
		var button: Button = _plugin_buttons[plugin_id]
		var owned := bool(GameState.plugins_owned.get(plugin_id, false))
		var equipped: bool = GameState.equipped_plugin == plugin_id
		var costs: Dictionary = {"helix": plugin.cost_helix}
		button.disabled = (not owned and not GameState.can_spend(costs)) or GameState.total_devour < plugin.unlock_devour
		var lock_text := ""
		if GameState.total_devour < plugin.unlock_devour:
			lock_text = "\n未解锁：需要总吞噬 %.0f%%" % plugin.unlock_devour
		elif not owned and button.disabled:
			lock_text = "\n还差：%s" % _missing_cost_text(costs)
		button.text = "%s%s%s\n%s\n成本：%.0f 螺旋序列%s" % [
			"已装配：" if equipped else "",
			plugin.display_name,
			"（已拥有）" if owned else "",
			plugin.description,
			plugin.cost_helix,
			lock_text
		]

func _refresh_prestige() -> void:
	var preview: Dictionary = SimulationService.prestige_preview()
	var can_reset: bool = bool(preview["can_reset"])
	var reset_state: String = "状态：可重置，点击按钮会立刻重开。" if can_reset else "状态：不可重置，按钮已锁定；继续推进区域或积累螺旋。"
	_prestige_label.text = "预览：本次可获得突变原 %d；当前 %d；重开后生产倍率 %.2fx。\n%s" % [
		preview["gain"],
		preview["current"],
		preview["next_multiplier"],
		reset_state
	]
	_prestige_button.disabled = not can_reset
	_prestige_button.text = "可重置：获得 %d 突变原" % int(preview["gain"]) if can_reset else "不可重置：收益 0，继续推进"
	_prestige_button.tooltip_text = "点击后保存并重开本轮。" if can_reset else "区域进度或螺旋不足时不会允许重置。"

func _cycle_deployment(unit_id: String) -> void:
	var current := int(GameState.deployment_intensity.get(unit_id, 0))
	var next: int = 0 if current >= 3 else current + 1
	_ensure_command_service()
	_command_service.set_deployment(unit_id, next)

func _save_now() -> void:
	_ensure_command_service()
	_command_service.save_now()

func _battle_text() -> String:
	var active = ConfigDB.get_region(GameState.active_region)
	var lines: Array[String] = ["当前战场：%s" % active.display_name]
	for unit_id in _unit_ids():
		var unit = ConfigDB.get_unit(unit_id)
		lines.append("%s 储备 %d / 场上 %d / 投放 %d" % [
			unit.display_name,
			GameState.reserves.get(unit_id, 0),
			GameState.field_units.get(unit_id, 0),
			GameState.deployment_intensity.get(unit_id, 0)
		])
	return "\n".join(lines)

func _refresh_battlefield(snapshot: Dictionary) -> void:
	if _battlefield_view == null:
		return
	_battlefield_view.set_snapshot(snapshot)
	if String(snapshot.get("mode", "")) == "complete" and String(snapshot.get("next_region_id", "")) != "":
		_battle_command_label.text = "战场操作：点击战场切换下一防线。"
	elif GameState.active_region == "factory_wall":
		_battle_command_label.text = "战场操作：左蓄兵补刺蛇首波，中强攻推进，右撤离保全。"
	else:
		_battle_command_label.text = "战场操作：左蓄兵攒波次，中强攻推进，右撤离保全。"

func _battlefield_snapshot() -> Dictionary:
	var active = ConfigDB.get_region(GameState.active_region)
	var report: Dictionary = GameState.battle_report
	var unit_id: String = _preferred_assault_unit()
	var projection_unit = ConfigDB.get_unit(unit_id)
	var projection: Dictionary = SimulationService.battle_projection(unit_id)
	var report_mode: String = String(report.get("mode", "idle"))
	var active_progress: float = float(GameState.region_progress.get(GameState.active_region, 0.0))
	var next_region_id: String = _next_region_id(active)
	var next_region_name: String = _region_display_name(next_region_id)
	var region_complete: bool = active_progress >= 100.0
	var power: float = float(report.get("power", 0.0))
	var pressure: float = float(report.get("pressure", 0.0))
	if pressure <= 0.0 and active != null and report_mode != "idle" and report_mode != "retreat":
		pressure = float(projection.get("effective_pressure", active.enemy_pressure))
	var projection_needed: int = int(projection.get("needed_reserve", 0))
	var live_ready: int = int(projection.get("prepared_reserve", int(GameState.reserves.get(unit_id, 0)) + int(GameState.field_units.get(unit_id, 0))))
	var live_shortfall: int = int(projection.get("reserve_shortfall", 0))
	var live_hatch_fill_count: int = int(projection.get("hatch_fill_count", 0))
	var live_hatch_missing_text: String = String(projection.get("hatch_missing_text", ""))
	if projection_needed > 0 and live_ready >= projection_needed:
		live_shortfall = 0
		live_hatch_fill_count = 0
		live_hatch_missing_text = ""
	var live_retreat_value: int = int(projection.get("retreat_value", 0))
	var live_retreat_field: int = int(projection.get("retreat_field_before", 0))
	var returned: int = int(report.get("returned", 0))
	var report_retreat_field: int = int(report.get("retreat_field_before", 0))
	var active_intensity: int = int(GameState.deployment_intensity.get(unit_id, 0))
	var unit_fields: Dictionary = _unit_field_counts()
	var field_total: int = _unit_count_total(unit_fields)
	var display_mode: String = _battle_display_mode(report_mode, live_shortfall, live_ready, projection_needed, active_intensity, live_retreat_field)
	if region_complete:
		display_mode = "complete"
		returned = 0
		live_retreat_value = 0
		live_retreat_field = 0
		report_retreat_field = 0
	return {
		"region_name": active.display_name if active != null else GameState.active_region,
		"progress": active_progress,
		"mode": display_mode,
		"report_mode": report_mode,
		"projection_unit_id": unit_id,
		"projection_unit_name": projection_unit.display_name if projection_unit != null else unit_id,
		"region_complete": region_complete,
		"next_region_id": next_region_id,
		"next_region_name": next_region_name,
		"next_region_unlocked": next_region_id != "" and bool(GameState.region_unlocked.get(next_region_id, false)),
		"power": power,
		"pressure": pressure,
		"reinforced": int(report.get("reinforced", 0)),
		"lost": int(report.get("lost", 0)),
		"field_total": field_total,
		"unit_fields": unit_fields,
		"zergling_field": int(GameState.field_units.get("zergling", 0)),
		"hydralisk_field": int(GameState.field_units.get("hydralisk", 0)),
		"zergling_reserve": int(GameState.reserves.get("zergling", 0)),
		"hydralisk_reserve": int(GameState.reserves.get("hydralisk", 0)),
		"zergling_intensity": int(GameState.deployment_intensity.get("zergling", 0)),
		"hydralisk_intensity": int(GameState.deployment_intensity.get("hydralisk", 0)),
		"unit_readout_text": _unit_readout_text(),
		"plugin_name": _equipped_plugin_name(),
		"returned": returned,
		"loss_reason": String(report.get("loss_reason", "")),
		"front_motion": String(report.get("front_motion", "none")),
		"progress_gain": float(report.get("progress_gain", 0.0)),
		"prepared_reserve": live_ready,
		"needed_reserve": projection_needed,
		"action": String(report.get("action", "")),
		"cause": "ready_wave" if live_shortfall <= 0 and projection_needed > 0 else String(report.get("cause", "")),
		"base_pressure": float(projection.get("base_pressure", report.get("base_pressure", pressure))),
		"effective_pressure": float(projection.get("effective_pressure", report.get("effective_pressure", pressure))),
		"support_bonus": float(projection.get("support_bonus", report.get("support_bonus", 0.0))),
		"plugin_bonus": float(projection.get("plugin_bonus", report.get("plugin_bonus", 0.0))),
		"projection_needed_reserve": projection_needed,
		"baseline_needed_reserve": int(projection.get("baseline_needed_reserve", report.get("baseline_needed_reserve", 0))),
		"reserve_shortfall": live_shortfall,
		"hatch_fill_count": live_hatch_fill_count,
		"hatch_missing_text": live_hatch_missing_text,
		"pressure_drop": float(projection.get("pressure_drop", report.get("pressure_drop", 0.0))),
		"loss_rate": float(projection.get("loss_rate", report.get("loss_rate", 0.0))),
		"baseline_loss_rate": float(projection.get("baseline_loss_rate", report.get("baseline_loss_rate", 0.0))),
		"loss_reduction": float(projection.get("loss_reduction", report.get("loss_reduction", 0.0))),
		"loss_saved_estimate": int(projection.get("loss_saved_estimate", report.get("loss_saved_estimate", 0))),
		"protected_estimate": int(projection.get("protected_estimate", report.get("protected_estimate", 0))),
		"acid_preview_loss_saved": int(projection.get("acid_preview_loss_saved", report.get("acid_preview_loss_saved", 0))),
		"acid_preview_protected": int(projection.get("acid_preview_protected", report.get("acid_preview_protected", 0))),
		"retreat_value": returned if returned > 0 else live_retreat_value,
		"retreat_field_before": report_retreat_field if returned > 0 else live_retreat_field,
		"preserved_loss_estimate": int(report.get("preserved_loss_estimate", projection.get("preserved_loss_estimate", 0))) if returned > 0 else int(projection.get("preserved_loss_estimate", 0)),
		"next_target": float(projection.get("next_target", report.get("next_target", 4.0))),
		"prestige_gain": int(projection.get("prestige_gain", report.get("prestige_gain", 0))),
		"prestige_ready": bool(projection.get("prestige_ready", report.get("prestige_ready", false)))
	}

func _unit_field_counts() -> Dictionary:
	var counts: Dictionary = {}
	for id in _unit_ids():
		var count := int(GameState.field_units.get(id, 0))
		if count > 0:
			counts[id] = count
	return counts

func _unit_count_total(counts: Dictionary) -> int:
	var total := 0
	for id in counts.keys():
		total += int(counts.get(id, 0))
	return total

func _battle_display_mode(report_mode: String, live_shortfall: int, live_ready: int, projection_needed: int, active_intensity: int, live_retreat_field: int) -> String:
	if projection_needed > 0 and live_ready >= projection_needed and live_shortfall <= 0:
		if report_mode == "understrength" or report_mode == "preparing":
			if active_intensity > 0 or live_retreat_field > 0:
				return "committed"
			return "ready"
	return report_mode

func _display_feedback(snapshot: Dictionary) -> String:
	if String(snapshot.get("mode", "")) == "complete":
		var next_name: String = String(snapshot.get("next_region_name", ""))
		if next_name != "":
			return "已吞噬当前防线：点击战场切换%s。" % next_name
		return "已吞噬当前防线：继续查看重置或新目标。"
	var message: String = GameState.feedback
	if _snapshot_wave_ready(snapshot) and _is_shortage_feedback(message):
		return "波次已备：储备 %d/%d，可强攻；额外孵化只影响后续补兵。" % [
			int(snapshot.get("prepared_reserve", 0)),
			int(snapshot.get("needed_reserve", 0))
		]
	return message

func _snapshot_wave_ready(snapshot: Dictionary) -> bool:
	var needed: int = int(snapshot.get("needed_reserve", 0))
	if needed <= 0:
		return false
	return int(snapshot.get("prepared_reserve", 0)) >= needed and int(snapshot.get("reserve_shortfall", 0)) <= 0

func _is_shortage_feedback(message: String) -> bool:
	return message.find("规模") >= 0 or message.find("还差") >= 0 or message.find("不足") >= 0 or message.find("缺幼虫") >= 0 or message.find("缺资源") >= 0

func _on_battlefield_command(action: String) -> void:
	_ensure_command_service()
	match action:
		"next_region":
			var next_region_id: String = _next_region_id(ConfigDB.get_region(GameState.active_region))
			if next_region_id != "":
				_command_service.select_region(next_region_id)
		"prepare":
			_command_service.prepare_wave(_preferred_prepare_unit())
		"assault":
			_command_service.assault_push(_preferred_assault_unit())
		"zergling":
			_command_service.prepare_wave("zergling")
		"hydralisk":
			_command_service.assault_push("hydralisk")
		"retreat":
			_command_service.retreat()
	if _resource_label != null:
		_refresh()

func _next_region_id(region) -> String:
	if region == null:
		return ""
	var next_region_id: String = String(region.next_region)
	if next_region_id == "":
		return ""
	if bool(GameState.region_unlocked.get(next_region_id, false)):
		return next_region_id
	return ""

func _region_display_name(region_id: String) -> String:
	if region_id == "":
		return ""
	var region = ConfigDB.get_region(region_id)
	return region.display_name if region != null else region_id

func _preferred_assault_unit() -> String:
	if GameState.active_region == "factory_wall":
		var hydralisk = ConfigDB.get_unit("hydralisk")
		var hydralisk_ready: bool = _projection_ready("hydralisk")
		if hydralisk_ready:
			return "hydralisk"
		var hydralisk_available: int = int(GameState.reserves.get("hydralisk", 0)) + int(GameState.field_units.get("hydralisk", 0))
		if hydralisk_available > 0 or _factory_hydralisk_plan_active() or (hydralisk != null and GameState.can_spend(hydralisk.resource_costs())):
			return "hydralisk"
	if GameState.active_region == "research_bastion":
		for unit_id in ["baneling", "carapace_guard"]:
			if _projection_ready(unit_id) or _unit_actionable(unit_id):
				return unit_id
		return "baneling"
	if GameState.active_region == "chitin_pass":
		for unit_id in ["roach", "carapace_guard", "hydralisk"]:
			if _projection_ready(unit_id) or _unit_actionable(unit_id):
				return unit_id
		return "roach"
	if GameState.active_region == "orbital_relay":
		for unit_id in ["mutalisk", "baneling", "roach"]:
			if _projection_ready(unit_id) or _unit_actionable(unit_id):
				return unit_id
		return "mutalisk"
	return "zergling"

func _preferred_prepare_unit() -> String:
	if GameState.active_region == "factory_wall" and _factory_hydralisk_plan_active():
		return "hydralisk"
	return _preferred_assault_unit()

func _factory_hydralisk_plan_active() -> bool:
	if GameState.active_region != "factory_wall":
		return false
	return bool(GameState.region_entry_staged.get("factory_wall", false)) or GameState.equipped_plugin == "piercing_spines" or bool(GameState.plugins_owned.get("piercing_spines", false))

func _unit_actionable(unit_id: String) -> bool:
	var unit = ConfigDB.get_unit(unit_id)
	if unit == null or not _unit_unlocked(unit):
		return false
	return int(GameState.reserves.get(unit_id, 0)) + int(GameState.field_units.get(unit_id, 0)) > 0 or GameState.can_spend(unit.resource_costs())

func _projection_ready(unit_id: String) -> bool:
	var projection: Dictionary = SimulationService.battle_projection(unit_id)
	var needed: int = int(projection.get("needed_reserve", 0))
	if needed <= 0:
		return false
	return int(projection.get("prepared_reserve", 0)) >= needed and int(projection.get("reserve_shortfall", 0)) <= 0

func _command_unit(unit_id: String) -> void:
	var reserve: int = int(GameState.reserves.get(unit_id, 0))
	if reserve <= 0:
		_ensure_command_service()
		if _command_service.hatch_unit(unit_id, 1):
			_command_service.set_deployment(unit_id, 1)
		return
	var current: int = int(GameState.deployment_intensity.get(unit_id, 0))
	var next: int = clampi(current + 1, 1, 3)
	if current >= 3:
		next = 0
	_ensure_command_service()
	_command_service.set_deployment(unit_id, next)

func _equipped_plugin_name() -> String:
	if GameState.equipped_plugin == "":
		return ""
	var plugin = ConfigDB.get_plugin(GameState.equipped_plugin)
	return plugin.display_name if plugin != null else GameState.equipped_plugin

func _add_battle_visuals(parent: VBoxContainer) -> void:
	_battle_progress = ProgressBar.new()
	_battle_progress.min_value = 0.0
	_battle_progress.max_value = 100.0
	_battle_progress.show_percentage = true
	_battle_progress.custom_minimum_size = Vector2(0, 24)
	_battle_progress.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(_battle_progress)

	var status_row := HBoxContainer.new()
	status_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_battle_status_strip = ColorRect.new()
	_battle_status_strip.color = Color(0.30, 0.32, 0.35)
	_battle_status_strip.custom_minimum_size = Vector2(48, 20)
	status_row.add_child(_battle_status_strip)
	_battle_flow_label = _make_label("")
	_battle_flow_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_row.add_child(_battle_flow_label)
	parent.add_child(status_row)

	var unit_row := HBoxContainer.new()
	unit_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	unit_row.add_theme_constant_override("separation", 4)
	for i in range(12):
		var marker := ColorRect.new()
		marker.color = Color(0.16, 0.17, 0.19)
		marker.custom_minimum_size = Vector2(18, 12)
		marker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_battle_unit_markers.append(marker)
		unit_row.add_child(marker)
	parent.add_child(unit_row)

func _refresh_battle_visuals(snapshot: Dictionary) -> void:
	if ConfigDB.get_region(GameState.active_region) == null:
		return
	var progress: float = float(snapshot.get("progress", 0.0))
	_battle_progress.value = clampf(progress, 0.0, 100.0)

	var reinforced := int(snapshot.get("reinforced", 0))
	var lost := int(snapshot.get("lost", 0))
	var field_total: int = _current_field_total()
	var visual_state: Dictionary = _battle_visual_state(snapshot)
	var status_text: String = String(visual_state.get("status_text", "待命"))
	var active_color: Color = Color(visual_state.get("active_color", Color(0.72, 0.80, 0.60)))
	var strip_color: Color = Color(visual_state.get("strip_color", Color(0.30, 0.32, 0.35)))
	_battle_status_strip.color = strip_color
	var flow_parts: Array[String] = [status_text]
	if reinforced > 0:
		flow_parts.append("补位 +%d" % reinforced)
	if lost > 0:
		flow_parts.append("损耗 -%d" % lost)
	_battle_flow_label.text = "战况：%s" % "  ".join(flow_parts)

	var lit_markers: int = clampi(field_total, 0, _battle_unit_markers.size())
	var refill_start: int = max(0, lit_markers - reinforced)
	for i in range(_battle_unit_markers.size()):
		var marker := _battle_unit_markers[i]
		if i < lit_markers:
			marker.color = Color(0.35, 0.78, 0.92) if i >= refill_start and reinforced > 0 else active_color
		else:
			marker.color = Color(0.16, 0.17, 0.19)

func _battle_visual_state(snapshot: Dictionary) -> Dictionary:
	var mode: String = String(snapshot.get("mode", "idle"))
	var state: Dictionary = {
		"status_text": "待命",
		"strip_color": Color(0.30, 0.32, 0.35),
		"active_color": Color(0.72, 0.80, 0.60)
	}
	match mode:
		"advance":
			state["strip_color"] = Color(0.20, 0.72, 0.34)
			state["active_color"] = Color(0.34, 0.82, 0.42)
			state["status_text"] = "推进 +%.1f%%" % float(snapshot.get("progress_gain", 0.0))
		"complete":
			state["strip_color"] = Color(0.72, 0.82, 0.26)
			state["active_color"] = Color(0.78, 0.88, 0.34)
			var next_name: String = String(snapshot.get("next_region_name", ""))
			state["status_text"] = "已吞噬，切换%s" % next_name if next_name != "" else "已吞噬"
		"stalled":
			state["strip_color"] = Color(0.82, 0.24, 0.20)
			state["active_color"] = Color(0.88, 0.38, 0.32)
			state["status_text"] = "停滞 %.1f / %.1f" % [float(snapshot.get("power", 0.0)), float(snapshot.get("pressure", 0.0))]
		"ready":
			state["strip_color"] = Color(0.28, 0.66, 0.76)
			state["active_color"] = Color(0.42, 0.90, 0.78)
			state["status_text"] = "波次已备 %d/%d" % [int(snapshot.get("prepared_reserve", 0)), int(snapshot.get("needed_reserve", 0))]
		"preparing":
			state["strip_color"] = Color(0.28, 0.56, 0.78)
			state["active_color"] = Color(0.38, 0.76, 0.92)
			state["status_text"] = "蓄兵 %d/%d" % [int(snapshot.get("prepared_reserve", 0)), int(snapshot.get("needed_reserve", 0))]
		"understrength":
			state["strip_color"] = Color(0.93, 0.56, 0.18)
			state["active_color"] = Color(0.96, 0.62, 0.24)
			state["status_text"] = "规模不足 %d/%d" % [int(snapshot.get("prepared_reserve", 0)), int(snapshot.get("needed_reserve", 0))]
		"committed":
			state["strip_color"] = Color(0.35, 0.72, 0.92)
			state["active_color"] = Color(0.40, 0.86, 0.92)
			state["status_text"] = "强攻补位中"
		"empty":
			state["strip_color"] = Color(0.93, 0.68, 0.20)
			state["active_color"] = Color(0.93, 0.68, 0.20)
			state["status_text"] = "阀门开启，等待补位"
		"holding":
			state["strip_color"] = Color(0.35, 0.54, 0.86)
			state["active_color"] = Color(0.35, 0.54, 0.86)
			state["status_text"] = "压制中，等待突破"
	return state

func _current_field_total() -> int:
	var total := 0
	for unit_id in GameState.field_units.keys():
		total += int(GameState.field_units.get(unit_id, 0))
	return total

func _reserve_total() -> int:
	var total := 0
	for unit_id in GameState.reserves.keys():
		total += int(GameState.reserves.get(unit_id, 0))
	return total

func _deployment_total() -> int:
	var total := 0
	for unit_id in GameState.deployment_intensity.keys():
		total += int(GameState.deployment_intensity.get(unit_id, 0))
	return total

func _next_step_text() -> String:
	var active = ConfigDB.get_region(GameState.active_region)
	var active_progress: float = float(GameState.region_progress.get(GameState.active_region, 0.0))
	var next_region_id: String = _next_region_id(active)
	if active_progress >= 100.0 and next_region_id != "":
		return "下一步：点击战场切换%s。" % _region_display_name(next_region_id)

	if GameState.active_region == "research_bastion":
		var unit_id: String = _preferred_assault_unit()
		var unit = ConfigDB.get_unit(unit_id)
		var projection: Dictionary = SimulationService.battle_projection(unit_id)
		var prepared: int = int(projection.get("prepared_reserve", 0))
		var needed: int = int(projection.get("needed_reserve", 0))
		var hatch_fill: int = int(projection.get("hatch_fill_count", 0))
		var unit_name: String = unit.display_name if unit != null else unit_id
		if unit != null and not _unit_unlocked(unit):
			return "下一步：研究堡垒预览；%s需总吞噬 %.0f%%。爆裂虫高推进/高损耗；甲壳卫士稳推进/低损耗。" % [unit_name, unit.unlock_devour]
		if needed > 0 and prepared >= needed:
			return "下一步：%s %d/%d 可强攻；爆裂虫高推进/高损耗，甲壳卫士稳推进/低损耗。" % [unit_name, prepared, needed]
		if hatch_fill > 0:
			return "下一步：左蓄兵补%d只%s；爆裂虫高推进/高损耗，甲壳卫士稳推进/低损耗。" % [hatch_fill, unit_name]
		return "下一步：研究堡垒敌压高，回工厂刷酶/螺旋后再蓄兵强攻。"

	if GameState.active_region == "factory_wall":
		var unit_id: String = _preferred_assault_unit()
		var unit = ConfigDB.get_unit(unit_id)
		var projection: Dictionary = SimulationService.battle_projection(unit_id)
		var prepared: int = int(projection.get("prepared_reserve", 0))
		var needed: int = int(projection.get("needed_reserve", 0))
		var shortfall: int = int(projection.get("reserve_shortfall", 0))
		var hatch_fill: int = int(projection.get("hatch_fill_count", 0))
		var unit_name: String = unit.display_name if unit != null else unit_id
		var plugin_text: String = "穿刺脊突已装配；" if GameState.equipped_plugin == "piercing_spines" else ""
		if needed > 0 and shortfall <= 0 and prepared >= needed:
			return "下一步：%s%s %d/%d，点战场中线强攻推进工厂。" % [plugin_text, unit_name, prepared, needed]
		if hatch_fill > 0:
			return "下一步：%s%s %d/%d，左蓄兵补%d只%s，再点中线强攻。" % [plugin_text, unit_name, prepared, needed, hatch_fill, unit_name]
		if shortfall > 0:
			return "下一步：右撤离保全或切回上一防线刷资源，再回来蓄兵强攻。"

	var mucus = ConfigDB.get_organ("mucus_fronds")
	if mucus != null and int(GameState.organ_levels.get("mucus_fronds", 0)) <= 1:
		var mucus_cost: Dictionary = {mucus.cost_resource: mucus.cost_for_level(int(GameState.organ_levels.get("mucus_fronds", 0)))}
		if GameState.can_spend(mucus_cost):
			return "下一步：升级菌毯绒毛，让原浆增长更快。"
		return "下一步：等待原浆补足 %s，再升级菌毯绒毛。" % _missing_cost_text(mucus_cost)

	var zergling = ConfigDB.get_unit("zergling")
	if _reserve_total() <= 0 and _current_field_total() <= 0:
		if zergling != null and GameState.can_spend(zergling.resource_costs()):
			return "下一步：孵化跳虫，把储备攒到可投放。"
		if zergling != null:
			return "下一步：暂停升级，等待自动产出补足 %s，再孵化跳虫恢复投放。" % _missing_cost_text(zergling.resource_costs())
		return "下一步：等待原浆和幼虫，按钮会显示还差多少。"

	if _deployment_total() <= 0 and _current_field_total() <= 0:
		return "下一步：打开跳虫投放强度，观察战场进度条。"

	if bool(GameState.region_unlocked.get("factory_wall", false)) and GameState.active_region != "factory_wall":
		return "下一步：切换废弃工厂防线，测试刺蛇与穿刺脊突。"

	if bool(GameState.region_unlocked.get("research_bastion", false)) and GameState.active_region != "research_bastion":
		return "下一步：切换研究堡垒外环，试爆裂虫与甲壳卫士的新敌压。"

	if active_progress < 8.0:
		return "下一步：看状态色条；若停滞，补储备或升级器官。"

	if GameState.active_region == "factory_wall" and GameState.equipped_plugin != "piercing_spines":
		var plugin = ConfigDB.get_plugin("piercing_spines")
		if plugin != null and (bool(GameState.plugins_owned.get("piercing_spines", false)) or GameState.can_spend({"helix": plugin.cost_helix})):
			return "下一步：装配穿刺脊突，提高工厂防线推进。"
		return "下一步：继续推进或积累螺旋序列，准备穿刺脊突。"

	var preview: Dictionary = SimulationService.prestige_preview()
	if int(preview.get("gain", 0)) > 0:
		return "下一步：查看吞噬世界预览，确认突变原收益后重置。"
	return "下一步：继续推进区域或积累螺旋，让重置预览出现收益。"

func _scaled_costs(costs: Dictionary, scale: float) -> Dictionary:
	var scaled: Dictionary = {}
	for id in costs.keys():
		scaled[id] = float(costs[id]) * scale
	return scaled

func _missing_cost_text(costs: Dictionary) -> String:
	var parts: Array[String] = []
	for id in GameState.RESOURCE_IDS:
		if not costs.has(id):
			continue
		var missing: float = max(0.0, float(costs[id]) - float(GameState.resources.get(id, 0.0)))
		if missing > 0.001:
			parts.append("%s %.0f" % [_resource_name(id), ceil(missing)])
	return "无" if parts.is_empty() else "、".join(parts)

func _unit_unlocked(unit) -> bool:
	return unit == null or GameState.total_devour + 0.001 >= float(unit.unlock_devour)

func _region_enemy_summary(region) -> String:
	if region == null:
		return ""
	var parts: Array[String] = []
	for enemy_id in region.enemy_ids:
		var enemy = ConfigDB.get_enemy(enemy_id)
		if enemy != null:
			parts.append("%s怕%s" % [enemy.display_name, enemy.weakness_tag])
	return "、".join(parts)

func _unit_readout_text() -> String:
	var field_parts: Array[String] = []
	var reserve_parts: Array[String] = []
	for unit_id in _unit_ids():
		var unit = ConfigDB.get_unit(unit_id)
		if unit == null:
			continue
		var field_count: int = int(GameState.field_units.get(unit_id, 0))
		var reserve_count: int = int(GameState.reserves.get(unit_id, 0))
		if field_count > 0:
			field_parts.append("%s %d" % [unit.display_name, field_count])
		if reserve_count > 0:
			reserve_parts.append("%s %d" % [unit.display_name, reserve_count])
	if field_parts.is_empty():
		field_parts.append("无")
	if reserve_parts.is_empty():
		reserve_parts.append("无")
	return "场上 %s    储备 %s" % [" / ".join(field_parts), " / ".join(reserve_parts)]

func _offline_text() -> String:
	if GameState.offline_report.is_empty():
		return "离线报告：暂无。读取存档会按 12 小时上限结算。"
	var report: Dictionary = GameState.offline_report
	var gains: Dictionary = report.get("gains", {})
	return "离线报告：%.1f 小时%s  原浆 +%.0f 酶 +%.1f 螺旋 +%.1f 幼虫 +%.1f" % [
		float(report.get("seconds", 0.0)) / 3600.0,
		"（已封顶）" if bool(report.get("capped", false)) else "",
		gains.get("pulp", 0.0),
		gains.get("enzyme", 0.0),
		gains.get("helix", 0.0),
		gains.get("larva", 0.0)
	]

func _add_section(parent: VBoxContainer, text: String) -> void:
	var separator := HSeparator.new()
	parent.add_child(separator)
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 19)
	parent.add_child(label)

func _make_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label

func _make_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(44, 52)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	button.clip_text = true
	return button

func _unit_role_tag(unit_id: String) -> String:
	match unit_id:
		"baneling":
			return "高推进/高损耗"
		"carapace_guard":
			return "稳推进/低损耗"
		"hydralisk":
			return "穿刺破甲"
		"roach":
			return "稳守前排"
		"mutalisk":
			return "高机动破点"
		_:
			return "低耗补位"

func _organ_ids() -> Array[String]:
	return ConfigDB.get_organ_ids()

func _unit_ids() -> Array[String]:
	return ConfigDB.get_unit_ids()

func _plugin_ids() -> Array[String]:
	return ConfigDB.get_plugin_ids()

func _region_ids() -> Array[String]:
	return ConfigDB.get_region_ids()

func _resource_name(id: String) -> String:
	var names := {
		"pulp": "有机原浆",
		"enzyme": "活性酶",
		"helix": "螺旋序列",
		"larva": "幼虫",
		"mutation": "突变原"
	}
	return names.get(id, id)
