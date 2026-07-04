class_name MineAnchorBehavior
extends Node
## Persistent mine anchor behavior that auto-detonates around nearby enemies.

const EXPLOSION_VFX_SCENE: PackedScene = preload("res://Scenes/Game/Survivor/VFX/mine_explosion_vfx.tscn")

@export var explosion_color: Color = Color(1.0, 0.56, 0.18, 1.0)
@export var shake_strength: float = 1.0

var _anchor: Node
var _cooldown_timer: float = 0.0


# Stores the owning anchor instance after instantiation.
func setup(anchor: Node) -> void:
	_anchor = anchor
	_cooldown_timer = 0.0


# Triggers one AoE explosion when enemies enter the mine trigger radius.
func _physics_process(delta: float) -> void:
	if not is_instance_valid(_anchor):
		return
	_cooldown_timer = maxf(0.0, _cooldown_timer - delta)
	if _cooldown_timer > 0.0:
		return
	var enemies: Array = _anchor.call("find_enemies_in_radius", float(_anchor.get("trigger_radius")))
	if enemies.is_empty():
		return
	_explode()
	_cooldown_timer = maxf(0.01, float(_anchor.get("attack_cooldown")))


# Applies eased AoE damage, visual feedback, and optional screen shake.
func _explode() -> void:
	var radius: float = float(_anchor.get("attack_radius"))
	var full_damage_radius: float = float(_anchor.get("full_damage_radius"))
	var min_damage_ratio: float = float(_anchor.get("min_damage_ratio"))
	var base_damage: float = float(_anchor.get("attack_damage"))
	var enemies: Array = _anchor.call("find_enemies_in_radius", radius)
	for item in enemies:
		var enemy: Node2D = item as Node2D
		if enemy == null or not enemy.has_method("take_damage"):
			continue
		var distance: float = enemy.global_position.distance_to(_anchor.global_position)
		var ratio: float = _compute_damage_ratio(distance, radius, full_damage_radius, min_damage_ratio)
		enemy.call("take_damage", base_damage * ratio)
	_spawn_feedback(radius)


# Calculates the explosion falloff from center to edge.
func _compute_damage_ratio(distance: float, radius: float, full_damage_radius: float, min_damage_ratio: float) -> float:
	if distance <= full_damage_radius:
		return 1.0
	if radius <= full_damage_radius:
		return min_damage_ratio
	var t: float = clampf((distance - full_damage_radius) / (radius - full_damage_radius), 0.0, 1.0)
	var eased: float = t * t * (3.0 - 2.0 * t)
	return lerpf(1.0, min_damage_ratio, eased)


# Spawns particles and asks the scene root to shake the camera.
func _spawn_feedback(radius: float) -> void:
	var scene_root: Node = get_tree().current_scene
	if scene_root == null:
		return
	var vfx: Node2D = EXPLOSION_VFX_SCENE.instantiate() as Node2D
	scene_root.add_child(vfx)
	vfx.global_position = _anchor.global_position
	vfx.call("setup", radius, explosion_color)
	if scene_root.has_method("apply_screen_shake"):
		scene_root.call("apply_screen_shake", shake_strength, 0.18)
