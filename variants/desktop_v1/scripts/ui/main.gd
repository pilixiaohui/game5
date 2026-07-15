extends Control

const ThemeFactory = preload("res://scripts/ui/theme_factory.gd")
const UI = preload("res://scripts/ui/ui_utils.gd")
const GameShell = preload("res://scripts/ui/game_shell.gd")
const BrandMark = preload("res://scripts/ui/brand_mark.gd")

var content: Control
var new_game_button: Button
var continue_button: Button
var settings_overlay: Control
var new_game_confirmation: Control
var title_notice: Label
var background_focus_modes: Dictionary = {}
var session: Node
var persistence_recovery: PanelContainer
var persistence_recovery_label: Label
var persistence_reload_button: Button
var showing_game := false

func _init(session_override: Node = null) -> void:
	session = session_override

func _ready() -> void:
	if session == null:
		session = get_node("/root/GameSession")
	theme = ThemeFactory.build()
	set_process_unhandled_input(true)
	get_viewport().gui_focus_changed.connect(_on_gui_focus_changed)
	_build_background()
	if not session.notice_posted.is_connected(_show_title_notice):
		session.notice_posted.connect(_show_title_notice)
	if not session.persistence_recovery_changed.is_connected(_on_persistence_recovery_changed):
		session.persistence_recovery_changed.connect(_on_persistence_recovery_changed)
	_on_persistence_recovery_changed(session.persistence_recovery_status())
	if "--demo" in OS.get_cmdline_user_args():
		session.new_game(2707)
		session.build_room(0, "thermal_metabolism")
		session.build_room(1, "biomass_filter")
		session.build_room(4, "embryo_hatchery")
		session.advance_steps(22)
		_show_game()
	else:
		_show_title()

func _build_background() -> void:
	var background := ColorRect.new()
	background.color = ThemeFactory.BG
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	content = MarginContainer.new()
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.add_theme_constant_override("margin_left", 24)
	content.add_theme_constant_override("margin_right", 24)
	content.add_theme_constant_override("margin_top", 20)
	content.add_theme_constant_override("margin_bottom", 20)
	add_child(content)
	_build_persistence_recovery()

func _build_persistence_recovery() -> void:
	persistence_recovery = PanelContainer.new()
	persistence_recovery.name = "PersistenceRecovery"
	persistence_recovery.visible = false
	persistence_recovery.z_index = 100
	persistence_recovery.mouse_filter = Control.MOUSE_FILTER_STOP
	persistence_recovery.anchor_left = 0.0
	persistence_recovery.anchor_top = 1.0
	persistence_recovery.anchor_right = 1.0
	persistence_recovery.anchor_bottom = 1.0
	persistence_recovery.offset_left = 24.0
	persistence_recovery.offset_top = -72.0
	persistence_recovery.offset_right = -24.0
	persistence_recovery.offset_bottom = -14.0
	add_child(persistence_recovery)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	persistence_recovery.add_child(row)
	persistence_recovery_label = UI.label("存档提交结果待确认。模拟、保存与操作已冻结，必须重新载入。", "Warning")
	persistence_recovery_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	persistence_recovery_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(persistence_recovery_label)
	persistence_reload_button = UI.button("重新载入存档", _reload_after_persistence_block, "PrimaryButton")
	persistence_reload_button.name = "ReloadAfterPersistenceBlock"
	persistence_reload_button.custom_minimum_size.x = 150
	row.add_child(persistence_reload_button)

