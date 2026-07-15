extends Node

signal state_changed(snapshot: Dictionary)
signal notice_posted(message: String, level: String)
signal persistence_recovery_changed(status: Dictionary)
signal battle_started(node_id: String)
signal battle_ended(node_id: String, captured: bool)

const SAVE_VERSION := "v1.0.0"
const DEFAULT_SAVE_PATH := "user://saves/slot_01.json"
const BACKUP_SUFFIX := ".bak"
const SAVE_TEMP_SUFFIX := ".tmp"
const BACKUP_TEMP_SUFFIX := ".bak.tmp"
const BACKUP_PREVIOUS_SUFFIX := ".bak.prev"
const ROLLBACK_SUFFIX := ".rollback"
const RECOVERY_SUFFIX := ".recover"

const SNAPSHOT_OK := "ok"
const SNAPSHOT_MISSING := "missing"
const SNAPSHOT_CORRUPT := "corrupt"
const SNAPSHOT_IO_ERROR := "io_error"
const PATH_EXISTS := "exists"

const COMMIT_NOT_COMMITTED := "not_committed"
const COMMIT_COMMITTED := "committed"
const COMMIT_UNCERTAIN := "uncertain"

const IO_HAS_SAVE_PRIMARY := "has_save_primary"
const IO_HAS_SAVE_BACKUP := "has_save_backup"
const IO_LOAD_PRIMARY := "load_primary"
const IO_LOAD_BACKUP := "load_backup"
const IO_CREATE_SAVE_DIRECTORY := "create_save_directory"
const IO_REMOVE_STALE_SAVE_TEMP := "remove_stale_save_temp"
const IO_WRITE_STAGED_SNAPSHOT := "write_staged_snapshot"
const IO_VALIDATE_STAGED_SNAPSHOT := "validate_staged_snapshot"
const IO_INSPECT_EXISTING_PRIMARY := "inspect_existing_primary"
const IO_COMMIT_FIRST_PRIMARY := "commit_first_primary"
const IO_VALIDATE_FIRST_PRIMARY := "validate_first_primary"
const IO_REMOVE_STALE_BACKUP_TEMP := "remove_stale_backup_temp"
const IO_COPY_PRIMARY_TO_BACKUP_TEMP := "copy_primary_to_backup_temp"
const IO_VALIDATE_BACKUP_CANDIDATE := "validate_backup_candidate"
const IO_INSPECT_EXISTING_BACKUP := "inspect_existing_backup"
const IO_REMOVE_STALE_BACKUP_PREVIOUS := "remove_stale_backup_previous"
const IO_COPY_EXISTING_BACKUP_TO_PREVIOUS := "copy_existing_backup_to_previous"
const IO_VALIDATE_PREVIOUS_BACKUP := "validate_previous_backup"
const IO_INSPECT_BACKUP_COMMIT_DESTINATION := "inspect_backup_commit_destination"
const IO_COMMIT_BACKUP := "commit_backup"
const IO_RESTORE_PREVIOUS_BACKUP_CLEANUP := "restore_previous_backup_cleanup"
const IO_RESTORE_PREVIOUS_BACKUP_COPY := "restore_previous_backup_copy"
const IO_VALIDATE_RESTORE_PREVIOUS_BACKUP := "validate_restore_previous_backup"
const IO_RESTORE_PREVIOUS_BACKUP_DESTINATION := "restore_previous_backup_destination"
const IO_RESTORE_PREVIOUS_BACKUP_COMMIT := "restore_previous_backup_commit"
const IO_VALIDATE_COMMITTED_BACKUP := "validate_committed_backup"
const IO_REMOVE_STALE_ROLLBACK := "remove_stale_rollback"
const IO_MOVE_PRIMARY_TO_ROLLBACK := "move_primary_to_rollback"
const IO_VALIDATE_ROLLBACK := "validate_rollback"
const IO_INSPECT_VACATED_PRIMARY_DESTINATION := "inspect_vacated_primary_destination"
const IO_COMMIT_PRIMARY := "commit_primary"
const IO_INSPECT_ROLLBACK_RESTORE_SOURCE := "inspect_rollback_restore_source"
const IO_VALIDATE_ROLLBACK_RESTORE_SOURCE := "validate_rollback_restore_source"
const IO_INSPECT_ROLLBACK_RESTORE_DESTINATION := "inspect_rollback_restore_destination"
const IO_RESTORE_PRIMARY_ROLLBACK_ENTRY := "restore_primary_rollback_entry"
const IO_VALIDATE_RESTORED_PRIMARY_ROLLBACK := "validate_restored_primary_rollback"
const IO_VALIDATE_COMMITTED_PRIMARY := "validate_committed_primary"
const IO_REMOVE_INVALID_COMMITTED_SLOT := "remove_invalid_committed_slot"
const IO_RESTORE_INVALID_PRIMARY_FROM_BACKUP_CLEANUP := "restore_invalid_primary_from_backup_cleanup"
const IO_RESTORE_INVALID_PRIMARY_FROM_BACKUP_COPY := "restore_invalid_primary_from_backup_copy"
const IO_VALIDATE_RESTORE_INVALID_PRIMARY_FROM_BACKUP := "validate_restore_invalid_primary_from_backup"
const IO_RESTORE_INVALID_PRIMARY_FROM_BACKUP_DESTINATION := "restore_invalid_primary_from_backup_destination"
const IO_RESTORE_INVALID_PRIMARY_FROM_BACKUP_COMMIT := "restore_invalid_primary_from_backup_commit"
const IO_CLEANUP_ROLLBACK := "cleanup_rollback"
const IO_CLEANUP_BACKUP_PREVIOUS := "cleanup_backup_previous"
const IO_REMOVE_STALE_RECOVERY := "remove_stale_recovery"
const IO_COPY_BACKUP_TO_RECOVERY := "copy_backup_to_recovery"
const IO_VALIDATE_RECOVERY_CANDIDATE := "validate_recovery_candidate"
const IO_REMOVE_INVALID_PRIMARY_FOR_RECOVERY := "remove_invalid_primary_for_recovery"
const IO_COMMIT_BACKUP_RECOVERY := "commit_backup_recovery"
const IO_VALIDATE_RESTORED_PRIMARY := "validate_restored_primary"

# BEGIN PERSISTENCE_IO_CALLSITES
const PERSISTENCE_IO_CALLSITES: Array[String] = [
	IO_HAS_SAVE_PRIMARY,
	IO_HAS_SAVE_BACKUP,
	IO_LOAD_PRIMARY,
	IO_LOAD_BACKUP,
	IO_CREATE_SAVE_DIRECTORY,
	IO_REMOVE_STALE_SAVE_TEMP,
	IO_WRITE_STAGED_SNAPSHOT,
	IO_VALIDATE_STAGED_SNAPSHOT,
	IO_INSPECT_EXISTING_PRIMARY,
	IO_COMMIT_FIRST_PRIMARY,
	IO_VALIDATE_FIRST_PRIMARY,
	IO_REMOVE_STALE_BACKUP_TEMP,
	IO_COPY_PRIMARY_TO_BACKUP_TEMP,
	IO_VALIDATE_BACKUP_CANDIDATE,
	IO_INSPECT_EXISTING_BACKUP,
	IO_REMOVE_STALE_BACKUP_PREVIOUS,
	IO_COPY_EXISTING_BACKUP_TO_PREVIOUS,
	IO_VALIDATE_PREVIOUS_BACKUP,
	IO_INSPECT_BACKUP_COMMIT_DESTINATION,
	IO_COMMIT_BACKUP,
	IO_RESTORE_PREVIOUS_BACKUP_CLEANUP,
	IO_RESTORE_PREVIOUS_BACKUP_COPY,
	IO_VALIDATE_RESTORE_PREVIOUS_BACKUP,
	IO_RESTORE_PREVIOUS_BACKUP_DESTINATION,
	IO_RESTORE_PREVIOUS_BACKUP_COMMIT,
	IO_VALIDATE_COMMITTED_BACKUP,
	IO_REMOVE_STALE_ROLLBACK,
	IO_MOVE_PRIMARY_TO_ROLLBACK,
	IO_VALIDATE_ROLLBACK,
	IO_INSPECT_VACATED_PRIMARY_DESTINATION,
	IO_COMMIT_PRIMARY,
	IO_INSPECT_ROLLBACK_RESTORE_SOURCE,
	IO_VALIDATE_ROLLBACK_RESTORE_SOURCE,
	IO_INSPECT_ROLLBACK_RESTORE_DESTINATION,
	IO_RESTORE_PRIMARY_ROLLBACK_ENTRY,
	IO_VALIDATE_RESTORED_PRIMARY_ROLLBACK,
	IO_VALIDATE_COMMITTED_PRIMARY,
	IO_REMOVE_INVALID_COMMITTED_SLOT,
	IO_RESTORE_INVALID_PRIMARY_FROM_BACKUP_CLEANUP,
	IO_RESTORE_INVALID_PRIMARY_FROM_BACKUP_COPY,
	IO_VALIDATE_RESTORE_INVALID_PRIMARY_FROM_BACKUP,
	IO_RESTORE_INVALID_PRIMARY_FROM_BACKUP_DESTINATION,
	IO_RESTORE_INVALID_PRIMARY_FROM_BACKUP_COMMIT,
	IO_CLEANUP_ROLLBACK,
	IO_CLEANUP_BACKUP_PREVIOUS,
	IO_REMOVE_STALE_RECOVERY,
	IO_COPY_BACKUP_TO_RECOVERY,
	IO_VALIDATE_RECOVERY_CANDIDATE,
	IO_REMOVE_INVALID_PRIMARY_FOR_RECOVERY,
	IO_COMMIT_BACKUP_RECOVERY,
	IO_VALIDATE_RESTORED_PRIMARY,
]
# END PERSISTENCE_IO_CALLSITES

const ROOM_DEFS := {
	"biomass_filter": {"name": "腐殖滤囊", "cost": 34, "build": 8, "color": "#78b96f", "unlock": "start"},
	"thermal_metabolism": {"name": "热化代谢腔", "cost": 38, "build": 9, "color": "#e1b653", "unlock": "start"},
	"embryo_hatchery": {"name": "胚流孵化室", "cost": 42, "build": 10, "color": "#c77ba7", "unlock": "start"},
	"digestive_pool": {"name": "腐解消化池", "cost": 48, "build": 11, "color": "#9e7ac1", "unlock": "carcass"},
	"synapse_analyzer": {"name": "突触解析腔", "cost": 52, "build": 12, "color": "#5bb8c6", "unlock": "sample"},
	"mutation_culture": {"name": "诱变培养腔", "cost": 58, "build": 13, "color": "#dc785f", "unlock": "mutation"},
}

const UNIT_DEFS := {
	"worker": {"name": "采质工蜂", "cost": 5, "seconds": 5},
	"biter": {"name": "噬咬体", "cost": 6, "seconds": 4},
	"root_spore": {"name": "根脉孢体", "cost": 8, "seconds": 6},
}

