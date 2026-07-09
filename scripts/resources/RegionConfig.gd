class_name RegionConfig
extends Resource

@export var id: String = ""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var length: float = 100.0
@export var enemy_ids: Array[String] = []
@export var enemy_pressure: float = 12.0
@export var reward_pulp_per_progress: float = 4.0
@export var reward_enzyme_per_progress: float = 0.5
@export var unlock_at_devour: float = 0.0
@export var next_region: String = ""
