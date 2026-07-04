class_name EnemyData
extends Resource
## Immutable enemy definition used by wave data and runtime spawns.

@export_group("Identity")
@export var enemy_id: String = ""
@export var display_name: String = ""

@export_group("Stats")
@export var base_max_hp: float = 70.0
@export var hp_per_level: float = 30.0
@export var base_attack_damage: float = 3.0
@export var damage_per_level: float = 2.0
@export var base_speed: float = 132.0
@export var speed_per_level: float = 7.0
@export var attack_cooldown: float = 1.0
@export var attack_range: float = 36.0
@export var player_chase_radius: float = 150.0
@export var house_priority_radius: float = 300.0
@export var anchor_chase_radius: float = 200.0
@export var structure_attack_padding: float = 95.0

@export_group("Rewards")
@export var exp_rewards: PackedFloat32Array = PackedFloat32Array()
@export var gold_rewards: PackedInt32Array = PackedInt32Array()

@export_group("Visual")
@export var tint: Color = Color(0.20, 0.68, 0.36, 1.0)
@export var scale_multiplier: float = 1.0

@export_group("Boss")
@export var is_boss: bool = false
@export var summon_enemy_id: String = ""
@export var summon_count: int = 0
@export var summon_interval: float = 6.0
@export var summon_ring_radius: float = 120.0


# Returns one runtime-ready enemy dictionary for the requested level.
func to_runtime_dictionary(level: int) -> Dictionary:
	var safe_level: int = maxi(1, level)
	return {
		"enemy_id": enemy_id,
		"display_name": display_name,
		"level": safe_level,
		"max_hp": base_max_hp + hp_per_level * float(safe_level),
		"attack_damage": base_attack_damage + damage_per_level * float(safe_level),
		"speed": base_speed + speed_per_level * float(safe_level - 1),
		"attack_cooldown": attack_cooldown,
		"attack_range": attack_range,
		"player_chase_radius": player_chase_radius,
		"house_priority_radius": house_priority_radius,
		"anchor_chase_radius": anchor_chase_radius,
		"structure_attack_padding": structure_attack_padding,
		"exp_reward": _pick_exp_reward(safe_level),
		"gold_reward": _pick_gold_reward(safe_level),
		"tint": tint,
		"scale_multiplier": scale_multiplier,
		"is_boss": is_boss,
		"summon_enemy_id": summon_enemy_id,
		"summon_count": summon_count,
		"summon_interval": summon_interval,
		"summon_ring_radius": summon_ring_radius,
	}


# Reads one EXP reward row and falls back to the last authored value.
func _pick_exp_reward(level: int) -> int:
	if exp_rewards.is_empty():
		return level * 2
	var index: int = clampi(level - 1, 0, exp_rewards.size() - 1)
	return int(round(float(exp_rewards[index])))


# Reads one gold reward row and falls back to the last authored value.
func _pick_gold_reward(level: int) -> int:
	if gold_rewards.is_empty():
		return 50 + level * 5
	var index: int = clampi(level - 1, 0, gold_rewards.size() - 1)
	return int(gold_rewards[index])
