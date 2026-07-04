class_name SkillDatabase
extends RefCounted
## Loader and selector for the CIGA in-run skill card resources.

const SKILL_RESOURCES: Array[Resource] = [
	preload("res://Scenes/Game/Survivor/Data/skill_1001.tres"),
	preload("res://Scenes/Game/Survivor/Data/skill_1002.tres"),
	preload("res://Scenes/Game/Survivor/Data/skill_1003.tres"),
	preload("res://Scenes/Game/Survivor/Data/skill_1004.tres"),
	preload("res://Scenes/Game/Survivor/Data/skill_1005.tres"),
	preload("res://Scenes/Game/Survivor/Data/skill_1006.tres"),
	preload("res://Scenes/Game/Survivor/Data/skill_1007.tres"),
	preload("res://Scenes/Game/Survivor/Data/skill_1008.tres"),
]

static var _skills: Array[Dictionary] = []
static var _skills_by_id: Dictionary = {}


# Loads and caches the authored resource rows.
static func load_skills() -> Array[Dictionary]:
	if not _skills.is_empty():
		return _skills
	for resource in SKILL_RESOURCES:
		if resource == null or not resource.has_method("to_dictionary"):
			continue
		var skill: Dictionary = resource.call("to_dictionary")
		_skills.append(skill)
		_skills_by_id[int(skill.get("id", 0))] = skill
	return _skills


# Reports known authoring issues without blocking the prototype.
static func validate() -> void:
	load_skills()
	var skill: Dictionary = get_skill(1002)
	if not skill.is_empty() and str(skill.get("name", "")) == "快速咏唱III":
		push_warning("SkillDatabase: skill 1002 is named 快速咏唱III in skill_setting.xlsx; data treats it as tier II by prerequisite chain.")


# Gets one skill dictionary by numeric id.
static func get_skill(skill_id: int) -> Dictionary:
	load_skills()
	if not _skills_by_id.has(skill_id):
		return {}
	return (_skills_by_id[skill_id] as Dictionary).duplicate(true)


# Returns the authored card name for lightweight UI helper text.
static func get_skill_name(skill_id: int) -> String:
	var skill: Dictionary = get_skill(skill_id)
	return str(skill.get("name", ""))


# Returns up to count currently selectable skill options.
static func get_available_options(player_state: Dictionary, count: int = 3) -> Array[Dictionary]:
	var selected: Array = player_state.get("selected_skill_ids", []) as Array
	var selected_groups: Dictionary = {}
	for selected_id in selected:
		var selected_skill: Dictionary = get_skill(int(selected_id))
		if selected_skill.is_empty():
			continue
		selected_groups[int(selected_skill.get("group_id", 0))] = true
	var available: Array[Dictionary] = []
	for skill in load_skills():
		var skill_id: int = int(skill.get("id", 0))
		if selected.has(skill_id):
			continue
		var group_id: int = int(skill.get("group_id", 0))
		var prerequisite: int = int(skill.get("prerequisite", 0))
		if prerequisite <= 0 and selected_groups.has(group_id):
			continue
		if prerequisite > 0 and not selected.has(prerequisite):
			continue
		available.append(skill.duplicate(true))
	available.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.get("rarity", 0)) == int(b.get("rarity", 0)):
			return int(a.get("id", 0)) < int(b.get("id", 0))
		return int(a.get("rarity", 0)) < int(b.get("rarity", 0))
	)
	return available.slice(0, mini(count, available.size()))


# Converts selected skills into player combat modifiers.
static func build_player_modifiers(selected_skill_ids: Array[int]) -> Dictionary:
	load_skills()
	var attack_speed_bonus: float = 0.0
	var attack_bonus: float = 0.0
	var splash_percent: float = 0.0
	var splash_radius: float = 0.0
	for skill_id in selected_skill_ids:
		var skill: Dictionary = get_skill(skill_id)
		var group_id: int = int(skill.get("group_id", 0))
		match group_id:
			1:
				attack_speed_bonus = maxf(attack_speed_bonus, float(skill.get("value", 0.0)))
			2:
				attack_bonus = maxf(attack_bonus, float(skill.get("value", 0.0)))
			3:
				splash_percent = maxf(splash_percent, float(skill.get("value", 0.0)) / 100.0)
				splash_radius = maxf(splash_radius, float(skill.get("value2", 0.0)))
			_:
				pass
	return {
		"attack_speed_multiplier": 1.0 + attack_speed_bonus,
		"attack_multiplier": 1.0 + attack_bonus,
		"splash_percent": splash_percent,
		"splash_radius": splash_radius
	}
