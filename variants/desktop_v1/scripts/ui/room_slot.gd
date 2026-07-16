extends Button

const ThemeFactory = preload("res://scripts/ui/theme_factory.gd")
const ArtAssets = preload("res://scripts/ui/art_assets.gd")

var room_data: Dictionary = {}
var is_selected := false
var room_name := "空槽"

func _ready() -> void:
	custom_minimum_size = Vector2(172, 132)
	focus_mode = Control.FOCUS_ALL
	clip_text = true
	alignment = HORIZONTAL_ALIGNMENT_LEFT
	icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_theme_constant_override("icon_max_width", 48)
	queue_redraw()

func set_room(data: Dictionary, selected: bool) -> void:
	room_data = data
	is_selected = selected
	var kind := String(data.get("kind", ""))
	if kind == "core":
		room_name = "核心巢室"
	elif kind == "":
		room_name = "自由空槽"
	else:
		room_name = String(GameSession.ROOM_DEFS[kind].name)
	icon = ArtAssets.room_icon(kind)
	var status := "选择槽位"
	if kind == "core":
		status = "账本 / 恢复保障"
	elif kind != "":
		status = "构筑 %d%%" % int(float(data.progress) * 100.0) if data.state == "building" else ("已暂停" if data.paused else "运行中")
	text = "%02d  %s\n%s" % [int(data.get("slot", 0)) + 1, room_name, status]
	queue_redraw()

func _draw() -> void:
	if room_data.is_empty():
		return
	var rect := Rect2(Vector2(10, size.y - 18), Vector2(size.x - 20, 5))
	var kind := String(room_data.get("kind", ""))
	var accent := ThemeFactory.BORDER
	if kind == "core":
		accent = ThemeFactory.AMBER
	elif kind != "":
		accent = ArtAssets.room_accent(kind)
	if is_selected:
		draw_rect(Rect2(Vector2(2, 2), size - Vector2(4, 4)), accent, false, 3.0)
	draw_circle(Vector2(18, 18), 5.0, accent)
	if room_data.get("state", "") == "building":
		draw_rect(rect, Color("091215"), true)
		draw_rect(Rect2(rect.position, Vector2(rect.size.x * float(room_data.progress), rect.size.y)), accent, true)
