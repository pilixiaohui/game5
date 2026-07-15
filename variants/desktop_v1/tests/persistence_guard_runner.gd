extends SceneTree

var session: Node
var failures: Array[String] = []
var assertions := 0
var scratch_data_root := ""

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	session = root.get_node("GameSession")
	session.set_process(false)
	scratch_data_root = _argument("--scratch-data-root=").simplify_path()
	var save_path := ProjectSettings.globalize_path(session.DEFAULT_SAVE_PATH).simplify_path()
	if scratch_data_root.is_empty() or not save_path.begins_with(scratch_data_root + "/"):
		push_error("PERSISTENCE_GUARDS_REFUSED scratch root does not own the save path")
		quit(1)
		return
	await _test_invalid_schema_matrix_preserves_slots()
	await _test_valid_backup_recovers_corrupt_or_missing_primary()
	await _test_new_game_requires_confirmation()
	_cleanup_slots()
	if failures.is_empty():
		print("PERSISTENCE_GUARDS_OK cases=3 schema_cases=5 assertions=%d" % assertions)
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("PERSISTENCE_GUARDS_FAILED cases=3 assertions=%d failures=%d" % [assertions, failures.size()])
		quit(1)

func _test_invalid_schema_matrix_preserves_slots() -> void:
	var cases: Array[String] = [
		"room progress type",
		"node position tuple field",
		"malformed link tuple",
		"wrong link array length",
		"candidate option nested field",
	]
	for index in range(cases.size()):
		_cleanup_slots()
		session.new_game(8100 + index)
		session.advance_steps(7)
		var invalid_state: Dictionary = session.snapshot()
		_corrupt_schema_case(cases[index], invalid_state)
		var primary_text := JSON.stringify(invalid_state)
		var backup_text := "{\"deliberately\":\"invalid backup %d\"}" % index
		_assert_true(_write_text(session.DEFAULT_SAVE_PATH, primary_text), "%s fixture must write invalid primary" % cases[index])
		_assert_true(_write_text(session.DEFAULT_SAVE_PATH + session.BACKUP_SUFFIX, backup_text), "%s fixture must write invalid backup" % cases[index])
		session.state = {}
		_assert_false(session.load_game(), "%s must be rejected when both slots are invalid" % cases[index])
		_assert_true(session.is_persistence_blocked(), "%s must block simulation and persistence" % cases[index])
		_assert_true(session.state.is_empty(), "%s must not install partial state" % cases[index])
		var state_before := JSON.stringify(session.state)
		session.advance_steps(5)
		_assert_false(session.save_game(), "%s must keep manual save blocked" % cases[index])
		_assert_equal(JSON.stringify(session.state), state_before, "%s must keep blocked simulation unchanged" % cases[index])
		_assert_equal(FileAccess.get_file_as_string(session.DEFAULT_SAVE_PATH), primary_text, "%s must preserve primary bytes" % cases[index])
		_assert_equal(FileAccess.get_file_as_string(session.DEFAULT_SAVE_PATH + session.BACKUP_SUFFIX), backup_text, "%s must preserve backup bytes" % cases[index])
		if index == 0:
			var main: Control = load("res://scenes/main.tscn").instantiate()
			root.add_child(main)
			await process_frame
			_press(main, "ContinueButton")
			await process_frame
			var notice := main.find_child("TitleNotice", true, false) as Label
			_assert_true(notice != null and notice.visible and "不可用" in notice.text, "invalid schema error must be visible on the title screen")
			main.queue_free()
			await process_frame

func _corrupt_schema_case(case_name: String, value: Dictionary) -> void:
	match case_name:
		"room progress type":
			value.rooms[0].progress = "bad"
		"node position tuple field":
			value.nodes[0].pos[1] = "bad"
		"malformed link tuple":
			value.links[0] = ["H"]
		"wrong link array length":
			value.links.pop_back()
		"candidate option nested field":
			value.candidate_group = {
				"id": "schema-fixture",
				"kind": "first",
				"source": "test",
				"options": [session.CANDIDATES[0].duplicate(true), session.CANDIDATES[1].duplicate(true), session.CANDIDATES[2].duplicate(true)],
			}
			value.candidate_group.options[0].cost = "bad"

