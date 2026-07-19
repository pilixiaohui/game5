extends SceneTree

var assertions := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var session := root.get_node("GameSession")
	session.set_process(false)
	var scratch_data_root := _argument("--scratch-data-root=").simplify_path()
	var save_path := ProjectSettings.globalize_path(session.DEFAULT_SAVE_PATH).simplify_path()
	_assert_true(not scratch_data_root.is_empty(), "isolation runner requires an owned XDG data root")
	_assert_true(save_path.begins_with(scratch_data_root + "/"), "production save path must remain inside the owned XDG data root")
	_cleanup_slots(session)
	session.new_game(9101)
	session.advance_steps(7)
	var expected_tick := int(session.state.tick)
	var expected_seed := int(session.state.seed)
	_assert_true(session.save_game(), "production isolation entry must save to its owned XDG root")
	session.state.tick = expected_tick + 1000
	session.state.seed = expected_seed + 1000
	_assert_true(session.load_game(), "production isolation entry must reload its owned save")
	_assert_equal(int(session.state.tick), expected_tick, "reload must restore the owned disk tick")
	_assert_equal(int(session.state.seed), expected_seed, "reload must restore the owned disk seed")
	_cleanup_slots(session)
	for suffix in ["", session.BACKUP_SUFFIX, session.SAVE_TEMP_SUFFIX, session.BACKUP_TEMP_SUFFIX, session.BACKUP_PREVIOUS_SUFFIX, session.ROLLBACK_SUFFIX, session.RECOVERY_SUFFIX, session.BACKUP_SUFFIX + session.RECOVERY_SUFFIX]:
		_assert_true(not FileAccess.file_exists(session.DEFAULT_SAVE_PATH + suffix), "isolation entry must clean owned slot artifact %s" % suffix)
	if failures.is_empty():
		print("ISOLATION_PRODUCTION_ENTRY_OK assertions=%d authority=tick,seed scratch=clean" % assertions)
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("ISOLATION_PRODUCTION_ENTRY_FAILED assertions=%d failures=%d" % [assertions, failures.size()])
		quit(1)

func _cleanup_slots(session: Node) -> void:
	for suffix in ["", session.BACKUP_SUFFIX, session.SAVE_TEMP_SUFFIX, session.BACKUP_TEMP_SUFFIX, session.BACKUP_PREVIOUS_SUFFIX, session.ROLLBACK_SUFFIX, session.RECOVERY_SUFFIX, session.BACKUP_SUFFIX + session.RECOVERY_SUFFIX]:
		var path: String = session.DEFAULT_SAVE_PATH + suffix
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _argument(prefix: String) -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with(prefix):
			return argument.trim_prefix(prefix)
	return ""

func _assert_true(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures.append(message)

func _assert_equal(actual: Variant, expected: Variant, message: String) -> void:
	assertions += 1
	if actual != expected:
		failures.append("%s (actual=%s expected=%s)" % [message, actual, expected])
