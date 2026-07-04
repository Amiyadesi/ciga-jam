class_name SurvivorPlayer
extends CharacterBody2D
## Player controller and automatic magic attack for the CIGA survivor slice.

signal health_changed(current_hp: int, max_hp: int)
signal died
signal stamina_changed(current: float, max_value: float, ratio: float, is_sprinting: bool)
signal exp_changed(current_exp: int, required_exp: int, level: int)
signal level_ready

const BULLET_SCENE: PackedScene = preload("res://Scenes/Game/Survivor/magic_bullet.tscn")
const SkillDb = preload("res://Scenes/Game/Survivor/skill_database.gd")

@export var move_speed: float = 310.0
@export var acceleration: float = 1800.0
@export var friction: float = 2200.0
@export var max_hp: int = 100
@export var base_attack_damage: int = 15
@export var base_attack_speed: float = 5.0
@export var attack_range: float = 200.0
@export var base_max_stamina: float = 100.0
@export var stamina_per_growth_level: float = 10.0
@export var stamina_drain_per_second: float = 12.0
@export var stamina_recovery_per_second: float = 12.0
@export var sprint_speed_multiplier: float = 1.3
@export var damage_invulnerability_duration: float = 0.5

@onready var visual_root: Node2D = $Visuals
@onready var magic_pivot: Node2D = $GunPivot
@onready var muzzle: Marker2D = $GunPivot/Muzzle

var current_hp: int = 100
var max_stamina: float = 100.0
var current_stamina: float = 100.0
var level: int = 1
var current_exp: int = 0
var selected_skill_ids: Array[int] = []

var _is_alive: bool = true
var _is_sprinting: bool = false
var _attack_timer: float = 0.0
var _attack_multiplier: float = 1.0
var _attack_speed_multiplier: float = 1.0
var _splash_percent: float = 0.0
var _splash_radius: float = 0.0
var _damage_cooldown_timer: float = 0.0


# Initializes movement state and publishes starting HUD values.
func _ready() -> void:
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	current_hp = max_hp
	max_stamina = base_max_stamina
	current_stamina = max_stamina
	health_changed.emit(current_hp, max_hp)
	_emit_stamina_changed()
	exp_changed.emit(current_exp, get_required_exp_for_next_level(), level)


# Moves the player and runs automatic combat.
func _physics_process(delta: float) -> void:
	_damage_cooldown_timer = maxf(0.0, _damage_cooldown_timer - delta)
	if not _is_alive:
		velocity = velocity.move_toward(Vector2.ZERO, friction * delta)
		move_and_slide()
		return
	var input_dir: Vector2 = Input.get_vector("left", "right", "up", "down")
	_update_sprint_state(delta, input_dir)
	var current_speed: float = move_speed * (sprint_speed_multiplier if _is_sprinting else 1.0)
	var target_velocity: Vector2 = input_dir * current_speed
	if input_dir != Vector2.ZERO:
		velocity = velocity.move_toward(target_velocity, acceleration * delta)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, friction * delta)
	move_and_slide()
	_update_facing(input_dir)
	_update_magic_pivot()
	_update_auto_attack(delta)


# Applies saved health values without trusting invalid persisted HP.
func apply_saved_health(saved_hp: int, saved_max_hp: int) -> void:
	max_hp = maxi(1, saved_max_hp)
	current_hp = clampi(saved_hp, 1, max_hp)
	_is_alive = current_hp > 0
	health_changed.emit(current_hp, max_hp)


# Applies permanent out-of-run stamina growth.
func apply_growth_modifiers(stamina_level: int) -> void:
	max_stamina = maxf(1.0, base_max_stamina + float(maxi(0, stamina_level)) * stamina_per_growth_level)
	current_stamina = max_stamina
	_emit_stamina_changed()


# Applies current in-run skill modifiers after a level-up selection.
func apply_run_skill_modifiers(modifiers: Dictionary) -> void:
	_attack_multiplier = float(modifiers.get("attack_multiplier", 1.0))
	_attack_speed_multiplier = float(modifiers.get("attack_speed_multiplier", 1.0))
	_splash_percent = float(modifiers.get("splash_percent", 0.0))
	_splash_radius = float(modifiers.get("splash_radius", 0.0))


# Adds EXP and emits level-ready when the threshold is reached.
func add_exp(amount: int) -> void:
	if amount <= 0:
		return
	current_exp += amount
	exp_changed.emit(current_exp, get_required_exp_for_next_level(), level)
	if current_exp >= get_required_exp_for_next_level():
		level_ready.emit()


