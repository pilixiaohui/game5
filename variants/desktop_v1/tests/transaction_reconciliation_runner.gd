extends SceneTree

const FaultSession = preload("res://tests/fault_injecting_game_session.gd")
const CASE_PREFIX := "--case="
const PHASE_PREFIX := "--phase="
const MANIFEST_PATH := "user://transaction_reconciliation_manifest.json"

var session: Node
var failures: Array[String] = []
var assertions := 0

func _initialize() -> void:
	root.size = Vector2i(1600, 900)
	call_deferred("_run")

func _run() -> void:
	var case_name := _argument(CASE_PREFIX)
	var phase := _argument(PHASE_PREFIX)
	if phase == "seed":
		_seed_interrupted_transaction(case_name)
	elif phase == "recover":
		await _recover_interrupted_transaction(case_name)
	else:
		failures.append("unknown transaction reconciliation phase: %s" % phase)
	if failures.is_empty():
		print("TRANSACTION_RECONCILIATION_OK case=%s phase=%s assertions=%d" % [case_name, phase, assertions])
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("TRANSACTION_RECONCILIATION_FAILED case=%s phase=%s assertions=%d failures=%d" % [case_name, phase, assertions, failures.size()])
		quit(1)

func _seed_interrupted_transaction(case_name: String) -> void:
	var autoload_session := root.get_node("GameSession")
	autoload_session.set_process(false)
	session = autoload_session
	if case_name == "restored_validation_io":
		session = FaultSession.new()
		session.name = "InterruptFaultSession"
		root.add_child(session)
		session.set_process(false)
	_cleanup_slots()
	var with_backup := case_name != "no_backup"
	_seed_old_generation(with_backup)
	var primary_before := _fingerprint(session.DEFAULT_SAVE_PATH)
	var backup_before := _fingerprint(session.DEFAULT_SAVE_PATH + session.BACKUP_SUFFIX)
	var expected_tick := int(session.state.tick)
	var expected_primary := primary_before
	var recovery_events: Array[Dictionary] = []
	if session.has_signal("persistence_recovery_changed"):
		session.persistence_recovery_changed.connect(func(status: Dictionary) -> void: recovery_events.append(status.duplicate(true)))

	match case_name:
		"no_backup", "old_backup":
			_stage_primary_move_only()
		"candidate_committed", "candidate_corrupt":
			session.advance_steps(4)
			_stage_candidate_for_commit()
			if case_name == "candidate_committed":
				expected_tick = int(session.state.tick)
				var committed: Dictionary = session.call("_commit_primary", session.DEFAULT_SAVE_PATH)
				_assert_equal(committed.get("outcome", ""), session.COMMIT_COMMITTED, "candidate fixture must cross the primary commit point")
				expected_primary = _fingerprint(session.DEFAULT_SAVE_PATH)
			else:
				var rename_error: Error = session.call("_fs_rename", session.DEFAULT_SAVE_PATH + session.SAVE_TEMP_SUFFIX, session.DEFAULT_SAVE_PATH, session.IO_COMMIT_PRIMARY)
				_assert_equal(rename_error, OK, "corrupt candidate fixture must commit the staged directory entry")
				_write_text(session.DEFAULT_SAVE_PATH, "{interrupted-corrupt-candidate")
		"restored_validation_io":
			session.advance_steps(4)
			session.corrupt_after(session.IO_COMMIT_PRIMARY)
			session.inject(session.IO_VALIDATE_RESTORED_PRIMARY_ROLLBACK, "read")
			_assert_false(session.save_game(), "restored-primary final read I/O fixture must reject the update")
			_assert_equal(session.last_commit_outcome(), session.COMMIT_UNCERTAIN, "restored-primary final read I/O must be uncertain")
			_assert_true(session.is_reload_required(), "restored-primary final read I/O must freeze for reload")
			_assert_true(not recovery_events.is_empty() and bool(recovery_events[-1].reload_required), "uncertain fixture must emit the global recovery state")
		_:
			failures.append("unknown transaction reconciliation case: %s" % case_name)

	var manifest := {
		"case": case_name,
		"expected_tick": expected_tick,
		"expected_primary": expected_primary,
		"expected_backup": backup_before,
		"old_primary": primary_before,
	}
	_write_text(MANIFEST_PATH, JSON.stringify(manifest))
	_assert_true(FileAccess.file_exists(MANIFEST_PATH), "seed process must persist its external fingerprint manifest")

