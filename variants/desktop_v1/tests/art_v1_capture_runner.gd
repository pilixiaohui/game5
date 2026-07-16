extends SceneTree

const CAPTURE_CHILD_ARG := "--capture-art-v1-child"
const BATTLE_CAPTURE_PHASE := 1.25
const TARGETS := [
	Vector2i(1280, 720),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
]
const PAGES := ["title", "hive", "swarm", "map", "battle"]
const ASSET_SPECS := {
	"title_hive_field_manual_v1.png": {"size": Vector2i(1920, 1080), "transparent": false},
	"room_biomass_filter_v1.png": {"size": Vector2i(256, 256), "transparent": true},
	"room_thermal_metabolism_v1.png": {"size": Vector2i(256, 256), "transparent": true},
	"room_embryo_hatchery_v1.png": {"size": Vector2i(256, 256), "transparent": true},
	"swarm_worker_v1.png": {"size": Vector2i(256, 256), "transparent": true},
	"swarm_biter_v1.png": {"size": Vector2i(256, 256), "transparent": true},
	"swarm_root_spore_v1.png": {"size": Vector2i(256, 256), "transparent": true},
	"state_resource_v1.png": {"size": Vector2i(256, 256), "transparent": true},
	"state_threat_v1.png": {"size": Vector2i(256, 256), "transparent": true},
	"state_owned_v1.png": {"size": Vector2i(256, 256), "transparent": true},
	"state_engaged_v1.png": {"size": Vector2i(256, 256), "transparent": true},
	"state_retreat_v1.png": {"size": Vector2i(256, 256), "transparent": true},
}

var session: Node
var main: Control
var failures: Array[String] = []
var captured := 0

func _initialize() -> void:
	if CAPTURE_CHILD_ARG not in OS.get_cmdline_user_args():
		push_error("ART_V1_CAPTURE_REFUSED use ./scripts/capture_art_v1.sh")
		quit(2)
		return
	call_deferred("_run")

func _run() -> void:
	_validate_source_assets()
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
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/art_v1/captures"))

	for target in TARGETS:
		root.size = target
		main.call("_show_title")
		await _settle()
		await _capture_page("title", target)

		main.call("_show_game")
		await _settle()
		var shell := _find_shell(main)
		if shell == null:
			failures.append("%dx%d: game shell not found" % [target.x, target.y])
			continue
		for page in ["hive", "swarm", "map"]:
			shell.call("_show_page", page)
			await _settle()
			_validate_live_layout(page, target)
			await _capture_page(page, target)
		if session.snapshot().active_battle.is_empty():
			if not session.attack_node("B"):
				failures.append("%dx%d: battle fixture could not start" % [target.x, target.y])
				continue
		shell.call("_show_page", "battle")
		var battle_canvas := _find_capture_canvas(shell)
		if battle_canvas == null or not bool(battle_canvas.call("set_capture_animation_phase", BATTLE_CAPTURE_PHASE)):
			failures.append("%dx%d: battle capture phase could not be fixed" % [target.x, target.y])
			continue
		await _settle()
		_validate_live_layout("battle", target)
		await _capture_page("battle", target)

	if failures.is_empty() and captured == TARGETS.size() * PAGES.size():
		print("ART_V1_CAPTURE_OK count=%d pages=%d sizes=%d" % [captured, PAGES.size(), TARGETS.size()])
		quit(0)
	else:
		for failure in failures:
			push_error("ART_V1_CAPTURE_FAILED %s" % failure)
		print("ART_V1_CAPTURE_FAILED count=%d failures=%d" % [captured, failures.size()])
		quit(1)

