extends SceneTree

const OUTPUT_DIR := "res://assets/art_m1"
const ENV_SIZE := Vector2i(1920, 1080)
const ROOM_RENDER_SIZE := Vector2i(1024, 1024)
const ROOM_OUTPUT_SIZE := Vector2i(512, 512)
const DETAIL_RENDER_SIZE := Vector2i(512, 512)
const DETAIL_OUTPUT_SIZE := Vector2i(256, 256)

const ENVIRONMENT_ASSETS := [
	"world_back_m1",
	"world_mid_m1",
	"world_fore_m1",
]
const ROOM_ASSETS := [
	"room_buildable_m1",
	"room_running_m1",
	"room_blocked_m1",
]
const DETAIL_ASSETS := [
	"unit_worker_m1",
	"unit_biter_m1",
	"unit_spore_m1",
	"unit_enemy_m1",
	"vfx_contact_m1",
	"vfx_hit_m1",
	"vfx_hurt_m1",
	"vfx_death_m1",
	"vfx_retreat_m1",
	"vfx_resource_m1",
]

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_render_all")

func _render_all() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	for asset_id in ENVIRONMENT_ASSETS + ROOM_ASSETS + DETAIL_ASSETS:
		await _render_asset(asset_id)
	if failures.is_empty():
		print("M1_ART_RENDER_OK count=%d" % (ENVIRONMENT_ASSETS.size() + ROOM_ASSETS.size() + DETAIL_ASSETS.size()))
		quit(0)
	else:
		for failure in failures:
			push_error("M1_ART_RENDER_FAILED %s" % failure)
		quit(1)

func _render_asset(asset_id: String) -> void:
	var is_environment := asset_id in ENVIRONMENT_ASSETS
	var is_room := asset_id in ROOM_ASSETS
	var render_size := ENV_SIZE if is_environment else (ROOM_RENDER_SIZE if is_room else DETAIL_RENDER_SIZE)
	var output_size := ENV_SIZE if is_environment else (ROOM_OUTPUT_SIZE if is_room else DETAIL_OUTPUT_SIZE)
	var viewport := SubViewport.new()
	viewport.size = render_size
	viewport.transparent_bg = not is_environment
	viewport.disable_3d = true
	viewport.msaa_2d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	root.add_child(viewport)

	var plate := M1Plate.new()
	plate.asset_id = asset_id
	plate.canvas_size = Vector2(render_size)
	viewport.add_child(plate)
	await process_frame
	await RenderingServer.frame_post_draw

	var image := viewport.get_texture().get_image() if viewport.get_texture() != null else null
	if image == null or image.is_empty():
		failures.append("%s: rendered image is empty" % asset_id)
		viewport.queue_free()
		return
	if Vector2i(image.get_width(), image.get_height()) != output_size:
		image.resize(output_size.x, output_size.y, Image.INTERPOLATE_LANCZOS)
	var output_path := "%s/%s.png" % [OUTPUT_DIR, asset_id]
	var error := image.save_png(output_path)
	if error != OK:
		failures.append("%s: PNG save failed (%s)" % [asset_id, error])
	else:
		print("M1_ART_ASSET_OK path=%s size=%dx%d alpha=%s" % [
			output_path,
			image.get_width(),
			image.get_height(),
			"opaque" if is_environment else "rgba",
		])
	viewport.queue_free()
	await process_frame

