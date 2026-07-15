extends SceneTree

var session: Node
var failures: Array[String] = []
var assertions := 0
var scratch_data_root := ""

func _initialize() -> void:
	root.size = Vector2i(1600, 900)
	call_deferred("_run")

func _run() -> void:
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
	await _test_ascension_layout_at_supported_resolutions()
	_print_case("ACC-A11Y-001/002 ascension layout and text remain readable", before)

	_cleanup_slots()
	if failures.is_empty():
		print("ACCEPTANCE_REGRESSIONS_OK cases=3 resolutions=3 assertions=%d" % assertions)
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("ACCEPTANCE_REGRESSIONS_FAILED cases=3 resolutions=3 assertions=%d failures=%d" % [assertions, failures.size()])
		quit(1)

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
	main.queue_free()
	await process_frame

func _test_retreat_confirmation_is_a_safe_decision_boundary() -> void:
	_cleanup_slots()
	session.new_game(8402)
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
	await _click(retreat_button)
	_assert_true(confirm_band.visible, "retreat command must open a visible confirmation")
	var tick_before := int(session.state.tick)
	var battle_before := JSON.stringify(session.state.active_battle)
	session.call("_process", 2.2)
	_assert_equal(int(session.state.tick), tick_before, "battle tick must not advance while retreat confirmation is open")
	_assert_equal(JSON.stringify(session.state.active_battle), battle_before, "battle facts must not change while retreat confirmation is open")

	await _click(close_button)
	_assert_true(not confirm_band.visible, "closing retreat confirmation must hide it")
	session.call("_process", 1.1)
	_assert_true(int(session.state.tick) > tick_before, "cancelling retreat must restore normal simulation")
	_assert_true(not session.state.active_battle.is_empty(), "cancelled retreat must leave the active battle available")
	var retreats_before := int(session.state.stats.retreats)
	await _click(retreat_button)
	await _click(confirm_button)
	_assert_true(session.state.active_battle.is_empty(), "confirming retreat must clear the active battle")
	_assert_equal(int(session.state.stats.retreats), retreats_before + 1, "confirming retreat must commit exactly one retreat")
	_assert_true(FileAccess.file_exists(session.DEFAULT_SAVE_PATH), "confirmed retreat must persist its production result")
	main.queue_free()
	await process_frame

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
	for resolution in [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]:
		root.size = resolution
		await _settle()
		var point_label := _find_label_by_text(main, points_text)
		var body_label := _find_label_containing(main, "购买后")
		var return_button := _find_button_by_text(main, "返回进化")
		_assert_true(point_label != null and point_label.is_visible_in_tree(), "%s point total must be visible" % resolution)
		_assert_true(body_label != null and body_label.is_visible_in_tree(), "%s ascension body copy must be visible" % resolution)
		_assert_true(return_button != null and return_button.is_visible_in_tree(), "%s ascension return command must remain reachable" % resolution)
		if point_label != null:
			_assert_equal(point_label.autowrap_mode, TextServer.AUTOWRAP_OFF, "%s fixed-format point total must not wrap" % resolution)
			_assert_true(point_label.size.x >= 96.0 and point_label.size.y <= 60.0, "%s point total must remain a horizontal stable field, got %s" % [resolution, point_label.size])
		if body_label != null:
			_assert_true(body_label.get_theme_font_size("font_size") >= 16, "%s body text must be at least 16 logical pixels" % resolution)
		if return_button != null:
			_assert_true(return_button.get_theme_font_size("font_size") >= 16, "%s primary controls must be at least 16 logical pixels" % resolution)
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

func _settle() -> void:
	for index in range(4):
		await process_frame

func _print_case(name: String, before: int) -> void:
	if failures.size() == before:
		print("PASS %s" % name)
	else:
		print("FAIL %s failures=%d" % [name, failures.size() - before])

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

func _assert_equal(actual: Variant, expected: Variant, message: String) -> void:
	assertions += 1
	if actual != expected:
		failures.append("%s (actual=%s expected=%s)" % [message, actual, expected])
