class_name M1RoomEntity
extends Node2D

@onready var sprite: Sprite2D = $Sprite2D

func configure(texture: Texture2D, display_size: Vector2) -> void:
	sprite.texture = texture
	if texture == null:
		sprite.visible = false
		return
	sprite.visible = true
	var source_size := texture.get_size()
	sprite.scale = Vector2(
		display_size.x / maxf(source_size.x, 1.0),
		display_size.y / maxf(source_size.y, 1.0)
	)
