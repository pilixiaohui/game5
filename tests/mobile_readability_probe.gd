extends SceneTree

var _failures: Array[String] = []
const VIEWPORT_WIDTH := 540.0
const VIEWPORT_HEIGHT := 960.0
const ACID_SCREENSHOT_PATH := "/tmp/stage3_mobile_acid_plugin.png"
const BATTLE_SCREENSHOT_PATH := "/tmp/stage3_mobile_battle_feedback.png"
const SHELL_SCREENSHOT_PATH := "/tmp/stage3_mobile_hardened_plugin.png"

func _initialize() -> void:
	DisplayServer.window_set_size(Vector2i(540, 960))
	root.size = Vector2i(540, 960)
	call_deferred("_run")

func _run() -> void:
	var GameState = root.get_node_or_null("GameState")
	var SimulationService = root.get_node_or_null("SimulationService")
	if GameState == null:
		_fail("GameState autoload missing")
		_finish()
		return
	if SimulationService == null:
		_fail("SimulationService autoload missing")
		_finish()
		return

	GameState.reset_new_game(false)
	GameState.ensure_config_defaults()
	GameState.resources = {"pulp": 999.0, "enzyme": 999.0, "helix": 999.0, "larva": 99.0, "mutation": 0.0}
	GameState.total_devour = 200.0
	GameState.region_progress["slum_edge"] = 100.0
	GameState.region_progress["factory_wall"] = 100.0
	GameState.region_unlocked["factory_wall"] = true
	GameState.region_unlocked["research_bastion"] = true
	GameState.active_region = "factory_wall"
	GameState.ensure_config_defaults()

	var main_scene: PackedScene = load("res://scenes/app/Main.tscn")
	var main := main_scene.instantiate()
	main.size = Vector2(540, 960)
	root.add_child(main)
	await process_frame
	main.call("_refresh")
	await process_frame

	var scroll := _find_scroll_container(main)
	_expect(scroll != null, "public UI should contain a ScrollContainer")
	if scroll != null:
		_expect(scroll.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED, "horizontal scroll should be disabled at 540px")
		_expect(not scroll.get_h_scroll_bar().visible, "horizontal scrollbar should not be visible at 540px")
		if scroll.get_child_count() > 0:
			var content := scroll.get_child(0) as Control
			if content != null:
				_expect(content.size.x <= scroll.size.x + 1.0, "main content should fit within the 540px viewport")

	var guide: Label = main.get("_guide_label")
	_expect(guide != null, "guide label should exist")
	if guide != null:
		_expect(guide.text.find("点击战场切换研究堡垒外环") >= 0, "completed factory guide should point to research bastion")
		_expect(guide.text.find("推进工厂") < 0, "completed factory guide should not keep stale factory assault text")
		_expect(guide.autowrap_mode == TextServer.AUTOWRAP_ARBITRARY, "guide should wrap in narrow mobile width")

	var unit_buttons: Dictionary = main.get("_unit_buttons")
	var baneling_button: Button = unit_buttons.get("baneling", null)
	var guard_button: Button = unit_buttons.get("carapace_guard", null)
	_expect(baneling_button != null and baneling_button.text.find("高推进/高损耗") >= 0, "baneling button should show short role tag")
	_expect(guard_button != null and guard_button.text.find("稳推进/低损耗") >= 0, "carapace guard button should show short role tag")
	if baneling_button != null:
		_expect(baneling_button.autowrap_mode == TextServer.AUTOWRAP_ARBITRARY, "unit buttons should wrap instead of widening")
	if guard_button != null:
		_expect(guard_button.autowrap_mode == TextServer.AUTOWRAP_ARBITRARY, "unit buttons should wrap instead of widening")

	GameState.active_region = "research_bastion"
	GameState.ensure_config_defaults()
	main.call("_refresh")
	await process_frame
	var plugin_buttons: Dictionary = main.get("_plugin_buttons")
	var acid_button: Button = plugin_buttons.get("acid_reservoir", null)
	var shell_button: Button = plugin_buttons.get("hardened_carapace", null)
	_expect(acid_button != null, "acid reservoir plugin button should exist in formal UI")
	_expect(shell_button != null, "hardened carapace plugin button should exist in formal UI")
	if acid_button != null:
		_expect(acid_button.text.find("酸液囊仓 -> 爆裂虫槽") >= 0, "acid plugin button should show its unit build slot")
		_expect(acid_button.text.find("腐蚀破甲") >= 0 and acid_button.text.find("酸蚀爆燃") >= 0, "acid plugin button should show status and reaction labels")
		_expect(acid_button.get_combined_minimum_size().x <= 520.0, "acid plugin button minimum width should fit 540px viewport")
		_expect(not acid_button.clip_text, "acid plugin button should not clip wrapped text")
		_expect(acid_button.alignment == HORIZONTAL_ALIGNMENT_LEFT, "acid plugin button text should be left-aligned inside the viewport")
		_expect(acid_button.size.y >= 118.0, "acid plugin build-card should have enough rendered height for wrapped rows")
		_expect(_control_fits_viewport(acid_button), "acid plugin rendered rect should fit within the 540px viewport")
	if shell_button != null:
		_expect(shell_button.text.find("硬化背甲 -> 甲壳卫士槽") >= 0, "shell plugin button should show its unit build slot")
		_expect(shell_button.text.find("硬化减损") >= 0 and shell_button.text.find("甲壳偏折") >= 0, "shell plugin button should show status and reaction labels")
		_expect(shell_button.get_combined_minimum_size().x <= 520.0, "shell plugin button minimum width should fit 540px viewport")
		_expect(not shell_button.clip_text, "shell plugin button should not clip wrapped text")
		_expect(shell_button.alignment == HORIZONTAL_ALIGNMENT_LEFT, "shell plugin button text should be left-aligned inside the viewport")
		_expect(shell_button.size.y >= 118.0, "shell plugin build-card should have enough rendered height for wrapped rows")
		_expect(_control_fits_viewport(shell_button), "shell plugin rendered rect should fit within the 540px viewport")

	if acid_button != null and shell_button != null:
		var acid_capture_rect := Rect2()
		var battle_capture_rect := Rect2()
		var shell_capture_rect := Rect2()
		_scroll_to_control(scroll, acid_button)
		await process_frame
		_expect(_control_visible_in_viewport(acid_button), "acid plugin button should be visible inside the captured 540x960 frame")
		acid_capture_rect = acid_button.get_global_rect()
		await RenderingServer.frame_post_draw
		_expect(_save_viewport_png(ACID_SCREENSHOT_PATH) == OK, "acid plugin rendered screenshot should be saved for review")

		acid_button.pressed.emit()
		await process_frame
		_expect(String(GameState.feedback).find("酸液囊仓 -> 爆裂虫槽") >= 0, "public acid plugin click should surface build slot feedback")
		_expect(String(GameState.feedback).find("腐蚀破甲") >= 0 and String(GameState.feedback).find("酸蚀爆燃") >= 0, "public acid plugin click should surface status/reaction feedback")
		_expect(SimulationService.hatch_unit("baneling", 3), "mobile probe should hatch banelings through service path after public plugin click")
		_expect(SimulationService.assault_push("baneling"), "mobile probe should commit baneling assault through service path")
		SimulationService.simulate_seconds(2.0, true)
		main.call("_refresh")
		await process_frame
		var battle_snapshot: Dictionary = main.call("_battlefield_snapshot")
		_expect(String(battle_snapshot.get("reaction_text", "")).find("酸蚀爆燃") >= 0, "battlefield snapshot should show acid reaction feedback")
		_expect(String(battle_snapshot.get("unit_readout_text", "")).find("酸蚀爆燃") >= 0, "battlefield readout should include acid reaction label")
		var battlefield = main.get("_battlefield_view")
		_expect(battlefield != null and _control_fits_viewport(battlefield), "battlefield view rendered rect should fit within the 540px viewport")
		var command_label: Label = main.get("_battle_command_label")
		_expect(command_label != null and _control_fits_viewport(command_label), "battle command hint should fit within the 540px viewport")
		_scroll_to_control(scroll, battlefield)
		await process_frame
		_expect(_control_visible_in_viewport(battlefield), "battlefield feedback should be visible inside the captured 540x960 frame")
		battle_capture_rect = battlefield.get_global_rect()
		await RenderingServer.frame_post_draw
		_expect(_save_viewport_png(BATTLE_SCREENSHOT_PATH) == OK, "battle feedback rendered screenshot should be saved for review")

		shell_button.pressed.emit()
		await process_frame
		_expect(String(GameState.feedback).find("硬化背甲 -> 甲壳卫士槽") >= 0, "public shell plugin click should surface build slot feedback")
		_expect(String(GameState.feedback).find("硬化减损") >= 0 and String(GameState.feedback).find("甲壳偏折") >= 0, "public shell plugin click should surface status/reaction feedback")
		main.call("_refresh")
		await process_frame
		if scroll != null and scroll.get_child_count() > 0:
			var refreshed_content := scroll.get_child(0) as Control
			if refreshed_content != null:
				_expect(refreshed_content.size.x <= scroll.size.x + 1.0, "stage3 plugin UI content should still fit within the 540px viewport")
		_scroll_to_control(scroll, shell_button)
		await process_frame
		_expect(_control_visible_in_viewport(shell_button), "shell plugin button should be visible inside the captured 540x960 frame")
		shell_capture_rect = shell_button.get_global_rect()
		await RenderingServer.frame_post_draw
		_expect(_save_viewport_png(SHELL_SCREENSHOT_PATH) == OK, "shell plugin rendered screenshot should be saved for review")
		print("STAGE3_RENDER_GEOMETRY_OK acid_rect=%s battle_rect=%s shell_rect=%s screenshots=%s,%s,%s" % [str(acid_capture_rect), str(battle_capture_rect), str(shell_capture_rect), ACID_SCREENSHOT_PATH, BATTLE_SCREENSHOT_PATH, SHELL_SCREENSHOT_PATH])
		print("STAGE3_MOBILE_BUILD_LABELS_OK acid=\"%s\" shell=\"%s\"" % [acid_button.text.split("\n")[1], shell_button.text.split("\n")[1]])

	main.queue_free()
	await process_frame
	_finish()

