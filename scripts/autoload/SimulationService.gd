extends Node

const OFFLINE_CAP_SECONDS := 12 * 60 * 60
const PREPARE_TARGET_MIN := 5
const PREPARE_MAX_BATCH := 3
const ASSAULT_INTENSITY := 3
const BATTLE_PROGRESS_RATE := 0.13
const BATTLE_HELIX_PER_PROGRESS := 0.45
const PRESTIGE_DEVOUR_PER_GAIN := 8.0
const PRESTIGE_HELIX_PER_GAIN := 18.0
const PRESTIGE_VISIBLE_DEVOUR := 4.0
const FACTORY_ENTRY_REGION := "factory_wall"
const FACTORY_ENTRY_UNIT := "hydralisk"
const FACTORY_ENTRY_PLUGIN := "piercing_spines"
const FACTORY_ENTRY_WAVE_MIN := 3

var ConfigDB
var GameState
var SaveService
var _accumulator := 0.0

func _enter_tree() -> void:
	_bind_dependencies()

func _ready() -> void:
	_bind_dependencies()
	GameState.ensure_config_defaults()
	settle_offline_from_save()

func _bind_dependencies() -> void:
	if get_tree() == null:
		return
	var root := get_tree().root
	if ConfigDB == null and root.has_node("ConfigDB"):
		ConfigDB = root.get_node("ConfigDB")
	if GameState == null and root.has_node("GameState"):
		GameState = root.get_node("GameState")
	if SaveService == null and root.has_node("SaveService"):
		SaveService = root.get_node("SaveService")

func _process(delta: float) -> void:
	_accumulator += delta
	if _accumulator >= 1.0:
		var seconds: int = int(floor(_accumulator))
		_accumulator -= float(seconds)
		simulate_seconds(float(seconds), true)

func simulate_seconds(seconds: float, include_battle: bool) -> void:
	if seconds <= 0.0:
		return
	GameState.ensure_config_defaults()
	_apply_metabolism(seconds)
	_apply_passive_larva(seconds)
	if include_battle:
		_apply_battle(seconds, 1.0)
	_unlock_regions()
	GameState.state_changed.emit()

func _apply_metabolism(seconds: float) -> void:
	for organ_id in ConfigDB.organs.keys():
		var organ = ConfigDB.get_organ(organ_id)
		var level := int(GameState.organ_levels.get(organ_id, 0))
		var rate: float = organ.rate_for_level(level, GameState.mutation_multiplier())
		if rate > 0.0:
			GameState.add_resource(organ.production_resource, rate * seconds)

func _apply_passive_larva(seconds: float) -> void:
	var core_bonus: float = 0.0125 * seconds * GameState.mutation_multiplier()
	GameState.add_resource("larva", core_bonus)

func purchase_organ(organ_id: String) -> bool:
	var organ = ConfigDB.get_organ(organ_id)
	if organ == null:
		GameState.set_feedback("未知器官配置：%s" % organ_id)
		return false
	var level := int(GameState.organ_levels.get(organ_id, 0))
	var costs: Dictionary = {organ.cost_resource: organ.cost_for_level(level)}
	if not GameState.spend(costs):
		GameState.set_feedback("资源不足：升级%s需要 %.0f %s。" % [organ.display_name, costs[organ.cost_resource], _resource_name(organ.cost_resource)])
		return false
	GameState.organ_levels[organ_id] = level + 1
	_refresh_battle_projection("upgrade")
	GameState.set_feedback("%s 升至 %d 级，%s产出提高。" % [organ.display_name, level + 1, _resource_name(organ.production_resource)])
	return true

func hatch_unit(unit_id: String, count: int = 1) -> bool:
	var unit = ConfigDB.get_unit(unit_id)
	if unit == null:
		GameState.set_feedback("未知单位配置：%s" % unit_id)
		return false
	if not _unit_unlocked(unit):
		GameState.set_feedback("%s尚未解锁：需要总吞噬 %.0f%%。先推进现有防线。" % [unit.display_name, unit.unlock_devour])
		return false
	var costs: Dictionary = unit.resource_costs()
	for id in costs.keys():
		costs[id] = float(costs[id]) * count
	if not GameState.spend(costs):
		GameState.set_feedback("孵化%s不足：需要原浆 %.0f、酶 %.0f、螺旋 %.0f、幼虫 %d。" % [unit.display_name, costs["pulp"], costs["enzyme"], costs["helix"], int(costs["larva"])])
		return false
	GameState.reserves[unit_id] = int(GameState.reserves.get(unit_id, 0)) + count
	GameState.set_feedback("孵化完成：%s +%d，储备可投放。" % [unit.display_name, count])
	return true

