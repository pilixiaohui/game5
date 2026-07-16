extends SceneTree

const FaultSession = preload("res://tests/fault_injecting_game_session.gd")
const BattlePage = preload("res://scripts/ui/battle_page.gd")
const REAL_AUTOSAVE_MINIMUM_MSEC := 30000
const REAL_AUTOSAVE_DEADLINE_MSEC := 37000

var session: Node
var failures: Array[String] = []
var assertions := 0
var scratch_data_root := ""

func _initialize() -> void:
	root.size = Vector2i(1600, 900)
	call_deferred("_run")

func _run() -> void:
	Engine.max_fps = 30
	session = root.get_node("GameSession")
	session.set_process(false)
	scratch_data_root = _argument("--scratch-data-root=").simplify_path()
	var save_path := ProjectSettings.globalize_path(session.DEFAULT_SAVE_PATH).simplify_path()
	if scratch_data_root.is_empty() or not save_path.begins_with(scratch_data_root + "/"):
		push_error("ACCEPTANCE_REGRESSIONS_REFUSED scratch root does not own the save path")
		quit(1)
		return

	var before := failures.size()
	await _test_new_game_modal_cancel_and_escape()
	_print_case("ACC-SAVE-004 new-game cancel and Esc are side-effect free", before)
	before = failures.size()
	await _test_retreat_confirmation_is_a_safe_decision_boundary()
	_print_case("ACC-RULE-007 retreat confirmation freezes and resolves atomically", before)
	before = failures.size()
	await _test_retreat_persistence_failures_are_atomic()
	_print_case("ACC-SAVE-001 retreat I/O failures preserve memory and committed slots", before)
	before = failures.size()
	await _test_ascension_layout_at_supported_resolutions()
	_print_case("ACC-A11Y-001/002 ascension layout and text remain readable", before)
	before = failures.size()
	await _test_global_persistence_recovery_entrypoints()
	_print_case("ACC-SAVE-005 uncertain saves expose one global reload entry", before)

	_cleanup_slots()
	if failures.is_empty():
		await _finish_and_quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("ACCEPTANCE_REGRESSIONS_FAILED cases=5 resolutions=3 assertions=%d failures=%d" % [assertions, failures.size()])
		await _finish_and_quit(1)

func _finish_and_quit(status: int) -> void:
	session.set_process(false)
	for child in root.get_children():
		if child != session:
			child.free()
	await process_frame
	_cleanup_slots()
	if status == 0:
		var exit_ready_file := _argument("--exit-ready-file=").simplify_path()
		var lifecycle_root := scratch_data_root.get_base_dir()
		if exit_ready_file.is_empty() or exit_ready_file.get_base_dir() != lifecycle_root:
			push_error("ACCEPTANCE_REGRESSIONS_REFUSED exit-ready file is outside the lifecycle root")
			quit(1)
			return
		var marker := FileAccess.open(exit_ready_file, FileAccess.WRITE)
		if marker == null:
			push_error("ACCEPTANCE_REGRESSIONS_FAILED could not publish exit-ready marker")
			quit(1)
			return
		marker.store_line("ready")
		marker.flush()
		marker.close()
		print("ACCEPTANCE_ASSERTIONS_OK cases=5 resolutions=3 assertions=%d" % assertions)
	quit(status)

func _test_new_game_modal_cancel_and_escape() -> void:
	_cleanup_slots()
	session.new_game(8401)
	session.advance_steps(9)
	_assert_true(session.save_game(), "new-game UI fixture must create a primary slot")
	_assert_true(session.save_game(), "new-game UI fixture must create a committed backup")
	var state_before := JSON.stringify(session.snapshot())
	var primary_before := FileAccess.get_file_as_bytes(session.DEFAULT_SAVE_PATH)
	var backup_before := FileAccess.get_file_as_bytes(session.DEFAULT_SAVE_PATH + session.BACKUP_SUFFIX)
	var main := load("res://scenes/main.tscn").instantiate() as Control
	root.add_child(main)
	await _settle()
	var new_game_button := main.find_child("NewGameButton", true, false) as Button
	var continue_button := main.find_child("ContinueButton", true, false) as Button
	_assert_true(new_game_button != null and continue_button != null, "title must expose stable new-game and continue controls")
	if new_game_button == null or continue_button == null:
		main.queue_free()
		await process_frame
		return

	await _click(new_game_button)
	var confirmation := main.find_child("NewGameConfirmation", true, false) as Control
	_assert_true(confirmation != null and confirmation.visible, "existing save must open the new-game modal")
	_assert_slots_unchanged(state_before, primary_before, backup_before, "opening new-game modal")
	var cancel_button := main.find_child("CancelNewGameButton", true, false) as Button
	_assert_true(cancel_button != null, "new-game modal must expose cancel")
	if cancel_button != null:
		await _click(cancel_button)
		_assert_true(not confirmation.visible, "pointer cancel must close the new-game modal")
		_assert_true(root.gui_get_focus_owner() == new_game_button, "cancel must restore focus to the new-game trigger")
	_assert_slots_unchanged(state_before, primary_before, backup_before, "pointer cancel")
	_assert_no_save_transients("pointer cancel")

	await _click(new_game_button)
	_assert_true(confirmation.visible, "new-game modal must reopen after cancellation")
	await _press_escape()
	_assert_true(not confirmation.visible, "Esc must close the topmost new-game modal")
	_assert_true(root.gui_get_focus_owner() == new_game_button, "Esc must restore focus to the new-game trigger")
	_assert_true(not continue_button.disabled, "continue must remain available after modal cancellation")
	_assert_slots_unchanged(state_before, primary_before, backup_before, "Esc cancel")
	_assert_no_save_transients("Esc cancel")

	await _click(new_game_button)
	_assert_true(confirmation.visible, "new-game modal must reopen for keyboard focus traversal")
	await _press_key(KEY_TAB)
	_assert_focus_in(confirmation, "Tab")
	await _press_key(KEY_TAB, true)
	_assert_focus_in(confirmation, "Shift+Tab")
	await _press_key(KEY_UP)
	_assert_focus_in(confirmation, "Up")
	await _press_key(KEY_DOWN)
	_assert_focus_in(confirmation, "Down")
	await _press_key(KEY_LEFT)
	_assert_focus_in(confirmation, "Left")
	await _press_key(KEY_RIGHT)
	_assert_focus_in(confirmation, "Right")
	await _press_key(KEY_ENTER)
	_assert_true(_find_shell(main) == null, "Enter after modal traversal must not activate a background command")
	_assert_slots_unchanged(state_before, primary_before, backup_before, "modal keyboard traversal")
	main.queue_free()
	await process_frame

