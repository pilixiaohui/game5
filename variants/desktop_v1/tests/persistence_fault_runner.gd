extends SceneTree

const FaultSession = preload("res://tests/fault_injecting_game_session.gd")

const FIRST_SAVE_CASES: Array[Dictionary] = [
	{"name": "save directory creation", "boundary": "create_save_directory"},
	{"name": "stale save temp cleanup", "boundary": "remove_stale_save_temp", "phase": "remove", "seed_suffix": ".tmp"},
	{"name": "staged snapshot write open", "boundary": "write_staged_snapshot", "phase": "open"},
	{"name": "staged snapshot partial write", "boundary": "write_staged_snapshot", "phase": "write"},
	{"name": "staged snapshot validation open", "boundary": "validate_staged_snapshot", "phase": "open"},
	{"name": "staged snapshot validation read", "boundary": "validate_staged_snapshot", "phase": "read"},
	{"name": "existing primary existence", "boundary": "inspect_existing_primary", "phase": "exists"},
	{"name": "first primary commit", "boundary": "commit_first_primary"},
	{"name": "first primary validation", "boundary": "validate_first_primary", "phase": "read"},
]

const UPDATE_CASES: Array[Dictionary] = [
	{"name": "stale backup temp cleanup", "boundary": "remove_stale_backup_temp", "phase": "remove", "seed_suffix": ".bak.tmp"},
	{"name": "backup temp copy", "boundary": "copy_primary_to_backup_temp"},
	{"name": "backup candidate validation", "boundary": "validate_backup_candidate", "phase": "read"},
	{"name": "existing backup inspection", "boundary": "inspect_existing_backup", "phase": "read"},
	{"name": "stale previous backup cleanup", "boundary": "remove_stale_backup_previous", "phase": "remove", "seed_suffix": ".bak.prev"},
	{"name": "existing backup preservation", "boundary": "copy_existing_backup_to_previous"},
	{"name": "previous backup validation", "boundary": "validate_previous_backup", "phase": "read"},
	{"name": "existing backup removal", "boundary": "remove_existing_backup", "phase": "remove"},
	{"name": "backup commit", "boundary": "commit_backup"},
	{"name": "backup rollback cleanup", "boundary": "restore_previous_backup_cleanup", "phase": "remove", "fail_first": "commit_backup", "seed_suffix": ".bak.recover"},
	{"name": "backup rollback copy", "boundary": "restore_previous_backup_copy", "fail_first": "commit_backup"},
	{"name": "backup rollback validation", "boundary": "validate_restore_previous_backup", "phase": "read", "fail_first": "commit_backup"},
	{"name": "backup rollback destination status", "boundary": "restore_previous_backup_destination", "phase": "exists", "fail_first": "commit_backup"},
	{"name": "backup rollback commit", "boundary": "restore_previous_backup_commit", "fail_first": "commit_backup"},
	{"name": "committed backup validation", "boundary": "validate_committed_backup", "phase": "read"},
	{"name": "stale primary rollback cleanup", "boundary": "remove_stale_rollback", "phase": "remove", "seed_suffix": ".rollback"},
	{"name": "primary rollback copy", "boundary": "copy_primary_to_rollback"},
	{"name": "primary rollback validation", "boundary": "validate_rollback", "phase": "read"},
	{"name": "primary removal", "boundary": "remove_primary_for_commit", "phase": "remove"},
	{"name": "primary commit", "boundary": "commit_primary"},
	{"name": "primary rollback cleanup", "boundary": "restore_primary_from_rollback_cleanup", "phase": "remove", "fail_first": "commit_primary", "seed_suffix": ".recover"},
	{"name": "primary rollback copy", "boundary": "restore_primary_from_rollback_copy", "fail_first": "commit_primary"},
	{"name": "primary rollback validation", "boundary": "validate_restore_primary_from_rollback", "phase": "read", "fail_first": "commit_primary"},
	{"name": "primary rollback destination status", "boundary": "restore_primary_from_rollback_destination", "phase": "exists", "fail_first": "commit_primary"},
	{"name": "primary rollback commit", "boundary": "restore_primary_from_rollback_commit", "fail_first": "commit_primary"},
	{"name": "committed primary validation", "boundary": "validate_committed_primary", "phase": "read"},
	{"name": "invalid committed primary removal", "boundary": "remove_invalid_committed_primary", "phase": "remove", "corrupt_after": "commit_primary"},
	{"name": "invalid primary rollback cleanup", "boundary": "restore_invalid_primary_from_rollback_cleanup", "phase": "remove", "corrupt_after": "commit_primary", "seed_suffix": ".recover"},
	{"name": "invalid primary rollback copy", "boundary": "restore_invalid_primary_from_rollback_copy", "corrupt_after": "commit_primary"},
	{"name": "invalid primary rollback validation", "boundary": "validate_restore_invalid_primary", "phase": "read", "corrupt_after": "commit_primary"},
	{"name": "invalid primary rollback destination status", "boundary": "restore_invalid_primary_destination", "phase": "exists", "corrupt_after": "commit_primary"},
	{"name": "invalid primary rollback commit", "boundary": "restore_invalid_primary_commit", "corrupt_after": "commit_primary"},
	{"name": "successful commit rollback cleanup", "boundary": "cleanup_rollback", "phase": "remove", "expect_success": true},
	{"name": "successful commit backup cleanup", "boundary": "cleanup_backup_previous", "phase": "remove", "expect_success": true},
	{"name": "backup post-commit corruption", "boundary": "commit_backup", "corrupt_only": true},
	{"name": "primary post-commit corruption", "boundary": "commit_primary", "corrupt_only": true},
]