func prepare_wave(unit_id: String = "zergling") -> bool:
	GameState.ensure_config_defaults()
	var unit = ConfigDB.get_unit(unit_id)
	var region = ConfigDB.get_region(GameState.active_region)
	if unit == null or region == null:
		GameState.set_feedback("战场准备失败：单位或区域配置缺失。")
		return false
	if not _unit_unlocked(unit):
		GameState.set_feedback("%s尚未解锁：需要总吞噬 %.0f%%；当前先推进已开放防线。" % [unit.display_name, unit.unlock_devour])
		return false
	_apply_factory_entry_staging(region.id, unit_id)
	var needed: int = _needed_reserve_for_region(unit_id, region)
	var field_count: int = int(GameState.field_units.get(unit_id, 0))
	var hatched: int = _hatch_toward_reserve(unit_id, maxi(0, needed - field_count), PREPARE_MAX_BATCH)
	GameState.deployment_intensity[unit_id] = 0
	var prepared: int = int(GameState.reserves.get(unit_id, 0)) + field_count
	var cause: String = "ready_wave" if prepared >= needed else "need_reserve"
	var pressure: float = _effective_pressure(region)
	GameState.battle_report = _make_battle_report("preparing", region, 0.0, float(prepared) * unit.power * _battle_support_multiplier(unit_id), pressure, _field_total(), 0, 0, {
		"prepared_reserve": prepared,
		"needed_reserve": needed,
		"action": "prepare",
		"cause": cause,
		"loss_reason": "preparing_wave",
		"front_motion": "hold",
		"base_pressure": region.enemy_pressure,
		"effective_pressure": pressure,
		"support_bonus": _battle_support_bonus(),
		"plugin_bonus": _plugin_damage_bonus(unit_id),
		"next_target": _next_battle_target()
	}, unit_id)
	if prepared >= needed:
		GameState.set_feedback("波次已备齐：%s 储备 %d/%d，可从战场中线强攻。" % [unit.display_name, prepared, needed])
	elif hatched > 0:
		GameState.set_feedback("保守蓄兵：%s +%d，波次 %d/%d；继续蓄兵或等资源补足后再强攻。" % [unit.display_name, hatched, prepared, needed])
	else:
		GameState.set_feedback(_reserve_shortfall_feedback(unit, prepared, needed))
	return prepared > 0 or hatched > 0

func assault_push(unit_id: String = "zergling") -> bool:
	GameState.ensure_config_defaults()
	var unit = ConfigDB.get_unit(unit_id)
	var region = ConfigDB.get_region(GameState.active_region)
	if unit == null or region == null:
		GameState.set_feedback("强攻失败：单位或区域配置缺失。")
		return false
	if not _unit_unlocked(unit):
		GameState.set_feedback("%s尚未解锁：需要总吞噬 %.0f%%；无法提交强攻。" % [unit.display_name, unit.unlock_devour])
		return false
	_apply_factory_entry_staging(region.id, unit_id)
	var needed: int = _needed_reserve_for_region(unit_id, region)
	var pressure: float = _effective_pressure(region)
	var ready_count: int = int(GameState.reserves.get(unit_id, 0)) + int(GameState.field_units.get(unit_id, 0))
	if ready_count < needed:
		_hatch_toward_reserve(unit_id, maxi(0, needed - int(GameState.field_units.get(unit_id, 0))), PREPARE_MAX_BATCH)
		ready_count = int(GameState.reserves.get(unit_id, 0)) + int(GameState.field_units.get(unit_id, 0))
	if ready_count < needed:
		GameState.deployment_intensity[unit_id] = 0
		GameState.battle_report = _make_battle_report("understrength", region, 0.0, float(ready_count) * unit.power * _battle_support_multiplier(unit_id), pressure, _field_total(), 0, 0, {
			"prepared_reserve": int(GameState.reserves.get(unit_id, 0)),
			"needed_reserve": needed,
			"action": "assault",
			"cause": "need_reserve",
			"loss_reason": "understrength",
			"front_motion": "hold",
			"base_pressure": region.enemy_pressure,
			"effective_pressure": pressure,
			"support_bonus": _battle_support_bonus(),
			"plugin_bonus": _plugin_damage_bonus(unit_id),
			"next_target": _next_battle_target()
		}, unit_id)
		GameState.set_feedback("强攻暂缓：%s 规模 %d/%d，战场已标出敌压差；先蓄兵或换构筑。" % [unit.display_name, ready_count, needed])
		return false
	GameState.deployment_intensity[unit_id] = ASSAULT_INTENSITY
	GameState.battle_report = _make_battle_report("committed", region, 0.0, float(ready_count) * unit.power * _battle_support_multiplier(unit_id), pressure, _field_total(), 0, 0, {
		"prepared_reserve": int(GameState.reserves.get(unit_id, 0)),
		"needed_reserve": needed,
		"action": "assault",
		"cause": "commit_push",
		"loss_reason": "committed_assault",
		"front_motion": "forward",
		"base_pressure": region.enemy_pressure,
		"effective_pressure": pressure,
		"support_bonus": _battle_support_bonus(),
		"plugin_bonus": _plugin_damage_bonus(unit_id),
		"next_target": _next_battle_target()
	}, unit_id)
	GameState.set_feedback("强攻下令：%s 投放强度 %d，下一拍补位推进；若敌压反推就撤离保全。" % [unit.display_name, ASSAULT_INTENSITY])
	return true

func set_deployment(unit_id: String, intensity: int) -> void:
	if not ConfigDB.units.has(unit_id):
		return
	GameState.deployment_intensity[unit_id] = clampi(intensity, 0, 5)
	var unit = ConfigDB.get_unit(unit_id)
	if intensity <= 0:
		GameState.set_feedback("%s 投放阀门关闭。" % unit.display_name)
	else:
		GameState.set_feedback("%s 投放强度 %d：会持续消耗储备并推进战线。" % [unit.display_name, intensity])

