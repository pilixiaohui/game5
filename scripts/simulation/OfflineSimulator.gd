class_name OfflineSimulator
extends RefCounted

func settle(seconds: float) -> Dictionary:
	return SimulationService.settle_offline(seconds)
