extends SceneTree

var session: Node
var failures: Array[String] = []
var assertions := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	session = root.get_node("GameSession")
	_run_test("INV-STRUCTURE reservation cancellation is lossless", _test_build_cancel_refunds_without_side_effects)
	_run_test("INV-ROOM-GROUP adjacency derives one merged group", _test_adjacent_rooms_merge_without_duplicate_state)
	_run_test("INV-ASSAULT all mobile combat units move atomically", _test_attack_and_retreat_preserve_unique_location)
	_run_test("INV-CANDIDATE one selection consumes one group", _test_candidate_group_is_single_choice)
	_run_test("INV-RANDOM same seed and save reload remain stable", _test_seed_and_save_are_deterministic)
	_run_test("INV-SCALE million units remain one compact batch", _test_million_unit_state_is_compact)
	_run_test("RELEASE-HEALTH first-hour loop reaches the unique exit", _test_first_hour_release_health)
	if failures.is_empty():
		print("TESTS_OK cases=7 assertions=%d" % assertions)
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("TESTS_FAILED cases=7 assertions=%d failures=%d" % [assertions, failures.size()])
		quit(1)

func _run_test(name: String, test: Callable) -> void:
	var before := failures.size()
	test.call()
	if failures.size() == before:
		print("PASS %s" % name)

func _test_build_cancel_refunds_without_side_effects() -> void:
	session.new_game(101)
	var before := float(session.state.resources.biomass)
	_assert_true(session.build_room(0, "thermal_metabolism"), "building a known room should be accepted")
	_assert_equal(float(session.state.resources.biomass), before - 38.0, "build must reserve the exact structure cost")
	session.advance_steps(3)
	_assert_true(session.cancel_room(0), "unfinished build should be cancellable")
	_assert_equal(float(session.state.resources.biomass), before, "cancellation must release the full reserved biomass")
	_assert_equal(String(session.state.rooms[0].kind), "", "cancelled slot must be empty")
	_assert_false(session.cancel_room(0), "retrying cancellation must be rejected")
	_assert_equal(float(session.state.resources.biomass), before, "rejected retry must not duplicate the refund")

func _test_adjacent_rooms_merge_without_duplicate_state() -> void:
	session.new_game(202)
	_assert_true(session.build_room(0, "biomass_filter"), "first compatible room should build")
	_assert_true(session.build_room(1, "biomass_filter"), "second adjacent compatible room should build")
	session.advance_steps(12)
	var matching_groups := 0
	var matching_slots := 0
	for group in session.room_groups():
		if group.kind == "biomass_filter":
			matching_groups += 1
			matching_slots += group.slots.size()
	_assert_equal(matching_groups, 1, "adjacent compatible modules must derive one group")
	_assert_equal(matching_slots, 2, "the group projection must retain both module identities")
	_assert_true(session.state.milestones.has("FH-004"), "actual adjacency must record the merge milestone")
	_assert_equal(String(session.state.rooms[0].kind), "biomass_filter", "projection must not delete the first module")
	_assert_equal(String(session.state.rooms[1].kind), "biomass_filter", "projection must not delete the second module")

func _test_attack_and_retreat_preserve_unique_location() -> void:
	session.new_game(303)
	session.state.units.biter = 16
	session.state.units.root_spore = 4
	_assert_true(session.attack_node("C"), "observed adjacent node should accept an assault")
	_assert_equal(int(session.state.units.biter), 0, "assault must remove every biter from the army ledger")
	_assert_equal(int(session.state.units.root_spore), 0, "assault must remove every mobile spore from the army ledger")
	_assert_equal(int(session.state.active_battle.biter), 16, "active node must own the exact committed biter batch")
	_assert_equal(int(session.state.active_battle.spore), 4, "active node must own the exact committed spore batch")
	_assert_false(session.attack_node("B"), "a second active battle must be rejected")
	session.advance_steps(2)
	var survivors_before := int(session.state.active_battle.biter) + int(session.state.active_battle.spore)
	_assert_true(session.retreat(), "active battle should retreat atomically")
	_assert_true(session.state.active_battle.is_empty(), "retreat must clear the active battle transaction")
	_assert_equal(int(session.state.units.biter) + int(session.state.units.root_spore), survivors_before, "every surviving mobile unit must return exactly once")
	_assert_true(int(session.state.units.root_mat) >= 1, "already rooted spores must remain fixed rather than becoming mobile again")
	_assert_true(session.state.milestones.has("FH-007"), "retreat must record persistent-node re-entry evidence")

func _test_candidate_group_is_single_choice() -> void:
	session.new_game(404)
	session.state.resources.genes = 40.0
	session.state.candidate_group = {"id": "fixture", "kind": "first", "source": "test", "options": [session.CANDIDATES[0].duplicate(true), session.CANDIDATES[1].duplicate(true), session.CANDIDATES[2].duplicate(true)]}
	var chosen: Dictionary = session.state.candidate_group.options[0]
	var before := float(session.state.resources.genes)
	_assert_true(session.select_candidate(chosen.id), "one member of the held group should be selectable")
	_assert_equal(session.state.mutations.size(), 1, "selection must create exactly one assimilated mutation")
	_assert_equal(float(session.state.resources.genes), before - float(chosen.cost), "selection must pay the public cost once")
	_assert_true(session.state.candidate_group.is_empty(), "selection must consume the whole group")
	_assert_false(session.select_candidate(chosen.id), "the consumed group cannot be selected again")
	_assert_equal(session.state.mutations.size(), 1, "rejected duplicate selection must not duplicate a mutation")

