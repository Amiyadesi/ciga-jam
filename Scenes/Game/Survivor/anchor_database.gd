class_name AnchorDatabase
extends RefCounted
## Thin wrapper around the authored anchor catalog resource.

const CATALOG: Resource = preload("res://Scenes/Game/Survivor/Data/anchor_catalog.tres")


# Returns the authored anchor catalog as a typed custom resource.
static func _catalog() -> Resource:
	return CATALOG


# Returns stable anchor ids in the hotbar order used by the prototype.
static func get_anchor_ids() -> Array[String]:
	return _catalog().call("get_anchor_ids")


# Returns whether an anchor id exists in the database.
static func has_anchor(anchor_id: String) -> bool:
	return bool(_catalog().call("has_anchor", anchor_id))


# Returns display metadata for a known anchor id.
static func get_anchor_meta(anchor_id: String) -> Dictionary:
	return _catalog().call("get_anchor_meta", anchor_id)


# Returns one level of combat stats, using 1-based anchor levels.
static func get_stats(anchor_id: String, level: int) -> Dictionary:
	return _catalog().call("get_stats", anchor_id, level)


# Returns the price stored on the next level row.
static func get_upgrade_cost(anchor_id: String, current_level: int) -> int:
	return int(_catalog().call("get_upgrade_cost", anchor_id, current_level))