class M1Plate:
	extends Node2D

	const KEY := Color("071014")
	const EQUIPMENT := Color("0e1a1e")
	const SURFACE := Color("142328")
	const BORDER := Color("294047")
	const OUTLINE := Color("03090b")
	const BONE := Color("e8efea")
	const MUTED := Color("93a6a6")
	const GREEN := Color("82d67b")
	const GREEN_DARK := Color("315b43")
	const CYAN := Color("57c4c3")
	const AMBER := Color("e2ba60")
	const RED := Color("dc785f")

	var asset_id := ""
	var canvas_size := Vector2.ZERO

	func _ready() -> void:
		queue_redraw()

	func _draw() -> void:
		match asset_id:
			"world_back_m1":
				_draw_world_back()
			"world_mid_m1":
				_draw_world_mid()
			"world_fore_m1":
				_draw_world_fore()
			"room_buildable_m1":
				_draw_room_buildable()
			"room_running_m1":
				_draw_room_running()
			"room_blocked_m1":
				_draw_room_blocked()
			"unit_worker_m1":
				_draw_worker()
			"unit_biter_m1":
				_draw_biter()
			"unit_spore_m1":
				_draw_spore()
			"unit_enemy_m1":
				_draw_enemy()
			"vfx_contact_m1":
				_draw_contact()
			"vfx_hit_m1":
				_draw_hit()
			"vfx_hurt_m1":
				_draw_hurt()
			"vfx_death_m1":
				_draw_death()
			"vfx_retreat_m1":
				_draw_retreat()
			"vfx_resource_m1":
				_draw_resource()

	func _draw_world_back() -> void:
		draw_rect(Rect2(Vector2.ZERO, canvas_size), KEY, true)
		# Engraved containment wall and distant cavern establish a single camera.
		for x in range(0, 1921, 120):
			var perspective_x := 960.0 + (float(x) - 960.0) * 0.92
			draw_line(Vector2(perspective_x, 130), Vector2(float(x), 890), Color(BORDER, 0.25), 2.0)
		for y in range(160, 900, 90):
			draw_line(Vector2(0, y), Vector2(1920, y + float(y - 520) * 0.03), Color(BORDER, 0.22), 2.0)
		draw_colored_polygon(PackedVector2Array([
			Vector2(0, 0), Vector2(1920, 0), Vector2(1920, 180), Vector2(1720, 150),
			Vector2(1490, 205), Vector2(1260, 142), Vector2(1030, 205), Vector2(820, 140),
			Vector2(590, 205), Vector2(360, 142), Vector2(0, 210),
		]), Color("0b171a"))
		draw_colored_polygon(PackedVector2Array([
			Vector2(0, 830), Vector2(280, 790), Vector2(520, 822), Vector2(760, 770),
			Vector2(980, 810), Vector2(1210, 760), Vector2(1470, 804), Vector2(1710, 775),
			Vector2(1920, 820), Vector2(1920, 1080), Vector2(0, 1080),
		]), Color("102024"))
		# Left biomass bounce and right threat light are broad material cues, not orbs.
		draw_colored_polygon(PackedVector2Array([
			Vector2(0, 240), Vector2(620, 200), Vector2(780, 780), Vector2(0, 820),
		]), Color("10251e"))
		draw_colored_polygon(PackedVector2Array([
			Vector2(1260, 250), Vector2(1920, 220), Vector2(1920, 830), Vector2(1120, 770),
		]), Color("211719"))
		for x in [130.0, 520.0, 905.0, 1285.0, 1670.0]:
			draw_rect(Rect2(x, 170, 34, 640), Color("1d2d31"), true)
			draw_rect(Rect2(x + 7, 190, 20, 600), Color("0a1417"), true)
			for y in range(220, 780, 92):
				draw_rect(Rect2(x - 12, y, 58, 16), Color(BONE, 0.20), true)
		for path in [
			PackedVector2Array([Vector2(0, 630), Vector2(280, 560), Vector2(520, 610), Vector2(800, 520)]),
			PackedVector2Array([Vector2(1920, 430), Vector2(1660, 470), Vector2(1450, 420), Vector2(1180, 510)]),
			PackedVector2Array([Vector2(80, 300), Vector2(360, 350), Vector2(640, 300), Vector2(940, 390)]),
		]:
			draw_polyline(path, OUTLINE, 28.0, true)
			draw_polyline(path, Color("254034"), 16.0, true)
			draw_polyline(path, Color(GREEN, 0.22), 3.0, true)
		# Receding floor planes preserve battle depth.
		for index in range(9):
			var y := 790.0 + pow(float(index) / 8.0, 1.6) * 230.0
			draw_line(Vector2(0, y), Vector2(1920, y), Color(BONE, 0.12), 2.0)
		for x in range(0, 1921, 160):
			draw_line(Vector2(960, 760), Vector2(x, 1080), Color(BORDER, 0.30), 2.0)

	func _draw_world_mid() -> void:
		draw_rect(Rect2(Vector2.ZERO, canvas_size), KEY, true)
		# Asymmetric hive shell on the left; room sprites occupy the three open sockets.
		_draw_rib_arc(Vector2(455, 530), Vector2(390, 355), -2.9, 1.1, 74.0, Color("6a725f"))
		_draw_rib_arc(Vector2(455, 530), Vector2(345, 315), -2.8, 1.05, 34.0, Color(BONE, 0.68))
		for center in [Vector2(280, 420), Vector2(485, 585), Vector2(665, 365)]:
			draw_circle(center, 126.0, OUTLINE)
			draw_circle(center, 112.0, Color("22392f"))
			for angle in range(0, 360, 45):
				var direction := Vector2.from_angle(deg_to_rad(float(angle)))
				draw_line(center + direction * 92.0, center + direction * 124.0, Color(BONE, 0.52), 11.0, true)
		# Central throat is the spatial transition, never a panel divider.
		for offset_value in [-95.0, -45.0, 45.0, 95.0]:
			var x: float = 930.0 + float(offset_value)
			draw_polyline(PackedVector2Array([
				Vector2(x - 120, 250), Vector2(x, 390), Vector2(x + 40, 650), Vector2(x + 115, 815),
			]), OUTLINE, 36.0, true)
			draw_polyline(PackedVector2Array([
				Vector2(x - 120, 250), Vector2(x, 390), Vector2(x + 40, 650), Vector2(x + 115, 815),
			]), Color("596257"), 17.0, true)
		draw_colored_polygon(PackedVector2Array([
			Vector2(1000, 380), Vector2(1090, 340), Vector2(1220, 440), Vector2(1180, 710),
			Vector2(1050, 770), Vector2(980, 660),
		]), Color("152a27"))
		# Battlefield emplacements use directional silhouettes and broken profiles.
		for base in [Vector2(1270, 690), Vector2(1510, 620), Vector2(1740, 720)]:
			var points := PackedVector2Array([
				base + Vector2(-110, 80), base + Vector2(-76, -40), base + Vector2(-20, -82),
				base + Vector2(45, -38), base + Vector2(94, 76),
			])
			draw_colored_polygon(points, OUTLINE)
			draw_polyline(points, Color("68544c"), 22.0, true)
			for slash in range(3):
				draw_line(base + Vector2(-56 + slash * 40, 42), base + Vector2(-12 + slash * 40, -18), Color(RED, 0.60), 7.0, true)
		draw_line(Vector2(1140, 815), Vector2(1870, 800), Color(BONE, 0.32), 12.0, true)
		draw_line(Vector2(1140, 833), Vector2(1870, 818), Color(RED, 0.42), 4.0, true)

	func _draw_world_fore() -> void:
		draw_rect(Rect2(Vector2.ZERO, canvas_size), KEY, true)
		# Foreground roots create a lens-like world frame without obscuring the play band.
		for path in [
			PackedVector2Array([Vector2(-40, 980), Vector2(240, 900), Vector2(460, 940), Vector2(710, 870), Vector2(950, 930)]),
			PackedVector2Array([Vector2(1920, 950), Vector2(1680, 885), Vector2(1470, 930), Vector2(1260, 875), Vector2(1010, 930)]),
			PackedVector2Array([Vector2(50, 1080), Vector2(300, 1000), Vector2(610, 1030), Vector2(900, 970)]),
		]:
			draw_polyline(path, OUTLINE, 62.0, true)
			draw_polyline(path, Color("3a513f"), 38.0, true)
			draw_polyline(path, Color(GREEN, 0.40), 6.0, true)
		for point in [Vector2(110, 900), Vector2(560, 920), Vector2(1360, 915), Vector2(1810, 890)]:
			draw_circle(point, 22.0, OUTLINE)
			draw_circle(point, 12.0, AMBER if point.x > 1000 else CYAN)
		for x in [35.0, 1885.0]:
			draw_line(Vector2(x, 150), Vector2(x, 900), OUTLINE, 52.0, true)
			draw_line(Vector2(x, 170), Vector2(x, 880), Color("596257"), 24.0, true)
		for x in range(210, 1830, 220):
			draw_colored_polygon(PackedVector2Array([
				Vector2(x, 110), Vector2(x + 54, 155), Vector2(x + 15, 198), Vector2(x - 38, 162),
			]), OUTLINE)
			draw_line(Vector2(x, 125), Vector2(x + 9, 178), Color(BONE, 0.36), 9.0, true)

	func _draw_room_buildable() -> void:
		var center := Vector2(512, 512)
		_draw_segmented_ring(center, 330.0, 250.0, CYAN, 0)
		# The open top notch and inward chevrons encode available construction.
		draw_colored_polygon(PackedVector2Array([
			Vector2(412, 165), Vector2(512, 245), Vector2(612, 165), Vector2(590, 90), Vector2(434, 90),
		]), Color(0, 0, 0, 0))
		for angle in [0.0, 90.0, 180.0, 270.0]:
			var direction := Vector2.from_angle(deg_to_rad(angle))
			var side := Vector2(-direction.y, direction.x)
			var outer := center + direction * 205.0
			var tip := center + direction * 92.0
			draw_colored_polygon(PackedVector2Array([outer - side * 44.0, tip, outer + side * 44.0]), Color(BONE, 0.82))
		draw_arc(center, 102.0, 0, TAU, 64, Color(CYAN, 0.75), 20.0, true)

	func _draw_room_running() -> void:
		var center := Vector2(512, 512)
		_draw_segmented_ring(center, 338.0, 260.0, GREEN, 1)
		for angle in range(0, 360, 60):
			var direction := Vector2.from_angle(deg_to_rad(float(angle)))
			var side := Vector2(-direction.y, direction.x)
			draw_colored_polygon(PackedVector2Array([
				center + direction * 80.0 - side * 34.0,
				center + direction * 226.0 - side * 68.0,
				center + direction * 226.0 + side * 68.0,
				center + direction * 80.0 + side * 34.0,
			]), Color("375942"))
			draw_line(center + direction * 96.0, center + direction * 214.0, Color(BONE, 0.58), 17.0, true)
		draw_circle(center, 106.0, OUTLINE)
		draw_circle(center, 84.0, Color("70592c"))
		draw_circle(center, 52.0, AMBER)
		draw_line(center + Vector2(-55, 60), center + Vector2(55, -60), BONE, 15.0, true)

	func _draw_room_blocked() -> void:
		var center := Vector2(512, 512)
		_draw_segmented_ring(center, 330.0, 252.0, RED, 2)
		for angle in [-90.0, 30.0, 150.0]:
			var direction := Vector2.from_angle(deg_to_rad(angle))
			var side := Vector2(-direction.y, direction.x)
			draw_colored_polygon(PackedVector2Array([
				center + direction * 105.0 - side * 52.0,
				center + direction * 310.0,
				center + direction * 105.0 + side * 52.0,
			]), Color("743c35"))
		draw_line(center + Vector2(-190, 190), center + Vector2(190, -190), OUTLINE, 82.0, true)
		draw_line(center + Vector2(-190, 190), center + Vector2(190, -190), BONE, 34.0, true)
		for offset in [-90.0, 0.0, 90.0]:
			draw_line(center + Vector2(offset - 70, 175), center + Vector2(offset + 30, 75), RED, 18.0, true)

	func _draw_worker() -> void:
		var body := PackedVector2Array([
			Vector2(70, 300), Vector2(180, 165), Vector2(342, 190), Vector2(430, 270),
			Vector2(345, 345), Vector2(172, 350),
		])
		_draw_layered_polygon(body, GREEN_DARK, Color("6da66b"))
		for sign in [-1.0, 1.0]:
			draw_polyline(PackedVector2Array([
				Vector2(230, 275 + sign * 26), Vector2(140, 290 + sign * 74), Vector2(62, 306 + sign * 92),
			]), OUTLINE, 25.0, true)
			draw_polyline(PackedVector2Array([
				Vector2(230, 275 + sign * 26), Vector2(140, 290 + sign * 74), Vector2(62, 306 + sign * 92),
			]), BONE, 10.0, true)
		for x in [182.0, 232.0, 282.0, 332.0]:
			draw_circle(Vector2(x, 272), 11.0, OUTLINE)
			draw_circle(Vector2(x, 272), 5.0, BONE)
		draw_line(Vector2(400, 240), Vector2(468, 205), CYAN, 10.0, true)

	func _draw_biter() -> void:
		var body := PackedVector2Array([
			Vector2(54, 330), Vector2(150, 185), Vector2(350, 198), Vector2(440, 268),
			Vector2(346, 354), Vector2(144, 366),
		])
		_draw_layered_polygon(body, Color("5a6258"), BONE)
		for index in range(3):
			var x := 175.0 + index * 72.0
			draw_colored_polygon(PackedVector2Array([
				Vector2(x, 202), Vector2(x + 34, 112 - index * 5), Vector2(x + 66, 212),
			]), OUTLINE)
			draw_line(Vector2(x + 22, 198), Vector2(x + 34, 140 - index * 4), Color(BONE, 0.75), 12.0, true)
		for sign in [-1.0, 1.0]:
			draw_polyline(PackedVector2Array([
				Vector2(398, 278), Vector2(474, 230 + sign * 55), Vector2(488, 268 + sign * 18),
			]), OUTLINE, 30.0, true)
			draw_polyline(PackedVector2Array([
				Vector2(398, 278), Vector2(474, 230 + sign * 55), Vector2(488, 268 + sign * 18),
			]), RED, 12.0, true)
		draw_circle(Vector2(370, 246), 10.0, GREEN)

	func _draw_spore() -> void:
		for x in [180.0, 256.0, 332.0]:
			draw_polyline(PackedVector2Array([
				Vector2(256, 292), Vector2(x, 370), Vector2(x + (x - 256) * 0.35, 462),
			]), OUTLINE, 30.0, true)
			draw_polyline(PackedVector2Array([
				Vector2(256, 292), Vector2(x, 370), Vector2(x + (x - 256) * 0.35, 462),
			]), GREEN_DARK, 14.0, true)
		_ellipse(Vector2(256, 220), Vector2(132, 118), OUTLINE, 56)
		_ellipse(Vector2(256, 220), Vector2(114, 100), Color("315b53"), 56)
		for x in [212.0, 256.0, 300.0]:
			draw_line(Vector2(x, 162), Vector2(x, 278), Color(CYAN, 0.82), 9.0, true)
		draw_polyline(PackedVector2Array([Vector2(345, 220), Vector2(410, 185), Vector2(458, 198)]), CYAN, 12.0, true)

	func _draw_enemy() -> void:
		var shield := PackedVector2Array([
			Vector2(84, 180), Vector2(330, 138), Vector2(446, 256), Vector2(332, 374), Vector2(84, 330), Vector2(150, 256),
		])
		_draw_layered_polygon(shield, Color("5b3431"), Color("a75143"))
		for index in range(3):
			var x := 170.0 + index * 76.0
			draw_colored_polygon(PackedVector2Array([
				Vector2(x, 158), Vector2(x + 28, 80), Vector2(x + 58, 152),
			]), OUTLINE)
		draw_polyline(PackedVector2Array([Vector2(135, 256), Vector2(300, 256), Vector2(250, 204)]), BONE, 18.0, true)
		for offset in [-48.0, 48.0]:
			draw_line(Vector2(282 + offset, 320), Vector2(352 + offset, 250), Color(RED, 0.72), 11.0, true)

	func _draw_contact() -> void:
		var left := PackedVector2Array([Vector2(38, 118), Vector2(216, 204), Vector2(160, 256), Vector2(216, 308), Vector2(38, 394), Vector2(108, 256)])
		var right := PackedVector2Array([Vector2(474, 118), Vector2(296, 204), Vector2(352, 256), Vector2(296, 308), Vector2(474, 394), Vector2(404, 256)])
		_draw_layered_polygon(left, Color("6b552f"), AMBER)
		_draw_layered_polygon(right, Color("67362f"), RED)
		draw_line(Vector2(224, 256), Vector2(288, 256), BONE, 16.0, true)
		for offset in [-74.0, 74.0]:
			draw_line(Vector2(256 + offset, 174), Vector2(256 - offset, 338), Color(BONE, 0.52), 9.0, true)

	func _draw_hit() -> void:
		var rays := PackedVector2Array()
		for index in range(16):
			var angle := TAU * float(index) / 16.0
			var radius := 212.0 if index % 2 == 0 else 70.0
			rays.append(Vector2(256, 256) + Vector2.from_angle(angle) * radius)
		_draw_layered_polygon(rays, Color("76572c"), AMBER)
		draw_circle(Vector2(256, 256), 46.0, BONE)
		draw_circle(Vector2(256, 256), 19.0, KEY)

	func _draw_hurt() -> void:
		draw_arc(Vector2(256, 256), 178.0, 0.25, TAU - 0.55, 72, RED, 34.0, true)
		draw_arc(Vector2(256, 256), 133.0, 0.25, TAU - 0.55, 72, Color(BONE, 0.70), 12.0, true)
		for path in [
			PackedVector2Array([Vector2(188, 98), Vector2(224, 188), Vector2(190, 246), Vector2(235, 320)]),
			PackedVector2Array([Vector2(350, 132), Vector2(300, 205), Vector2(338, 278), Vector2(286, 382)]),
		]:
			draw_polyline(path, BONE, 14.0, true)
		draw_colored_polygon(PackedVector2Array([Vector2(208, 420), Vector2(304, 420), Vector2(256, 482)]), RED)

	func _draw_death() -> void:
		for index in range(7):
			var x := 86.0 + index * 58.0
			var top := 92.0 + float(index % 3) * 42.0
			draw_colored_polygon(PackedVector2Array([
				Vector2(x, top), Vector2(x + 42, top + 74), Vector2(x + 8, 316 + index * 9), Vector2(x - 26, top + 82),
			]), Color(BONE, 0.75 if index % 2 == 0 else 0.48))
			draw_line(Vector2(x + 6, 330), Vector2(x - 30, 430), Color(RED, 0.58), 9.0, true)
		draw_line(Vector2(72, 440), Vector2(448, 440), Color(MUTED, 0.70), 18.0, true)
		for x in [142.0, 256.0, 370.0]:
			draw_circle(Vector2(x, 458), 9.0, KEY)

	func _draw_retreat() -> void:
		var wedge := PackedVector2Array([
			Vector2(54, 102), Vector2(450, 170), Vector2(356, 256), Vector2(450, 342), Vector2(54, 410), Vector2(186, 256),
		])
		_draw_layered_polygon(wedge, Color("6b552f"), AMBER)
		draw_polyline(PackedVector2Array([Vector2(390, 256), Vector2(276, 256), Vector2(204, 326), Vector2(108, 326)]), BONE, 19.0, true)
		for offset in [-62.0, 0.0, 62.0]:
			draw_line(Vector2(330 + offset, 154), Vector2(260 + offset, 224), KEY, 20.0, true)

	func _draw_resource() -> void:
		var pod := _ellipse_points(Vector2(256, 275), Vector2(128, 166), 56)
		_draw_layered_polygon(pod, GREEN_DARK, GREEN)
		draw_polyline(PackedVector2Array([Vector2(256, 392), Vector2(256, 280), Vector2(205, 218), Vector2(168, 180)]), OUTLINE, 28.0, true)
		draw_polyline(PackedVector2Array([Vector2(256, 392), Vector2(256, 280), Vector2(205, 218), Vector2(168, 180)]), BONE, 10.0, true)
		for point in [Vector2(300, 198), Vector2(330, 276), Vector2(208, 328)]:
			draw_circle(point, 22.0, OUTLINE)
			draw_circle(point, 10.0, KEY)
		for x in [178.0, 256.0, 334.0]:
			draw_colored_polygon(PackedVector2Array([Vector2(x - 18, 118), Vector2(x, 76), Vector2(x + 18, 118)]), CYAN)

	func _draw_segmented_ring(center: Vector2, outer_radius: float, inner_radius: float, accent: Color, pattern: int) -> void:
		var ring_radius := (outer_radius + inner_radius) * 0.5
		var ring_width := outer_radius - inner_radius
		draw_arc(center, ring_radius, 0, TAU, 96, OUTLINE, ring_width + 28.0, true)
		draw_arc(center, ring_radius, 0, TAU, 96, Color("596257"), ring_width, true)
		for index in range(12):
			var angle := TAU * float(index) / 12.0
			var direction := Vector2.from_angle(angle)
			var side := Vector2(-direction.y, direction.x)
			var inner := center + direction * (inner_radius + 16.0)
			var outer := center + direction * (outer_radius - 12.0)
			draw_colored_polygon(PackedVector2Array([
				inner - side * 30.0, outer - side * 48.0, outer + side * 48.0, inner + side * 30.0,
			]), accent if (index + pattern) % 3 == 0 else Color(BONE, 0.54))

	func _draw_rib_arc(center: Vector2, radius: Vector2, start: float, end: float, width: float, color: Color) -> void:
		var points := PackedVector2Array()
		for index in range(65):
			var angle := lerpf(start, end, float(index) / 64.0)
			points.append(center + Vector2(cos(angle) * radius.x, sin(angle) * radius.y))
		draw_polyline(points, OUTLINE, width + 24.0, true)
		draw_polyline(points, color, width, true)

	func _draw_layered_polygon(points: PackedVector2Array, shadow: Color, fill: Color) -> void:
		var center := Vector2.ZERO
		for point in points:
			center += point
		center /= float(points.size())
		var outer := PackedVector2Array()
		var inner := PackedVector2Array()
		for point in points:
			outer.append(center + (point - center) * 1.07)
			inner.append(center + (point - center) * 0.84)
		draw_colored_polygon(outer, OUTLINE)
		draw_colored_polygon(points, shadow)
		draw_colored_polygon(inner, fill)

	func _ellipse(center: Vector2, radius: Vector2, color: Color, segments: int) -> void:
		draw_colored_polygon(_ellipse_points(center, radius, segments), color)

	func _ellipse_points(center: Vector2, radius: Vector2, segments: int) -> PackedVector2Array:
		var points := PackedVector2Array()
		for index in range(segments):
			var angle := TAU * float(index) / float(segments)
			points.append(center + Vector2(cos(angle) * radius.x, sin(angle) * radius.y))
		return points
