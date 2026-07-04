class_name SkillDatabase
extends RefCounted
## CIGA 局内成长卡数据库，负责加载、筛选和运行时修正。

const SKILL_RESOURCES: Array[Resource] = [
	preload("res://Scenes/Game/Survivor/Data/skill_1001.tres"),
	preload("res://Scenes/Game/Survivor/Data/skill_1002.tres"),
	preload("res://Scenes/Game/Survivor/Data/skill_1003.tres"),
	preload("res://Scenes/Game/Survivor/Data/skill_1004.tres"),
	preload("res://Scenes/Game/Survivor/Data/skill_1005.tres"),
	preload("res://Scenes/Game/Survivor/Data/skill_1006.tres"),
	preload("res://Scenes/Game/Survivor/Data/skill_1007.tres"),
	preload("res://Scenes/Game/Survivor/Data/skill_1008.tres"),
	preload("res://Scenes/Game/Survivor/Data/skill_1009.tres"),
	preload("res://Scenes/Game/Survivor/Data/skill_1010.tres"),
	preload("res://Scenes/Game/Survivor/Data/skill_1011.tres"),
	preload("res://Scenes/Game/Survivor/Data/skill_1012.tres"),
	preload("res://Scenes/Game/Survivor/Data/skill_1013.tres"),
	preload("res://Scenes/Game/Survivor/Data/skill_1014.tres"),
	preload("res://Scenes/Game/Survivor/Data/skill_1015.tres"),
	preload("res://Scenes/Game/Survivor/Data/skill_1016.tres"),
	preload("res://Scenes/Game/Survivor/Data/skill_1017.tres"),
	preload("res://Scenes/Game/Survivor/Data/skill_1018.tres"),
	preload("res://Scenes/Game/Survivor/Data/skill_1019.tres"),
]

static var _skills: Array[Dictionary] = []
static var _skills_by_id: Dictionary = {}
static var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
static var _rng_ready: bool = false


# 加载并缓存所有技能资源行。
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


# 报告已知的表格问题，但不阻塞原型运行。
static func validate() -> void:
	load_skills()
	var skill: Dictionary = get_skill(1002)
	if not skill.is_empty() and str(skill.get("name", "")) == "快速咏唱III":
		push_warning("SkillDatabase: skill 1002 is named 快速咏唱III in skill_setting.xlsx; data treats it as tier II by prerequisite chain.")


# 通过 id 取出一条技能定义。
static func get_skill(skill_id: int) -> Dictionary:
	load_skills()
	if not _skills_by_id.has(skill_id):
		return {}
	return (_skills_by_id[skill_id] as Dictionary).duplicate(true)


# 返回技能名称，供轻量 UI 使用。
static func get_skill_name(skill_id: int) -> String:
	var skill: Dictionary = get_skill(skill_id)
	return str(skill.get("name", ""))


# 返回当前最多 count 张可选卡牌。
static func get_available_options(player_state: Dictionary, count: int = 3) -> Array[Dictionary]:
	_ensure_rng_ready()
	var selected: Array = player_state.get("selected_skill_ids", []) as Array
	var selected_ids: Array[int] = []
	for selected_id in selected:
		selected_ids.append(int(selected_id))
	var available: Array[Dictionary] = _get_drawable_skills(selected_ids)
	if available.is_empty():
		return []
	var options: Array[Dictionary] = []
	if available.size() >= count:
		var pool: Array[Dictionary] = []
		for item in available:
			pool.append((item as Dictionary).duplicate(true))
		while options.size() < count and not pool.is_empty():
			var pick_index: int = _rng.randi_range(0, pool.size() - 1)
			options.append((pool[pick_index] as Dictionary).duplicate(true))
			pool.remove_at(pick_index)
	else:
		while options.size() < count:
			var repeat_index: int = _rng.randi_range(0, available.size() - 1)
			options.append((available[repeat_index] as Dictionary).duplicate(true))
	return options


# 只返回当前已经满足前置条件的可抽技能列表。
static func _get_drawable_skills(selected_ids: Array[int]) -> Array[Dictionary]:
	var selected_groups: Dictionary = {}
	for selected_id in selected_ids:
		var selected_skill: Dictionary = get_skill(int(selected_id))
		if selected_skill.is_empty():
			continue
		selected_groups[int(selected_skill.get("group_id", 0))] = true
	var available: Array[Dictionary] = []
	for skill in load_skills():
		var skill_id: int = int(skill.get("id", 0))
		if selected_ids.has(skill_id):
			continue
		var group_id: int = int(skill.get("group_id", 0))
		var prerequisite: int = int(skill.get("prerequisite", 0))
		if prerequisite <= 0 and selected_groups.has(group_id):
			continue
		if prerequisite > 0 and not selected_ids.has(prerequisite):
			continue
		available.append((skill as Dictionary).duplicate(true))
	return available


