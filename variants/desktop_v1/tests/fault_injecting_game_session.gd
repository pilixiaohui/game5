extends "res://scripts/core/game_session.gd"

var failure_steps: Dictionary = {}
var corruption_steps: Dictionary = {}
var operation_trace: Array[String] = []
var operation_phase_trace: Array[String] = []

func inject(callsite: String, phase: String = "*", count: int = 1) -> void:
	failure_steps[_boundary_key(callsite, phase)] = count

func corrupt_after(step: String, count: int = 1) -> void:
	corruption_steps[step] = count

func clear_injections() -> void:
	failure_steps.clear()
	corruption_steps.clear()
	operation_trace.clear()
	operation_phase_trace.clear()

func _fs_make_dir(path: String, callsite: String) -> Error:
	if _should_fail(callsite, "make_dir"):
		return ERR_CANT_CREATE
	return super._fs_make_dir(path, callsite)

func _fs_remove(path: String, callsite: String) -> Error:
	if _should_fail(callsite, "remove"):
		return ERR_CANT_CREATE
	return super._fs_remove(path, callsite)

func _fs_copy(source: String, destination: String, callsite: String) -> Error:
	if _should_fail(callsite, "copy"):
		return ERR_CANT_CREATE
	return super._fs_copy(source, destination, callsite)

func _fs_rename(source: String, destination: String, callsite: String) -> Error:
	if _should_fail(callsite, "rename"):
		return ERR_CANT_CREATE
	var error := super._fs_rename(source, destination, callsite)
	if error == OK and _should_corrupt(callsite):
		var file := FileAccess.open(destination, FileAccess.WRITE)
		if file == null:
			return FileAccess.get_open_error()
		file.store_string("{fault-injected-corruption")
		var write_error := file.get_error()
		file.close()
		return write_error
	return error

func _fs_path_status(path: String, callsite: String) -> Dictionary:
	if _should_fail(callsite, "exists"):
		return {"status": SNAPSHOT_IO_ERROR, "error_code": ERR_FILE_CANT_READ}
	return super._fs_path_status(path, callsite)

func _fs_open_snapshot_read(path: String, callsite: String) -> Dictionary:
	if _should_fail(callsite, "open"):
		return {"file": null, "error": ERR_CANT_OPEN}
	return super._fs_open_snapshot_read(path, callsite)

func _fs_read_snapshot_bytes(file: FileAccess, callsite: String) -> Dictionary:
	if _should_fail(callsite, "read"):
		return {"text": "", "error": ERR_FILE_CANT_READ}
	return super._fs_read_snapshot_bytes(file, callsite)

func _fs_open_snapshot_write(path: String, callsite: String) -> Dictionary:
	if _should_fail(callsite, "open"):
		return {"file": null, "error": ERR_CANT_OPEN}
	return super._fs_open_snapshot_write(path, callsite)

func _fs_write_snapshot_bytes(file: FileAccess, text: String, callsite: String) -> Error:
	if _should_fail(callsite, "write"):
		file.store_string(text.left(maxi(1, text.length() / 2)))
		return ERR_FILE_CANT_WRITE
	return super._fs_write_snapshot_bytes(file, text, callsite)

func _should_fail(callsite: String, phase: String) -> bool:
	assert(callsite in PERSISTENCE_IO_CALLSITES, "test reached unnamed persistence callsite: %s" % callsite)
	var exact_key := _boundary_key(callsite, phase)
	operation_trace.append(callsite)
	operation_phase_trace.append(exact_key)
	for injection_key in [exact_key, _boundary_key(callsite, "*")]:
		var remaining := int(failure_steps.get(injection_key, 0))
		if remaining > 0:
			failure_steps[injection_key] = remaining - 1
			return true
	return false

func _should_corrupt(callsite: String) -> bool:
	assert(callsite in PERSISTENCE_IO_CALLSITES, "test reached unnamed persistence callsite: %s" % callsite)
	var remaining := int(corruption_steps.get(callsite, 0))
	if remaining <= 0:
		return false
	corruption_steps[callsite] = remaining - 1
	return true

func _boundary_key(callsite: String, phase: String) -> String:
	return "%s.%s" % [callsite, phase]
