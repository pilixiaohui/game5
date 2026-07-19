extends SceneTree

const TARGETS := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]
const HivePage = preload("res://scripts/ui/hive_page.gd")
const BattlePage = preload("res://scripts/ui/battle_page.gd")
const ERROR_CONTROL_SCENE_PATH := "res://tests/m1_error_control_fixture.tscn"
const VISUAL_MIN_UNIT_BBOX_PX := 48.0
const VISUAL_MIN_VFX_BBOX_PX := 46.0
const VISUAL_MIN_LOCAL_CONTRAST := 0.04
const VISUAL_LANDMARKS := {
	"operations": ["WorkerLead", "ResourceRoute"],
	"engagement": ["BiterVanguard", "SporeSupport", "EnemyBulwark", "Contact", "Hit", "Hurt"],
	"retreat": ["BiterVanguard", "Death", "Retreat"],
}
const VISUAL_DIRECTIONS := {
	"engagement:BiterVanguard": 1,
	"engagement:EnemyBulwark": -1,
	"retreat:BiterVanguard": -1,
	"retreat:Retreat": -1,
}

var session: Node
var main: Control
var capture_root := ""
var failures: Array[String] = []
var assertions := 0
var hashes: Array[String] = []
var save_notices := 0
var battle_signal_connections := 0
var state_signal_connections := 0
var run_started_msec := 0
var public_result_captures := 0

func _initialize() -> void:
	root.size = Vector2i(1600, 900)
	call_deferred("_run")