func select_region(region_id: String) -> bool:
	if not bool(GameState.region_unlocked.get(region_id, false)):
		GameState.set_feedback("区域尚未解锁，需要更高吞噬度。")
		return false
	GameState.active_region = region_id
	var region = ConfigDB.get_region(region_id)
	var staging_note: String = _apply_factory_entry_staging(region_id, FACTORY_ENTRY_UNIT)
	var suffix: String = " %s" % staging_note if staging_note != "" else ""
	GameState.set_feedback("目标区域切换为：%s。%s" % [region.display_name, suffix])
	GameState.state_changed.emit()
	return true

func buy_or_equip_plugin(plugin_id: String) -> bool:
	var plugin = ConfigDB.get_plugin(plugin_id)
	if plugin == null:
		return false
	if not bool(GameState.plugins_owned.get(plugin_id, false)):
		if GameState.total_devour < plugin.unlock_devour:
			GameState.set_feedback("%s需要吞噬度 %.0f%% 后解锁。" % [plugin.display_name, plugin.unlock_devour])
			return false
		if not GameState.spend({"helix": plugin.cost_helix}):
			GameState.set_feedback("螺旋序列不足：装配%s需要 %.0f。" % [plugin.display_name, plugin.cost_helix])
			return false
		GameState.plugins_owned[plugin_id] = true
	GameState.equipped_plugin = plugin_id
	_refresh_battle_projection("plugin")
	GameState.set_feedback("已装配构筑：%s。下一次战斗会改变伤害或保全结果。" % plugin.display_name)
	return true

func retreat() -> void:
	var returned: int = 0
	var field_before: int = _field_total()
	for unit_id in GameState.field_units.keys():
		var current := int(GameState.field_units.get(unit_id, 0))
		var kept: int = int(floor(current * 0.75))
		GameState.reserves[unit_id] = int(GameState.reserves.get(unit_id, 0)) + kept
		GameState.field_units[unit_id] = 0
		GameState.deployment_intensity[unit_id] = 0
		returned += kept
	var region = ConfigDB.get_region(GameState.active_region)
	if region != null:
		GameState.battle_report = _make_battle_report("retreat", region, 0.0, 0.0, 0.0, 0, 0, 0, {
			"returned": returned,
			"retreat_value": returned,
			"retreat_field_before": field_before,
			"preserved_loss_estimate": maxi(0, field_before - returned),
			"loss_reason": "withdraw",
			"front_motion": "back"
		})
	GameState.set_feedback("战场撤离：保留并回收 %d 个单位，停止继续消耗储备。" % returned)

func battle_projection(unit_id: String = "zergling") -> Dictionary:
	GameState.ensure_config_defaults()
	var region = ConfigDB.get_region(GameState.active_region)
	if region == null:
		return {}
	var unit = ConfigDB.get_unit(unit_id)
	var unit_power: float = 0.0 if unit == null else unit.power * _battle_support_multiplier(unit_id)
	var effective_pressure: float = _effective_pressure(region)
	var needed: int = _needed_reserve_for_region(unit_id, region)
	var baseline_pressure: float = _baseline_pressure(region)
	var baseline_needed: int = _baseline_needed_reserve(unit_id, region)
	var preview: Dictionary = prestige_preview()
	var reserve_count: int = int(GameState.reserves.get(unit_id, 0))
	var field_count: int = int(GameState.field_units.get(unit_id, 0))
	var field_total: int = _field_total()
	var potential_retreat: int = _potential_retreat_return()
	var current_loss_rate: float = _current_loss_rate_for_unit(unit_id)
	var baseline_loss_rate: float = _baseline_loss_rate_for_unit(unit_id)
	var wave_reference: int = maxi(needed, reserve_count + field_count)
	var reserve_shortfall: int = maxi(0, needed - reserve_count - field_count)
	var hatch_fill_count: int = _affordable_hatch_count(unit_id, reserve_shortfall)
	var hatch_missing_text: String = ""
	if reserve_shortfall > 0 and hatch_fill_count <= 0 and unit != null:
		hatch_missing_text = _missing_cost_text(unit.resource_costs())
	var loss_saved_estimate: int = int(ceil(float(wave_reference) * maxf(0.0, baseline_loss_rate - current_loss_rate)))
	var protected_estimate: int = maxi(0, wave_reference - int(ceil(float(wave_reference) * current_loss_rate)))
	var acid_preview_loss_saved: int = 0
	var acid_preview_protected: int = 0
	var acid_preview_rate: float = _acid_preview_loss_rate(unit_id)
	if acid_preview_rate < current_loss_rate:
		acid_preview_loss_saved = int(ceil(float(wave_reference) * (current_loss_rate - acid_preview_rate)))
		acid_preview_protected = maxi(0, wave_reference - int(ceil(float(wave_reference) * acid_preview_rate)))
	return {
		"base_pressure": float(region.enemy_pressure),
		"effective_pressure": effective_pressure,
		"needed_reserve": needed,
		"baseline_needed_reserve": baseline_needed,
		"prepared_reserve": reserve_count + field_count,
		"reserve_shortfall": reserve_shortfall,
		"hatch_fill_count": hatch_fill_count,
		"hatch_missing_text": hatch_missing_text,
		"unit_power": unit_power,
		"support_bonus": _battle_support_bonus(),
		"plugin_bonus": _plugin_damage_bonus(unit_id),
		"survival_bonus": _support_survival_bonus(),
		"pressure_drop": maxf(0.0, baseline_pressure - effective_pressure),
		"loss_rate": current_loss_rate,
		"baseline_loss_rate": baseline_loss_rate,
		"loss_reduction": maxf(0.0, baseline_loss_rate - current_loss_rate),
		"loss_saved_estimate": loss_saved_estimate,
		"protected_estimate": protected_estimate,
		"acid_preview_loss_saved": acid_preview_loss_saved,
		"acid_preview_protected": acid_preview_protected,
		"retreat_value": potential_retreat,
		"retreat_field_before": field_total,
		"preserved_loss_estimate": maxi(0, field_total - potential_retreat),
		"next_target": _next_battle_target(),
		"prestige_gain": int(preview.get("gain", 0)),
		"prestige_ready": bool(preview.get("can_reset", false))
	}

