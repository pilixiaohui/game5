extends SceneTree

const TARGETS := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]
const FLOW_DEADLINE_MSEC := 9000

var session: Node
var main: Control
var capture_root := ""
var failures: Array[String] = []
var assertions := 0
var captures := 0
var save_notice_message := ""
var save_notice_authority: Dictionary = {}
var baseline_state_connections := 0
var baseline_battle_connections := 0
var run_started_msec := 0

func _initialize() -> void:
	root.size = TARGETS[0]
	call_deferred("_run")

func _run() -> void:
	run_started_msec = Time.get_ticks_msec()
	_phase_marker("startup", "start")
	session = root.get_node("GameSession")
	capture_root = _argument("--capture-root=").simplify_path()
	_assert_true(not capture_root.is_empty(), "fresh UI runner requires an owned capture root")
	if capture_root.is_empty():
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(capture_root))
	baseline_state_connections = _signal_connection_count("state_changed")
	baseline_battle_connections = _signal_connection_count("battle_ended")
	_assert_true(session.snapshot().is_empty(), "isolated startup must begin without authority state")
	_assert_true(not session.has_save(), "isolated startup must begin without a primary, rollback, or backup save")
	session.notice_posted.connect(_on_notice_posted)

	main = load("res://scenes/main.tscn").instantiate() as Control
	root.add_child(main)
	await _settle()
	_phase_marker("startup", "end")
	var new_game := _find_button_by_name(main, "NewGameButton")
	_assert_true(new_game != null and new_game.is_visible_in_tree(), "title must expose the production New Game button")
	await _click(new_game)

	var shell := _find_shell()
	_assert_true(shell != null, "New Game must enter the production GameShell")
	if shell == null:
		await _finish()
		return
	var presenter := shell.find_child("M1WorldPresenter", true, false) as Control
	_assert_true(presenter != null and bool(presenter.call("is_available")), "fresh hive must mount the Node2D M1 presenter")
	var hud := presenter.find_child("M1HiveHud", true, false) as Control if presenter != null else null
	_assert_true(hud != null and hud.is_visible_in_tree(), "fresh hive must expose the native M1 Control HUD")
	if hud == null:
		await _finish()
		return

	var initial: Dictionary = session.snapshot()
	_assert_equal(initial.rooms.size(), 12, "New Game must create exactly twelve authoritative room slots")
	_assert_true(initial.active_battle.is_empty(), "New Game must not preseed a battle")
	_assert_equal(int(initial.units.biter), 0, "New Game must not preseed combat units")
	_assert_equal(_authority_hash(_read_slot(session.DEFAULT_SAVE_PATH)), _authority_hash(initial), "New Game button must persist the initial authority generation")
	var build_capture_started := Time.get_ticks_msec()
	_phase_marker("build-capture", "start")
	await _capture_layout_phase("build", presenter, hud)
	_phase_marker("build-capture", "end", "elapsed_ms=%d captures=%d" % [Time.get_ticks_msec() - build_capture_started, captures])

	var speed_four := _find_button_by_text(shell, "4×")
	await _click(speed_four)
	_assert_equal(int(session.snapshot().speed), 4, "production speed button must select the real 4x scheduler")
	await _select_slot_and_build(hud, 0, "thermal_metabolism")
	await _select_slot_and_build(hud, 1, "biomass_filter")
	await _select_slot_and_build(hud, 4, "embryo_hatchery")

	var build_deadline := Time.get_ticks_msec() + FLOW_DEADLINE_MSEC
	while not _rooms_complete([0, 1, 4]) and Time.get_ticks_msec() < build_deadline:
		await process_frame
	_assert_true(_rooms_complete([0, 1, 4]), "real scheduler must complete the three publicly requested starting rooms")

	await _click(_find_button_by_name(hud, "M1RoomSlot_05"))
	await _click(_find_button_by_name(hud, "M1Target_MinimalFormation"))
	var reduced: Dictionary = session.snapshot()
	_assert_equal(int(reduced.targets.worker), 0, "public hatchery controls must reduce the worker target")
	_assert_equal(int(reduced.targets.biter), 1, "public hatchery controls must select a minimal biter target")
	_assert_equal(int(reduced.targets.root_spore), 0, "public hatchery controls must reduce the spore target")

	var unit_deadline := Time.get_ticks_msec() + FLOW_DEADLINE_MSEC
	while int(session.snapshot().units.biter) <= 0 and Time.get_ticks_msec() < unit_deadline:
		await process_frame
	_assert_true(int(session.snapshot().units.biter) > 0, "real hatchery rules must form a combat-capable unit from public target controls")
	await _verify_layout_phase("production", presenter, hud)
	_phase_marker("first-production", "instant", "rooms=3 biter=%d" % int(session.snapshot().units.biter))

	var map_button := _find_button_by_text(shell, "区域图")
	await _click(map_button)
	_assert_equal(String(shell.get("current_page")), "map", "production navigation must leave the M1 hive for the region map")
	var node_button := _find_button_by_prefix(shell, "B  ")
	await _click(node_button)
	var attack_button := _find_button_by_text(shell, "提交全部可参战虫群")
	_assert_true(attack_button != null and not attack_button.disabled, "selected observed node must expose an enabled public assault button")
	await _click(attack_button)
	var battle: Dictionary = session.snapshot().active_battle
	_assert_true(not battle.is_empty() and String(battle.get("node_id", "")) == "B", "public map assault must install the real B-node battle")
	_assert_equal(String(shell.get("current_page")), "battle", "successful public assault must enter the production battle page")
	var battle_presenter := shell.find_child("M1WorldPresenter", true, false) as Control
	_assert_true(battle_presenter != null and bool(battle_presenter.call("is_available")), "fresh assault must mount the M1 battle presenter")
	var battle_contract: Dictionary = battle_presenter.call("world_contract_snapshot") if battle_presenter != null else {}
	_assert_equal(String(battle_contract.get("phase", "")), "engagement", "M1 battle world must consume the authoritative active battle")

	await _click(_find_button_by_text(shell, "1×"))
	var before_save: Dictionary = session.snapshot()
	save_notice_message = ""
	save_notice_authority = {}
	await _click(_find_button_by_text(shell, "保存"))
	var after_save: Dictionary = session.snapshot()
	_assert_true(not save_notice_authority.is_empty(), "production Save button must expose the exact committed authority generation")
	_assert_true(int(after_save.tick) >= int(before_save.tick), "real scheduler may only move forward across the save observation window")
	var primary := _read_slot(session.DEFAULT_SAVE_PATH)
	_assert_equal(_authority_hash(primary), _authority_hash(save_notice_authority), "primary save must match the authority captured by production save feedback")
	_assert_true(FileAccess.file_exists(session.DEFAULT_SAVE_PATH + session.BACKUP_SUFFIX), "battle save must retain a backup generation")
	_assert_true(save_notice_message.contains("保存") or save_notice_message.contains("存档"), "GameShell must expose production save feedback")
	var battle_strip := shell.find_child("BattleStrip", true, false) as Control
	var battle_text := shell.find_child("BattleText", true, false) as Label
	_assert_true(battle_strip != null and battle_strip.is_visible_in_tree(), "active battle UI feedback strip must remain visible")
	_assert_true(battle_text != null and (battle_text.text.contains("敌军") or battle_text.text.contains("腐殖渗口")), "battle feedback must reflect authoritative combat state")

	_phase_marker("exit-ready", "instant", "assertions=%d captures=%d" % [assertions, captures])
	await _finish()

