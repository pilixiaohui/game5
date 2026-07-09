class_name BattleDirector
extends Node

signal battle_tick(region_id: String, progress: float)

func apply_macro_tick(seconds: float) -> void:
	SimulationService.simulate_seconds(seconds, true)
	battle_tick.emit(GameState.active_region, GameState.region_progress.get(GameState.active_region, 0.0))
