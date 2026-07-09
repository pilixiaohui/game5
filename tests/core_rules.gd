extends SceneTree

const ConfigDBScript := preload("res://scripts/autoload/ConfigDB.gd")
const GameStateScript := preload("res://scripts/autoload/GameState.gd")
const SaveServiceScript := preload("res://scripts/autoload/SaveService.gd")
const SimulationServiceScript := preload("res://scripts/autoload/SimulationService.gd")
const BattlefieldViewScript := preload("res://scripts/ui/BattlefieldView.gd")
const MainScript := preload("res://scripts/ui/Main.gd")

var ConfigDB
var GameState
var SaveService
var SimulationService
var _failures: Array[String] = []

func _initialize() -> void:
	_install_services()
	call_deferred("_run_deferred")

func _install_services() -> void:
	ConfigDB = ConfigDBScript.new()
	ConfigDB.name = "ConfigDB"
	root.add_child(ConfigDB)

	GameState = GameStateScript.new()
	GameState.name = "GameState"
	GameState.ConfigDB = ConfigDB
	root.add_child(GameState)

	SaveService = SaveServiceScript.new()
	SaveService.name = "SaveService"
	SaveService.GameState = GameState
	root.add_child(SaveService)

	SimulationService = SimulationServiceScript.new()
	SimulationService.name = "SimulationService"
	SimulationService.ConfigDB = ConfigDB
	SimulationService.GameState = GameState
	SimulationService.SaveService = SaveService
	root.add_child(SimulationService)

func _run_deferred() -> void:
	_run()
	if _failures.is_empty():
		print("CORE_RULES_OK")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)

func _run() -> void:
	ConfigDB.ensure_loaded()
	_test_metabolism_and_upgrade()
	_test_failure_paths_do_not_mutate_state()
	_test_deploy_retreat_conservation()
	_test_battle_report_feedback_states()
	_test_battlefield_intent_commands()
	_test_early_pacing_projection()
	_test_battlefield_badge_regressions()
	_test_main_battlefield_display_state_sync()
	_test_ready_wave_overrides_hatch_shortage_ui()
	_test_completed_region_battlefield_flow()
	_test_factory_entry_supply_idempotent()
	_test_factory_entry_first_push_loop()
	_test_factory_public_battlefield_commands_use_hydralisk()
	_test_content_expansion_units_and_research_bastion()
	_test_mobile_readability_and_completed_factory_guidance()
	_test_plugin_ab_comparison()
	_test_offline_cap()
	_test_save_integrity()
	_test_prestige_preview_and_reset_state()

func _test_metabolism_and_upgrade() -> void:
	GameState.reset_new_game(false)
	GameState.ensure_config_defaults()
	_assert(GameState.resources["pulp"] >= 0.0, "new save resources must not be negative")

	SimulationService.simulate_seconds(30.0, false)
	_assert(float(GameState.resources["pulp"]) > 36.0, "organic pulp should grow from baseline metabolism")

	GameState.resources["pulp"] = 500.0
	GameState.resources["enzyme"] = 80.0
	GameState.resources["helix"] = 40.0
	GameState.resources["larva"] = 30.0
	var before_pulp := float(GameState.resources["pulp"])
	_assert(SimulationService.purchase_organ("mucus_fronds"), "organ purchase should succeed when affordable")
	_assert(float(GameState.resources["pulp"]) < before_pulp, "organ purchase should spend pulp")
	_assert(_all_resources_non_negative(), "organ purchase must not make resources negative")

func _test_failure_paths_do_not_mutate_state() -> void:
	GameState.reset_new_game(false)
	GameState.ensure_config_defaults()
	GameState.resources = {"pulp": 0.0, "enzyme": 0.0, "helix": 0.0, "larva": 0.0, "mutation": 0.0}
	GameState.ensure_config_defaults()
	var before: Dictionary = GameState.to_dict().duplicate(true)

	_assert(not SimulationService.purchase_organ("deep_roots"), "unaffordable organ purchase should fail")
	_assert(int(GameState.organ_levels["deep_roots"]) == int(before["organ_levels"]["deep_roots"]), "failed organ purchase must not change organ level")
	_assert(_resources_equal(GameState.resources, before["resources"]), "failed organ purchase must not spend resources")

	_assert(not SimulationService.hatch_unit("hydralisk", 1), "unaffordable hatch should fail")
	_assert(int(GameState.reserves["hydralisk"]) == int(before["reserves"]["hydralisk"]), "failed hatch must not add reserve")
	_assert(_resources_equal(GameState.resources, before["resources"]), "failed hatch must not spend resources")

	_assert(not SimulationService.buy_or_equip_plugin("piercing_spines"), "unaffordable plugin purchase should fail")
	_assert(not bool(GameState.plugins_owned.get("piercing_spines", false)), "failed plugin purchase must not add ownership")
	_assert(GameState.equipped_plugin == "", "failed plugin purchase must not equip plugin")
	_assert(_resources_equal(GameState.resources, before["resources"]), "failed plugin purchase must not spend resources")
	_assert(_all_resources_non_negative(), "failed paths must not make resources negative")

func _test_deploy_retreat_conservation() -> void:
	GameState.reset_new_game(false)
	GameState.ensure_config_defaults()
	GameState.resources = {"pulp": 500.0, "enzyme": 20.0, "helix": 0.0, "larva": 40.0, "mutation": 0.0}
	GameState.ensure_config_defaults()
	_assert(SimulationService.hatch_unit("zergling", 8), "zergling hatch should succeed")
	_assert(SimulationService.hatch_unit("hydralisk", 4), "hydralisk hatch should succeed")
	var zergling_reserve := int(GameState.reserves["zergling"])
	SimulationService.set_deployment("zergling", 2)
	SimulationService.set_deployment("hydralisk", 1)
	SimulationService.simulate_seconds(8.0, true)
	_assert(int(GameState.reserves["zergling"]) < zergling_reserve, "deployment should consume reserve")
	_assert(float(GameState.region_progress["slum_edge"]) > 0.0, "battle should advance devour progress with enough force")

	var reserve_before_retreat := int(GameState.reserves["zergling"]) + int(GameState.reserves["hydralisk"])
	var field_before_retreat := int(GameState.field_units["zergling"]) + int(GameState.field_units["hydralisk"])
	var expected_return := int(floor(float(GameState.field_units["zergling"]) * 0.75)) + int(floor(float(GameState.field_units["hydralisk"]) * 0.75))
	var retreat_projection: Dictionary = SimulationService.battle_projection("zergling")
	_assert(int(retreat_projection.get("retreat_field_before", 0)) == field_before_retreat, "retreat projection should expose current field count before withdrawal")
	_assert(int(retreat_projection.get("retreat_value", 0)) == expected_return, "retreat projection should expose recoverable unit value")
	SimulationService.retreat()
	var reserve_after_retreat := int(GameState.reserves["zergling"]) + int(GameState.reserves["hydralisk"])
	var field_after_retreat := int(GameState.field_units["zergling"]) + int(GameState.field_units["hydralisk"])
	_assert(field_before_retreat > 0, "battle should have field units before retreat")
	_assert(field_after_retreat == 0, "retreat should clear field units")
	_assert(int(GameState.deployment_intensity["zergling"]) == 0 and int(GameState.deployment_intensity["hydralisk"]) == 0, "retreat should close deployment valves")
	_assert(reserve_after_retreat == reserve_before_retreat + expected_return, "retreat should return exactly 75 percent floored from each field unit stack")
	_assert(String(GameState.battle_report.get("mode", "")) == "retreat", "retreat should replace stale pressure report with retreat state")
	_assert(int(GameState.battle_report.get("returned", 0)) == expected_return, "retreat battle report should expose recovered unit count")
	_assert(int(GameState.battle_report.get("field_total", -1)) == 0, "retreat battle report should show an empty field")
	_assert(int(GameState.battle_report.get("retreat_value", 0)) == expected_return, "retreat battle report should keep recovered value for battlefield cues")
	_assert(int(GameState.battle_report.get("retreat_field_before", 0)) == field_before_retreat, "retreat battle report should preserve pre-retreat field count")

