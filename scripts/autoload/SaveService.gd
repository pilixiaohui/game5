extends Node

const SAVE_PATH := "user://endless_flood_save.json"

var GameState
var last_error: String = ""

func _enter_tree() -> void:
	_bind_dependencies()

func _ready() -> void:
	_bind_dependencies()
	load_game()

func _bind_dependencies() -> void:
	if GameState == null and get_tree() != null and get_tree().root.has_node("GameState"):
		GameState = get_tree().root.get_node("GameState")

func save_game() -> bool:
	GameState.ensure_config_defaults()
	GameState.last_save_unix = Time.get_unix_time_from_system()
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		last_error = "无法写入存档：%s" % FileAccess.get_open_error()
		return false
	file.store_string(JSON.stringify(GameState.to_dict(), "\t"))
	file.close()
	last_error = ""
	return true

func load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		GameState.ensure_config_defaults()
		return false
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		last_error = "无法读取存档：%s" % FileAccess.get_open_error()
		return false
	var content := file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(content)
	if typeof(parsed) != TYPE_DICTIONARY:
		last_error = "存档 JSON 损坏，已保留新档。"
		return false
	GameState.from_dict(parsed)
	last_error = ""
	return true

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_game()
