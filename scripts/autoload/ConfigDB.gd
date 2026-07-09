extends Node

var organs: Dictionary = {}
var units: Dictionary = {}
var enemies: Dictionary = {}
var plugins: Dictionary = {}
var regions: Dictionary = {}

const ORGAN_DIR := "res://data/organs"
const UNIT_DIR := "res://data/units"
const ENEMY_DIR := "res://data/enemies"
const PLUGIN_DIR := "res://data/plugins"
const REGION_DIR := "res://data/regions"

func _ready() -> void:
	load_all()

func load_all() -> void:
	organs = _load_index_from_dir(ORGAN_DIR)
	units = _load_index_from_dir(UNIT_DIR)
	enemies = _load_index_from_dir(ENEMY_DIR)
	plugins = _load_index_from_dir(PLUGIN_DIR)
	regions = _load_index_from_dir(REGION_DIR)

func ensure_loaded() -> void:
	if organs.is_empty() or units.is_empty() or regions.is_empty():
		load_all()

func _load_index_from_dir(dir_path: String) -> Dictionary:
	var indexed: Dictionary = {}
	var paths := _resource_paths_in_dir(dir_path)
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

func _resource_paths_in_dir(dir_path: String) -> Array[String]:
	var paths: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_warning("Missing config directory: %s" % dir_path)
		return paths
	for file_name in dir.get_files():
		if file_name.ends_with(".tres") or file_name.ends_with(".res"):
			paths.append("%s/%s" % [dir_path, file_name])
	paths.sort()
	return paths

func get_organ_ids() -> Array[String]:
	ensure_loaded()
	return _sorted_ids(organs)

func get_unit_ids() -> Array[String]:
	ensure_loaded()
	return _sorted_ids(units)

func get_enemy_ids() -> Array[String]:
	ensure_loaded()
	return _sorted_ids(enemies)

func get_plugin_ids() -> Array[String]:
	ensure_loaded()
	return _sorted_ids(plugins)

func get_region_ids() -> Array[String]:
	ensure_loaded()
	return _sorted_ids(regions)

func _sorted_ids(index: Dictionary) -> Array[String]:
	var ids: Array[String] = []
	for id in index.keys():
		ids.append(String(id))
	ids.sort_custom(func(left_id: String, right_id: String) -> bool:
		return _sort_resource_before(index[left_id], index[right_id], left_id, right_id)
	)
	return ids

func _sort_resource_before(left, right, left_id: String, right_id: String) -> bool:
	var left_order := 0
	var right_order := 0
	if left != null:
		left_order = int(left.get("sort_order"))
	if right != null:
		right_order = int(right.get("sort_order"))
	if left_order == right_order:
		return left_id < right_id
	return left_order < right_order

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