func _test_battle_report_feedback_states() -> void:
	GameState.reset_new_game(false)
	GameState.ensure_config_defaults()
	SimulationService.set_deployment("zergling", 2)
	SimulationService.simulate_seconds(1.0, true)
	_assert(String(GameState.battle_report.get("mode", "")) == "empty", "open valve with no reserves should report empty reinforcement state")

	GameState.reset_new_game(false)
	GameState.ensure_config_defaults()
	GameState.resources = {"pulp": 200.0, "enzyme": 20.0, "helix": 0.0, "larva": 20.0, "mutation": 0.0}
	GameState.ensure_config_defaults()
	_assert(SimulationService.hatch_unit("zergling", 1), "single zergling hatch should set up stalled battle report")
	SimulationService.set_deployment("zergling", 1)
	SimulationService.simulate_seconds(1.0, true)
	_assert(String(GameState.battle_report.get("mode", "")) == "stalled", "underpowered field should report stalled battle")
	_assert(int(GameState.battle_report.get("reinforced", 0)) > 0, "battle report should record visible unit reinforcement")
	_assert(int(GameState.battle_report.get("lost", 0)) > 0, "stalled battle report should record visible losses")

	GameState.reset_new_game(false)
	GameState.ensure_config_defaults()
	GameState.resources = {"pulp": 500.0, "enzyme": 20.0, "helix": 0.0, "larva": 40.0, "mutation": 0.0}
	GameState.ensure_config_defaults()
	_assert(SimulationService.hatch_unit("zergling", 8), "zergling hatch should set up advancing battle report")
	SimulationService.set_deployment("zergling", 2)
	SimulationService.simulate_seconds(4.0, true)
	_assert(String(GameState.battle_report.get("mode", "")) == "advance", "sufficient field power should report advancing battle")
	_assert(float(GameState.battle_report.get("progress_gain", 0.0)) > 0.0, "advancing battle report should expose progress gain for progress bar feedback")
	_assert(int(GameState.battle_report.get("reinforced", 0)) > 0, "advancing battle report should expose unit refill count")

func _test_battlefield_intent_commands() -> void:
	GameState.reset_new_game(false)
	GameState.ensure_config_defaults()
	_assert(SimulationService.prepare_wave("zergling"), "prepare command should hatch an initial wave when affordable")
	_assert(String(GameState.battle_report.get("mode", "")) == "preparing", "prepare command should show wave preparation instead of opening combat")
	_assert(int(GameState.reserves.get("zergling", 0)) > 0, "prepare command should add reserve")
	_assert(int(GameState.deployment_intensity.get("zergling", -1)) == 0, "prepare command must not open deployment before scale is ready")
	_assert(int(GameState.field_units.get("zergling", 0)) == 0, "prepare command must not send the first wave into losses")
	_assert(int(GameState.battle_report.get("needed_reserve", 0)) > int(GameState.battle_report.get("prepared_reserve", 0)), "initial no-seed wave should expose reserve shortfall")

	_assert(not SimulationService.assault_push("zergling"), "understrength assault should be held instead of committed")
	_assert(String(GameState.battle_report.get("mode", "")) == "understrength", "understrength assault should explain insufficient scale")
	_assert(int(GameState.deployment_intensity.get("zergling", -1)) == 0, "understrength assault must keep deployment closed")

	GameState.resources["pulp"] = 120.0
	GameState.resources["larva"] = 10.0
	_assert(SimulationService.prepare_wave("zergling"), "second preparation should top up the wave")
	_assert(SimulationService.assault_push("zergling"), "sufficient wave should commit assault")
	_assert(String(GameState.battle_report.get("mode", "")) == "committed", "committed assault should be visible before the next simulation tick")
	_assert(int(GameState.deployment_intensity.get("zergling", 0)) == 3, "committed assault should set explicit high intensity")