const CANDIDATES := [
	{"id": "acid_jaws", "name": "酸蚀颚列", "summary": "噬咬体伤害 +35%", "pressure": "能源负载 +1", "cost": 7, "accent": "#dc785f"},
	{"id": "carrier_membrane", "name": "载流膜翼", "summary": "工蜂回流效率 +50%", "pressure": "工蜂耐久 -10%", "cost": 6, "accent": "#57c4c3"},
	{"id": "dense_brood", "name": "致密育囊", "summary": "孵化速度 +30%", "pressure": "孵化功率 +2", "cost": 7, "accent": "#c77ba7"},
	{"id": "root_resonance", "name": "根网共振", "summary": "菌毯伤害 +40%", "pressure": "孢体形成成本 +1", "cost": 6, "accent": "#82d67b"},
	{"id": "efficient_metabolism", "name": "高效代谢", "summary": "能源供给 +25%", "pressure": "储能上限 -10%", "cost": 5, "accent": "#e2ba60"},
	{"id": "rapid_digest", "name": "裂解酶潮", "summary": "残骸处理速度 +50%", "pressure": "消化功率 +2", "cost": 6, "accent": "#9d86d8"},
]

const NODE_LAYOUT := [
	{"id": "H", "name": "初始虫巢", "role": "虫巢", "pos": [0.12, 0.52], "base_enemy": 0, "structure": 0},
	{"id": "C", "name": "共振前庭", "role": "接触", "pos": [0.30, 0.30], "base_enemy": 12, "structure": 0},
	{"id": "B", "name": "腐殖渗口", "role": "资源", "pos": [0.31, 0.72], "base_enemy": 15, "structure": 0},
	{"id": "P", "name": "增殖压境", "role": "出兵源", "pos": [0.50, 0.18], "base_enemy": 20, "structure": 15},
	{"id": "E", "name": "热裂隘口", "role": "阻断", "pos": [0.54, 0.58], "base_enemy": 24, "structure": 20},
	{"id": "W", "name": "蜕变场", "role": "样本", "pos": [0.52, 0.84], "base_enemy": 18, "structure": 8},
	{"id": "X", "name": "壳层边界", "role": "区域出口", "pos": [0.79, 0.48], "base_enemy": 34, "structure": 28},
]

const NODE_LINKS := [["H", "C"], ["H", "B"], ["C", "P"], ["C", "E"], ["B", "E"], ["B", "W"], ["P", "X"], ["E", "X"], ["W", "X"], ["C", "B"]]

const CANDIDATE_STATE_SCHEMA := {
	"id": "string",
	"name": "string",
	"summary": "string",
	"pressure": "string",
	"cost": "int",
	"accent": "string",
}

const ROOM_STATE_SCHEMA := {
	"slot": "int",
	"kind": "string",
	"state": "string",
	"progress": "float",
	"paused": "bool",
	"task_progress": "float",
	"task_kind": "string",
}

const NODE_STATE_SCHEMA := {
	"id": "string",
	"name": "string",
	"role": "string",
	"pos": {"$tuple": ["float", "float"]},
	"base_enemy": "int",
	"structure": "int",
	"enemy": "int",
	"enemy_max": "int",
	"structure_hp": "int",
	"structure_max": "int",
	"owned": "bool",
	"observed": "bool",
	"assaults": "int",
	"sample_claimed": "bool",
}

const BATTLE_STATE_SCHEMA := {
	"node_id": "string",
	"enemy": "int",
	"enemy_max": "int",
	"structure_hp": "int",
	"structure_max": "int",
	"biter": "int",
	"spore": "int",
	"roots": "int",
	"elapsed": "int",
	"kills": "int",
	"losses": "int",
}

const STATE_SCHEMA := {
	"save_version": "string",
	"seed": "int",
	"tick": "int",
	"running": "bool",
	"paused": "bool",
	"speed": "int",
	"resources": {"biomass": "float", "energy": "float", "genes": "float"},
	"energy": {"supply": "float", "base_load": "float", "task_load": "float", "net": "float", "capacity": "float"},
	"processing": {"field_organic": "float", "field_carcass": "float", "secured_carcass": "float", "field_sample": "float", "secured_sample": "float", "sample_tissue": "float"},
	"units": {"larva": "int", "worker": "int", "biter": "int", "root_spore": "int", "root_mat": "int", "lost": "int", "formed": "int"},
	"targets": {"worker": "int", "biter": "int", "root_spore": "int"},
	"rooms": {"$array": ROOM_STATE_SCHEMA, "$size": 12},
	"nodes": {"$array": NODE_STATE_SCHEMA, "$size": 7},
	"links": {"$array": {"$tuple": ["string", "string"]}, "$size": 10},
	"active_battle": {"$optional": BATTLE_STATE_SCHEMA},
	"candidate_group": {"$optional": {"id": "string", "kind": "string", "source": "string", "options": {"$array": CANDIDATE_STATE_SCHEMA, "$size": 3}}},
	"mutations": {"$array": CANDIDATE_STATE_SCHEMA},
	"unlocks": {"digestive_pool": "bool", "synapse_analyzer": "bool", "mutation_culture": "bool", "active_induction": "bool"},
	"milestones": {"$map": "int"},
	"ledger": {"$array": {"tick": "int", "type": "string", "message": "string", "details": "json"}, "$max": 80},
	"stats": {"biomass_formed": "float", "genes_formed": "float", "enemies_defeated": "int", "nodes_captured": "int", "retreats": "int", "candidate_groups": "int"},
	"adjacent_region": {"unlocked": "bool", "name": "string", "theme": "string", "resource": "string", "hive_condition": "string"},
	"settings": {"ui_scale": "float", "animation": "string", "reduce_flashes": "bool", "master_volume": "float"},
}

var state: Dictionary = {}
var _accumulator := 0.0
var _autosave_elapsed := 0.0
var _persistence_blocked := false
var _reload_required := false
var _last_load_error := ""
var _last_commit_outcome := COMMIT_NOT_COMMITTED
var _decision_pauses := {}

func _ready() -> void:
	set_process(true)

func _process(delta: float) -> void:
	if _persistence_blocked or not _decision_pauses.is_empty() or state.is_empty() or not state.get("running", false) or state.get("paused", false):
		return
	_accumulator += delta * float(state.get("speed", 1))
	_autosave_elapsed += delta
	var steps := 0
	while _accumulator >= 1.0 and steps < 12:
		_accumulator -= 1.0
		advance_one_tick()
		steps += 1
	if _autosave_elapsed >= 30.0:
		_autosave_elapsed = 0.0
		save_game()

func new_game(seed_value: int = 0) -> void:
	if _reject_if_persistence_blocked():
		return
	_persistence_blocked = false
	_reload_required = false
	_last_load_error = ""
	_last_commit_outcome = COMMIT_NOT_COMMITTED
	_decision_pauses.clear()
	_accumulator = 0.0
	_autosave_elapsed = 0.0
	var actual_seed := seed_value if seed_value != 0 else int(Time.get_unix_time_from_system())
	state = {
		"save_version": SAVE_VERSION,
		"seed": actual_seed,
		"tick": 0,
		"running": true,
		"paused": false,
		"speed": 1,
		"resources": {"biomass": 280.0, "energy": 96.0, "genes": 0.0},
		"energy": {"supply": 2.0, "base_load": 1.0, "task_load": 0.0, "net": 1.0, "capacity": 130.0},
		"processing": {"field_organic": 80.0, "field_carcass": 0.0, "secured_carcass": 0.0, "field_sample": 0.0, "secured_sample": 0.0, "sample_tissue": 0.0},
		"units": {"larva": 0, "worker": 0, "biter": 0, "root_spore": 0, "root_mat": 0, "lost": 0, "formed": 0},
		"targets": {"worker": 3, "biter": 18, "root_spore": 6},
		"rooms": _fresh_rooms(),
		"nodes": _generate_nodes(actual_seed),
		"links": NODE_LINKS.duplicate(true),
		"active_battle": {},
		"candidate_group": {},
		"mutations": [],
		"unlocks": {"digestive_pool": false, "synapse_analyzer": false, "mutation_culture": false, "active_induction": false},
		"milestones": {},
		"ledger": [],
		"stats": {"biomass_formed": 0.0, "genes_formed": 0.0, "enemies_defeated": 0, "nodes_captured": 0, "retreats": 0, "candidate_groups": 0},
		"adjacent_region": {"unlocked": false, "name": "硅骨湿原", "theme": "矿化骨板与低温孢尘", "resource": "高密度结构质", "hive_condition": "占领着床节点并保障 120 生物质"},
		"settings": {"ui_scale": 1.0, "animation": "完整", "reduce_flashes": false, "master_volume": 0.8},
	}
	_record("round_started", "初始虫巢已苏醒，区域内容由种子一次提交。")
	_mark("FH-UX-001")
	_mark("FH-UX-002")
	_mark("FH-UX-003")
	_mark("FH-UX-004")
	_emit_change()
	_emit_persistence_recovery_changed()

func _fresh_rooms() -> Array:
	var rooms: Array = []
	for index in range(12):
		rooms.append({"slot": index, "kind": "", "state": "empty", "progress": 0.0, "paused": false, "task_progress": 0.0, "task_kind": ""})
	rooms[5] = {"slot": 5, "kind": "core", "state": "complete", "progress": 1.0, "paused": false, "task_progress": 0.0, "task_kind": ""}
	return rooms

