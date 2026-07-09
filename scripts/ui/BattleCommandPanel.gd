extends HBoxContainer

signal command_requested(action: String)

func _ready() -> void:
	if get_child_count() > 0:
		return
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_add_command_button("蓄兵", "prepare")
	_add_command_button("强攻", "assault")
	_add_command_button("撤离保全", "retreat")

func _add_command_button(text: String, action: String) -> void:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 50)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	button.clip_text = false
	button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.pressed.connect(func() -> void:
		command_requested.emit(action)
	)
	add_child(button)