func _test_early_pacing_projection() -> void:
	GameState.reset_new_game(false)
	GameState.ensure_config_defaults()
	GameState.resources = {"pulp": 120.0, "enzyme": 0.0, "helix": 0.0, "larva": 12.0, "mutation": 0.0}
	GameState.ensure_config_defaults()
	_assert(SimulationService.prepare_wave("zergling"), "early pacing setup should prepare wave")
	_assert(int(GameState.battle_report.get("needed_reserve", 0)) == 5, "fresh no-upgrade wave threshold should start at five")
	_assert(int(GameState.battle_report.get("reserve_shortfall", 0)) == 2, "fresh first prepare should expose the two-unit shortfall")
	_assert(int(GameState.battle_report.get("hatch_fill_count", 0)) == 2, "fresh first prepare should show that another left-click can fill the shortfall")
	_assert(SimulationService.prepare_wave("zergling"), "early pacing setup should top up wave")
	_assert(SimulationService.assault_push("zergling"), "full early wave should commit")
	SimulationService.simulate_seconds(5.0, true)
	_assert(GameState.total_devour >= 4.0, "first committed wave should reveal reset-preview milestone inside the opening window")
	var preview: Dictionary = SimulationService.prestige_preview()
	_assert(int(preview.get("gain", 0)) >= 1, "early reset preview should show a tangible gain after opening push")
	_assert(float(GameState.resources.get("helix", 0.0)) >= 2.0, "opening push should naturally expose acid_carapace plugin affordability")

	GameState.reset_new_game(false)
	GameState.ensure_config_defaults()
	var base_projection: Dictionary = SimulationService.battle_projection("zergling")
	GameState.organ_levels["deep_roots"] = 1
	var upgraded_projection: Dictionary = SimulationService.battle_projection("zergling")
	_assert(int(base_projection.get("baseline_needed_reserve", 0)) == 5, "baseline battle projection should expose the original five-unit threshold")
	_assert(int(upgraded_projection.get("baseline_needed_reserve", 0)) == 5, "upgraded battle projection should retain original threshold for comparison")
	_assert(int(upgraded_projection.get("needed_reserve", 0)) == 4, "deep roots should lower the visible wave threshold from five to four")
	_assert(int(upgraded_projection.get("needed_reserve", 0)) < int(base_projection.get("needed_reserve", 0)), "support upgrade should visibly lower wave threshold")
	_assert(float(upgraded_projection.get("effective_pressure", 0.0)) < float(base_projection.get("effective_pressure", 0.0)), "support upgrade should visibly reduce effective enemy pressure")
	_assert(float(upgraded_projection.get("pressure_drop", 0.0)) > 0.0, "support upgrade projection should expose the enemy-pressure reduction amount")

	GameState.resources["helix"] = 2.0
	_assert(SimulationService.buy_or_equip_plugin("acid_carapace"), "acid carapace should be affordable in early projection setup")
	var plugin_projection: Dictionary = SimulationService.battle_projection("zergling")
	_assert(float(plugin_projection.get("plugin_bonus", 0.0)) > 0.0, "acid carapace should expose a battlefield plugin damage delta")
	_assert(float(plugin_projection.get("loss_rate", 0.0)) < float(plugin_projection.get("baseline_loss_rate", 0.0)), "acid carapace should expose lower projected loss rate")
	_assert(float(plugin_projection.get("loss_reduction", 0.0)) > 0.0, "acid carapace should expose the loss-reduction amount")
	_assert(int(plugin_projection.get("loss_saved_estimate", 0)) > 0, "acid carapace should expose an estimated saved-loss count")
	_assert(int(plugin_projection.get("protected_estimate", 0)) > 0, "acid carapace should expose an estimated protected wave count")

func _test_battlefield_badge_regressions() -> void:
	GameState.reset_new_game(false)
	GameState.ensure_config_defaults()
	GameState.resources = {"pulp": 0.0, "enzyme": 0.0, "helix": 0.0, "larva": 0.0, "mutation": 0.0}
	GameState.reserves["zergling"] = 3
	GameState.ensure_config_defaults()
	var blocked_projection: Dictionary = SimulationService.battle_projection("zergling")
	_assert(int(blocked_projection.get("reserve_shortfall", 0)) == 2, "battle projection should expose actual missing bodies")
	_assert(int(blocked_projection.get("hatch_fill_count", -1)) == 0, "battle projection should not suggest hatch fill when resources cannot pay for one unit")
	_assert(String(blocked_projection.get("hatch_missing_text", "")) != "", "battle projection should expose missing hatch resources when resources block the next body")

	GameState.reserves["zergling"] = 12
	var ready_projection: Dictionary = SimulationService.battle_projection("zergling")
	_assert(int(ready_projection.get("prepared_reserve", 0)) == 12, "battle projection should reflect current reserve count")
	_assert(int(ready_projection.get("reserve_shortfall", -1)) == 0, "sufficient current reserves must not expose a shortage badge")
	_assert(int(ready_projection.get("hatch_fill_count", -1)) == 0, "sufficient current reserves must not expose a hatch-fill action")

	GameState.organ_levels["deep_roots"] = 1
	GameState.reserves["zergling"] = 13
	var threshold_projection: Dictionary = SimulationService.battle_projection("zergling")
	_assert(int(threshold_projection.get("needed_reserve", 0)) == 4, "deep roots readiness regression should use the current four-unit threshold")
	_assert(int(threshold_projection.get("prepared_reserve", 0)) == 13, "deep roots readiness regression should see the actual thirteen-unit reserve")
	_assert(int(threshold_projection.get("reserve_shortfall", -1)) == 0, "thirteen reserves at a four-unit threshold must not expose a shortage")

	GameState.reset_new_game(false)
	GameState.ensure_config_defaults()
	SimulationService.retreat()
	_assert(int(GameState.battle_report.get("returned", -1)) == 0, "empty retreat should return zero units")
	_assert(int(GameState.battle_report.get("retreat_value", -1)) == 0, "empty retreat should not advertise a positive retreat value")
	_assert(int(GameState.battle_report.get("retreat_field_before", -1)) == 0, "empty retreat should not advertise field units to preserve")

	GameState.reset_new_game(false)
	GameState.ensure_config_defaults()
	GameState.resources = {"pulp": 160.0, "enzyme": 0.0, "helix": 0.0, "larva": 20.0, "mutation": 0.0}
	GameState.ensure_config_defaults()
	_assert(SimulationService.hatch_unit("zergling", 4), "retreat-window setup should hatch a small real wave")
	SimulationService.set_deployment("zergling", 3)
	SimulationService.simulate_seconds(1.0, true)
	var field_after_stall: int = int(GameState.field_units.get("zergling", 0))
	var natural_retreat_projection: Dictionary = SimulationService.battle_projection("zergling")
	_assert(field_after_stall > 0, "stalled multi-unit wave should leave a real field-unit retreat window")
	_assert(int(natural_retreat_projection.get("retreat_value", 0)) > 0, "natural retreat window should expose a positive preservation value")

	var view = BattlefieldViewScript.new()
	_assert(String(view.call("_display_mode", "understrength", 13, 4, 0)) != "understrength", "ready projection must not render a stale understrength mode")
	_assert(String(view.call("_mode_text", "understrength", 0.0, 0.0, 0, 13, 4)).find("规模不足") == -1, "ready projection must not print scale-insufficient wording")
	view.set_snapshot({
		"returned": 0,
		"retreat_value": 4,
		"retreat_field_before": 6,
		"preserved_loss_estimate": 2
	})
	_assert(int(view.call("_retreat_badge_visible_return")) == 4, "positive retreat projection should show a preservation badge immediately")
	view.set_snapshot({
		"returned": 0,
		"retreat_value": 0,
		"retreat_field_before": 0,
		"preserved_loss_estimate": 0
	})
	_assert(int(view.call("_retreat_badge_visible_return")) == 4, "positive retreat badge should remain readable after the field clears")
	view.call("_process", 2.5)
	_assert(int(view.call("_retreat_badge_visible_return")) == 4, "retreat badge should hold for the readable window")
	view.call("_process", 0.6)
	_assert(int(view.call("_retreat_badge_visible_return")) == 0, "retreat badge should clear after the readable window instead of lingering")
	view.free()

