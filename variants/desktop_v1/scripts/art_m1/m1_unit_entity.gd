class_name M1UnitEntity
extends Node2D

@onready var sprite: Sprite2D = $Sprite2D

static var _alpha_rect_cache := {}

var _source_alpha_rect := Rect2()
var _facing_x := 1

func configure(texture: Texture2D, display_size: Vector2, face_left: bool = false) -> void:
	sprite.texture = texture
	if texture == null:
		sprite.visible = false
		return
	sprite.visible = true
	_source_alpha_rect = _alpha_rect(texture)
	var source_size := texture.get_size()
	var x_scale := display_size.x / maxf(source_size.x, 1.0)
	sprite.scale = Vector2(x_scale, display_size.y / maxf(source_size.y, 1.0))
	set_facing_left(face_left)

func set_facing_left(face_left: bool) -> void:
	_facing_x = -1 if face_left else 1
	sprite.scale.x = absf(sprite.scale.x) * float(_facing_x)

func visual_landmark_contract() -> Dictionary:
	return {
		"rect": _alpha_rect_in_parent(),
		"direction_x": _facing_x,
		"kind": "unit",
	}

func set_represented_count(count: int) -> void:
	visible = count > 0

func _alpha_rect(texture: Texture2D) -> Rect2:
	var key := texture.resource_path
	if _alpha_rect_cache.has(key):
		return _alpha_rect_cache[key]
	var image := texture.get_image()
	if image == null or image.is_empty():
		return Rect2(Vector2.ZERO, texture.get_size())
	var minimum := Vector2i(image.get_width(), image.get_height())
	var maximum := Vector2i(-1, -1)
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if image.get_pixel(x, y).a >= 0.08:
				minimum.x = mini(minimum.x, x)
				minimum.y = mini(minimum.y, y)
				maximum.x = maxi(maximum.x, x)
				maximum.y = maxi(maximum.y, y)
	var result := Rect2(Vector2.ZERO, texture.get_size())
	if maximum.x >= minimum.x and maximum.y >= minimum.y:
		result = Rect2(Vector2(minimum), Vector2(maximum - minimum + Vector2i.ONE))
	_alpha_rect_cache[key] = result
	return result

func _alpha_rect_in_parent() -> Rect2:
	if sprite.texture == null:
		return Rect2()
	var source_size := sprite.texture.get_size()
	var source_corners := [
		_source_alpha_rect.position - source_size * 0.5,
		Vector2(_source_alpha_rect.end.x, _source_alpha_rect.position.y) - source_size * 0.5,
		_source_alpha_rect.end - source_size * 0.5,
		Vector2(_source_alpha_rect.position.x, _source_alpha_rect.end.y) - source_size * 0.5,
	]
	var minimum := Vector2(INF, INF)
	var maximum := Vector2(-INF, -INF)
	for corner in source_corners:
		var projected: Vector2 = transform * (sprite.transform * corner)
		minimum = minimum.min(projected)
		maximum = maximum.max(projected)
	return Rect2(minimum, maximum - minimum)
