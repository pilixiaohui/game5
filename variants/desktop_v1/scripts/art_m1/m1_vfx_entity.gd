class_name M1VfxEntity
extends Node2D

@onready var sprite: Sprite2D = $Sprite2D

var _animation: Tween
var _persistent := true
static var _alpha_rect_cache := {}

var _source_alpha_rect := Rect2()
var _direction_x := 0

func configure(texture: Texture2D, display_size: Vector2, persistent: bool = true, static_capture: bool = false, direction_x: int = 0) -> void:
	_persistent = persistent
	_direction_x = clampi(direction_x, -1, 1)
	sprite.texture = texture
	if texture == null:
		sprite.visible = false
		return
	_source_alpha_rect = _alpha_rect(texture)
	var source_size := texture.get_size()
	sprite.scale = Vector2(
		display_size.x / maxf(source_size.x, 1.0),
		display_size.y / maxf(source_size.y, 1.0)
	)
	sprite.visible = true
	if not persistent and not static_capture:
		_play_bounded_feedback()

func visual_landmark_contract() -> Dictionary:
	return {
		"rect": _alpha_rect_in_parent(),
		"direction_x": _direction_x,
		"kind": "vfx",
	}

func is_animating() -> bool:
	return _animation != null and _animation.is_valid() and _animation.is_running()

func stop_animation() -> void:
	if _animation != null and _animation.is_valid():
		_animation.kill()
	_animation = null

func _play_bounded_feedback() -> void:
	stop_animation()
	var target_scale := sprite.scale
	sprite.scale = target_scale * 0.72
	sprite.modulate.a = 0.0
	_animation = create_tween()
	_animation.set_trans(Tween.TRANS_QUAD)
	_animation.set_ease(Tween.EASE_OUT)
	_animation.tween_property(sprite, "modulate:a", 1.0, 0.10)
	_animation.parallel().tween_property(sprite, "scale", target_scale * 1.08, 0.16)
	_animation.tween_property(sprite, "scale", target_scale, 0.12)
	_animation.parallel().tween_property(sprite, "modulate:a", 0.0, 0.18)
	_animation.tween_callback(queue_free)

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

func _exit_tree() -> void:
	stop_animation()