func prestige_preview() -> Dictionary:
	var gain: int = int(floor(GameState.total_devour / PRESTIGE_DEVOUR_PER_GAIN + float(GameState.resources.get("helix", 0.0)) / PRESTIGE_HELIX_PER_GAIN))
	if GameState.total_devour >= PRESTIGE_VISIBLE_DEVOUR:
		gain = max(1, gain)
	return {
		"gain": gain,
		"current": int(GameState.resources.get("mutation", 0)),
		"next_multiplier": 1.0 + float(GameState.resources.get("mutation", 0) + gain) * 0.05,
		"can_reset": gain > 0
	}

func perform_prestige() -> bool:
	var preview: Dictionary = prestige_preview()
	if not bool(preview["can_reset"]):
		GameState.set_feedback("重置收益仍为 0：继续推进区域或积累螺旋序列。")
		return false
	var gained := int(preview["gain"])
	GameState.add_resource("mutation", gained)
	GameState.reset_count += 1
	GameState.reset_new_game(true)
	GameState.set_feedback("吞噬世界完成：获得突变原 %d。新轮回生产速度已提升。" % gained)
	SaveService.save_game()
	return true

func settle_offline_from_save() -> Dictionary:
	var now: int = Time.get_unix_time_from_system()
	var elapsed: int = now - int(GameState.last_save_unix)
	if elapsed <= 5:
		return {}
	return settle_offline(float(elapsed))

func settle_offline(seconds: float) -> Dictionary:
	var capped_seconds: float = min(seconds, float(OFFLINE_CAP_SECONDS))
	var before: Dictionary = GameState.resources.duplicate(true)
	simulate_seconds(capped_seconds, false)
	_apply_battle(capped_seconds, 0.25)
	_unlock_regions()
	var gains: Dictionary = {}
	for id in GameState.RESOURCE_IDS:
		gains[id] = float(GameState.resources.get(id, 0.0)) - float(before.get(id, 0.0))
	var report: Dictionary = {
		"seconds": capped_seconds,
		"capped": seconds > OFFLINE_CAP_SECONDS,
		"gains": gains,
		"active_region": GameState.active_region
	}
	GameState.offline_report = report
	GameState.offline_report_ready.emit(report)
	GameState.set_feedback("离线结算 %.1f 小时%s：资源和战线按宏观公式推进。" % [capped_seconds / 3600.0, "（12小时封顶）" if seconds > OFFLINE_CAP_SECONDS else ""])
	return report

func _apply_battle(seconds: float, efficiency: float) -> void:
	var region = ConfigDB.get_region(GameState.active_region)
	if region == null or not bool(GameState.region_unlocked.get(region.id, false)):
		return
	var reinforced: int = 0
	for unit_id in ConfigDB.units.keys():
		var unit = ConfigDB.get_unit(unit_id)
		var intensity := int(GameState.deployment_intensity.get(unit_id, 0))
		if intensity <= 0:
			continue
		var available := int(GameState.reserves.get(unit_id, 0))
		var batch: int = min(available, int(ceil(float(intensity * unit.deployment_batch) * seconds * efficiency)))
		if batch > 0:
			GameState.reserves[unit_id] = available - batch
			GameState.field_units[unit_id] = int(GameState.field_units.get(unit_id, 0)) + batch
			reinforced += batch

	var power: float = _field_power(region)
	var pressure: float = _effective_pressure(region)
	var field_total: int = _field_total()
	if field_total <= 0:
		if _has_open_valve():
			GameState.battle_report = _make_battle_report("empty", region, 0.0, power, pressure, field_total, reinforced, 0, {
				"loss_reason": "no_reserve",
				"front_motion": "none"
			})
		else:
			GameState.battle_report = _make_battle_report("idle", region, 0.0, 0.0, 0.0, field_total, reinforced, 0, {
				"loss_reason": "no_order",
				"front_motion": "none"
			})
		if _has_open_valve():
			GameState.set_feedback("投放阀门已打开，但储备为空：回到虫巢孵化单位。")
		return

	var lost: int = 0
	if power >= pressure:
		var progress_gain: float = min(100.0 - float(GameState.region_progress.get(region.id, 0.0)), (power - pressure * 0.55) * BATTLE_PROGRESS_RATE * seconds * efficiency)
		if progress_gain > 0.0:
			GameState.region_progress[region.id] = float(GameState.region_progress.get(region.id, 0.0)) + progress_gain
			GameState.total_devour = max(GameState.total_devour, _total_region_progress())
			GameState.add_resource("pulp", region.reward_pulp_per_progress * progress_gain)
			GameState.add_resource("enzyme", region.reward_enzyme_per_progress * progress_gain)
			GameState.add_resource("helix", progress_gain * BATTLE_HELIX_PER_PROGRESS)
			GameState.total_kills += int(progress_gain * 2.0)
		var breakthrough_rate: float = 0.0 if GameState.total_devour < PRESTIGE_VISIBLE_DEVOUR else 0.012 * seconds * efficiency
		lost = _apply_attrition(breakthrough_rate)
		GameState.battle_report = _make_battle_report("advance" if progress_gain > 0.0 else "holding", region, progress_gain, power, pressure, _field_total(), reinforced, lost, {
			"loss_reason": "breakthrough_attrition",
			"front_motion": "forward" if progress_gain > 0.0 else "hold",
			"cause": "commit_push",
			"base_pressure": region.enemy_pressure,
			"effective_pressure": pressure,
			"support_bonus": _battle_support_bonus(),
			"plugin_bonus": _dominant_plugin_bonus(),
			"next_target": _next_battle_target()
		})
		GameState.set_feedback("战线推进 %.1f%%：构筑与投放压过敌方火力，尸体回流为资源。" % progress_gain)
	else:
		lost = _apply_attrition(0.065 * seconds * efficiency)
		GameState.battle_report = _make_battle_report("stalled", region, 0.0, power, pressure, _field_total(), reinforced, lost, {
			"loss_reason": "enemy_pressure",
			"front_motion": "back",
			"cause": _battle_cause(region, power, pressure),
			"base_pressure": region.enemy_pressure,
			"effective_pressure": pressure,
			"support_bonus": _battle_support_bonus(),
			"plugin_bonus": _dominant_plugin_bonus(),
			"next_target": _next_battle_target()
		})
		var hint: String = _battle_hint(region, power, pressure)
		GameState.set_feedback("推进停滞：我方 %.1f / 敌压 %.1f。%s" % [power, pressure, hint])

	if float(GameState.region_progress.get(region.id, 0.0)) >= 100.0 and region.next_region != "":
		GameState.region_unlocked[region.next_region] = true
		GameState.set_feedback("%s 吞噬完成，新区域已解锁。" % region.display_name)