func _generate_nodes(seed_value: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var result: Array = []
	for template in NODE_LAYOUT:
		var node: Dictionary = template.duplicate(true)
		var enemy := int(template.base_enemy)
		if enemy > 0:
			enemy += rng.randi_range(-2, 3)
		node["enemy"] = max(0, enemy)
		node["enemy_max"] = max(0, enemy)
		node["structure_hp"] = int(template.structure)
		node["structure_max"] = int(template.structure)
		node["owned"] = template.id == "H"
		node["observed"] = template.id in ["H", "C", "B"]
		node["assaults"] = 0
		node["sample_claimed"] = false
		result.append(node)
	return result

func has_save(path: String = DEFAULT_SAVE_PATH) -> bool:
	var primary := _fs_path_status(path, IO_HAS_SAVE_PRIMARY)
	if primary.status != SNAPSHOT_MISSING:
		return true
	var backup := _fs_path_status(path + BACKUP_SUFFIX, IO_HAS_SAVE_BACKUP)
	return backup.status != SNAPSHOT_MISSING

func snapshot() -> Dictionary:
	return state.duplicate(true)

func set_speed(value: int) -> void:
	if _reject_if_persistence_blocked():
		return
	if value not in [1, 2, 4]:
		return
	state["speed"] = value
	_emit_change()

func set_paused(value: bool) -> void:
	if _reject_if_persistence_blocked():
		return
	state["paused"] = value
	_emit_change()

func set_decision_pause(source: String, value: bool) -> void:
	if source.is_empty():
		return
	if value and _reject_if_persistence_blocked():
		return
	if value:
		_decision_pauses[source] = true
	else:
		_decision_pauses.erase(source)

func build_room(slot: int, kind: String) -> bool:
	if _reject_if_persistence_blocked():
		return false
	if not ROOM_DEFS.has(kind) or slot < 0 or slot >= state.rooms.size():
		return _reject("无法识别的房间或槽位。")
	if state.rooms[slot].kind != "":
		return _reject("该槽位已经被占用。")
	if not is_room_unlocked(kind):
		return _reject("蓝图尚未满足发现条件。")
	var cost := float(ROOM_DEFS[kind].cost)
	if state.resources.biomass < cost:
		return _reject("生物质不足，结构投入未提交。")
	state.resources.biomass -= cost
	state.rooms[slot] = {"slot": slot, "kind": kind, "state": "building", "progress": 0.0, "paused": false, "task_progress": 0.0, "task_kind": ""}
	_record("room_build_started", "%s 开始构筑。" % ROOM_DEFS[kind].name, {"slot": slot, "kind": kind, "cost": cost})
	_emit_change()
	return true

func cancel_room(slot: int) -> bool:
	if _reject_if_persistence_blocked():
		return false
	if slot < 0 or slot >= state.rooms.size():
		return false
	var room: Dictionary = state.rooms[slot]
	if room.state != "building":
		return _reject("只有未完成的建设可以取消。")
	var refund := float(ROOM_DEFS[room.kind].cost)
	state.resources.biomass += refund
	state.rooms[slot] = {"slot": slot, "kind": "", "state": "empty", "progress": 0.0, "paused": false, "task_progress": 0.0, "task_kind": ""}
	_record("room_build_cancelled", "建设已取消，结构预留完整释放。", {"slot": slot, "refund": refund})
	_emit_change()
	return true

func demolish_room(slot: int) -> bool:
	if _reject_if_persistence_blocked():
		return false
	if slot < 0 or slot >= state.rooms.size():
		return false
	var room: Dictionary = state.rooms[slot]
	if room.kind in ["", "core"] or room.state != "complete":
		return _reject("该结构不能拆除。")
	var refund := float(ROOM_DEFS[room.kind].cost)
	state.resources.biomass += refund
	state.rooms[slot] = {"slot": slot, "kind": "", "state": "empty", "progress": 0.0, "paused": false, "task_progress": 0.0, "task_kind": ""}
	_record("room_demolished", "完整结构投入已回收；已结算时间与能源不倒转。", {"slot": slot, "refund": refund})
	_emit_change()
	return true

func move_room(from_slot: int, to_slot: int) -> bool:
	if _reject_if_persistence_blocked():
		return false
	if from_slot < 0 or to_slot < 0 or from_slot >= state.rooms.size() or to_slot >= state.rooms.size():
		return false
	if state.rooms[from_slot].kind in ["", "core"] or state.rooms[to_slot].kind != "":
		return _reject("移动要求一个可移动房间和一个空槽。")
	var moved: Dictionary = state.rooms[from_slot].duplicate(true)
	moved.slot = to_slot
	state.rooms[to_slot] = moved
	state.rooms[from_slot] = {"slot": from_slot, "kind": "", "state": "empty", "progress": 0.0, "paused": false, "task_progress": 0.0, "task_kind": ""}
	_record("room_moved", "房间完成无损移动，任务与缓冲保持。", {"from": from_slot, "to": to_slot})
	_check_merge_milestone(to_slot)
	_emit_change()
	return true

func set_room_paused(slot: int, value: bool) -> bool:
	if _reject_if_persistence_blocked():
		return false
	if slot < 0 or slot >= state.rooms.size() or state.rooms[slot].kind in ["", "core"]:
		return false
	state.rooms[slot].paused = value
	_record("room_policy_changed", "%s。" % ("房间已暂停" if value else "房间已恢复"), {"slot": slot})
	_emit_change()
	return true

func is_room_unlocked(kind: String) -> bool:
	if not ROOM_DEFS.has(kind):
		return false
	match ROOM_DEFS[kind].unlock:
		"start": return true
		"carcass": return bool(state.unlocks.digestive_pool)
		"sample": return bool(state.unlocks.synapse_analyzer)
		"mutation": return bool(state.unlocks.mutation_culture)
	return false

func set_unit_target(kind: String, delta: int) -> void:
	if _reject_if_persistence_blocked():
		return
	if not state.targets.has(kind):
		return
	state.targets[kind] = max(0, int(state.targets[kind]) + delta)
	_emit_change()

func attack_node(node_id: String) -> bool:
	if _reject_if_persistence_blocked():
		return false
	if not state.active_battle.is_empty():
		return _reject("当前已有一个主动战场。")
	var node := _node(node_id)
	if node.is_empty() or node.owned or not node.observed:
		return _reject("该节点当前不可进攻。")
	if not _has_owned_neighbor(node_id):
		return _reject("没有与该节点连通的已占领入口。")
	var biter := int(state.units.biter)
	var spores := int(state.units.root_spore)
	if biter + spores <= 0:
		return _reject("虫群大军中没有可参战单位。")
	state.units.biter = 0
	state.units.root_spore = 0
	state.active_battle = {
		"node_id": node_id,
		"enemy": int(node.enemy),
		"enemy_max": int(node.enemy_max),
		"structure_hp": int(node.structure_hp),
		"structure_max": int(node.structure_max),
		"biter": biter,
		"spore": spores,
		"roots": 0,
		"elapsed": 0,
		"kills": 0,
		"losses": 0,
	}
	node.assaults = int(node.assaults) + 1
	_mark("FH-006")
	if int(node.assaults) > 1:
		_mark("FH-007")
	_record("battle_started", "虫群已全部提交至 %s。" % node.name, {"node_id": node_id, "biter": biter, "spore": spores})
	battle_started.emit(node_id)
	_emit_change()
	return true

func retreat() -> bool:
	if _reject_if_persistence_blocked():
		return false
	if state.active_battle.is_empty():
		return _reject("没有可以撤离的主动战场。")
	var node_id := String(state.active_battle.node_id)
	var candidate := _build_retreat_candidate()
	var normalized := _normalize_state(candidate)
	if not normalized.ok:
		return _reject("撤离候选状态校验失败：%s；当前战场和存档保持不变。" % normalized.error)
	var commit := _commit_snapshot(DEFAULT_SAVE_PATH, normalized.state)
	if commit.outcome == COMMIT_UNCERTAIN:
		return _fail_persistence("撤离存档已越过提交点，但结果无法确认：%s 当前内存未安装候选；请重新载入决定权威状态。" % commit.error, true)
	if commit.outcome != COMMIT_COMMITTED:
		return _reject("撤离持久化失败：%s 当前战场和存档保持不变，可重试。" % commit.error)
	state = normalized.state
	notice_posted.emit("撤离原子提交：可机动单位已回归，固定菌毯留置，敌军开始有源恢复。", "info")
	battle_ended.emit(node_id, false)
	_emit_change()
	return true

func _build_retreat_candidate() -> Dictionary:
	var candidate := state.duplicate(true)
	var battle: Dictionary = candidate.active_battle
	var node: Dictionary = {}
	for candidate_node in candidate.nodes:
		if String(candidate_node.id) == String(battle.node_id):
			node = candidate_node
			break
	candidate.units.biter += int(battle.biter)
	candidate.units.root_spore += int(battle.spore)
	candidate.units.root_mat += int(battle.roots)
	node.enemy = min(int(node.enemy_max), int(battle.enemy) + max(1, int(ceil(float(node.enemy_max) * 0.15))))
	node.structure_hp = int(battle.structure_hp)
	candidate.stats.retreats += 1
	if not candidate.milestones.has("FH-007"):
		candidate.milestones["FH-007"] = int(candidate.tick)
	candidate.ledger.push_front({
		"tick": int(candidate.tick),
		"type": "battle_retreated",
		"message": "撤离原子提交：可机动单位已回归，固定菌毯留置，敌军开始有源恢复。",
		"details": {"node_id": node.id},
	})
	if candidate.ledger.size() > 80:
		candidate.ledger.resize(80)
	candidate.active_battle = {}
	return candidate

func induce_candidate() -> bool:
	if _reject_if_persistence_blocked():
		return false
	if not state.unlocks.active_induction:
		return _reject("主动诱导尚未解锁。")
	if not state.candidate_group.is_empty():
		return _reject("普通候选槽已被占用。")
	if state.resources.genes < 8.0:
		return _reject("主动诱导需要 8 基因。")
	state.resources.genes -= 8.0
	_form_candidate_group("ordinary", "主动诱导")
	_emit_change()
	return true

func culture_candidate() -> bool:
	if _reject_if_persistence_blocked():
		return false
	if not state.unlocks.mutation_culture or not _has_complete_room("mutation_culture"):
		return _reject("需要运行中的诱变培养腔。")
	if not state.candidate_group.is_empty():
		return _reject("普通候选槽已被占用。")
	if state.resources.biomass < 18.0:
		return _reject("培养候选需要 18 生物质。")
	state.resources.biomass -= 18.0
	_form_candidate_group("ordinary", "诱变培养腔")
	_emit_change()
	return true

func select_candidate(candidate_id: String) -> bool:
	if _reject_if_persistence_blocked():
		return false
	if state.candidate_group.is_empty():
		return _reject("当前没有候选组。")
	var selected: Dictionary = {}
	for candidate in state.candidate_group.options:
		if candidate.id == candidate_id:
			selected = candidate
			break
	if selected.is_empty():
		return _reject("候选不属于当前持有组。")
	if state.resources.genes < float(selected.cost):
		return _reject("基因不足，同化没有发生。")
	state.resources.genes -= float(selected.cost)
	var group_kind: String = state.candidate_group.kind
	state.mutations.append(selected.duplicate(true))
	state.candidate_group = {}
	if group_kind == "first":
		state.unlocks.mutation_culture = true
		state.unlocks.active_induction = true
		_mark("FH-010")
	else:
		_mark("FH-012")
	_record("mutation_assimilated", "已同化 %s；同组其他候选消失。" % selected.name, {"candidate_id": selected.id, "group_kind": group_kind})
	_emit_change()
	return true

func advance_steps(count: int) -> void:
	for index in range(max(0, count)):
		advance_one_tick()

func advance_one_tick() -> void:
	if _persistence_blocked or state.is_empty():
		return
	state.tick += 1
	_update_energy()
	_update_rooms()
	_update_logistics()
	_update_battle()
	if state.tick == 4:
		_mark("FH-003")
	if state.tick % 2 == 0:
		_emit_change()

func _update_energy() -> void:
	var thermal_count := _count_complete_rooms("thermal_metabolism", false)
	var supply := 2.0 + float(thermal_count) * 9.0
	if _has_mutation("efficient_metabolism"):
		supply *= 1.25
	var base_load := 1.0 + float(_count_complete_rooms("", true)) * 0.8
	var task_load := float(_count_building_rooms()) * 2.5
	if not state.active_battle.is_empty():
		task_load += 2.0
	if _has_mutation("acid_jaws"):
		base_load += 1.0
	var capacity: float = maxf(80.0, 130.0 + float(thermal_count) * 35.0)
	if _has_mutation("efficient_metabolism"):
		capacity *= 0.9
	var net := supply - base_load - task_load
	state.resources.energy = clamp(float(state.resources.energy) + net, 0.0, capacity)
	state.energy = {"supply": supply, "base_load": base_load, "task_load": task_load, "net": net, "capacity": capacity}

func _update_rooms() -> void:
	for index in range(state.rooms.size()):
		var room: Dictionary = state.rooms[index]
		if room.kind in ["", "core"] or room.paused:
			continue
		if room.state == "building":
			if state.resources.energy <= 0.0 and room.kind != "thermal_metabolism":
				continue
			room.progress += 1.0 / float(ROOM_DEFS[room.kind].build)
			if room.progress >= 1.0:
				room.progress = 1.0
				room.state = "complete"
				_record("room_completed", "%s 已接入虫巢网络。" % ROOM_DEFS[room.kind].name, {"slot": index, "kind": room.kind})
				_check_merge_milestone(index)
			state.rooms[index] = room
			continue
		match room.kind:
			"biomass_filter": _tick_filter(room, index)
			"embryo_hatchery": _tick_hatchery(room, index)
			"digestive_pool": _tick_digestive(room, index)
			"synapse_analyzer": _tick_analyzer(room, index)

func _tick_filter(room: Dictionary, index: int) -> void:
	if state.processing.field_organic <= 0.0:
		return
	room.task_progress += 1.0
	if room.task_progress >= 6.0:
		room.task_progress = 0.0
		var formed: float = minf(6.0, float(state.processing.field_organic))
		state.processing.field_organic -= formed
		if state.units.worker > 0:
			state.resources.biomass += formed
			state.stats.biomass_formed += formed
			_mark("FH-002")
			_record("biomass_delivered", "工蜂把腐殖滤囊的物理输出投递到账本。", {"amount": formed})
		else:
			state.processing.field_organic += formed
		_mark("FH-001")
		_trigger_mutation_effect("production")
	state.rooms[index] = room

func _tick_hatchery(room: Dictionary, index: int) -> void:
	var kind := String(room.task_kind)
	if kind == "":
		for candidate_kind in ["worker", "biter", "root_spore"]:
			if _available_unit_count(candidate_kind) < int(state.targets[candidate_kind]):
				kind = candidate_kind
				break
		if kind == "":
			room.task_progress = 0.0
			state.rooms[index] = room
			return
		room.task_kind = kind
	var unit_def: Dictionary = UNIT_DEFS[kind]
	if state.resources.biomass < float(unit_def.cost):
		state.rooms[index] = room
		return
	room.task_progress += 1.3 if _has_mutation("dense_brood") else 1.0
	if room.task_progress >= float(unit_def.seconds):
		state.resources.biomass -= float(unit_def.cost)
		state.units[kind] += 1
		state.units.formed += 1
		room.task_progress = 0.0
		room.task_kind = ""
		_record("unit_formed", "%s 完成等量分化并离巢。" % unit_def.name, {"kind": kind})
	state.rooms[index] = room

func _tick_digestive(room: Dictionary, index: int) -> void:
	var has_sample: bool = float(state.processing.secured_sample) > 0.0
	var has_carcass: bool = float(state.processing.secured_carcass) > 0.0
	if not has_sample and not has_carcass:
		return
	room.task_progress += 1.5 if _has_mutation("rapid_digest") else 1.0
	if room.task_progress >= 5.0:
		room.task_progress = 0.0
		if has_sample:
			state.processing.secured_sample -= 1.0
			state.processing.sample_tissue += 1.0
			state.unlocks.synapse_analyzer = true
			_record("sample_separated", "固定样本完成残骸分离，样本组织进入解析链。")
		else:
			var amount: float = minf(4.0, float(state.processing.secured_carcass))
			state.processing.secured_carcass -= amount
			state.resources.biomass += amount * 1.5
			state.stats.biomass_formed += amount * 1.5
			_mark("FH-008")
			_record("carcass_digested", "普通残骸经腐解与投递形成生物质。", {"amount": amount * 1.5})
	state.rooms[index] = room

func _tick_analyzer(room: Dictionary, index: int) -> void:
	if state.processing.sample_tissue <= 0.0:
		return
	room.task_progress += 1.0
	if room.task_progress >= 7.0:
		room.task_progress = 0.0
		state.processing.sample_tissue -= 1.0
		state.resources.genes += 34.0
		state.stats.genes_formed += 34.0
		_mark("FH-009")
		if state.mutations.is_empty() and state.candidate_group.is_empty():
			_form_candidate_group("first", "首次样本解析")
		_record("sample_analyzed", "突触解析形成 34 基因、样本标签与首次候选机会。")
	state.rooms[index] = room

func _update_logistics() -> void:
	var workers := int(state.units.worker)
	if workers <= 0:
		return
	var capacity: float = maxf(1.0, float(workers) * (1.5 if _has_mutation("carrier_membrane") else 1.0))
	if state.processing.field_sample > 0.0:
		var sample_amount: float = minf(capacity, float(state.processing.field_sample))
		state.processing.field_sample -= sample_amount
		state.processing.secured_sample += sample_amount
		capacity -= sample_amount
	if capacity > 0.0 and state.processing.field_carcass > 0.0:
		var carcass_amount: float = minf(capacity, float(state.processing.field_carcass))
		state.processing.field_carcass -= carcass_amount
		state.processing.secured_carcass += carcass_amount
	if state.processing.field_carcass > 0.0 or state.processing.secured_carcass > 0.0:
		state.unlocks.digestive_pool = true

func _update_battle() -> void:
	if state.active_battle.is_empty():
		return
	var battle: Dictionary = state.active_battle
	battle.elapsed += 1
	if battle.spore > 0 and battle.elapsed % 2 == 0:
		battle.spore -= 1
		battle.roots += 1
		_mark("FH-005")
	var attack_power := float(battle.biter) * 1.05 + float(battle.roots) * 1.25
	if _has_mutation("acid_jaws"):
		attack_power *= 1.35
	if _has_mutation("root_resonance"):
		attack_power += float(battle.roots) * 0.5
	var enemy_kills: int = mini(int(battle.enemy), maxi(1, int(floor(attack_power / 8.0)))) if attack_power > 0 else 0
	battle.enemy -= enemy_kills
	battle.kills += enemy_kills
	state.stats.enemies_defeated += enemy_kills
	state.processing.field_carcass += float(enemy_kills)
	if battle.elapsed % 3 == 0 and battle.enemy > 0:
		var losses: int = mini(int(battle.biter), maxi(0, int(floor(float(battle.enemy) / 18.0))))
		battle.biter -= losses
		battle.losses += losses
		state.units.lost += losses
	if battle.enemy <= 0 and battle.structure_hp > 0:
		battle.structure_hp = max(0, int(battle.structure_hp) - max(1, int(floor(attack_power / 10.0))))
	if battle.biter + battle.spore + battle.roots <= 0:
		var failed_node := _node(battle.node_id)
		failed_node.enemy = int(battle.enemy)
		failed_node.structure_hp = int(battle.structure_hp)
		state.active_battle = {}
		_mark("FH-007")
		_record("army_destroyed", "虫群全灭；节点状态保留，可重新形成军队后再进入。")
		battle_ended.emit(failed_node.id, false)
		_emit_change()
		return
	if battle.enemy <= 0 and battle.structure_hp <= 0:
		_capture_active_node(battle)
		return
	state.active_battle = battle
	_trigger_mutation_effect("battle")

func _capture_active_node(battle: Dictionary) -> void:
	var node := _node(battle.node_id)
	node.enemy = 0
	node.structure_hp = 0
	node.owned = true
	state.units.biter += int(battle.biter)
	state.units.root_spore += int(battle.spore)
	state.units.root_mat += int(battle.roots)
	state.stats.nodes_captured += 1
	state.processing.field_organic += 35.0 if node.id == "B" else 12.0
	if node.id == "W" and not node.sample_claimed:
		node.sample_claimed = true
		state.processing.field_sample += 1.0
	for neighbor_id in _neighbors(node.id):
		_node(neighbor_id).observed = true
	_mark("FH-013")
	if node.id == "X":
		state.adjacent_region.unlocked = true
		_mark("FH-014")
	_record("node_captured", "%s 已安全占领；移动单位回归，外部来源开放。" % node.name, {"node_id": node.id})
	state.active_battle = {}
	battle_ended.emit(node.id, true)
	save_game()
	_emit_change()

func _form_candidate_group(kind: String, source: String) -> void:
	var start := int((int(state.seed) + int(state.stats.candidate_groups) * 2) % CANDIDATES.size())
	var options: Array = []
	for offset in range(3):
		options.append(CANDIDATES[(start + offset * 2) % CANDIDATES.size()].duplicate(true))
	state.candidate_group = {"id": "group_%d" % (int(state.stats.candidate_groups) + 1), "kind": kind, "source": source, "options": options}
	state.stats.candidate_groups += 1
	_record("candidate_group_formed", "%s形成一个全局候选组；整个组占用一个槽位。" % source, {"kind": kind})

func ascension_preview() -> Dictionary:
	if state.is_empty():
		return {}
	var contributions := [
		{"name": "区域吞噬", "value": int(state.stats.nodes_captured) * 14},
		{"name": "外源同化", "value": int(state.stats.biomass_formed / 10.0)},
		{"name": "虫群规模", "value": int(state.units.formed / 2)},
		{"name": "战场适应", "value": int(state.stats.enemies_defeated / 5)},
		{"name": "基因解析", "value": int(state.stats.genes_formed / 4.0)},
		{"name": "构筑深度", "value": state.mutations.size() * 12},
	]
	var points := 0
	for item in contributions:
		points += int(item.value)
	return {
		"points": points,
		"contributions": contributions,
		"permanents": [
			{"name": "初始生物质", "current": 0, "next": 18, "cost": 24},
			{"name": "初始储能", "current": 0, "next": 12, "cost": 20},
			{"name": "工蜂韧性", "current": "0%", "next": "+5%", "cost": 28},
			{"name": "房间构筑", "current": "0%", "next": "+4%", "cost": 30},
			{"name": "样本解析", "current": "0%", "next": "+6%", "cost": 32},
			{"name": "地图情报", "current": "1 层", "next": "2 层", "cost": 36},
		],
		"leaders": [
			{"name": "母巢·赫卡忒", "strength": "房间吞吐与恢复", "weakness": "战场推进较慢"},
			{"name": "猎群·伊克西昂", "strength": "接触面与追猎", "weakness": "结构生产负载高"},
			{"name": "根网·弥赛亚", "strength": "菌毯控制与留置", "weakness": "机动单位形成较慢"},
		],
	}

func completion_summary() -> Dictionary:
	var completed: Array = []
	for id in state.get("milestones", {}).keys():
		if str(id).begins_with("FH-") and not str(id).begins_with("FH-UX"):
			completed.append(id)
	return {"completed": completed.size(), "total": 14, "is_complete": completed.size() >= 14, "ids": completed}

func save_game(path: String = DEFAULT_SAVE_PATH) -> bool:
	if state.is_empty():
		return false
	if _persistence_blocked:
		return _reject("存档提交结果待确认，模拟、操作与保存已冻结；请重新载入。")
	var normalized := _normalize_state(state)
	if not normalized.ok:
		return _fail_persistence("当前状态校验失败：%s；未写入存档。" % normalized.error)
	var commit := _commit_snapshot(path, normalized.state)
	if commit.outcome == COMMIT_UNCERTAIN:
		return _fail_persistence("存档提交结果无法确认：%s 模拟、操作与保存已冻结；请重新载入。" % commit.error, true)
	if commit.outcome != COMMIT_COMMITTED:
		return _reject(commit.error)
	state = normalized.state
	notice_posted.emit(commit.get("warning", "已保存至本地存档槽"), "warning" if commit.has("warning") else "success")
	return true

func load_game(path: String = DEFAULT_SAVE_PATH) -> bool:
	var primary := _read_snapshot(path, IO_LOAD_PRIMARY)
	var recovered := false
	if primary.status == SNAPSHOT_IO_ERROR:
		return _fail_persistence("主槽读取发生 I/O 错误（%s）；未读取备份，所有文件保持不变。" % primary.error)
	if primary.status in [SNAPSHOT_MISSING, SNAPSHOT_CORRUPT]:
		var backup := _read_snapshot(path + BACKUP_SUFFIX, IO_LOAD_BACKUP)
		if not backup.ok:
			return _fail_persistence("主槽不可用（%s），备份也不可用（%s）；所有文件保持不变。" % [primary.error, backup.error])
		var recovery := _restore_backup(path, primary.status)
		if not recovery.ok:
			return _fail_persistence("备份有效但主槽恢复失败：%s；备份保持不变。" % recovery.error)
		primary = backup
		recovered = true
	state = primary.state
	state.running = true
	_persistence_blocked = false
	_reload_required = false
	_last_load_error = ""
	_decision_pauses.clear()
	_accumulator = 0.0
	_autosave_elapsed = 0.0
	var preserve_previous := _reconcile_backup_protection(path)
	var cleanup := _cleanup_transaction_scratch(path, preserve_previous)
	_record("save_recovered" if recovered else "save_loaded", "主槽不可用，已从验证通过的备份恢复。" if recovered else "本地存档已恢复，地图与候选不会重抽。")
	if not cleanup.ok:
		notice_posted.emit("存档已重新载入，但事务临时文件清理失败：%s" % cleanup.error, "warning")
	_emit_change()
	_emit_persistence_recovery_changed()
	return true

func _reconcile_backup_protection(path: String) -> bool:
	var previous_path := path + BACKUP_PREVIOUS_SUFFIX
	var previous := _read_snapshot(previous_path, IO_VALIDATE_PREVIOUS_BACKUP)
	if previous.status == SNAPSHOT_MISSING:
		return false
	if not previous.ok:
		return true
	var backup_path := path + BACKUP_SUFFIX
	var backup := _read_snapshot(backup_path, IO_INSPECT_EXISTING_BACKUP)
	if backup.ok:
		return false
	if backup.status == SNAPSHOT_IO_ERROR:
		return true
	var restore_error := _restore_copy(previous_path, backup_path, IO_RESTORE_PREVIOUS_BACKUP_CLEANUP, IO_RESTORE_PREVIOUS_BACKUP_COPY, IO_VALIDATE_RESTORE_PREVIOUS_BACKUP, IO_RESTORE_PREVIOUS_BACKUP_DESTINATION, IO_RESTORE_PREVIOUS_BACKUP_COMMIT)
	return restore_error != OK

func _commit_snapshot(path: String, snapshot: Dictionary) -> Dictionary:
	_last_commit_outcome = COMMIT_NOT_COMMITTED
	var base_dir := path.get_base_dir()
	if not base_dir.is_empty():
		var mkdir_error := _fs_make_dir(ProjectSettings.globalize_path(base_dir), IO_CREATE_SAVE_DIRECTORY)
		if mkdir_error != OK:
			return _commit_error("无法创建存档目录（%s）。" % mkdir_error)
	var temp_path := path + SAVE_TEMP_SUFFIX
	var stale_temp_error := _remove_if_exists(temp_path, IO_REMOVE_STALE_SAVE_TEMP)
	if stale_temp_error != OK:
		return _not_committed_after_cleanup(path, "无法清理旧临时存档（%s）。" % stale_temp_error)
	var write_error := _write_snapshot_file(temp_path, snapshot, IO_WRITE_STAGED_SNAPSHOT)
	if write_error != OK:
		return _not_committed_after_cleanup(path, "无法完整写入临时存档（%s）。" % write_error)
	var staged := _read_snapshot(temp_path, IO_VALIDATE_STAGED_SNAPSHOT)
	if not staged.ok:
		return _not_committed_after_cleanup(path, "临时存档校验失败：%s。" % staged.error)
	var primary := _read_snapshot(path, IO_INSPECT_EXISTING_PRIMARY)
	if primary.status == SNAPSHOT_IO_ERROR:
		return _not_committed_after_cleanup(path, "现有主槽读取发生 I/O 错误：%s；拒绝写入。" % primary.error)
	if primary.status == SNAPSHOT_CORRUPT:
		return _not_committed_after_cleanup(path, "现有主槽损坏，拒绝自动覆盖；请先继续游戏以恢复备份。")
	if primary.ok:
		var backup_preparation := _prepare_backup(path)
		if not backup_preparation.ok:
			return _not_committed_after_cleanup(path, backup_preparation.error)
		var rollback_preparation := _prepare_primary_rollback(path)
		if not rollback_preparation.ok:
			if rollback_preparation.get("outcome", COMMIT_NOT_COMMITTED) == COMMIT_UNCERTAIN:
				return rollback_preparation
			return _not_committed_after_cleanup(path, rollback_preparation.error)
		var primary_commit := _commit_primary(path)
		if primary_commit.outcome == COMMIT_UNCERTAIN:
			return primary_commit
		if primary_commit.outcome != COMMIT_COMMITTED:
			return _not_committed_after_cleanup(path, primary_commit.error)
		var backup_commit := _commit_prepared_backup(path, bool(backup_preparation.had_backup))
		var committed_cleanup := _cleanup_transaction_scratch(path, bool(backup_commit.get("preserve_previous", false)))
		var warnings: Array[String] = []
		if not backup_commit.ok:
			warnings.append(backup_commit.error)
		if not committed_cleanup.ok:
			warnings.append(committed_cleanup.error)
		return _commit_success("存档主槽已提交，但保护维护需要关注：%s" % " ".join(warnings) if not warnings.is_empty() else "")
	else:
		var first_commit_error := _fs_rename(temp_path, path, IO_COMMIT_FIRST_PRIMARY)
		if first_commit_error != OK:
			return _not_committed_after_cleanup(path, "首次主槽提交失败（%s）。" % first_commit_error)
		var first_primary := _read_snapshot(path, IO_VALIDATE_FIRST_PRIMARY)
		if first_primary.status == SNAPSHOT_IO_ERROR:
			return _commit_uncertain("首次主槽提交后读取发生 I/O 错误：%s。" % first_primary.error)
		if not first_primary.ok:
			var remove_invalid := _remove_if_exists(path, IO_REMOVE_INVALID_COMMITTED_SLOT)
			if remove_invalid != OK:
				return _commit_uncertain("首次主槽提交后损坏且无法移除（%s）。" % remove_invalid)
			return _not_committed_after_cleanup(path, "首次主槽提交后校验失败，已移除无效主槽。")
		var first_cleanup := _cleanup_transaction_scratch(path)
		return _commit_success("首次主槽已提交，但临时文件清理失败：%s" % first_cleanup.error if not first_cleanup.ok else "")

func _prepare_backup(path: String) -> Dictionary:
	var backup_path := path + BACKUP_SUFFIX
	var backup_temp := path + BACKUP_TEMP_SUFFIX
	var previous_backup := path + BACKUP_PREVIOUS_SUFFIX
	var cleanup_temp := _remove_if_exists(backup_temp, IO_REMOVE_STALE_BACKUP_TEMP)
	if cleanup_temp != OK:
		return _commit_error("无法清理旧备份临时文件（%s）。" % cleanup_temp)
	var copy_primary := _fs_copy(path, backup_temp, IO_COPY_PRIMARY_TO_BACKUP_TEMP)
	if copy_primary != OK:
		return _commit_error("无法复制主槽到备份候选（%s）。" % copy_primary)
	var backup_candidate := _read_snapshot(backup_temp, IO_VALIDATE_BACKUP_CANDIDATE)
	if not backup_candidate.ok:
		return _commit_error("备份候选校验失败：%s。" % backup_candidate.error)
	var existing_backup := _read_snapshot(backup_path, IO_INSPECT_EXISTING_BACKUP)
	if existing_backup.status == SNAPSHOT_IO_ERROR:
		return _commit_error("现有备份读取发生 I/O 错误：%s；拒绝替换。" % existing_backup.error)
	var preserved_previous := false
	if existing_backup.ok:
		var cleanup_previous := _remove_if_exists(previous_backup, IO_REMOVE_STALE_BACKUP_PREVIOUS)
		if cleanup_previous != OK:
			return _commit_error("无法清理旧备份保护副本（%s）。" % cleanup_previous)
		var preserve_error := _fs_copy(backup_path, previous_backup, IO_COPY_EXISTING_BACKUP_TO_PREVIOUS)
		if preserve_error != OK:
			return _commit_error("无法保护已承诺备份（%s）。" % preserve_error)
		var previous_check := _read_snapshot(previous_backup, IO_VALIDATE_PREVIOUS_BACKUP)
		if not previous_check.ok:
			return _commit_error("已承诺备份保护副本校验失败：%s。" % previous_check.error)
		preserved_previous = true
	return {"ok": true, "error": "", "had_backup": existing_backup.ok, "preserved_previous": preserved_previous}

func _commit_prepared_backup(path: String, had_backup: bool) -> Dictionary:
	var backup_path := path + BACKUP_SUFFIX
	var backup_temp := path + BACKUP_TEMP_SUFFIX
	var previous_backup := path + BACKUP_PREVIOUS_SUFFIX
	var destination := _fs_path_status(backup_path, IO_INSPECT_BACKUP_COMMIT_DESTINATION)
	if destination.status == SNAPSHOT_IO_ERROR:
		return _commit_error("备份提交点状态无法确认（%s）；主槽已提交。" % destination.error_code)
	var commit_backup := _fs_rename(backup_temp, backup_path, IO_COMMIT_BACKUP)
	if commit_backup != OK:
		return _commit_error("备份提交失败（%s）；原备份未被触碰，主槽已提交。" % commit_backup)
	var committed_backup := _read_snapshot(backup_path, IO_VALIDATE_COMMITTED_BACKUP)
	if committed_backup.ok:
		return {"ok": true, "error": ""}
	if committed_backup.status == SNAPSHOT_IO_ERROR:
		return {"ok": false, "error": "备份提交后读取结果不确定：%s；旧备份保护副本仍保留，主槽已提交。" % committed_backup.error, "preserve_previous": had_backup}
	if had_backup:
		var restore_error := _restore_copy(previous_backup, backup_path, IO_RESTORE_PREVIOUS_BACKUP_CLEANUP, IO_RESTORE_PREVIOUS_BACKUP_COPY, IO_VALIDATE_RESTORE_PREVIOUS_BACKUP, IO_RESTORE_PREVIOUS_BACKUP_DESTINATION, IO_RESTORE_PREVIOUS_BACKUP_COMMIT)
		if restore_error != OK:
			return {"ok": false, "error": "备份提交后损坏且旧备份恢复失败（%s）；保护副本仍保留，主槽已提交。" % restore_error, "preserve_previous": true}
		return _commit_error("备份提交后损坏，已恢复旧备份；主槽已提交。")
	var remove_invalid := _remove_if_exists(backup_path, IO_REMOVE_INVALID_COMMITTED_SLOT)
	return _commit_error("首个备份提交后损坏，已移除无效备份；主槽已提交。" if remove_invalid == OK else "首个备份提交后损坏且无法移除（%s）；主槽已提交。" % remove_invalid)

func _prepare_primary_rollback(path: String) -> Dictionary:
	var rollback_path := path + ROLLBACK_SUFFIX
	var cleanup_rollback := _remove_if_exists(rollback_path, IO_REMOVE_STALE_ROLLBACK)
	if cleanup_rollback != OK:
		return _commit_error("无法清理旧主槽回滚副本（%s）。" % cleanup_rollback)
	var move_rollback := _fs_rename(path, rollback_path, IO_MOVE_PRIMARY_TO_ROLLBACK)
	if move_rollback != OK:
		return _commit_error("无法原子保留旧主槽目录项（%s）。" % move_rollback)
	var rollback_check := _read_snapshot(rollback_path, IO_VALIDATE_ROLLBACK)
	if not rollback_check.ok:
		var restore := _restore_primary_rollback_entry(path)
		if restore.ok:
			return _commit_error("旧主槽目录项校验失败（%s），已原子恢复。" % rollback_check.error)
		return _commit_uncertain("旧主槽已移至回滚目录项，但校验与恢复均失败（%s/%s）；必须重新载入。" % [rollback_check.error, restore.error])
	return {"ok": true, "error": ""}

func _commit_primary(path: String) -> Dictionary:
	var temp_path := path + SAVE_TEMP_SUFFIX
	var destination := _fs_path_status(path, IO_INSPECT_VACATED_PRIMARY_DESTINATION)
	if destination.status != SNAPSHOT_MISSING:
		var destination_restore := _restore_primary_rollback_entry(path)
		if destination_restore.ok:
			return _commit_error("主槽提交点未保持空闲（%s），已恢复旧主槽。" % destination.error_code)
		return _commit_uncertain("主槽提交点状态异常且旧主槽无法恢复（%s/%s）；必须重新载入。" % [destination.error_code, destination_restore.error])
	var commit_primary := _fs_rename(temp_path, path, IO_COMMIT_PRIMARY)
	if commit_primary != OK:
		var failed_commit_restore := _restore_primary_rollback_entry(path)
		if failed_commit_restore.ok:
			return _commit_error("主槽原子提交失败（%s），已恢复原目录项。" % commit_primary)
		return _commit_uncertain("主槽提交失败且旧目录项无法恢复（%s/%s）；必须重新载入。" % [commit_primary, failed_commit_restore.error])
	var committed_primary := _read_snapshot(path, IO_VALIDATE_COMMITTED_PRIMARY)
	if committed_primary.status == SNAPSHOT_IO_ERROR:
		return _commit_uncertain("新主槽提交后读取发生 I/O 错误：%s；结果必须由重新载入决定。" % committed_primary.error)
	if not committed_primary.ok:
		var rollback := _restore_primary_rollback_entry(path)
		if rollback.ok:
			return _commit_error("新主槽校验失败，已原子恢复提交前主槽。")
		var backup_fallback := _restore_copy(path + BACKUP_SUFFIX, path, IO_RESTORE_INVALID_PRIMARY_FROM_BACKUP_CLEANUP, IO_RESTORE_INVALID_PRIMARY_FROM_BACKUP_COPY, IO_VALIDATE_RESTORE_INVALID_PRIMARY_FROM_BACKUP, IO_RESTORE_INVALID_PRIMARY_FROM_BACKUP_DESTINATION, IO_RESTORE_INVALID_PRIMARY_FROM_BACKUP_COMMIT)
		if backup_fallback == OK:
			return _commit_uncertain("新主槽校验失败；原目录项恢复无法确认（%s），已恢复可加载备份，但权威状态仍须重新载入。" % rollback.error)
		return _commit_uncertain("新主槽损坏，主槽回滚与备份恢复均失败（%s/%s）；必须重新载入。" % [rollback.error, backup_fallback])
	return _commit_success()

func _restore_primary_rollback_entry(path: String) -> Dictionary:
	var rollback_path := path + ROLLBACK_SUFFIX
	var source := _fs_path_status(rollback_path, IO_INSPECT_ROLLBACK_RESTORE_SOURCE)
	if source.status != PATH_EXISTS:
		return _commit_error("旧主槽回滚目录项不可确认（%s）。" % source.error_code)
	var source_snapshot := _read_snapshot(rollback_path, IO_VALIDATE_ROLLBACK_RESTORE_SOURCE)
	if not source_snapshot.ok:
		return _commit_error("旧主槽回滚目录项不可验证：%s。" % source_snapshot.error)
	var destination := _fs_path_status(path, IO_INSPECT_ROLLBACK_RESTORE_DESTINATION)
	if destination.status == SNAPSHOT_IO_ERROR:
		return _commit_error("主槽恢复目标状态不可确认（%s）。" % destination.error_code)
	var restore := _fs_rename(rollback_path, path, IO_RESTORE_PRIMARY_ROLLBACK_ENTRY)
	if restore != OK:
		return _commit_error("旧主槽目录项原子恢复失败（%s）。" % restore)
	var restored := _read_snapshot(path, IO_VALIDATE_RESTORED_PRIMARY_ROLLBACK)
	if not restored.ok:
		return _commit_error("原子恢复后的旧主槽无法验证：%s。" % restored.error)
	return {"ok": true, "error": ""}

func _restore_backup(path: String, primary_status: String) -> Dictionary:
	var backup_path := path + BACKUP_SUFFIX
	var recovery_path := path + RECOVERY_SUFFIX
	var cleanup_recovery := _remove_if_exists(recovery_path, IO_REMOVE_STALE_RECOVERY)
	if cleanup_recovery != OK:
		return _commit_error("无法清理旧恢复临时文件（%s）。" % cleanup_recovery)
	var copy_backup := _fs_copy(backup_path, recovery_path, IO_COPY_BACKUP_TO_RECOVERY)
	if copy_backup != OK:
		return _commit_error("无法复制备份到恢复候选（%s）。" % copy_backup)
	var recovery_check := _read_snapshot(recovery_path, IO_VALIDATE_RECOVERY_CANDIDATE)
	if not recovery_check.ok:
		return _commit_error("恢复候选校验失败：%s。" % recovery_check.error)
	if primary_status == SNAPSHOT_CORRUPT:
		var remove_primary := _fs_remove(path, IO_REMOVE_INVALID_PRIMARY_FOR_RECOVERY)
		if remove_primary != OK:
			return _commit_error("无法移除无效主槽（%s）。" % remove_primary)
	var commit_recovery := _fs_rename(recovery_path, path, IO_COMMIT_BACKUP_RECOVERY)
	if commit_recovery != OK:
		return _commit_error("无法提交备份恢复（%s）。" % commit_recovery)
	var restored := _read_snapshot(path, IO_VALIDATE_RESTORED_PRIMARY)
	if not restored.ok:
		return _commit_error("备份恢复后主槽校验失败：%s。" % restored.error)
	return {"ok": true, "error": ""}

func _restore_copy(source: String, destination: String, cleanup_io: String, copy_io: String, validate_io: String, destination_io: String, commit_io: String) -> Error:
	var recovery_path := destination + RECOVERY_SUFFIX
	var cleanup_recovery := _remove_if_exists(recovery_path, cleanup_io)
	if cleanup_recovery != OK:
		return cleanup_recovery
	var copy_error := _fs_copy(source, recovery_path, copy_io)
	if copy_error != OK:
		return copy_error
	var recovery_check := _read_snapshot(recovery_path, validate_io)
	if not recovery_check.ok:
		return ERR_FILE_CANT_READ if recovery_check.status == SNAPSHOT_IO_ERROR else ERR_FILE_CORRUPT
	var destination_status := _fs_path_status(destination, destination_io)
	if destination_status.status == SNAPSHOT_IO_ERROR:
		return int(destination_status.error_code)
	return _fs_rename(recovery_path, destination, commit_io)

func _read_snapshot(path: String, callsite: String) -> Dictionary:
	var path_status := _fs_path_status(path, callsite)
	if path_status.status == SNAPSHOT_MISSING:
		return _snapshot_result(SNAPSHOT_MISSING, "文件不存在")
	if path_status.status == SNAPSHOT_IO_ERROR:
		return _snapshot_result(SNAPSHOT_IO_ERROR, "文件状态检查失败（%s）" % path_status.error_code, int(path_status.error_code))
	var open_result := _fs_open_snapshot_read(path, callsite)
	if open_result.file == null:
		return _snapshot_result(SNAPSHOT_IO_ERROR, "文件无法打开（%s）" % open_result.error, int(open_result.error))
	var file: FileAccess = open_result.file
	var read_result := _fs_read_snapshot_bytes(file, callsite)
	file.close()
	if read_result.error != OK:
		return _snapshot_result(SNAPSHOT_IO_ERROR, "文件读取不完整（%s）" % read_result.error, int(read_result.error))
	var parser := JSON.new()
	var parse_error := parser.parse(read_result.text)
	if parse_error != OK:
		return _snapshot_result(SNAPSHOT_CORRUPT, "JSON 第 %d 行损坏" % parser.get_error_line())
	var normalized := _normalize_state(parser.data)
	if not normalized.ok:
		return _snapshot_result(SNAPSHOT_CORRUPT, normalized.error)
	return {"status": SNAPSHOT_OK, "ok": true, "state": normalized.state, "error": "", "error_code": OK}

func _snapshot_result(status: String, message: String, error_code: Error = OK) -> Dictionary:
	return {"status": status, "ok": false, "state": {}, "error": message, "error_code": error_code}

func _write_snapshot_file(path: String, snapshot: Dictionary, callsite: String) -> Error:
	var open_result := _fs_open_snapshot_write(path, callsite)
	if open_result.file == null:
		return int(open_result.error)
	var file: FileAccess = open_result.file
	var write_error := _fs_write_snapshot_bytes(file, JSON.stringify(snapshot), callsite)
	file.close()
	return write_error

func _remove_if_exists(path: String, callsite: String) -> Error:
	var path_status := _fs_path_status(path, callsite)
	if path_status.status == SNAPSHOT_MISSING:
		return OK
	if path_status.status == SNAPSHOT_IO_ERROR:
		return int(path_status.error_code)
	return _fs_remove(path, callsite)

func _commit_error(message: String) -> Dictionary:
	_last_commit_outcome = COMMIT_NOT_COMMITTED
	return {"ok": false, "outcome": COMMIT_NOT_COMMITTED, "error": message}

func _commit_uncertain(message: String) -> Dictionary:
	_last_commit_outcome = COMMIT_UNCERTAIN
	return {"ok": false, "outcome": COMMIT_UNCERTAIN, "error": message}

func _commit_success(warning: String = "") -> Dictionary:
	_last_commit_outcome = COMMIT_COMMITTED
	var result := {"ok": true, "outcome": COMMIT_COMMITTED, "error": ""}
	if not warning.is_empty():
		result["warning"] = warning
	return result

func _not_committed_after_cleanup(path: String, message: String) -> Dictionary:
	var cleanup := _cleanup_transaction_scratch(path)
	if not cleanup.ok:
		return _commit_uncertain("%s 事务未到提交点，但临时文件清理失败：%s" % [message, cleanup.error])
	return _commit_error(message)

func _cleanup_transaction_scratch(path: String, preserve_previous: bool = false) -> Dictionary:
	var cleanup_steps := [
		[path + SAVE_TEMP_SUFFIX, IO_REMOVE_STALE_SAVE_TEMP],
		[path + BACKUP_TEMP_SUFFIX, IO_REMOVE_STALE_BACKUP_TEMP],
		[path + ROLLBACK_SUFFIX, IO_CLEANUP_ROLLBACK],
	]
	if not preserve_previous:
		cleanup_steps.append([path + BACKUP_PREVIOUS_SUFFIX, IO_CLEANUP_BACKUP_PREVIOUS])
	var errors: Array[String] = []
	for step in cleanup_steps:
		var cleanup_error := _remove_if_exists(String(step[0]), String(step[1]))
		if cleanup_error != OK:
			errors.append("%s=%s" % [step[1], cleanup_error])
	return {"ok": errors.is_empty(), "error": ", ".join(errors)}

func _fs_make_dir(path: String, callsite: String) -> Error:
	if not _is_persistence_io_callsite(callsite):
		return ERR_INVALID_PARAMETER
	return DirAccess.make_dir_recursive_absolute(path)

func _fs_remove(path: String, callsite: String) -> Error:
	if not _is_persistence_io_callsite(callsite):
		return ERR_INVALID_PARAMETER
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _fs_copy(source: String, destination: String, callsite: String) -> Error:
	if not _is_persistence_io_callsite(callsite):
		return ERR_INVALID_PARAMETER
	return DirAccess.copy_absolute(ProjectSettings.globalize_path(source), ProjectSettings.globalize_path(destination))

func _fs_rename(source: String, destination: String, callsite: String) -> Error:
	if not _is_persistence_io_callsite(callsite):
		return ERR_INVALID_PARAMETER
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(source), ProjectSettings.globalize_path(destination))

