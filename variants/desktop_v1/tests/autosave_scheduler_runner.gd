extends SceneTree

var failures: Array[String] = []
var assertions := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var session: Node = root.get_node("GameSession")
	session.new_game(9401)
	session.state.units.biter = 5
	_assert_true(session.attack_node("C"), "scheduler fixture must start a real battle")
	_assert_true(session.save_game(), "scheduler fixture must create primary")
	_assert_true(session.save_game(), "scheduler fixture must create backup")
	var primary_before := FileAccess.get_file_as_string(session.DEFAULT_SAVE_PATH)
	var tick_before := int(session.state.tick)
	session.set_process(true)
	await create_timer(31.2).timeout
	session.set_process(false)
	var primary_after := FileAccess.get_file_as_string(session.DEFAULT_SAVE_PATH)
	var parser := JSON.new()
	_assert_equal(parser.parse(primary_after), OK, "real autosave must leave parseable JSON")
	var disk_tick := int(parser.data.get("tick", -1)) if parser.data is Dictionary else -1
	var backup_parser := JSON.new()
	var backup_text := FileAccess.get_file_as_string(session.DEFAULT_SAVE_PATH + session.BACKUP_SUFFIX)
	_assert_equal(backup_parser.parse(backup_text), OK, "real autosave must retain a parseable backup")
	var backup_tick := int(backup_parser.data.get("tick", -1)) if backup_parser.data is Dictionary else -1
	_assert_true(primary_after != primary_before, "real 31-second scheduler must replace the primary bytes")
	_assert_true(disk_tick >= tick_before + 29, "real scheduler must persist continuous simulation progress")
	_assert_true(backup_tick >= tick_before and backup_tick < disk_tick, "real autosave must preserve a prior complete generation as backup")
	_assert_true(session.state.active_battle.is_empty() or int(session.state.active_battle.elapsed) > 0, "real scheduler must progress the active battle")
	_assert_true(not session.is_persistence_blocked(), "real autosave must leave persistence enabled")
	if failures.is_empty():
		print("AUTOSAVE_SCHEDULER_OK elapsed=31.2 disk_tick=%d assertions=%d" % [disk_tick, assertions])
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("AUTOSAVE_SCHEDULER_FAILED assertions=%d failures=%d" % [assertions, failures.size()])
		quit(1)

func _assert_true(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures.append(message)

func _assert_equal(actual: Variant, expected: Variant, message: String) -> void:
	assertions += 1
	if actual != expected:
		failures.append("%s (actual=%s expected=%s)" % [message, actual, expected])