const RECOVERY_CASES: Array[Dictionary] = [
	{"name": "stale recovery cleanup", "boundary": "remove_stale_recovery", "phase": "remove", "seed_stale": true, "mode": "corrupt"},
	{"name": "backup recovery copy", "boundary": "copy_backup_to_recovery", "mode": "corrupt"},
	{"name": "recovery candidate validation", "boundary": "validate_recovery_candidate", "phase": "read", "mode": "corrupt"},
	{"name": "invalid primary removal", "boundary": "remove_invalid_primary_for_recovery", "phase": "remove", "mode": "corrupt"},
	{"name": "backup recovery commit with corrupt primary", "boundary": "commit_backup_recovery", "mode": "corrupt"},
	{"name": "backup recovery commit with missing primary", "boundary": "commit_backup_recovery", "mode": "missing"},
	{"name": "restored primary validation", "boundary": "validate_restored_primary", "phase": "read", "mode": "corrupt"},
	{"name": "backup recovery post-commit corruption", "boundary": "commit_backup_recovery", "mode": "corrupt", "corrupt_only": true},
]

const CLASSIFICATION_CASES: Array[Dictionary] = [
	{"name": "has-save primary existence", "boundary": "has_save_primary", "phase": "exists"},
	{"name": "has-save backup existence", "boundary": "has_save_backup", "phase": "exists"},
	{"name": "load primary existence", "boundary": "load_primary", "phase": "exists"},
	{"name": "load primary open", "boundary": "load_primary", "phase": "open"},
	{"name": "load primary read", "boundary": "load_primary", "phase": "read"},
	{"name": "load backup open", "boundary": "load_backup", "phase": "open"},
]

const SLOT_SUFFIXES: Array[String] = ["", ".bak", ".tmp", ".bak.tmp", ".bak.prev", ".rollback", ".recover", ".bak.recover"]
const SENTINEL_PATH := "user://persistence_fault_sentinel.txt"
const SENTINEL_BYTES := "persistence-fault-outside-sentinel"

var subject: Node
var failures: Array[String] = []
var assertions := 0
var scratch_data_root := ""

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	scratch_data_root = _argument("--scratch-data-root=").simplify_path()
	var save_path := ProjectSettings.globalize_path("user://saves/slot_01.json").simplify_path()
	if scratch_data_root.is_empty() or not save_path.begins_with(scratch_data_root + "/"):
		push_error("PERSISTENCE_FAULTS_REFUSED scratch root does not own the save path")
		quit(1)
		return
	subject = FaultSession.new()
	subject.name = "FaultSession"
	root.add_child(subject)
	subject.set_process(false)
	_write_text(SENTINEL_PATH, SENTINEL_BYTES)
	_assert_coverage_contract()
	_test_classification_callsite_matrix()
	_test_first_save_failure_matrix()
	_test_existing_slot_update_matrix()
	_test_recovery_failure_matrix()
	_test_successful_update_cleans_scratch()
	_cleanup_slots()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SENTINEL_PATH))
	subject.queue_free()
	if failures.is_empty():
		print("PERSISTENCE_FAULTS_OK first_save_cases=%d update_cases=%d recovery_cases=%d classification_cases=%d callsites=%d assertions=%d" % [FIRST_SAVE_CASES.size(), UPDATE_CASES.size(), RECOVERY_CASES.size(), CLASSIFICATION_CASES.size(), subject.PERSISTENCE_IO_CALLSITES.size(), assertions])
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("PERSISTENCE_FAULTS_FAILED assertions=%d failures=%d" % [assertions, failures.size()])
		quit(1)