func _test_main_battlefield_display_state_sync() -> void:
	GameState.reset_new_game(false)
	GameState.ensure_config_defaults()
	GameState.resources = {"pulp": 36.0, "enzyme": 0.0, "helix": 0.0, "larva": 3.0, "mutation": 0.0}
	GameState.ensure_config_defaults()
	_assert(SimulationService.prepare_wave("zergling"), "display sync setup should create a partial wave")
	_assert(not SimulationService.assault_push("zergling"), "display sync setup should create an old understrength report")
	_assert(String(GameState.battle_report.get("mode", "")) == "understrength", "display sync setup should preserve stale understrength in rule report")

	GameState.organ_levels["deep_roots"] = 1
	GameState.reserves["zergling"] = 13
	GameState.field_units["zergling"] = 0
	GameState.deployment_intensity["zergling"] = 0

	var main = MainScript.new()
	main.ConfigDB = ConfigDB
	main.GameState = GameState
	main.SaveService = SaveService
	main.SimulationService = SimulationService
	var snapshot: Dictionary = main.call("_battlefield_snapshot")
	_assert(String(GameState.battle_report.get("mode", "")) == "understrength", "UI display derivation must not rewrite the underlying rule report")
	_assert(int(snapshot.get("prepared_reserve", 0)) == 13, "battlefield snapshot should use the current live reserve count")
	_assert(int(snapshot.get("needed_reserve", 0)) == 4, "battlefield snapshot should use the current projection threshold")
	_assert(int(snapshot.get("reserve_shortfall", -1)) == 0, "battlefield snapshot should not expose a live shortage once projection is ready")
	_assert(String(snapshot.get("mode", "")) != "understrength", "battlefield snapshot must not pass through stale understrength mode")
	_assert(String(snapshot.get("mode", "")) != "preparing", "battlefield snapshot must not pass through stale preparing mode once projection is ready")
	var visual_state: Dictionary = main.call("_battle_visual_state", snapshot)
	_assert(String(visual_state.get("status_text", "")).find("规模不足") == -1, "battle status strip helper must not output stale scale-insufficient text")
	main.free()

func _test_ready_wave_overrides_hatch_shortage_ui() -> void:
	GameState.reset_new_game(false)
	GameState.ensure_config_defaults()
	GameState.organ_levels["deep_roots"] = 1
	GameState.reserves["zergling"] = 13
	GameState.field_units["zergling"] = 0
	GameState.deployment_intensity["zergling"] = 0
	GameState.battle_report = {
		"mode": "understrength",
		"region_id": "slum_edge",
		"progress": 0.0,
		"progress_gain": 0.0,
		"power": 9.6,
		"pressure": 13.3,
		"field_total": 0,
		"reinforced": 0,
		"lost": 0,
		"returned": 0,
		"loss_reason": "understrength",
		"front_motion": "hold",
		"prepared_reserve": 3,
		"needed_reserve": 4,
		"reserve_shortfall": 1,
		"hatch_fill_count": 0,
		"hatch_missing_text": "幼虫 1",
		"cause": "need_reserve"
	}
	GameState.set_feedback("强攻暂缓：跳虫 规模 3/4，缺幼虫1；先蓄兵或换构筑。")

	var main = MainScript.new()
	main.ConfigDB = ConfigDB
	main.GameState = GameState
	main.SaveService = SaveService
	main.SimulationService = SimulationService
	var snapshot: Dictionary = main.call("_battlefield_snapshot")
	_assert(int(snapshot.get("prepared_reserve", 0)) == 13, "ready override should use actual reserve count 13")
	_assert(int(snapshot.get("needed_reserve", 0)) == 4, "ready override should keep the current four-unit threshold")
	_assert(int(snapshot.get("reserve_shortfall", -1)) == 0, "ready override must clear stale one-unit shortage")
	_assert(int(snapshot.get("hatch_fill_count", -1)) == 0, "ready override must clear hatch-fill prompts")
	_assert(String(snapshot.get("hatch_missing_text", "x")) == "", "ready override must clear hatch missing resource text")
	_assert(String(snapshot.get("mode", "")) == "ready", "ready override should expose a wave-ready display state")
	var visual_state: Dictionary = main.call("_battle_visual_state", snapshot)
	var status_text: String = String(visual_state.get("status_text", ""))
	_assert(status_text.find("规模不足") == -1 and status_text.find("还差") == -1, "status strip must not show shortage when reserve satisfies threshold")
	var display_feedback: String = main.call("_display_feedback", snapshot)
	_assert(display_feedback.find("规模") == -1, "display feedback must suppress stale assault scale text")
	_assert(display_feedback.find("缺幼虫") == -1, "display feedback must not let hatch resource shortage deny a ready wave")
	_assert(display_feedback.find("可强攻") >= 0, "display feedback should point to the valid assault action")

	var view = BattlefieldViewScript.new()
	_assert(not bool(view.call("_should_show_shortfall_badge", 13, 4, 1)), "shortfall badge must be hidden when current reserve already meets threshold")
	view.free()
	main.free()

	GameState.reset_new_game(false)
	GameState.ensure_config_defaults()
	GameState.active_region = "factory_wall"
	GameState.region_unlocked["factory_wall"] = true
	GameState.organ_levels["deep_roots"] = 1
	GameState.reserves["zergling"] = 13
	GameState.reserves["hydralisk"] = 0
	GameState.field_units["zergling"] = 0
	GameState.field_units["hydralisk"] = 0
	GameState.resources = {"pulp": 78.0, "enzyme": 12.0, "helix": 0.0, "larva": 3.0, "mutation": 0.0}
	GameState.ensure_config_defaults()
	main = MainScript.new()
	main.ConfigDB = ConfigDB
	main.GameState = GameState
	main.SaveService = SaveService
	main.SimulationService = SimulationService
	var preferred_unit: String = String(main.call("_preferred_assault_unit"))
	_assert(preferred_unit == "hydralisk", "factory command should prefer hydralisk first wave instead of letting ready zerglings steal it")
	_assert(SimulationService.assault_push(preferred_unit), "preferred hydralisk wave should commit through public factory selection")
	_assert(String(GameState.feedback).find("规模") == -1, "committed ready wave must not leave stale 3/4 assault feedback")
	_assert(int(GameState.deployment_intensity.get("hydralisk", 0)) == 3, "hydralisk should receive the factory assault command")
	_assert(int(GameState.deployment_intensity.get("zergling", 0)) == 0, "ready zerglings should not steal the factory assault command")
	main.free()

