extends SceneTree

const RESOLUTIONS := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]

var session: Node
var failures: Array[String] = []
var assertions := 0
var capture_root := ""
var scratch_data_root := ""

func _initialize() -> void:
	root.size = Vector2i(1600, 900)
	call_deferred("_run")

func _run() -> void:
	session = root.get_node("GameSession")
	session.set_process(false)
	scratch_data_root = _argument("--scratch-data-root=").simplify_path()
	capture_root = _argument("--capture-root=").simplify_path()
	var save_path := ProjectSettings.globalize_path(session.DEFAULT_SAVE_PATH).simplify_path()
	if scratch_data_root.is_empty() or not save_path.begins_with(scratch_data_root + "/"):
		push_error("ASCENSION_RENDER_REFUSED scratch root does not own the save path")
		quit(1)
		return
	if capture_root.is_empty() or not capture_root.begins_with(scratch_data_root.get_base_dir() + "/"):
		push_error("ASCENSION_RENDER_REFUSED capture root must stay inside the owned work root")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(capture_root)

	session.new_game(8460)
	session.state.stats.nodes_captured = 6
	session.state.stats.biomass_formed = 370.0
	session.state.stats.enemies_defeated = 130
	session.state.stats.genes_formed = 32.0
	session.state.units.formed = 40
	session.state.mutations = [session.CANDIDATES[0].duplicate(true)]
	var main := load("res://scenes/main.tscn").instantiate() as Control
	root.add_child(main)
	await _settle_rendered()
	main.call("_show_game")
	await _settle_rendered()
	var shell := _find_shell(main)
	_assert_true(shell != null, "render fixture must expose the production GameShell")
	if shell != null:
		shell.call("_show_page", "ascension")
		await _settle_rendered()
		await _assert_resolutions(main)

	main.queue_free()
	await process_frame
	_cleanup_slots()
	if failures.is_empty():
		print("ASCENSION_RENDER_GATE_OK resolutions=3 captures=3 assertions=%d" % assertions)
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("ASCENSION_RENDER_GATE_FAILED resolutions=3 assertions=%d failures=%d" % [assertions, failures.size()])
		quit(1)

func _assert_resolutions(main: Control) -> void:
	var availability := _find_label_by_text(main, "尚未开放")
	var page_title := _find_label_by_text(main, "飞升只读预览")
	var return_button := _find_button_by_text(main, "返回进化")
	var ascension_page := page_title.get_parent().get_parent() as Control if page_title != null else null
	var scroll := _find_scroll_container(ascension_page)
	var longest_label := _find_longest_label(scroll)
	_assert_true(availability != null and page_title != null, "ascension header must expose title and availability status")
	_assert_true(return_button != null, "ascension header must expose the return command")
	_assert_true(scroll != null and longest_label != null, "ascension body must expose a scroll viewport and rendered copy")
	for resolution in RESOLUTIONS:
		root.size = resolution
		await _settle_rendered()
		var texture := root.get_texture()
		var image: Image = texture.get_image() if texture != null else null
		var viewport_rect := Rect2(Vector2.ZERO, Vector2(resolution))
		_assert_true(image != null and image.get_size() == resolution, "%s must produce a real rendered frame" % resolution)
		if availability != null:
			var header_rect := availability.get_global_rect()
			_assert_true(viewport_rect.encloses(header_rect), "%s availability rect must be fully inside the viewport, got %s" % [resolution, header_rect])
			_assert_true(header_rect.size.x >= 80.0 and header_rect.size.y <= 36.0, "%s availability must remain a horizontal header field, got %s" % [resolution, header_rect.size])
			_assert_equal(availability.get_line_count(), 1, "%s availability must render on one actual line" % resolution)
			_assert_equal(availability.get_visible_line_count(), availability.get_line_count(), "%s availability must expose every rendered line" % resolution)
			_assert_false(availability.clip_text, "%s availability must not clip" % resolution)
			if image != null:
				_assert_true(_count_text_pixels(image, header_rect) >= 12, "%s availability rect must contain rendered text pixels" % resolution)
		if page_title != null:
			_assert_equal(page_title.get_line_count(), 1, "%s page title must remain one rendered line" % resolution)
			_assert_true(page_title.get_global_rect().size.x >= 180.0, "%s page title must retain a readable horizontal rect" % resolution)
		if return_button != null:
			_assert_true(viewport_rect.encloses(return_button.get_global_rect()), "%s return command must be fully inside the viewport" % resolution)
			_assert_true(return_button.is_visible_in_tree() and not return_button.disabled and return_button.focus_mode == Control.FOCUS_ALL, "%s return command must remain visible, enabled and keyboard reachable" % resolution)
		if scroll != null and longest_label != null:
			scroll.scroll_vertical = 1000000
			await _settle_rendered()
			texture = root.get_texture()
			image = texture.get_image() if texture != null else null
			var longest_rect := longest_label.get_global_rect()
			var visible_scroll_rect := scroll.get_global_rect().intersection(viewport_rect)
			_assert_true(visible_scroll_rect.encloses(longest_rect), "%s longest body text must be reachable in the visible scroll viewport, visible=%s text=%s" % [resolution, visible_scroll_rect, longest_rect])
			_assert_true(longest_rect.size.x >= 240.0 and longest_rect.size.y >= 16.0, "%s longest body text must retain a readable rect, got %s" % [resolution, longest_rect.size])
			_assert_true(longest_label.get_line_count() <= 3, "%s longest body text must use at most three actual lines" % resolution)
			_assert_equal(longest_label.get_visible_line_count(), longest_label.get_line_count(), "%s longest body text must expose every rendered line" % resolution)
			_assert_false(longest_label.clip_text, "%s longest body text must not clip" % resolution)
			var text_pixels := _count_text_pixels(image, longest_rect) if image != null else 0
			_assert_true(text_pixels >= 24, "%s longest body rect must contain rendered text pixels" % resolution)
			var capture_path := capture_root.path_join("ascension_%dx%d.png" % [resolution.x, resolution.y])
			_assert_equal(image.save_png(capture_path) if image != null else ERR_CANT_CREATE, OK, "%s rendered frame must be written for verification" % resolution)
			print("ASCENSION_RENDER size=%s header_rect=%s header_lines=%d longest_chars=%d longest_rect=%s longest_lines=%d longest_pixels=%d" % [resolution, availability.get_global_rect() if availability != null else Rect2(), availability.get_line_count() if availability != null else -1, longest_label.text.length(), longest_rect, longest_label.get_line_count(), text_pixels])
			scroll.scroll_vertical = 0

