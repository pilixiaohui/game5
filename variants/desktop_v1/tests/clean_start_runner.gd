extends SceneTree

var failures: Array[String] = []
var assertions := 0

func _initialize() -> void:
	root.size = Vector2i(1600, 900)
	call_deferred("_run")

func _run() -> void:
	var session := root.get_node_or_null("GameSession")
	if session == null or not session.has_method("new_game"):
		_fail_fast("GameSession autoload or new_game method is missing")
		return
	session.set_process(false)
	var main_scene := load("res://scenes/main.tscn") as PackedScene
	if main_scene == null:
		_fail_fast("main scene or one of its required scripts failed to load")
		return
	var main := main_scene.instantiate() as Control
	if main == null or not main.has_method("_show_game"):
		if main != null:
			main.queue_free()
		_fail_fast("main scene is not a Control with the required _show_game method")
		return
	root.add_child(main)
	await _settle()
	_assert_brand_marks(main, 1, "title")
	session.new_game(8303)
	main.call("_show_game")
	await _settle()
	_assert_brand_marks(main, 1, "game shell")
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	_assert_true(image != null and image.get_width() == 1600 and image.get_height() == 900, "clean start must render a 1600x900 frame")
	if failures.is_empty():
		print("CLEAN_START_OK brands=2 size=1600x900")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("CLEAN_START_FAILED assertions=%d failures=%d" % [assertions, failures.size()])
		quit(1)

func _assert_brand_marks(node: Node, expected: int, context: String) -> void:
	var marks: Array[Node] = []
	_collect_marks(node, marks)
	_assert_equal(marks.size(), expected, "%s must expose the expected brand mark count" % context)
	for mark in marks:
		var texture_rect := mark as TextureRect
		if texture_rect == null:
			failures.append("%s brand mark must be a TextureRect" % context)
			continue
		_assert_true(texture_rect.texture != null, "%s brand texture must load without imported cache" % context)
		if texture_rect.texture != null:
			var image := texture_rect.texture.get_image()
			_assert_true(image != null and image.get_width() == 256 and image.get_height() == 256, "%s must decode the complete 256x256 brand source" % context)

func _collect_marks(node: Node, result: Array[Node]) -> void:
	if node.name == "BrandMark":
		result.append(node)
	for child in node.get_children():
		_collect_marks(child, result)

func _settle() -> void:
	for index in range(4):
		await process_frame

func _fail_fast(message: String) -> void:
	push_error("CLEAN_START_FAILED %s" % message)
	print("CLEAN_START_FAILED assertions=%d failures=1" % assertions)
	quit(1)

func _assert_true(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures.append(message)

func _assert_equal(actual: Variant, expected: Variant, message: String) -> void:
	assertions += 1
	if actual != expected:
		failures.append("%s (actual=%s expected=%s)" % [message, actual, expected])