func _test_completed_region_battlefield_flow() -> void:
	GameState.reset_new_game(false)
	GameState.ensure_config_defaults()
	GameState.region_progress["slum_edge"] = 100.0
	GameState.total_devour = 100.0
	GameState.region_unlocked["factory_wall"] = true
	GameState.field_units["zergling"] = 6
	GameState.reserves["zergling"] = 3
	GameState.deployment_intensity["zergling"] = 3
	GameState.battle_report = {
		"mode": "stalled",
		"region_id": "slum_edge",
		"progress": 100.0,
		"progress_gain": 0.0,
		"power": 9.0,
		"pressure": 14.0,
		"field_total": 6,
		"reinforced": 0,
		"lost": 0,
		"returned": 0,
		"retreat_value": 4,
		"retreat_field_before": 6,
		"preserved_loss_estimate": 2,
		"loss_reason": "enemy_pressure",
		"front_motion": "back",
		"cause": "need_reserve"
	}
	GameState.set_feedback("推进停滞：我方 9.0 / 敌压 14.0。可撤离保全。")

	var main = MainScript.new()
	main.ConfigDB = ConfigDB
	main.GameState = GameState
	main.SaveService = SaveService
	main.SimulationService = SimulationService
	var snapshot: Dictionary = main.call("_battlefield_snapshot")
	_assert(String(snapshot.get("mode", "")) == "complete", "100 percent current region should present a completed battlefield state")
	_assert(String(snapshot.get("next_region_id", "")) == "factory_wall", "completed battlefield snapshot should expose the next unlocked region")
	_assert(String(snapshot.get("next_region_name", "")) != "", "completed battlefield snapshot should expose next region display name")
	_assert(int(snapshot.get("retreat_value", -1)) == 0, "completed battlefield must not advertise retreat preservation")
	_assert(int(snapshot.get("retreat_field_before", -1)) == 0, "completed battlefield must not expose retreat field count")
	var visual_state: Dictionary = main.call("_battle_visual_state", snapshot)
	var status_text: String = String(visual_state.get("status_text", ""))
	_assert(status_text.find("已吞噬") >= 0, "completed battlefield status strip should announce completion")
	_assert(status_text.find("压制") == -1 and status_text.find("撤离") == -1, "completed battlefield status strip must not look like an active fight")
	var feedback_text: String = main.call("_display_feedback", snapshot)
	_assert(feedback_text.find("已吞噬") >= 0 and feedback_text.find("切换") >= 0, "completed battlefield feedback should point to next-line switching")
	_assert(feedback_text.find("撤离") == -1 and feedback_text.find("压制") == -1, "completed battlefield feedback should suppress stale combat wording")
	main.call("_on_battlefield_command", "next_region")
	_assert(GameState.active_region == "factory_wall", "completed battlefield command should switch to the next unlocked defense line through SimulationService")
	main.free()

	var view = BattlefieldViewScript.new()
	view.set_snapshot({
		"mode": "stalled",
		"returned": 0,
		"retreat_value": 4,
		"retreat_field_before": 6,
		"preserved_loss_estimate": 2
	})
	_assert(int(view.call("_retreat_badge_visible_return")) == 4, "test setup should create a held retreat badge before completion")
	view.set_snapshot({
		"mode": "complete",
		"next_region_id": "factory_wall",
		"next_region_name": "废弃工厂防线",
		"returned": 0,
		"retreat_value": 0,
		"retreat_field_before": 0
	})
	_assert(int(view.call("_retreat_badge_visible_return")) == 0, "completed battlefield should clear held retreat badges")
	var emitted: Array[String] = []
	view.command_requested.connect(func(action: String) -> void:
		emitted.append(action)
	)
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = Vector2(250.0, 110.0)
	view.call("_gui_input", event)
	_assert(emitted.size() == 1 and emitted[0] == "next_region", "completed battlefield click should emit next-region command")
	var meter_y := 212.0
	_assert(float(view.call("_target_marker_line_bottom", meter_y)) < float(view.call("_bottom_readout_y", meter_y)), "target marker line must stay above bottom readout text")
	_assert(float(view.call("_target_marker_label_y", meter_y)) < float(view.call("_bottom_readout_y", meter_y)), "target marker label must stay above bottom readout text")
	_assert(float(view.call("_bottom_readout_y", meter_y)) - float(view.call("_target_marker_line_bottom", meter_y)) >= 36.0, "target marker should stay visibly separated from bottom readout")
	view.free()

func _test_factory_entry_supply_idempotent() -> void:
	GameState.reset_new_game(false)
	GameState.ensure_config_defaults()
	GameState.resources = {"pulp": 0.0, "enzyme": 0.0, "helix": 0.0, "larva": 0.0, "mutation": 0.0}
	GameState.reserves["hydralisk"] = 0
	GameState.field_units["hydralisk"] = 0
	GameState.region_progress["slum_edge"] = 100.0
	GameState.total_devour = 100.0
	GameState.region_unlocked["factory_wall"] = true
	GameState.ensure_config_defaults()
	var before: Dictionary = GameState.to_dict().duplicate(true)
	_assert(SimulationService.select_region("factory_wall"), "entry supply idempotent setup should select factory")
	_assert(bool(GameState.region_entry_staged.get("factory_wall", false)), "entry supply should mark factory as staged")
	_assert(bool(GameState.plugins_owned.get("piercing_spines", false)), "entry supply should purchase piercing_spines")
	_assert(GameState.equipped_plugin == "piercing_spines", "entry supply should equip piercing_spines")
	_assert(float(GameState.resources.get("pulp", 0.0)) >= 78.0, "entry supply should floor pulp for three hydralisks")
	_assert(float(GameState.resources.get("enzyme", 0.0)) >= 12.0, "entry supply should floor enzyme for three hydralisks")
	_assert(float(GameState.resources.get("larva", 0.0)) >= 3.0, "entry supply should floor larvae for three hydralisks")
	_assert(float(GameState.resources.get("helix", 0.0)) == 0.0, "entry supply should spend the granted piercing_spines helix")
	_assert(int(GameState.reserves.get("hydralisk", -1)) == int(before["reserves"].get("hydralisk", 0)), "entry supply must not add hydralisk reserves directly")
	var after_first: Dictionary = GameState.to_dict().duplicate(true)
	GameState.active_region = "slum_edge"
	_assert(SimulationService.select_region("factory_wall"), "entry supply idempotent setup should re-enter factory")
	var after_second: Dictionary = GameState.to_dict().duplicate(true)
	_assert(_resources_equal(after_second["resources"], after_first["resources"]), "entry supply must not add resources on second entry")
	_assert(int(after_second["reserves"].get("hydralisk", 0)) == int(after_first["reserves"].get("hydralisk", 0)), "entry supply must not add reserves on second entry")
	_assert(bool(after_second["plugins_owned"].get("piercing_spines", false)) == bool(after_first["plugins_owned"].get("piercing_spines", false)), "entry supply must not change plugin ownership on second entry")
	_assert(String(after_second.get("equipped_plugin", "")) == String(after_first.get("equipped_plugin", "")), "entry supply must not change equipped plugin on second entry")

