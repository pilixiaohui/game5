class_name MetabolismSimulator
extends RefCounted

func simulate(seconds: float) -> void:
	SimulationService.simulate_seconds(seconds, false)