func _fs_path_status(path: String, callsite: String) -> Dictionary:
	if not _is_persistence_io_callsite(callsite):
		return {"status": SNAPSHOT_IO_ERROR, "error_code": ERR_INVALID_PARAMETER}
	if FileAccess.file_exists(path):
		return {"status": PATH_EXISTS, "error_code": OK}
	var probe := FileAccess.open(path, FileAccess.READ)
	if probe != null:
		probe.close()
		return {"status": PATH_EXISTS, "error_code": OK}
	var open_error := FileAccess.get_open_error()
	if open_error == ERR_FILE_NOT_FOUND:
		return {"status": SNAPSHOT_MISSING, "error_code": open_error}
	return {"status": SNAPSHOT_IO_ERROR, "error_code": open_error if open_error != OK else ERR_CANT_OPEN}

func _fs_open_snapshot_read(path: String, callsite: String) -> Dictionary:
	if not _is_persistence_io_callsite(callsite):
		return {"file": null, "error": ERR_INVALID_PARAMETER}
	var file := FileAccess.open(path, FileAccess.READ)
	var open_error := FileAccess.get_open_error() if file == null else OK
	return {"file": file, "error": open_error if open_error != OK else ERR_CANT_OPEN if file == null else OK}

func _fs_read_snapshot_bytes(file: FileAccess, callsite: String) -> Dictionary:
	if not _is_persistence_io_callsite(callsite):
		return {"text": "", "error": ERR_INVALID_PARAMETER}
	var text := file.get_as_text()
	return {"text": text, "error": file.get_error()}

