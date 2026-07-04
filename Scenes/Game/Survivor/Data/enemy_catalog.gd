class_name EnemyCatalog
extends Resource
## Lookup table for authored enemy resources used by the wave framework.

@export var entries: Dictionary = {}


# Returns true when the enemy id exists in the catalog.
func has_enemy(enemy_id: String) -> bool:
	return entries.has(enemy_id)


# Returns one raw enemy resource by id.
func get_enemy_data(enemy_id: String) -> EnemyData:
	if not entries.has(enemy_id):
		push_error("EnemyCatalog: unknown enemy id '%s'" % enemy_id)
		return null
	return entries[enemy_id] as EnemyData


# Returns one runtime dictionary for the requested enemy id and level.
func get_runtime_stats(enemy_id: String, level: int) -> Dictionary:
	var data: EnemyData = get_enemy_data(enemy_id)
	if data == null:
		return {}
	return data.to_runtime_dictionary(level)
