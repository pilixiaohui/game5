class_name M1WorldSlice
extends Node2D

const DESIGN_ACTION_SIZE := Vector2(1520, 855)
const ROOM_SCENE := preload("res://scenes/art_m1/m1_room_entity.tscn")
const UNIT_SCENE := preload("res://scenes/art_m1/m1_unit_entity.tscn")
const VFX_SCENE := preload("res://scenes/art_m1/m1_vfx_entity.tscn")

const ROOM_BUILDABLE := preload("res://assets/art_m1/room_buildable_m1.png")
const ROOM_RUNNING := preload("res://assets/art_m1/room_running_m1.png")
const ROOM_BLOCKED := preload("res://assets/art_m1/room_blocked_m1.png")
const UNIT_WORKER := preload("res://assets/art_m1/unit_worker_m1.png")
const UNIT_BITER := preload("res://assets/art_m1/unit_biter_m1.png")
const UNIT_SPORE := preload("res://assets/art_m1/unit_spore_m1.png")
const UNIT_ENEMY := preload("res://assets/art_m1/unit_enemy_m1.png")
const VFX_CONTACT := preload("res://assets/art_m1/vfx_contact_m1.png")
const VFX_HIT := preload("res://assets/art_m1/vfx_hit_m1.png")
const VFX_HURT := preload("res://assets/art_m1/vfx_hurt_m1.png")
const VFX_DEATH := preload("res://assets/art_m1/vfx_death_m1.png")
const VFX_RETREAT := preload("res://assets/art_m1/vfx_retreat_m1.png")
const VFX_RESOURCE := preload("res://assets/art_m1/vfx_resource_m1.png")

@onready var camera: Camera2D = $Camera2D
@onready var rooms_root: Node2D = $Rooms
@onready var units_root: Node2D = $Units
@onready var phase_vfx_root: Node2D = $PhaseVFX
@onready var event_vfx_root: Node2D = $EventVFX

var preview_phase := "operations"
var capture_mode := false
var production_mode := false
var view_model: M1WorldViewModel
var event_count := 0
var _rooms: Array[M1RoomEntity] = []
var _units: Dictionary = {}

func _ready() -> void:
	_build_room_entities()
	_build_unit_entities()
	_apply_phase("operations", false)

func set_viewport_size(viewport_size: Vector2i) -> void:
	if not is_instance_valid(camera):
		call_deferred("set_viewport_size", viewport_size)
		return
	var width := maxf(float(viewport_size.x), 1.0)
	var height := maxf(float(viewport_size.y), 1.0)
	# Frame the authored action field rather than the decorative overscan plates.
	var fit := minf(width / DESIGN_ACTION_SIZE.x, height / DESIGN_ACTION_SIZE.y)
	camera.zoom = Vector2.ONE * maxf(fit, 0.001)

func set_capture_phase(phase: String) -> bool:
	if phase not in ["operations", "engagement", "retreat"]:
		return false
	capture_mode = true
	_apply_phase(phase, true)
	return true

func set_production_mode(enabled: bool) -> void:
	production_mode = enabled

func set_view_model(model: M1WorldViewModel) -> void:
	var previous := view_model
	view_model = model
	_sync_rooms()
	_sync_units()
	if capture_mode:
		return
	var next_phase := "engagement" if model.is_battle_active() else "operations"
	if previous != null and previous.is_battle_active() and not model.is_battle_active():
		next_phase = "operations" if model.captured_nodes > previous.captured_nodes else "retreat"
	_apply_phase(next_phase, false)
	_consume_battle_delta(previous, model)

func show_retreat_intent(active: bool) -> void:
	if capture_mode:
		return
	_apply_phase("retreat" if active else ("engagement" if view_model != null and view_model.is_battle_active() else "operations"), false)

func present_authority_event(kind: String) -> void:
	match kind:
		"contact":
			_spawn_transient("AuthorityContact", VFX_CONTACT, Vector2(1322, 587), Vector2(116, 116))
		"hit":
			_spawn_transient("AuthorityHit", VFX_HIT, Vector2(1420, 520), Vector2(112, 112))
		"hurt":
			_spawn_transient("AuthorityHurt", VFX_HURT, Vector2(1172, 612), Vector2(118, 118))
		"death":
			_spawn_transient("AuthorityDeath", VFX_DEATH, Vector2(1590, 538), Vector2(148, 148))
		"retreat":
			_apply_phase("retreat", false)
			_spawn_transient("AuthorityRetreat", VFX_RETREAT, Vector2(1200, 494), Vector2(160, 160))

