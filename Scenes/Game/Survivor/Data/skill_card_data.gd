class_name SkillCardData
extends Resource
## Immutable one-card definition migrated from the spreadsheet export.

@export var id: int = 0
@export var name: String = ""
@export var value: float = 0.0
@export var value2: float = 0.0
@export var rarity: int = 1
@export var prerequisite: int = 0
@export_multiline var description: String = ""
@export var group_id: int = 0


# Returns a UI-ready description with spreadsheet placeholders resolved.
func build_description() -> String:
	return description.format([_format_number(value), _format_number(value2)])


# Returns a defensive runtime dictionary for gameplay queries.
func to_dictionary() -> Dictionary:
	return {
		"id": id,
		"name": name,
		"value": value,
		"value2": value2,
		"rarity": rarity,
		"prerequisite": prerequisite,
		"description": description,
		"display_description": build_description(),
		"group_id": group_id,
	}


# Formats floats without noisy tail zeroes for authored UI text.
func _format_number(raw: float) -> String:
	if is_zero_approx(raw - roundf(raw)):
		return str(int(round(raw)))
	return str(snappedf(raw, 0.01)).trim_suffix("0").trim_suffix(".")