func _test_retreat_confirmation_is_a_safe_decision_boundary() -> void:
	_cleanup_slots()
	session.new_game(8402)
	session.set_speed(4)
	session.state.units.biter = 16
	session.state.units.root_spore = 4
	_assert_true(session.attack_node("B"), "retreat UI fixture must start a production battle")
	var main := load("res://scenes/main.tscn").instantiate() as Control
	root.add_child(main)
	await _settle()
	main.call("_show_game")
	await _settle()
	var shell := _find_shell(main)
	_assert_true(shell != null, "retreat UI fixture must expose the game shell")
	if shell == null:
		main.queue_free()
		await process_frame
		return
	shell.call("_show_page", "battle")
	await _settle()
	var retreat_button := _find_button_by_text(main, "撤离")
	var confirm_button := _find_button_by_text(main, "确认撤离")
	var close_button := _find_button_by_text(main, "关闭")
	_assert_true(retreat_button != null and confirm_button != null and close_button != null, "battle page must expose retreat confirmation controls")
	if retreat_button == null or confirm_button == null or close_button == null:
		main.queue_free()
		await process_frame
		return
	var confirm_band := confirm_button.get_parent().get_parent() as Control
	session.set_process(true)
	var tick_before := int(session.state.tick)
	await _click_same_frame(retreat_button)
	_assert_true(confirm_band.visible, "retreat command must open a visible confirmation")
	var battle_before := JSON.stringify(session.state.active_battle)
	await _wait_frames(18)
	_assert_equal(int(session.state.tick), tick_before, "battle tick must not advance while retreat confirmation is open")
	_assert_equal(JSON.stringify(session.state.active_battle), battle_before, "battle facts must not change while retreat confirmation is open")

	await _click_same_frame(close_button)
	_assert_true(not confirm_band.visible, "closing retreat confirmation must hide it")
	await _wait_frames(12)
	_assert_true(int(session.state.tick) > tick_before, "cancelling retreat must restore normal simulation")
	_assert_true(not session.state.active_battle.is_empty(), "cancelled retreat must leave the active battle available")
	var retreats_before := int(session.state.stats.retreats)
	await _click_same_frame(retreat_button)
	await _click_same_frame(confirm_button)
	_assert_true(session.state.active_battle.is_empty(), "confirming retreat must clear the active battle")
	_assert_equal(int(session.state.stats.retreats), retreats_before + 1, "confirming retreat must commit exactly one retreat")
	_assert_true(FileAccess.file_exists(session.DEFAULT_SAVE_PATH), "confirmed retreat must persist its production result")
	session.set_process(false)
	main.queue_free()
	await process_frame