func _find_scroll_container(node: Node) -> ScrollContainer:
	if node is ScrollContainer:
		return node
	for child in node.get_children():
		var found := _find_scroll_container(child)
		if found != null:
			return found
	return null

func _control_fits_viewport(control: Control) -> bool:
	if control == null:
		return false
	var rect := control.get_global_rect()
	return rect.position.x >= -0.5 and rect.end.x <= VIEWPORT_WIDTH + 0.5 and rect.size.x <= VIEWPORT_WIDTH + 0.5

func _control_visible_in_viewport(control: Control) -> bool:
	if not _control_fits_viewport(control):
		return false
	var rect := control.get_global_rect()
	return rect.position.y >= -0.5 and rect.end.y <= VIEWPORT_HEIGHT + 0.5

func _scroll_to_control(scroll: ScrollContainer, control: Control) -> void:
	if scroll == null or control == null:
		return
	var rect := control.get_global_rect()
	var target_y: int = maxi(0, scroll.scroll_vertical + int(rect.position.y) - 64)
	scroll.scroll_vertical = target_y

func _save_viewport_png(path: String) -> Error:
	var image := root.get_viewport().get_texture().get_image()
	return image.save_png(path)

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)

func _fail(message: String) -> void:
	_failures.append(message)
	push_error(message)

func _finish() -> void:
	if _failures.is_empty():
		print("MOBILE_READABILITY_PROBE_OK")
		quit(0)
	else:
		quit(1)
