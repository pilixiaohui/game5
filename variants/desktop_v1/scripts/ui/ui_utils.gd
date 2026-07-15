extends RefCounted

static func label(text: String, variation: String = "") -> Label:
	var node := Label.new()
	node.text = text
	if variation != "":
		node.theme_type_variation = variation
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return node

static func button(text: String, callback: Callable, variation: String = "") -> Button:
	var node := Button.new()
	node.text = text
	node.focus_mode = Control.FOCUS_ALL
	if variation != "":
		node.theme_type_variation = variation
	node.pressed.connect(callback)
	return node

static func separator(vertical: bool = false) -> Control:
	var node: Control = VSeparator.new() if vertical else HSeparator.new()
	return node

static func clear(container: Node) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()

static func spacer(expand: bool = true) -> Control:
	var node := Control.new()
	if expand:
		node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		node.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return node

static func progress(value: float, maximum: float = 100.0) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.max_value = maximum
	bar.value = value
	bar.show_percentage = false
	bar.custom_minimum_size.y = 8
	return bar