func _fs_open_snapshot_write(path: String, callsite: String) -> Dictionary:
	if not _is_persistence_io_callsite(callsite):
		return {"file": null, "error": ERR_INVALID_PARAMETER}
	var file := FileAccess.open(path, FileAccess.WRITE)
	var open_error := FileAccess.get_open_error() if file == null else OK
	return {"file": file, "error": open_error if open_error != OK else ERR_CANT_OPEN if file == null else OK}

func _fs_write_snapshot_bytes(file: FileAccess, text: String, callsite: String) -> Error:
	if not _is_persistence_io_callsite(callsite):
		return ERR_INVALID_PARAMETER
	file.store_string(text)
	return file.get_error()

func _is_persistence_io_callsite(callsite: String) -> bool:
	if callsite in PERSISTENCE_IO_CALLSITES:
		return true
	push_error("Unnamed persistence I/O callsite: %s" % callsite)
	return false

func is_persistence_blocked() -> bool:
	return _persistence_blocked

func is_reload_required() -> bool:
	return _reload_required

func last_commit_outcome() -> String:
	return _last_commit_outcome

func last_load_error() -> String:
	return _last_load_error

func persistence_recovery_status() -> Dictionary:
	return {
		"blocked": _persistence_blocked,
		"reload_required": _reload_required,
		"message": _last_load_error,
		"commit_outcome": _last_commit_outcome,
	}

