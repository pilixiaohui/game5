class_name M1WorldPresenter
extends Control

const UI = preload("res://scripts/ui/ui_utils.gd")
const ViewModel = preload("res://scripts/ui/m1_world_view_model.gd")
const HiveHud = preload("res://scripts/ui/m1_hive_hud.gd")
const WORLD_SCENE_PATH := "res://scenes/art_m1/m1_hive_battle_world_slice.tscn"
const EVENT_HOLD_SECONDS := 0.55

var session: Node
var world_scene_path := WORLD_SCENE_PATH
var viewport_host: SubViewportContainer
var world_viewport: SubViewport
var world: Node2D
var rail_panel: PanelContainer
var phase_label: Label
var state_labels: Dictionary = {}
var hive_hud: Control
var view_model: M1WorldViewModel
var available := false
var fallback_reason := ""
var presentation_queue: Array[Dictionary] = []
var presentation_history: Array[Dictionary] = []
var presentation_elapsed := 0.0
var presentation_result_active := false
var presentation_result_captured := false

func _init(session_override: Node = null, world_scene_path_override: String = WORLD_SCENE_PATH) -> void:
	session = session_override
	world_scene_path = world_scene_path_override

func _ready() -> void:
	if session == null:
		session = get_node_or_null("/root/GameSession")
	set_clip_contents(true)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	if world_scene_path.is_empty():
		fallback_reason = "M1 世界场景未配置"
		_build_fallback()
		return
	var packed := load(world_scene_path) as PackedScene
	if packed == null:
		fallback_reason = "M1 世界场景不可用"
		_build_fallback()
		return
	var candidate := packed.instantiate()
	if not candidate.has_method("set_view_model"):
		fallback_reason = "M1 世界场景缺少 set_view_model"
		candidate.free()
		_build_fallback()
		return
	world = candidate as Node2D
	if world == null:
		fallback_reason = "M1 世界场景不是 Node2D"
		candidate.free()
		_build_fallback()
		return
	_build_world_viewport()
	world.name = "WorldRoot"
	world_viewport.add_child(world)
	if world.has_method("set_production_mode"):
		world.call("set_production_mode", true)
	_build_production_rail()
	_build_hive_hud()
	available = true
	visibility_changed.connect(_sync_processing)
	if session != null:
		set_snapshot(session.snapshot())
	_sync_viewport_size()
	_sync_processing()

func is_available() -> bool:
	return available

func get_fallback_reason() -> String:
	return fallback_reason

func set_snapshot(snapshot: Dictionary) -> void:
	if not available or world == null or not world.has_method("set_view_model"):
		return
	var previous := view_model
	view_model = ViewModel.from_snapshot(snapshot)
	world.call("set_view_model", view_model)
	_queue_snapshot_events(previous, view_model)
	if presentation_result_active and not view_model.is_battle_active() and world.has_method("hold_result_phase"):
		world.call("hold_result_phase", presentation_result_captured)
	_refresh_hive_hud(snapshot)
	_refresh_production_rail()

func present_battle_result(summary: Dictionary, captured: bool) -> void:
	presentation_result_active = true
	presentation_result_captured = captured
	var final_kind := "death" if captured or String(summary.get("outcome", "")) == "destroyed" else "retreat"
	_queue_presentation_event(final_kind, int(summary.get("settled_tick", view_model.tick if view_model != null else 0)), "ledger:%s" % String(summary.get("rule_event", "battle_result")))
	if is_instance_valid(world) and world.has_method("hold_result_phase"):
		world.call("hold_result_phase", captured)

func clear_battle_result() -> void:
	presentation_result_active = false
	presentation_result_captured = false

func presentation_contract_snapshot() -> Dictionary:
	var kinds: Array[String] = []
	var monotonic := true
	var previous_msec := -1
	for event in presentation_history:
		kinds.append(String(event.get("kind", "")))
		var at_msec := int(event.get("at_msec", -1))
		if at_msec < previous_msec:
			monotonic = false
		previous_msec = at_msec
	for event in presentation_queue:
		kinds.append(String(event.get("kind", "")))
	return {
		"queued": presentation_queue.size(),
		"history": presentation_history.duplicate(true),
		"kinds": kinds,
		"monotonic": monotonic,
		"result_active": presentation_result_active,
		"source": "readonly-authority-snapshot-ledger",
	}

func show_retreat_intent(active: bool) -> void:
	if available and is_instance_valid(world) and world.has_method("show_retreat_intent"):
		world.call("show_retreat_intent", active)
		_refresh_production_rail()