func _capture_layout_phase(phase: String, presenter: Control, hud: Control) -> void:
	for target in TARGETS:
		root.size = target
		await _settle()
		_assert_hud_layout(hud, presenter, target, phase)
		var image := root.get_texture().get_image() if root.get_texture() != null else null
		_assert_true(image != null and not image.is_empty(), "%s %s fresh UI capture must be non-empty" % [phase, target])
		if image == null or image.is_empty():
			continue
		_assert_equal(Vector2i(image.get_width(), image.get_height()), target, "fresh UI capture must retain its requested resolution")
		var colors := {}
		for y in range(0, image.get_height(), 24):
			for x in range(0, image.get_width(), 24):
				colors[image.get_pixel(x, y).to_html(false)] = true
		_assert_true(colors.size() >= 24, "%s %s fresh UI capture must not be blank-like" % [phase, target])
		var path := "%s/m1-fresh-%s-%dx%d.png" % [capture_root, phase, target.x, target.y]
		_assert_true(image.save_png(ProjectSettings.globalize_path(path)) == OK, "fresh UI capture must save under the owned root")
		captures += 1
		print("M1_FRESH_UI_SCREENSHOT_OK phase=%s size=%dx%d sha256=%s authority=%s" % [phase, target.x, target.y, FileAccess.get_sha256(ProjectSettings.globalize_path(path)), _authority_hash(session.snapshot())])

