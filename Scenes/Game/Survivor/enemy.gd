class_name SurvivorEnemy
extends CharacterBody2D
## CIGA enemy that prioritizes house, player, and anchors.

signal died(enemy: Node, gold_reward: int, exp_reward: int)

const FLOATING_TEXT_SCENE: PackedScene = preload("res://Scenes/UIorgan/floating_text.tscn")

@export var gold_reward: int = 1
@export var exp_reward: int = 12
@export var player_chase_radius: float = 150.0
@export var house_priority_radius: float = 300.0
@export var anchor_chase_radius: float = 200.0
@export var attack_range: float = 36.0
@export var structure_attack_padding: float = 95.0
@export var hit_stop_duration: float = 0.05
@export var post_hit_slow_duration: float = 0.1
@export var post_hit_slow_multiplier: float = 0.7

@onready var visual: Polygon2D = $Visual
@onready var attack_area: Area2D = $AttackArea
@onready var animation_player: AnimationPlayer = $AnimationPlayer

var max_hp: int = 100
var attack_damage: int = 5
var speed: float = 130.0
var attack_cooldown: float = 1.0

var _hp: int = 100
var _attack_timer: float = 0.0
var _slow_multiplier: float = 1.0
var _slow_timer: float = 0.0
var _hit_stop_timer: float = 0.0
var _house: Node2D
var _player: Node2D
var _anchor_provider: Callable
var _is_alive: bool = true


# Registers enemy group membership.
func _ready() -> void:
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	add_to_group("enemies")
	_hp = max_hp


# Assigns stats and target references after spawning.
func setup(enemy_type: String, enemy_level: int, house: Node2D, player: Node2D, anchors_provider: Callable = Callable()) -> void:
	_house = house
	_player = player
	_anchor_provider = anchors_provider
	var level_value: int = maxi(1, enemy_level)
	if enemy_type == "bat":
		max_hp = 25 * level_value + 40
		attack_damage = 3 * level_value + 5
		speed = 190.0 + float(level_value) * 9.0
		attack_cooldown = 0.6
		exp_reward = 16 + level_value * 2
		gold_reward = 2
		visual.color = Color(0.35, 0.24, 0.68, 1.0)
	else:
		max_hp = 30 * level_value + 70
		attack_damage = 2 * level_value + 3
		speed = 132.0 + float(level_value) * 7.0
		attack_cooldown = 1.0
		exp_reward = 12 + level_value * 2
		gold_reward = 1
		visual.color = Color(0.20, 0.68, 0.36, 1.0)
	_hp = max_hp


# Moves toward current highest-priority target and attacks on cooldown.
func _physics_process(delta: float) -> void:
	if not _is_alive:
		return
	_attack_timer = maxf(0.0, _attack_timer - delta)
	_update_status(delta)
	if _hit_stop_timer > 0.0:
		velocity = Vector2.ZERO
		move_and_slide()
		return
	var target: Node2D = _pick_target()
	if is_instance_valid(target):
		var direction: Vector2 = global_position.direction_to(target.global_position)
		velocity = direction * speed * _slow_multiplier
		if direction.x > 0.05:
			visual.scale.x = 1.0
		elif direction.x < -0.05:
			visual.scale.x = -1.0
		if global_position.distance_to(target.global_position) <= _get_attack_reach_for(target):
			_try_attack(target)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, speed * delta)
	move_and_slide()


# Reduces HP and kills the enemy at zero.
func take_damage(amount: float) -> void:
	if amount <= 0.0 or _hp <= 0:
		return
	_spawn_damage_text(amount)
	_hp = maxi(0, int(round(float(_hp) - amount)))
	apply_hit_stop()
	apply_slow(post_hit_slow_multiplier, post_hit_slow_duration)
	_flash_damage()
	if _hp == 0:
		_die()


# Applies short hit-stop feedback.
func apply_hit_stop() -> void:
	_hit_stop_timer = maxf(_hit_stop_timer, hit_stop_duration)


# Temporarily multiplies movement speed for status effects.
func apply_slow(multiplier: float, duration: float) -> void:
	_slow_multiplier = minf(_slow_multiplier, clampf(multiplier, 0.05, 1.0))
	_slow_timer = maxf(_slow_timer, duration)


# Chooses the highest-priority target currently relevant to this enemy.
func _pick_target() -> Node2D:
	if is_instance_valid(_house) and global_position.distance_to(_house.global_position) <= house_priority_radius:
		return _house
	if is_instance_valid(_player) and global_position.distance_to(_player.global_position) <= player_chase_radius:
		return _player
	var anchor: Node2D = _nearest_anchor_in_radius(anchor_chase_radius)
	if anchor != null:
		return anchor
	return _house if is_instance_valid(_house) else _player


# Returns closest placed anchor within the attraction radius.
func _nearest_anchor_in_radius(radius: float) -> Node2D:
	var anchors: Array = []
	if _anchor_provider.is_valid():
		var provided: Variant = _anchor_provider.call()
		if provided is Array:
			anchors = provided as Array
	else:
		anchors = get_tree().get_nodes_in_group("anchors")
	var best: Node2D = null
	var best_distance_sq: float = radius * radius
	for item in anchors:
		if not is_instance_valid(item) or not (item is Node2D):
			continue
		var anchor: Node2D = item as Node2D
		if anchor.has_method("is_targetable") and not bool(anchor.call("is_targetable")):
			continue
		var dist_sq: float = global_position.distance_squared_to(anchor.global_position)
		if dist_sq <= best_distance_sq:
			best = anchor
			best_distance_sq = dist_sq
	return best


# Damages the current target if the enemy attack cooldown is ready.
func _try_attack(target: Node2D) -> void:
	if _attack_timer > 0.0 or not target.has_method("take_damage"):
		return
	target.call("take_damage", attack_damage)
	_attack_timer = attack_cooldown


# Expands melee reach for large static targets whose centers sit behind collision shapes.
func _get_attack_reach_for(target: Node2D) -> float:
	if target == _house or target.is_in_group("anchors"):
		return attack_range + structure_attack_padding
	return attack_range


# Restores speed and hit-stop state as timers expire.
func _update_status(delta: float) -> void:
	_hit_stop_timer = maxf(0.0, _hit_stop_timer - delta)
	if _slow_timer <= 0.0:
		_slow_multiplier = 1.0
		return
	_slow_timer = maxf(0.0, _slow_timer - delta)
	if _slow_timer <= 0.0:
		_slow_multiplier = 1.0


# Gives quick white flash feedback for hits.
func _flash_damage() -> void:
	var old_color: Color = visual.color
	visual.color = Color.WHITE
	var tween: Tween = create_tween()
	tween.tween_property(visual, "color", old_color, 0.12)


# Spawns a floating damage label near the enemy for any incoming hit.
func _spawn_damage_text(amount: float) -> void:
	var scene_root: Node = get_tree().current_scene
	if scene_root == null:
		return
	var floating_text: Node2D = FLOATING_TEXT_SCENE.instantiate() as Node2D
	scene_root.add_child(floating_text)
	floating_text.global_position = global_position + Vector2(0.0, -36.0)
	if floating_text.has_method("start_damage"):
		floating_text.call("start_damage", amount)
	else:
		floating_text.call("start", str(amount))


# Emits rewards and fades out before removing the enemy.
func _die() -> void:
	_is_alive = false
	remove_from_group("enemies")
	died.emit(self, gold_reward, exp_reward)
	var tween: Tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.18)
	tween.finished.connect(queue_free)