func hold_result_phase(captured: bool) -> void:
	_apply_phase("engagement" if captured else "retreat", false)

func world_contract_snapshot() -> Dictionary:
	var active_tweens := 0
	for child in event_vfx_root.get_children():
		if child.has_method("is_animating") and bool(child.call("is_animating")):
			active_tweens += 1
	return {
		"root_type": get_class(),
		"camera_type": camera.get_class(),
		"camera_enabled": camera.enabled,
		"environment_sprites": $Environment.get_child_count(),
		"room_entities": rooms_root.get_child_count(),
		"unit_entities": units_root.get_child_count(),
		"phase_vfx": phase_vfx_root.get_child_count(),
		"transient_vfx": event_vfx_root.get_child_count(),
		"active_tweens": active_tweens,
		"event_count": event_count,
		"phase": preview_phase,
		"world_controls": find_children("*", "Control", true, false).size(),
		"static_redraws": 0,
		"action_field_max_y": 756,
		"visual_landmarks": visual_landmark_contract(),
	}

func visual_landmark_contract() -> Dictionary:
	var landmarks := {}
	for name in ["WorkerLead", "BiterVanguard", "SporeSupport", "EnemyBulwark"]:
		var unit := _units.get(name) as M1UnitEntity
		if unit != null and unit.visible:
			landmarks[name] = _project_landmark(unit.visual_landmark_contract())
	for child in phase_vfx_root.get_children():
		if child is M1VfxEntity and not child.is_queued_for_deletion():
			landmarks[child.name] = _project_landmark(child.visual_landmark_contract())
	return landmarks

func clear_transient_feedback() -> void:
	for child in event_vfx_root.get_children():
		if child.has_method("stop_animation"):
			child.call("stop_animation")
		child.queue_free()

func _build_room_entities() -> void:
	var specs := [
		{"name": "BuildableRoom", "position": Vector2(288, 430), "size": Vector2(196, 196)},
		{"name": "RunningRoom", "position": Vector2(496, 590), "size": Vector2(208, 208)},
		{"name": "BlockedRoom", "position": Vector2(658, 370), "size": Vector2(196, 196)},
	]
	for spec in specs:
		var room := ROOM_SCENE.instantiate() as M1RoomEntity
		room.name = spec.name
		room.position = spec.position
		rooms_root.add_child(room)
		room.configure(ROOM_BUILDABLE, spec.size)
		_rooms.append(room)

func _build_unit_entities() -> void:
	_add_unit("WorkerLead", UNIT_WORKER, Vector2(696, 648), Vector2(156, 156), false)
	_add_unit("WorkerTrail", UNIT_WORKER, Vector2(812, 716), Vector2(138, 138), false)
	_add_unit("BiterVanguard", UNIT_BITER, Vector2(1127, 607), Vector2(216, 216), false)
	_add_unit("SporeSupport", UNIT_SPORE, Vector2(1210, 716), Vector2(180, 180), false)
	_add_unit("EnemyBulwark", UNIT_ENEMY, Vector2(1499, 554), Vector2(200, 200), true)
	_add_unit("EnemyReserve", UNIT_ENEMY, Vector2(1646, 679), Vector2(170, 170), true)

func _add_unit(name: String, texture: Texture2D, at: Vector2, display_size: Vector2, face_left: bool) -> void:
	var unit := UNIT_SCENE.instantiate() as M1UnitEntity
	unit.name = name
	unit.position = at
	units_root.add_child(unit)
	unit.configure(texture, display_size, face_left)
	_units[name] = unit

func _sync_rooms() -> void:
	var states := [ROOM_BUILDABLE, ROOM_RUNNING, ROOM_BLOCKED]
	var found := 0
	for room in view_model.rooms:
		if String(room.get("kind", "")) in ["", "core"]:
			continue
		if found >= states.size():
			break
		if bool(room.get("paused", false)):
			states[found] = ROOM_BLOCKED
		elif String(room.get("state", "")) in ["building", "complete"]:
			states[found] = ROOM_RUNNING
		else:
			states[found] = ROOM_BUILDABLE
		found += 1
	var sizes := [Vector2(196, 196), Vector2(208, 208), Vector2(196, 196)]
	for index in range(_rooms.size()):
		_rooms[index].configure(states[index], sizes[index])

