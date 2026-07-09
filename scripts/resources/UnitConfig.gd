class_name UnitConfig
extends Resource

@export var id: String = ""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var larva_cost: int = 1
@export var pulp_cost: float = 10.0
@export var enzyme_cost: float = 0.0
@export var helix_cost: float = 0.0
@export var unlock_devour: float = 0.0
@export var hatch_seconds: float = 3.0
@export var power: float = 1.0
@export var toughness: float = 1.0
@export var damage_tag: String = "physical"
@export var deployment_batch: int = 3

func resource_costs() -> Dictionary:
	return {
		"pulp": pulp_cost,
		"enzyme": enzyme_cost,
		"helix": helix_cost,
		"larva": float(larva_cost)
	}
