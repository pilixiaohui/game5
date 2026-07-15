extends HSplitContainer

const UI = preload("res://scripts/ui/ui_utils.gd")

var snapshot: Dictionary = {}
var log_box: VBoxContainer
var setting_box: VBoxContainer

func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	split_offset = -390
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 10)
	add_child(left)
	left.add_child(UI.label("事件与账目", "PageTitle"))
	left.add_child(UI.label("事件只记录已经提交的事实；页面访问不会生成玩法结果。", "Muted"))
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(scroll)
	log_box = VBoxContainer.new()
	log_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	log_box.add_theme_constant_override("separation", 7)
	scroll.add_child(log_box)

	var right := PanelContainer.new()
	right.custom_minimum_size.x = 380
	add_child(right)
	setting_box = VBoxContainer.new()
	setting_box.add_theme_constant_override("separation", 10)
	right.add_child(setting_box)

func set_snapshot(value: Dictionary) -> void:
	snapshot = value
	if snapshot.is_empty():
		return
	_rebuild_log()
	_rebuild_settings()

func _rebuild_log() -> void:
	UI.clear(log_box)
	for event in snapshot.ledger.slice(0, min(30, snapshot.ledger.size())):
		var row := HBoxContainer.new()
		var tick := UI.label("T+%05d" % event.tick, "Muted")
		tick.custom_minimum_size.x = 90
		row.add_child(tick)
		var message := UI.label(event.message)
		message.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(message)
		log_box.add_child(row)

func _rebuild_settings() -> void:
	UI.clear(setting_box)
	setting_box.add_child(UI.label("系统与设置", "PageTitle"))
	setting_box.add_child(UI.button("手动保存", _save, "PrimaryButton"))
	setting_box.add_child(UI.label("自动保存每 30 秒执行；战役结束和撤离也会保存。", "Muted"))
	setting_box.add_child(UI.separator())
	setting_box.add_child(UI.label("界面缩放", "Section"))
	var scale_options := OptionButton.new()
	for value in ["100%", "115%", "130%"]:
		scale_options.add_item(value)
	var scales := [1.0, 1.15, 1.3]
	var closest := scales.find(float(snapshot.settings.ui_scale))
	scale_options.select(max(0, closest))
	scale_options.item_selected.connect(_set_scale)
	setting_box.add_child(scale_options)
	setting_box.add_child(UI.label("动画强度", "Section"))
	var animation_options := OptionButton.new()
	for value in ["完整", "降低", "最低"]:
		animation_options.add_item(value)
	animation_options.select(max(0, ["完整", "降低", "最低"].find(snapshot.settings.animation)))
	animation_options.item_selected.connect(_set_animation)
	setting_box.add_child(animation_options)
	var flashes := CheckButton.new()
	flashes.text = "减少闪烁"
	flashes.button_pressed = bool(snapshot.settings.reduce_flashes)
	flashes.toggled.connect(_set_flashes)
	setting_box.add_child(flashes)
	setting_box.add_child(UI.label("总音量", "Section"))
	var volume := HSlider.new()
	volume.min_value = 0.0
	volume.max_value = 1.0
	volume.step = 0.05
	volume.value = float(snapshot.settings.master_volume)
	volume.value_changed.connect(_set_volume)
	setting_box.add_child(volume)
	setting_box.add_child(UI.separator())
	var completion := GameSession.completion_summary()
	setting_box.add_child(UI.label("体验里程碑 %d / %d" % [completion.completed, completion.total], "Section"))
	setting_box.add_child(UI.progress(float(completion.completed), float(completion.total)))
	setting_box.add_child(UI.label("正式飞升、多虫巢、第二地区节点网：尚未开放", "Warning"))

func _save() -> void:
	GameSession.save_game()

func _set_scale(index: int) -> void:
	GameSession.update_settings({"ui_scale": [1.0, 1.15, 1.3][index]})

func _set_animation(index: int) -> void:
	GameSession.update_settings({"animation": ["完整", "降低", "最低"][index]})

func _set_flashes(value: bool) -> void:
	GameSession.update_settings({"reduce_flashes": value})

func _set_volume(value: float) -> void:
	GameSession.update_settings({"master_volume": value})
