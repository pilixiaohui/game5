extends SceneTree

const FaultSession = preload("res://tests/fault_injecting_game_session.gd")

var failures: Array[String] = []
var assertions := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var scratch_data_root := _argument("--scratch-data-root=").simplify_path()
	var phase := _argument("--phase=")
	var subject := FaultSession.new()
	root.add_child(subject)
	subject.set_process(false)
	var save_path := ProjectSettings.globalize_path(subject.DEFAULT_SAVE_PATH).simplify_path()
	if scratch_data_root.is_empty() or not save_path.begins_with(scratch_data_root + "/"):
		push_error("PRIMARY_READ_IO_REFUSED scratch root does not own the save path")
		quit(1)
		return
	if phase == "seed":
		subject.new_game(9901)
		subject.advance_steps(2)
		_assert_true(subject.save_game(), "seed must create primary")
		subject.advance_steps(3)
		_assert_true(subject.save_game(), "seed must create backup")
	else:
		var primary_before := FileAccess.get_file_as_string(subject.DEFAULT_SAVE_PATH)
		var backup_before := FileAccess.get_file_as_string(subject.DEFAULT_SAVE_PATH + subject.BACKUP_SUFFIX)
		subject.inject(subject.IO_LOAD_PRIMARY, phase)
		_assert_false(subject.load_game(), "%s I/O injection must reject load" % phase)
		_assert_true(subject.is_persistence_blocked(), "%s I/O injection must block persistence" % phase)
		_assert_true(subject.state.is_empty(), "%s I/O injection must not install backup state" % phase)
		_assert_equal(FileAccess.get_file_as_string(subject.DEFAULT_SAVE_PATH), primary_before, "%s must preserve primary bytes" % phase)
		_assert_equal(FileAccess.get_file_as_string(subject.DEFAULT_SAVE_PATH + subject.BACKUP_SUFFIX), backup_before, "%s must preserve backup bytes" % phase)
		_assert_true("%s.%s" % [subject.IO_LOAD_PRIMARY, phase] in subject.operation_phase_trace, "%s must hit the real load-primary callsite" % phase)
	if failures.is_empty():
		print("PRIMARY_READ_IO_OK phase=%s assertions=%d" % [phase, assertions])
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("PRIMARY_READ_IO_FAILED phase=%s assertions=%d failures=%d" % [phase, assertions, failures.size()])
		quit(1)

func _argument(prefix: String) -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with(prefix):
			return argument.trim_prefix(prefix)
	return ""

func _assert_true(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures.append(message)

func _assert_false(value: bool, message: String) -> void:
	_assert_true(not value, message)

func _assert_equal(actual: Variant, expected: Variant, message: String) -> void:
	assertions += 1
	if actual != expected:
		failures.append("%s (actual=%s expected=%s)" % [message, actual, expected])