func _show_title() -> void:
	showing_game = false
	UI.clear(content)
	content.add_theme_constant_override("margin_left", 24)
	content.add_theme_constant_override("margin_right", 24)
	content.add_theme_constant_override("margin_top", 20)
	content.add_theme_constant_override("margin_bottom", 84 if session.is_reload_required() else 20)
	var root := HBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 50)
	content.add_child(root)
	var visual := VBoxContainer.new()
	visual.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	visual.size_flags_vertical = Control.SIZE_EXPAND_FILL
	visual.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(visual)
	var game_title := UI.label("异种起源", "GameTitle")
	game_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	visual.add_child(game_title)
	var game_subtitle := UI.label("无尽洪流", "PageTitle")
	game_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	game_subtitle.add_theme_color_override("font_color", ThemeFactory.GREEN)
	visual.add_child(game_subtitle)
	var emblem := TextureRect.new()
	emblem.name = "BrandMark"
	emblem.texture = BrandMark.texture()
	emblem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	emblem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	emblem.custom_minimum_size = Vector2(260, 260)
	visual.add_child(emblem)
	var premise := UI.label("经营一座活体虫巢，在持续战场中回收、解析并改写虫群。", "Section")
	premise.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	visual.add_child(premise)

	var actions := VBoxContainer.new()
	actions.custom_minimum_size.x = 370
	actions.size_flags_vertical = Control.SIZE_EXPAND_FILL
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 12)
	root.add_child(actions)
	actions.add_child(UI.label("本地存档", "PageTitle"))
	actions.add_child(UI.label("腐殖盆地 · 第一轮", "Muted"))
	new_game_button = UI.button("新游戏", _new_game, "PrimaryButton")
	new_game_button.name = "NewGameButton"
	actions.add_child(new_game_button)
	continue_button = UI.button("继续游戏", _continue_game)
	continue_button.name = "ContinueButton"
	continue_button.disabled = not session.has_save()
	actions.add_child(continue_button)
	actions.add_child(UI.button("设置", _toggle_title_settings))
	actions.add_child(UI.button("退出", get_tree().quit))
	title_notice = UI.label("", "Warning")
	title_notice.name = "TitleNotice"
	title_notice.visible = false
	actions.add_child(title_notice)
	actions.add_child(UI.separator())
	actions.add_child(UI.label("Godot 4.7 · Windows 桌面首小时切片", "Muted"))
	_build_title_settings(actions)
	_build_new_game_confirmation()

func _build_title_settings(parent: VBoxContainer) -> void:
	settings_overlay = PanelContainer.new()
	settings_overlay.visible = false
	parent.add_child(settings_overlay)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	settings_overlay.add_child(box)
	box.add_child(UI.label("启动设置", "Section"))
	var fullscreen := CheckButton.new()
	fullscreen.text = "全屏"
	fullscreen.button_pressed = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	fullscreen.toggled.connect(_toggle_fullscreen)
	box.add_child(fullscreen)
	box.add_child(UI.label("游戏内系统页可调整界面缩放、动画、闪烁与音量。", "Muted"))

func _build_new_game_confirmation() -> void:
	new_game_confirmation = ColorRect.new()
	new_game_confirmation.name = "NewGameConfirmation"
	new_game_confirmation.color = Color(0.0, 0.0, 0.0, 0.68)
	new_game_confirmation.mouse_filter = Control.MOUSE_FILTER_STOP
	new_game_confirmation.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	new_game_confirmation.visible = false
	add_child(new_game_confirmation)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	new_game_confirmation.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 460
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	box.add_child(UI.label("确认开始新游戏", "Section"))
	box.add_child(UI.label("现有本地进度将移入备份槽。", "Warning"))
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	box.add_child(actions)
	var confirm := UI.button("确认重开", _confirm_new_game, "DangerButton")
	confirm.name = "ConfirmNewGameButton"
	confirm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(confirm)
	var cancel := UI.button("取消", _cancel_new_game)
	cancel.name = "CancelNewGameButton"
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(cancel)
	confirm.focus_neighbor_left = confirm.get_path_to(cancel)
	confirm.focus_neighbor_right = confirm.get_path_to(cancel)
	confirm.focus_neighbor_top = confirm.get_path_to(confirm)
	confirm.focus_neighbor_bottom = confirm.get_path_to(confirm)
	confirm.focus_next = confirm.get_path_to(cancel)
	confirm.focus_previous = confirm.get_path_to(cancel)
	cancel.focus_neighbor_left = cancel.get_path_to(confirm)
	cancel.focus_neighbor_right = cancel.get_path_to(confirm)
	cancel.focus_neighbor_top = cancel.get_path_to(cancel)
	cancel.focus_neighbor_bottom = cancel.get_path_to(cancel)
	cancel.focus_next = cancel.get_path_to(confirm)
	cancel.focus_previous = cancel.get_path_to(confirm)

func _new_game() -> void:
	if session.has_save():
		_set_background_focus_enabled(false)
		new_game_confirmation.visible = true
		_focus_new_game_modal()
		return
	_start_new_game()