func _test_retreat_persistence_failures_are_atomic() -> void:
	var subject := FaultSession.new()
	subject.name = "RetreatFaultSession"
	root.add_child(subject)
	subject.set_process(false)
	var ended_events: Array = []
	subject.battle_ended.connect(func(node_id: String, captured: bool) -> void: ended_events.append([node_id, captured]))
	var cases := [
		{"name": "staged open", "boundary": "write_staged_snapshot", "phase": "open"},
		{"name": "staged partial write", "boundary": "write_staged_snapshot", "phase": "write"},
		{"name": "primary rename", "boundary": "commit_primary", "phase": "rename"},
	]
	for index in range(cases.size()):
		var case: Dictionary = cases[index]
		_cleanup_slots_for(subject)
		subject.clear_injections()
		ended_events.clear()
		subject.new_game(8450 + index)
		subject.set_speed(4)
		subject.state.units.biter = 16
		subject.state.units.root_spore = 4
		_assert_true(subject.attack_node("B"), "%s fixture must start a production battle" % case.name)
		_assert_true(subject.save_game(), "%s fixture must create a primary" % case.name)
		_assert_true(subject.save_game(), "%s fixture must create a committed backup" % case.name)
		var state_before := JSON.stringify(subject.snapshot())
		var primary_before := FileAccess.get_file_as_bytes(subject.DEFAULT_SAVE_PATH)
		var backup_before := FileAccess.get_file_as_bytes(subject.DEFAULT_SAVE_PATH + subject.BACKUP_SUFFIX)
		var committed_before := _committed_slot_fingerprint(subject)
		subject.clear_injections()
		subject.inject(case.boundary, case.phase)
		var page := BattlePage.new(subject)
		root.add_child(page)
		page.set_snapshot(subject.snapshot())
		await _settle()
		var retreat_button := page.find_child("RetreatButton", true, false) as Button
		var confirm_button := page.find_child("ConfirmRetreatButton", true, false) as Button
		var confirmation := page.find_child("RetreatConfirmation", true, false) as Control
		_assert_true(retreat_button != null and confirm_button != null and confirmation != null, "%s must expose production retreat controls" % case.name)
		subject.set_process(true)
		var tick_before := int(subject.state.tick)
		await _click_same_frame(retreat_button)
		await _wait_frames(12)
		_assert_equal(int(subject.state.tick), tick_before, "%s confirmation must pause the real scheduler" % case.name)
		await _click_same_frame(confirm_button)
		_assert_true(confirmation.visible, "%s failure must keep confirmation visible for retry" % case.name)
		await _wait_frames(12)
		_assert_equal(int(subject.state.tick), tick_before, "%s failure must retain decision pause" % case.name)
		_assert_equal(JSON.stringify(subject.snapshot()), state_before, "%s failure must preserve memory" % case.name)
		_assert_equal(FileAccess.get_file_as_bytes(subject.DEFAULT_SAVE_PATH), primary_before, "%s failure must preserve primary bytes" % case.name)
		_assert_equal(FileAccess.get_file_as_bytes(subject.DEFAULT_SAVE_PATH + subject.BACKUP_SUFFIX), backup_before, "%s failure must preserve backup bytes" % case.name)
		_assert_equal(_committed_slot_fingerprint(subject), committed_before, "%s not-committed result must preserve path/hash/size/nanosecond mtime" % case.name)
		_assert_no_save_transients_for(subject, "%s not-committed result" % case.name)
		_assert_commit_outcome(subject, "not_committed", "%s failure" % case.name)
		_assert_equal(ended_events.size(), 0, "%s failure must not emit battle_ended" % case.name)
		_assert_true("%s.%s" % [case.boundary, case.phase] in subject.operation_phase_trace, "%s fixture must reach the injected phase" % case.name)
		subject.clear_injections()
		await _click_same_frame(confirm_button)
		_assert_true(not confirmation.visible, "%s clean retry must close confirmation" % case.name)
		_assert_true(subject.state.active_battle.is_empty(), "%s clean retry must commit retreat" % case.name)
		_assert_equal(ended_events.size(), 1, "%s clean retry must emit battle_ended once" % case.name)
		subject.set_process(false)
		page.queue_free()
		await process_frame
	await _test_post_commit_retreat_outcomes(subject, ended_events)
	subject.clear_injections()
	_cleanup_slots_for(subject)
	subject.queue_free()
	await process_frame