func _test_factory_entry_first_push_loop() -> void:
	GameState.reset_new_game(false)
	GameState.ensure_config_defaults()
	GameState.resources = {"pulp": 0.0, "enzyme": 0.0, "helix": 0.0, "larva": 0.0, "mutation": 0.0}
	GameState.region_progress["slum_edge"] = 100.0
	GameState.total_devour = 100.0
	GameState.region_unlocked["factory_wall"] = true
	GameState.ensure_config_defaults()
	_assert(SimulationService.select_region("factory_wall"), "factory wall should be selectable after first-line completion")
	_assert(GameState.active_region == "factory_wall", "factory entry test should switch to the second defense line")
	_assert(GameState.equipped_plugin == "piercing_spines", "factory entry should equip the real shield-counter plugin")
	_assert(float(GameState.resources.get("pulp", 0.0)) >= 78.0, "factory entry staging should floor pulp to a three-hydralisk wave")
	_assert(float(GameState.resources.get("enzyme", 0.0)) >= 12.0, "factory entry staging should floor enzyme to a three-hydralisk wave")
	_assert(float(GameState.resources.get("larva", 0.0)) >= 3.0, "factory entry staging should floor larvae to a three-hydralisk wave")
	var projection: Dictionary = SimulationService.battle_projection("hydralisk")
	_assert(int(projection.get("needed_reserve", 0)) == 3, "piercing hydralisk factory entry should expose exactly a three-unit first wave")
	_assert(int(projection.get("hatch_fill_count", 0)) >= 3, "factory first wave should be actionable from battlefield prepare")
	_assert(SimulationService.prepare_wave("hydralisk"), "factory prepare should hatch the staged hydralisk first wave")
	_assert(int(GameState.reserves.get("hydralisk", 0)) >= 3, "factory prepare should create real hydralisk reserve")
	_assert(SimulationService.assault_push("hydralisk"), "factory staged wave should commit through the normal assault path")
	SimulationService.simulate_seconds(3.0, true)
	var factory_advanced: bool = float(GameState.region_progress.get("factory_wall", 0.0)) > 0.0
	_assert(factory_advanced, "factory_advanced=true regression: second defense line should make real progress after staged first push")
	_assert(String(GameState.battle_report.get("mode", "")) == "advance", "factory first push should report a real advance, not a fixed completion")
	_assert(float(GameState.battle_report.get("power", 0.0)) > float(GameState.battle_report.get("pressure", 0.0)), "factory first push must advance because power exceeds pressure")

func _test_factory_public_battlefield_commands_use_hydralisk() -> void:
	GameState.reset_new_game(false)
	GameState.ensure_config_defaults()
	GameState.resources = {"pulp": 0.0, "enzyme": 0.0, "helix": 0.0, "larva": 0.0, "mutation": 0.0}
	GameState.reserves["zergling"] = 9
	GameState.reserves["hydralisk"] = 0
	GameState.field_units["zergling"] = 0
	GameState.field_units["hydralisk"] = 0
	GameState.region_progress["slum_edge"] = 100.0
	GameState.total_devour = 100.0
	GameState.region_unlocked["factory_wall"] = true
	GameState.ensure_config_defaults()
	_assert(SimulationService.select_region("factory_wall"), "factory public command setup should select factory")

	var main = MainScript.new()
	main.ConfigDB = ConfigDB
	main.GameState = GameState
	main.SaveService = SaveService
	main.SimulationService = SimulationService
	var snapshot: Dictionary = main.call("_battlefield_snapshot")
	_assert(String(snapshot.get("projection_unit_id", "")) == "hydralisk", "factory first screen should target hydralisk even when zerglings are ready")
	_assert(String(snapshot.get("projection_unit_name", "")) == "刺蛇", "factory first screen should name the hydralisk target")
	_assert(int(snapshot.get("prepared_reserve", -1)) == 0, "factory first screen should show hydralisk 0/3 before left prepare")
	_assert(int(snapshot.get("needed_reserve", -1)) == 3, "factory first screen should show hydralisk 0/3 target")
	var next_step: String = String(main.call("_next_step_text"))
	_assert(next_step.find("刺蛇 0/3") >= 0, "factory next-step copy should expose the hydralisk 0/3 target")
	_assert(next_step.find("穿刺脊突已装配") >= 0, "factory next-step copy should expose piercing spines equipment")

	var zergling_before: int = int(GameState.reserves.get("zergling", 0))
	main.call("_on_battlefield_command", "prepare")
	var left_prepares_hydra: bool = int(GameState.reserves.get("hydralisk", 0)) >= 3 and int(GameState.reserves.get("zergling", 0)) == zergling_before
	_assert(left_prepares_hydra, "left_prepares_hydra=true regression: factory left battlefield command should prepare hydralisks, not zerglings")
	main.call("_on_battlefield_command", "assault")
	_assert(int(GameState.deployment_intensity.get("hydralisk", 0)) == 3, "factory center assault should commit hydralisks")
	_assert(int(GameState.deployment_intensity.get("zergling", 0)) == 0, "factory center assault must not let ready zerglings steal the first push")
	SimulationService.simulate_seconds(3.0, true)
	_assert(int(GameState.field_units.get("hydralisk", 0)) > 0, "factory public command push should put hydralisks on the field")
	_assert(float(GameState.region_progress.get("factory_wall", 0.0)) > 0.0, "factory public command push should advance the factory")
	_assert(float(GameState.battle_report.get("power", 0.0)) > float(GameState.battle_report.get("pressure", 0.0)), "factory public command push must advance because power exceeds pressure")
	main.free()

