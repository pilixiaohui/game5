extends SceneTree

const OUTPUT_DIR := "res://assets/art_v1"
const TITLE_SIZE := Vector2i(1920, 1080)
const ICON_RENDER_SIZE := Vector2i(1024, 1024)
const ICON_OUTPUT_SIZE := Vector2i(256, 256)

const ASSETS := [
	"title_hive_field_manual_v1",
	"room_biomass_filter_v1",
	"room_thermal_metabolism_v1",
	"room_embryo_hatchery_v1",
	"swarm_worker_v1",
	"swarm_biter_v1",
	"swarm_root_spore_v1",
	"state_resource_v1",
	"state_threat_v1",
	"state_owned_v1",
	"state_engaged_v1",
	"state_retreat_v1",
]

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_render_all")

func _render_all() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	for asset_id in ASSETS:
		await _render_asset(asset_id)
	if failures.is_empty():
		print("ART_V1_RENDER_OK count=%d" % ASSETS.size())
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)

func _render_asset(asset_id: String) -> void:
	var is_title := asset_id.begins_with("title_")
	var viewport := SubViewport.new()
	viewport.size = TITLE_SIZE if is_title else ICON_RENDER_SIZE
	viewport.transparent_bg = not is_title
	viewport.disable_3d = true
	viewport.msaa_2d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	root.add_child(viewport)

	var plate := ArtPlate.new()
	plate.asset_id = asset_id
	plate.canvas_size = Vector2(viewport.size)
	viewport.add_child(plate)
	await process_frame
	await RenderingServer.frame_post_draw

	var texture := viewport.get_texture()
	if texture == null:
		failures.append("%s: missing viewport texture" % asset_id)
		viewport.queue_free()
		return
	var image := texture.get_image()
	if image == null or image.is_empty():
		failures.append("%s: empty rendered image" % asset_id)
		viewport.queue_free()
		return
	if not is_title:
		image.resize(ICON_OUTPUT_SIZE.x, ICON_OUTPUT_SIZE.y, Image.INTERPOLATE_LANCZOS)
	var path := "%s/%s.png" % [OUTPUT_DIR, asset_id]
	var error := image.save_png(path)
	if error != OK:
		failures.append("%s: save failed (%s)" % [asset_id, error])
	else:
		print("ART_V1_ASSET_OK path=%s size=%dx%d alpha=%s" % [
			path,
			image.get_width(),
			image.get_height(),
			"opaque" if is_title else "rgba",
		])
	viewport.queue_free()
	await process_frame