func _test_post_commit_retreat_outcomes(subject: Node, ended_events: Array) -> void:
	var cases := [
		{"name": "existing post-commit open", "existing": true, "boundary": "validate_committed_primary", "phase": "open", "outcome": "uncertain"},
		{"name": "existing post-commit read", "existing": true, "boundary": "validate_committed_primary", "phase": "read", "outcome": "uncertain"},
		{"name": "existing post-commit corruption", "existing": true, "boundary": "commit_primary", "corrupt": true, "outcome": "not_committed"},
		{"name": "first-save post-commit open", "existing": false, "boundary": "validate_first_primary", "phase": "open", "outcome": "uncertain"},
		{"name": "first-save post-commit read", "existing": false, "boundary": "validate_first_primary", "phase": "read", "outcome": "uncertain"},
		{"name": "first-save post-commit corruption", "existing": false, "boundary": "commit_first_primary", "corrupt": true, "outcome": "not_committed"},
	]
	for index in range(cases.size()):
		var case: Dictionary = cases[index]
		_cleanup_slots_for(subject)
		subject.clear_injections()
		ended_events.clear()
		subject.new_game(8500 + index)
		subject.set_speed(4)
		subject.state.units.biter = 16
		subject.state.units.root_spore = 4
		_assert_true(subject.attack_node("B"), "%s fixture must start a production battle" % case.name)
		if case.existing:
			_assert_true(subject.save_game(), "%s fixture must create a primary" % case.name)
			_assert_true(subject.save_game(), "%s fixture must create a committed backup" % case.name)
		var state_before := JSON.stringify(subject.snapshot())
		var primary_before := FileAccess.get_file_as_bytes(subject.DEFAULT_SAVE_PATH)
		var backup_before := FileAccess.get_file_as_bytes(subject.DEFAULT_SAVE_PATH + subject.BACKUP_SUFFIX)
		var committed_before := _committed_slot_fingerprint(subject)
		subject.clear_injections()
		if case.get("corrupt", false):
			subject.corrupt_after(case.boundary)
		else:
			subject.inject(case.boundary, case.phase)
		var main := _instantiate_main_for(subject)
		root.add_child(main)
		await _settle()
		main.call("_show_game")
		await _settle()
		var shell := _find_shell(main)
		if shell != null:
			shell.call("_show_page", "battle")
			await _settle()
		var page := shell.get("pages").get("battle") as Control if shell != null else null
		await _settle()
		var retreat_button := page.find_child("RetreatButton", true, false) as Button if page != null else null
		var confirm_button := page.find_child("ConfirmRetreatButton", true, false) as Button if page != null else null
		var confirmation := page.find_child("RetreatConfirmation", true, false) as Control if page != null else null
		_assert_true(retreat_button != null and confirm_button != null and confirmation != null, "%s must expose production retreat controls" % case.name)
		if retreat_button == null or confirm_button == null or confirmation == null:
			main.queue_free()
			await process_frame
			continue
		subject.set_process(true)
		var tick_before := int(subject.state.tick)
		await _click_same_frame(retreat_button)
		await _click_same_frame(confirm_button)
		_assert_equal(JSON.stringify(subject.snapshot()), state_before, "%s failed call must not install the candidate in memory" % case.name)
		_assert_equal(ended_events.size(), 0, "%s failed call must not emit battle_ended" % case.name)
		_assert_commit_outcome(subject, case.outcome, case.name)
		if case.outcome == "uncertain":
			_assert_true(subject.is_persistence_blocked(), "%s must enter persistence-blocked state" % case.name)
			_assert_true(not confirmation.visible, "%s must close the retry confirmation after the commit point" % case.name)
			var blocked_band := main.find_child("PersistenceRecovery", true, false) as Control
			var reload_button := main.find_child("ReloadAfterPersistenceBlock", true, false) as Button
			_assert_true(blocked_band != null and blocked_band.visible, "%s must show a player-visible persistence-blocked state" % case.name)
			_assert_true(reload_button != null and reload_button.visible, "%s must expose reload as the only recovery command" % case.name)
			await _wait_frames(12)
			_assert_equal(int(subject.state.tick), tick_before, "%s must freeze the real scheduler" % case.name)
			if subject.is_persistence_blocked():
				var target_before := int(subject.state.targets.worker)
				subject.set_unit_target("worker", 1)
				_assert_equal(int(subject.state.targets.worker), target_before, "%s must reject later gameplay mutations" % case.name)
				var committed_after_uncertain := _committed_slot_fingerprint(subject)
				_assert_false(subject.save_game(), "%s must reject later saves" % case.name)
				_assert_equal(_committed_slot_fingerprint(subject), committed_after_uncertain, "%s blocked save must not touch committed slots" % case.name)
			var disk_candidate := _read_snapshot_json(subject.DEFAULT_SAVE_PATH)
			var disk_battle: Variant = disk_candidate.get("active_battle", null)
			_assert_true(disk_battle is Dictionary and (disk_battle as Dictionary).is_empty(), "%s primary must contain the complete retreat candidate after rename" % case.name)
			if case.existing:
				_assert_equal(FileAccess.get_file_as_bytes(subject.DEFAULT_SAVE_PATH + subject.BACKUP_SUFFIX), backup_before, "%s must preserve the committed backup until authority is reloaded" % case.name)
			subject.clear_injections()
			if reload_button != null:
				await _click_same_frame(reload_button)
			else:
				_assert_true(subject.load_game(), "%s clean reload fallback must succeed" % case.name)
			_assert_true(not subject.is_persistence_blocked(), "%s clean reload must clear persistence blocking" % case.name)
			_assert_true(subject.state.active_battle.is_empty(), "%s reload must install the committed retreat candidate" % case.name)
			_assert_equal(ended_events.size(), 0, "%s reload must not synthesize battle_ended" % case.name)
			_assert_no_save_transients_for(subject, "%s reload" % case.name)
		else:
			_assert_false(subject.is_persistence_blocked(), "%s known rollback must remain retryable" % case.name)
			_assert_true(confirmation.visible, "%s known rollback must retain the retry confirmation" % case.name)
			_assert_equal(_committed_slot_fingerprint(subject), committed_before, "%s not-committed rollback must preserve path/hash/size/nanosecond mtime" % case.name)
			_assert_equal(FileAccess.get_file_as_bytes(subject.DEFAULT_SAVE_PATH + subject.BACKUP_SUFFIX), backup_before, "%s known rollback must preserve backup bytes" % case.name)
			if case.existing:
				_assert_equal(FileAccess.get_file_as_bytes(subject.DEFAULT_SAVE_PATH), primary_before, "%s must restore the prior primary generation" % case.name)
				subject.clear_injections()
				_assert_true(subject.load_game(), "%s clean reload must install the restored old generation" % case.name)
				_assert_true(not subject.state.active_battle.is_empty(), "%s restored generation must retain the battle for retry" % case.name)
			else:
				_assert_false(FileAccess.file_exists(subject.DEFAULT_SAVE_PATH), "%s must remove the invalid first primary" % case.name)
				_assert_false(FileAccess.file_exists(subject.DEFAULT_SAVE_PATH + subject.BACKUP_SUFFIX), "%s must not invent a backup" % case.name)
				subject.clear_injections()
			_assert_no_save_transients_for(subject, "%s rollback" % case.name)
			page.set_snapshot(subject.snapshot())
			await _click_same_frame(confirm_button)
			_assert_true(not confirmation.visible, "%s clean retry must commit and close confirmation" % case.name)
			_assert_true(subject.state.active_battle.is_empty(), "%s clean retry must install the retreat" % case.name)
			_assert_equal(ended_events.size(), 1, "%s clean retry must emit battle_ended exactly once" % case.name)
			subject.state = {}
			_assert_true(subject.load_game(), "%s post-retry reload must install the committed result" % case.name)
			var reloaded_battle: Variant = subject.state.get("active_battle", null)
			_assert_true(reloaded_battle is Dictionary and (reloaded_battle as Dictionary).is_empty(), "%s post-retry reload must retain the retreat result" % case.name)
		subject.set_process(false)
		main.queue_free()
		await process_frame

