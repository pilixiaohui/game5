extends Control

const ThemeFactory = preload("res://scripts/ui/theme_factory.gd")
const ArtAssets = preload("res://scripts/ui/art_assets.gd")

var battle: Dictionary = {}
var animation_time := 0.0

func _ready() -> void:
	custom_minimum_size = Vector2(820, 300)
	set_process(true)

func set_battle(value: Dictionary) -> void:
	battle = value
	queue_redraw()

func _process(delta: float) -> void:
	animation_time += delta
	if not battle.is_empty():
		queue_redraw()

func set_capture_animation_phase(value: float) -> bool:
	if "--capture-art-v1-child" not in OS.get_cmdline_user_args():
		return false
	animation_time = value
	set_process(false)
	queue_redraw()
	return true

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("071114"), true)
	var floor_y := size.y * 0.72
	for index in range(6):
		var y := floor_y + index * 10
		draw_line(Vector2(0, y), Vector2(size.x, y), Color("183337"), 2.0)
	draw_line(Vector2(size.x * 0.50, size.y * 0.12), Vector2(size.x * 0.50, floor_y + 16), Color(ThemeFactory.AMBER, 0.30), 2.0)
	for index in range(10):
		var x := float(index) / 9.0 * size.x
		var height := 18.0 + float((index * 13) % 36)
		draw_line(Vector2(x, floor_y), Vector2(x + 14, floor_y - height), Color("1a3431"), 4.0)
	if battle.is_empty():
		_draw_empty_state()
		return
	var friendly_total := int(battle.get("biter", 0)) + int(battle.get("spore", 0)) + int(battle.get("roots", 0))
	var enemy_total := int(battle.get("enemy", 0))
	var contact: float = clampf(0.48 + float(enemy_total - friendly_total) * 0.004, 0.32, 0.68) * size.x
	_draw_swarm(int(battle.get("biter", 0)), Vector2(contact - 170, floor_y - 20), ArtAssets.SWARM_BITER, ThemeFactory.GREEN, 1.0)
	_draw_swarm(int(battle.get("spore", 0)), Vector2(contact - 250, floor_y - 70), ArtAssets.SWARM_ROOT_SPORE, ThemeFactory.CYAN, 0.8)
	_draw_roots(int(battle.get("roots", 0)), Vector2(contact - 115, floor_y + 4))
	_draw_swarm(enemy_total, Vector2(contact + 145, floor_y - 20), ArtAssets.STATE_THREAT, ThemeFactory.RED, -1.0)
	if int(battle.get("structure_hp", 0)) > 0:
		var structure_pos := Vector2(size.x - 105, floor_y - 65)
		draw_circle(structure_pos, 48.0, Color("452529"))
		draw_arc(structure_pos, 48.0, 0, TAU, 32, ThemeFactory.RED, 4.0)
		for i in range(6):
			var angle := TAU * float(i) / 6.0
			draw_line(structure_pos, structure_pos + Vector2.from_angle(angle) * 64.0, ThemeFactory.RED, 5.0)
	var pulse := (sin(animation_time * 4.0) + 1.0) * 0.5
	draw_circle(Vector2(contact, floor_y - 24), 8.0 + pulse * 5.0, Color(ThemeFactory.AMBER, 0.65))
	draw_texture_rect(ArtAssets.STATE_ENGAGED, Rect2(Vector2(contact - 18, floor_y - 42), Vector2(36, 36)), false)

func _draw_empty_state() -> void:
	var center := Vector2(size.x * 0.5, size.y * 0.46)
	for ring in range(3):
		draw_arc(center, 45.0 + ring * 24.0, 0, TAU, 64, Color(ThemeFactory.CYAN, 0.30 - ring * 0.06), 2.0)
	draw_circle(center, 12.0, ThemeFactory.CYAN)

func _draw_swarm(count: int, origin: Vector2, texture: Texture2D, color: Color, direction: float) -> void:
	var representatives: int = mini(18, maxi(0, count))
	for index in range(representatives):
		var row: int = index % 4
		var column: int = index / 4
		var wobble: float = sin(animation_time * 3.0 + index * 1.7) * 4.0
		var point: Vector2 = origin + Vector2(direction * column * 24.0, row * 19.0 - wobble)
		draw_texture_rect(texture, Rect2(point - Vector2(10, 10), Vector2(20, 20)), false)
		draw_line(point, point + Vector2(-direction * 10.0, 7.0), Color(color, 0.65), 2.0)

func _draw_roots(count: int, origin: Vector2) -> void:
	for index in range(min(8, count)):
		var point := origin + Vector2(-index * 26.0, 0)
		draw_texture_rect(ArtAssets.SWARM_ROOT_SPORE, Rect2(point - Vector2(13, 13), Vector2(26, 26)), false)
		draw_line(point, point + Vector2(-12, 18), ThemeFactory.GREEN, 3.0)
		draw_line(point, point + Vector2(12, 18), ThemeFactory.GREEN, 3.0)
