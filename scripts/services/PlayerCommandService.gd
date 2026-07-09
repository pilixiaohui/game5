extends RefCounted

var ConfigDB
var GameState
var SaveService
var SimulationService

func configure(config_db, game_state, save_service, simulation_service):
	ConfigDB = config_db
	GameState = game_state
	SaveService = save_service
	SimulationService = simulation_service
	return self

func purchase_organ(organ_id: String) -> bool:
	return SimulationService.purchase_organ(organ_id)

func hatch_unit(unit_id: String, count: int = 1) -> bool:
	return SimulationService.hatch_unit(unit_id, count)

func select_region(region_id: String) -> bool:
	return SimulationService.select_region(region_id)

func set_deployment(unit_id: String, intensity: int) -> void:
	SimulationService.set_deployment(unit_id, intensity)

func retreat() -> void:
	SimulationService.retreat()

func buy_or_equip_plugin(plugin_id: String) -> bool:
	return SimulationService.buy_or_equip_plugin(plugin_id)

func perform_prestige() -> bool:
	return SimulationService.perform_prestige()

func prepare_wave(unit_id: String) -> bool:
	return SimulationService.prepare_wave(unit_id)

func assault_push(unit_id: String) -> bool:
	return SimulationService.assault_push(unit_id)

func save_now() -> bool:
	if SaveService.save_game():
		GameState.set_feedback("存档完成。")
		return true
	GameState.set_feedback(SaveService.last_error)
	return false

func load_and_settle() -> void:
	SaveService.load_game()
	SimulationService.settle_offline_from_save()
	GameState.set_feedback("已读取存档并结算离线收益。")

func new_game_and_save() -> void:
	GameState.reset_new_game(false)
	SaveService.save_game()