func _test_global_persistence_recovery_entrypoints() -> void:
	var subject := FaultSession.new()
	subject.name = "GlobalRecoveryFaultSession"
	root.add_child(subject)
	subject.set_process(false)
	_assert_true(subject.has_signal("persistence_recovery_changed"), "GameSession must expose an explicit persistence recovery state signal")
	var battle_events: Array = []
	var success_notices: Array[String] = []
	subject.battle_ended.connect(func(node_id: String, captured: bool) -> void: battle_events.append([node_id, captured]))
	subject.notice_posted.connect(func(message: String, level: String) -> void:
		if level == "success":
			success_notices.append(message)
	)

	await _exercise_uncertain_save_entry(subject, "Ctrl+S", func(main: Control) -> void:
		await _press_save_shortcut()
	, battle_events, success_notices)
	await _exercise_uncertain_save_entry(subject, "system page save", func(main: Control) -> void:
		var shell := _find_shell(main)
		if shell != null:
			var system_button := _find_button_by_text(shell, "系统")
			_assert_true(system_button != null, "system page fixture must expose the production navigation command")
			if system_button != null:
				await _click_same_frame(system_button)
				await _settle()
		var save_button := _find_button_by_text(main, "手动保存")
		_assert_true(save_button != null, "system page must expose its production save command")
		if save_button != null:
			await _click_same_frame(save_button)
	, battle_events, success_notices)
	await _exercise_uncertain_save_entry(subject, "scheduler autosave", func(main: Control) -> void:
		await _trigger_real_autosave(subject)
	, battle_events, success_notices)

	_cleanup_slots_for(subject)
	subject.state = {}
	subject.clear_injections()
	subject.inject("validate_first_primary", "open")
	var title_main := _instantiate_main_for(subject)
	root.add_child(title_main)
	await _settle()
	var new_game := title_main.find_child("NewGameButton", true, false) as Button
	_assert_true(new_game != null, "first-save fixture must expose the production new-game command")
	battle_events.clear()
	success_notices.clear()
	if new_game != null:
		await _click_same_frame(new_game)
	_assert_true("validate_first_primary.open" in subject.operation_phase_trace, "first new game must reach the injected post-commit open boundary")
	await _assert_and_resolve_global_recovery(title_main, subject, "first new game save", battle_events, success_notices)
	_assert_true(_find_shell(title_main) != null, "successful first-save reload must enter the game using disk authority")
	title_main.queue_free()
	await process_frame
	subject.set_process(false)
	subject.queue_free()
	await process_frame

func _exercise_uncertain_save_entry(subject: Node, action_name: String, trigger: Callable, battle_events: Array, success_notices: Array[String]) -> void:
	_cleanup_slots_for(subject)
	subject.clear_injections()
	subject.new_game(8600 + assertions)
	subject.advance_steps(2)
	_assert_true(subject.save_game(), "%s fixture must create a primary" % action_name)
	subject.advance_steps(2)
	_assert_true(subject.save_game(), "%s fixture must create a backup" % action_name)
	subject.advance_steps(1)
	var main := _instantiate_main_for(subject)
	root.add_child(main)
	await _settle()
	main.call("_show_game")
	await _settle()
	subject.clear_injections()
	subject.inject("validate_committed_primary", "open")
	battle_events.clear()
	success_notices.clear()
	await trigger.call(main)
	_assert_true("validate_committed_primary.open" in subject.operation_phase_trace, "%s must reach the injected post-commit open boundary" % action_name)
	await _assert_and_resolve_global_recovery(main, subject, action_name, battle_events, success_notices)
	main.queue_free()
	await process_frame

func _assert_and_resolve_global_recovery(main: Control, subject: Node, action_name: String, battle_events: Array, success_notices: Array[String]) -> void:
	var recovery_band := main.find_child("PersistenceRecovery", true, false) as Control
	var reload_buttons := main.find_children("ReloadAfterPersistenceBlock", "Button", true, false)
	var reload_button := reload_buttons[0] as Button if reload_buttons.size() == 1 else null
	_assert_commit_outcome(subject, "uncertain", action_name)
	_assert_true(subject.is_reload_required(), "%s must require authoritative reload" % action_name)
	_assert_equal(reload_buttons.size(), 1, "%s must expose exactly one reload command" % action_name)
	_assert_true(recovery_band != null and recovery_band.is_visible_in_tree(), "%s must show the global recovery state on the current page" % action_name)
	_assert_true(reload_button != null and reload_button.is_visible_in_tree(), "%s reload command must be visible and reachable" % action_name)
	var disk_snapshot := _read_snapshot_json(subject.DEFAULT_SAVE_PATH)
	_assert_true(not disk_snapshot.is_empty(), "%s uncertain primary must remain a readable authority candidate" % action_name)
	var disk_tick := int(disk_snapshot.get("tick", -1))
	var disk_seed := int(disk_snapshot.get("seed", -1))
	var shell := _find_shell(main)
	if shell != null:
		var map_button := _find_button_by_text(shell, "区域图")
		_assert_true(map_button != null, "%s must expose production navigation while recovery remains global" % action_name)
		if map_button != null:
			await _click_same_frame(map_button)
			await _settle()
		var switched_buttons := main.find_children("ReloadAfterPersistenceBlock", "Button", true, false)
		_assert_equal(switched_buttons.size(), 1, "%s page switch must retain exactly one recovery command" % action_name)
		_assert_true(switched_buttons.size() == 1 and switched_buttons[0] == reload_button, "%s page switch must retain the Main-owned recovery command" % action_name)
		_assert_true(recovery_band != null and recovery_band.is_visible_in_tree(), "%s page switch must keep recovery visible" % action_name)
	if reload_button != null and reload_button.is_visible_in_tree():
		subject.clear_injections()
		subject.inject("load_primary", "open")
		await _click_same_frame(reload_button)
		_assert_true("load_primary.open" in subject.operation_phase_trace, "%s failed reload must reach the production primary-read boundary" % action_name)
		_assert_true(subject.is_reload_required(), "%s failed reload must remain retryable" % action_name)
		_assert_true(recovery_band.is_visible_in_tree(), "%s failed reload must keep recovery visible" % action_name)
		_assert_true(not reload_button.disabled and root.gui_get_focus_owner() == reload_button, "%s failed reload must restore focus to the enabled reload command" % action_name)
	else:
		_assert_true(false, "%s must use the visible production reload command" % action_name)
	var sentinel_tick := disk_tick + 100000
	var sentinel_seed := disk_seed + 100000
	if not subject.state.is_empty():
		subject.state.tick = sentinel_tick
		subject.state.seed = sentinel_seed
	subject.clear_injections()
	if reload_button != null and reload_button.is_visible_in_tree():
		await _click_same_frame(reload_button)
	else:
		_assert_true(subject.load_game(), "%s fallback reload must restore disk authority" % action_name)
	_assert_true(not subject.is_persistence_blocked() and not subject.is_reload_required(), "%s successful reload must clear the global freeze" % action_name)
	_assert_equal(int(subject.state.get("tick", -1)), disk_tick, "%s successful reload must replace the in-memory tick sentinel with disk authority" % action_name)
	_assert_equal(int(subject.state.get("seed", -1)), disk_seed, "%s successful reload must replace the in-memory seed sentinel with disk authority" % action_name)
	_assert_equal(battle_events.size(), 0, "%s save failure and reload must not synthesize retreat/battle completion" % action_name)
	_assert_equal(success_notices.size(), 0, "%s uncertain save and reload must not synthesize a successful-save notice" % action_name)
	if recovery_band != null:
		_assert_true(not recovery_band.visible, "%s successful reload must hide the global recovery state" % action_name)