func _seed_old_generation(with_backup: bool) -> void:
	session.new_game(9901)
	if with_backup:
		session.advance_steps(2)
		_assert_true(session.save_game(), "fixture first generation must commit")
		session.advance_steps(3)
		_assert_true(session.save_game(), "fixture newer primary must commit with an old backup")
	else:
		session.advance_steps(5)
		_assert_true(session.save_game(), "single-slot fixture must commit its primary")

func _stage_primary_move_only() -> void:
	var backup: Dictionary = session.call("_prepare_backup", session.DEFAULT_SAVE_PATH)
	_assert_true(bool(backup.ok), "interruption fixture must prepare backup protection")
	var rollback: Dictionary = session.call("_prepare_primary_rollback", session.DEFAULT_SAVE_PATH)
	_assert_true(bool(rollback.ok), "interruption fixture must move primary to rollback")
	_assert_false(FileAccess.file_exists(session.DEFAULT_SAVE_PATH), "interruption point must have no primary")
	_assert_true(FileAccess.file_exists(session.DEFAULT_SAVE_PATH + session.ROLLBACK_SUFFIX), "interruption point must retain rollback")

func _stage_candidate_for_commit() -> void:
	var staged_error: Error = session.call("_write_snapshot_file", session.DEFAULT_SAVE_PATH + session.SAVE_TEMP_SUFFIX, session.snapshot(), session.IO_WRITE_STAGED_SNAPSHOT)
	_assert_equal(staged_error, OK, "candidate fixture must write the staged snapshot")
	var backup: Dictionary = session.call("_prepare_backup", session.DEFAULT_SAVE_PATH)
	_assert_true(bool(backup.ok), "candidate fixture must prepare backup protection")
	var rollback: Dictionary = session.call("_prepare_primary_rollback", session.DEFAULT_SAVE_PATH)
	_assert_true(bool(rollback.ok), "candidate fixture must move old primary to rollback")

func _recover_interrupted_transaction(case_name: String) -> void:
	session = root.get_node("GameSession")
	session.set_process(false)
	var manifest := _read_json(MANIFEST_PATH)
	_assert_equal(String(manifest.get("case", "")), case_name, "recovery process must read the matching seed manifest")
	var state_events: Array[Dictionary] = []
	var recovery_events: Array[Dictionary] = []
	session.state_changed.connect(func(snapshot: Dictionary) -> void: state_events.append(snapshot.duplicate(true)))
	session.persistence_recovery_changed.connect(func(status: Dictionary) -> void: recovery_events.append(status.duplicate(true)))
	var main := load("res://scenes/main.tscn").instantiate() as Control
	root.add_child(main)
	await _settle()
	var continue_button := main.find_child("ContinueButton", true, false) as Button
	_assert_true(continue_button != null and not continue_button.disabled, "%s must keep Continue reachable" % case_name)
	if continue_button != null and not continue_button.disabled:
		await _click(continue_button)
	_assert_true(_find_shell(main) != null, "%s Continue must enter the game" % case_name)
	_assert_equal(int(session.state.get("tick", -1)), int(manifest.get("expected_tick", -2)), "%s must load the exact authoritative generation" % case_name)
	_assert_equal(_fingerprint(session.DEFAULT_SAVE_PATH), _normalize_fingerprint(manifest.get("expected_primary", {})), "%s primary must preserve the authoritative path/hash/size/nanosecond mtime" % case_name)
	_assert_equal(_fingerprint(session.DEFAULT_SAVE_PATH + session.BACKUP_SUFFIX), _normalize_fingerprint(manifest.get("expected_backup", {})), "%s backup fingerprint must remain unchanged" % case_name)
	_assert_false(FileAccess.file_exists(session.DEFAULT_SAVE_PATH + session.ROLLBACK_SUFFIX), "%s successful reconciliation must consume or clean rollback" % case_name)
	_assert_false(session.is_persistence_blocked(), "%s successful reconciliation must unfreeze persistence" % case_name)
	var recovery_band := main.find_child("PersistenceRecovery", true, false) as Control
	_assert_true(recovery_band != null and not recovery_band.visible, "%s successful reconciliation must leave global recovery UI hidden" % case_name)
	_assert_equal(state_events.size(), 1, "%s load must emit exactly one authoritative state change" % case_name)
	_assert_true(not recovery_events.is_empty() and not bool(recovery_events[-1].reload_required), "%s load must emit a cleared recovery state" % case_name)
	_assert_no_transaction_scratch(case_name)
	main.queue_free()
	await process_frame