func _field_power(region) -> float:
	var power: float = 0.0
	for unit_id in GameState.field_units.keys():
		var unit = ConfigDB.get_unit(unit_id)
		if unit == null:
			continue
		var count := int(GameState.field_units.get(unit_id, 0))
		power += float(count) * unit.power * _region_unit_power_multiplier(unit_id, region)
	return power

func _apply_attrition(rate: float) -> int:
	var plugin = ConfigDB.get_plugin(GameState.equipped_plugin)
	var lost_total: int = 0
	for unit_id in GameState.field_units.keys():
		var unit = ConfigDB.get_unit(unit_id)
		var current := int(GameState.field_units.get(unit_id, 0))
		if current <= 0:
			continue
		var toughness: float = 1.0 if unit == null else maxf(0.25, unit.toughness)
		var survival_bonus: float = 0.0
		if plugin != null and plugin.target_unit == unit_id:
			survival_bonus = plugin.survival_bonus
		var effective_rate: float = maxf(0.0, rate / toughness - survival_bonus - _support_survival_bonus())
		var lost: int = min(current, int(ceil(float(current) * effective_rate)))
		if current > 1:
			lost = mini(lost, current - 1)
		GameState.field_units[unit_id] = current - lost
		lost_total += lost
	return lost_total

func _make_battle_report(mode: String, region, progress_gain: float, power: float, pressure: float, field_total: int, reinforced: int, lost: int, extras: Dictionary = {}, projection_unit_id: String = "zergling") -> Dictionary:
	var preview: Dictionary = prestige_preview()
	var projection: Dictionary = battle_projection(projection_unit_id)
	var potential_retreat: int = _potential_retreat_return()
	var report: Dictionary = {
		"mode": mode,
		"region_id": region.id,
		"progress": float(GameState.region_progress.get(region.id, 0.0)),
		"progress_gain": progress_gain,
		"power": power,
		"pressure": pressure,
		"field_total": field_total,
		"reinforced": reinforced,
		"lost": lost,
		"returned": 0,
		"loss_reason": "",
		"front_motion": "none",
		"base_pressure": float(region.enemy_pressure),
		"effective_pressure": pressure,
		"support_bonus": _battle_support_bonus(),
		"plugin_bonus": _dominant_plugin_bonus(),
		"baseline_needed_reserve": int(projection.get("baseline_needed_reserve", 0)),
		"hatch_missing_text": String(projection.get("hatch_missing_text", "")),
		"reserve_shortfall": int(projection.get("reserve_shortfall", 0)),
		"hatch_fill_count": int(projection.get("hatch_fill_count", 0)),
		"pressure_drop": float(projection.get("pressure_drop", 0.0)),
		"loss_rate": float(projection.get("loss_rate", 0.0)),
		"baseline_loss_rate": float(projection.get("baseline_loss_rate", 0.0)),
		"loss_reduction": float(projection.get("loss_reduction", 0.0)),
		"loss_saved_estimate": int(projection.get("loss_saved_estimate", 0)),
		"protected_estimate": int(projection.get("protected_estimate", 0)),
		"acid_preview_loss_saved": int(projection.get("acid_preview_loss_saved", 0)),
		"acid_preview_protected": int(projection.get("acid_preview_protected", 0)),
		"retreat_value": potential_retreat,
		"retreat_field_before": _field_total(),
		"preserved_loss_estimate": maxi(0, _field_total() - potential_retreat),
		"next_target": _next_battle_target(),
		"prestige_gain": int(preview.get("gain", 0)),
		"prestige_ready": bool(preview.get("can_reset", false))
	}
	for key in extras.keys():
		report[key] = extras[key]
	return report

