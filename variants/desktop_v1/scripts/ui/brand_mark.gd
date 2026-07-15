extends RefCounted

const SOURCE_PATH := "res://assets/brand/organism_mark.svg"

static var _cached_texture: Texture2D

static func texture() -> Texture2D:
	if _cached_texture != null:
		return _cached_texture
	var image := Image.new()
	var source := FileAccess.get_file_as_string(SOURCE_PATH)
	if not source.is_empty() and image.load_svg_from_string(source, 1.0) == OK:
		_cached_texture = ImageTexture.create_from_image(image)
		return _cached_texture
	image = Image.create(64, 64, false, Image.FORMAT_RGBA8)
	image.fill(Color("071014"))
	for y in range(18, 46):
		for x in range(18, 46):
			if Vector2(x - 32, y - 32).length() <= 13.0:
				image.set_pixel(x, y, Color("82d67b"))
	_cached_texture = ImageTexture.create_from_image(image)
	return _cached_texture