func _run() -> void:
	run_started_msec = Time.get_ticks_msec()
	_phase_marker("startup", "start")
	session = root.get_node("GameSession")
	session.set_process(false)
	session.notice_posted.connect(_on_notice_posted)
	capture_root = _argument("--capture-root=").simplify_path()
	_assert_true(not capture_root.is_empty(), "M1 production runner requires an owned capture root")
	if capture_root.is_empty():
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(capture_root))
	_cleanup_slots()
	session.new_game(4127)
	session.state.units.worker = 2
	session.state.units.biter = 80
	session.state.units.root_spore = 2
	_assert_true(session.save_game(), "production-entry fixture must save through GameSession")
	var state_before := _state_hash(session.snapshot())

	main = load("res://scenes/main.tscn").instantiate() as Control
	root.add_child(main)
	await _settle()
	main.call("_show_game")
	await _settle()
	_phase_marker("startup", "end", "main=ready")
	var shell := _find_shell()
	_assert_true(shell != null, "production main must enter GameShell")
	var hive_presenter := shell.find_child("M1WorldPresenter", true, false) as Control if shell != null else null
	_assert_true(hive_presenter != null and bool(hive_presenter.call("is_available")), "hive page must own the M1 world presenter")
	_assert_equal(_m1_presenter_count(shell), 1, "production shell must mount exactly one visible M1 presenter")
	var legacy_detail := shell.find_child("LegacyHiveDetailBand", true, false) as Control
	_assert_true(legacy_detail != null and not legacy_detail.visible, "M1 activation must hide the legacy hive detail band")
	_assert_equal(_state_hash(session.snapshot()), state_before, "presenter mount must not mutate GameSession state")
	var hidden_detail_count := legacy_detail.get_child_count() if legacy_detail != null else -1
	session.set_speed(2)
	await _settle()
	_assert_equal(legacy_detail.get_child_count() if legacy_detail != null else -1, hidden_detail_count, "M1 state updates must not rebuild hidden legacy details")
	var operations_hash := _state_hash(session.snapshot())
	_assert_world_contract(hive_presenter, "operations")
	await _verify_dock_transitions(hive_presenter)
	var operations_started := _phase_begin("operations-capture", 15000)
	await _capture_targets("operations", operations_hash, hive_presenter)
	_phase_end("operations-capture", operations_started, 15000, "captures=3")
	await _verify_legacy_fallback(session.snapshot())

	var map_button := _find_button_by_text(shell, "区域图")
	_assert_true(map_button != null, "production navigation must expose the region map")
	if map_button != null:
		await _click(map_button)
	_assert_equal(String(shell.get("current_page")), "map", "leaving the hive slice must enter the legacy map flow")
	_assert_true(not is_instance_valid(hive_presenter), "leaving the hive page must release its M1 view")
	_assert_equal(_m1_presenter_count(shell), 0, "hidden pages must not retain an M1 presenter")
	var node_button := _find_button_by_prefix(shell, "B  ")
	_assert_true(node_button != null, "production map must expose the observed resource node")
	if node_button != null:
		await _click(node_button)
	# Keep the production battle alive across the 30-second scheduler boundary and
	# make both real damage directions observable without changing combat rules.
	var battle_fixture_node := _mutable_node("B")
	if not battle_fixture_node.is_empty():
		battle_fixture_node.enemy = 80
		battle_fixture_node.enemy_max = 80
		battle_fixture_node.structure_hp = 100
		battle_fixture_node.structure_max = 100
	var attack_button := _find_button_by_text(shell, "提交全部可参战虫群")
	_assert_true(attack_button != null and not attack_button.disabled, "production map must expose the real assault command")
	if attack_button != null and not attack_button.disabled:
		await _click(attack_button)
	_assert_true(not session.state.active_battle.is_empty(), "production assault must install the real active battle")
	var battle_hash := _state_hash(session.snapshot())
	var battle_presenter := shell.find_child("M1WorldPresenter", true, false) as Control if shell != null else null
	_assert_true(battle_presenter != null and bool(battle_presenter.call("is_available")), "battle page must retain the M1 presenter")
	_assert_equal(String(shell.get("current_page")), "battle", "real map assault must explicitly enter the M1 battle page")
	_assert_equal(_m1_presenter_count(shell), 1, "battle entry must mount exactly one M1 presenter")
	_assert_equal(_state_hash(session.snapshot()), battle_hash, "battle presenter must not write GameSession state")
	var battle_authority_hash := _authority_hash(session.snapshot())
	battle_signal_connections = _signal_connection_count("battle_ended")
	state_signal_connections = _signal_connection_count("state_changed")
	var battle_lifecycle_epoch := int(_m1_lifecycle_snapshot(shell).get("epoch", -1))
	_assert_world_contract(battle_presenter, "engagement")
	var engagement_started := _phase_begin("engagement-capture", 15000)
	await _capture_targets("engagement", battle_hash, battle_presenter)
	_phase_end("engagement-capture", engagement_started, 15000, "captures=3")
	await _verify_battle_fallback(session.snapshot())

	var one_x := _find_button_by_text(shell, "1×")
	_assert_true(one_x != null, "battle page must retain the real 1x scheduler control")
	if one_x != null:
		await _click(one_x)
	_assert_equal(int(session.state.speed), 1, "battle autosave fixture must use the real 1x scheduler")
	battle_authority_hash = _authority_hash(session.snapshot())
	var pre_ctrl_s_primary := _file_fingerprint(session.DEFAULT_SAVE_PATH)
	var shortcut_notice_before := save_notices
	await _press_save_shortcut()
	_assert_true(save_notices > shortcut_notice_before, "production Ctrl+S must run after battle M1 presenter mount")
	_assert_equal(_authority_hash(session.snapshot()), battle_authority_hash, "Ctrl+S must preserve the battle authority state")
	var ctrl_s_fingerprint := _committed_slot_fingerprint()
	_assert_true(bool(ctrl_s_fingerprint.primary.exists) and bool(ctrl_s_fingerprint.backup.exists), "Ctrl+S must commit both primary and backup generations")
	_assert_fingerprint_complete(ctrl_s_fingerprint, "Ctrl+S")
	_assert_disk_authority_matches(ctrl_s_fingerprint.primary, battle_authority_hash, "Ctrl+S")
	_assert_equal(ctrl_s_fingerprint.backup.sha256, pre_ctrl_s_primary.sha256, "Ctrl+S backup must retain the previous primary hash")
	_assert_equal(ctrl_s_fingerprint.backup.size, pre_ctrl_s_primary.size, "Ctrl+S backup must retain the previous primary size")

	var autosave_notice_before := save_notices
	var autosave_tick_before := int(session.state.tick)
	var autosave_started := _phase_begin("autosave", 40000)
	session.set_process(true)
	var autosave_deadline := Time.get_ticks_msec() + 40000
	while save_notices == autosave_notice_before and Time.get_ticks_msec() < autosave_deadline:
		await process_frame
		if save_notices > autosave_notice_before:
			session.set_process(false)
	session.set_process(false)
	_assert_true(save_notices > autosave_notice_before, "real 30-second scheduler must autosave after battle M1 presenter mount")
	_assert_true(int(session.state.tick) >= autosave_tick_before + 30, "autosave coverage must cross the real 30-second scheduler boundary after assault")
	var hive_hash := _state_hash(session.snapshot())
	var autosave_fingerprint := _committed_slot_fingerprint()
	_assert_fingerprint_complete(autosave_fingerprint, "autosave")
	_assert_disk_authority_matches(autosave_fingerprint.primary, _authority_hash(session.snapshot()), "autosave")
	_assert_equal(autosave_fingerprint.backup.sha256, ctrl_s_fingerprint.primary.sha256, "autosave backup must retain the Ctrl+S primary hash")
	_assert_equal(autosave_fingerprint.backup.size, ctrl_s_fingerprint.primary.size, "autosave backup must retain the Ctrl+S primary size")
	_phase_end("autosave", autosave_started, 40000, "tick_delta=%d notices=%d primary_sha=%s backup_sha=%s primary_size=%d backup_size=%d" % [int(session.state.tick) - autosave_tick_before, save_notices - autosave_notice_before, String(autosave_fingerprint.primary.sha256), String(autosave_fingerprint.backup.sha256), int(autosave_fingerprint.primary.size), int(autosave_fingerprint.backup.size)])
	battle_authority_hash = _authority_hash(session.snapshot())
	await create_timer(1.3).timeout
	var settled_world: Dictionary = battle_presenter.call("world_contract_snapshot") if is_instance_valid(battle_presenter) else {}
	_contract_equal(int(settled_world.get("transient_vfx", -1)), 0, "bounded battle feedback must release transient VFX after scheduler stop")
	_contract_equal(int(settled_world.get("active_tweens", -1)), 0, "bounded battle feedback must leave no active Tween after scheduler stop")
	var live_presentation: Dictionary = battle_presenter.call("presentation_contract_snapshot") if is_instance_valid(battle_presenter) else {}
	var live_kinds: Array = live_presentation.get("kinds", [])
	_contract_true(live_kinds.has("contact"), "public assault must present contact from the authoritative battle start")
	_contract_true(live_kinds.has("hit"), "real enemy/structure deltas must present hit feedback")
	_contract_true(live_kinds.has("hurt"), "real loss deltas must present hurt feedback")
	_contract_true(bool(live_presentation.get("monotonic", false)), "authority presentation events must retain monotonic display order")
	_contract_equal(String(live_presentation.get("source", "")), "readonly-authority-snapshot-ledger", "battle presentation must identify its read-only authority source")

	var save_notice_before := save_notices
	var battle_save := _find_button_by_text(shell, "保存")
	_assert_true(battle_save != null, "GameShell must retain its production save command")
	if battle_save != null:
		await _click(battle_save)
	_assert_true(save_notices > save_notice_before, "production save button must commit through GameSession")
	_assert_equal(_authority_hash(session.snapshot()), _authority_hash(_read_slot(session.DEFAULT_SAVE_PATH)), "battle save must persist the authoritative state")
	_assert_true(FileAccess.file_exists(session.DEFAULT_SAVE_PATH + session.BACKUP_SUFFIX), "battle save must preserve the production backup generation")
	var battle_fingerprint := _committed_slot_fingerprint()
	_assert_fingerprint_complete(battle_fingerprint, "battle save")
	_assert_equal(battle_fingerprint.backup.sha256, autosave_fingerprint.primary.sha256, "battle save backup must retain the autosave primary hash")
	_assert_equal(battle_fingerprint.backup.size, autosave_fingerprint.primary.size, "battle save backup must retain the autosave primary size")
	var battle_primary := FileAccess.get_file_as_bytes(session.DEFAULT_SAVE_PATH)
	var battle_backup := FileAccess.get_file_as_bytes(session.DEFAULT_SAVE_PATH + session.BACKUP_SUFFIX)
	session.state.resources.biomass = float(session.state.resources.biomass) + 91.0
	_assert_true(_state_hash(session.snapshot()) != battle_hash, "reload fixture must install an in-memory sentinel only")
	_assert_true(session.load_game(), "production reload must accept the battle save")
	await _settle()
	_assert_equal(_authority_hash(session.snapshot()), _authority_hash(_read_slot(session.DEFAULT_SAVE_PATH)), "reload must install the disk primary authority state")
	_assert_equal(_authority_hash(session.snapshot()), battle_authority_hash, "reload must restore the disk-authoritative battle state")
	_assert_equal(_file_fingerprint(session.DEFAULT_SAVE_PATH), battle_fingerprint.primary, "reload must preserve the battle primary sha/size/mtime")
	_assert_equal(_file_fingerprint(session.DEFAULT_SAVE_PATH + session.BACKUP_SUFFIX), battle_fingerprint.backup, "reload must preserve the battle backup sha/size/mtime")
	_assert_equal(FileAccess.get_file_as_bytes(session.DEFAULT_SAVE_PATH), battle_primary, "reload must not rewrite the saved primary")
	_assert_equal(FileAccess.get_file_as_bytes(session.DEFAULT_SAVE_PATH + session.BACKUP_SUFFIX), battle_backup, "reload must not rewrite the saved backup")

	var retreat_started := _phase_begin("retreat", 15000)
	var retreat_button := shell.find_child("RetreatButton", true, false) as Button if shell != null else null
	_assert_true(retreat_button != null and not retreat_button.disabled, "M1 battle presentation must retain production retreat control")
	if retreat_button != null and not retreat_button.disabled:
		await _click(retreat_button)
	_assert_world_contract(battle_presenter, "retreat")
	var retreat_capture_started := _phase_begin("retreat-capture", 15000)
	await _capture_contract_targets("retreat", _state_hash(session.snapshot()), battle_presenter)
	_phase_end("retreat-capture", retreat_capture_started, 15000, "captures=3")
	_phase_marker("screenshots-complete", "instant", "captures=%d" % hashes.size())
	var confirm_button := shell.find_child("ConfirmRetreatButton", true, false) as Button if shell != null else null
	_assert_true(confirm_button != null, "production retreat confirmation must remain reachable")
	if confirm_button != null:
		await _click(confirm_button)
	_assert_true(session.state.active_battle.is_empty(), "confirmed retreat must exit the M1 battle flow through production rules")
	_contract_equal(String(shell.get("current_page")), "battle", "retreat result must remain on the M1 battle page until player confirmation")
	var retreat_result: Dictionary = _battle_result_snapshot(shell)
	_contract_true(bool(retreat_result.get("visible", false)), "retreat must expose a persistent production result summary")
	var retreat_summary: Dictionary = retreat_result.get("summary", {})
	_contract_equal(String(retreat_summary.get("outcome", "")), "retreated", "retreat summary must derive its outcome from the real rule result")
	_contract_equal(String(retreat_summary.get("rule_event", "")), "battle_retreated", "retreat summary must cite the authoritative ledger event")
	_contract_true(String(retreat_summary.get("deployed", "")).contains("噬咬体"), "retreat summary must report deployed units")
	_contract_true(String(retreat_summary.get("returned", "")).contains("菌毯"), "retreat summary must report returned and fixed units")
	_contract_true(String(retreat_summary.get("losses", "")).is_valid_int(), "retreat summary must report losses")
	var retreat_presentation: Dictionary = battle_presenter.call("presentation_contract_snapshot") if is_instance_valid(battle_presenter) else {}
	_contract_true((retreat_presentation.get("kinds", []) as Array).has("retreat"), "retreat settlement must enqueue retreat feedback from the rule result")
	var retreat_result_confirm := shell.find_child("ConfirmBattleResultButton", true, false) as Button
	_contract_true(retreat_result_confirm != null and not retreat_result_confirm.disabled, "long-running retreat must expose result confirmation immediately after its observation window")
	if retreat_result_confirm != null and not retreat_result_confirm.disabled:
		await _click(retreat_result_confirm)
	_assert_equal(String(shell.get("current_page")), "map", "confirmed result summary must return to the legacy map flow")
	_assert_true(not is_instance_valid(battle_presenter), "confirmed result exit must release the M1 view and its animation lifecycle")
	_assert_equal(_m1_presenter_count(shell), 0, "confirmed result exit must leave no hidden M1 presenter")
	var after_retreat_hash := _state_hash(session.snapshot())
	var retreat_authority_hash := _authority_hash(session.snapshot())
	_assert_true(after_retreat_hash != battle_hash, "confirmed retreat must produce a new authoritative state hash")
	_assert_true(FileAccess.file_exists(session.DEFAULT_SAVE_PATH), "retreat flow must leave a production primary save")
	_assert_true(FileAccess.file_exists(session.DEFAULT_SAVE_PATH + session.BACKUP_SUFFIX), "retreat flow must leave a production backup save")
	var retreat_fingerprint := _committed_slot_fingerprint()
	_assert_fingerprint_complete(retreat_fingerprint, "retreat")
	_assert_equal(retreat_fingerprint.backup.sha256, battle_fingerprint.primary.sha256, "retreat backup must retain the battle-save primary hash")
	_assert_equal(retreat_fingerprint.backup.size, battle_fingerprint.primary.size, "retreat backup must retain the battle-save primary size")
	var retreat_primary := FileAccess.get_file_as_bytes(session.DEFAULT_SAVE_PATH)
	session.state.resources.energy = float(session.state.resources.energy) + 13.0
	_assert_true(session.load_game(), "post-retreat reload must succeed through production persistence")
	await _settle()
	_assert_equal(_authority_hash(session.snapshot()), retreat_authority_hash, "post-retreat reload must restore the disk-authoritative state")
	_assert_equal(_file_fingerprint(session.DEFAULT_SAVE_PATH), retreat_fingerprint.primary, "post-retreat reload must preserve primary sha/size/mtime")
	_assert_equal(_file_fingerprint(session.DEFAULT_SAVE_PATH + session.BACKUP_SUFFIX), retreat_fingerprint.backup, "post-retreat reload must preserve backup sha/size/mtime")
	_assert_equal(FileAccess.get_file_as_bytes(session.DEFAULT_SAVE_PATH), retreat_primary, "post-retreat reload must preserve the committed primary")
	_phase_end("retreat", retreat_started, 15000, "map=true presenter=0")

	var natural_capture_started := _phase_begin("natural-capture", 15000)
	var reentry_node_button := _find_button_by_prefix(shell, "B  ")
	_assert_true(reentry_node_button != null, "captured production flow must retain the retreated node for re-entry")
	if reentry_node_button != null:
		await _click(reentry_node_button)
	var reentry_attack := _find_button_by_text(shell, "提交全部可参战虫群")
	_assert_true(reentry_attack != null and not reentry_attack.disabled, "captured production flow must expose re-entry assault")
	if reentry_attack != null and not reentry_attack.disabled:
		await _click(reentry_attack)
	var reentry_presenter := shell.find_child("M1WorldPresenter", true, false) as Control
	_assert_true(reentry_presenter != null and bool(reentry_presenter.call("is_available")), "re-entry battle must mount a fresh M1 presenter")
	var four_x := _find_button_by_text(shell, "4×")
	_assert_true(four_x != null, "production shell must expose fast-forward for natural capture")
	if four_x != null:
		await _click(four_x)
	session.set_process(true)
	var capture_deadline := Time.get_ticks_msec() + 12000
	while not session.state.active_battle.is_empty() and Time.get_ticks_msec() < capture_deadline:
		await process_frame
	session.set_process(false)
	_assert_true(session.state.active_battle.is_empty(), "natural re-entry must reach captured=true within its production deadline")
	_assert_true(bool(session.node_by_id("B").owned), "natural captured=true must install node ownership")
	await _settle()
	_contract_equal(String(shell.get("current_page")), "battle", "natural captured=true must retain the M1 result view until confirmation")
	_contract_equal(_m1_presenter_count(shell), 1, "natural capture summary must retain exactly one visible M1 presenter")
	_contract_true(is_instance_valid(reentry_presenter), "natural capture summary must retain the battle presenter node")
	var capture_result: Dictionary = _battle_result_snapshot(shell)
	_contract_true(bool(capture_result.get("visible", false)), "natural capture must expose a persistent production result summary")
	var capture_summary: Dictionary = capture_result.get("summary", {})
	_contract_equal(String(capture_summary.get("outcome", "")), "captured", "capture summary must derive its outcome from the real rule result")
	_contract_equal(String(capture_summary.get("rule_event", "")), "node_captured", "capture summary must cite the authoritative ledger event")
	_contract_true(String(capture_summary.get("resource_reward", "")).contains("外源有机质"), "capture summary must report real resource rewards")
	_contract_true(String(capture_summary.get("capture_benefit", "")).contains("纳入虫巢网络"), "capture summary must report node ownership benefit")
	_contract_true(String(capture_summary.get("next_node_impact", "")).contains("新观察"), "capture summary must report newly observed next-node impact")
	var summary_authority_hash := _authority_hash(session.snapshot())
	await _capture_public_result_targets(summary_authority_hash)
	var result_confirm := shell.find_child("ConfirmBattleResultButton", true, false) as Button
	var result_ready_deadline := Time.get_ticks_msec() + 5000
	while result_confirm != null and result_confirm.disabled and Time.get_ticks_msec() < result_ready_deadline:
		await process_frame
	capture_result = _battle_result_snapshot(shell)
	_contract_true(int(capture_result.get("observation_elapsed_msec", 0)) >= int(capture_result.get("minimum_observation_msec", 4000)), "1x battle presentation must remain observable for at least four seconds")
	_contract_true(result_confirm != null and not result_confirm.disabled, "capture summary confirmation must unlock after the bounded observation window")
	_contract_equal(_authority_hash(session.snapshot()), summary_authority_hash, "presentation-only observation must not delay or rewrite authority state")
	var result_presentation: Dictionary = reentry_presenter.call("presentation_contract_snapshot") if is_instance_valid(reentry_presenter) else {}
	_contract_true((result_presentation.get("kinds", []) as Array).has("death"), "captured settlement must present death feedback from the rule result")
	_contract_true(bool(result_presentation.get("result_active", false)), "M1 presenter must retain the settled result until confirmation")
	if result_confirm != null and not result_confirm.disabled:
		await _click(result_confirm)
	_assert_equal(String(shell.get("current_page")), "map", "natural captured=true must return the production shell to Map after summary confirmation")
	_assert_equal(_m1_presenter_count(shell), 0, "confirmed natural capture must release every M1 presenter")
	_assert_true(not is_instance_valid(reentry_presenter), "confirmed natural capture must free the battle presenter node")
	var battle_page := _shell_page(shell, "battle")
	_assert_true(battle_page != null and not battle_page.visible, "natural capture must leave the Battle page inactive")
	_assert_equal(_m1_presenter_count(battle_page), 0, "natural capture must leave no presenter under the inactive Battle page")
	_assert_equal(_signal_connection_count("battle_ended"), battle_signal_connections, "natural capture must not leak battle-ended signal connections")
	_assert_equal(_signal_connection_count("state_changed"), state_signal_connections, "natural capture must not leak state-changed signal connections")
	var natural_lifecycle := _m1_lifecycle_snapshot(shell)
	_contract_true(natural_lifecycle.has("epoch"), "natural capture must expose the production M1 lifecycle contract")
	_contract_true(int(natural_lifecycle.get("epoch", -1)) > battle_lifecycle_epoch, "natural capture must emit a presenter lifecycle transition")
	_contract_equal(String(natural_lifecycle.get("page", "")), "battle", "natural capture must release the Battle presenter lifecycle")
	_contract_true(not bool(natural_lifecycle.get("mounted", true)), "natural capture must end with the Battle presenter unmounted")
	var captured_fingerprint := _committed_slot_fingerprint()
	_assert_fingerprint_complete(captured_fingerprint, "capture")
	_assert_disk_authority_matches(captured_fingerprint.primary, _authority_hash(session.snapshot()), "capture")
	_assert_equal(captured_fingerprint.backup.sha256, retreat_fingerprint.primary.sha256, "capture backup must retain the retreat primary hash")
	_assert_equal(captured_fingerprint.backup.size, retreat_fingerprint.primary.size, "capture backup must retain the retreat primary size")
	var captured_hash := _state_hash(session.snapshot())
	_phase_end("natural-capture", natural_capture_started, 15000, "captured=true summary=confirmed presenter=0")

	var hive_button := _find_button_by_text(shell, "虫巢")
	_assert_true(hive_button != null, "legacy map flow must retain a route back to the hive slice")
	if hive_button != null:
		await _click(hive_button)
	_assert_equal(String(shell.get("current_page")), "hive", "legacy flow must re-enter the hive slice")
	_assert_equal(_m1_presenter_count(shell), 1, "hive re-entry must mount one fresh M1 presenter")
	_assert_equal(_state_hash(session.snapshot()), captured_hash, "M1 re-entry must remain a read-only projection")
	_assert_equal(hashes.size(), 9, "production evidence must include operations, engagement and retreat at all three resolutions")
	_assert_equal(_unique_hash_count(), 9, "all production screenshots must have distinct bytes")
	_contract_equal(public_result_captures, 3, "public result evidence must include all three production resolutions")
	print("M1_PUBLIC_BATTLE_PRESENTATION_OK observation_ms=4000 events=contact,hit,hurt,death,retreat summary=deployed,returned,losses,reward,capture,next-node captures=3 authority=readonly")
	print("M1_PUBLIC_DOCK_LAYOUT_OK resolutions=1280x720,1600x900,1920x1080 slots=12 input=mouse,keyboard viewport=reallocated rail=78-100 overlap=0")
	_phase_marker("exit-ready", "instant", "assertions=%d failures=%d" % [assertions, failures.size()])

	var teardown_started := _phase_begin("teardown", 5000)
	session.set_process(false)
	if session.notice_posted.is_connected(_on_notice_posted):
		session.notice_posted.disconnect(_on_notice_posted)
	_cleanup_slots()
	main.queue_free()
	await process_frame
	await process_frame
	_contract_true(not is_instance_valid(main), "M1 production teardown must release the main scene before success")
	_phase_end("teardown", teardown_started, 5000, "main=freed scheduler=stopped")
	if failures.is_empty():
		print("M1_PRODUCTION_ENTRY_OK assertions=%d captures=9 phases=operations,engagement,retreat save_order=post-battle-ctrl-s,post-battle-autosave,button,reload,retreat natural_capture=true state_hash_before=%s state_hash_hive=%s state_hash_battle=%s state_hash_after_retreat=%s state_hash_after_capture=%s" % [assertions, state_before, hive_hash, battle_hash, after_retreat_hash, captured_hash])
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("M1_PRODUCTION_ENTRY_FAILED assertions=%d failures=%d" % [assertions, failures.size()])
		quit(1)