func _verify_layout_phase(phase: String, presenter: Control, hud: Control) -> void:
	for target in TARGETS:
		root.size = target
		await _settle()
		_assert_hud_layout(hud, presenter, target, phase)

func _assert_hud_layout(hud: Control, presenter: Control, target: Vector2i, phase: String) -> void:
	var contract: Dictionary = hud.call("ui_contract_snapshot")
	_assert_equal(int(contract.get("slot_count", -1)), 12, "%s %s HUD must expose all twelve slots" % [phase, target])
	_assert_equal(int(contract.get("visible_slot_count", -1)), 12, "%s %s HUD must keep all twelve slots visible" % [phase, target])
	_assert_equal(int(contract.get("focusable_slot_count", -1)), 12, "%s %s HUD must keep all twelve slots keyboard-focusable" % [phase, target])
	_assert_true(bool(contract.get("detail_visible", false)), "%s %s HUD must keep room details visible" % [phase, target])
	if phase == "build":
		_assert_equal(int(contract.get("build_action_count", -1)), 6, "%s HUD must expose every room blueprint action" % target)
		_assert_true(int(contract.get("enabled_build_action_count", 0)) >= 3, "%s HUD must expose the three starting blueprints" % target)
	else:
		_assert_equal(int(contract.get("target_action_count", -1)), 7, "%s HUD must expose target steppers and the minimal formation action" % target)
	var presenter_rect := presenter.get_global_rect()
	for candidate in hud.find_children("M1RoomSlot_*", "Button", true, false):
		var button := candidate as Button
		var rect := button.get_global_rect()
		_assert_true(rect.size.x >= 72.0 and rect.size.y >= 38.0, "%s %s slot must retain a stable click target" % [phase, target])
		_assert_true(rect.position.x >= presenter_rect.position.x - 1.0 and rect.end.x <= presenter_rect.end.x + 1.0, "%s %s slot must not clip horizontally" % [phase, target])
	var detail_panel := hud.find_child("M1HiveDetailPanel", true, false) as Control
	var action_pattern := "M1Build_*" if phase == "build" else "M1Target_*"
	var enabled_actions := 0
	for candidate in hud.find_children(action_pattern, "Button", true, false):
		var action := candidate as Button
		if action.disabled:
			continue
		enabled_actions += 1
		var action_rect := action.get_global_rect()
		_assert_true(action_rect.size.x >= 34.0 and action_rect.size.y >= 32.0, "%s %s action must retain a stable click target" % [phase, target])
		_assert_true(detail_panel.get_global_rect().encloses(action_rect), "%s %s enabled action must remain fully visible in the detail panel" % [phase, target])
	_assert_true(enabled_actions >= 3, "%s %s must retain at least three enabled production actions" % [phase, target])
	var focus_probe := _find_button_by_name(hud, "M1RoomSlot_01")
	focus_probe.grab_focus()
	_assert_true(focus_probe.has_focus(), "%s %s slot must accept keyboard focus" % [phase, target])

func _select_slot_and_build(hud: Control, slot: int, kind: String) -> void:
	await _click(_find_button_by_name(hud, "M1RoomSlot_%02d" % (slot + 1)))
	var build_button := _find_button_by_name(hud, "M1Build_%s" % kind)
	_assert_true(build_button != null and not build_button.disabled, "selected slot must expose enabled %s construction" % kind)
	await _click(build_button)
	var room: Dictionary = session.snapshot().rooms[slot]
	_assert_equal(String(room.get("kind", "")), kind, "public build button must commit %s to slot %d" % [kind, slot + 1])
	_assert_equal(String(room.get("state", "")), "building", "public build button must start real construction")

