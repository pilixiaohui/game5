extends Node

signal state_changed
signal feedback_changed(message: String)
signal offline_report_ready(report: Dictionary)

var ConfigDB

const SAVE_VERSION := 1
const RESOURCE_IDS: Array[String] = ["pulp", "enzyme", "helix", "larva", "mutation"]

var resources: Dictionary = {}
var organ_levels: Dictionary = {}
var reserves: Dictionary = {}
var field_units: Dictionary = {}
var deployment_intensity: Dictionary = {}
var plugins_owned: Dictionary = {}
var equipped_plugin: String = ""
var region_progress: Dictionary = {}
var region_unlocked: Dictionary = {}
var region_entry_staged: Dictionary = {}
var active_region: String = "slum_edge"
var feedback: String = "蜂巢刚刚复苏：升级菌毯绒毛，孵化跳虫，再打开投放阀门。"
var offline_report: Dictionary = {}
var battle_report: Dictionary = {}
var total_devour: float = 0.0
var total_kills: int = 0
var reset_count: int = 0
var last_save_unix: int = 0

func _enter_tree() -> void:
	_bind_dependencies()

func _ready() -> void:
	_bind_dependencies()
	reset_new_game(false)

func _bind_dependencies() -> void:
	if ConfigDB == null and get_tree() != null and get_tree().root.has_node("ConfigDB"):
		ConfigDB = get_tree().root.get_node("ConfigDB")

func reset_new_game(keep_mutation: bool = true) -> void:
	var kept_mutation := float(resources.get("mutation", 0.0)) if keep_mutation else 0.0
	resources = {
		"pulp": 36.0 + kept_mutation * 4.0,
		"enzyme": 0.0,
		"helix": 0.0,
		"larva": 4.0,
		"mutation": kept_mutation
	}
	organ_levels = {"mucus_fronds": 1}
	reserves = {}
	field_units = {}
	deployment_intensity = {}
	plugins_owned = {}
	equipped_plugin = ""
	region_progress = {}
	region_unlocked = {"slum_edge": true}
	region_entry_staged = {}
	active_region = "slum_edge"
	battle_report = _empty_battle_report()
	total_devour = 0.0
	total_kills = 0
	if not keep_mutation:
		reset_count = 0
	last_save_unix = Time.get_unix_time_from_system()
	feedback = "新蜂巢已建立：原浆自动增长，先升级器官并孵化储备。"
	offline_report = {}
	state_changed.emit()
	feedback_changed.emit(feedback)

func ensure_config_defaults() -> void:
	ConfigDB.ensure_loaded()
	for resource_id in RESOURCE_IDS:
		if not resources.has(resource_id):
			resources[resource_id] = 0.0
	for organ_id in ConfigDB.organs.keys():
		if not organ_levels.has(organ_id):
			organ_levels[organ_id] = 0
	for unit_id in ConfigDB.units.keys():
		if not reserves.has(unit_id):
			reserves[unit_id] = 0
		if not field_units.has(unit_id):
			field_units[unit_id] = 0
		if not deployment_intensity.has(unit_id):
			deployment_intensity[unit_id] = 0
	for region_id in ConfigDB.regions.keys():
		if not region_progress.has(region_id):
			region_progress[region_id] = 0.0
		if not region_unlocked.has(region_id):
			var region = ConfigDB.get_region(region_id)
			region_unlocked[region_id] = total_devour >= region.unlock_at_devour
		if not region_entry_staged.has(region_id):
			region_entry_staged[region_id] = false
	if not region_unlocked.has(active_region) or not region_unlocked[active_region]:
		active_region = "slum_edge"

func set_feedback(message: String) -> void:
	feedback = message
	feedback_changed.emit(message)
	state_changed.emit()

func add_resource(id: String, amount: float) -> void:
	resources[id] = max(0.0, float(resources.get(id, 0.0)) + amount)

func can_spend(costs: Dictionary) -> bool:
	for id in costs.keys():
		if float(resources.get(id, 0.0)) + 0.001 < float(costs[id]):
			return false
	return true

func spend(costs: Dictionary) -> bool:
	if not can_spend(costs):
		return false
	for id in costs.keys():
		resources[id] = max(0.0, float(resources.get(id, 0.0)) - float(costs[id]))
	state_changed.emit()
	return true

func mutation_multiplier() -> float:
	return 1.0 + float(resources.get("mutation", 0.0)) * 0.05

func to_dict() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"resources": resources,
		"organ_levels": organ_levels,
		"reserves": reserves,
		"field_units": field_units,
		"deployment_intensity": deployment_intensity,
		"plugins_owned": plugins_owned,
		"equipped_plugin": equipped_plugin,
		"region_progress": region_progress,
		"region_unlocked": region_unlocked,
		"region_entry_staged": region_entry_staged,
		"active_region": active_region,
		"feedback": feedback,
		"offline_report": offline_report,
		"total_devour": total_devour,
		"total_kills": total_kills,
		"reset_count": reset_count,
		"last_save_unix": last_save_unix
	}

func from_dict(data: Dictionary) -> void:
	resources = data.get("resources", {})
	organ_levels = data.get("organ_levels", {})
	reserves = data.get("reserves", {})
	field_units = data.get("field_units", {})
	deployment_intensity = data.get("deployment_intensity", {})
	plugins_owned = data.get("plugins_owned", {})
	equipped_plugin = String(data.get("equipped_plugin", ""))
	region_progress = data.get("region_progress", {})
	region_unlocked = data.get("region_unlocked", {"slum_edge": true})
	region_entry_staged = data.get("region_entry_staged", {})
	active_region = String(data.get("active_region", "slum_edge"))
	feedback = String(data.get("feedback", feedback))
	offline_report = data.get("offline_report", {})
	total_devour = float(data.get("total_devour", 0.0))
	total_kills = int(data.get("total_kills", 0))
	reset_count = int(data.get("reset_count", 0))
	last_save_unix = int(data.get("last_save_unix", Time.get_unix_time_from_system()))
	ensure_config_defaults()
	battle_report = _empty_battle_report()
	state_changed.emit()
	feedback_changed.emit(feedback)

func _empty_battle_report() -> Dictionary:
	return {
		"mode": "idle",
		"region_id": active_region,
		"progress": 0.0,
		"progress_gain": 0.0,
		"power": 0.0,
			"pressure": 0.0,
			"field_total": 0,
			"reinforced": 0,
			"lost": 0,
			"returned": 0,
			"loss_reason": "",
			"front_motion": "none",
			"prepared_reserve": 0,
			"needed_reserve": 0,
			"action": "",
			"cause": "",
			"base_pressure": 0.0,
			"effective_pressure": 0.0,
			"support_bonus": 0.0,
			"plugin_bonus": 0.0,
			"baseline_needed_reserve": 0,
			"reserve_shortfall": 0,
			"hatch_fill_count": 0,
			"hatch_missing_text": "",
			"pressure_drop": 0.0,
			"loss_rate": 0.0,
			"baseline_loss_rate": 0.0,
			"loss_reduction": 0.0,
			"loss_saved_estimate": 0,
			"protected_estimate": 0,
			"acid_preview_loss_saved": 0,
			"acid_preview_protected": 0,
			"retreat_value": 0,
			"retreat_field_before": 0,
			"preserved_loss_estimate": 0,
			"next_target": 4.0,
			"prestige_gain": 0,
			"prestige_ready": false
		}