func _test_content_expansion_units_and_research_bastion() -> void:
	GameState.reset_new_game(false)
	GameState.ensure_config_defaults()
	_assert(ConfigDB.get_unit("baneling") != null, "content expansion should load baneling unit config")
	_assert(ConfigDB.get_unit("carapace_guard") != null, "content expansion should load carapace guard unit config")
	_assert(ConfigDB.get_region("research_bastion") != null, "content expansion should load research bastion region")
	_assert(ConfigDB.get_enemy("flame_turret") != null and ConfigDB.get_enemy("rail_sentry") != null, "content expansion should load new enemy pressure configs")

	GameState.resources = {"pulp": 999.0, "enzyme": 999.0, "helix": 999.0, "larva": 99.0, "mutation": 0.0}
	GameState.ensure_config_defaults()
	_assert(not SimulationService.hatch_unit("baneling", 1), "new baneling should be locked before its devour threshold")
	_assert(int(GameState.reserves.get("baneling", 0)) == 0, "locked baneling hatch must not add reserves")

	GameState.total_devour = 200.0
	GameState.region_progress["slum_edge"] = 100.0
	GameState.region_progress["factory_wall"] = 100.0
	GameState.region_unlocked["factory_wall"] = true
	GameState.region_unlocked["research_bastion"] = true
	GameState.active_region = "research_bastion"
	GameState.ensure_config_defaults()
	var baneling_projection: Dictionary = SimulationService.battle_projection("baneling")
	var guard_projection: Dictionary = SimulationService.battle_projection("carapace_guard")
	_assert(int(baneling_projection.get("needed_reserve", 0)) > 0, "baneling research projection should expose a real wave threshold")
	_assert(float(guard_projection.get("loss_rate", 1.0)) < float(baneling_projection.get("loss_rate", 0.0)), "carapace guard should expose a lower loss rate through toughness")
	_assert(SimulationService.prepare_wave("baneling"), "research bastion left prepare should hatch real baneling reserves")
	_assert(int(GameState.reserves.get("baneling", 0)) > 0, "baneling prepare should create reserve through real costs")
	_assert(SimulationService.assault_push("baneling"), "baneling should commit through normal assault path")
	SimulationService.simulate_seconds(4.0, true)
	_assert(float(GameState.region_progress.get("research_bastion", 0.0)) > 0.0, "research bastion should advance from real baneling power")
	_assert(float(GameState.battle_report.get("power", 0.0)) > float(GameState.battle_report.get("pressure", 0.0)), "research bastion advance must come from power exceeding pressure")

	GameState.reset_new_game(false)
	GameState.ensure_config_defaults()
	GameState.resources = {"pulp": 999.0, "enzyme": 999.0, "helix": 999.0, "larva": 99.0, "mutation": 0.0}
	GameState.total_devour = 200.0
	GameState.region_unlocked["research_bastion"] = true
	GameState.active_region = "research_bastion"
	GameState.ensure_config_defaults()
	_assert(SimulationService.prepare_wave("carapace_guard"), "carapace guard should prepare through real hatch costs")
	_assert(int(GameState.reserves.get("carapace_guard", 0)) > 0, "carapace guard prepare should create reserve")
	_assert(SimulationService.assault_push("carapace_guard"), "carapace guard should commit through normal assault path")
	SimulationService.simulate_seconds(4.0, true)
	_assert(float(GameState.region_progress.get("research_bastion", 0.0)) > 0.0, "carapace guard should advance the research bastion through real combat")
	_assert(float(GameState.battle_report.get("power", 0.0)) > float(GameState.battle_report.get("pressure", 0.0)), "carapace guard advance must come from power exceeding pressure")

	GameState.reset_new_game(false)
	GameState.ensure_config_defaults()
	GameState.resources = {"pulp": 999.0, "enzyme": 999.0, "helix": 999.0, "larva": 99.0, "mutation": 0.0}
	GameState.total_devour = 200.0
	GameState.region_progress["factory_wall"] = 100.0
	GameState.region_unlocked["factory_wall"] = true
	GameState.region_unlocked["research_bastion"] = true
	GameState.active_region = "factory_wall"
	GameState.ensure_config_defaults()
	var main = MainScript.new()
	main.ConfigDB = ConfigDB
	main.GameState = GameState
	main.SaveService = SaveService
	main.SimulationService = SimulationService
	var factory_complete_snapshot: Dictionary = main.call("_battlefield_snapshot")
	_assert(String(factory_complete_snapshot.get("mode", "")) == "complete", "completed factory should present completion state before the new line")
	_assert(String(factory_complete_snapshot.get("next_region_id", "")) == "research_bastion", "completed factory should expose research bastion as the next public line")
	main.call("_on_battlefield_command", "next_region")
	_assert(GameState.active_region == "research_bastion", "public battlefield next-line click should enter research bastion")
	var next_step: String = String(main.call("_next_step_text"))
	_assert(next_step.find("爆裂虫") >= 0 and next_step.find("甲壳卫士") >= 0, "research bastion first-screen guidance should name both new roles")
	main.free()

func _test_mobile_readability_and_completed_factory_guidance() -> void:
	GameState.reset_new_game(false)
	GameState.ensure_config_defaults()
	GameState.resources = {"pulp": 999.0, "enzyme": 999.0, "helix": 999.0, "larva": 99.0, "mutation": 0.0}
	GameState.total_devour = 200.0
	GameState.region_progress["slum_edge"] = 100.0
	GameState.region_progress["factory_wall"] = 100.0
	GameState.region_unlocked["factory_wall"] = true
	GameState.region_unlocked["research_bastion"] = true
	GameState.active_region = "factory_wall"
	GameState.ensure_config_defaults()

	var main = MainScript.new()
	main.ConfigDB = ConfigDB
	main.GameState = GameState
	main.SaveService = SaveService
	main.SimulationService = SimulationService
	main.size = Vector2(540, 960)
	root.add_child(main)
	main.call("_refresh")

	var scroll := _find_scroll_container(main)
	_assert(scroll != null, "mobile readability regression should find the public scroll container")
	if scroll != null:
		_assert(scroll.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED, "540-wide UI should not expose horizontal scrolling")
	var next_step: String = String(main.call("_next_step_text"))
	_assert(next_step.find("点击战场切换研究堡垒外环") >= 0, "completed factory top guidance should prioritize switching to research bastion")
	_assert(next_step.find("推进工厂") < 0, "completed factory top guidance must not keep stale hydralisk factory assault copy")
	var unit_buttons: Dictionary = main.get("_unit_buttons")
	var baneling_button: Button = unit_buttons.get("baneling", null)
	var guard_button: Button = unit_buttons.get("carapace_guard", null)
	_assert(baneling_button != null and baneling_button.text.find("高推进/高损耗") >= 0, "baneling mobile label should expose the short role tag")
	_assert(guard_button != null and guard_button.text.find("稳推进/低损耗") >= 0, "carapace guard mobile label should expose the short role tag")
	if baneling_button != null:
		_assert(baneling_button.autowrap_mode == TextServer.AUTOWRAP_ARBITRARY, "unit hatch buttons should wrap instead of widening the 540px layout")
	main.queue_free()

func _find_scroll_container(node: Node) -> ScrollContainer:
	if node is ScrollContainer:
		return node
	for child in node.get_children():
		var found := _find_scroll_container(child)
		if found != null:
			return found
	return null

func _test_plugin_ab_comparison() -> void:
	GameState.resources["helix"] = 20.0
	_assert(SimulationService.buy_or_equip_plugin("piercing_spines"), "plugin should be buyable with helix")
	_assert(GameState.equipped_plugin == "piercing_spines", "plugin should become equipped")

	var baseline_progress := _simulate_factory_push("")
	var piercing_progress := _simulate_factory_push("piercing_spines")
	_assert(piercing_progress > baseline_progress, "piercing_spines should produce higher factory progress than identical no-plugin state")
	_assert(piercing_progress - baseline_progress >= 5.0, "piercing_spines should create a meaningful progress delta")