func _assert_coverage_contract() -> void:
	var production: Array = subject.PERSISTENCE_IO_CALLSITES.duplicate()
	var production_set := {}
	for callsite in production:
		production_set[callsite] = true
	_assert_equal(production_set.size(), production.size(), "production persistence callsite names must be unique")
	var covered_set := {}
	for cases in [FIRST_SAVE_CASES, UPDATE_CASES, RECOVERY_CASES, CLASSIFICATION_CASES]:
		for case in cases:
			covered_set[case.boundary] = true
	var covered: Array = covered_set.keys()
	production.sort()
	covered.sort()
	_assert_equal(covered, production, "fault matrix covered set must equal the production persistence callsite list")

func _test_classification_callsite_matrix() -> void:
	for index in range(CLASSIFICATION_CASES.size()):
		var case := CLASSIFICATION_CASES[index]
		var fixture := _seed_three_generations(8800 + index)
		var primary_before := _read_text(subject.DEFAULT_SAVE_PATH)
		var backup_before := _read_text(subject.DEFAULT_SAVE_PATH + subject.BACKUP_SUFFIX)
		subject.clear_injections()
		if case.boundary == "has_save_primary":
			subject.inject(case.boundary, case.phase)
			_assert_true(subject.has_save(), "%s I/O error must conservatively report an occupied slot" % case.name)
		elif case.boundary == "has_save_backup":
			DirAccess.remove_absolute(ProjectSettings.globalize_path(subject.DEFAULT_SAVE_PATH))
			subject.inject(case.boundary, case.phase)
			_assert_true(subject.has_save(), "%s I/O error must conservatively report an occupied slot" % case.name)
		else:
			if case.boundary == "load_backup":
				_write_text(subject.DEFAULT_SAVE_PATH, "{corrupt-primary")
				primary_before = _read_text(subject.DEFAULT_SAVE_PATH)
			subject.state = {}
			subject.inject(case.boundary, case.phase)
			_assert_false(subject.load_game(), "%s I/O error must block loading" % case.name)
			_assert_true(subject.is_persistence_blocked(), "%s must block persistence" % case.name)
			_assert_true(subject.state.is_empty(), "%s must not install any generation" % case.name)
			_assert_equal(_read_text(subject.DEFAULT_SAVE_PATH), primary_before, "%s must preserve primary bytes" % case.name)
			_assert_equal(_read_text(subject.DEFAULT_SAVE_PATH + subject.BACKUP_SUFFIX), backup_before, "%s must preserve backup bytes" % case.name)
		_assert_true(case.boundary in subject.operation_trace, "%s must reach %s.%s" % [case.name, case.boundary, case.phase])
		_assert_true("%s.%s" % [case.boundary, case.phase] in subject.operation_phase_trace, "%s must reach the requested phase" % case.name)
		_assert_no_unauthorized_side_effects(case.name)
		subject.clear_injections()
		if case.boundary.begins_with("load_"):
			_assert_true(subject.load_game(), "%s must load or recover on a clean retry" % case.name)
			_assert_true(int(subject.state.tick) in [int(fixture.primary_tick), int(fixture.backup_tick)], "%s retry must install a complete committed generation" % case.name)

