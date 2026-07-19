extends SceneTree

const CHILD_ARG := "--m1-capture-child"
const TARGETS := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]
const PHASES := ["operations", "engagement", "retreat"]
const ASSET_SPECS := {
	"world_back_m1.png": {"size": Vector2i(1920, 1080), "transparent": false},
	"world_mid_m1.png": {"size": Vector2i(1920, 1080), "transparent": false},
	"world_fore_m1.png": {"size": Vector2i(1920, 1080), "transparent": false},
	"room_buildable_m1.png": {"size": Vector2i(512, 512), "transparent": true},
	"room_running_m1.png": {"size": Vector2i(512, 512), "transparent": true},
	"room_blocked_m1.png": {"size": Vector2i(512, 512), "transparent": true},
	"unit_worker_m1.png": {"size": Vector2i(256, 256), "transparent": true},
	"unit_biter_m1.png": {"size": Vector2i(256, 256), "transparent": true},
	"unit_spore_m1.png": {"size": Vector2i(256, 256), "transparent": true},
	"unit_enemy_m1.png": {"size": Vector2i(256, 256), "transparent": true},
	"vfx_contact_m1.png": {"size": Vector2i(256, 256), "transparent": true},
	"vfx_hit_m1.png": {"size": Vector2i(256, 256), "transparent": true},
	"vfx_hurt_m1.png": {"size": Vector2i(256, 256), "transparent": true},
	"vfx_death_m1.png": {"size": Vector2i(256, 256), "transparent": true},
	"vfx_retreat_m1.png": {"size": Vector2i(256, 256), "transparent": true},
	"vfx_resource_m1.png": {"size": Vector2i(256, 256), "transparent": true},
}

var failures: Array[String] = []
var captured := 0
var scene: Node2D
var phase_hashes := {}

func _initialize() -> void:
	if CHILD_ARG not in OS.get_cmdline_user_args():
		push_error("M1_CAPTURE_REFUSED use scripts/capture_m1_world_slice.sh")
		quit(2)
		return
	call_deferred("_run")

func _run() -> void:
	_validate_source_assets()
	scene = load("res://scenes/art_m1/m1_hive_battle_world_slice.tscn").instantiate()
	root.add_child(scene)
	await _settle()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/art_m1/captures"))
	for target in TARGETS:
		root.size = target
		scene.call("set_viewport_size", target)
		for phase in PHASES:
			if not bool(scene.call("set_capture_phase", phase)):
				failures.append("%dx%d %s: phase refused" % [target.x, target.y, phase])
				continue
			await _settle()
			_capture("%s_%dx%d" % [phase, target.x, target.y], target)
		var target_key := "%dx%d" % [target.x, target.y]
		var target_hashes: Array = phase_hashes.get(target_key, [])
		var unique_hashes := {}
		for phase_hash in target_hashes:
			unique_hashes[phase_hash] = true
		if unique_hashes.size() != PHASES.size():
			failures.append("%s: phase screenshots are not visually distinct hashes=%s" % [target_key, target_hashes])
	if failures.is_empty() and captured == TARGETS.size() * PHASES.size():
		print("M1_CAPTURE_OK count=%d sizes=1280x720,1600x900,1920x1080 phases=operations,engagement,retreat" % captured)
		quit(0)
	else:
		for failure in failures:
			push_error("M1_CAPTURE_FAILED %s" % failure)
		quit(1)

func _validate_source_assets() -> void:
	for filename in ASSET_SPECS.keys():
		var spec: Dictionary = ASSET_SPECS[filename]
		var image := Image.new()
		var error := image.load("res://assets/art_m1/%s" % filename)
		if error != OK or image.is_empty():
			failures.append("%s: load error %s" % [filename, error])
			continue
		var expected: Vector2i = spec.size
		if Vector2i(image.get_width(), image.get_height()) != expected:
			failures.append("%s: expected %s got %dx%d" % [filename, expected, image.get_width(), image.get_height()])
		if bool(spec.transparent):
			for corner in [Vector2i(0, 0), Vector2i(image.get_width() - 1, 0), Vector2i(0, image.get_height() - 1), Vector2i(image.get_width() - 1, image.get_height() - 1)]:
				if image.get_pixelv(corner).a > 0.01:
					failures.append("%s: corner alpha %.3f" % [filename, image.get_pixelv(corner).a])
		else:
			if image.detect_alpha():
				failures.append("%s: environment is not opaque" % filename)

func _capture(name: String, target: Vector2i) -> void:
	var image := root.get_texture().get_image() if root.get_texture() != null else null
	if image == null or image.is_empty():
		failures.append("%s: missing viewport image" % name)
		return
	if Vector2i(image.get_width(), image.get_height()) != target:
		failures.append("%s: expected viewport %s got %dx%d" % [name, target, image.get_width(), image.get_height()])
		return
	var colors := {}
	for y in range(0, image.get_height(), 24):
		for x in range(0, image.get_width(), 24):
			colors[image.get_pixel(x, y).to_html(false)] = true
	if colors.size() < 24:
		failures.append("%s: blank-like screenshot colors=%d" % [name, colors.size()])
		return
	var output := "res://artifacts/art_m1/captures/%s.png" % name
	var error := image.save_png(output)
	if error != OK:
		failures.append("%s: save error %s" % [name, error])
		return
	var target_key := "%dx%d" % [target.x, target.y]
	var target_hashes: Array = phase_hashes.get(target_key, [])
	target_hashes.append(FileAccess.get_sha256(ProjectSettings.globalize_path(output)))
	phase_hashes[target_key] = target_hashes
	captured += 1
	print("M1_SCREENSHOT_OK path=%s colors=%d" % [output, colors.size()])

func _settle() -> void:
	for index in range(5):
		await process_frame
	await RenderingServer.frame_post_draw