func _battle_hint(region, power: float, pressure: float) -> String:
	if region != null and region.id == FACTORY_ENTRY_REGION and _field_total() < FACTORY_ENTRY_WAVE_MIN:
		return "点左侧蓄兵补刺蛇首波，再点中线强攻；若失败就右撤离保全。"
	if region != null and region.id == "research_bastion":
		return "火焰炮塔怕爆裂虫，轨道哨戒怕甲壳卫士；脆皮强攻后注意撤离保全。"
	if _field_total() < 6:
		return "储备投放太少，先孵化或提高投放强度。"
	if GameState.equipped_plugin == "":
		return "装配穿刺脊突或酸化甲壳能改变这一场结果。"
	if power < pressure * 0.8:
		return "敌方装甲压制明显，升级神经尖塔/酸蚀喷泉补足螺旋和酶。"
	return "接近突破，继续补储备或撤离保留兵力后调整。"

func _battle_cause(_region, power: float, pressure: float) -> String:
	if _field_total() < 6:
		return "need_reserve"
	if GameState.equipped_plugin == "":
		return "need_plugin"
	if power < pressure * 0.8:
		return "need_intensity"
	return "commit_push"

func _needed_reserve_for_region(unit_id: String, region) -> int:
	var unit = ConfigDB.get_unit(unit_id)
	if unit == null or region == null:
		return PREPARE_TARGET_MIN
	var pressure: float = _effective_pressure(region)
	var unit_power: float = maxf(0.1, unit.power * _region_unit_power_multiplier(unit_id, region))
	var floor_target: int = PREPARE_TARGET_MIN if _battle_support_bonus() <= 0.001 and _plugin_damage_bonus(unit_id) <= 0.001 else PREPARE_TARGET_MIN - 1
	if region.id == FACTORY_ENTRY_REGION and unit_id == FACTORY_ENTRY_UNIT and GameState.equipped_plugin == FACTORY_ENTRY_PLUGIN:
		floor_target = FACTORY_ENTRY_WAVE_MIN
	return maxi(floor_target, int(ceil(pressure / unit_power)))

func _baseline_needed_reserve(unit_id: String, region) -> int:
	var unit = ConfigDB.get_unit(unit_id)
	if unit == null or region == null:
		return PREPARE_TARGET_MIN
	var pressure: float = _baseline_pressure(region)
	var unit_power: float = maxf(0.1, unit.power)
	return maxi(PREPARE_TARGET_MIN, int(ceil(pressure / unit_power)))

func _baseline_pressure(region) -> float:
	var progress: float = float(GameState.region_progress.get(region.id, 0.0))
	return maxf(1.0, region.enemy_pressure * (1.0 + progress / 150.0))

func _effective_pressure(region) -> float:
	var progress: float = float(GameState.region_progress.get(region.id, 0.0))
	var pressure: float = maxf(1.0, region.enemy_pressure * (1.0 + progress / 150.0))
	return maxf(1.0, pressure * (1.0 - _pressure_relief_bonus()))

func _battle_support_multiplier(unit_id: String) -> float:
	return 1.0 + _battle_support_bonus() + _plugin_damage_bonus(unit_id)

func _region_unit_power_multiplier(unit_id: String, region) -> float:
	var unit = ConfigDB.get_unit(unit_id)
	var bonus: float = 1.0 + _battle_support_bonus() + _plugin_damage_bonus(unit_id)
	if unit != null and region != null and unit.damage_tag != "physical":
		for enemy_id in region.enemy_ids:
			var counter_enemy = ConfigDB.get_enemy(enemy_id)
			if counter_enemy != null and counter_enemy.weakness_tag == unit.damage_tag:
				bonus += 0.35
				break
	var plugin = ConfigDB.get_plugin(GameState.equipped_plugin)
	if plugin == null or plugin.target_unit != unit_id or region == null:
		return bonus
	for enemy_id in region.enemy_ids:
		var enemy = ConfigDB.get_enemy(enemy_id)
		if enemy != null and enemy.weakness_tag == plugin.counter_tag:
			bonus += 0.30
			break
	return bonus

func _battle_support_bonus() -> float:
	var mucus_extra: int = maxi(0, int(GameState.organ_levels.get("mucus_fronds", 0)) - 1)
	var root_level: int = int(GameState.organ_levels.get("deep_roots", 0))
	var acid_level: int = int(GameState.organ_levels.get("acid_fountain", 0))
	var neural_level: int = int(GameState.organ_levels.get("neural_spire", 0))
	var bonus: float = float(mucus_extra) * 0.04 + float(root_level) * 0.08 + float(acid_level) * 0.05 + float(neural_level) * 0.04
	return minf(0.34, bonus)

func _pressure_relief_bonus() -> float:
	var root_level: int = int(GameState.organ_levels.get("deep_roots", 0))
	var reflux_level: int = int(GameState.organ_levels.get("reflux_pump", 0))
	return minf(0.24, float(root_level) * 0.05 + float(reflux_level) * 0.04)

