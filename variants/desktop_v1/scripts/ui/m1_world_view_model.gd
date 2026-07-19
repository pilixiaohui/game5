class_name M1WorldViewModel
extends RefCounted

var tick: int = 0
var resources: Dictionary = {}
var units: Dictionary = {}
var rooms: Array = []
var active_battle: Dictionary = {}
var ledger: Array = []
var captured_nodes: int = 0

static func from_snapshot(snapshot: Dictionary) -> M1WorldViewModel:
	var model := M1WorldViewModel.new()
	model.tick = int(snapshot.get("tick", 0))
	model.resources = (snapshot.get("resources", {}) as Dictionary).duplicate(true)
	model.units = (snapshot.get("units", {}) as Dictionary).duplicate(true)
	model.rooms = (snapshot.get("rooms", []) as Array).duplicate(true)
	model.active_battle = (snapshot.get("active_battle", {}) as Dictionary).duplicate(true)
	model.ledger = (snapshot.get("ledger", []) as Array).duplicate(true)
	for node in snapshot.get("nodes", []):
		if bool(node.get("owned", false)):
			model.captured_nodes += 1
	return model

func is_battle_active() -> bool:
	return not active_battle.is_empty()