# Consumes the current level threshold and increments player level.
func level_up_with_skill(skill_id: int) -> void:
	var required: int = get_required_exp_for_next_level()
	if current_exp < required:
		return
	current_exp -= required
	level += 1
	selected_skill_ids.append(skill_id)
	var modifiers: Dictionary = SkillDb.build_player_modifiers(selected_skill_ids)
	apply_run_skill_modifiers(modifiers)
	exp_changed.emit(current_exp, get_required_exp_for_next_level(), level)


# Returns document formula result for the next player level.
func get_required_exp_for_next_level() -> int:
	return 5 * level * level + 15 * level + 30


# Reduces HP and emits death once.
func take_damage(amount: int) -> void:
	if amount <= 0 or not _is_alive or _damage_cooldown_timer > 0.0:
		return
	_damage_cooldown_timer = damage_invulnerability_duration
	current_hp = maxi(0, current_hp - amount)
	health_changed.emit(current_hp, max_hp)
	if current_hp == 0:
		_die()


# Restores HP for later pickups or upgrades.
func heal(amount: int) -> void:
	if amount <= 0 or not _is_alive:
		return
	current_hp = mini(max_hp, current_hp + amount)
	health_changed.emit(current_hp, max_hp)


# Drains or restores stamina depending on sprint intent and movement state.
func _update_sprint_state(delta: float, input_dir: Vector2) -> void:
	var wants_sprint: bool = Input.is_action_pressed("sprint") and input_dir != Vector2.ZERO
	var can_sprint: bool = current_stamina > 0.0
	_is_sprinting = wants_sprint and can_sprint
	if _is_sprinting:
		current_stamina = maxf(0.0, current_stamina - stamina_drain_per_second * delta)
		if is_zero_approx(current_stamina):
			_is_sprinting = false
	else:
		current_stamina = minf(max_stamina, current_stamina + stamina_recovery_per_second * delta)
	_emit_stamina_changed()


# Publishes stamina values in both absolute and normalized form for HUDs.
func _emit_stamina_changed() -> void:
	var ratio: float = current_stamina / max_stamina if max_stamina > 0.0 else 0.0
	stamina_changed.emit(current_stamina, max_stamina, clampf(ratio, 0.0, 1.0), _is_sprinting)


# Flips the placeholder body toward horizontal movement while preserving vertical-facing behavior.
func _update_facing(input_dir: Vector2) -> void:
	if input_dir.x > 0.05:
		visual_root.scale.x = 1.0
	elif input_dir.x < -0.05:
		visual_root.scale.x = -1.0


# Points the placeholder magic circle toward the current target or mouse fallback.
func _update_magic_pivot() -> void:
	var target: Node2D = _find_nearest_enemy()
	var aim_point: Vector2 = target.global_position if target != null else get_global_mouse_position()
	var to_target: Vector2 = aim_point - magic_pivot.global_position
	if to_target.length_squared() > 1.0:
		magic_pivot.rotation = to_target.angle()


# Fires magic bullets at the closest enemy in range based on attack speed.
func _update_auto_attack(delta: float) -> void:
	_attack_timer = maxf(0.0, _attack_timer - delta)
	if _attack_timer > 0.0:
		return
	var target: Node2D = _find_nearest_enemy()
	if target == null:
		return
	_attack_timer = 1.0 / maxf(0.1, base_attack_speed * _attack_speed_multiplier)
	var bullet: Area2D = BULLET_SCENE.instantiate() as Area2D
	get_parent().add_child(bullet)
	var damage: int = maxi(1, int(round(float(base_attack_damage) * _attack_multiplier)))
	var direction: Vector2 = muzzle.global_position.direction_to(target.global_position)
	bullet.call("setup", muzzle.global_position, direction, damage, Color(0.92, 0.48, 1.0, 1.0), self, _splash_percent, _splash_radius)


# Finds the nearest enemy inside player attack radius.
func _find_nearest_enemy() -> Node2D:
	var best: Node2D = null
	var best_distance_sq: float = INF
	for node in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(node) or not (node is Node2D):
			continue
		var enemy: Node2D = node as Node2D
		var dist_sq: float = global_position.distance_squared_to(enemy.global_position)
		if dist_sq <= attack_range * attack_range and dist_sq < best_distance_sq:
			best = enemy
			best_distance_sq = dist_sq
	return best


# Stops input and notifies the game root that combat ended.
func _die() -> void:
	_is_alive = false
	_is_sprinting = false
	_emit_stamina_changed()
	died.emit()