func _trigger_real_autosave(subject: Node) -> void:
	var started_msec := Time.get_ticks_msec()
	subject.set_process(true)
	while Time.get_ticks_msec() - started_msec < REAL_AUTOSAVE_DEADLINE_MSEC and not ("validate_committed_primary.open" in subject.operation_phase_trace):
		await process_frame
	subject.set_process(false)
	var elapsed_msec := Time.get_ticks_msec() - started_msec
	_assert_true(elapsed_msec >= REAL_AUTOSAVE_MINIMUM_MSEC, "scheduler autosave must cross the real 30-second production interval")
	_assert_true(elapsed_msec < REAL_AUTOSAVE_DEADLINE_MSEC, "scheduler autosave must reach the injected boundary before its bounded deadline")
	print("RECOVERY_UI_REAL_AUTOSAVE elapsed_msec=%d boundary=%s" % [elapsed_msec, "validate_committed_primary.open" in subject.operation_phase_trace])

func _instantiate_main_for(subject: Node) -> Control:
	var main := load("res://scenes/main.tscn").instantiate() as Control
	for property in main.get_property_list():
		if String(property.name) == "session":
			main.set("session", subject)
			break
	return main

func _test_ascension_layout_at_supported_resolutions() -> void:
	_cleanup_slots()
	session.new_game(8403)
	session.state.stats.nodes_captured = 6
	session.state.stats.biomass_formed = 370.0
	session.state.stats.enemies_defeated = 130
	session.state.stats.genes_formed = 32.0
	session.state.units.formed = 40
	session.state.mutations = [session.CANDIDATES[0].duplicate(true)]
	var main := load("res://scenes/main.tscn").instantiate() as Control
	root.add_child(main)
	await _settle()
	main.call("_show_game")
	await _settle()
	var shell := _find_shell(main)
	_assert_true(shell != null, "ascension layout fixture must expose the game shell")
	if shell == null:
		main.queue_free()
		await process_frame
		return
	shell.call("_show_page", "ascension")
	await _settle()
	_assert_equal(String(ProjectSettings.get_setting("display/window/stretch/mode")), "disabled", "desktop UI must use one-to-one logical pixels at supported windows")
	var points_text := str(session.ascension_preview().points)
	var availability := _find_label_by_text(main, "尚未开放")
	var page_title := _find_label_by_text(main, "飞升只读预览")
	var return_button := _find_button_by_text(main, "返回进化")
	var ascension_page := page_title.get_parent().get_parent() as Control if page_title != null else null
	var scroll := _find_scroll_container(ascension_page)
	var longest_label := _find_longest_label(scroll)
	_assert_true(availability != null and page_title != null, "ascension header must expose title and availability status")
	_assert_true(scroll != null and longest_label != null, "ascension body must expose a scroll viewport and rendered copy")
	for resolution in [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]:
		root.size = resolution
		await _settle_rendered()
		var texture := root.get_texture()
		var image: Image = texture.get_image() if texture != null else null
		var point_label := _find_label_by_text(main, points_text)
		var body_label := _find_label_containing(main, "购买后")
		var viewport_rect := Rect2(Vector2.ZERO, Vector2(resolution))
		_assert_true(image != null and image.get_size() == resolution, "%s must produce a real rendered frame" % resolution)
		_assert_true(point_label != null and point_label.is_visible_in_tree(), "%s point total must be visible" % resolution)
		_assert_true(body_label != null and body_label.is_visible_in_tree(), "%s ascension body copy must be visible" % resolution)
		_assert_true(return_button != null and return_button.is_visible_in_tree(), "%s ascension return command must remain reachable" % resolution)
		if return_button != null:
			_assert_true(viewport_rect.encloses(return_button.get_global_rect()), "%s return command rect must be fully inside the viewport, got %s" % [resolution, return_button.get_global_rect()])
			_assert_true(not return_button.disabled and return_button.focus_mode == Control.FOCUS_ALL, "%s return command must remain enabled and keyboard reachable" % resolution)
		if availability != null:
			var availability_rect := availability.get_global_rect()
			_assert_true(viewport_rect.encloses(availability_rect), "%s availability rect must be fully inside the viewport, got %s" % [resolution, availability_rect])
			_assert_true(availability_rect.size.x >= 80.0 and availability_rect.size.y <= 36.0, "%s availability must remain a horizontal header field, got %s" % [resolution, availability_rect.size])
			_assert_equal(availability.get_line_count(), 1, "%s availability must render on one actual line" % resolution)
			_assert_equal(availability.get_visible_line_count(), availability.get_line_count(), "%s availability must not hide rendered lines" % resolution)
			_assert_false(availability.clip_text, "%s availability must not clip text" % resolution)
			if image != null:
				var availability_pixels := _count_text_pixels(image, availability_rect)
				_assert_true(availability_pixels >= 12, "%s availability rect must contain rendered text pixels, got %d" % [resolution, availability_pixels])
		if page_title != null:
			_assert_equal(page_title.get_line_count(), 1, "%s page title must remain one rendered line" % resolution)
			_assert_true(page_title.get_global_rect().size.x >= 180.0, "%s page title must retain a readable horizontal rect" % resolution)
		if point_label != null:
			_assert_equal(point_label.autowrap_mode, TextServer.AUTOWRAP_OFF, "%s fixed-format point total must not wrap" % resolution)
			_assert_true(point_label.size.x >= 96.0 and point_label.size.y <= 60.0, "%s point total must remain a horizontal stable field, got %s" % [resolution, point_label.size])
		if body_label != null:
			_assert_true(body_label.get_theme_font_size("font_size") >= 16, "%s body text must be at least 16 logical pixels" % resolution)
		if return_button != null:
			_assert_true(return_button.get_theme_font_size("font_size") >= 16, "%s primary controls must be at least 16 logical pixels" % resolution)
		if scroll != null and longest_label != null:
			scroll.scroll_vertical = 1000000
			await _settle_rendered()
			texture = root.get_texture()
			image = texture.get_image() if texture != null else null
			var longest_rect := longest_label.get_global_rect()
			var visible_scroll_rect := scroll.get_global_rect().intersection(viewport_rect)
			_assert_true(visible_scroll_rect.encloses(longest_rect), "%s longest body text must be reachable in the visible scroll viewport, visible=%s text=%s" % [resolution, visible_scroll_rect, longest_rect])
			_assert_true(longest_rect.size.x >= 240.0 and longest_rect.size.y >= 16.0, "%s longest body text must retain a readable rect, got %s" % [resolution, longest_rect.size])
			_assert_true(longest_label.get_line_count() <= 3, "%s longest body text must use at most three actual lines, got %d" % [resolution, longest_label.get_line_count()])
			_assert_equal(longest_label.get_visible_line_count(), longest_label.get_line_count(), "%s longest body text must expose every rendered line" % resolution)
			_assert_false(longest_label.clip_text, "%s longest body text must not clip" % resolution)
			var longest_pixels := -1
			if image != null:
				longest_pixels = _count_text_pixels(image, longest_rect)
				_assert_true(longest_pixels >= 24, "%s longest body rect must contain rendered text pixels, got %d" % [resolution, longest_pixels])
			print("ASCENSION_RENDER size=%s header_rect=%s header_lines=%d longest_chars=%d longest_rect=%s longest_lines=%d longest_pixels=%d" % [resolution, availability.get_global_rect() if availability != null else Rect2(), availability.get_line_count() if availability != null else -1, longest_label.text.length(), longest_rect, longest_label.get_line_count(), longest_pixels])
			scroll.scroll_vertical = 0
	root.size = Vector2i(1600, 900)
	main.queue_free()
	await process_frame

