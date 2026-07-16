extends RefCounted

const TITLE_BACKGROUND = preload("res://assets/art_v1/title_hive_field_manual_v1.png")

const ROOM_BIOMASS_FILTER = preload("res://assets/art_v1/room_biomass_filter_v1.png")
const ROOM_THERMAL_METABOLISM = preload("res://assets/art_v1/room_thermal_metabolism_v1.png")
const ROOM_EMBRYO_HATCHERY = preload("res://assets/art_v1/room_embryo_hatchery_v1.png")

const SWARM_WORKER = preload("res://assets/art_v1/swarm_worker_v1.png")
const SWARM_BITER = preload("res://assets/art_v1/swarm_biter_v1.png")
const SWARM_ROOT_SPORE = preload("res://assets/art_v1/swarm_root_spore_v1.png")

const STATE_RESOURCE = preload("res://assets/art_v1/state_resource_v1.png")
const STATE_THREAT = preload("res://assets/art_v1/state_threat_v1.png")
const STATE_OWNED = preload("res://assets/art_v1/state_owned_v1.png")
const STATE_ENGAGED = preload("res://assets/art_v1/state_engaged_v1.png")
const STATE_RETREAT = preload("res://assets/art_v1/state_retreat_v1.png")

static func room_icon(kind: String) -> Texture2D:
	match kind:
		"biomass_filter":
			return ROOM_BIOMASS_FILTER
		"thermal_metabolism":
			return ROOM_THERMAL_METABOLISM
		"embryo_hatchery":
			return ROOM_EMBRYO_HATCHERY
	return null

static func room_accent(kind: String) -> Color:
	match kind:
		"biomass_filter":
			return Color("82d67b")
		"thermal_metabolism":
			return Color("e2ba60")
		"embryo_hatchery":
			return Color("57c4c3")
	return Color("294047")

static func swarm_icon(kind: String) -> Texture2D:
	match kind:
		"worker":
			return SWARM_WORKER
		"biter":
			return SWARM_BITER
		"root_spore":
			return SWARM_ROOT_SPORE
	return null

static func state_icon(state: String) -> Texture2D:
	match state:
		"resource":
			return STATE_RESOURCE
		"threat":
			return STATE_THREAT
		"owned":
			return STATE_OWNED
		"engaged":
			return STATE_ENGAGED
		"retreat":
			return STATE_RETREAT
	return null
