extends SceneTree

const NATURAL_FORCE_SEED := 8731
const HUMAN_OBSERVATION_MSEC := 10500
const CONFIRMATION_REVIEW_MSEC := 1500
const REENTRY_DEADLINE_MSEC := 12000

var session: Node
var failures: Array[String] = []
var assertions := 0
var scratch_data_root := ""

func _initialize() -> void:
	root.size = Vector2i(1600, 900)
	Engine.max_fps = 30
	call_deferred("_run")

func _run() -> void:
	session = root.get_node("GameSession")
	session.set_process(false)
	scratch_data_root = _argument("--scratch-data-root=").simplify_path()
	var save_path := ProjectSettings.globalize_path(session.DEFAULT_SAVE_PATH).simplify_path()
	if scratch_data_root.is_empty() or not save_path.begins_with(scratch_data_root + "/"):
		push_error("RETREAT_WINDOW_REFUSED scratch root does not own the save path")
		quit(1)
		return

	_cleanup_slots()
	_naturally_form_first_force()
	if not failures.is_empty():
		await _finish()
		return
	_assert_true(session.save_game(), "natural-force fixture must commit the pre-battle generation")
	var baseline_primary := FileAccess.get_file_as_bytes(session.DEFAULT_SAVE_PATH)
	var baseline_disk := _read_slot(session.DEFAULT_SAVE_PATH)

	var battle_events: Array = []
	var battle_starts: Array[String] = []
	session.battle_started.connect(func(node_id: String) -> void: battle_starts.append(node_id))
	session.battle_ended.connect(func(node_id: String, captured: bool) -> void: battle_events.append([node_id, captured]))

	var main := load("res://scenes/main.tscn").instantiate() as Control
	root.add_child(main)
	await _settle()
	var continue_button := _find_button_by_text(main, "继续游戏")
	_assert_true(continue_button != null and not continue_button.disabled, "production title must expose Continue for the natural-force generation")
	if continue_button == null or continue_button.disabled:
		main.queue_free()
		await _finish()
		return
	await _click(continue_button)
	var shell := _find_shell(main)
	_assert_true(shell != null, "Continue must enter the production game shell")
	if shell == null:
		main.queue_free()
		await _finish()
		return

	var one_x := _find_button_by_text(shell, "1×")
	var map_button := _find_button_by_text(shell, "区域图")
	_assert_true(one_x != null and map_button != null, "production shell must expose 1x speed and the region map")
	if one_x == null or map_button == null:
		main.queue_free()
		await _finish()
		return
	await _click(one_x)
	_assert_equal(int(session.state.speed), 1, "real 1x control must install the human-observation speed")
	await _click(map_button)

	var target: Dictionary = _first_observed_resource_node()
	_assert_true(not target.is_empty(), "natural first loop must expose a resource node adjacent to the hive")
	if target.is_empty():
		main.queue_free()
		await _finish()
		return
	var node_button := _find_button_by_prefix(shell, "%s  " % target.id)
	_assert_true(node_button != null, "production map must expose the selected resource node")
	if node_button == null:
		main.queue_free()
		await _finish()
		return
	await _click(node_button)
	var attack_button := _find_button_by_text(shell, "提交全部可参战虫群")
	_assert_true(attack_button != null and not attack_button.disabled, "natural force must enable the production assault command")
	if attack_button == null or attack_button.disabled:
		main.queue_free()
		await _finish()
		return

	var force_before := {
		"biter": int(session.state.units.biter),
		"spore": int(session.state.units.root_spore),
		"root_mat": int(session.state.units.root_mat),
	}
	session.set_process(true)
	var observation_started := Time.get_ticks_msec()
	await _click(attack_button)
	_assert_equal(battle_starts, [String(target.id)], "real assault input must emit exactly one production battle start")
	_assert_true(not session.state.active_battle.is_empty(), "real assault input must install an active battle")
	if session.state.active_battle.is_empty():
		main.queue_free()
		await _finish()
		return
	var initial_enemy := int(session.state.active_battle.enemy)
	var retreat_button := shell.find_child("RetreatButton", true, false) as Button
	var confirmation := shell.find_child("RetreatConfirmation", true, false) as Control
	var cancel_button := shell.find_child("CancelRetreatButton", true, false) as Button
	var confirm_button := shell.find_child("ConfirmRetreatButton", true, false) as Button
	_assert_true(retreat_button != null and confirmation != null and cancel_button != null and confirm_button != null, "production battle page must expose the complete retreat decision UI")
	if retreat_button == null or confirmation == null or cancel_button == null or confirm_button == null:
		main.queue_free()
		await _finish()
		return

	await _wait_until_msec(observation_started + HUMAN_OBSERVATION_MSEC)
	var observed_msec := Time.get_ticks_msec() - observation_started
	_assert_true(not session.state.active_battle.is_empty(), "1x natural-force battle must remain active after a normal 10.5 second observation delay")
	if session.state.active_battle.is_empty():
		failures.append("retreat command became unreachable before the delayed pointer action (elapsed_msec=%d initial_enemy=%d)" % [observed_msec, initial_enemy])
		main.queue_free()
		await _finish()
		return
	_assert_true(int(session.state.active_battle.enemy) < initial_enemy, "the observation window must show real combat progress rather than pause the assault")
	_assert_true(retreat_button.is_visible_in_tree() and not retreat_button.disabled, "retreat must remain reachable after observing the live battle")

	await _click(retreat_button)
	_assert_true(confirmation.visible, "delayed real input must open the production retreat confirmation")
	var frozen_tick := int(session.state.tick)
	var frozen_battle := JSON.stringify(session.state.active_battle)
	var review_started := Time.get_ticks_msec()
	await _wait_until_msec(review_started + CONFIRMATION_REVIEW_MSEC)
	_assert_equal(int(session.state.tick), frozen_tick, "retreat confirmation must freeze the real scheduler during review")
	_assert_equal(JSON.stringify(session.state.active_battle), frozen_battle, "retreat confirmation must freeze every combat fact during review")

	await _click(cancel_button)
	_assert_true(not confirmation.visible, "cancel must close the confirmation and return to the battle")
	await _wait_for_tick_after(frozen_tick, 60)
	_assert_true(int(session.state.tick) > frozen_tick, "cancel must resume real frame scheduling")
	_assert_true(not session.state.active_battle.is_empty(), "cancelled retreat must leave enough battle window for another decision")
	if session.state.active_battle.is_empty():
		failures.append("battle resolved immediately after cancelling the decision")
		main.queue_free()
		await _finish()
		return

	await _click(retreat_button)
	_assert_true(confirmation.visible, "retreat confirmation must reopen after cancellation")
	var committed_battle: Dictionary = session.state.active_battle.duplicate(true)
	var retreats_before := int(session.state.stats.retreats)
	var retreat_tick := int(session.state.tick)
	await _click(confirm_button)
	_assert_true(session.state.active_battle.is_empty(), "confirming retreat must clear the active battle through production rules")
	_assert_equal(int(session.state.stats.retreats), retreats_before + 1, "confirming retreat must record one retreat generation")
	_assert_equal(int(session.state.units.biter), int(committed_battle.biter), "retreat must return every surviving mobile biter exactly once")
	_assert_equal(int(session.state.units.root_spore), int(committed_battle.spore), "retreat must return every still-mobile spore exactly once")
	_assert_equal(int(session.state.units.root_mat), force_before.root_mat + int(committed_battle.roots), "retreat must retain rooted spores as fixed mat rather than remobilize them")
	_assert_equal(battle_events, [[String(target.id), false]], "confirmed retreat must emit one non-capture battle result")
	var retreated_node: Dictionary = session.node_by_id(target.id)
	var expected_enemy := mini(int(retreated_node.enemy_max), int(committed_battle.enemy) + maxi(1, int(ceil(float(retreated_node.enemy_max) * 0.15))))
	_assert_equal(int(retreated_node.enemy), expected_enemy, "retreat must apply the real enemy recovery rule")
	_assert_equal(int(retreated_node.structure_hp), int(committed_battle.structure_hp), "retreat must preserve real structure damage")

	var retreat_primary := FileAccess.get_file_as_bytes(session.DEFAULT_SAVE_PATH)
	var retreat_backup := FileAccess.get_file_as_bytes(session.DEFAULT_SAVE_PATH + session.BACKUP_SUFFIX)
	var retreat_disk := _read_slot(session.DEFAULT_SAVE_PATH)
	_assert_true(retreat_primary != baseline_primary, "retreat must commit a new primary generation")
	_assert_equal(retreat_backup, baseline_primary, "retreat must preserve the pre-battle generation as the committed backup")
	_assert_true(retreat_disk.active_battle is Dictionary and retreat_disk.active_battle.is_empty(), "retreat primary must contain no active battle")
	_assert_equal(int(retreat_disk.tick), retreat_tick, "retreat primary tick must match the visible decision boundary")
	_assert_equal(int(retreat_disk.stats.retreats), retreats_before + 1, "retreat primary must persist the visible retreat count")

	await _click(map_button)
	node_button = _find_button_by_prefix(shell, "%s  " % target.id)
	_assert_true(node_button != null, "retreated node must remain reachable on the production map")
	if node_button == null:
		main.queue_free()
		await _finish()
		return
	await _click(node_button)
	attack_button = _find_button_by_text(shell, "提交全部可参战虫群")
	_assert_true(attack_button != null and not attack_button.disabled, "returned mobile survivors must support real re-entry")
	if attack_button == null or attack_button.disabled:
		main.queue_free()
		await _finish()
		return
	await _click(attack_button)
	_assert_true(not session.state.active_battle.is_empty(), "re-entry must install a second active battle")
	var four_x := _find_button_by_text(shell, "4×")
	_assert_true(four_x != null, "production shell must expose fast-forward after the 1x decision test")
	if four_x != null:
		await _click(four_x)
	var reentry_started := Time.get_ticks_msec()
	while not session.state.active_battle.is_empty() and Time.get_ticks_msec() - reentry_started < REENTRY_DEADLINE_MSEC:
		await process_frame
	_assert_true(session.state.active_battle.is_empty(), "real re-entry battle must converge within its bounded deadline")
	_assert_true(bool(session.node_by_id(target.id).owned), "real re-entry must capture the retreated node")
	_assert_equal(battle_starts, [String(target.id), String(target.id)], "re-entry must emit the second production battle start")
	_assert_equal(battle_events, [[String(target.id), false], [String(target.id), true]], "re-entry must finish with one real capture result")

	var captured_primary := FileAccess.get_file_as_bytes(session.DEFAULT_SAVE_PATH)
	var captured_backup := FileAccess.get_file_as_bytes(session.DEFAULT_SAVE_PATH + session.BACKUP_SUFFIX)
	var captured_disk := _read_slot(session.DEFAULT_SAVE_PATH)
	var backup_disk := _read_slot(session.DEFAULT_SAVE_PATH + session.BACKUP_SUFFIX)
	_assert_true(captured_primary != retreat_primary, "capture must commit a generation after the retreat generation")
	_assert_equal(captured_backup, retreat_primary, "capture must retain the exact retreat generation as backup")
	_assert_true(int(captured_disk.tick) > int(retreat_disk.tick), "capture primary must advance beyond the retreat generation")
	_assert_true(bool(_node_from_slot(captured_disk, target.id).owned), "capture primary must persist node ownership")
	_assert_true(not bool(_node_from_slot(backup_disk, target.id).owned), "capture backup must preserve the retreated re-entry state")
	_assert_equal(int(backup_disk.stats.retreats), retreats_before + 1, "capture backup must preserve the retreat count")
	_assert_true(int(baseline_disk.tick) < int(retreat_disk.tick), "natural-force baseline must precede the retreat generation")
	_assert_no_save_transients()

	session.set_process(false)
	main.queue_free()
	await _finish(observed_msec)