func _test_first_save_failure_matrix() -> void:
	for index in range(FIRST_SAVE_CASES.size()):
		var case := FIRST_SAVE_CASES[index]
		_cleanup_slots()
		DirAccess.remove_absolute(ProjectSettings.globalize_path(subject.DEFAULT_SAVE_PATH.get_base_dir()))
		subject.clear_injections()
		subject.new_game(9000 + index)
		subject.advance_steps(3)
		var attempted_tick := int(subject.state.tick)
		if case.has("seed_suffix"):
			_write_text(subject.DEFAULT_SAVE_PATH + case.seed_suffix, JSON.stringify(subject.snapshot()))
		_inject_case(case)
		_assert_false(subject.save_game(), "%s injection must reject the first save" % case.name)
		_assert_case_reached(case)
		_assert_false(FileAccess.file_exists(subject.DEFAULT_SAVE_PATH + subject.BACKUP_SUFFIX), "%s must not invent a committed backup" % case.name)
		_assert_no_unauthorized_side_effects(case.name)
		subject.clear_injections()
		_assert_true(subject.save_game(), "%s must permit a clean retry" % case.name)
		_assert_loads_one_complete_generation(case.name, [attempted_tick])

func _test_existing_slot_update_matrix() -> void:
	for index in range(UPDATE_CASES.size()):
		var case := UPDATE_CASES[index]
		var fixture := _seed_three_generations(9100 + index)
		if case.has("seed_suffix"):
			_write_text(subject.DEFAULT_SAVE_PATH + case.seed_suffix, fixture.backup)
		subject.advance_steps(5)
		var attempted_tick := int(subject.state.tick)
		subject.clear_injections()
		if case.has("fail_first"):
			subject.inject(case.fail_first, "rename")
		if not case.get("corrupt_only", false):
			_inject_case(case)
		if case.has("corrupt_after"):
			subject.corrupt_after(case.corrupt_after)
		elif case.get("corrupt_only", false):
			subject.corrupt_after(case.boundary)
		var save_result: bool = subject.save_game()
		if case.get("expect_success", false):
			_assert_true(save_result, "%s is post-commit cleanup and must keep the save successful" % case.name)
		else:
			_assert_false(save_result, "%s injection must reject the update" % case.name)
		_assert_case_reached(case)
		var promised_backup: String = fixture.primary if case.get("expect_success", false) else fixture.backup
		_assert_promised_backup(case.name, promised_backup)
		_assert_no_unauthorized_side_effects(case.name)
		subject.clear_injections()
		_assert_loads_one_complete_generation(case.name, [int(fixture.primary_tick), attempted_tick])
		_assert_promised_backup(case.name, promised_backup)

func _test_recovery_failure_matrix() -> void:
	for index in range(RECOVERY_CASES.size()):
		var case := RECOVERY_CASES[index]
		var fixture := _seed_three_generations(9500 + index)
		var primary_path: String = subject.DEFAULT_SAVE_PATH
		if case.mode == "missing":
			DirAccess.remove_absolute(ProjectSettings.globalize_path(primary_path))
		else:
			_write_text(primary_path, "{corrupt-primary")
		if case.get("seed_stale", false):
			_write_text(primary_path + subject.RECOVERY_SUFFIX, fixture.primary)
		subject.state = {}
		subject.clear_injections()
		if case.get("corrupt_only", false):
			subject.corrupt_after(case.boundary)
		else:
			_inject_case(case)
		_assert_false(subject.load_game(), "%s injection must reject recovery" % case.name)
		_assert_case_reached(case)
		_assert_true(subject.is_persistence_blocked(), "%s must block simulation after recovery failure" % case.name)
		_assert_true(subject.state.is_empty(), "%s must not install backup before durable recovery" % case.name)
		_assert_promised_backup(case.name, fixture.backup)
		_assert_no_unauthorized_side_effects(case.name)
		subject.clear_injections()
		_assert_true(subject.load_game(), "%s must recover on a clean retry" % case.name)
		_assert_equal(_read_text(primary_path), fixture.backup, "%s retry must restore exact backup bytes" % case.name)
		_assert_equal(_read_text(primary_path + subject.BACKUP_SUFFIX), fixture.backup, "%s retry must preserve exact backup bytes" % case.name)

func _test_successful_update_cleans_scratch() -> void:
	var fixture := _seed_three_generations(9700)
	subject.advance_steps(2)
	_assert_true(subject.save_game(), "successful cleanup fixture must save")
	_assert_equal(_read_text(subject.DEFAULT_SAVE_PATH + subject.BACKUP_SUFFIX), fixture.primary, "successful update must commit the replaced primary as backup")
	for suffix in [subject.SAVE_TEMP_SUFFIX, subject.BACKUP_TEMP_SUFFIX, subject.BACKUP_PREVIOUS_SUFFIX, subject.ROLLBACK_SUFFIX, subject.RECOVERY_SUFFIX, subject.BACKUP_SUFFIX + subject.RECOVERY_SUFFIX]:
		_assert_false(FileAccess.file_exists(subject.DEFAULT_SAVE_PATH + suffix), "successful update must clean scratch artifact %s" % suffix)
	_assert_no_unauthorized_side_effects("successful update")