func _assert_slots_unchanged(state_before: String, primary_before: PackedByteArray, backup_before: PackedByteArray, action: String) -> void:
	_assert_equal(JSON.stringify(session.snapshot()), state_before, "%s must preserve in-memory state" % action)
	_assert_equal(FileAccess.get_file_as_bytes(session.DEFAULT_SAVE_PATH), primary_before, "%s must preserve primary bytes" % action)
	_assert_equal(FileAccess.get_file_as_bytes(session.DEFAULT_SAVE_PATH + session.BACKUP_SUFFIX), backup_before, "%s must preserve backup bytes" % action)

func _assert_no_save_transients(action: String) -> void:
	for suffix in [session.SAVE_TEMP_SUFFIX, session.BACKUP_TEMP_SUFFIX, session.BACKUP_PREVIOUS_SUFFIX, session.ROLLBACK_SUFFIX, session.RECOVERY_SUFFIX, session.BACKUP_SUFFIX + session.RECOVERY_SUFFIX]:
		_assert_true(not FileAccess.file_exists(session.DEFAULT_SAVE_PATH + suffix), "%s must not leave %s" % [action, suffix])

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

func _click_same_frame(button: Button) -> void:
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
	await process_frame

func _press_escape() -> void:
	var down := InputEventKey.new()
	down.keycode = KEY_ESCAPE
	down.physical_keycode = KEY_ESCAPE
	down.pressed = true
	root.push_input(down)
	await process_frame
	var up := InputEventKey.new()
	up.keycode = KEY_ESCAPE
	up.physical_keycode = KEY_ESCAPE
	up.pressed = false
	root.push_input(up)
	await _settle()

func _press_key(keycode: Key, shift_pressed: bool = false) -> void:
	var down := InputEventKey.new()
	down.keycode = keycode
	down.physical_keycode = keycode
	down.shift_pressed = shift_pressed
	down.pressed = true
	root.push_input(down)
	var up := InputEventKey.new()
	up.keycode = keycode
	up.physical_keycode = keycode
	up.shift_pressed = shift_pressed
	up.pressed = false
	root.push_input(up)
	await _settle()

func _press_save_shortcut() -> void:
	var down := InputEventKey.new()
	down.keycode = KEY_S
	down.physical_keycode = KEY_S
	down.ctrl_pressed = true
	down.pressed = true
	root.push_input(down)
	var up := InputEventKey.new()
	up.keycode = KEY_S
	up.physical_keycode = KEY_S
	up.ctrl_pressed = true
	up.pressed = false
	root.push_input(up)
	await _settle()

func _assert_focus_in(scope: Control, action: String) -> void:
	var owner := root.gui_get_focus_owner()
	_assert_true(owner != null and scope.is_ancestor_of(owner), "%s must keep keyboard focus inside the new-game modal" % action)