func _emit_persistence_recovery_changed() -> void:
	persistence_recovery_changed.emit(persistence_recovery_status())

func _fail_persistence(message: String, requires_reload: bool = false) -> bool:
	_persistence_blocked = true
	_reload_required = _reload_required or requires_reload
	_last_load_error = message
	_accumulator = 0.0
	_autosave_elapsed = 0.0
	notice_posted.emit(message, "warning")
	_emit_persistence_recovery_changed()
	return false

func _reject_if_persistence_blocked() -> bool:
	if not _reload_required:
		return false
	_reject("存档提交结果待确认；操作已冻结，请重新载入。")
	return true

func _normalize_state(candidate: Variant) -> Dictionary:
	var errors: Array[String] = []
	var normalized: Variant = _normalize_schema(candidate, STATE_SCHEMA, "state", errors)
	if errors.is_empty():
		_validate_normalized_state(normalized, errors)
	return {
		"ok": errors.is_empty(),
		"state": normalized if normalized is Dictionary else {},
		"error": "" if errors.is_empty() else errors[0],
	}

func _normalize_schema(value: Variant, schema: Variant, path: String, errors: Array[String]) -> Variant:
	if schema is String:
		match String(schema):
			"int":
				if value is int:
					return value
				if value is float and is_finite(float(value)) and float(value) == floor(float(value)):
					return int(value)
				_schema_error(errors, "%s 必须是整数" % path)
				return 0
			"float":
				if value is int or value is float:
					var number := float(value)
					if is_finite(number):
						return number
				_schema_error(errors, "%s 必须是有限数值" % path)
				return 0.0
			"bool":
				if value is bool:
					return value
				_schema_error(errors, "%s 必须是布尔值" % path)
				return false
			"string":
				if value is String:
					return value
				_schema_error(errors, "%s 必须是字符串" % path)
				return ""
			"json":
				return _normalize_json(value, path, errors)
		_schema_error(errors, "%s 使用未知 schema" % path)
		return null
	if not schema is Dictionary:
		_schema_error(errors, "%s 的 schema 无效" % path)
		return null
	var schema_dict: Dictionary = schema
	if schema_dict.has("$optional"):
		if not value is Dictionary:
			_schema_error(errors, "%s 必须是对象" % path)
			return {}
		if value.is_empty():
			return {}
		return _normalize_schema(value, schema_dict["$optional"], path, errors)
	if schema_dict.has("$array"):
		if not value is Array:
			_schema_error(errors, "%s 必须是数组" % path)
			return []
		if schema_dict.has("$size") and value.size() != int(schema_dict["$size"]):
			_schema_error(errors, "%s 长度必须为 %d" % [path, int(schema_dict["$size"])])
		if schema_dict.has("$max") and value.size() > int(schema_dict["$max"]):
			_schema_error(errors, "%s 长度不能超过 %d" % [path, int(schema_dict["$max"])])
		var result: Array = []
		for index in range(value.size()):
			result.append(_normalize_schema(value[index], schema_dict["$array"], "%s[%d]" % [path, index], errors))
		return result
	if schema_dict.has("$tuple"):
		if not value is Array or value.size() != schema_dict["$tuple"].size():
			_schema_error(errors, "%s 必须是固定长度数组" % path)
			return []
		var tuple: Array = []
		for index in range(value.size()):
			tuple.append(_normalize_schema(value[index], schema_dict["$tuple"][index], "%s[%d]" % [path, index], errors))
		return tuple
	if schema_dict.has("$map"):
		if not value is Dictionary:
			_schema_error(errors, "%s 必须是对象" % path)
			return {}
		var mapped := {}
		for key in value.keys():
			mapped[String(key)] = _normalize_schema(value[key], schema_dict["$map"], "%s.%s" % [path, key], errors)
		return mapped
	if not value is Dictionary:
		_schema_error(errors, "%s 必须是对象" % path)
		return {}
	var source: Dictionary = value
	for key in schema_dict.keys():
		if not source.has(key):
			_schema_error(errors, "%s 缺少字段 %s" % [path, key])
	for key in source.keys():
		if not schema_dict.has(key):
			_schema_error(errors, "%s 包含未知字段 %s" % [path, key])
	var object := {}
	for key in schema_dict.keys():
		if source.has(key):
			object[key] = _normalize_schema(source[key], schema_dict[key], "%s.%s" % [path, key], errors)
	return object