func _fingerprint(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"exists": false, "sha256": "", "size": 0, "mtime": ""}
	var global_path := ProjectSettings.globalize_path(path)
	var sha_output: Array = []
	var stat_output: Array = []
	var sha_status := OS.execute("sha256sum", PackedStringArray([global_path]), sha_output, true)
	var stat_status := OS.execute("stat", PackedStringArray(["-c", "%s|%y", global_path]), stat_output, true)
	_assert_equal(sha_status, 0, "external SHA-256 fingerprint must succeed")
	_assert_equal(stat_status, 0, "external nanosecond stat fingerprint must succeed")
	var stat_parts := String("".join(stat_output)).strip_edges().split("|", false, 1)
	return {
		"exists": true,
		"sha256": String("".join(sha_output)).get_slice(" ", 0),
		"size": int(stat_parts[0]),
		"mtime": String(stat_parts[1]),
	}

func _normalize_fingerprint(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return {}
	var fingerprint: Dictionary = value
	return {
		"exists": bool(fingerprint.get("exists", false)),
		"sha256": String(fingerprint.get("sha256", "")),
		"size": int(fingerprint.get("size", 0)),
		"mtime": String(fingerprint.get("mtime", "")),
	}

func _read_json(path: String) -> Dictionary:
	var parser := JSON.new()
	return parser.data if parser.parse(FileAccess.get_file_as_string(path)) == OK and parser.data is Dictionary else {}

func _write_text(path: String, value: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(value)
		file.close()

func _assert_no_transaction_scratch(case_name: String) -> void:
	for suffix in [session.SAVE_TEMP_SUFFIX, session.BACKUP_TEMP_SUFFIX, session.BACKUP_PREVIOUS_SUFFIX, session.ROLLBACK_SUFFIX, session.RECOVERY_SUFFIX, session.BACKUP_SUFFIX + session.RECOVERY_SUFFIX]:
		_assert_false(FileAccess.file_exists(session.DEFAULT_SAVE_PATH + suffix), "%s must clean scratch artifact %s" % [case_name, suffix])

func _cleanup_slots() -> void:
	for suffix in ["", session.BACKUP_SUFFIX, session.SAVE_TEMP_SUFFIX, session.BACKUP_TEMP_SUFFIX, session.BACKUP_PREVIOUS_SUFFIX, session.ROLLBACK_SUFFIX, session.RECOVERY_SUFFIX, session.BACKUP_SUFFIX + session.RECOVERY_SUFFIX]:
		var path: String = session.DEFAULT_SAVE_PATH + suffix
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if FileAccess.file_exists(MANIFEST_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(MANIFEST_PATH))

func _click(button: Button) -> void:
	var position := button.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = position
	motion.global_position = position
	root.push_input(motion)
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.position = position
	down.global_position = position
	down.pressed = true
	root.push_input(down)
	await process_frame
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.position = position
	up.global_position = position
	up.pressed = false
	root.push_input(up)
	await _settle()

func _find_shell(node: Node) -> Node:
	if node.has_method("_show_page") and node.has_method("_update_battle_strip"):
		return node
	for child in node.get_children():
		var found := _find_shell(child)
		if found != null:
			return found
	return null

func _settle() -> void:
	for index in range(5):
		await process_frame

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
