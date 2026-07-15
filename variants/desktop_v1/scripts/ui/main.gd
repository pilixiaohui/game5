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

func _ready() -> void:
	theme = ThemeFactory.build()
	set_process_unhandled_input(true)
	_build_background()
	if not GameSession.notice_posted.is_connected(_show_title_notice):
		GameSession.notice_posted.connect(_show_title_notice)
	if "--demo" in OS.get_cmdline_user_args():
		GameSession.new_game(2707)
		GameSession.build_room(0, "thermal_metabolism")
		GameSession.build_room(1, "biomass_filter")
		GameSession.build_room(4, "embryo_hatchery")
		GameSession.advance_steps(22)
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

func _show_title() -> void:
	UI.clear(content)
	content.add_theme_constant_override("margin_left", 24)
	content.add_theme_constant_override("margin_right", 24)
	content.add_theme_constant_override("margin_top", 20)
	content.add_theme_constant_override("margin_bottom", 20)
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
	continue_button.disabled = not GameSession.has_save()
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
	confirm.focus_next = confirm.get_path_to(cancel)
	cancel.focus_neighbor_left = cancel.get_path_to(confirm)
	cancel.focus_neighbor_right = cancel.get_path_to(confirm)
	cancel.focus_next = cancel.get_path_to(confirm)

func _new_game() -> void:
	if GameSession.has_save():
		new_game_confirmation.visible = true
		var cancel := new_game_confirmation.find_child("CancelNewGameButton", true, false) as Button
		if cancel:
			cancel.grab_focus()
		return
	_start_new_game()

func _confirm_new_game() -> void:
	new_game_confirmation.visible = false
	_start_new_game()

func _cancel_new_game() -> void:
	_close_new_game_confirmation()
	_show_title_notice("已取消重开，当前状态和存档未改变。", "info")

func _close_new_game_confirmation() -> void:
	new_game_confirmation.visible = false
	if is_instance_valid(new_game_button):
		new_game_button.grab_focus()

func _start_new_game() -> void:
	GameSession.new_game()
	if GameSession.save_game():
		_show_game()

func _continue_game() -> void:
	if GameSession.load_game():
		_show_game()

func _show_title_notice(message: String, level: String) -> void:
	if not is_instance_valid(title_notice):
		return
	title_notice.text = message
	title_notice.theme_type_variation = "Warning" if level == "warning" else "Muted"
	title_notice.visible = true

func _show_game() -> void:
	if is_instance_valid(new_game_confirmation):
		new_game_confirmation.visible = false
	UI.clear(content)
	content.add_theme_constant_override("margin_left", 0)
	content.add_theme_constant_override("margin_right", 0)
	content.add_theme_constant_override("margin_top", 0)
	content.add_theme_constant_override("margin_bottom", 0)
	var shell := GameShell.new()
	content.add_child(shell)

func _toggle_title_settings() -> void:
	settings_overlay.visible = not settings_overlay.visible

func _toggle_fullscreen(enabled: bool) -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if enabled else DisplayServer.WINDOW_MODE_WINDOWED)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and is_instance_valid(new_game_confirmation) and new_game_confirmation.visible:
		_cancel_new_game()
		get_viewport().set_input_as_handled()
