extends SceneTree

const CAPTURE_CHILD_ARG := "--capture-child"
const SCREENSHOT_SPECS := [
	{"path": "res://screenshots/title_1600x900.png", "size": Vector2i(1600, 900)},
	{"path": "res://screenshots/hive_1600x900.png", "size": Vector2i(1600, 900)},
	{"path": "res://screenshots/map_1600x900.png", "size": Vector2i(1600, 900)},
	{"path": "res://screenshots/battle_1600x900.png", "size": Vector2i(1600, 900)},
	{"path": "res://screenshots/evolution_1280x720.png", "size": Vector2i(1280, 720)},
	{"path": "res://screenshots/system_1280x720.png", "size": Vector2i(1280, 720)},
]

var session: Node
var main: Control
var capture_failures: Array[String] = []

func _initialize() -> void:
	if CAPTURE_CHILD_ARG in OS.get_cmdline_user_args():
		root.size = Vector2i(1600, 900)
		call_deferred("_run_capture_child")
	else:
		call_deferred("_run_headless_controller")

func _run_headless_controller() -> void:
	var screenshot_root := ProjectSettings.globalize_path("res://screenshots")
	DirAccess.make_dir_recursive_absolute(screenshot_root)
	for spec in SCREENSHOT_SPECS:
		var absolute_path := ProjectSettings.globalize_path(String(spec.path))
		if FileAccess.file_exists(absolute_path):
			DirAccess.remove_absolute(absolute_path)
	var output: Array = []
	var project_path := ProjectSettings.globalize_path("res://").trim_suffix("/")
	var arguments := PackedStringArray([
		"-a",
		OS.get_executable_path(),
		"--audio-driver", "Dummy",
		"--path", project_path,
		"-s", "res://tests/screenshot_runner.gd",
		"--", CAPTURE_CHILD_ARG,
	])
	var status := OS.execute("xvfb-run", arguments, output, true)
	for line in output:
		print(String(line).trim_suffix("\n"))
	if status != 0:
		push_error("SCREENSHOTS_FAILED capture child exit=%d" % status)
		quit(status)
		return
	for spec in SCREENSHOT_SPECS:
		_validate_written_screenshot(String(spec.path), spec.size)
	if capture_failures.is_empty():
		print("SCREENSHOTS_OK count=6 desktop_sizes=1600x900,1280x720 controller=headless-xvfb")
		quit(0)
	else:
		_finish_failed()

func _run_capture_child() -> void:
	session = root.get_node("GameSession")
	session.set_process(false)
	session.new_game(2707)
	session.state.resources.biomass = 900.0
	session.build_room(0, "thermal_metabolism")
	session.build_room(1, "biomass_filter")
	session.build_room(2, "biomass_filter")
	session.build_room(4, "embryo_hatchery")
	session.advance_steps(150)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _settle()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://screenshots"))
	await _capture("res://screenshots/title_1600x900.png", Vector2i(1600, 900))
	main.call("_show_game")
	await _settle()
	await _capture("res://screenshots/hive_1600x900.png", Vector2i(1600, 900))
	var shell := _find_shell(main)
	if shell == null:
		capture_failures.append("game shell not found")
		_finish_failed()
		return
	shell.call("_show_page", "map")
	await _settle()
	await _capture("res://screenshots/map_1600x900.png", Vector2i(1600, 900))
	session.attack_node("B")
	shell.call("_show_page", "battle")
	await _settle()
	await _capture("res://screenshots/battle_1600x900.png", Vector2i(1600, 900))
	root.size = Vector2i(1280, 720)
	shell.call("_show_page", "evolution")
	await _settle()
	await _capture("res://screenshots/evolution_1280x720.png", Vector2i(1280, 720))
	shell.call("_show_page", "system")
	await _settle()
	await _capture("res://screenshots/system_1280x720.png", Vector2i(1280, 720))
	if capture_failures.is_empty():
		print("SCREENSHOTS_CHILD_OK count=6")
		quit(0)
	else:
		_finish_failed()

func _find_shell(node: Node) -> Node:
	if node.has_method("_show_page") and node.has_method("_update_battle_strip"):
		return node
	for child in node.get_children():
		var found := _find_shell(child)
		if found != null:
			return found
	return null

func _settle() -> void:
	for index in range(4):
		await process_frame
	await RenderingServer.frame_post_draw

func _capture(path: String, expected_size: Vector2i) -> void:
	var texture := root.get_texture()
	if texture == null:
		capture_failures.append("missing viewport texture for %s" % path)
		return
	var image := texture.get_image()
	if image == null:
		capture_failures.append("missing viewport image for %s" % path)
		return
	if image.get_width() != expected_size.x or image.get_height() != expected_size.y:
		capture_failures.append("unexpected screenshot size for %s: %dx%d" % [path, image.get_width(), image.get_height()])
		return
	var sampled_colors := {}
	for y in range(0, image.get_height(), 24):
		for x in range(0, image.get_width(), 24):
			sampled_colors[image.get_pixel(x, y).to_html(false)] = true
	if sampled_colors.size() < 8:
		capture_failures.append("screenshot appears blank for %s: sampled_colors=%d" % [path, sampled_colors.size()])
		return
	var error := image.save_png(path)
	if error != OK:
		capture_failures.append("failed to save %s: error=%s" % [path, error])
		return
	print("SCREENSHOT_OK path=%s sampled_colors=%d" % [path, sampled_colors.size()])

func _validate_written_screenshot(path: String, expected_size: Vector2i) -> void:
	var image := Image.new()
	var error := image.load(ProjectSettings.globalize_path(path))
	if error != OK:
		capture_failures.append("controller could not load %s: error=%s" % [path, error])
		return
	if Vector2i(image.get_width(), image.get_height()) != expected_size:
		capture_failures.append("controller found wrong dimensions for %s: %dx%d" % [path, image.get_width(), image.get_height()])

func _finish_failed() -> void:
	for failure in capture_failures:
		push_error("SCREENSHOT_FAILED %s" % failure)
	print("SCREENSHOTS_FAILED count=%d" % capture_failures.size())
	quit(1)
