extends VBoxContainer

signal m1_presenter_lifecycle(mounted: bool)
signal battle_result_confirmed

const UI = preload("res://scripts/ui/ui_utils.gd")
const BattleCanvas = preload("res://scripts/ui/battle_canvas.gd")
const M1WorldPresenter = preload("res://scripts/ui/m1_world_presenter.gd")
const ArtAssets = preload("res://scripts/ui/art_assets.gd")
const RETREAT_DECISION_PAUSE := "retreat_confirmation"
const PRESENTATION_MIN_WINDOW_MSEC := 4000

var snapshot: Dictionary = {}
var canvas: Control
var title: Label
var engagement_icon: TextureRect
var metrics: Label
var retreat_button: Button
var confirm_band: PanelContainer
var session: Node
var m1_presenter: Control
var canvas_panel: PanelContainer
var fallback_reason: Label
var m1_scene_path := M1WorldPresenter.WORLD_SCENE_PATH
var result_band: PanelContainer
var result_title: Label
var result_body: Label
var result_confirm_button: Button
var result_ready_timer: Timer
var battle_entry_snapshot: Dictionary = {}
var last_active_battle: Dictionary = {}
var battle_presentation_started_msec := 0
var result_summary: Dictionary = {}

func _init(session_override: Node = null, m1_scene_path_override: String = M1WorldPresenter.WORLD_SCENE_PATH) -> void:
	session = session_override
	m1_scene_path = m1_scene_path_override

func _ready() -> void:
	if session == null:
		session = get_node("/root/GameSession")
	set_process_unhandled_input(true)
	visibility_changed.connect(_on_visibility_changed)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 10)
	var header := HBoxContainer.new()
	add_child(header)
	engagement_icon = UI.texture_rect(ArtAssets.STATE_ENGAGED, Vector2(32, 32))
	header.add_child(engagement_icon)
	title = UI.label("长战场", "PageTitle")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	retreat_button = UI.button("撤离", _show_retreat_confirm, "DangerButton")
	retreat_button.name = "RetreatButton"
	retreat_button.icon = ArtAssets.STATE_RETREAT
	retreat_button.add_theme_constant_override("icon_max_width", 24)
	header.add_child(retreat_button)
	add_child(UI.label("画面代表只投影真实批次；代表数量、动画与帧率不会参与结算。", "Muted"))
	fallback_reason = UI.label("", "Warning")
	fallback_reason.name = "M1FallbackReason"
	fallback_reason.visible = false
	add_child(fallback_reason)
	canvas_panel = PanelContainer.new()
	canvas_panel.name = "BattleVisualPanel"
	canvas_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(canvas_panel)
	canvas = BattleCanvas.new()
	canvas.name = "LegacyBattleCanvas"
	canvas.visible = true
	canvas_panel.add_child(canvas)
	metrics = UI.label("", "Metric")
	metrics.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(metrics)
	_build_result_band()
	confirm_band = PanelContainer.new()
	confirm_band.name = "RetreatConfirmation"
	confirm_band.visible = false
	add_child(confirm_band)
	var confirm_row := HBoxContainer.new()
	confirm_band.add_child(confirm_row)
	var warning := UI.label("撤离在下一合法边界原子提交；确认后不可取消。", "Warning")
	warning.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	confirm_row.add_child(warning)
	var close_button := UI.button("关闭", _hide_retreat_confirm)
	close_button.name = "CancelRetreatButton"
	confirm_row.add_child(close_button)
	var confirm_button := UI.button("确认撤离", _confirm_retreat, "DangerButton")
	confirm_button.name = "ConfirmRetreatButton"
	confirm_button.icon = ArtAssets.STATE_RETREAT
	confirm_button.add_theme_constant_override("icon_max_width", 22)
	confirm_row.add_child(confirm_button)
func set_snapshot(value: Dictionary) -> void:
	snapshot = value
	if is_instance_valid(m1_presenter) and m1_presenter.has_method("set_snapshot"):
		m1_presenter.call("set_snapshot", snapshot)
	if snapshot.is_empty():
		return
	var battle: Dictionary = snapshot.active_battle
	if not battle.is_empty():
		if battle_entry_snapshot.is_empty() or String((battle_entry_snapshot.get("active_battle", {}) as Dictionary).get("node_id", "")) != String(battle.get("node_id", "")):
			battle_entry_snapshot = snapshot.duplicate(true)
			battle_presentation_started_msec = Time.get_ticks_msec()
		last_active_battle = battle.duplicate(true)
	if not _m1_projection_active():
		canvas.set_battle(battle)
	var persistence_blocked: bool = session.is_reload_required()
	retreat_button.disabled = battle.is_empty() or persistence_blocked
	if persistence_blocked and confirm_band.visible:
		_hide_retreat_confirm(false)
	if battle.is_empty():
		if result_summary.is_empty():
			engagement_icon.visible = false
			title.text = "长战场 · 当前无主动战役"
			metrics.text = "从区域图选择一个可观察节点提交进攻"
			_hide_retreat_confirm(false)
	else:
		engagement_icon.visible = true
		var node: Dictionary = session.node_by_id(battle.node_id)
		title.text = "%s · %s" % [battle.node_id, node.name]
		metrics.text = "噬咬体 %d   根脉孢体 %d   留置菌毯 %d     敌军 %d   结构 %d     歼灭 %d   战损 %d" % [battle.biter, battle.spore, battle.roots, battle.enemy, battle.structure_hp, battle.kills, battle.losses]

