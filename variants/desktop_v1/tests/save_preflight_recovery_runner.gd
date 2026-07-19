extends SceneTree

const FaultSession = preload("res://tests/fault_injecting_game_session.gd")

var session: Node
var failures: Array[String] = []
var assertions := 0
var scratch_data_root := ""

func _initialize() -> void:
	root.size = Vector2i(1600, 900)
	Engine.max_fps = 30
	call_deferred("_run")

func _run() -> void:
	session = FaultSession.new()
	session.name = "SavePreflightFaultSession"
	root.add_child(session)
	session.set_process(false)
	scratch_data_root = _argument("--scratch-data-root=").simplify_path()
	var save_path := ProjectSettings.globalize_path(session.DEFAULT_SAVE_PATH).simplify_path()
	if scratch_data_root.is_empty() or not save_path.begins_with(scratch_data_root + "/"):
		push_error("SAVE_PREFLIGHT_RECOVERY_REFUSED scratch root does not own the save path")
		quit(1)
		return

	_cleanup_slots()
	session.new_game(9811)
	session.set_speed(4)
	session.advance_steps(2)
	_assert_true(session.save_game(), "fixture must commit backup generation tick 2")
	session.advance_steps(3)
	_assert_true(session.save_game(), "fixture must commit primary generation tick 5")
	var old_primary := _fingerprint(session.DEFAULT_SAVE_PATH)
	var old_backup := _fingerprint(session.DEFAULT_SAVE_PATH + session.BACKUP_SUFFIX)
	_assert_equal(_read_tick(session.DEFAULT_SAVE_PATH), 5, "fixture primary must be tick 5")
	_assert_equal(_read_tick(session.DEFAULT_SAVE_PATH + session.BACKUP_SUFFIX), 2, "fixture backup must be tick 2")

	session.advance_steps(4)
	var memory_before := JSON.stringify(session.snapshot())
	var temp_path: String = session.DEFAULT_SAVE_PATH + session.SAVE_TEMP_SUFFIX
	var rollback_path: String = session.DEFAULT_SAVE_PATH + session.ROLLBACK_SUFFIX
	var staged_error: Error = session.call("_write_snapshot_file", temp_path, session.snapshot(), session.IO_WRITE_STAGED_SNAPSHOT)
	_assert_equal(staged_error, OK, "fixture must retain a complete staged tick 9 candidate")
	_assert_equal(_read_tick(temp_path), 9, "staged candidate must contain tick 9")
	var rename_error := DirAccess.rename_absolute(ProjectSettings.globalize_path(session.DEFAULT_SAVE_PATH), ProjectSettings.globalize_path(rollback_path))
	_assert_equal(rename_error, OK, "fixture must simulate the interrupted primary-to-rollback rename")
	var staged_before := _fingerprint(temp_path)
	var rollback_before := _fingerprint(rollback_path)
	_assert_equal(rollback_before, old_primary, "rollback must preserve the exact old-primary fingerprint")
	_assert_false(FileAccess.file_exists(session.DEFAULT_SAVE_PATH), "interrupted fixture must start without primary")

	var recovery_events: Array[Dictionary] = []
	var state_events: Array[Dictionary] = []
	var battle_events: Array = []
	var success_notices: Array[String] = []
	var autoload_session := root.get_node("GameSession")
	autoload_session.set_process(false)
	autoload_session.state = session.snapshot()
	session.persistence_recovery_changed.connect(func(status: Dictionary) -> void: recovery_events.append(status.duplicate(true)))
	session.state_changed.connect(func(snapshot: Dictionary) -> void:
		autoload_session.state = snapshot.duplicate(true)
		state_events.append(snapshot.duplicate(true))
	)
	session.battle_ended.connect(func(node_id: String, captured: bool) -> void: battle_events.append([node_id, captured]))
	session.notice_posted.connect(func(message: String, level: String) -> void:
		if level == "success":
			success_notices.append(message)
	)
	var main := _instantiate_main_for(session)
	root.add_child(main)
	await _settle()
	main.call("_show_game")
	await _settle()

	session.clear_injections()
	session.inject(session.IO_VALIDATE_RESTORED_PRIMARY_ROLLBACK, "read")
	_assert_false(session.save_game(), "public save must fail closed when restored-primary validation is uncertain")
	await _settle()
	_assert_true("%s.read" % session.IO_VALIDATE_RESTORED_PRIMARY_ROLLBACK in session.operation_phase_trace, "public save must reach restored-primary final read")
	_assert_equal(session.last_commit_outcome(), session.COMMIT_UNCERTAIN, "save preflight must preserve the reconciliation uncertain outcome")
	_assert_true(session.is_persistence_blocked() and session.is_reload_required(), "uncertain preflight must freeze persistence and require reload")
	_assert_equal(JSON.stringify(session.snapshot()), memory_before, "uncertain preflight must not install another in-memory generation")
	_assert_equal(state_events.size(), 0, "uncertain preflight must not emit a successful state change")
	_assert_equal(battle_events.size(), 0, "uncertain preflight must not synthesize battle completion")
	_assert_equal(success_notices.size(), 0, "uncertain preflight must not synthesize save success")
	_assert_equal(recovery_events.size(), 1, "uncertain preflight must emit one explicit recovery state")
	_assert_true(not recovery_events.is_empty() and bool(recovery_events[-1].reload_required), "recovery signal must require authoritative reload")

	var recovery_band := main.find_child("PersistenceRecovery", true, false) as Control
	var reload_buttons := main.find_children("ReloadAfterPersistenceBlock", "Button", true, false)
	var reload_button := reload_buttons[0] as Button if reload_buttons.size() == 1 else null
	_assert_equal(reload_buttons.size(), 1, "Main must own exactly one global reload command")
	_assert_true(recovery_band != null and recovery_band.is_visible_in_tree(), "uncertain preflight must show the global recovery UI")
	_assert_true(reload_button != null and reload_button.is_visible_in_tree(), "global reload command must remain visible and reachable")
	_assert_equal(_fingerprint(session.DEFAULT_SAVE_PATH), old_primary, "restored primary must preserve the exact old-primary fingerprint")
	_assert_equal(_fingerprint(session.DEFAULT_SAVE_PATH + session.BACKUP_SUFFIX), old_backup, "uncertain preflight must preserve backup fingerprint")
	_assert_equal(_fingerprint(temp_path), staged_before, "uncertain preflight must preserve staged candidate fingerprint")
	_assert_false(FileAccess.file_exists(rollback_path), "successful restore rename must consume the rollback path")

	var tick_before_frames := int(session.snapshot().tick)
	session.set_process(true)
	await _wait_frames(20)
	session.set_process(false)
	_assert_equal(int(session.snapshot().tick), tick_before_frames, "uncertain preflight must freeze real frame scheduling")
	var worker_target_before := int(session.snapshot().targets.worker)
	session.set_unit_target("worker", 1)
	_assert_equal(int(session.snapshot().targets.worker), worker_target_before, "uncertain preflight must reject gameplay mutation")
	var slots_before_rejected_save := _slot_fingerprints()
	_assert_false(session.save_game(), "uncertain preflight must reject every later save")
	_assert_equal(_slot_fingerprints(), slots_before_rejected_save, "rejected save must not touch primary, backup, or candidates")

	session.clear_injections()
	if reload_button != null and reload_button.is_visible_in_tree():
		await _click(reload_button)
	else:
		_assert_true(session.load_game(), "fallback reload must only keep the negative control runnable")
	_assert_true(not session.is_persistence_blocked() and not session.is_reload_required(), "successful reload must clear the global freeze")
	_assert_equal(int(session.snapshot().tick), 5, "successful reload must install restored primary tick 5")
	_assert_equal(int(session.snapshot().seed), 9811, "successful reload must preserve disk seed authority")
	_assert_true(recovery_band != null and not recovery_band.visible, "successful reload must hide global recovery UI")
	_assert_equal(state_events.size(), 1, "successful reload must emit exactly one authoritative state change")
	_assert_true(not recovery_events.is_empty() and not bool(recovery_events[-1].reload_required), "successful reload must emit a cleared recovery state")
	_assert_equal(_fingerprint(session.DEFAULT_SAVE_PATH), old_primary, "reload must preserve restored primary fingerprint")
	_assert_equal(_fingerprint(session.DEFAULT_SAVE_PATH + session.BACKUP_SUFFIX), old_backup, "reload must preserve backup fingerprint")
	_assert_equal(battle_events.size(), 0, "reload must not synthesize battle completion")
	_assert_equal(success_notices.size(), 0, "reload must not synthesize save success")
	_assert_no_transaction_scratch()

	_cleanup_slots()
	main.queue_free()
	session.queue_free()
	await process_frame
	if failures.is_empty():
		print("SAVE_PREFLIGHT_RECOVERY_OK assertions=%d authority=primary_tick_5 backup_tick_2 staged_tick_9 ui=global scratch=clean" % assertions)
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("SAVE_PREFLIGHT_RECOVERY_FAILED assertions=%d failures=%d" % [assertions, failures.size()])
		quit(1)

