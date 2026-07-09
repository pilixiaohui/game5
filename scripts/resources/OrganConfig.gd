class_name OrganConfig
extends Resource

@export var id: String = ""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var cost_resource: String = "pulp"
@export var base_cost: float = 10.0
@export var cost_growth: float = 1.16
@export var production_resource: String = "pulp"
@export var base_rate: float = 1.0
@export var rate_growth: float = 1.12

func cost_for_level(current_level: int) -> float:
	return floor(base_cost * pow(cost_growth, max(current_level, 0)))

func rate_for_level(current_level: int, mutation_multiplier: float = 1.0) -> float:
	if current_level <= 0:
		return 0.0
	return base_rate * pow(rate_growth, current_level - 1) * mutation_multiplier
