class_name MushroomAnchorBehavior
extends Node
## 蘑菇塔行为脚本，按冷却在最近敌人处生成范围爆炸。

const EXPLOSION_VFX_SCENE: PackedScene = preload("res://Scenes/Game/Survivor/VFX/mine_explosion_vfx.tscn")

var _anchor: Node
var _cooldown_timer: float = 0.0
var _blast_radius: float = 80.0
var _full_damage_radius: float = 36.0
var _explosion_color: Color = Color(1.0, 0.78, 0.48, 1.0)
var _shake_strength: float = 0.55


# 缓存所属锚点与当前等级对应的爆炸参数。
func setup(anchor: Node) -> void:
	_anchor = anchor
	var params: Dictionary = anchor.get("behavior_params") as Dictionary
	_blast_radius = maxf(1.0, float(params.get("blast_radius", 80.0)))
	_full_damage_radius = minf(_blast_radius, maxf(18.0, float(anchor.get("full_damage_radius"))))
	_explosion_color = params.get("explosion_color", Color(1.0, 0.78, 0.48, 1.0)) as Color
	_shake_strength = float(params.get("shake_strength", 0.55))
	_cooldown_timer = 0.0


# 冷却结束后寻找最近敌人，并在其位置触发一次爆炸。
func _physics_process(delta: float) -> void:
	if not is_instance_valid(_anchor):
		return
	_cooldown_timer = maxf(0.0, _cooldown_timer - delta)
	if _cooldown_timer > 0.0:
		return
	var target: Node2D = _anchor.call("find_nearest_enemy") as Node2D
	if target == null:
		return
	_cooldown_timer = maxf(0.01, float(_anchor.get("attack_cooldown")))
	_explode_at(target.global_position)


# 对爆炸半径内的敌人结算伤害，并补上命中特效。
func _explode_at(center: Vector2) -> void:
	var damage: float = float(_anchor.get("attack_damage"))
	for item in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(item) or not (item is Node2D):
			continue
		var enemy: Node2D = item as Node2D
		if enemy.global_position.distance_to(center) > _blast_radius:
			continue
		if enemy.has_method("take_damage"):
			enemy.call("take_damage", damage)
			if _anchor.has_method("apply_on_hit_effects"):
				_anchor.call("apply_on_hit_effects", enemy)
	_spawn_feedback(center)


# 复用地雷的爆炸表现，并补一次可配置的屏幕震动。
func _spawn_feedback(center: Vector2) -> void:
	var scene_root: Node = get_tree().current_scene
	if scene_root == null:
		return
	var vfx: Node2D = EXPLOSION_VFX_SCENE.instantiate() as Node2D
	scene_root.add_child(vfx)
	vfx.global_position = center
	vfx.call("setup", _blast_radius, _full_damage_radius, _explosion_color)
	if scene_root.has_method("apply_screen_shake"):
		scene_root.call("apply_screen_shake", _shake_strength, 0.14)