func _test_valid_backup_recovers_corrupt_or_missing_primary() -> void:
	for mode in ["json_corrupt", "schema_corrupt", "missing"]:
		_cleanup_slots()
		session.new_game(8150 + ["json_corrupt", "schema_corrupt", "missing"].find(mode))
		session.advance_steps(4)
		_assert_true(session.save_game(), "%s recovery fixture must create primary" % mode)
		session.advance_steps(3)
		_assert_true(session.save_game(), "%s recovery fixture must create backup" % mode)
		var backup_before := FileAccess.get_file_as_string(session.DEFAULT_SAVE_PATH + session.BACKUP_SUFFIX)
		if mode == "json_corrupt":
			_assert_true(_write_text(session.DEFAULT_SAVE_PATH, "{broken-primary"), "corrupt recovery fixture must replace primary")
		elif mode == "schema_corrupt":
			var invalid_primary: Dictionary = session.snapshot()
			invalid_primary.rooms[0].progress = "bad"
			_assert_true(_write_text(session.DEFAULT_SAVE_PATH, JSON.stringify(invalid_primary)), "schema recovery fixture must replace primary")
		else:
			_assert_equal(DirAccess.remove_absolute(ProjectSettings.globalize_path(session.DEFAULT_SAVE_PATH)), OK, "missing recovery fixture must remove primary")
		var classified: Dictionary = session._read_snapshot(session.DEFAULT_SAVE_PATH, session.IO_LOAD_PRIMARY)
		_assert_equal(classified.status, session.SNAPSHOT_MISSING if mode == "missing" else session.SNAPSHOT_CORRUPT, "%s primary must be classified before recovery" % mode)
		session.state = {}
		_assert_true(session.load_game(), "%s primary must recover from a validated backup" % mode)
		_assert_false(session.is_persistence_blocked(), "%s recovery must leave persistence enabled" % mode)
		_assert_equal(FileAccess.get_file_as_string(session.DEFAULT_SAVE_PATH), backup_before, "%s recovery must restore exact primary bytes" % mode)
		_assert_equal(FileAccess.get_file_as_string(session.DEFAULT_SAVE_PATH + session.BACKUP_SUFFIX), backup_before, "%s recovery must preserve exact backup bytes" % mode)
		_assert_true(not session.state.is_empty(), "%s recovery must install the validated state" % mode)

func _test_new_game_requires_confirmation() -> void:
	_cleanup_slots()
	session.new_game(8202)
	session.advance_steps(9)
	_assert_true(session.save_game(), "new-game fixture must write a valid primary")
	_assert_true(session.save_game(), "new-game fixture must write a valid backup")
	var state_before := JSON.stringify(session.snapshot())
	var primary_before := FileAccess.get_file_as_string(session.DEFAULT_SAVE_PATH)
	var main: Control = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	_press(main, "NewGameButton")
	await process_frame
	var confirmation := main.find_child("NewGameConfirmation", true, false) as Control
	_assert_true(confirmation != null and confirmation.visible, "existing save must open a visible confirmation")
	_assert_equal(JSON.stringify(session.snapshot()), state_before, "opening confirmation must not change state")
	_assert_equal(FileAccess.get_file_as_string(session.DEFAULT_SAVE_PATH), primary_before, "opening confirmation must not change the slot")
	_press(main, "CancelNewGameButton")
	await process_frame
	_assert_true(not confirmation.visible, "cancel must close the confirmation")
	_assert_equal(JSON.stringify(session.snapshot()), state_before, "cancel must preserve in-memory state")
	_assert_equal(FileAccess.get_file_as_string(session.DEFAULT_SAVE_PATH), primary_before, "cancel must preserve the primary slot")
	_press(main, "NewGameButton")
	await process_frame
	_press(main, "ConfirmNewGameButton")
	await process_frame
	_assert_equal(int(session.state.tick), 0, "confirmation must start a fresh round")
	_assert_true(FileAccess.get_file_as_string(session.DEFAULT_SAVE_PATH) != primary_before, "confirmation must replace the primary slot")
	_assert_equal(FileAccess.get_file_as_string(session.DEFAULT_SAVE_PATH + session.BACKUP_SUFFIX), primary_before, "confirmation must preserve the replaced primary as backup")
	main.queue_free()
	await process_frame

func _press(root_node: Node, node_name: String) -> void:
	var button := root_node.find_child(node_name, true, false) as Button
	_assert_true(button != null, "%s must exist" % node_name)
	if button != null:
		button.emit_signal("pressed")

func _write_text(path: String, text: String) -> bool:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(text)
	var error := file.get_error()
	file.close()
	return error == OK

func _cleanup_slots() -> void:
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

func _assert_false(value: bool, message: String) -> void:
	_assert_true(not value, message)

func _assert_equal(actual: Variant, expected: Variant, message: String) -> void:
	assertions += 1
	if actual != expected:
		failures.append("%s (actual=%s expected=%s)" % [message, actual, expected])