func _confirm_new_game() -> void:
	_close_new_game_confirmation(false)
	_start_new_game()

func _cancel_new_game() -> void:
	_close_new_game_confirmation()
	_show_title_notice("已取消重开，当前状态和存档未改变。", "info")

func _close_new_game_confirmation(restore_focus: bool = true) -> void:
	new_game_confirmation.visible = false
	_set_background_focus_enabled(true)
	if restore_focus and is_instance_valid(new_game_button):
		new_game_button.grab_focus()

func _focus_new_game_modal() -> void:
	if not is_instance_valid(new_game_confirmation) or not new_game_confirmation.visible:
		return
	var cancel := new_game_confirmation.find_child("CancelNewGameButton", true, false) as Button
	if cancel:
		cancel.grab_focus()

func _set_background_focus_enabled(enabled: bool) -> void:
	if enabled:
		for control in background_focus_modes.keys():
			if is_instance_valid(control):
				control.focus_mode = int(background_focus_modes[control])
		background_focus_modes.clear()
		return
	background_focus_modes.clear()
	for node in content.find_children("*", "Control", true, false):
		var control := node as Control
		if control != null and control.focus_mode != Control.FOCUS_NONE:
			background_focus_modes[control] = control.focus_mode
			control.focus_mode = Control.FOCUS_NONE

func _on_gui_focus_changed(control: Control) -> void:
	if not is_instance_valid(new_game_confirmation) or not new_game_confirmation.visible:
		return
	if control == null or not new_game_confirmation.is_ancestor_of(control):
		call_deferred("_focus_new_game_modal")

func _start_new_game() -> void:
	session.new_game()
	if session.save_game():
		_show_game()

func _continue_game() -> void:
	if session.load_game():
		_show_game()

func _show_title_notice(message: String, level: String) -> void:
	if not is_instance_valid(title_notice):
		return
	title_notice.text = message
	title_notice.theme_type_variation = "Warning" if level == "warning" else "Muted"
	title_notice.visible = true

func _show_game() -> void:
	showing_game = true
	if is_instance_valid(new_game_confirmation):
		_close_new_game_confirmation(false)
	UI.clear(content)
	content.add_theme_constant_override("margin_left", 0)
	content.add_theme_constant_override("margin_right", 0)
	content.add_theme_constant_override("margin_top", 0)
	content.add_theme_constant_override("margin_bottom", 72 if session.is_reload_required() else 0)
	var shell := GameShell.new(session)
	content.add_child(shell)

func _on_persistence_recovery_changed(status: Dictionary) -> void:
	if not is_instance_valid(persistence_recovery):
		return
	var visible: bool = bool(status.get("reload_required", false))
	persistence_recovery.visible = visible
	persistence_reload_button.disabled = false
	persistence_recovery_label.tooltip_text = String(status.get("message", ""))
	content.add_theme_constant_override("margin_bottom", 72 if visible and showing_game else 84 if visible else 0 if showing_game else 20)
	if visible:
		call_deferred("_focus_persistence_recovery")

func _focus_persistence_recovery() -> void:
	if is_instance_valid(persistence_reload_button) and persistence_reload_button.is_visible_in_tree() and not persistence_reload_button.disabled:
		persistence_reload_button.grab_focus()

func _reload_after_persistence_block() -> void:
	if not session.is_reload_required():
		return
	var was_showing_game := showing_game
	persistence_reload_button.disabled = true
	if session.load_game():
		if not was_showing_game:
			_show_game()
		return
	persistence_reload_button.disabled = false
	_focus_persistence_recovery()

func _toggle_title_settings() -> void:
	settings_overlay.visible = not settings_overlay.visible

func _toggle_fullscreen(enabled: bool) -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if enabled else DisplayServer.WINDOW_MODE_WINDOWED)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and is_instance_valid(new_game_confirmation) and new_game_confirmation.visible:
		_cancel_new_game()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept") and is_instance_valid(new_game_confirmation) and new_game_confirmation.visible:
		var owner := get_viewport().gui_get_focus_owner()
		if owner == null or not new_game_confirmation.is_ancestor_of(owner):
			_focus_new_game_modal()
			get_viewport().set_input_as_handled()
