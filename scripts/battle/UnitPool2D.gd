class_name UnitPool2D
extends Node2D

var _pool: Array[Node2D] = []

func fetch() -> Node2D:
	if _pool.is_empty():
		return Node2D.new()
	return _pool.pop_back()

func recycle(node: Node2D) -> void:
	node.visible = false
	if node.get_parent() != null:
		node.get_parent().remove_child(node)
	_pool.append(node)