func _simulate_factory_push(plugin_id: String) -> float:
	GameState.reset_new_game(false)
	GameState.ensure_config_defaults()
	GameState.resources["pulp"] = 300.0
	GameState.resources["enzyme"] = 80.0
	GameState.resources["helix"] = 20.0
	GameState.resources["larva"] = 30.0
	GameState.plugins_owned = {}
	GameState.equipped_plugin = ""
	if plugin_id != "":
		_assert(SimulationService.buy_or_equip_plugin(plugin_id), "plugin should be affordable in A/B setup: %s" % plugin_id)
	_assert(SimulationService.hatch_unit("hydralisk", 6), "hydralisk hatch should succeed in A/B setup")
	GameState.region_unlocked["factory_wall"] = true
	GameState.active_region = "factory_wall"
	SimulationService.set_deployment("hydralisk", 3)
	var before_factory := float(GameState.region_progress["factory_wall"])
	SimulationService.simulate_seconds(10.0, true)
	return float(GameState.region_progress["factory_wall"]) - before_factory

func _test_offline_cap() -> void:
	GameState.reset_new_game(false)
	GameState.ensure_config_defaults()
	var report: Dictionary = SimulationService.settle_offline(60.0 * 60.0 * 24.0)
	_assert(bool(report["capped"]), "offline report should mark cap when exceeding 12 hours")
	_assert(is_equal_approx(float(report["seconds"]), float(SimulationService.OFFLINE_CAP_SECONDS)), "offline duration should cap at 12 hours")

func _test_save_integrity() -> void:
	GameState.reset_new_game(false)
	GameState.ensure_config_defaults()
	GameState.resources = {"pulp": 222.0, "enzyme": 33.0, "helix": 11.0, "larva": 7.0, "mutation": 2.0}
	GameState.organ_levels["deep_roots"] = 3
	GameState.reserves["zergling"] = 9
	GameState.field_units["hydralisk"] = 4
	GameState.deployment_intensity["hydralisk"] = 2
	GameState.plugins_owned["piercing_spines"] = true
	GameState.equipped_plugin = "piercing_spines"
	GameState.region_progress["slum_edge"] = 42.5
	GameState.region_unlocked["factory_wall"] = true
	GameState.active_region = "factory_wall"
	GameState.total_devour = 42.5
	GameState.total_kills = 13
	GameState.reset_count = 2
	_assert(SaveService.save_game(), "save should write current state")
	var saved: Dictionary = GameState.to_dict().duplicate(true)
	GameState.reset_new_game(false)
	_assert(SaveService.load_game(), "load should read saved state")
	_assert(_resources_equal(GameState.resources, saved["resources"]), "load should restore all resources")
	_assert(int(GameState.organ_levels["deep_roots"]) == 3, "load should restore organ levels")
	_assert(int(GameState.reserves["zergling"]) == 9, "load should restore reserves")
	_assert(int(GameState.field_units["hydralisk"]) == 4, "load should restore field units")
	_assert(int(GameState.deployment_intensity["hydralisk"]) == 2, "load should restore deployment intensity")
	_assert(bool(GameState.plugins_owned["piercing_spines"]), "load should restore plugin ownership")
	_assert(GameState.equipped_plugin == "piercing_spines", "load should restore equipped plugin")
	_assert(is_equal_approx(float(GameState.region_progress["slum_edge"]), 42.5), "load should restore region progress")
	_assert(bool(GameState.region_unlocked["factory_wall"]), "load should restore region unlocks")
	_assert(GameState.active_region == "factory_wall", "load should restore active region")
	_assert(is_equal_approx(GameState.total_devour, 42.5), "load should restore total devour")
	_assert(GameState.total_kills == 13, "load should restore total kills")
	_assert(GameState.reset_count == 2, "load should restore reset count")
	_assert(int(GameState.last_save_unix) > 0, "load should restore last save timestamp")

func _test_prestige_preview_and_reset_state() -> void:
	GameState.reset_new_game(false)
	GameState.ensure_config_defaults()
	GameState.resources = {"pulp": 400.0, "enzyme": 80.0, "helix": 45.0, "larva": 30.0, "mutation": 1.0}
	GameState.organ_levels["deep_roots"] = 2
	GameState.reserves["zergling"] = 8
	GameState.field_units["hydralisk"] = 3
	GameState.deployment_intensity["hydralisk"] = 2
	GameState.battle_report = {"mode": "stalled", "region_id": "factory_wall", "progress": 25.0, "progress_gain": 0.0, "power": 3.0, "pressure": 30.0, "field_total": 3, "reinforced": 0, "lost": 1}
	GameState.plugins_owned["piercing_spines"] = true
	GameState.equipped_plugin = "piercing_spines"
	GameState.region_progress["slum_edge"] = 25.0
	GameState.region_unlocked["factory_wall"] = true
	GameState.active_region = "factory_wall"
	GameState.total_devour = max(GameState.total_devour, 25.0)
	var preview: Dictionary = SimulationService.prestige_preview()
	var mutation_before := int(GameState.resources["mutation"])
	var reset_count_before: int = GameState.reset_count
	_assert(int(preview["gain"]) > 0, "prestige preview should show gain after progress")
	_assert(SimulationService.perform_prestige(), "prestige should execute when preview gain is positive")
	_assert(int(GameState.resources["mutation"]) == mutation_before + int(preview["gain"]), "prestige actual gain should match preview")
	_assert(GameState.reset_count == reset_count_before + 1, "prestige should increment reset count")
	_assert(GameState.active_region == "slum_edge", "prestige should reset active region")
	_assert(GameState.equipped_plugin == "", "prestige should clear equipped plugin")
	_assert(GameState.plugins_owned.is_empty(), "prestige should clear plugin ownership")
	_assert(int(GameState.reserves["zergling"]) == 0 and int(GameState.field_units["hydralisk"]) == 0, "prestige should clear reserves and field units")
	_assert(int(GameState.deployment_intensity["hydralisk"]) == 0, "prestige should clear deployment intensity")
	_assert(is_equal_approx(float(GameState.region_progress["slum_edge"]), 0.0), "prestige should clear region progress")
	_assert(not bool(GameState.region_unlocked["factory_wall"]), "prestige should relock later regions")
	_assert(int(GameState.organ_levels["mucus_fronds"]) == 1, "prestige should keep only baseline mucus fronds organ")
	_assert(String(GameState.battle_report.get("mode", "")) == "idle", "prestige should clear temporary battle visual report")

func _all_resources_non_negative() -> bool:
	for id in GameState.RESOURCE_IDS:
		if float(GameState.resources.get(id, 0.0)) < 0.0:
			return false
	return true

func _resources_equal(left: Dictionary, right: Dictionary) -> bool:
	for id in GameState.RESOURCE_IDS:
		if not is_equal_approx(float(left.get(id, 0.0)), float(right.get(id, 0.0))):
			return false
	return true

func _assert(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