# 初始化技能抽卡用的随机数发生器。
static func _ensure_rng_ready() -> void:
	if _rng_ready:
		return
	_rng.randomize()
	_rng_ready = true


# 把已选择技能转换成整局运行时修正。
static func build_run_modifiers(selected_skill_ids: Array[int]) -> Dictionary:
	load_skills()
	var attack_cooldown_reduction: float = 0.0
	var attack_bonus: float = 0.0
	var splash_percent: float = 0.0
	var splash_radius: float = 0.0
	var pierce_falloff: float = 0.0
	var anchor_limit: int = 9
	var anchor_attack_bonus: float = 0.0
	var reward_bonus: float = 0.0
	var anchor_hit_slow_percent: float = 0.0
	for skill_id in selected_skill_ids:
		var skill: Dictionary = get_skill(skill_id)
		var group_id: int = int(skill.get("group_id", 0))
		match group_id:
			1:
				attack_cooldown_reduction = maxf(attack_cooldown_reduction, float(skill.get("value", 0.0)))
			2:
				attack_bonus = maxf(attack_bonus, float(skill.get("value", 0.0)))
			3:
				splash_percent = maxf(splash_percent, float(skill.get("value", 0.0)) / 100.0)
				splash_radius = maxf(splash_radius, float(skill.get("value2", 0.0)))
			4:
				var falloff: float = float(skill.get("value", 0.0)) / 100.0
				pierce_falloff = falloff if pierce_falloff <= 0.0 else minf(pierce_falloff, falloff)
			5:
				anchor_limit = maxi(anchor_limit, int(skill.get("value", 9.0)))
			6:
				anchor_attack_bonus = maxf(anchor_attack_bonus, float(skill.get("value", 0.0)) / 100.0)
			7:
				reward_bonus = maxf(reward_bonus, float(skill.get("value", 0.0)) / 100.0)
			8:
				anchor_hit_slow_percent = maxf(anchor_hit_slow_percent, float(skill.get("value", 0.0)) / 100.0)
			_:
				pass
	return {
		"player_attack_cooldown_multiplier": maxf(0.1, 1.0 - attack_cooldown_reduction),
		"player_attack_multiplier": 1.0 + attack_bonus,
		"player_splash_percent": splash_percent,
		"player_splash_radius": splash_radius,
		"player_pierce_enabled": pierce_falloff > 0.0,
		"player_pierce_falloff": pierce_falloff,
		"anchor_limit": anchor_limit,
		"anchor_attack_multiplier": 1.0 + anchor_attack_bonus,
		"gold_multiplier": 1.0 + reward_bonus,
		"exp_multiplier": 1.0 + reward_bonus,
		"anchor_hit_slow_percent": anchor_hit_slow_percent,
		"anchor_hit_slow_duration": 1.0,
	}


# 把玩家当前真正生效的技能整理成摘要，同组只保留最后一次选择的最高级。
static func get_selected_skill_summaries(selected_skill_ids: Array[int]) -> Array[Dictionary]:
	load_skills()
	var grouped: Dictionary = {}
	for skill_id in selected_skill_ids:
		var skill: Dictionary = get_skill(skill_id)
		if skill.is_empty():
			continue
		grouped[int(skill.get("group_id", 0))] = skill
	var summaries: Array[Dictionary] = []
	var group_ids: Array[int] = []
	for key in grouped.keys():
		group_ids.append(int(key))
	group_ids.sort()
	for group_id in group_ids:
		var item: Dictionary = (grouped[group_id] as Dictionary).duplicate(true)
		item["summary_text"] = "%s  %s" % [_rarity_text(int(item.get("rarity", 1))), str(item.get("name", ""))]
		summaries.append(item)
	return summaries


# 保留旧接口名，兼容仍在迁移中的调用方。
static func build_player_modifiers(selected_skill_ids: Array[int]) -> Dictionary:
	return build_run_modifiers(selected_skill_ids)


# 为技能摘要提供简短稀有度文案。
static func _rarity_text(rarity: int) -> String:
	match rarity:
		1:
			return "普通"
		2:
			return "稀有"
		3:
			return "史诗"
		_:
			return "未知"
