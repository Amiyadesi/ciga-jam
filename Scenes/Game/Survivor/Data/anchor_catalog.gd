class_name AnchorCatalog
extends Resource
## Catalog of anchor level definitions shown in the hotbar and used for placement.

@export var entries: Dictionary = {}
@export var hotbar_order: PackedStringArray = PackedStringArray()


# Returns true when the catalog contains the given anchor id.
func has_anchor(anchor_id: String) -> bool:
	return entries.has(anchor_id)


# Returns stable ids for hotbar display.
func get_anchor_ids() -> Array[String]:
	var ids: Array[String] = []
	for anchor_id in hotbar_order:
		if entries.has(anchor_id):
			ids.append(anchor_id)
	return ids


# Returns the top-level metadata dictionary for one anchor id.
func get_anchor_meta(anchor_id: String) -> Dictionary:
	if not entries.has(anchor_id):
		push_error("AnchorCatalog: unknown anchor id '%s'" % anchor_id)
		return {}
	var meta_variant: Variant = entries[anchor_id]
	if not (meta_variant is Dictionary):
		push_error("AnchorCatalog: invalid entry for '%s'" % anchor_id)
		return {}
	return (meta_variant as Dictionary).duplicate(true)


# Returns one level definition as a typed runtime dictionary.
func get_stats(anchor_id: String, level: int) -> Dictionary:
	var meta: Dictionary = get_anchor_meta(anchor_id)
	if meta.is_empty():
		return {}
	var levels_variant: Variant = meta.get("levels", [])
	if not (levels_variant is Array):
		push_error("AnchorCatalog: missing levels for '%s'" % anchor_id)
		return {}
	var levels: Array = levels_variant as Array
	if levels.is_empty():
		push_error("AnchorCatalog: empty levels for '%s'" % anchor_id)
		return {}
	var index: int = clampi(level - 1, 0, levels.size() - 1)
	var data: Resource = levels[index] as Resource
	if data == null or not data.has_method("to_runtime_dictionary"):
		push_error("AnchorCatalog: level %d for '%s' is not AnchorData" % [level, anchor_id])
		return {}
	return data.to_runtime_dictionary(index + 1, levels.size())


# Returns the next level price used for in-world upgrades.
func get_upgrade_cost(anchor_id: String, current_level: int) -> int:
	var meta: Dictionary = get_anchor_meta(anchor_id)
	if meta.is_empty():
		return 0
	var levels: Array = meta.get("levels", []) as Array
	var next_index: int = current_level
	if next_index < 0 or next_index >= levels.size():
		return 0
	var data: Resource = levels[next_index] as Resource
	return int(data.get("price")) if data != null else 0
