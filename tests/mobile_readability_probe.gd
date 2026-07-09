extends SceneTree

var _failures: Array[String] = []

func _initialize() -> void:
	DisplayServer.window_set_size(Vector2i(540, 960))
	call_deferred("_run")

func _run() -> void:
	var GameState = root.get_node_or_null("GameState")
	if GameState == null:
		_fail("GameState autoload missing")
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

	main.queue_free()
	_finish()

func _find_scroll_container(node: Node) -> ScrollContainer:
	if node is ScrollContainer:
		return node
	for child in node.get_children():
		var found := _find_scroll_container(child)
		if found != null:
			return found
	return null

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