func _slot_fingerprints() -> Dictionary:
	return {
		"primary": _fingerprint(session.DEFAULT_SAVE_PATH),
		"backup": _fingerprint(session.DEFAULT_SAVE_PATH + session.BACKUP_SUFFIX),
		"temp": _fingerprint(session.DEFAULT_SAVE_PATH + session.SAVE_TEMP_SUFFIX),
		"rollback": _fingerprint(session.DEFAULT_SAVE_PATH + session.ROLLBACK_SUFFIX),
	}

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

func _read_tick(path: String) -> int:
	var parser := JSON.new()
	return int(parser.data.get("tick", -1)) if parser.parse(FileAccess.get_file_as_string(path)) == OK and parser.data is Dictionary else -1

func _assert_no_transaction_scratch() -> void:
	for suffix in [session.SAVE_TEMP_SUFFIX, session.BACKUP_TEMP_SUFFIX, session.BACKUP_PREVIOUS_SUFFIX, session.ROLLBACK_SUFFIX, session.RECOVERY_SUFFIX, session.BACKUP_SUFFIX + session.RECOVERY_SUFFIX]:
		_assert_false(FileAccess.file_exists(session.DEFAULT_SAVE_PATH + suffix), "successful reload must clean scratch artifact %s" % suffix)

func _instantiate_main_for(subject: Node) -> Control:
	var main := load("res://scenes/main.tscn").instantiate() as Control
	main.set("session", subject)
	return main

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
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.position = position
	up.global_position = position
	up.pressed = false
	root.push_input(up)
	await _settle()

func _wait_frames(count: int) -> void:
	for index in range(count):
		await process_frame

func _settle() -> void:
	await _wait_frames(5)

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