func _validate_source_assets() -> void:
	for filename in ASSET_SPECS.keys():
		var spec: Dictionary = ASSET_SPECS[filename]
		var path := "res://assets/art_v1/%s" % filename
		if not FileAccess.file_exists(path):
			failures.append("%s: source missing" % filename)
			continue
		var texture := ResourceLoader.load(path, "Texture2D") as Texture2D
		var image := texture.get_image() if texture != null else null
		var expected: Vector2i = spec.size
		if image == null or image.is_empty():
			failures.append("%s: source empty" % filename)
			continue
		if Vector2i(image.get_width(), image.get_height()) != expected:
			failures.append("%s: expected %s, got %dx%d" % [filename, expected, image.get_width(), image.get_height()])
		if bool(spec.transparent):
			for corner in [
				Vector2i(0, 0),
				Vector2i(image.get_width() - 1, 0),
				Vector2i(0, image.get_height() - 1),
				Vector2i(image.get_width() - 1, image.get_height() - 1),
			]:
				if image.get_pixelv(corner).a > 0.01:
					failures.append("%s: non-transparent corner %s" % [filename, corner])
		else:
			if image.detect_alpha():
				failures.append("%s: title unexpectedly contains transparent pixels" % filename)
		var used := image.get_used_rect()
		if bool(spec.transparent) and (used.size.x < 96 or used.size.y < 96 or used.size.x > 246 or used.size.y > 246):
			failures.append("%s: implausible subject coverage %s" % [filename, used])

func _validate_live_layout(page: String, target: Vector2i) -> void:
	var viewport_rect := Rect2(Vector2.ZERO, Vector2(target))
	for node in main.find_children("*", "Control", true, false):
		var control := node as Control
		if control == null or not control.is_visible_in_tree() or control.size.x <= 0 or control.size.y <= 0:
			continue
		var rect := control.get_global_rect()
		if not viewport_rect.encloses(rect):
			failures.append("%s %dx%d: visible control clipped by viewport: %s rect=%s" % [page, target.x, target.y, control.get_path(), rect])
		if control is Button and (control as Button).text != "" and control.get_minimum_size().x > control.size.x + 2.0:
			failures.append("%s %dx%d: clipped button text: %s" % [page, target.x, target.y, (control as Button).text])
		if control is Label:
			var label := control as Label
			if label.text != "" and label.autowrap_mode == TextServer.AUTOWRAP_OFF and label.get_minimum_size().x > label.size.x + 2.0:
				failures.append("%s %dx%d: clipped single-line label: %s" % [page, target.x, target.y, label.text])

func _capture_page(page: String, target: Vector2i) -> void:
	var texture := root.get_texture()
	if texture == null:
		failures.append("%s %dx%d: missing viewport texture" % [page, target.x, target.y])
		return
	var image := texture.get_image()
	if image == null or image.get_width() != target.x or image.get_height() != target.y:
		failures.append("%s %dx%d: unexpected viewport image" % [page, target.x, target.y])
		return
	var sampled_colors := {}
	for y in range(0, image.get_height(), 24):
		for x in range(0, image.get_width(), 24):
			sampled_colors[image.get_pixel(x, y).to_html(false)] = true
	if sampled_colors.size() < 12:
		failures.append("%s %dx%d: screenshot appears blank (%d sampled colors)" % [page, target.x, target.y, sampled_colors.size()])
		return
	var path := "res://artifacts/art_v1/captures/%s_%dx%d.png" % [page, target.x, target.y]
	var error := image.save_png(path)
	if error != OK:
		failures.append("%s: save failed (%s)" % [path, error])
		return
	captured += 1
	print("ART_V1_SCREENSHOT_OK path=%s colors=%d" % [path, sampled_colors.size()])

func _find_shell(node: Node) -> Node:
	if node.has_method("_show_page") and node.has_method("_update_battle_strip"):
		return node
	for child in node.get_children():
		var found := _find_shell(child)
		if found != null:
			return found
	return null

func _find_capture_canvas(node: Node) -> Node:
	if node.has_method("set_capture_animation_phase"):
		return node
	for child in node.get_children():
		var found := _find_capture_canvas(child)
		if found != null:
			return found
	return null

func _settle() -> void:
	for index in range(4):
		await process_frame
	await RenderingServer.frame_post_draw
