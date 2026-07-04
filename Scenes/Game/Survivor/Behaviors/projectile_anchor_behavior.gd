class_name ProjectileAnchorBehavior
extends Node
## Projectile-based anchor behavior shared by single-shot and multi-shot anchors.

const BULLET_SCENE: PackedScene = preload("res://Scenes/Game/Survivor/magic_bullet.tscn")

@export var shot_count: int = 1
@export var spread_offset: float = 16.0
@export var projectile_color: Color = Color(0.66, 0.88, 1.0, 1.0)

var _anchor: Node
var _fire_timer: float = 0.0


# Stores the owning anchor instance after the child scene is instantiated.
func setup(anchor: Node) -> void:
	_anchor = anchor
	_fire_timer = 0.0


# Fires projectiles at the nearest enemy whenever the anchor cooldown is ready.
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


# Spawns the configured number of projectiles from the owner anchor.
func _fire_at(target: Node2D) -> void:
	var parent: Node = _resolve_projectile_parent()
	if parent == null:
		return
	var damage: float = float(_anchor.get("attack_damage"))
	for i in range(maxi(1, shot_count)):
		var bullet: Area2D = BULLET_SCENE.instantiate() as Area2D
		parent.add_child(bullet)
		var centered_index: float = float(i) - float(shot_count - 1) * 0.5
		var offset: Vector2 = Vector2(0.0, centered_index * spread_offset)
		var direction: Vector2 = _anchor.global_position.direction_to(target.global_position + offset)
		bullet.call("setup", _anchor.global_position + offset, direction, damage, projectile_color, _anchor)


# Prefers the shared projectile container so spawned bullets do not pollute the anchor list.
func _resolve_projectile_parent() -> Node:
	if _anchor == null or _anchor.get_tree() == null:
		return null
	var scene_root: Node = _anchor.get_tree().current_scene
	if scene_root != null:
		var projectile_root: Node = scene_root.get_node_or_null("World/Projectiles")
		if projectile_root != null:
			return projectile_root
	return _anchor.get_parent()
