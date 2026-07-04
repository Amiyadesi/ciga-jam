class_name MushroomAnchorBehavior
extends Node
## Explodes around the nearest enemy to apply area damage on a cooldown.

const EXPLOSION_VFX_SCENE: PackedScene = preload("res://Scenes/Game/Survivor/VFX/mine_explosion_vfx.tscn")

var _anchor: Node
var _cooldown_timer: float = 0.0
var _blast_radius: float = 80.0
var _explosion_color: Color = Color(1.0, 0.78, 0.48, 1.0)
var _shake_strength: float = 0.55


# Caches the owner anchor and static effect parameters.
func setup(anchor: Node) -> void:
	_anchor = anchor
	var params: Dictionary = anchor.get("behavior_params") as Dictionary
	_blast_radius = maxf(1.0, float(params.get("blast_radius", 80.0)))
	_explosion_color = params.get("explosion_color", Color(1.0, 0.78, 0.48, 1.0)) as Color
	_shake_strength = float(params.get("shake_strength", 0.55))
	_cooldown_timer = 0.0


# Looks for a target and detonates around it once the anchor cooldown expires.
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


# Damages every enemy inside the configured blast radius and spawns feedback.
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


# Reuses the explosion VFX for area hits and optional screen shake.
func _spawn_feedback(center: Vector2) -> void:
	var scene_root: Node = get_tree().current_scene
	if scene_root == null:
		return
	var vfx: Node2D = EXPLOSION_VFX_SCENE.instantiate() as Node2D
	scene_root.add_child(vfx)
	vfx.global_position = center
	vfx.call("setup", _blast_radius, _explosion_color)
	if scene_root.has_method("apply_screen_shake"):
		scene_root.call("apply_screen_shake", _shake_strength, 0.14)
