extends VBoxContainer

signal return_to_title_requested

const ThemeFactory = preload("res://scripts/ui/theme_factory.gd")
const UI = preload("res://scripts/ui/ui_utils.gd")
const BrandMark = preload("res://scripts/ui/brand_mark.gd")
const HivePage = preload("res://scripts/ui/hive_page.gd")
const MapPage = preload("res://scripts/ui/map_page.gd")
const BattlePage = preload("res://scripts/ui/battle_page.gd")
const EvolutionPage = preload("res://scripts/ui/evolution_page.gd")
const SwarmPage = preload("res://scripts/ui/swarm_page.gd")
const AscensionPage = preload("res://scripts/ui/ascension_page.gd")
const SystemPage = preload("res://scripts/ui/system_page.gd")

const NAV_ITEMS := [
	{"id": "hive", "label": "虫巢"},
	{"id": "map", "label": "区域图"},
	{"id": "evolution", "label": "进化"},
	{"id": "swarm", "label": "虫群"},
	{"id": "system", "label": "系统"},
]

var current_page := "hive"
var pages := {}
var nav_buttons := {}
var resource_labels := {}
var tick_label: Label
var speed_buttons := {}
var battle_strip: PanelContainer
var battle_text: Label
var notice_band: PanelContainer
var notice_label: Label
var notice_timer: Timer

func _ready() -> void:
	set_process_unhandled_input(true)
	add_theme_constant_override("separation", 0)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_build_status_bar()
	_build_navigation()
	_build_battle_strip()
	_build_page_host()
	_build_notice()
	GameSession.state_changed.connect(_on_state_changed)
	GameSession.notice_posted.connect(_show_notice)
	_on_state_changed(GameSession.snapshot())