func _phase_begin(phase: String, budget_msec: int) -> int:
	var started := Time.get_ticks_msec()
	_phase_marker(phase, "start", "budget_ms=%d" % budget_msec)
	return started

func _phase_end(phase: String, started_msec: int, budget_msec: int, detail: String = "") -> void:
	var elapsed := Time.get_ticks_msec() - started_msec
	_contract_true(elapsed <= budget_msec, "%s phase exceeded its %dms bound (elapsed=%dms)" % [phase, budget_msec, elapsed])
	var suffix := "elapsed_ms=%d budget_ms=%d" % [elapsed, budget_msec]
	if not detail.is_empty():
		suffix += " " + detail
	_phase_marker(phase, "end", suffix)

func _phase_marker(phase: String, edge: String, detail: String = "") -> void:
	var total := Time.get_ticks_msec() - run_started_msec if run_started_msec > 0 else 0
	var suffix := "" if detail.is_empty() else " " + detail
	print("M1_PRODUCTION_PHASE phase=%s edge=%s total_ms=%d%s" % [phase, edge, total, suffix])

func _capture_targets(phase: String, state_hash: String, presenter: Control) -> void:
	for target in TARGETS:
		root.size = target
		await _settle()
		_contract_equal(_state_hash(session.snapshot()), state_hash, "%s %s must project the same authority snapshot" % [phase, target])
		_assert_readable_rail(presenter, target, phase)
		_contract_dock_layout(presenter, target, phase)
		var image := root.get_texture().get_image() if root.get_texture() != null else null
		_assert_true(image != null and not image.is_empty(), "production %s screenshot must be non-empty" % target)
		if image == null or image.is_empty():
			continue
		_assert_equal(Vector2i(image.get_width(), image.get_height()), target, "production screenshot must retain requested resolution")
		var colors := {}
		for y in range(0, image.get_height(), 24):
			for x in range(0, image.get_width(), 24):
				colors[image.get_pixel(x, y).to_html(false)] = true
		_assert_true(colors.size() >= 24, "production %s screenshot must not be blank-like" % target)
		if target == Vector2i(1280, 720):
			_contract_visual_scale(presenter, image, phase)
		var path := "%s/m1-production-%s-%dx%d.png" % [capture_root, phase, target.x, target.y]
		_assert_true(image.save_png(ProjectSettings.globalize_path(path)) == OK, "production screenshot must save to the owned capture root")
		var sha := FileAccess.get_sha256(ProjectSettings.globalize_path(path))
		hashes.append(sha)
		print("M1_PRODUCTION_SCREENSHOT_OK phase=%s size=%dx%d sha256=%s colors=%d state_hash=%s" % [phase, target.x, target.y, sha, colors.size(), state_hash])