func _naturally_form_first_force() -> void:
	session.new_game(NATURAL_FORCE_SEED)
	_assert_true(session.build_room(0, "thermal_metabolism"), "first loop must build production power through the public rule")
	_assert_true(session.build_room(1, "biomass_filter"), "first loop must build biomass delivery through the public rule")
	_assert_true(session.build_room(4, "embryo_hatchery"), "first loop must build the public hatchery")
	var steps := 0
	while steps < 260 and (int(session.state.units.worker) < int(session.state.targets.worker) or int(session.state.units.biter) < int(session.state.targets.biter) or int(session.state.units.root_spore) < int(session.state.targets.root_spore)):
		session.advance_steps(1)
		steps += 1
	_assert_equal(int(session.state.units.worker), int(session.state.targets.worker), "public production must naturally form the first worker target")
	_assert_equal(int(session.state.units.biter), int(session.state.targets.biter), "public production must naturally form the first biter target")
	_assert_equal(int(session.state.units.root_spore), int(session.state.targets.root_spore), "public production must naturally form the first root-spore target")
	_assert_equal(int(session.state.units.biter), 18, "first-loop design target must remain 18 biters")
	_assert_equal(int(session.state.units.root_spore), 6, "first-loop design target must remain 6 spores")

func _first_observed_resource_node() -> Dictionary:
	for node in session.state.nodes:
		if bool(node.observed) and not bool(node.owned) and String(node.role) == "资源":
			return node
	return {}