func _build_result_band() -> void:
	result_band = PanelContainer.new()
	result_band.name = "M1BattleResultSummary"
	result_band.visible = false
	add_child(result_band)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	result_band.add_child(box)
	result_title = UI.label("战果摘要", "Section")
	box.add_child(result_title)
	result_body = UI.label("")
	result_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(result_body)
	result_confirm_button = UI.button("确认战果并返回区域图", _confirm_battle_result, "PrimaryButton")
	result_confirm_button.name = "ConfirmBattleResultButton"
	result_confirm_button.focus_mode = Control.FOCUS_ALL
	box.add_child(result_confirm_button)
	result_ready_timer = Timer.new()
	result_ready_timer.one_shot = true
	result_ready_timer.timeout.connect(_enable_result_confirmation)
	add_child(result_ready_timer)

func present_battle_result(node_id: String, captured: bool, authority_snapshot: Dictionary) -> void:
	if battle_entry_snapshot.is_empty():
		battle_entry_snapshot = authority_snapshot.duplicate(true)
		battle_presentation_started_msec = Time.get_ticks_msec()
	result_summary = _build_battle_result(node_id, captured, authority_snapshot)
	result_band.visible = true
	result_title.text = "占领完成" if captured else "战斗撤离"
	result_body.text = "出战：%s\n回归：%s\n损失：%s\n资源奖励：%s\n占领收益：%s\n下一节点影响：%s" % [result_summary.deployed, result_summary.returned, result_summary.losses, result_summary.resource_reward, result_summary.capture_benefit, result_summary.next_node_impact]
	retreat_button.disabled = true
	confirm_band.visible = false
	var elapsed := Time.get_ticks_msec() - battle_presentation_started_msec
	var remaining := maxi(0, PRESENTATION_MIN_WINDOW_MSEC - elapsed)
	result_confirm_button.disabled = remaining > 0
	if remaining > 0:
		result_ready_timer.start(float(remaining) / 1000.0)
	else:
		_enable_result_confirmation()
	if is_instance_valid(m1_presenter) and m1_presenter.has_method("present_battle_result"):
		m1_presenter.call("present_battle_result", result_summary, captured)

func battle_result_snapshot() -> Dictionary:
	return {
		"visible": is_instance_valid(result_band) and result_band.visible,
		"confirm_ready": is_instance_valid(result_confirm_button) and not result_confirm_button.disabled,
		"observation_elapsed_msec": Time.get_ticks_msec() - battle_presentation_started_msec if battle_presentation_started_msec > 0 else 0,
		"minimum_observation_msec": PRESENTATION_MIN_WINDOW_MSEC,
		"summary": result_summary.duplicate(true),
	}

func _build_battle_result(node_id: String, captured: bool, authority_snapshot: Dictionary) -> Dictionary:
	var entry_battle: Dictionary = battle_entry_snapshot.get("active_battle", {})
	var deployed_biter := int(entry_battle.get("biter", 0))
	var deployed_spore := int(entry_battle.get("spore", 0))
	var returned_biter := int(last_active_battle.get("biter", 0))
	var returned_spore := int(last_active_battle.get("spore", 0))
	var returned_roots := int(last_active_battle.get("roots", 0))
	var losses := int(last_active_battle.get("losses", maxi(0, deployed_biter + deployed_spore - returned_biter - returned_spore - returned_roots)))
	var before_processing: Dictionary = battle_entry_snapshot.get("processing", {})
	var after_processing: Dictionary = authority_snapshot.get("processing", {})
	var organic_delta := float(after_processing.get("field_organic", 0.0)) - float(before_processing.get("field_organic", 0.0))
	var sample_delta := float(after_processing.get("field_sample", 0.0)) - float(before_processing.get("field_sample", 0.0))
	var newly_observed: Array[String] = []
	var before_nodes := _node_visibility_by_id(battle_entry_snapshot.get("nodes", []))
	for node in authority_snapshot.get("nodes", []):
		var id := String(node.get("id", ""))
		if bool(node.get("observed", false)) and not bool(before_nodes.get(id, false)):
			newly_observed.append("%s %s" % [id, String(node.get("name", ""))])
	var resource_parts: Array[String] = []
	if organic_delta > 0.0:
		resource_parts.append("外源有机质 +%d" % int(organic_delta))
	if sample_delta > 0.0:
		resource_parts.append("固定样本 +%d" % int(sample_delta))
	if resource_parts.is_empty():
		resource_parts.append("无新增外源资源")
	return {
		"node_id": node_id,
		"outcome": "captured" if captured else "retreated",
		"deployed": "噬咬体 %d / 孢体 %d" % [deployed_biter, deployed_spore],
		"returned": "噬咬体 %d / 孢体 %d / 菌毯 %d" % [returned_biter, returned_spore, returned_roots],
		"losses": "%d" % losses,
		"resource_reward": "、".join(resource_parts),
		"capture_benefit": "%s 纳入虫巢网络" % node_id if captured else "未占领，节点状态保留",
		"next_node_impact": "新观察 %s" % "、".join(newly_observed) if not newly_observed.is_empty() else "无新增可观察节点",
		"settled_tick": int(authority_snapshot.get("tick", 0)),
		"rule_event": _settlement_event_type(authority_snapshot.get("ledger", [])),
		"source": "readonly-authority-snapshot-ledger",
	}