func _capture_contract_targets(phase: String, state_hash: String, presenter: Control) -> void:
	for target in TARGETS:
		root.size = target
		await _settle()
		_contract_equal(_state_hash(session.snapshot()), state_hash, "%s %s must project the same authority snapshot" % [phase, target])
		_contract_readable_rail(presenter, target, phase)
		_contract_dock_layout(presenter, target, phase)
		var image := root.get_texture().get_image() if root.get_texture() != null else null
		_contract_true(image != null and not image.is_empty(), "production %s %s screenshot must be non-empty" % [phase, target])
		if image == null or image.is_empty():
			continue
		_contract_equal(Vector2i(image.get_width(), image.get_height()), target, "production %s screenshot must retain requested resolution" % phase)
		var colors := {}
		for y in range(0, image.get_height(), 24):
			for x in range(0, image.get_width(), 24):
				colors[image.get_pixel(x, y).to_html(false)] = true
		_contract_true(colors.size() >= 24, "production %s %s screenshot must not be blank-like" % [phase, target])
		if target == Vector2i(1280, 720):
			_contract_visual_scale(presenter, image, phase)
		var path := "%s/m1-production-%s-%dx%d.png" % [capture_root, phase, target.x, target.y]
		_contract_true(image.save_png(ProjectSettings.globalize_path(path)) == OK, "production %s screenshot must save to the owned capture root" % phase)
		var sha := FileAccess.get_sha256(ProjectSettings.globalize_path(path))
		hashes.append(sha)
		print("M1_PRODUCTION_SCREENSHOT_OK phase=%s size=%dx%d sha256=%s colors=%d state_hash=%s" % [phase, target.x, target.y, sha, colors.size(), state_hash])

