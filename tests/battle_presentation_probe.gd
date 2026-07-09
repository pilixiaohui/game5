extends SceneTree

var _failures: Array[String] = []

func _initialize() -> void:
	DisplayServer.window_set_size(Vector2i(540, 960))
	call_deferred("_run")

func _run() -> void:
	var ConfigDB = root.get_node_or_null("ConfigDB")
	var GameState = root.get_node_or_null("GameState")
	var SimulationService = root.get_node_or_null("SimulationService")
	if ConfigDB == null or GameState == null or SimulationService == null:
		_fail("autoload services should exist for battle presentation probe")
		_finish()
		return

	GameState.reset_new_game(false)
	GameState.ensure_config_defaults()
	GameState.resources = {"pulp": 2000.0, "enzyme": 600.0, "helix": 120.0, "larva": 120.0, "mutation": 0.0}
	GameState.total_devour = 250.0
	for region_id in ConfigDB.regions.keys():
		GameState.region_unlocked[region_id] = true
	GameState.active_region = "slum_edge"
	GameState.ensure_config_defaults()

	var main_scene: PackedScene = load("res://scenes/app/Main.tscn")
	var main := main_scene.instantiate()
	main.size = Vector2(540, 960)
	root.add_child(main)
	await process_frame
	await process_frame

	_expect(SimulationService.hatch_unit("zergling", 18), "probe should hatch enough zerglings for a visible wave")
	_expect(SimulationService.assault_push("zergling"), "probe should commit a public assault through service rules")
	SimulationService.simulate_seconds(8.0, true)
	main.call("_refresh")
	await _wait_frames(8)

	var view = main.get("_battlefield_view")
	_expect(view != null, "official main scene should expose battlefield view")
	if view == null:
		main.queue_free()
		await process_frame
		_finish()
		return

	var active_after_assault := int(view.call("presentation_active_count"))
	var assault_stats: Dictionary = view.call("presentation_stats")
	_expect(active_after_assault >= 30, "presentation battle should show at least 30 active units at 540x960")
	_expect(int(assault_stats.get("max_active_seen", 0)) >= 30, "presentation stats should record 30+ active units")

	var loss_snapshot: Dictionary = main.call("_battlefield_snapshot")
	loss_snapshot["mode"] = "stalled"
	loss_snapshot["front_motion"] = "back"
	loss_snapshot["lost"] = 6
	loss_snapshot["field_total"] = maxi(10, int(loss_snapshot.get("field_total", 0)))
	loss_snapshot["unit_fields"] = {"zergling": int(loss_snapshot["field_total"])}
	var lost_before := int(view.call("presentation_stats").get("lost_recycled_total", 0))
	view.call("set_snapshot", loss_snapshot)
	await _wait_frames(3)
	var lost_after := int(view.call("presentation_stats").get("lost_recycled_total", 0))
	_expect(lost_after > lost_before, "loss snapshot should recycle dead presentation units")

	var active_before_retreat := int(view.call("presentation_active_count"))
	SimulationService.retreat()
	main.call("_refresh")
	await _wait_frames(6)
	var retreat_stats: Dictionary = view.call("presentation_stats")
	_expect(active_before_retreat > 0, "probe should have active presentation units before retreat")
	_expect(int(view.call("presentation_active_count")) == 0, "retreat should clear active presentation units")
	_expect(int(retreat_stats.get("retreat_recycled_total", 0)) > 0, "retreat should recycle presentation units")

	var leak_snapshot: Dictionary = loss_snapshot.duplicate(true)
	leak_snapshot["mode"] = "advance"
	leak_snapshot["front_motion"] = "forward"
	leak_snapshot["lost"] = 0
	leak_snapshot["retreat_value"] = 0
	leak_snapshot["retreat_field_before"] = 0
	view.call("set_snapshot", leak_snapshot)
	await _wait_frames(3)
	var director: Node = view.get_node_or_null("BattleDirector")
	for _i in range(120):
		if director != null:
			director.call("_process", 1.0)
	var leak_stats: Dictionary = view.call("presentation_stats")
	_expect(int(leak_stats.get("active_count", 0)) <= int(leak_stats.get("max_allowed", 48)), "2 minute simulated presentation should stay within active cap")
	var node_cap: int = int(leak_stats.get("max_allowed", 48)) * 3 + 6
	_expect(_count_nodes(view) <= node_cap, "2 minute simulated presentation should not leak scene nodes")

	if _failures.is_empty():
		print("BATTLE_PRESENTATION_PROBE_OK active=%d max=%d lost_recycled=%d retreat_recycled=%d nodes=%d cap=%d" % [
			active_after_assault,
			int(leak_stats.get("max_active_seen", 0)),
			int(leak_stats.get("lost_recycled_total", 0)),
			int(leak_stats.get("retreat_recycled_total", 0)),
			_count_nodes(view),
			node_cap
		])
	main.queue_free()
	await process_frame
	_finish()

func _wait_frames(count: int) -> void:
	for _i in range(count):
		await process_frame

func _count_nodes(node: Node) -> int:
	var total := 1
	for child in node.get_children():
		total += _count_nodes(child)
	return total

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