func _seed_three_generations(seed_value: int) -> Dictionary:
	_cleanup_slots()
	subject.clear_injections()
	subject.new_game(seed_value)
	subject.advance_steps(2)
	_assert_true(subject.save_game(), "fixture first save must succeed")
	subject.advance_steps(3)
	_assert_true(subject.save_game(), "fixture second save must succeed")
	subject.advance_steps(4)
	_assert_true(subject.save_game(), "fixture third save must succeed")
	return {
		"primary": _read_text(subject.DEFAULT_SAVE_PATH),
		"backup": _read_text(subject.DEFAULT_SAVE_PATH + subject.BACKUP_SUFFIX),
		"primary_tick": int(subject.state.tick),
		"backup_tick": _snapshot_tick(subject.DEFAULT_SAVE_PATH + subject.BACKUP_SUFFIX),
	}

func _inject_case(case: Dictionary) -> void:
	subject.inject(case.boundary, case.get("phase", "*"))

func _assert_case_reached(case: Dictionary) -> void:
	_assert_true(case.boundary in subject.operation_trace, "%s must reach %s" % [case.name, case.boundary])
	if case.has("phase"):
		_assert_true("%s.%s" % [case.boundary, case.phase] in subject.operation_phase_trace, "%s must reach phase %s" % [case.name, case.phase])

func _snapshot_tick(path: String) -> int:
	var parser := JSON.new()
	return int(parser.data.tick) if parser.parse(_read_text(path)) == OK and parser.data is Dictionary else -1

func _assert_loads_one_complete_generation(case_name: String, expected_ticks: Array) -> void:
	var verifier := FaultSession.new()
	root.add_child(verifier)
	verifier.set_process(false)
	_assert_true(verifier.load_game(), "%s must leave an old or new complete generation loadable" % case_name)
	if not verifier.state.is_empty():
		_assert_true(int(verifier.state.tick) in expected_ticks, "%s must load only an expected complete generation" % case_name)
	verifier.queue_free()

func _assert_promised_backup(case_name: String, expected: String) -> void:
	var paths: Array = [
		subject.DEFAULT_SAVE_PATH + subject.BACKUP_SUFFIX,
		subject.DEFAULT_SAVE_PATH + subject.BACKUP_PREVIOUS_SUFFIX,
		subject.DEFAULT_SAVE_PATH + subject.BACKUP_SUFFIX + subject.RECOVERY_SUFFIX,
	]
	_assert_true(_contains_bytes(paths, expected), "%s must not lose the already committed backup" % case_name)

func _assert_no_unauthorized_side_effects(case_name: String) -> void:
	_assert_equal(_read_text(SENTINEL_PATH), SENTINEL_BYTES, "%s must not modify data outside the save namespace" % case_name)
	var save_dir_path := ProjectSettings.globalize_path(subject.DEFAULT_SAVE_PATH.get_base_dir())
	if not DirAccess.dir_exists_absolute(save_dir_path):
		return
	var directory := DirAccess.open(save_dir_path)
	_assert_true(directory != null, "%s save namespace must remain readable" % case_name)
	if directory == null:
		return
	var allowed_names: Array[String] = []
	for suffix in SLOT_SUFFIXES:
		allowed_names.append(subject.DEFAULT_SAVE_PATH.get_file() + suffix)
	for file_name in directory.get_files():
		_assert_true(file_name in allowed_names, "%s must not create an unauthorized save file: %s" % [case_name, file_name])
	_assert_equal(directory.get_directories().size(), 0, "%s must not create an unauthorized save directory" % case_name)

func _contains_bytes(paths: Array, expected: String) -> bool:
	for path in paths:
		if FileAccess.file_exists(path) and _read_text(path) == expected:
			return true
	return false

func _read_text(path: String) -> String:
	return FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""

func _write_text(path: String, value: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(value)
		file.close()

func _cleanup_slots() -> void:
	if subject == null:
		return
	for suffix in SLOT_SUFFIXES:
		var path: String = subject.DEFAULT_SAVE_PATH + suffix
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