func _capture_public_result_targets(expected_authority_hash: String) -> void:
	for target in TARGETS:
		root.size = target
		await _settle()
		_contract_equal(_authority_hash(session.snapshot()), expected_authority_hash, "all result resolutions must project the same authority snapshot")
		var result := _battle_result_snapshot(_find_shell())
		_contract_true(bool(result.get("visible", false)), "%s production result summary must remain visible" % target)
		var image := root.get_texture().get_image() if root.get_texture() != null else null
		_contract_true(image != null and not image.is_empty(), "%s public result screenshot must be non-empty" % target)
		if image == null or image.is_empty():
			continue
		var path := "%s/m1-public-result-%dx%d.png" % [capture_root, target.x, target.y]
		_contract_true(image.save_png(ProjectSettings.globalize_path(path)) == OK, "%s public result screenshot must save under the owned root" % target)
		public_result_captures += 1
		print("M1_PUBLIC_RESULT_SCREENSHOT_OK size=%dx%d sha256=%s authority=%s" % [target.x, target.y, FileAccess.get_sha256(ProjectSettings.globalize_path(path)), expected_authority_hash])

func _verify_dock_transitions(presenter: Control) -> void:
	root.size = TARGETS[0]
	await _settle()
	var hud := presenter.find_child("M1HiveHud", true, false) as Control
	_contract_true(hud != null, "production hive must expose the native dock container")
	if hud == null:
		return
	var initial: Dictionary = hud.call("ui_contract_snapshot")
	_contract_true(bool(initial.get("slot_expanded", false)) and bool(initial.get("detail_expanded", false)), "both production docks must start expanded and reachable")
	_contract_true(bool(initial.get("slot_toggle_focusable", false)) and bool(initial.get("detail_toggle_focusable", false)), "both dock toggles must be keyboard focusable")
	_contract_dock_layout(presenter, TARGETS[0], "operations-expanded")
	var initial_viewport: Rect2 = initial.get("viewport_slot_rect", Rect2())
	var slot_toggle_button := hud.find_child("M1ToggleSlotDock", true, false) as Button
	if slot_toggle_button != null:
		await _click(slot_toggle_button)
	var slot_collapsed: Dictionary = hud.call("ui_contract_snapshot")
	var slot_collapsed_viewport: Rect2 = slot_collapsed.get("viewport_slot_rect", Rect2())
	_contract_true(not bool(slot_collapsed.get("slot_expanded", true)), "slot dock toggle must collapse through the public Control")
	_contract_true(slot_collapsed_viewport.size.x > initial_viewport.size.x, "slot collapse must reallocate width to the SubViewportContainer")
	_contract_dock_layout(presenter, TARGETS[0], "operations-slot-collapsed")
	if slot_toggle_button != null:
		await _click(slot_toggle_button)
	var detail_toggle_button := hud.find_child("M1ToggleDetailDock", true, false) as Button
	if detail_toggle_button != null:
		await _click(detail_toggle_button)
	var detail_collapsed: Dictionary = hud.call("ui_contract_snapshot")
	var detail_collapsed_viewport: Rect2 = detail_collapsed.get("viewport_slot_rect", Rect2())
	_contract_true(not bool(detail_collapsed.get("detail_expanded", true)), "detail dock toggle must collapse through the public Control")
	_contract_true(detail_collapsed_viewport.size.x > initial_viewport.size.x, "detail collapse must reallocate width to the SubViewportContainer")
	_contract_dock_layout(presenter, TARGETS[0], "operations-detail-collapsed")
	if detail_toggle_button != null:
		await _click(detail_toggle_button)