func _find_shell(node: Node) -> Node:
	if node.has_method("_show_page") and node.has_method("_update_battle_strip"):
		return node
	for child in node.get_children():
		var found := _find_shell(child)
		if found != null:
			return found
	return null

func _find_button_by_text(node: Node, text: String) -> Button:
	if node is Button and node.text == text:
		return node as Button
	for child in node.get_children():
		var found := _find_button_by_text(child, text)
		if found != null:
			return found
	return null

func _find_label_by_text(node: Node, text: String) -> Label:
	if node is Label and node.text == text:
		return node as Label
	for child in node.get_children():
		var found := _find_label_by_text(child, text)
		if found != null:
			return found
	return null

func _find_scroll_container(node: Node) -> ScrollContainer:
	if node == null:
		return null
	if node is ScrollContainer:
		return node as ScrollContainer
	for child in node.get_children():
		var found := _find_scroll_container(child)
		if found != null:
			return found
	return null

func _find_longest_label(node: Node) -> Label:
	if node == null:
		return null
	var longest: Label = node as Label if node is Label else null
	for child in node.get_children():
		var candidate := _find_longest_label(child)
		if candidate != null and (longest == null or candidate.text.length() > longest.text.length()):
			longest = candidate
	return longest

func _count_text_pixels(image: Image, rect: Rect2) -> int:
	var start_x := clampi(int(floor(rect.position.x)), 0, image.get_width())
	var start_y := clampi(int(floor(rect.position.y)), 0, image.get_height())
	var end_x := clampi(int(ceil(rect.end.x)), 0, image.get_width())
	var end_y := clampi(int(ceil(rect.end.y)), 0, image.get_height())
	var count := 0
	for y in range(start_y, end_y):
		for x in range(start_x, end_x):
			var color := image.get_pixel(x, y)
			if color.a > 0.9 and color.r + color.g + color.b > 1.0 and max(color.r, color.g, color.b) > 0.45:
				count += 1
	return count

func _settle_rendered() -> void:
	for index in range(4):
		await process_frame
	await RenderingServer.frame_post_draw

func _cleanup_slots() -> void:
	for suffix in ["", session.BACKUP_SUFFIX, session.SAVE_TEMP_SUFFIX, session.BACKUP_TEMP_SUFFIX, session.BACKUP_PREVIOUS_SUFFIX, session.ROLLBACK_SUFFIX, session.RECOVERY_SUFFIX, session.BACKUP_SUFFIX + session.RECOVERY_SUFFIX]:
		var path: String = session.DEFAULT_SAVE_PATH + suffix
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _argument(prefix: String) -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with(prefix):
			return argument.trim_prefix(prefix)
	return ""

func _assert_true(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures.append(message)

func _assert_false(value: bool, message: String) -> void:
	_assert_true(not value, message)

func _assert_equal(actual: Variant, expected: Variant, message: String) -> void:
	assertions += 1
	if actual != expected:
		failures.append("%s (actual=%s expected=%s)" % [message, actual, expected])