func _sync_units() -> void:
	var battle := view_model.active_battle
	(_units.WorkerLead as M1UnitEntity).set_represented_count(int(view_model.units.get("worker", 0)))
	(_units.WorkerTrail as M1UnitEntity).set_represented_count(maxi(int(view_model.units.get("worker", 0)) - 1, 0))
	(_units.BiterVanguard as M1UnitEntity).set_represented_count(int(battle.get("biter", view_model.units.get("biter", 0))))
	(_units.SporeSupport as M1UnitEntity).set_represented_count(int(battle.get("spore", view_model.units.get("root_spore", 0))))
	(_units.EnemyBulwark as M1UnitEntity).set_represented_count(int(battle.get("enemy", 1)))
	(_units.EnemyReserve as M1UnitEntity).set_represented_count(maxi(int(battle.get("enemy", 2)) - 1, 0))

func _apply_phase(phase: String, static_capture: bool) -> void:
	if phase == preview_phase and phase_vfx_root.get_child_count() > 0:
		return
	preview_phase = phase
	(_units.BiterVanguard as M1UnitEntity).set_facing_left(phase == "retreat")
	for child in phase_vfx_root.get_children():
		child.queue_free()
	match phase:
		"operations":
			_add_vfx(phase_vfx_root, "ResourceRoute", VFX_RESOURCE, Vector2(946, 546), Vector2(150, 150), true, static_capture)
		"engagement":
			_add_vfx(phase_vfx_root, "Contact", VFX_CONTACT, Vector2(1322, 587), Vector2(194, 194), true, static_capture)
			_add_vfx(phase_vfx_root, "Hit", VFX_HIT, Vector2(1376, 508), Vector2(212, 212), true, static_capture)
			_add_vfx(phase_vfx_root, "Hurt", VFX_HURT, Vector2(1564, 546), Vector2(216, 216), true, static_capture)
		"retreat":
			_add_vfx(phase_vfx_root, "Death", VFX_DEATH, Vector2(1635, 533), Vector2(232, 232), true, static_capture)
			_add_vfx(phase_vfx_root, "Retreat", VFX_RETREAT, Vector2(1200, 494), Vector2(270, 270), true, static_capture, -1)
	event_count += 1

func _consume_battle_delta(previous: M1WorldViewModel, current: M1WorldViewModel) -> void:
	if previous == null or not previous.is_battle_active() or not current.is_battle_active():
		return
	var old_battle := previous.active_battle
	var battle := current.active_battle
	if int(battle.get("enemy", 0)) < int(old_battle.get("enemy", 0)):
		_spawn_transient("EnemyHit", VFX_HIT, Vector2(1376, 508), Vector2(80, 80))
	elif int(battle.get("losses", 0)) > int(old_battle.get("losses", 0)):
		_spawn_transient("SwarmHurt", VFX_HURT, Vector2(1188, 612), Vector2(92, 92))
	elif int(battle.get("structure_hp", 0)) < int(old_battle.get("structure_hp", 0)):
		_spawn_transient("StructureHit", VFX_CONTACT, Vector2(1490, 572), Vector2(96, 96))

func _spawn_transient(name: String, texture: Texture2D, at: Vector2, display_size: Vector2) -> void:
	clear_transient_feedback()
	_add_vfx(event_vfx_root, name, texture, at, display_size, false, capture_mode)
	event_count += 1

func _add_vfx(parent: Node2D, name: String, texture: Texture2D, at: Vector2, display_size: Vector2, persistent: bool, static_capture: bool, direction_x: int = 0) -> void:
	var vfx := VFX_SCENE.instantiate() as M1VfxEntity
	vfx.name = name
	vfx.position = at
	parent.add_child(vfx)
	vfx.configure(texture, display_size, persistent, static_capture, direction_x)

func _project_landmark(contract: Dictionary) -> Dictionary:
	var design_rect: Rect2 = contract.get("rect", Rect2())
	var canvas_transform := get_viewport().get_canvas_transform()
	var corners := [
		canvas_transform * design_rect.position,
		canvas_transform * Vector2(design_rect.end.x, design_rect.position.y),
		canvas_transform * design_rect.end,
		canvas_transform * Vector2(design_rect.position.x, design_rect.end.y),
	]
	var minimum := Vector2(INF, INF)
	var maximum := Vector2(-INF, -INF)
	for corner in corners:
		minimum = minimum.min(corner)
		maximum = maximum.max(corner)
	return {
		"rect": Rect2(minimum, maximum - minimum),
		"direction_x": int(contract.get("direction_x", 0)),
		"kind": String(contract.get("kind", "")),
	}

func _exit_tree() -> void:
	clear_transient_feedback()