func _contract_dock_layout(presenter: Control, target: Vector2i, phase: String) -> void:
	if not is_instance_valid(presenter):
		_contract_true(false, "%s %s presenter must exist for dock geometry" % [phase, target])
		return
	var contract: Dictionary = presenter.call("world_contract_snapshot")
	_contract_true(bool(contract.get("layout_non_overlapping", false)), "%s %s viewport, docks and rail must not intersect" % [phase, target])
	var viewport_rect: Rect2 = contract.get("viewport_rect", Rect2())
	var rail_rect: Rect2 = contract.get("rail_rect", Rect2())
	var geometry_hud: Dictionary = contract.get("hud", {})
	print("M1_DOCK_GEOMETRY phase=%s size=%dx%d slot=%s viewport=%s detail=%s rail=%s expanded=%s/%s" % [phase, target.x, target.y, geometry_hud.get("slot_dock_rect", Rect2()), viewport_rect, geometry_hud.get("detail_dock_rect", Rect2()), rail_rect, geometry_hud.get("slot_expanded", false), geometry_hud.get("detail_expanded", false)])
	_contract_true(viewport_rect.size.x > 0.0 and viewport_rect.size.y > 0.0, "%s %s must allocate a positive world viewport" % [phase, target])
	_contract_true(viewport_rect.end.y <= rail_rect.position.y + 1.0, "%s %s world viewport must end before the 78 percent rail" % [phase, target])
	var hud_contract: Dictionary = contract.get("hud", {})
	if bool(hud_contract.get("operations_visible", false)):
		var slot_rect: Rect2 = hud_contract.get("slot_dock_rect", Rect2())
		var detail_rect: Rect2 = hud_contract.get("detail_dock_rect", Rect2())
		_contract_true(slot_rect.end.x <= viewport_rect.position.x + 1.0, "%s %s slot dock must end before the action field" % [phase, target])
		_contract_true(viewport_rect.end.x <= detail_rect.position.x + 1.0, "%s %s detail dock must begin after the action field" % [phase, target])

func _contract_visual_scale(presenter: Control, image: Image, phase: String) -> void:
	var contract: Dictionary = presenter.call("world_contract_snapshot") if is_instance_valid(presenter) else {}
	var landmarks: Dictionary = contract.get("visual_landmarks", {})
	for landmark_name in VISUAL_LANDMARKS.get(phase, []):
		_contract_true(landmarks.has(landmark_name), "%s 1280 capture must expose %s visual landmark" % [phase, landmark_name])
		if not landmarks.has(landmark_name):
			continue
		var landmark: Dictionary = landmarks[landmark_name]
		var rect: Rect2 = landmark.get("rect", Rect2())
		var minimum_bbox := VISUAL_MIN_UNIT_BBOX_PX if String(landmark.get("kind", "")) == "unit" else VISUAL_MIN_VFX_BBOX_PX
		var bbox_min := minf(rect.size.x, rect.size.y)
		var contrast := _local_landmark_contrast(image, rect)
		var direction_x := int(landmark.get("direction_x", 0))
		_contract_true(bbox_min >= minimum_bbox, "%s %s projected alpha bbox must be at least %.1fpx (actual=%.1fpx)" % [phase, landmark_name, minimum_bbox, bbox_min])
		_contract_true(contrast >= VISUAL_MIN_LOCAL_CONTRAST, "%s %s must retain %.3f local foreground/background contrast (actual=%.3f)" % [phase, landmark_name, VISUAL_MIN_LOCAL_CONTRAST, contrast])
		var direction_key := "%s:%s" % [phase, landmark_name]
		if VISUAL_DIRECTIONS.has(direction_key):
			_contract_equal(direction_x, int(VISUAL_DIRECTIONS[direction_key]), "%s %s direction must preserve confrontation/retreat semantics" % [phase, landmark_name])
		print("M1_VISUAL_SCALE_OK phase=%s landmark=%s bbox=%.1fx%.1f min_px=%.1f contrast=%.3f min_contrast=%.3f direction_x=%d" % [phase, landmark_name, rect.size.x, rect.size.y, minimum_bbox, contrast, VISUAL_MIN_LOCAL_CONTRAST, direction_x])

func _local_landmark_contrast(image: Image, rect: Rect2) -> float:
	var bounds := Rect2i(Vector2i.ZERO, Vector2i(image.get_width(), image.get_height()))
	var inside := Rect2i(Vector2i(floor(rect.position.x), floor(rect.position.y)), Vector2i(ceil(rect.size.x), ceil(rect.size.y))).intersection(bounds)
	if inside.size.x <= 0 or inside.size.y <= 0:
		return 0.0
	var outer := inside.grow(6).intersection(bounds)
	var background_sum := Vector3.ZERO
	var background_count := 0
	for y in range(outer.position.y, outer.end.y, 2):
		for x in range(outer.position.x, outer.end.x, 2):
			if inside.has_point(Vector2i(x, y)):
				continue
			var color := image.get_pixel(x, y)
			background_sum += Vector3(color.r, color.g, color.b)
			background_count += 1
	if background_count == 0:
		return 0.0
	var background := background_sum / float(background_count)
	var difference_sum := 0.0
	var foreground_count := 0
	for y in range(inside.position.y, inside.end.y, 2):
		for x in range(inside.position.x, inside.end.x, 2):
			var color := image.get_pixel(x, y)
			difference_sum += Vector3(color.r, color.g, color.b).distance_to(background) / sqrt(3.0)
			foreground_count += 1
	return difference_sum / float(maxi(foreground_count, 1))

