extends VBoxContainer

const UI = preload("res://scripts/ui/ui_utils.gd")
const BattleCanvas = preload("res://scripts/ui/battle_canvas.gd")

var snapshot: Dictionary = {}
var canvas: Control
var title: Label
var metrics: Label
var retreat_button: Button
var confirm_band: PanelContainer

func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 10)
	var header := HBoxContainer.new()
	add_child(header)
	title = UI.label("长战场", "PageTitle")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	retreat_button = UI.button("撤离", _show_retreat_confirm, "DangerButton")
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
	confirm_band.visible = false
	add_child(confirm_band)
	var confirm_row := HBoxContainer.new()
	confirm_band.add_child(confirm_row)
	var warning := UI.label("撤离在下一合法边界原子提交；确认后不可取消。", "Warning")
	warning.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	confirm_row.add_child(warning)
	confirm_row.add_child(UI.button("关闭", _hide_retreat_confirm))
	confirm_row.add_child(UI.button("确认撤离", _confirm_retreat, "DangerButton"))

func set_snapshot(value: Dictionary) -> void:
	snapshot = value
	if snapshot.is_empty():
		return
	var battle: Dictionary = snapshot.active_battle
	canvas.set_battle(battle)
	retreat_button.disabled = battle.is_empty()
	if battle.is_empty():
		title.text = "长战场 · 当前无主动战役"
		metrics.text = "从区域图选择一个可观察节点提交进攻"
		confirm_band.visible = false
	else:
		var node := GameSession.node_by_id(battle.node_id)
		title.text = "%s · %s" % [battle.node_id, node.name]
		metrics.text = "噬咬体 %d   根脉孢体 %d   留置菌毯 %d     敌军 %d   结构 %d     歼灭 %d   战损 %d" % [battle.biter, battle.spore, battle.roots, battle.enemy, battle.structure_hp, battle.kills, battle.losses]

func _show_retreat_confirm() -> void:
	confirm_band.visible = true

func _hide_retreat_confirm() -> void:
	confirm_band.visible = false

func _confirm_retreat() -> void:
	if GameSession.retreat():
		confirm_band.visible = false
