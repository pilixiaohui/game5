extends SceneTree

const VIEWPORT_WIDTH := 540.0
const VIEWPORT_HEIGHT := 960.0
const SCREENSHOT_PATH := "/tmp/first_version_loop_probe.png"

var _failures: Array[String] = []

func _initialize() -> void:
	DisplayServer.window_set_size(Vector2i(540, 960))
	root.size = Vector2i(540, 960)
	call_deferred("_run")

func _run() -> void:
	var GameState = root.get_node_or_null("GameState")
	var SimulationService = root.get_node_or_null("SimulationService")
	if GameState == null or SimulationService == null:
		_fail("first-version probe requires GameState and SimulationService autoloads")
		_finish()
		return

	GameState.reset_new_game(false)
	GameState.ensure_config_defaults()
	var main_scene: PackedScene = load("res://scenes/app/Main.tscn")
	var main := main_scene.instantiate()
	main.size = Vector2(VIEWPORT_WIDTH, VIEWPORT_HEIGHT)
	root.add_child(main)
	await process_frame
	await process_frame
	main.call("_refresh")

	var scroll := _find_scroll_container(main)
	_expect(scroll != null, "formal entry should render inside a ScrollContainer")
	if scroll != null:
		_expect(scroll.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED, "formal entry should disable horizontal scroll at 540px")
		_expect(not scroll.get_h_scroll_bar().visible, "formal entry should not show a horizontal scrollbar")

	var start_button: Button = main.get("_start_button")
	var continue_button: Button = main.get("_continue_button")
	var restart_button: Button = main.get("_restart_button")
	var session_label: Label = main.get("_session_label")
	var session_result_label: Label = main.get("_session_result_label")
	_expect(start_button != null and continue_button != null and restart_button != null, "start/continue/restart buttons should be present on the first screen")
	_expect(session_label != null and session_label.text.find("首局目标链") >= 0, "first screen should explain the first-session objective chain")
	_expect(session_result_label != null and session_result_label.text.find("战术选择") >= 0, "first screen should explain risk/reward build choices")
	for control in [start_button, continue_button, restart_button, session_label, session_result_label]:
		_expect(_control_fits_viewport(control), "first screen control should fit within the 540px viewport: %s" % str(control))

	start_button.pressed.emit()
	await process_frame
	_expect(String(GameState.feedback).find("首局开始") >= 0, "start should produce first-session feedback")
	GameState.resources["pulp"] = 1.0
	continue_button.pressed.emit()
	await process_frame
	_expect(String(GameState.feedback).find("已读取存档") >= 0 or String(GameState.feedback).find("没有可继续") >= 0, "continue should produce load/settlement feedback")
	GameState.resources["pulp"] = 999.0
	restart_button.pressed.emit()
	await process_frame
	_expect(String(GameState.feedback).find("首局已重开") >= 0, "restart should produce clear restart feedback")

	GameState.resources = {"pulp": 999.0, "enzyme": 999.0, "helix": 999.0, "larva": 99.0, "mutation": 0.0}
	GameState.total_devour = 200.0
	GameState.region_unlocked["research_bastion"] = true
	GameState.active_region = "research_bastion"
	GameState.ensure_config_defaults()
	main.call("_refresh")
	await process_frame

	var plugin_buttons: Dictionary = main.get("_plugin_buttons")
	var acid_button: Button = plugin_buttons.get("acid_reservoir", null)
	var shell_button: Button = plugin_buttons.get("hardened_carapace", null)
	_expect(acid_button != null and shell_button != null, "formal UI should expose both first-version build choices")
	if acid_button != null and shell_button != null:
		acid_button.pressed.emit()
		await process_frame
		_expect(String(GameState.feedback).find("酸液囊仓 -> 爆裂虫槽") >= 0, "acid build click should expose baneling slot feedback")
		var acid_projection: Dictionary = SimulationService.battle_projection("baneling")
		_expect(float(acid_projection.get("plugin_bonus", 0.0)) > 0.0, "acid build should change real combat projection")

		main.call("_on_battlefield_command", "prepare")
		await process_frame
		_expect(int(GameState.reserves.get("baneling", 0)) > 0, "left battlefield prepare should create real baneling reserve")
		main.call("_on_battlefield_command", "assault")
		SimulationService.simulate_seconds(4.0, true)
		main.call("_refresh")
		await _wait_frames(8)
		_expect(float(GameState.region_progress.get("research_bastion", 0.0)) > 0.0, "center assault should advance research bastion through real rules")
		_expect(float(GameState.battle_report.get("power", 0.0)) > float(GameState.battle_report.get("pressure", 0.0)), "advance should be caused by power exceeding pressure")
		var view = main.get("_battlefield_view")
		_expect(view != null, "formal entry should expose battlefield presentation")
		if view != null:
			var stats: Dictionary = view.call("presentation_stats")
			var node_cap: int = int(stats.get("max_allowed", 48)) * 3 + 12
			_expect(_count_nodes(view) <= node_cap, "first-version battle presentation should stay within node cap")

		main.call("_on_battlefield_command", "retreat")
		await process_frame
		_expect(String(GameState.feedback).find("撤离") >= 0, "right battlefield retreat should produce preservation feedback")

		shell_button.pressed.emit()
		await process_frame
		_expect(String(GameState.feedback).find("硬化背甲 -> 甲壳卫士槽") >= 0, "shell build click should expose carapace guard slot feedback")
		var shell_projection: Dictionary = SimulationService.battle_projection("carapace_guard")
		_expect(float(shell_projection.get("loss_rate", 1.0)) < float(acid_projection.get("loss_rate", 0.0)), "shell build should expose a lower-loss tradeoff than acid baneling")

	GameState.reset_new_game(false)
	GameState.ensure_config_defaults()
	GameState.resources = {"pulp": 0.0, "enzyme": 0.0, "helix": 0.0, "larva": 0.0, "mutation": 0.0}
	GameState.total_devour = 200.0
	GameState.region_unlocked["research_bastion"] = true
	GameState.active_region = "research_bastion"
	GameState.ensure_config_defaults()
	main.call("_on_battlefield_command", "assault")
	await process_frame
	var failure_snapshot: Dictionary = main.call("_battlefield_snapshot")
	var failure_text: String = String(main.call("_first_version_result_text", failure_snapshot))
	_expect(String(GameState.battle_report.get("mode", "")) == "understrength", "understrength first-session assault should fail through rules")
	_expect(failure_text.find("失败反馈") >= 0, "formal entry should surface failure feedback")

	await RenderingServer.frame_post_draw
	_expect(_save_viewport_png(SCREENSHOT_PATH) == OK, "first-version loop screenshot should be saved for review")
	if _failures.is_empty():
		print("FIRST_VERSION_LOOP_PROBE_OK screenshot=%s progress=%.2f failure=\"%s\"" % [
			SCREENSHOT_PATH,
			float(GameState.region_progress.get("research_bastion", 0.0)),
			failure_text
		])
	main.queue_free()
	await process_frame
	_finish()

func _wait_frames(count: int) -> void:
	for _i in range(count):
		await process_frame

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

func _count_nodes(node: Node) -> int:
	var total := 1
	for child in node.get_children():
		total += _count_nodes(child)
	return total

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
		quit(0)
	else:
		quit(1)