func world_contract_snapshot() -> Dictionary:
	if not available or not is_instance_valid(world) or not world.has_method("world_contract_snapshot"):
		return {}
	var contract: Dictionary = world.call("world_contract_snapshot")
	contract["host_type"] = viewport_host.get_class() if is_instance_valid(viewport_host) else ""
	contract["viewport_type"] = world_viewport.get_class() if is_instance_valid(world_viewport) else ""
	contract["rail_reserved_start"] = 0.78
	contract["hud"] = hive_hud.call("ui_contract_snapshot") if is_instance_valid(hive_hud) else {}
	contract["viewport_rect"] = viewport_host.get_global_rect() if is_instance_valid(viewport_host) else Rect2()
	contract["rail_rect"] = rail_panel.get_global_rect() if is_instance_valid(rail_panel) else Rect2()
	var hud_contract: Dictionary = contract.hud
	var viewport_rect: Rect2 = contract.viewport_rect
	var rail_rect: Rect2 = contract.rail_rect
	var slot_rect: Rect2 = hud_contract.get("slot_dock_rect", Rect2())
	var detail_rect: Rect2 = hud_contract.get("detail_dock_rect", Rect2())
	var horizontal_docks_clear := slot_rect.size == Vector2.ZERO or detail_rect.size == Vector2.ZERO or (slot_rect.end.x <= viewport_rect.position.x + 0.5 and viewport_rect.end.x <= detail_rect.position.x + 0.5)
	contract["layout_non_overlapping"] = horizontal_docks_clear and viewport_rect.end.y <= rail_rect.position.y + 0.5
	var landmarks: Dictionary = contract.get("visual_landmarks", {})
	var host_origin := viewport_host.get_global_rect().position if is_instance_valid(viewport_host) else Vector2.ZERO
	for key in landmarks.keys():
		var landmark: Dictionary = landmarks[key]
		var local_rect: Rect2 = landmark.get("rect", Rect2())
		landmark["rect"] = Rect2(local_rect.position + host_origin, local_rect.size)
		landmarks[key] = landmark
	contract["visual_landmarks"] = landmarks
	return contract

func clear_transient_feedback() -> void:
	if is_instance_valid(world) and world.has_method("clear_transient_feedback"):
		world.call("clear_transient_feedback")

func _build_world_viewport() -> void:
	viewport_host = SubViewportContainer.new()
	viewport_host.name = "M1WorldViewportHost"
	viewport_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	viewport_host.stretch = true
	viewport_host.custom_minimum_size = Vector2.ZERO
	viewport_host.resized.connect(_sync_viewport_size)
	world_viewport = SubViewport.new()
	world_viewport.name = "M1WorldViewport"
	world_viewport.disable_3d = true
	world_viewport.transparent_bg = false
	world_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	world_viewport.size = Vector2i(1, 1)
	viewport_host.add_child(world_viewport)

func _build_fallback() -> void:
	var fallback := PanelContainer.new()
	fallback.name = "M1FallbackNotice"
	fallback.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var label := UI.label("M1 世界呈现不可用：%s；正在使用传统页面。" % fallback_reason, "Warning")
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	fallback.add_child(label)
	add_child(fallback)

func _build_production_rail() -> void:
	rail_panel = PanelContainer.new()
	rail_panel.name = "M1ProductionStateRail"
	rail_panel.z_index = 8
	rail_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rail_panel.anchor_left = 0.0
	rail_panel.anchor_top = 0.78
	rail_panel.anchor_right = 1.0
	rail_panel.anchor_bottom = 1.0
	add_child(rail_panel)
	var center := CenterContainer.new()
	rail_panel.add_child(center)
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 6)
	center.add_child(row)
	phase_label = UI.label("虫巢现场", "Section")
	phase_label.custom_minimum_size.x = 92
	phase_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	phase_label.add_theme_font_size_override("font_size", 17)
	row.add_child(phase_label)
	for state in ["资源", "威胁", "占领", "交战", "撤离"]:
		var label := UI.label(state, "Muted")
		label.name = "M1State_%s" % state
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		label.custom_minimum_size = Vector2(58, 32)
		label.add_theme_font_size_override("font_size", 16)
		row.add_child(label)
		state_labels[state] = label

func _build_hive_hud() -> void:
	hive_hud = HiveHud.new()
	hive_hud.connect("command_requested", _on_hud_command_requested)
	add_child(hive_hud)
	hive_hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hive_hud.anchor_bottom = 0.78
	hive_hud.offset_bottom = 0.0
	hive_hud.call("attach_world_viewport", viewport_host)