func _assert_readable_rail(presenter: Control, target: Vector2i, phase: String) -> void:
	_assert_true(is_instance_valid(presenter) and presenter.is_visible_in_tree(), "%s %s presenter must be visible for layout evidence" % [phase, target])
	if not is_instance_valid(presenter):
		return
	var rail := presenter.find_child("M1ProductionStateRail", true, false) as Control
	_assert_true(rail != null and rail.is_visible_in_tree(), "%s %s must expose the native production state rail" % [phase, target])
	if rail == null:
		return
	_assert_true(rail.size.y >= 40.0, "%s %s state rail must retain a readable height" % [phase, target])
	var presenter_rect := presenter.get_global_rect()
	var labels := presenter.find_children("M1State_*", "Label", true, false)
	_assert_equal(labels.size(), 5, "%s %s must retain all five Chinese state labels" % [phase, target])
	for candidate in labels:
		var label := candidate as Label
		var rect := label.get_global_rect()
		_assert_equal(label.get_line_count(), 1, "%s %s label %s must remain one line" % [phase, target, label.text])
		_assert_true(label.get_theme_font_size("font_size") >= 16, "%s %s label %s must retain production-readable type" % [phase, target, label.text])
		_assert_true(rect.size.x >= 58.0 and rect.size.y >= 28.0, "%s %s label %s must retain a stable rect" % [phase, target, label.text])
		_assert_true(rect.position.x >= presenter_rect.position.x - 1.0 and rect.end.x <= presenter_rect.end.x + 1.0, "%s %s label %s must not clip horizontally" % [phase, target, label.text])

func _contract_readable_rail(presenter: Control, target: Vector2i, phase: String) -> void:
	_contract_true(is_instance_valid(presenter) and presenter.is_visible_in_tree(), "%s %s presenter must be visible for layout evidence" % [phase, target])
	if not is_instance_valid(presenter):
		return
	var rail := presenter.find_child("M1ProductionStateRail", true, false) as Control
	_contract_true(rail != null and rail.is_visible_in_tree(), "%s %s must expose the native production state rail" % [phase, target])
	if rail == null:
		return
	_contract_true(rail.size.y >= 40.0, "%s %s state rail must retain a readable height" % [phase, target])
	var presenter_rect := presenter.get_global_rect()
	var labels := presenter.find_children("M1State_*", "Label", true, false)
	_contract_equal(labels.size(), 5, "%s %s must retain all five Chinese state labels" % [phase, target])
	for candidate in labels:
		var label := candidate as Label
		var rect := label.get_global_rect()
		_contract_equal(label.get_line_count(), 1, "%s %s label %s must remain one line" % [phase, target, label.text])
		_contract_true(label.get_theme_font_size("font_size") >= 16, "%s %s label %s must retain production-readable type" % [phase, target, label.text])
		_contract_true(rect.size.x >= 58.0 and rect.size.y >= 28.0, "%s %s label %s must retain a stable rect" % [phase, target, label.text])
		_contract_true(rect.position.x >= presenter_rect.position.x - 1.0 and rect.end.x <= presenter_rect.end.x + 1.0, "%s %s label %s must not clip horizontally" % [phase, target, label.text])

func _assert_world_contract(presenter: Control, expected_phase: String) -> void:
	_contract_true(is_instance_valid(presenter) and presenter.has_method("world_contract_snapshot"), "%s presenter must expose the native world contract" % expected_phase)
	if not is_instance_valid(presenter) or not presenter.has_method("world_contract_snapshot"):
		return
	var contract: Dictionary = presenter.call("world_contract_snapshot")
	_contract_equal(String(contract.get("root_type", "")), "Node2D", "M1 production world root must be Node2D")
	_contract_equal(String(contract.get("camera_type", "")), "Camera2D", "M1 production world must own Camera2D")
	_contract_true(bool(contract.get("camera_enabled", false)), "M1 production camera must be enabled")
	_contract_equal(String(contract.get("host_type", "")), "SubViewportContainer", "M1 production presenter must isolate the world viewport")
	_contract_equal(String(contract.get("viewport_type", "")), "SubViewport", "M1 production presenter must own a SubViewport")
	_contract_equal(int(contract.get("environment_sprites", -1)), 3, "M1 production environment must contain three Sprite2D plates")
	_contract_equal(int(contract.get("room_entities", -1)), 3, "M1 production world must instance three reusable room scenes")
	_contract_true(int(contract.get("unit_entities", 0)) >= 6, "M1 production world must instance reusable unit scenes")
	_contract_equal(int(contract.get("world_controls", -1)), 0, "M1 production world must contain no Control nodes")
	_contract_equal(int(contract.get("static_redraws", -1)), 0, "M1 static world must not redraw through CanvasItem._draw")
	_contract_true(int(contract.get("action_field_max_y", 1080)) < 842, "M1 VFX geometry must stay above the 78 percent rail reserve")
	_contract_equal(float(contract.get("rail_reserved_start", 0.0)), 0.78, "M1 production rail reserve must begin at 78 percent")
	_contract_equal(String(contract.get("phase", "")), expected_phase, "M1 world must consume the production phase transition")
	_contract_true(int(contract.get("event_count", 0)) > 0, "M1 world must record at least one consumed visual event")

func _verify_legacy_fallback(value: Dictionary) -> void:
	for scene_path in ["", ERROR_CONTROL_SCENE_PATH]:
		var fallback := HivePage.new(session, scene_path)
		fallback.name = "M1FallbackFixture"
		fallback.visible = true
		root.add_child(fallback)
		fallback.set_snapshot(value)
		fallback.set_active(true)
		await _settle()
		var legacy := fallback.find_child("LegacyHiveFallback", true, false) as Control
		var detail_band := fallback.find_child("LegacyHiveDetailBand", true, false) as Control
		var world_band := fallback.find_child("M1WorldBand", true, false) as Control
		var reason := fallback.find_child("LegacyHiveFallbackReason", true, false) as Label
		_assert_true(legacy != null and legacy.visible, "unavailable M1 scene must expose the real legacy hive page")
		_assert_true(detail_band != null and detail_band.visible, "hive fallback must reactivate the legacy detail band")
		_assert_true(world_band != null and not world_band.visible, "fallback must not leave a partial M1 world visible")
		_assert_true(reason != null and reason.visible and not reason.text.is_empty(), "hive fallback must show an explicit reason")
		if scene_path == ERROR_CONTROL_SCENE_PATH:
			_assert_true(reason.text.contains("set_view_model"), "hive error-Control fallback must report the missing view contract")
		var detail := fallback.find_child("LegacyHiveDetail", true, false) as Control
		_assert_true(detail != null and detail.get_child_count() > 0, "legacy reactivation must refresh hive details once")
		fallback.set_active(false)
		fallback.queue_free()
		await process_frame