func _normalize_json(value: Variant, path: String, errors: Array[String]) -> Variant:
	if value == null or value is bool or value is String or value is int:
		return value
	if value is float:
		if not is_finite(float(value)):
			_schema_error(errors, "%s 包含非有限数值" % path)
			return 0.0
		return int(value) if float(value) == floor(float(value)) else float(value)
	if value is Array:
		var array: Array = []
		for index in range(value.size()):
			array.append(_normalize_json(value[index], "%s[%d]" % [path, index], errors))
		return array
	if value is Dictionary:
		var object := {}
		for key in value.keys():
			object[String(key)] = _normalize_json(value[key], "%s.%s" % [path, key], errors)
		return object
	_schema_error(errors, "%s 包含不可序列化值" % path)
	return null

func _validate_normalized_state(value: Dictionary, errors: Array[String]) -> void:
	if String(value.save_version) != SAVE_VERSION:
		_schema_error(errors, "state.save_version 与当前版本不兼容")
	if int(value.tick) < 0:
		_schema_error(errors, "state.tick 不能为负数")
	if int(value.speed) not in [1, 2, 4]:
		_schema_error(errors, "state.speed 只能为 1、2 或 4")
	_require_non_negative(value.resources, ["biomass", "energy", "genes"], "state.resources", errors)
	_require_non_negative(value.processing, ["field_organic", "field_carcass", "secured_carcass", "field_sample", "secured_sample", "sample_tissue"], "state.processing", errors)
	_require_non_negative(value.units, ["larva", "worker", "biter", "root_spore", "root_mat", "lost", "formed"], "state.units", errors)
	_require_non_negative(value.targets, ["worker", "biter", "root_spore"], "state.targets", errors)
	_require_non_negative(value.stats, ["biomass_formed", "genes_formed", "enemies_defeated", "nodes_captured", "retreats", "candidate_groups"], "state.stats", errors)
	if float(value.energy.supply) < 0.0 or float(value.energy.base_load) < 0.0 or float(value.energy.task_load) < 0.0 or float(value.energy.capacity) <= 0.0:
		_schema_error(errors, "state.energy 包含非法负载或容量")
	for index in range(value.rooms.size()):
		var room: Dictionary = value.rooms[index]
		if int(room.slot) != index:
			_schema_error(errors, "state.rooms[%d].slot 与数组位置不一致" % index)
		if float(room.progress) < 0.0 or float(room.progress) > 1.0 or float(room.task_progress) < 0.0:
			_schema_error(errors, "state.rooms[%d] 包含非法进度" % index)
		if room.task_kind != "" and not UNIT_DEFS.has(room.task_kind):
			_schema_error(errors, "state.rooms[%d].task_kind 未知" % index)
		if index == 5:
			if room.kind != "core" or room.state != "complete":
				_schema_error(errors, "state.rooms[5] 必须是完整核心")
		elif room.kind == "":
			if room.state != "empty":
				_schema_error(errors, "state.rooms[%d] 空槽状态无效" % index)
		elif room.kind == "core" or not ROOM_DEFS.has(room.kind) or room.state not in ["building", "complete"]:
			_schema_error(errors, "state.rooms[%d] 房间定义无效" % index)
	for index in range(value.nodes.size()):
		var node: Dictionary = value.nodes[index]
		var template: Dictionary = NODE_LAYOUT[index]
		for key in ["id", "name", "role", "pos", "base_enemy", "structure"]:
			if node[key] != template[key]:
				_schema_error(errors, "state.nodes[%d].%s 与区域定义不一致" % [index, key])
		_require_non_negative(node, ["enemy", "enemy_max", "structure_hp", "structure_max", "assaults"], "state.nodes[%d]" % index, errors)
		if int(node.enemy) > int(node.enemy_max) or int(node.structure_hp) > int(node.structure_max):
			_schema_error(errors, "state.nodes[%d] 当前值超过上限" % index)
	if value.links != NODE_LINKS:
		_schema_error(errors, "state.links 与固定区域拓扑不一致")
	if not value.active_battle.is_empty():
		if _node_index(String(value.active_battle.node_id)) < 0:
			_schema_error(errors, "state.active_battle.node_id 未知")
		_require_non_negative(value.active_battle, ["enemy", "enemy_max", "structure_hp", "structure_max", "biter", "spore", "roots", "elapsed", "kills", "losses"], "state.active_battle", errors)
		if int(value.active_battle.enemy) > int(value.active_battle.enemy_max) or int(value.active_battle.structure_hp) > int(value.active_battle.structure_max):
			_schema_error(errors, "state.active_battle 当前值超过上限")
	_validate_candidates(value, errors)
	for milestone in value.milestones.keys():
		if not String(milestone).begins_with("FH-") or int(value.milestones[milestone]) < 0:
			_schema_error(errors, "state.milestones 包含非法记录")
	for event in value.ledger:
		if int(event.tick) < 0 or String(event.type).is_empty() or String(event.message).is_empty():
			_schema_error(errors, "state.ledger 包含非法事件")
	if float(value.settings.ui_scale) not in [1.0, 1.15, 1.3]:
		_schema_error(errors, "state.settings.ui_scale 不受支持")
	if String(value.settings.animation) not in ["完整", "降低", "最低"]:
		_schema_error(errors, "state.settings.animation 不受支持")
	if float(value.settings.master_volume) < 0.0 or float(value.settings.master_volume) > 1.0:
		_schema_error(errors, "state.settings.master_volume 超出范围")