func _rooms_complete(slots: Array) -> bool:
	var snapshot: Dictionary = session.snapshot()
	for slot in slots:
		if String(snapshot.rooms[int(slot)].state) != "complete":
			return false
	return true

func _finish() -> void:
	var teardown_started := Time.get_ticks_msec()
	_phase_marker("teardown", "start")
	if is_instance_valid(main):
		main.queue_free()
		await process_frame
		await process_frame
	_assert_equal(_signal_connection_count("state_changed"), baseline_state_connections, "fresh UI teardown must release state listeners")
	_assert_equal(_signal_connection_count("battle_ended"), baseline_battle_connections, "fresh UI teardown must release battle listeners")
	if session.notice_posted.is_connected(_on_notice_posted):
		session.notice_posted.disconnect(_on_notice_posted)
	_phase_marker("teardown", "end", "elapsed_ms=%d" % (Time.get_ticks_msec() - teardown_started))
	if failures.is_empty():
		print("M1_FRESH_UI_OK assertions=%d captures=%d path=new-game,slot,build,production,map,assault,battle,save authority=%s" % [assertions, captures, _authority_hash(session.snapshot())])
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("M1_FRESH_UI_FAILED assertions=%d failures=%d captures=%d" % [assertions, failures.size(), captures])
		quit(1)

func _find_shell() -> Control:
	var expected := load("res://scripts/ui/game_shell.gd")
	for node in root.find_children("*", "Control", true, false):
		if node.get_script() == expected:
			return node as Control
	return null

func _find_button_by_name(node: Node, button_name: String) -> Button:
	return node.find_child(button_name, true, false) as Button if node != null else null

func _find_button_by_text(node: Node, text: String) -> Button:
	if node == null:
		return null
	for child in node.find_children("*", "Button", true, false):
		var button := child as Button
		if button != null and button.text == text:
			return button
	return null

func _find_button_by_prefix(node: Node, prefix: String) -> Button:
	if node == null:
		return null
	for child in node.find_children("*", "Button", true, false):
		var button := child as Button
		if button != null and button.text.begins_with(prefix):
			return button
	return null

func _click(button: Button) -> void:
	_assert_true(button != null, "required production button must exist")
	if button == null:
		return
	_assert_true(button.is_visible_in_tree() and not button.disabled, "%s must be visible and enabled" % button.name)
	if not button.is_visible_in_tree() or button.disabled:
		return
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

func _settle() -> void:
	for index in range(3):
		await process_frame
	await RenderingServer.frame_post_draw

func _read_slot(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK or not parser.data is Dictionary:
		return {}
	return parser.data

func _authority_hash(value: Dictionary) -> String:
	var authority := value.duplicate(true)
	authority.erase("ledger")
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(JSON.stringify(_canonical_json(authority), "", true).to_utf8_buffer())
	return context.finish().hex_encode()

func _canonical_json(value: Variant) -> Variant:
	if value is float and float(value) == floor(float(value)):
		return int(value)
	if value is Array:
		var result: Array = []
		for item in value:
			result.append(_canonical_json(item))
		return result
	if value is Dictionary:
		var result := {}
		for key in value.keys():
			result[String(key)] = _canonical_json(value[key])
		return result
	return value

func _signal_connection_count(signal_name: String) -> int:
	return session.get_signal_connection_list(signal_name).size()

func _on_notice_posted(message: String, _level: String) -> void:
	if message.contains("保存") or message.contains("存档"):
		save_notice_message = message
		save_notice_authority = session.snapshot()

func _argument(prefix: String) -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with(prefix):
			return argument.trim_prefix(prefix)
	return ""

func _phase_marker(phase: String, edge: String, detail: String = "") -> void:
	var total := Time.get_ticks_msec() - run_started_msec if run_started_msec > 0 else 0
	var suffix := "" if detail.is_empty() else " " + detail
	print("M1_FRESH_UI_PHASE phase=%s edge=%s total_ms=%d%s" % [phase, edge, total, suffix])

func _assert_true(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures.append(message)

func _assert_equal(actual: Variant, expected: Variant, message: String) -> void:
	assertions += 1
	if actual != expected:
		failures.append("%s (expected=%s actual=%s)" % [message, str(expected), str(actual)])
