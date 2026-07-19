extends SceneTree

const MANIFEST_PATH := "res://docs/m1_hive_battle_world_slice_manifest.json"

var failures: Array[String] = []
var checked := 0
var started_msec := 0

func _initialize() -> void:
	started_msec = Time.get_ticks_msec()
	print("M1_ASSET_LIFECYCLE phase=start total_ms=0")
	call_deferred("_run")

func _run() -> void:
	var manifest := _read_manifest()
	if manifest.is_empty():
		await _finish()
		return
	_check(String(manifest.get("art_revision", "")) == "m1-art-v2-rail78", "manifest must expose the accepted rail78 revision")
	var assets: Array = manifest.get("assets", [])
	var preview: Dictionary = manifest.get("preview_evidence", {})
	var captures: Array = preview.get("raw_capture_files", [])
	var annotations: Array = preview.get("annotated_files", [])
	_check(assets.size() == 16, "manifest must contain exactly 16 runtime assets")
	_check(captures.size() == 9, "manifest must contain exactly nine raw captures")
	_check(annotations.size() == 6, "manifest must contain exactly six annotations")
	var unique := {}
	for entry in assets + captures + annotations:
		_check_evidence_file(entry)
		unique[String(entry.get("file", ""))] = true
	_check(unique.size() == 31, "31-file evidence contract must contain no duplicate paths")
	_check_import_contracts(assets)
	_check_source_contract(manifest.get("source_policy", {}))
	_check_geometry_contract(preview)
	_check_old_contract_removed(annotations)
	await _finish()

func _read_manifest() -> Dictionary:
	if not FileAccess.file_exists(MANIFEST_PATH):
		failures.append("manifest is missing")
		return {}
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(MANIFEST_PATH)) != OK or not parser.data is Dictionary:
		failures.append("manifest is not valid JSON")
		return {}
	return parser.data

func _check_evidence_file(entry: Dictionary) -> void:
	var relative := String(entry.get("file", ""))
	var path := "res://%s" % relative
	_check(not relative.is_empty() and FileAccess.file_exists(path), "%s must exist" % relative)
	if relative.is_empty() or not FileAccess.file_exists(path):
		return
	var bytes := FileAccess.get_file_as_bytes(path)
	_check(bytes.size() == int(entry.get("bytes", -1)), "%s byte count must match manifest" % relative)
	_check(FileAccess.get_sha256(path) == String(entry.get("sha256", "")), "%s SHA-256 must match manifest" % relative)
	var expected: Array = entry.get("size", [])
	if expected.size() == 2:
		var image := Image.new()
		var error := image.load_png_from_buffer(bytes)
		_check(error == OK and not image.is_empty(), "%s must load as PNG" % relative)
		if error == OK and not image.is_empty():
			_check(Vector2i(image.get_width(), image.get_height()) == Vector2i(int(expected[0]), int(expected[1])), "%s dimensions must match manifest" % relative)
	checked += 1

func _check_import_contracts(assets: Array) -> void:
	for entry in assets:
		var import_path := "res://%s.import" % String(entry.get("file", ""))
		_check(FileAccess.file_exists(import_path), "%s must retain Godot import metadata" % import_path)
		if not FileAccess.file_exists(import_path):
			continue
		var text := FileAccess.get_file_as_string(import_path)
		for setting in ["compress/mode=0", "mipmaps/generate=false", "process/fix_alpha_border=true", "process/premult_alpha=false"]:
			_check(text.contains(setting), "%s must retain %s" % [import_path, setting])

func _check_source_contract(source_policy: Dictionary) -> void:
	_check(String(source_policy.get("provider", "")).contains("mcp__multica_imagegen__image_gen"), "source policy must identify the built-in image provider")
	for key in ["environment_source", "specimen_source"]:
		var source: Dictionary = source_policy.get(key, {})
		_check_evidence_file(source)
	_check(FileAccess.file_exists("res://docs/art_m1_sources/PROMPTS.md"), "source prompt record must exist")

func _check_geometry_contract(preview: Dictionary) -> void:
	var rail: Dictionary = preview.get("rail_safe_zone_contract", {})
	var boundary := float(rail.get("reserved_start_design_y", 0.0))
	_check(float(rail.get("reserved_start_percent", 0.0)) == 78.0, "rail reserve must begin at 78 percent")
	_check(float(rail.get("actual_icon_top_design_y", 0.0)) >= boundary, "rail icon must remain inside the reserved zone")
	_check(float(rail.get("actual_rail_line_design_y", 0.0)) >= boundary, "rail line must remain inside the reserved zone")
	var contours: Dictionary = rail.get("semantic_contour_max_y_design", {})
	_check(contours.size() == 5, "geometry contract must cover five semantic VFX")
	for name in contours.keys():
		_check(float(contours[name]) < boundary, "%s VFX must remain above the rail reserve" % name)

func _check_old_contract_removed(annotations: Array) -> void:
	var manifest_text := FileAccess.get_file_as_string(MANIFEST_PATH)
	var prompt_text := FileAccess.get_file_as_string("res://docs/art_m1_sources/PROMPTS.md")
	for stale in ["14 TO 86", "86 TO 100", "86%", "_rail-safe.png"]:
		_check(not manifest_text.contains(stale) and not prompt_text.contains(stale), "old 86 percent contract must have zero hits for %s" % stale)
	for entry in annotations:
		_check(String(entry.get("file", "")).contains("_rail78-safe.png"), "annotation paths must use the rail78 contract name")

func _check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)

func _finish() -> void:
	var status := 0 if failures.is_empty() else 1
	if status == 0:
		print("M1_ASSET_CONTRACT_OK files=31 assets=16 captures=9 annotations=6 imports=16 rail=78-100 vfx=action-field sources=verified checked=%d" % checked)
	else:
		for failure in failures:
			push_error("M1_ASSET_CONTRACT_FAILED %s" % failure)
	print("M1_ASSET_LIFECYCLE phase=complete total_ms=%d status=%d checked=%d" % [_elapsed_msec(), status, checked])

	for child in root.get_children():
		_disable_node_tree(child)
		child.free()
	await process_frame
	var remaining_nodes := root.get_child_count()
	var remaining_signals := _root_signal_connection_count()
	if remaining_nodes != 0 or remaining_signals != 0:
		status = 1
		push_error("M1_ASSET_CONTRACT_FAILED lifecycle teardown retained nodes=%d signals=%d" % [remaining_nodes, remaining_signals])
	print("M1_ASSET_LIFECYCLE phase=teardown total_ms=%d status=%d nodes=%d signals=%d" % [_elapsed_msec(), status, remaining_nodes, remaining_signals])
	print("M1_ASSET_LIFECYCLE phase=quit total_ms=%d status=%d" % [_elapsed_msec(), status])
	quit(status)

func _disable_node_tree(node: Node) -> void:
	node.process_mode = Node.PROCESS_MODE_DISABLED
	node.set_process(false)
	node.set_physics_process(false)
	node.set_process_input(false)
	node.set_process_unhandled_input(false)
	for child in node.get_children():
		_disable_node_tree(child)

func _root_signal_connection_count() -> int:
	var total := 0
	for child in root.get_children():
		total += _node_signal_connection_count(child)
	return total

func _node_signal_connection_count(node: Node) -> int:
	var total := 0
	for signal_info in node.get_signal_list():
		var signal_name := StringName(signal_info.get("name", ""))
		if not signal_name.is_empty():
			total += node.get_signal_connection_list(signal_name).size()
	for child in node.get_children():
		total += _node_signal_connection_count(child)
	return total

func _elapsed_msec() -> int:
	return Time.get_ticks_msec() - started_msec
