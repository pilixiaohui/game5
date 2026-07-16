extends VBoxContainer

const UI = preload("res://scripts/ui/ui_utils.gd")
const BattleCanvas = preload("res://scripts/ui/battle_canvas.gd")
const ArtAssets = preload("res://scripts/ui/art_assets.gd")
const RETREAT_DECISION_PAUSE := "retreat_confirmation"

var snapshot: Dictionary = {}
var canvas: Control
var title: Label
var engagement_icon: TextureRect
var metrics: Label
var retreat_button: Button
var confirm_band: PanelContainer
var session: Node

func _init(session_override: Node = null) -> void:
	session = session_override

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
	var canvas_panel := PanelContainer.new()
	canvas_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(canvas_panel)
	canvas = BattleCanvas.new()
	canvas_panel.add_child(canvas)
	metrics = UI.label("", "Metric")
	metrics.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(metrics)
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
	if snapshot.is_empty():
		return
	var battle: Dictionary = snapshot.active_battle
	canvas.set_battle(battle)
	var persistence_blocked: bool = session.is_reload_required()
	retreat_button.disabled = battle.is_empty() or persistence_blocked
	if persistence_blocked and confirm_band.visible:
		_hide_retreat_confirm(false)
	if battle.is_empty():
		engagement_icon.visible = false
		title.text = "长战场 · 当前无主动战役"
		metrics.text = "从区域图选择一个可观察节点提交进攻"
		_hide_retreat_confirm(false)
	else:
		engagement_icon.visible = true
		var node: Dictionary = session.node_by_id(battle.node_id)
		title.text = "%s · %s" % [battle.node_id, node.name]
		metrics.text = "噬咬体 %d   根脉孢体 %d   留置菌毯 %d     敌军 %d   结构 %d     歼灭 %d   战损 %d" % [battle.biter, battle.spore, battle.roots, battle.enemy, battle.structure_hp, battle.kills, battle.losses]

func _show_retreat_confirm() -> void:
	if session.is_reload_required() or confirm_band.visible or snapshot.active_battle.is_empty():
		return
	session.set_decision_pause(RETREAT_DECISION_PAUSE, true)
	confirm_band.visible = true
	var cancel := confirm_band.find_child("CancelRetreatButton", true, false) as Button
	if cancel:
		cancel.grab_focus()

func _hide_retreat_confirm(restore_focus: bool = true) -> void:
	session.set_decision_pause(RETREAT_DECISION_PAUSE, false)
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
