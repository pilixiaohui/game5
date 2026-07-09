class_name PluginConfig
extends Resource

@export var id: String = ""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var sort_order: int = 0
@export var target_unit: String = ""
@export var cost_helix: float = 0.0
@export var damage_bonus: float = 0.0
@export var survival_bonus: float = 0.0
@export var counter_tag: String = ""
@export var element_tag: String = ""
@export var status_ids: Array[String] = []
@export var build_slot: String = "primary"
@export var unlock_devour: float = 0.0