func _support_survival_bonus() -> float:
	var acid_level: int = int(GameState.organ_levels.get("acid_fountain", 0))
	var reflux_level: int = int(GameState.organ_levels.get("reflux_pump", 0))
	return minf(0.014, float(acid_level) * 0.003 + float(reflux_level) * 0.004)

func _current_loss_rate_for_unit(unit_id: String) -> float:
	var plugin = ConfigDB.get_plugin(GameState.equipped_plugin)
	var plugin_survival: float = 0.0
	if plugin != null and plugin.target_unit == unit_id:
		plugin_survival = plugin.survival_bonus
	var unit = ConfigDB.get_unit(unit_id)
	var toughness: float = 1.0 if unit == null else maxf(0.25, unit.toughness)
	return maxf(0.0, 0.065 / toughness - plugin_survival - _support_survival_bonus())

func _baseline_loss_rate_for_unit(_unit_id: String) -> float:
	return 0.065

func _acid_preview_loss_rate(unit_id: String) -> float:
	var plugin = ConfigDB.get_plugin("acid_carapace")
	if plugin == null or plugin.target_unit != unit_id:
		return _current_loss_rate_for_unit(unit_id)
	var preview_survival: float = plugin.survival_bonus
	var unit = ConfigDB.get_unit(unit_id)
	var toughness: float = 1.0 if unit == null else maxf(0.25, unit.toughness)
	return maxf(0.0, 0.065 / toughness - preview_survival - _support_survival_bonus())

func _potential_retreat_return() -> int:
	var returned: int = 0
	for unit_id in GameState.field_units.keys():
		var current: int = int(GameState.field_units.get(unit_id, 0))
		returned += int(floor(float(current) * 0.75))
	return returned

func _plugin_damage_bonus(unit_id: String) -> float:
	var plugin = ConfigDB.get_plugin(GameState.equipped_plugin)
	if plugin == null or plugin.target_unit != unit_id:
		return 0.0
	return plugin.damage_bonus

func _dominant_plugin_bonus() -> float:
	var best: float = 0.0
	for unit_id in GameState.field_units.keys():
		if int(GameState.field_units.get(unit_id, 0)) > 0:
			best = maxf(best, _plugin_damage_bonus(unit_id))
	for unit_id in GameState.reserves.keys():
		if int(GameState.reserves.get(unit_id, 0)) > 0:
			best = maxf(best, _plugin_damage_bonus(unit_id))
	return best

func _next_battle_target() -> float:
	if GameState.total_devour < PRESTIGE_VISIBLE_DEVOUR:
		return PRESTIGE_VISIBLE_DEVOUR
	var region = ConfigDB.get_region(GameState.active_region)
	if region != null and region.next_region != "":
		var next_region = ConfigDB.get_region(region.next_region)
		if next_region != null and GameState.total_devour < next_region.unlock_at_devour:
			return next_region.unlock_at_devour
	return 100.0

func _refresh_battle_projection(action: String) -> void:
	var region = ConfigDB.get_region(GameState.active_region)
	if region == null:
		return
	var report: Dictionary = GameState.battle_report.duplicate(true)
	if report.is_empty():
		report = _make_battle_report("idle", region, 0.0, 0.0, 0.0, _field_total(), 0, 0)
	var projection: Dictionary = battle_projection("zergling")
	var potential_retreat: int = _potential_retreat_return()
	report["base_pressure"] = float(region.enemy_pressure)
	report["effective_pressure"] = _effective_pressure(region)
	report["pressure"] = float(report["effective_pressure"])
	report["support_bonus"] = _battle_support_bonus()
	report["plugin_bonus"] = _dominant_plugin_bonus()
	report["baseline_needed_reserve"] = int(projection.get("baseline_needed_reserve", 0))
	report["hatch_missing_text"] = String(projection.get("hatch_missing_text", ""))
	report["reserve_shortfall"] = int(projection.get("reserve_shortfall", 0))
	report["hatch_fill_count"] = int(projection.get("hatch_fill_count", 0))
	report["pressure_drop"] = float(projection.get("pressure_drop", 0.0))
	report["loss_rate"] = float(projection.get("loss_rate", 0.0))
	report["baseline_loss_rate"] = float(projection.get("baseline_loss_rate", 0.0))
	report["loss_reduction"] = float(projection.get("loss_reduction", 0.0))
	report["loss_saved_estimate"] = int(projection.get("loss_saved_estimate", 0))
	report["protected_estimate"] = int(projection.get("protected_estimate", 0))
	report["acid_preview_loss_saved"] = int(projection.get("acid_preview_loss_saved", 0))
	report["acid_preview_protected"] = int(projection.get("acid_preview_protected", 0))
	report["retreat_value"] = potential_retreat
	report["retreat_field_before"] = _field_total()
	report["preserved_loss_estimate"] = maxi(0, _field_total() - potential_retreat)
	report["next_target"] = _next_battle_target()
	report["action"] = action
	GameState.battle_report = report

func _hatch_toward_reserve(unit_id: String, target_reserve: int, max_batch: int) -> int:
	var reserve: int = int(GameState.reserves.get(unit_id, 0))
	var missing: int = clampi(target_reserve - reserve, 0, max_batch)
	if missing <= 0:
		return 0
	var affordable: int = _affordable_hatch_count(unit_id, missing)
	if affordable <= 0:
		return 0
	return affordable if hatch_unit(unit_id, affordable) else 0