func _wait_frames(count: int) -> void:
	for index in range(count):
		await process_frame

func _find_shell(node: Node) -> Node:
	if node.has_method("_show_page") and node.has_method("_update_battle_strip"):
		return node
	for child in node.get_children():
		var found := _find_shell(child)
		if found != null:
			return found
	return null

func _find_button_by_text(node: Node, text: String) -> Button:
	if node is Button and node.text == text:
		return node as Button
	for child in node.get_children():
		var found := _find_button_by_text(child, text)
		if found != null:
			return found
	return null

func _find_label_by_text(node: Node, text: String) -> Label:
	if node is Label and node.text == text:
		return node as Label
	for child in node.get_children():
		var found := _find_label_by_text(child, text)
		if found != null:
			return found
	return null

func _find_label_containing(node: Node, text: String) -> Label:
	if node is Label and text in node.text:
		return node as Label
	for child in node.get_children():
		var found := _find_label_containing(child, text)
		if found != null:
			return found
	return null

func _find_scroll_container(node: Node) -> ScrollContainer:
	if node == null:
		return null
	if node is ScrollContainer:
		return node as ScrollContainer
	for child in node.get_children():
		var found := _find_scroll_container(child)
		if found != null:
			return found
	return null

func _find_longest_label(node: Node) -> Label:
	if node == null:
		return null
	var longest: Label = node as Label if node is Label else null
	for child in node.get_children():
		var candidate := _find_longest_label(child)
		if candidate != null and (longest == null or candidate.text.length() > longest.text.length()):
			longest = candidate
	return longest

func _count_text_pixels(image: Image, rect: Rect2) -> int:
	var start_x := clampi(int(floor(rect.position.x)), 0, image.get_width())
	var start_y := clampi(int(floor(rect.position.y)), 0, image.get_height())
	var end_x := clampi(int(ceil(rect.end.x)), 0, image.get_width())
	var end_y := clampi(int(ceil(rect.end.y)), 0, image.get_height())
	var count := 0
	for y in range(start_y, end_y):
		for x in range(start_x, end_x):
			var color := image.get_pixel(x, y)
			if color.a > 0.9 and color.r + color.g + color.b > 1.0 and max(color.r, color.g, color.b) > 0.45:
				count += 1
	return count

func _settle_rendered() -> void:
	await _settle()
	await RenderingServer.frame_post_draw

func _settle() -> void:
	for index in range(4):
		await process_frame

func _print_case(name: String, before: int) -> void:
	if failures.size() == before:
		print("PASS %s" % name)
	else:
		print("FAIL %s failures=%d" % [name, failures.size() - before])

func _assert_commit_outcome(owner: Node, expected: String, action: String) -> void:
	_assert_true(owner.has_method("last_commit_outcome"), "%s must expose the explicit commit outcome" % action)
	if owner.has_method("last_commit_outcome"):
		_assert_equal(owner.last_commit_outcome(), expected, "%s must report %s" % [action, expected])

func _committed_slot_fingerprint(owner: Node) -> Dictionary:
	var global_paths: Array[String] = []
	var path_set: Array[String] = []
	for suffix in ["", owner.BACKUP_SUFFIX]:
		var local_path: String = owner.DEFAULT_SAVE_PATH + suffix
		if FileAccess.file_exists(local_path):
			global_paths.append(ProjectSettings.globalize_path(local_path))
			path_set.append(local_path.get_file())
	path_set.sort()
	if global_paths.is_empty():
		return {"paths": path_set, "sha256": "", "stat": ""}
	var sha_args := PackedStringArray(global_paths)
	var stat_args := PackedStringArray(["-c", "%n|%s|%y"])
	stat_args.append_array(PackedStringArray(global_paths))
	var sha_output: Array = []
	var stat_output: Array = []
	var sha_status := OS.execute("sha256sum", sha_args, sha_output, true)
	var stat_status := OS.execute("stat", stat_args, stat_output, true)
	_assert_equal(sha_status, 0, "external SHA-256 fingerprint must succeed")
	_assert_equal(stat_status, 0, "external nanosecond stat fingerprint must succeed")
	return {
		"paths": path_set,
		"sha256": "".join(sha_output).strip_edges(),
		"stat": "".join(stat_output).strip_edges(),
	}

func _assert_no_save_transients_for(owner: Node, action: String) -> void:
	for suffix in [owner.SAVE_TEMP_SUFFIX, owner.BACKUP_TEMP_SUFFIX, owner.BACKUP_PREVIOUS_SUFFIX, owner.ROLLBACK_SUFFIX, owner.RECOVERY_SUFFIX, owner.BACKUP_SUFFIX + owner.RECOVERY_SUFFIX]:
		_assert_false(FileAccess.file_exists(owner.DEFAULT_SAVE_PATH + suffix), "%s must clean scratch artifact %s" % [action, suffix])

func _read_snapshot_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parser := JSON.new()
	return parser.data if parser.parse(FileAccess.get_file_as_string(path)) == OK and parser.data is Dictionary else {}

func _cleanup_slots() -> void:
	_cleanup_slots_for(session)

func _cleanup_slots_for(owner: Node) -> void:
	for suffix in ["", owner.BACKUP_SUFFIX, owner.SAVE_TEMP_SUFFIX, owner.BACKUP_TEMP_SUFFIX, owner.BACKUP_PREVIOUS_SUFFIX, owner.ROLLBACK_SUFFIX, owner.RECOVERY_SUFFIX, owner.BACKUP_SUFFIX + owner.RECOVERY_SUFFIX]:
		var path: String = owner.DEFAULT_SAVE_PATH + suffix
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