func _verify_battle_fallback(value: Dictionary) -> void:
	var fallback := BattlePage.new(session, ERROR_CONTROL_SCENE_PATH)
	fallback.name = "M1BattleFallbackFixture"
	fallback.visible = true
	root.add_child(fallback)
	fallback.set_snapshot(value)
	fallback.set_active(true)
	await _settle()
	var canvas := fallback.find_child("LegacyBattleCanvas", true, false) as Control
	var reason := fallback.find_child("M1FallbackReason", true, false) as Label
	var presenter := fallback.find_child("M1WorldPresenter", true, false) as Control
	_assert_true(presenter != null and not bool(presenter.call("is_available")), "battle error-Control presenter must fail closed")
	_assert_true(canvas != null and canvas.visible, "battle fallback must keep the legacy battle canvas reachable")
	_assert_true(reason != null and reason.visible and reason.text.contains("set_view_model"), "battle fallback must show the missing view contract reason")
	fallback.set_active(false)
	fallback.queue_free()
	await process_frame

func _m1_presenter_count(node: Node) -> int:
	if node == null:
		return 0
	return node.find_children("M1WorldPresenter", "Control", true, false).size()

func _unique_hash_count() -> int:
	var unique := {}
	for value in hashes:
		unique[value] = true
	return unique.size()

func _on_notice_posted(message: String, level: String) -> void:
	if level in ["success", "warning"] and (message.contains("保存") or message.contains("存档槽")):
		save_notices += 1

func _state_hash(value: Dictionary) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(JSON.stringify(_canonical_json(value), "", true).to_utf8_buffer())
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

func _authority_hash(value: Dictionary) -> String:
	var authority := value.duplicate(true)
	authority.erase("ledger")
	return _state_hash(authority)

func _read_slot(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK or not parser.data is Dictionary:
		return {}
	return parser.data

func _mutable_node(node_id: String) -> Dictionary:
	for node in session.state.nodes:
		if String(node.get("id", "")) == node_id:
			return node
	return {}

func _shell_page(shell: Control, page_id: String) -> Control:
	if shell == null:
		return null
	var pages: Dictionary = shell.get("pages")
	return pages.get(page_id) as Control if pages.has(page_id) else null

func _battle_result_snapshot(shell: Control) -> Dictionary:
	var page := _shell_page(shell, "battle")
	if page == null or not page.has_method("battle_result_snapshot"):
		return {}
	var value: Variant = page.call("battle_result_snapshot")
	return value if value is Dictionary else {}

func _signal_connection_count(signal_name: String) -> int:
	return session.get_signal_connection_list(signal_name).size()

func _m1_lifecycle_snapshot(shell: Control) -> Dictionary:
	if shell == null or not shell.has_method("m1_lifecycle_snapshot"):
		return {}
	var snapshot_value: Variant = shell.call("m1_lifecycle_snapshot")
	return snapshot_value if snapshot_value is Dictionary else {}

func _file_fingerprint(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"path": path, "exists": false, "sha256": "", "size": 0, "mtime": ""}
	var global_path := ProjectSettings.globalize_path(path)
	var sha_output: Array = []
	var stat_output: Array = []
	var sha_status := OS.execute("sha256sum", PackedStringArray([global_path]), sha_output, true)
	var stat_status := OS.execute("stat", PackedStringArray(["-c", "%s|%y", global_path]), stat_output, true)
	_assert_equal(sha_status, 0, "external SHA-256 fingerprint must succeed")
	_assert_equal(stat_status, 0, "external nanosecond stat fingerprint must succeed")
	var stat_parts := String("".join(stat_output)).strip_edges().split("|", false, 1)
	return {
		"path": path,
		"exists": true,
		"sha256": String("".join(sha_output)).get_slice(" ", 0),
		"size": int(stat_parts[0]) if stat_parts.size() > 0 else 0,
		"mtime": String(stat_parts[1]) if stat_parts.size() > 1 else "",
	}

func _committed_slot_fingerprint() -> Dictionary:
	return {
		"primary": _file_fingerprint(session.DEFAULT_SAVE_PATH),
		"backup": _file_fingerprint(session.DEFAULT_SAVE_PATH + session.BACKUP_SUFFIX),
	}

func _assert_fingerprint_complete(value: Dictionary, label: String) -> void:
	for slot in ["primary", "backup"]:
		var fingerprint: Dictionary = value.get(slot, {})
		var expected_path: String = session.DEFAULT_SAVE_PATH if slot == "primary" else session.DEFAULT_SAVE_PATH + session.BACKUP_SUFFIX
		_assert_equal(String(fingerprint.get("path", "")), expected_path, "%s %s must expose its exact save path" % [label, slot])
		_assert_true(bool(fingerprint.get("exists", false)), "%s %s must exist" % [label, slot])
		_assert_true(not String(fingerprint.get("sha256", "")).is_empty(), "%s %s must expose SHA-256" % [label, slot])
		_assert_true(int(fingerprint.get("size", 0)) > 0, "%s %s must expose a positive size" % [label, slot])
		_assert_true(not String(fingerprint.get("mtime", "")).is_empty(), "%s %s must expose nanosecond mtime" % [label, slot])

func _assert_disk_authority_matches(primary_fingerprint: Dictionary, expected_hash: String, label: String) -> void:
	_assert_equal(_file_fingerprint(session.DEFAULT_SAVE_PATH), primary_fingerprint, "%s primary fingerprint must remain the committed slot" % label)
	var disk_state := _read_slot(session.DEFAULT_SAVE_PATH)
	_assert_equal(_authority_hash(disk_state), expected_hash, "%s primary must match the authority state" % label)

func _cleanup_slots() -> void:
	for suffix in ["", session.BACKUP_SUFFIX, session.SAVE_TEMP_SUFFIX, session.BACKUP_TEMP_SUFFIX, session.BACKUP_PREVIOUS_SUFFIX, session.ROLLBACK_SUFFIX, session.RECOVERY_SUFFIX, session.BACKUP_SUFFIX + session.RECOVERY_SUFFIX]:
		var path: String = session.DEFAULT_SAVE_PATH + suffix
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _find_shell() -> Control:
	for node in main.find_children("*", "Control", true, false):
		if node.has_method("_show_page") and node.has_method("_update_battle_strip"):
			return node as Control
	return null

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

func _settle() -> void:
	for index in range(2):
		await process_frame
	await RenderingServer.frame_post_draw

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

func _contract_true(value: bool, message: String) -> void:
	if not value:
		failures.append(message)

func _contract_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		failures.append("%s (actual=%s expected=%s)" % [message, actual, expected])