func _test_seed_and_save_are_deterministic() -> void:
	session.new_game(505)
	var first_nodes := JSON.stringify(session.state.nodes)
	session.new_game(505)
	_assert_equal(JSON.stringify(session.state.nodes), first_nodes, "same seed must commit the same full node content")
	session.new_game(506)
	_assert_not_equal(JSON.stringify(session.state.nodes), first_nodes, "different seed should alter committed encounter values")
	session.new_game(505)
	_assert_true(session.build_room(0, "thermal_metabolism"), "save fixture room should build")
	session.advance_steps(5)
	var saved_snapshot: Dictionary = session.snapshot()
	var path := "user://tests/determinism_slot.json"
	_assert_true(session.save_game(path), "save must atomically write a complete snapshot")
	session.state.seed = 999
	session.state.nodes[1].enemy = 999
	_assert_true(session.load_game(path), "saved snapshot must load through the production repository")
	_assert_equal(int(session.state.seed), int(saved_snapshot.seed), "load must restore the saved seed")
	_assert_equal(int(session.state.nodes[1].enemy), int(saved_snapshot.nodes[1].enemy), "load must restore committed hidden encounter state")
	_assert_equal(String(session.state.rooms[0].kind), "thermal_metabolism", "load must restore in-flight structure state")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path + ".bak"))

func _test_million_unit_state_is_compact() -> void:
	session.new_game(606)
	session.state.units.biter = 1000000
	var serialized_size := JSON.stringify(session.state).to_utf8_buffer().size()
	_assert_true(serialized_size < 100000, "million-unit batch must not expand into per-unit serialized objects")
	_assert_true(session.attack_node("C"), "million-unit batch should use the same assault command")
	_assert_equal(int(session.state.active_battle.biter), 1000000, "the exact quantity must cross the ownership boundary")
	_assert_equal(int(session.state.units.biter), 0, "army ledger must not retain a shadow million-unit copy")
	session.advance_steps(1)
	_assert_true(session.state.active_battle.is_empty(), "compact batch should resolve the small fixture without per-unit iteration")
	_assert_equal(int(session.state.units.biter), 1000000, "surviving batch must return with exact quantity")

func _test_first_hour_release_health() -> void:
	session.new_game(707)
	session.state.resources.biomass = 2000.0
	session.state.processing.field_organic = 1000.0
	_assert_true(session.build_room(0, "thermal_metabolism"), "release flow needs power")
	_assert_true(session.build_room(1, "biomass_filter"), "release flow needs biomass formation")
	_assert_true(session.build_room(2, "biomass_filter"), "release flow exercises room merging")
	_assert_true(session.build_room(4, "embryo_hatchery"), "release flow needs continuous unit formation")
	session.advance_steps(170)
	_assert_true(int(session.state.units.biter) >= 15, "hatchery must form a viable biter force")
	_assert_true(int(session.state.units.root_spore) >= 4, "hatchery must form a distinct root-spore force")
	_assert_true(session.attack_node("B"), "resource branch should be reachable from the hive")
	session.advance_steps(2)
	_assert_true(session.retreat(), "release flow must exercise atomic retreat")
	_assert_true(session.attack_node("B"), "the same persistent node should accept re-entry")
	_drive_battle()
	_assert_true(session.node_by_id("B").owned, "resource node should become safe territory")
	session.advance_steps(8)
	_assert_true(session.state.unlocks.digestive_pool, "secured battle remains must unlock digestion")
	_assert_true(session.build_room(8, "digestive_pool"), "digestive pool should build after carcass discovery")
	session.advance_steps(25)
	_assert_true(session.attack_node("W"), "sample branch should be reachable after B")
	_drive_battle()
	_assert_true(session.node_by_id("W").owned, "fixed sample node should be captured")
	session.advance_steps(18)
	_assert_true(session.state.unlocks.synapse_analyzer, "sample separation must unlock the analyzer")
	_assert_true(session.build_room(9, "synapse_analyzer"), "analyzer should build after sample separation")
	session.advance_steps(24)
	_assert_false(session.state.candidate_group.is_empty(), "analyzer must form the first protected candidate group")
	var first: Dictionary = session.state.candidate_group.options[0]
	_assert_true(session.select_candidate(first.id), "first group must support one paid assimilation")
	_assert_true(session.build_room(10, "mutation_culture"), "first mutation must unlock the culture room")
	session.advance_steps(16)
	_assert_true(session.induce_candidate(), "active induction must form an ordinary group")
	var ordinary: Dictionary = session.state.candidate_group.options[0]
	_assert_true(session.select_candidate(ordinary.id), "ordinary group must support one paid assimilation")
	_assert_true(session.attack_node("X"), "sample branch must provide a legal route to the unique exit")
	_drive_battle(220)
	_assert_true(session.node_by_id("X").owned, "unique exit must be capturable")
	_assert_true(session.state.adjacent_region.unlocked, "exit capture must reveal only the adjacent region summary")
	for id in ["FH-001", "FH-002", "FH-003", "FH-004", "FH-005", "FH-006", "FH-007", "FH-008", "FH-009", "FH-010", "FH-011", "FH-012", "FH-013", "FH-014"]:
		_assert_true(session.state.milestones.has(id), "release flow must produce milestone %s from gameplay events" % id)
	_assert_equal(session.state.mutations.size(), 2, "first and ordinary groups must each contribute one mutation")
	_assert_true(session.ascension_preview().points > 0, "same save snapshot must produce a numeric ascension preview")

func _drive_battle(max_steps: int = 160) -> void:
	var steps := 0
	while not session.state.active_battle.is_empty() and steps < max_steps:
		session.advance_steps(1)
		steps += 1
	_assert_true(session.state.active_battle.is_empty(), "battle fixture must converge within its step budget")

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

func _assert_not_equal(actual: Variant, expected: Variant, message: String) -> void:
	assertions += 1
	if actual == expected:
		failures.append("%s (both=%s)" % [message, actual])