func _refresh_hive_hud(snapshot: Dictionary) -> void:
	if not is_instance_valid(hive_hud) or not is_instance_valid(session):
		return
	var unlocked := {}
	for kind in session.ROOM_DEFS.keys():
		unlocked[kind] = session.is_room_unlocked(kind)
	hive_hud.call("set_projection", snapshot, session.ROOM_DEFS, session.UNIT_DEFS, unlocked, session.room_groups())

func _on_hud_command_requested(command: String, payload: Dictionary) -> void:
	if not is_instance_valid(session):
		return
	match command:
		"build_room":
			session.build_room(int(payload.get("slot", -1)), String(payload.get("kind", "")))
		"cancel_room":
			session.cancel_room(int(payload.get("slot", -1)))
		"demolish_room":
			session.demolish_room(int(payload.get("slot", -1)))
		"set_room_paused":
			session.set_room_paused(int(payload.get("slot", -1)), bool(payload.get("value", false)))
		"set_unit_target":
			session.set_unit_target(String(payload.get("kind", "")), int(payload.get("delta", 0)))
		"set_unit_targets":
			var requested: Dictionary = payload.get("targets", {})
			var current: Dictionary = session.snapshot().get("targets", {})
			for kind in requested.keys():
				session.set_unit_target(String(kind), int(requested[kind]) - int(current.get(kind, 0)))
		"culture_candidate":
			session.culture_candidate()

func _refresh_production_rail() -> void:
	if not is_instance_valid(rail_panel) or view_model == null:
		return
	var contract: Dictionary = world_contract_snapshot()
	var phase := String(contract.get("phase", "operations"))
	phase_label.text = {"operations": "虫巢现场", "engagement": "主动战场", "retreat": "撤离判定"}.get(phase, "虫巢现场")
	phase_label.theme_type_variation = "Warning" if phase != "operations" else "Section"
	var emphasis := String({"operations": "资源", "engagement": "交战", "retreat": "撤离"}.get(phase, "资源"))
	for state in state_labels.keys():
		var label: Label = state_labels[state]
		label.theme_type_variation = "NavActiveButton" if String(state) == emphasis else "Muted"

func _sync_viewport_size() -> void:
	if not is_instance_valid(world_viewport):
		return
	var viewport_size := Vector2i(maxi(1, int(viewport_host.size.x)), maxi(1, int(viewport_host.size.y)))
	if not viewport_host.stretch:
		world_viewport.size = viewport_size
	if is_instance_valid(world) and world.has_method("set_viewport_size"):
		world.call("set_viewport_size", viewport_size)

func _sync_processing() -> void:
	var active := is_visible_in_tree()
	if is_instance_valid(world):
		world.process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED
	if is_instance_valid(world_viewport):
		world_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_DISABLED
	set_process(active)

func _process(delta: float) -> void:
	if presentation_queue.is_empty() or not available:
		return
	presentation_elapsed += delta
	if presentation_elapsed < EVENT_HOLD_SECONDS:
		return
	presentation_elapsed = 0.0
	var event: Dictionary = presentation_queue.pop_front()
	event["at_msec"] = Time.get_ticks_msec()
	presentation_history.append(event)
	if presentation_history.size() > 32:
		presentation_history.pop_front()
	if is_instance_valid(world) and world.has_method("present_authority_event"):
		world.call("present_authority_event", String(event.kind))

func _queue_snapshot_events(previous: M1WorldViewModel, current: M1WorldViewModel) -> void:
	if current == null:
		return
	if (previous == null or not previous.is_battle_active()) and current.is_battle_active():
		_queue_presentation_event("contact", current.tick, "ledger:battle_started" if _ledger_has_type(current.ledger, "battle_started") else "snapshot:active_battle")
		return
	if previous == null or not previous.is_battle_active() or not current.is_battle_active():
		return
	var before := previous.active_battle
	var after := current.active_battle
	if int(after.get("enemy", 0)) < int(before.get("enemy", 0)) or int(after.get("structure_hp", 0)) < int(before.get("structure_hp", 0)):
		_queue_presentation_event("hit", current.tick, "snapshot_delta")
	if int(after.get("losses", 0)) > int(before.get("losses", 0)):
		_queue_presentation_event("hurt", current.tick, "snapshot_delta")

func _queue_presentation_event(kind: String, tick: int, source: String) -> void:
	var event := {"kind": kind, "tick": tick, "source": source, "queued_msec": Time.get_ticks_msec()}
	if presentation_queue.size() >= 12:
		presentation_queue.pop_front()
	presentation_queue.append(event)

func _ledger_has_type(ledger: Array, event_type: String) -> bool:
	for event in ledger:
		if String(event.get("type", "")) == event_type:
			return true
	return false

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_sync_viewport_size()

func _exit_tree() -> void:
	clear_transient_feedback()
