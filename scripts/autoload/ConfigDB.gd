extends Node

var organs: Dictionary = {}
var units: Dictionary = {}
var enemies: Dictionary = {}
var plugins: Dictionary = {}
var regions: Dictionary = {}

const ORGAN_PATHS: Array[String] = [
	"res://data/organs/mucus_fronds.tres",
	"res://data/organs/deep_roots.tres",
	"res://data/organs/acid_fountain.tres",
	"res://data/organs/ferment_sac.tres",
	"res://data/organs/reflux_pump.tres",
	"res://data/organs/neural_spire.tres"
]
const UNIT_PATHS: Array[String] = [
	"res://data/units/zergling.tres",
	"res://data/units/hydralisk.tres",
	"res://data/units/baneling.tres",
	"res://data/units/carapace_guard.tres"
]
const ENEMY_PATHS: Array[String] = [
	"res://data/enemies/rifleman.tres",
	"res://data/enemies/shield_guard.tres",
	"res://data/enemies/flame_turret.tres",
	"res://data/enemies/rail_sentry.tres"
]
const PLUGIN_PATHS: Array[String] = [
	"res://data/plugins/piercing_spines.tres",
	"res://data/plugins/acid_carapace.tres"
]
const REGION_PATHS: Array[String] = [
	"res://data/regions/slum_edge.tres",
	"res://data/regions/factory_wall.tres",
	"res://data/regions/research_bastion.tres"
]

func _ready() -> void:
	load_all()

func load_all() -> void:
	organs = _load_index(ORGAN_PATHS)
	units = _load_index(UNIT_PATHS)
	enemies = _load_index(ENEMY_PATHS)
	plugins = _load_index(PLUGIN_PATHS)
	regions = _load_index(REGION_PATHS)

func ensure_loaded() -> void:
	if organs.is_empty() or units.is_empty() or regions.is_empty():
		load_all()

func _load_index(paths: Array[String]) -> Dictionary:
	var indexed: Dictionary = {}
	for path in paths:
		var resource := load(path)
		if resource == null:
			push_warning("Missing config: %s" % path)
			continue
		if resource.id == "":
			push_warning("Config without id: %s" % path)
			continue
		indexed[resource.id] = resource
	return indexed

func get_organ(id: String):
	ensure_loaded()
	return organs.get(id)

func get_unit(id: String):
	ensure_loaded()
	return units.get(id)

func get_enemy(id: String):
	ensure_loaded()
	return enemies.get(id)

func get_plugin(id: String):
	ensure_loaded()
	return plugins.get(id)

func get_region(id: String):
	ensure_loaded()
	return regions.get(id)