func _validate_candidates(value: Dictionary, errors: Array[String]) -> void:
	var mutation_ids := {}
	for mutation in value.mutations:
		var candidate := _candidate_definition(String(mutation.id))
		if candidate.is_empty() or mutation != candidate or mutation_ids.has(mutation.id):
			_schema_error(errors, "state.mutations 包含未知、重复或被修改的候选")
		mutation_ids[mutation.id] = true
	if value.candidate_group.is_empty():
		return
	if String(value.candidate_group.id).is_empty() or String(value.candidate_group.source).is_empty() or String(value.candidate_group.kind) not in ["first", "ordinary"]:
		_schema_error(errors, "state.candidate_group 元数据无效")
	var option_ids := {}
	for option in value.candidate_group.options:
		var candidate := _candidate_definition(String(option.id))
		if candidate.is_empty() or option != candidate or option_ids.has(option.id):
			_schema_error(errors, "state.candidate_group 包含未知、重复或被修改的候选")
		option_ids[option.id] = true

func _candidate_definition(candidate_id: String) -> Dictionary:
	for candidate in CANDIDATES:
		if candidate.id == candidate_id:
			return candidate
	return {}

func _node_index(node_id: String) -> int:
	for index in range(NODE_LAYOUT.size()):
		if NODE_LAYOUT[index].id == node_id:
			return index
	return -1

func _require_non_negative(value: Dictionary, keys: Array, path: String, errors: Array[String]) -> void:
	for key in keys:
		if float(value[key]) < 0.0:
			_schema_error(errors, "%s.%s 不能为负数" % [path, key])

func _schema_error(errors: Array[String], message: String) -> void:
	if errors.is_empty():
		errors.append(message)

func update_settings(settings: Dictionary) -> void:
	if _reject_if_persistence_blocked():
		return
	for key in settings.keys():
		state.settings[key] = settings[key]
	_emit_change()

func node_by_id(node_id: String) -> Dictionary:
	return _node(node_id).duplicate(true)

func neighbors(node_id: String) -> Array:
	return _neighbors(node_id)

func room_groups() -> Array:
	var groups: Array = []
	var visited := {}
	for room in state.rooms:
		if room.kind in ["", "core"] or visited.has(room.slot):
			continue
		var slots: Array = []
		var queue: Array = [int(room.slot)]
		while not queue.is_empty():
			var slot: int = queue.pop_front()
			if visited.has(slot) or state.rooms[slot].kind != room.kind:
				continue
			visited[slot] = true
			slots.append(slot)
			for adjacent in _adjacent_slots(slot):
				if not visited.has(adjacent):
					queue.append(adjacent)
		groups.append({"kind": room.kind, "slots": slots})
	return groups

func _node(node_id: String) -> Dictionary:
	for node in state.get("nodes", []):
		if node.id == node_id:
			return node
	return {}

func _neighbors(node_id: String) -> Array:
	var result: Array = []
	for link in NODE_LINKS:
		if link[0] == node_id:
			result.append(link[1])
		elif link[1] == node_id:
			result.append(link[0])
	return result

func _has_owned_neighbor(node_id: String) -> bool:
	for neighbor in _neighbors(node_id):
		if _node(neighbor).owned:
			return true
	return false

func _adjacent_slots(slot: int) -> Array:
	var result: Array = []
	var row := slot / 4
	var col := slot % 4
	for direction in [[-1, 0], [1, 0], [0, -1], [0, 1]]:
		var next_row: int = row + direction[0]
		var next_col: int = col + direction[1]
		if next_row >= 0 and next_row < 3 and next_col >= 0 and next_col < 4:
			result.append(next_row * 4 + next_col)
	return result

func _check_merge_milestone(slot: int) -> void:
	var kind: String = state.rooms[slot].kind
	for adjacent in _adjacent_slots(slot):
		if state.rooms[adjacent].kind == kind and kind not in ["", "core"]:
			_mark("FH-004")
			return

func _count_complete_rooms(kind: String, include_all: bool = false) -> int:
	var count := 0
	for room in state.rooms:
		if room.state == "complete" and room.kind != "core" and (include_all or room.kind == kind):
			count += 1
	return count

func _count_building_rooms() -> int:
	var count := 0
	for room in state.rooms:
		if room.state == "building":
			count += 1
	return count

func _has_complete_room(kind: String) -> bool:
	return _count_complete_rooms(kind) > 0

func _available_unit_count(kind: String) -> int:
	var count := int(state.units[kind])
	if not state.active_battle.is_empty():
		match kind:
			"biter": count += int(state.active_battle.biter)
			"root_spore": count += int(state.active_battle.spore) + int(state.active_battle.roots)
	return count

func _has_mutation(candidate_id: String) -> bool:
	for mutation in state.mutations:
		if mutation.id == candidate_id:
			return true
	return false

func _trigger_mutation_effect(context: String) -> void:
	if not state.mutations.is_empty() and not state.milestones.has("FH-011"):
		_mark("FH-011")
		_record("mutation_effect_applied", "已同化突变在%s规则中产生可观察修正。" % ("生产" if context == "production" else "战场"))

func _mark(id: String) -> void:
	if state.milestones.has(id):
		return
	state.milestones[id] = int(state.tick)

func _record(event_type: String, message: String, details: Dictionary = {}) -> void:
	if state.is_empty():
		return
	var event := {"tick": int(state.tick), "type": event_type, "message": message, "details": details}
	state.ledger.push_front(event)
	if state.ledger.size() > 80:
		state.ledger.resize(80)
	notice_posted.emit(message, "info")

func _reject(message: String) -> bool:
	notice_posted.emit(message, "warning")
	return false

func _emit_change() -> void:
	state_changed.emit(snapshot())