func _affordable_hatch_count(unit_id: String, max_count: int) -> int:
	var unit = ConfigDB.get_unit(unit_id)
	if unit == null:
		return 0
	for count in range(max_count, 0, -1):
		var costs: Dictionary = _scaled_costs(unit.resource_costs(), float(count))
		if GameState.can_spend(costs):
			return count
	return 0

func _scaled_costs(costs: Dictionary, scale: float) -> Dictionary:
	var scaled: Dictionary = {}
	for id in costs.keys():
		scaled[id] = float(costs[id]) * scale
	return scaled

func _missing_cost_text(costs: Dictionary) -> String:
	var parts: Array[String] = []
	for id in GameState.RESOURCE_IDS:
		if not costs.has(id):
			continue
		var missing: float = maxf(0.0, float(costs[id]) - float(GameState.resources.get(id, 0.0)))
		if missing > 0.001:
			parts.append("%s %.0f" % [_resource_name(id), ceil(missing)])
	return "无" if parts.is_empty() else "、".join(parts)

func _field_total() -> int:
	var total: int = 0
	for unit_id in GameState.field_units.keys():
		total += int(GameState.field_units.get(unit_id, 0))
	return total

func _has_open_valve() -> bool:
	for unit_id in GameState.deployment_intensity.keys():
		if int(GameState.deployment_intensity.get(unit_id, 0)) > 0:
			return true
	return false

func _unit_unlocked(unit) -> bool:
	return unit == null or GameState.total_devour + 0.001 >= float(unit.unlock_devour)

func _apply_factory_entry_staging(region_id: String, unit_id: String) -> String:
	if region_id != FACTORY_ENTRY_REGION or unit_id != FACTORY_ENTRY_UNIT:
		return ""
	var unit = ConfigDB.get_unit(FACTORY_ENTRY_UNIT)
	var plugin = ConfigDB.get_plugin(FACTORY_ENTRY_PLUGIN)
	if unit == null or plugin == null:
		return ""
	if bool(GameState.region_entry_staged.get(FACTORY_ENTRY_REGION, false)):
		if GameState.equipped_plugin != FACTORY_ENTRY_PLUGIN and bool(GameState.plugins_owned.get(FACTORY_ENTRY_PLUGIN, false)):
			GameState.equipped_plugin = FACTORY_ENTRY_PLUGIN
		return ""
	var changed := false
	var costs: Dictionary = _scaled_costs(unit.resource_costs(), float(FACTORY_ENTRY_WAVE_MIN))
	if float(GameState.resources.get("pulp", 0.0)) < float(costs.get("pulp", 0.0)):
		GameState.resources["pulp"] = float(costs.get("pulp", 0.0))
		changed = true
	if float(GameState.resources.get("enzyme", 0.0)) < float(costs.get("enzyme", 0.0)):
		GameState.resources["enzyme"] = float(costs.get("enzyme", 0.0))
		changed = true
	if float(GameState.resources.get("larva", 0.0)) < float(costs.get("larva", 0.0)):
		GameState.resources["larva"] = float(costs.get("larva", 0.0))
		changed = true
	if not bool(GameState.plugins_owned.get(FACTORY_ENTRY_PLUGIN, false)) and float(GameState.resources.get("helix", 0.0)) < plugin.cost_helix:
		GameState.resources["helix"] = plugin.cost_helix
		changed = true
	if not bool(GameState.plugins_owned.get(FACTORY_ENTRY_PLUGIN, false)) and GameState.spend({"helix": plugin.cost_helix}):
		GameState.plugins_owned[FACTORY_ENTRY_PLUGIN] = true
		changed = true
	if GameState.equipped_plugin != FACTORY_ENTRY_PLUGIN and bool(GameState.plugins_owned.get(FACTORY_ENTRY_PLUGIN, false)):
		GameState.equipped_plugin = FACTORY_ENTRY_PLUGIN
		changed = true
	GameState.region_entry_staged[FACTORY_ENTRY_REGION] = true
	return "破防回流已补足首轮刺蛇营养并装配穿刺脊突；左蓄兵，中过线强攻。" if changed else ""

func _reserve_shortfall_feedback(unit, prepared: int, needed: int) -> String:
	var missing_text: String = _missing_cost_text(unit.resource_costs())
	if GameState.active_region == FACTORY_ENTRY_REGION:
		return "波次不足：%s %d/%d。点左侧蓄兵补首波；若资源仍缺，退回上一防线刷资源后再强攻。" % [unit.display_name, prepared, needed]
	return "波次不足：%s 储备 %d/%d，还差 %s。" % [unit.display_name, prepared, needed, missing_text]

func _unlock_regions() -> void:
	for region_id in ConfigDB.regions.keys():
		var region = ConfigDB.get_region(region_id)
		if region != null and GameState.total_devour >= region.unlock_at_devour:
			GameState.region_unlocked[region_id] = true

func _total_region_progress() -> float:
	var total: float = 0.0
	for region_id in GameState.region_progress.keys():
		total += float(GameState.region_progress.get(region_id, 0.0))
	return total

func _resource_name(id: String) -> String:
	var names := {
		"pulp": "有机原浆",
		"enzyme": "活性酶",
		"helix": "螺旋序列",
		"larva": "幼虫",
		"mutation": "突变原"
	}
	return names.get(id, id)
