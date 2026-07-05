class_name ProjectileAnchorBehavior
extends Node
## 投射物锚点通用行为，供单发和多发锚点共用。

const BULLET_SCENE: PackedScene = preload("res://Scenes/Game/Survivor/magic_bullet.tscn")

@export var shot_count: int = 1
@export var spread_offset: float = 16.0
@export var projectile_color: Color = Color(0.66, 0.88, 1.0, 1.0)

var _anchor: Node
var _fire_timer: float = 0.0
var _projectile_modifiers: Dictionary = {}


# 在子行为场景实例化后缓存所属锚点。
func setup(anchor: Node) -> void:
	_anchor = anchor
	var params: Dictionary = anchor.get("behavior_params") as Dictionary
	shot_count = maxi(1, int(params.get("shot_count", shot_count)))
	spread_offset = float(params.get("spread_offset", spread_offset))
	projectile_color = params.get("projectile_color", projectile_color) as Color
	_projectile_modifiers = {
		"pierce_enabled": bool(params.get("pierce_enabled", false)),
		"pierce_falloff": clampf(float(params.get("pierce_falloff", 0.0)), 0.0, 0.95),
	}
	_fire_timer = 0.0


# 只要攻击冷却转好，就朝最近敌人发射一轮投射物。
func _physics_process(delta: float) -> void:
	if not is_instance_valid(_anchor):
		return
	_fire_timer = maxf(0.0, _fire_timer - delta)
	if _fire_timer > 0.0:
		return
	var target: Node2D = _anchor.call("find_nearest_enemy") as Node2D
	if target == null:
		return
	var cooldown: float = float(_anchor.get("attack_cooldown"))
	_fire_timer = maxf(0.01, cooldown)
	_fire_at(target)


# 按当前配置生成一轮投射物，并补一次施法音效。
func _fire_at(target: Node2D) -> void:
	var parent: Node = _resolve_projectile_parent()
	if parent == null:
		return
	var damage: float = float(_anchor.get("attack_damage"))
	for i in range(maxi(1, shot_count)):
		var projectile_modifiers: Dictionary = _projectile_modifiers.duplicate(true)
		projectile_modifiers["status_effects"] = _get_anchor_status_effects()
		var bullet: Area2D = BULLET_SCENE.instantiate() as Area2D
		parent.add_child(bullet)
		var centered_index: float = float(i) - float(shot_count - 1) * 0.5
		var offset: Vector2 = Vector2(0.0, centered_index * spread_offset)
		var direction: Vector2 = _anchor.global_position.direction_to(target.global_position + offset)
		bullet.call("setup", _anchor.global_position + offset, direction, damage, projectile_color, _anchor, 0.0, 0.0, projectile_modifiers)
	var game_audio: Node = _anchor.get_tree().root.get_node_or_null("GameAudio") if _anchor != null and _anchor.get_tree() != null else null
	if game_audio != null:
		game_audio.call("play_fireball")


# 优先把子弹挂到统一的投射物容器，避免污染锚点节点列表。
func _resolve_projectile_parent() -> Node:
	if _anchor == null or _anchor.get_tree() == null:
		return null
	var scene_root: Node = _anchor.get_tree().current_scene
	if scene_root != null:
		var projectile_root: Node = scene_root.get_node_or_null("World/Projectiles")
		if projectile_root != null:
			return projectile_root
	return _anchor.get_parent()


# Copies anchor-provided hit effects onto spawned projectiles.
func _get_anchor_status_effects() -> Array[Dictionary]:
	if _anchor == null or not _anchor.has_method("get_on_hit_status_effects"):
		return []
	var raw_effects: Variant = _anchor.call("get_on_hit_status_effects")
	var effects: Array[Dictionary] = []
	if not (raw_effects is Array):
		return effects
	for raw_effect in raw_effects as Array:
		if raw_effect is Dictionary:
			effects.append((raw_effect as Dictionary).duplicate(true))
	return effects