class ArtPlate:
	extends Node2D

	const GRAPHITE := Color("071014")
	const EQUIPMENT := Color("0e1a1e")
	const SURFACE := Color("142328")
	const BORDER := Color("294047")
	const BONE := Color("e8efea")
	const MUTED := Color("93a6a6")
	const GREEN := Color("82d67b")
	const GREEN_DARK := Color("315b43")
	const CYAN := Color("57c4c3")
	const AMBER := Color("e2ba60")
	const RED := Color("dc785f")
	const OUTLINE := Color("061014")

	var asset_id := ""
	var canvas_size := Vector2.ZERO

	func _ready() -> void:
		queue_redraw()

	func _draw() -> void:
		match asset_id:
			"title_hive_field_manual_v1":
				_draw_title()
			"room_biomass_filter_v1":
				_draw_biomass_filter()
			"room_thermal_metabolism_v1":
				_draw_thermal_chamber()
			"room_embryo_hatchery_v1":
				_draw_hatchery()
			"swarm_worker_v1":
				_draw_worker()
			"swarm_biter_v1":
				_draw_biter()
			"swarm_root_spore_v1":
				_draw_root_spore()
			"state_resource_v1":
				_draw_resource()
			"state_threat_v1":
				_draw_threat()
			"state_owned_v1":
				_draw_owned()
			"state_engaged_v1":
				_draw_engaged()
			"state_retreat_v1":
				_draw_retreat()

	func _draw_title() -> void:
		draw_rect(Rect2(Vector2.ZERO, canvas_size), GRAPHITE, true)
		for x in range(0, int(canvas_size.x), 96):
			draw_line(Vector2(x, 0), Vector2(x, canvas_size.y), Color(BORDER, 0.13), 1.0)
		for y in range(0, int(canvas_size.y), 96):
			draw_line(Vector2(0, y), Vector2(canvas_size.x, y), Color(BORDER, 0.13), 1.0)

		# Bio-industrial containment rails frame the colony without becoming a UI panel.
		draw_rect(Rect2(340, 166, 960, 690), Color(EQUIPMENT, 0.72), true)
		draw_rect(Rect2(338, 164, 964, 694), Color(BORDER, 0.65), false, 3.0)
		for y in [220.0, 508.0, 796.0]:
			draw_line(Vector2(292, y), Vector2(1372, y), Color(BONE, 0.36), 10.0, true)
			draw_line(Vector2(292, y + 14), Vector2(1372, y + 14), Color(BORDER, 0.75), 3.0, true)
		for x in [382.0, 1258.0]:
			draw_line(Vector2(x, 132), Vector2(x, 908), Color(BONE, 0.34), 12.0, true)
			for y in range(190, 880, 92):
				draw_rect(Rect2(x - 23, y, 46, 20), SURFACE, true)
				draw_rect(Rect2(x - 23, y, 46, 20), Color(BONE, 0.42), false, 3.0)

		# Branching roots carry the silhouette to the lower edge.
		var root_paths := [
			PackedVector2Array([Vector2(790, 700), Vector2(710, 790), Vector2(620, 900), Vector2(520, 1080)]),
			PackedVector2Array([Vector2(860, 710), Vector2(900, 820), Vector2(1020, 920), Vector2(1120, 1080)]),
			PackedVector2Array([Vector2(690, 690), Vector2(570, 750), Vector2(410, 830), Vector2(250, 990)]),
			PackedVector2Array([Vector2(940, 675), Vector2(1080, 730), Vector2(1230, 820), Vector2(1370, 980)]),
		]
		for path in root_paths:
			draw_polyline(path, OUTLINE, 42.0, true)
			draw_polyline(path, GREEN_DARK, 26.0, true)
			draw_polyline(path, Color(GREEN, 0.42), 5.0, true)

		# Main chitin colony: asymmetrical lobes and visible chamber cuts.
		_ellipse(Vector2(790, 560), Vector2(350, 280), OUTLINE, 80)
		_ellipse(Vector2(790, 560), Vector2(332, 262), Color("244034"), 80)
		_ellipse(Vector2(610, 570), Vector2(185, 180), Color("315b43"), 64)
		_ellipse(Vector2(945, 585), Vector2(155, 205), Color("203b34"), 64)
		_ellipse(Vector2(790, 365), Vector2(150, 185), Color("2b4d3f"), 64)
		for angle in range(0, 360, 30):
			var direction := Vector2.from_angle(deg_to_rad(float(angle)))
			draw_line(Vector2(790, 560) + direction * 165.0, Vector2(790, 560) + direction * 300.0, Color(BONE, 0.22), 8.0, true)

		# Three readable room motifs embedded in the hive.
		_draw_filter_motif(Vector2(610, 575), 0.72)
		_draw_thermal_motif(Vector2(940, 585), 0.78)
		_draw_hatchery_motif(Vector2(790, 350), 0.84)

		for point in [Vector2(515, 410), Vector2(1080, 445), Vector2(520, 735), Vector2(1050, 740)]:
			draw_circle(point, 18.0, OUTLINE)
			draw_circle(point, 11.0, CYAN)
			draw_line(point, Vector2(1258 if point.x > 800 else 382, point.y), Color(CYAN, 0.50), 3.0, true)

		# Preserve the live-menu side as a calm graphite field.
		draw_rect(Rect2(canvas_size.x * 0.74, 0, canvas_size.x * 0.26, canvas_size.y), Color(GRAPHITE, 0.90), true)
		for y in [188.0, 540.0, 892.0]:
			draw_line(Vector2(1480, y), Vector2(1840, y), Color(BORDER, 0.28), 2.0)

	func _draw_biomass_filter() -> void:
		_draw_filter_motif(Vector2(512, 512), 2.35)
		for x in [280.0, 512.0, 744.0]:
			draw_circle(Vector2(x, 512), 20.0, BONE)
			draw_circle(Vector2(x, 512), 10.0, GRAPHITE)

	func _draw_thermal_chamber() -> void:
		_draw_thermal_motif(Vector2(512, 500), 2.45)
		draw_colored_polygon(PackedVector2Array([
			Vector2(462, 790), Vector2(562, 790), Vector2(512, 872)
		]), GRAPHITE)

	func _draw_hatchery() -> void:
		_draw_hatchery_motif(Vector2(512, 484), 2.55)
		draw_rect(Rect2(340, 760, 344, 76), OUTLINE, true)
		draw_rect(Rect2(366, 776, 292, 40), BONE, true)

	func _draw_worker() -> void:
		var body := PackedVector2Array([
			Vector2(230, 570), Vector2(390, 370), Vector2(680, 410),
			Vector2(790, 540), Vector2(650, 650), Vector2(355, 650)
		])
		_draw_layered_polygon(body, GREEN_DARK, GREEN)
		draw_circle(Vector2(734, 520), 90.0, OUTLINE)
		draw_circle(Vector2(734, 520), 68.0, Color("47785b"))
		for offset in [-1.0, 1.0]:
			var y: float = 535.0 + float(offset) * 54.0
			draw_polyline(PackedVector2Array([
				Vector2(430, y), Vector2(300, y + float(offset) * 90.0), Vector2(172, y + float(offset) * 126.0)
			]), OUTLINE, 42.0, true)
			draw_polyline(PackedVector2Array([
				Vector2(430, y), Vector2(300, y + float(offset) * 90.0), Vector2(172, y + float(offset) * 126.0)
			]), BONE, 20.0, true)
		for x in [342.0, 430.0, 518.0, 606.0]:
			draw_circle(Vector2(x, 535), 17.0, GRAPHITE)
			draw_circle(Vector2(x, 535), 8.0, BONE)
		draw_line(Vector2(760, 480), Vector2(848, 426), CYAN, 16.0, true)
		draw_line(Vector2(760, 560), Vector2(852, 612), CYAN, 16.0, true)

	func _draw_biter() -> void:
		var body := PackedVector2Array([
			Vector2(180, 610), Vector2(350, 380), Vector2(710, 410),
			Vector2(835, 520), Vector2(690, 650), Vector2(330, 690)
		])
		_draw_layered_polygon(body, Color("58635a"), BONE)
		for index in range(3):
			var x := 380.0 + index * 125.0
			draw_colored_polygon(PackedVector2Array([
				Vector2(x, 410), Vector2(x + 54, 265 - index * 12), Vector2(x + 102, 425)
			]), OUTLINE)
			draw_colored_polygon(PackedVector2Array([
				Vector2(x + 16, 402), Vector2(x + 54, 302 - index * 10), Vector2(x + 84, 414)
			]), BONE)
		_draw_mandible(PackedVector2Array([Vector2(760, 500), Vector2(872, 390), Vector2(910, 480), Vector2(840, 526)]))
		_draw_mandible(PackedVector2Array([Vector2(760, 565), Vector2(872, 680), Vector2(910, 590), Vector2(840, 542)]))
		draw_line(Vector2(812, 520), Vector2(872, 456), RED, 18.0, true)
		draw_line(Vector2(812, 550), Vector2(872, 614), RED, 18.0, true)
		draw_circle(Vector2(705, 502), 18.0, GREEN)

	func _draw_root_spore() -> void:
		for x in [390.0, 512.0, 634.0]:
			draw_polyline(PackedVector2Array([
				Vector2(512, 590), Vector2(x, 710), Vector2(x + (x - 512) * 0.35, 850)
			]), OUTLINE, 58.0, true)
			draw_polyline(PackedVector2Array([
				Vector2(512, 590), Vector2(x, 710), Vector2(x + (x - 512) * 0.35, 850)
			]), GREEN_DARK, 34.0, true)
		_ellipse(Vector2(512, 430), Vector2(250, 225), OUTLINE, 72)
		_ellipse(Vector2(512, 430), Vector2(224, 200), Color("315b53"), 72)
		_ellipse(Vector2(512, 430), Vector2(178, 154), Color("4a7a69"), 64)
		for x in [430.0, 512.0, 594.0]:
			draw_line(Vector2(x, 330), Vector2(x, 545), Color(CYAN, 0.82), 18.0, true)
		draw_polyline(PackedVector2Array([Vector2(695, 420), Vector2(790, 360), Vector2(842, 382)]), OUTLINE, 36.0, true)
		draw_polyline(PackedVector2Array([Vector2(695, 420), Vector2(790, 360), Vector2(842, 382)]), CYAN, 16.0, true)

	func _draw_resource() -> void:
		var pod := _ellipse_points(Vector2(512, 512), Vector2(280, 350), 72)
		_draw_layered_polygon(pod, GREEN_DARK, GREEN)
		draw_polyline(PackedVector2Array([
			Vector2(512, 735), Vector2(512, 520), Vector2(420, 405), Vector2(352, 350)
		]), OUTLINE, 56.0, true)
		draw_polyline(PackedVector2Array([
			Vector2(512, 735), Vector2(512, 520), Vector2(420, 405), Vector2(352, 350)
		]), BONE, 22.0, true)
		for point in [Vector2(588, 380), Vector2(635, 515), Vector2(405, 610)]:
			draw_circle(point, 46.0, OUTLINE)
			draw_circle(point, 24.0, GRAPHITE)

	func _draw_threat() -> void:
		var crest := PackedVector2Array([
			Vector2(170, 710), Vector2(280, 350), Vector2(410, 470),
			Vector2(512, 150), Vector2(620, 470), Vector2(770, 320),
			Vector2(850, 730), Vector2(610, 655), Vector2(512, 850),
			Vector2(405, 650)
		])
		_draw_layered_polygon(crest, Color("5b3431"), RED)
		draw_polyline(PackedVector2Array([Vector2(310, 730), Vector2(720, 280)]), OUTLINE, 72.0, true)
		draw_polyline(PackedVector2Array([Vector2(310, 730), Vector2(720, 280)]), BONE, 28.0, true)
		for offset in [-80.0, 80.0]:
			draw_line(Vector2(420 + offset, 650), Vector2(650 + offset, 410), Color(BONE, 0.48), 16.0, true)

	func _draw_owned() -> void:
		var hex := PackedVector2Array([
			Vector2(512, 142), Vector2(820, 320), Vector2(820, 690),
			Vector2(512, 868), Vector2(204, 690), Vector2(204, 320)
		])
		draw_polyline(PackedVector2Array(Array(hex) + [hex[0]]), OUTLINE, 96.0, true)
		draw_polyline(PackedVector2Array(Array(hex) + [hex[0]]), GREEN, 50.0, true)
		for direction in [Vector2(0, 1), Vector2(0, -1), Vector2(1, 0), Vector2(-1, 0)]:
			var typed_direction := Vector2(direction)
			var outer: Vector2 = Vector2(512, 512) - typed_direction * 220.0
			var tip: Vector2 = Vector2(512, 512) - typed_direction * 85.0
			var side: Vector2 = Vector2(-typed_direction.y, typed_direction.x) * 60.0
			draw_colored_polygon(PackedVector2Array([outer - side, tip, outer + side]), CYAN)
		for angle in range(0, 360, 45):
			draw_line(Vector2(512, 512), Vector2(512, 512) + Vector2.from_angle(deg_to_rad(float(angle))) * 105.0, BONE, 12.0, true)
		draw_circle(Vector2(512, 512), 54.0, OUTLINE)
		draw_circle(Vector2(512, 512), 30.0, BONE)

	func _draw_engaged() -> void:
		draw_line(Vector2(300, 730), Vector2(724, 286), Color(AMBER, 0.66), 68.0, true)
		draw_line(Vector2(300, 286), Vector2(724, 730), Color(AMBER, 0.66), 68.0, true)
		var left := PackedVector2Array([
			Vector2(128, 300), Vector2(430, 430), Vector2(340, 512),
			Vector2(430, 594), Vector2(128, 724), Vector2(228, 512)
		])
		var right := PackedVector2Array([
			Vector2(896, 300), Vector2(594, 430), Vector2(684, 512),
			Vector2(594, 594), Vector2(896, 724), Vector2(796, 512)
		])
		_draw_layered_polygon(left, Color("5b3431"), RED)
		_draw_layered_polygon(right, Color("5b3431"), RED)
		draw_line(Vector2(458, 512), Vector2(566, 512), BONE, 24.0, true)

	func _draw_retreat() -> void:
		var wedge := PackedVector2Array([
			Vector2(190, 190), Vector2(848, 310), Vector2(690, 512),
			Vector2(848, 714), Vector2(190, 834), Vector2(420, 512)
		])
		_draw_layered_polygon(wedge, Color("5a4a2c"), AMBER)
		draw_polyline(PackedVector2Array([
			Vector2(710, 512), Vector2(520, 512), Vector2(390, 620), Vector2(250, 620)
		]), OUTLINE, 82.0, true)
		draw_polyline(PackedVector2Array([
			Vector2(710, 512), Vector2(520, 512), Vector2(390, 620), Vector2(250, 620)
		]), BONE, 34.0, true)
		for offset in [-110.0, 0.0, 110.0]:
			draw_line(Vector2(540 + offset, 310), Vector2(420 + offset, 430), Color(GRAPHITE, 0.72), 32.0, true)

	func _draw_filter_motif(center: Vector2, scale: float) -> void:
		var radii := Vector2(84, 92) * scale
		for offset in [-82.0, 0.0, 82.0]:
			_ellipse(center + Vector2(offset * scale, 0), radii, OUTLINE, 48)
			_ellipse(center + Vector2(offset * scale, 0), radii * 0.82, Color("47785b"), 48)
		_ellipse(center - Vector2(135, 0) * scale, Vector2(32, 72) * scale, BONE, 40)
		for y in [-35.0, 0.0, 35.0]:
			draw_circle(center + Vector2(-145, y) * scale, 8.0 * scale, GRAPHITE)
		draw_rect(Rect2(center + Vector2(122, -54) * scale, Vector2(68, 108) * scale), BONE, true)
		draw_rect(Rect2(center + Vector2(140, -34) * scale, Vector2(50, 68) * scale), GRAPHITE, true)

	func _draw_thermal_motif(center: Vector2, scale: float) -> void:
		for index in range(6):
			var angle := TAU * float(index) / 6.0
			var direction := Vector2.from_angle(angle)
			var side := Vector2(-direction.y, direction.x)
			var inner := center + direction * 68.0 * scale
			var outer := center + direction * 145.0 * scale
			draw_colored_polygon(PackedVector2Array([
				inner - side * 35.0 * scale,
				outer - side * 55.0 * scale,
				outer + side * 55.0 * scale,
				inner + side * 35.0 * scale,
			]), OUTLINE)
			draw_line(inner, outer, BONE, 30.0 * scale, true)
		draw_circle(center, 92.0 * scale, OUTLINE)
		draw_circle(center, 72.0 * scale, Color("725b2f"))
		draw_circle(center, 45.0 * scale, AMBER)
		draw_arc(center, 118.0 * scale, 0, TAU, 48, Color(AMBER, 0.65), 8.0 * scale, true)

	func _draw_hatchery_motif(center: Vector2, scale: float) -> void:
		var points := PackedVector2Array([
			center + Vector2(-80, -125) * scale,
			center + Vector2(-145, -35) * scale,
			center + Vector2(-132, 115) * scale,
			center + Vector2(-70, 175) * scale,
			center + Vector2(70, 175) * scale,
			center + Vector2(132, 115) * scale,
			center + Vector2(145, -35) * scale,
			center + Vector2(80, -125) * scale,
			center + Vector2(30, -70) * scale,
			center,
			center + Vector2(-30, -70) * scale,
		])
		_draw_layered_polygon(points, Color("284e4d"), CYAN)
		for x in [-58.0, 0.0, 58.0]:
			draw_line(center + Vector2(x, -36) * scale, center + Vector2(x * 0.55, 126) * scale, Color(BONE, 0.78), 12.0 * scale, true)
		draw_rect(Rect2(center + Vector2(-118, 155) * scale, Vector2(236, 45) * scale), BONE, true)
		draw_rect(Rect2(center + Vector2(-84, 164) * scale, Vector2(168, 27) * scale), GRAPHITE, true)

	func _draw_mandible(points: PackedVector2Array) -> void:
		draw_polyline(points, OUTLINE, 62.0, true)
		draw_polyline(points, BONE, 30.0, true)

	func _draw_layered_polygon(points: PackedVector2Array, shadow: Color, fill: Color) -> void:
		var center := Vector2.ZERO
		for point in points:
			center += point
		center /= float(points.size())
		var outer := PackedVector2Array()
		for point in points:
			outer.append(center + (point - center) * 1.07)
		draw_colored_polygon(outer, OUTLINE)
		draw_colored_polygon(points, shadow)
		var inner := PackedVector2Array()
		for point in points:
			inner.append(center + (point - center) * 0.86)
		draw_colored_polygon(inner, fill)

	func _ellipse(center: Vector2, radius: Vector2, color: Color, segments: int) -> void:
		draw_colored_polygon(_ellipse_points(center, radius, segments), color)

	func _ellipse_points(center: Vector2, radius: Vector2, segments: int) -> PackedVector2Array:
		var points := PackedVector2Array()
		for index in range(segments):
			var angle := TAU * float(index) / float(segments)
			points.append(center + Vector2(cos(angle) * radius.x, sin(angle) * radius.y))
		return points