func _find_shell(main: Control) -> Control:
	for node in main.find_children("*", "Control", true, false):
		if node.has_method("_show_page") and node.has_method("_update_battle_strip"):
			return node as Control
	return null

func _find_button_by_text(node: Node, text: String) -> Button:
	if node is Button and String((node as Button).text) == text:
		return node as Button
	for child in node.get_children():
		var found := _find_button_by_text(child, text)
		if found != null:
			return found
	return null

func _find_button_by_prefix(node: Node, prefix: String) -> Button:
	if node is Button and String((node as Button).text).begins_with(prefix):
		return node as Button
	for child in node.get_children():
		var found := _find_button_by_prefix(child, prefix)
		if found != null:
			return found
	return null

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

func _wait_until_msec(deadline: int) -> void:
	while Time.get_ticks_msec() < deadline:
		await process_frame

func _wait_for_tick_after(tick: int, max_frames: int) -> void:
	for index in range(max_frames):
		if int(session.state.tick) > tick:
			return
		await process_frame

func _settle() -> void:
	for index in range(5):
		await process_frame

func _read_slot(path: String) -> Dictionary:
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK or not parser.data is Dictionary:
		return {}
	return parser.data

func _node_from_slot(slot: Dictionary, node_id: String) -> Dictionary:
	for node in slot.get("nodes", []):
		if String(node.get("id", "")) == node_id:
			return node
	return {}

func _assert_no_save_transients() -> void:
	for suffix in [session.SAVE_TEMP_SUFFIX, session.BACKUP_TEMP_SUFFIX, session.BACKUP_PREVIOUS_SUFFIX, session.ROLLBACK_SUFFIX, session.RECOVERY_SUFFIX, session.BACKUP_SUFFIX + session.RECOVERY_SUFFIX]:
		_assert_false(FileAccess.file_exists(session.DEFAULT_SAVE_PATH + suffix), "completed retreat flow must clean transient %s" % suffix)

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

func _finish(observed_msec: int = 0) -> void:
	session.set_process(false)
	_cleanup_slots()
	await process_frame
	if failures.is_empty():
		print("RETREAT_WINDOW_OK assertions=%d observation_msec=%d natural_force=18+6 modal=freeze cancel=resume retreat=committed reentry=captured generations=exact" % [assertions, observed_msec])
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("RETREAT_WINDOW_FAILED assertions=%d failures=%d observation_msec=%d" % [assertions, failures.size(), observed_msec])
		quit(1)

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