func _build_status_bar() -> void:
	var bar := PanelContainer.new()
	bar.custom_minimum_size.y = 64
	add_child(bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	bar.add_child(row)
	var mark := TextureRect.new()
	mark.name = "BrandMark"
	mark.texture = BrandMark.texture()
	mark.custom_minimum_size = Vector2(38, 38)
	mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(mark)
	var identity := VBoxContainer.new()
	identity.custom_minimum_size.x = 190
	identity.add_child(UI.label("异种起源", "Section"))
	identity.add_child(UI.label("初始虫巢 · 腐殖盆地", "Muted"))
	row.add_child(identity)
	row.add_child(UI.separator(true))
	for key in ["biomass", "energy", "genes"]:
		var metric := VBoxContainer.new()
		metric.custom_minimum_size.x = 105
		metric.add_child(UI.label({"biomass": "生物质", "energy": "储能", "genes": "基因"}[key], "Muted"))
		var value := UI.label("0", "Metric")
		metric.add_child(value)
		resource_labels[key] = value
		row.add_child(metric)
	row.add_child(UI.spacer())
	tick_label = UI.label("T+00000", "Muted")
	tick_label.custom_minimum_size.x = 86
	tick_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	tick_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(tick_label)
	var speed_group := HBoxContainer.new()
	speed_group.add_theme_constant_override("separation", 4)
	row.add_child(speed_group)
	for speed in [1, 2, 4]:
		var button := UI.button("%d×" % speed, _set_speed.bind(speed))
		button.custom_minimum_size.x = 48
		speed_group.add_child(button)
		speed_buttons[speed] = button
	row.add_child(UI.button("保存", GameSession.save_game))

func _build_navigation() -> void:
	var band := ColorRect.new()
	band.color = Color("0a1519")
	band.custom_minimum_size.y = 48
	add_child(band)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	band.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	margin.add_child(row)
	for item in NAV_ITEMS:
		var button := UI.button(item.label, _show_page.bind(String(item.id)), "NavButton")
		button.custom_minimum_size.x = 112
		row.add_child(button)
		nav_buttons[item.id] = button
	row.add_child(UI.spacer())
	var completion := UI.label("首版里程碑 0 / 14", "Muted")
	completion.name = "CompletionLabel"
	completion.custom_minimum_size.x = 165
	completion.autowrap_mode = TextServer.AUTOWRAP_OFF
	completion.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(completion)

func _build_battle_strip() -> void:
	battle_strip = PanelContainer.new()
	battle_strip.custom_minimum_size.y = 44
	add_child(battle_strip)
	var row := HBoxContainer.new()
	battle_strip.add_child(row)
	var indicator := ColorRect.new()
	indicator.name = "Indicator"
	indicator.color = ThemeFactory.MUTED
	indicator.custom_minimum_size = Vector2(6, 28)
	row.add_child(indicator)
	battle_text = UI.label("当前无主动战场", "Muted")
	battle_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(battle_text)
	var return_button := UI.button("返回战场", _show_page.bind("battle"), "PrimaryButton")
	return_button.name = "ReturnBattleButton"
	return_button.disabled = true
	row.add_child(return_button)

func _build_page_host() -> void:
	var margin := MarginContainer.new()
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	add_child(margin)
	var host := VBoxContainer.new()
	host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(host)
	pages = {
		"hive": HivePage.new(),
		"map": MapPage.new(),
		"battle": BattlePage.new(),
		"evolution": EvolutionPage.new(),
		"swarm": SwarmPage.new(),
		"ascension": AscensionPage.new(),
		"system": SystemPage.new(),
	}
	for id in pages.keys():
		var page: Control = pages[id]
		page.visible = id == current_page
		page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		page.size_flags_vertical = Control.SIZE_EXPAND_FILL
		host.add_child(page)
	pages.map.open_battle_requested.connect(_show_page.bind("battle"))
	pages.evolution.open_ascension_requested.connect(_show_page.bind("ascension"))
	pages.ascension.back_requested.connect(_show_page.bind("evolution"))

func _build_notice() -> void:
	notice_band = PanelContainer.new()
	notice_band.visible = false
	notice_band.custom_minimum_size.y = 42
	add_child(notice_band)
	notice_label = UI.label("")
	notice_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	notice_band.add_child(notice_label)
	notice_timer = Timer.new()
	notice_timer.one_shot = true
	notice_timer.wait_time = 3.2
	notice_timer.timeout.connect(_hide_notice)
	add_child(notice_timer)

func _on_state_changed(snapshot: Dictionary) -> void:
	if snapshot.is_empty():
		return
	resource_labels.biomass.text = "%d" % int(snapshot.resources.biomass)
	resource_labels.energy.text = "%d / %d" % [int(snapshot.resources.energy), int(snapshot.energy.capacity)]
	resource_labels.genes.text = "%d" % int(snapshot.resources.genes)
	tick_label.text = "T+%05d" % int(snapshot.tick)
	for speed in speed_buttons.keys():
		speed_buttons[speed].theme_type_variation = "NavActiveButton" if int(snapshot.speed) == int(speed) else "NavButton"
	for page in pages.values():
		page.set_snapshot(snapshot)
	_update_battle_strip(snapshot)
	var completion := GameSession.completion_summary()
	var completion_label := find_child("CompletionLabel", true, false) as Label
	if completion_label:
		completion_label.text = "首版里程碑 %d / 14" % completion.completed

func _update_battle_strip(snapshot: Dictionary) -> void:
	var return_button := battle_strip.find_child("ReturnBattleButton", true, false) as Button
	var indicator := battle_strip.find_child("Indicator", true, false) as ColorRect
	if snapshot.active_battle.is_empty():
		battle_text.text = "当前无主动战场 · 区域节点保持持久状态"
		battle_text.theme_type_variation = "Muted"
		return_button.disabled = true
		indicator.color = ThemeFactory.MUTED
	else:
		var battle: Dictionary = snapshot.active_battle
		var node := GameSession.node_by_id(battle.node_id)
		battle_text.text = "%s  ·  敌军 %d  ·  结构 %d  ·  战损 %d" % [node.name, battle.enemy, battle.structure_hp, battle.losses]
		battle_text.theme_type_variation = "Warning"
		return_button.disabled = false
		indicator.color = ThemeFactory.RED

func _show_page(page_id: String) -> void:
	if not pages.has(page_id):
		return
	current_page = page_id
	for id in pages.keys():
		pages[id].visible = id == page_id
	for id in nav_buttons.keys():
		var selected: bool = String(id) == page_id or (page_id == "ascension" and String(id) == "evolution")
		nav_buttons[id].theme_type_variation = "NavActiveButton" if selected else "NavButton"

func _set_speed(speed: int) -> void:
	GameSession.set_speed(speed)

func _show_notice(message: String, level: String) -> void:
	notice_label.text = message
	notice_label.theme_type_variation = "Warning" if level == "warning" else "Muted"
	notice_band.visible = true
	notice_timer.start()

func _hide_notice() -> void:
	notice_band.visible = false

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("save_game"):
		GameSession.save_game()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("toggle_fullscreen"):
		var mode := DisplayServer.window_get_mode()
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if mode == DisplayServer.WINDOW_MODE_FULLSCREEN else DisplayServer.WINDOW_MODE_FULLSCREEN)
		get_viewport().set_input_as_handled()