func _node_visibility_by_id(nodes: Array) -> Dictionary:
	var result := {}
	for node in nodes:
		result[String(node.get("id", ""))] = bool(node.get("observed", false))
	return result

func _settlement_event_type(ledger: Array) -> String:
	for event in ledger:
		var event_type := String(event.get("type", ""))
		if event_type in ["node_captured", "battle_retreated", "army_destroyed"]:
			return event_type
	return ""

func _enable_result_confirmation() -> void:
	if not is_instance_valid(result_confirm_button) or not result_band.visible:
		return
	result_confirm_button.disabled = false
	result_confirm_button.grab_focus()

func _confirm_battle_result() -> void:
	if result_summary.is_empty() or result_confirm_button.disabled:
		return
	result_ready_timer.stop()
	result_band.visible = false
	result_summary = {}
	battle_entry_snapshot = {}
	last_active_battle = {}
	if is_instance_valid(m1_presenter) and m1_presenter.has_method("clear_battle_result"):
		m1_presenter.call("clear_battle_result")
	battle_result_confirmed.emit()

func _m1_projection_active() -> bool:
	return is_instance_valid(m1_presenter) and bool(m1_presenter.call("is_available"))

func set_active(active: bool) -> void:
	if active:
		_mount_m1_presenter()
	else:
		_unmount_m1_presenter()

func _mount_m1_presenter() -> void:
	if is_instance_valid(m1_presenter):
		return
	m1_presenter = M1WorldPresenter.new(session, m1_scene_path)
	m1_presenter.name = "M1WorldPresenter"
	canvas_panel.add_child(m1_presenter)
	canvas_panel.move_child(m1_presenter, 0)
	var available: bool = bool(m1_presenter.call("is_available"))
	m1_presenter_lifecycle.emit(true)
	canvas.visible = not available
	fallback_reason.visible = not available
	if not available:
		fallback_reason.text = "M1 战场视图不可用：%s；已回退传统战场页。" % String(m1_presenter.call("get_fallback_reason"))
		if not snapshot.is_empty():
			canvas.set_battle(snapshot.active_battle)
	if available and not snapshot.is_empty():
		m1_presenter.call("set_snapshot", snapshot)

func _unmount_m1_presenter() -> void:
	if is_instance_valid(m1_presenter):
		m1_presenter.queue_free()
		m1_presenter_lifecycle.emit(false)
	m1_presenter = null
	canvas.visible = false
	fallback_reason.visible = false
	result_ready_timer.stop()

func _show_retreat_confirm() -> void:
	if session.is_reload_required() or confirm_band.visible or snapshot.active_battle.is_empty():
		return
	session.set_decision_pause(RETREAT_DECISION_PAUSE, true)
	if is_instance_valid(m1_presenter) and m1_presenter.has_method("show_retreat_intent"):
		m1_presenter.call("show_retreat_intent", true)
	confirm_band.visible = true
	var cancel := confirm_band.find_child("CancelRetreatButton", true, false) as Button
	if cancel:
		cancel.grab_focus()

func _hide_retreat_confirm(restore_focus: bool = true) -> void:
	session.set_decision_pause(RETREAT_DECISION_PAUSE, false)
	if is_instance_valid(m1_presenter) and m1_presenter.has_method("show_retreat_intent"):
		m1_presenter.call("show_retreat_intent", false)
	confirm_band.visible = false
	if restore_focus and is_instance_valid(retreat_button) and retreat_button.is_visible_in_tree() and not retreat_button.disabled:
		retreat_button.grab_focus()

func _confirm_retreat() -> void:
	if session.retreat():
		_hide_retreat_confirm()
	elif session.is_reload_required():
		_hide_retreat_confirm(false)
		retreat_button.disabled = true
	else:
		var confirm := confirm_band.find_child("ConfirmRetreatButton", true, false) as Button
		if confirm:
			confirm.grab_focus()

func _on_visibility_changed() -> void:
	if not is_visible_in_tree() and is_instance_valid(confirm_band) and confirm_band.visible:
		_hide_retreat_confirm(false)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and is_instance_valid(confirm_band) and confirm_band.visible:
		_hide_retreat_confirm()
		get_viewport().set_input_as_handled()

func _exit_tree() -> void:
	if is_instance_valid(session):
		session.set_decision_pause(RETREAT_DECISION_PAUSE, false)
