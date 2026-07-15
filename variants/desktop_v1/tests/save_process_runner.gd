extends SceneTree

const PHASE_PREFIX := "--phase="

var session: Node
var failures: Array[String] = []
var assertions := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	session = root.get_node("GameSession")
	session.set_process(false)
	var phase := _phase_argument()
	match phase:
		"seed": _seed_disk_save()
		"load-progress-autosave": _load_progress_autosave()
		"reload": _reload_after_autosave()
		_: failures.append("unknown save-process phase: %s" % phase)
	if failures.is_empty():
		print("SAVE_PROCESS_OK phase=%s assertions=%d" % [phase, assertions])
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("SAVE_PROCESS_FAILED phase=%s assertions=%d failures=%d" % [phase, assertions, failures.size()])
		quit(1)

func _seed_disk_save() -> void:
	session.new_game(9001)
	session.state.resources.biomass = 2000.0
	session.state.processing.field_organic = 1000.0
	_assert_true(session.build_room(0, "thermal_metabolism"), "fixture must build power")
	_assert_true(session.build_room(1, "biomass_filter"), "fixture must build production")
	_assert_true(session.build_room(4, "embryo_hatchery"), "fixture must build hatchery")
	session.advance_steps(150)
	_assert_true(int(session.state.units.biter) > 0, "fixture must form combat units")
	_assert_true(session.attack_node("C"), "fixture must enter a persistent battle")
	session.advance_steps(2)
	_assert_true(not session.state.active_battle.is_empty(), "fixture battle must remain active at save time")
	_assert_true(session.save_game(), "first disk save must succeed")
	_assert_true(session.save_game(), "second disk save must establish a backup")
	_assert_true(FileAccess.file_exists(session.DEFAULT_SAVE_PATH), "primary slot must exist")
	_assert_true(FileAccess.file_exists(session.DEFAULT_SAVE_PATH + ".bak"), "backup slot must exist")

func _load_progress_autosave() -> void:
	_assert_true(session.load_game(), "a new process must load the disk save")
	_assert_runtime_numeric_types()
	var tick_before := int(session.state.tick)
	var enemy_before := int(session.state.active_battle.enemy)
	session.advance_steps(40)
	_assert_equal(int(session.state.tick), tick_before + 40, "loaded simulation must advance every requested tick")
	_assert_true(session.state.active_battle.is_empty() or int(session.state.active_battle.enemy) < enemy_before, "loaded battle must progress rather than freeze")
	_assert_runtime_numeric_types()
	_assert_true(session.save_game(), "manual save after loaded simulation progress must succeed")
	_assert_true(FileAccess.file_exists(session.DEFAULT_SAVE_PATH), "progress save must retain the primary slot")
	_assert_true(FileAccess.file_exists(session.DEFAULT_SAVE_PATH + ".bak"), "progress save must retain a backup")

func _reload_after_autosave() -> void:
	_assert_true(session.load_game(), "a third process must load the post-autosave slot")
	_assert_runtime_numeric_types()
	var tick_before := int(session.state.tick)
	session.advance_steps(3)
	_assert_equal(int(session.state.tick), tick_before + 3, "reloaded simulation must remain live")
	_assert_true(session.save_game(), "reloaded state must remain serializable")

func _assert_runtime_numeric_types() -> void:
	_assert_equal(typeof(session.state.seed), TYPE_INT, "seed must normalize to int")
	_assert_equal(typeof(session.state.tick), TYPE_INT, "tick must normalize to int")
	_assert_equal(typeof(session.state.speed), TYPE_INT, "speed must normalize to int")
	for key in session.state.units.keys():
		_assert_equal(typeof(session.state.units[key]), TYPE_INT, "units.%s must normalize to int" % key)
	for key in session.state.targets.keys():
		_assert_equal(typeof(session.state.targets[key]), TYPE_INT, "targets.%s must normalize to int" % key)
	for key in session.state.resources.keys():
		_assert_equal(typeof(session.state.resources[key]), TYPE_FLOAT, "resources.%s must normalize to float" % key)
	for key in session.state.energy.keys():
		_assert_equal(typeof(session.state.energy[key]), TYPE_FLOAT, "energy.%s must normalize to float" % key)
	for key in session.state.processing.keys():
		_assert_equal(typeof(session.state.processing[key]), TYPE_FLOAT, "processing.%s must normalize to float" % key)
	for room in session.state.rooms:
		_assert_equal(typeof(room.slot), TYPE_INT, "room.slot must normalize to int")
		_assert_equal(typeof(room.progress), TYPE_FLOAT, "room.progress must normalize to float")
		_assert_equal(typeof(room.task_progress), TYPE_FLOAT, "room.task_progress must normalize to float")
	for node in session.state.nodes:
		for key in ["base_enemy", "structure", "enemy", "enemy_max", "structure_hp", "structure_max", "assaults"]:
			_assert_equal(typeof(node[key]), TYPE_INT, "node.%s must normalize to int" % key)
		_assert_equal(typeof(node.pos[0]), TYPE_FLOAT, "node.pos[0] must normalize to float")
		_assert_equal(typeof(node.pos[1]), TYPE_FLOAT, "node.pos[1] must normalize to float")
	if not session.state.active_battle.is_empty():
		for key in ["enemy", "enemy_max", "structure_hp", "structure_max", "biter", "spore", "roots", "elapsed", "kills", "losses"]:
			_assert_equal(typeof(session.state.active_battle[key]), TYPE_INT, "active_battle.%s must normalize to int" % key)
	for mutation in session.state.mutations:
		_assert_equal(typeof(mutation.cost), TYPE_INT, "mutation.cost must normalize to int")
	if not session.state.candidate_group.is_empty():
		for option in session.state.candidate_group.options:
			_assert_equal(typeof(option.cost), TYPE_INT, "candidate cost must normalize to int")
	for milestone in session.state.milestones.values():
		_assert_equal(typeof(milestone), TYPE_INT, "milestone tick must normalize to int")
	for event in session.state.ledger:
		_assert_equal(typeof(event.tick), TYPE_INT, "ledger tick must normalize to int")
	for key in ["biomass_formed", "genes_formed"]:
		_assert_equal(typeof(session.state.stats[key]), TYPE_FLOAT, "stats.%s must normalize to float" % key)
	for key in ["enemies_defeated", "nodes_captured", "retreats", "candidate_groups"]:
		_assert_equal(typeof(session.state.stats[key]), TYPE_INT, "stats.%s must normalize to int" % key)
	_assert_equal(typeof(session.state.settings.ui_scale), TYPE_FLOAT, "settings.ui_scale must normalize to float")
	_assert_equal(typeof(session.state.settings.master_volume), TYPE_FLOAT, "settings.master_volume must normalize to float")

func _phase_argument() -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with(PHASE_PREFIX):
			return argument.trim_prefix(PHASE_PREFIX)
	return ""

func _assert_true(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures.append(message)

func _assert_equal(actual: Variant, expected: Variant, message: String) -> void:
	assertions += 1
	if actual != expected:
		failures.append("%s (actual=%s expected=%s)" % [message, actual, expected])
