class_name SurvivorPlayer
extends CharacterBody2D
## 生存模式玩家控制器，负责移动、冲刺、自动攻击和升级数据。

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
@export var base_attack_cooldown: float = 0.25
@export var attack_range: float = 230.0
@export var base_max_stamina: float = 100.0
@export var stamina_per_growth_level: float = 10.0
@export var stamina_drain_per_second: float = 12.0
@export var stamina_recovery_per_second: float = 12.0
@export var sprint_speed_multiplier: float = 1.3
@export var damage_invulnerability_duration: float = 0.5

@onready var visual_root: Node2D = $Visuals
@onready var magic_pivot: Node2D = $GunPivot
@onready var muzzle: Marker2D = $GunPivot/Muzzle
@onready var attack_range_area: Area2D = $AttackRangeArea
@onready var attack_range_shape: CollisionShape2D = $AttackRangeArea/CollisionShape2D
@onready var attack_range_indicator: Node2D = $AttackRangeIndicator
@onready var sprint_bar: ProgressBar = $SprintBar

const MAX_LEVEL: int = 15

var current_hp: int = 100
var max_stamina: float = 100.0
var current_stamina: float = 100.0
var level: int = 1
var total_exp: int = 0
var current_exp: int = 0
var pending_level_ups: int = 0
var selected_skill_ids: Array[int] = []

var _is_alive: bool = true
var _is_sprinting: bool = false
var _attack_timer: float = 0.0
var _attack_multiplier: float = 1.0
var _attack_cooldown_multiplier: float = 1.0
var _splash_percent: float = 0.0
var _splash_radius: float = 0.0
var _pierce_enabled: bool = false
var _pierce_falloff: float = 0.0
var _damage_cooldown_timer: float = 0.0
var _attack_range_targets: Dictionary = {}


# 初始化玩家状态，并推送第一帧 HUD 数据。
func _ready() -> void:
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	current_hp = max_hp
	max_stamina = base_max_stamina
	current_stamina = max_stamina
	_apply_attack_range_shape()
	if attack_range_area != null:
		attack_range_area.body_entered.connect(_on_attack_range_body_entered)
		attack_range_area.body_exited.connect(_on_attack_range_body_exited)
	if attack_range_indicator != null:
		attack_range_indicator.call("set_radius", attack_range)
		attack_range_indicator.call("set_active", false)
	health_changed.emit(current_hp, max_hp)
	_emit_stamina_changed()
	_refresh_sprint_bar()
	_sync_exp_alias()
	exp_changed.emit(total_exp, get_required_exp_for_next_level(), level)


# 驱动移动、冲刺和自动攻击。
func _physics_process(delta: float) -> void:
	_damage_cooldown_timer = maxf(0.0, _damage_cooldown_timer - delta)
	_prune_attack_range_targets()
	if not _is_alive:
		_refresh_attack_range_indicator()
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
	_refresh_attack_range_indicator()


# 应用存档血量，并防止非法残血把本局锁死。
func apply_saved_health(saved_hp: int, saved_max_hp: int) -> void:
	max_hp = maxi(1, saved_max_hp)
	current_hp = clampi(saved_hp, 1, max_hp)
	_is_alive = current_hp > 0
	health_changed.emit(current_hp, max_hp)


# 应用局外体力成长。
func apply_growth_modifiers(stamina_level: int) -> void:
	max_stamina = maxf(1.0, base_max_stamina + float(maxi(0, stamina_level)) * stamina_per_growth_level)
	current_stamina = max_stamina
	_emit_stamina_changed()
	_refresh_sprint_bar()


# 应用本局升级卡牌带来的运行时修正。
func apply_run_skill_modifiers(modifiers: Dictionary) -> void:
	_attack_multiplier = float(modifiers.get("player_attack_multiplier", modifiers.get("attack_multiplier", 1.0)))
	_attack_cooldown_multiplier = float(modifiers.get("player_attack_cooldown_multiplier", 1.0))
	_splash_percent = float(modifiers.get("player_splash_percent", modifiers.get("splash_percent", 0.0)))
	_splash_radius = float(modifiers.get("player_splash_radius", modifiers.get("splash_radius", 0.0)))
	_pierce_enabled = bool(modifiers.get("player_pierce_enabled", false))
	_pierce_falloff = float(modifiers.get("player_pierce_falloff", 0.0))


# 增加累计经验，并在有待选升级时发出信号。
func add_exp(amount: int) -> void:
	if amount <= 0:
		return
	var old_pending: int = pending_level_ups
	total_exp += amount
	_sync_exp_alias()
	_sync_pending_level_ups()
	exp_changed.emit(total_exp, get_required_exp_for_next_level(), level)
	if pending_level_ups > old_pending:
		level_ready.emit()


# 消耗一次待选升级，并把所选技能记入本局状态。
func level_up_with_skill(skill_id: int) -> void:
	if pending_level_ups <= 0 or level >= MAX_LEVEL:
		return
	level = mini(MAX_LEVEL, level + 1)
	if skill_id > 0:
		selected_skill_ids.append(skill_id)
	_sync_pending_level_ups()
	_sync_exp_alias()
	var modifiers: Dictionary = SkillDb.build_run_modifiers(selected_skill_ids)
	apply_run_skill_modifiers(modifiers)
	exp_changed.emit(total_exp, get_required_exp_for_next_level(), level)
	if pending_level_ups > 0:
		level_ready.emit()


# 返回从当前等级升到下一等级所需经验。
func get_required_exp_for_level(current_level: int) -> int:
	return 5 * current_level * current_level + 15 * current_level + 30


# 返回经验条当前应该显示的累计区间。
func get_level_interval_bounds() -> Dictionary:
	var min_exp: int = _get_cumulative_exp_to_reach_level(level)
	var max_exp: int = min_exp if level >= MAX_LEVEL else _get_cumulative_exp_to_reach_level(level + 1)
	return {
		"min_exp": min_exp,
		"max_exp": max_exp,
		"is_max_level": level >= MAX_LEVEL,
	}


# 返回下一次升级对应的累计经验阈值。
func get_required_exp_for_next_level() -> int:
	return int(get_level_interval_bounds().get("max_exp", 0))


# 承受伤害，并维持玩家受击冷却。
func take_damage(amount: int) -> void:
	if amount <= 0 or not _is_alive or _damage_cooldown_timer > 0.0:
		return
	_damage_cooldown_timer = damage_invulnerability_duration
	current_hp = maxi(0, current_hp - amount)
	health_changed.emit(current_hp, max_hp)
	var game_audio: Node = get_tree().root.get_node_or_null("GameAudio")
	if game_audio != null:
		game_audio.call("play_player_hit")
	var scene_root: Node = get_tree().current_scene
	if scene_root != null and scene_root.has_method("apply_screen_shake"):
		scene_root.call("apply_screen_shake", 0.22, 0.12)
	if current_hp == 0:
		_die()


# 恢复生命，供后续道具或升级使用。
func heal(amount: int) -> void:
	if amount <= 0 or not _is_alive:
		return
	current_hp = mini(max_hp, current_hp + amount)
	health_changed.emit(current_hp, max_hp)


# 根据冲刺输入消耗或恢复体力。
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
	_refresh_sprint_bar()


# 对外广播当前体力数值和比例。
func _emit_stamina_changed() -> void:
	var ratio: float = current_stamina / max_stamina if max_stamina > 0.0 else 0.0
	stamina_changed.emit(current_stamina, max_stamina, clampf(ratio, 0.0, 1.0), _is_sprinting)


# 只根据水平移动翻面，保留原本的竖直表现。
func _update_facing(input_dir: Vector2) -> void:
	if input_dir.x > 0.05:
		visual_root.scale.x = 1.0
	elif input_dir.x < -0.05:
		visual_root.scale.x = -1.0


# 让法杖朝向最近敌人，没有敌人时朝向鼠标。
func _update_magic_pivot() -> void:
	var target: Node2D = _find_nearest_enemy()
	var aim_point: Vector2 = target.global_position if target != null else get_global_mouse_position()
	var to_target: Vector2 = aim_point - magic_pivot.global_position
	if to_target.length_squared() > 1.0:
		magic_pivot.rotation = to_target.angle()


# 按攻击冷却向范围内最近敌人发射魔弹。
func _update_auto_attack(delta: float) -> void:
	_attack_timer = maxf(0.0, _attack_timer - delta)
	if _attack_timer > 0.0:
		return
	var target: Node2D = _find_nearest_enemy()
	if target == null:
		return
	_attack_timer = maxf(0.01, base_attack_cooldown * _attack_cooldown_multiplier)
	var bullet: Area2D = BULLET_SCENE.instantiate() as Area2D
	var projectile_parent: Node = _get_projectile_parent()
	if projectile_parent == null:
		projectile_parent = get_parent()
	projectile_parent.add_child(bullet)
	var damage: int = maxi(1, int(round(float(base_attack_damage) * _attack_multiplier)))
	var direction: Vector2 = muzzle.global_position.direction_to(target.global_position)
	bullet.call(
		"setup",
		muzzle.global_position,
		direction,
		damage,
		Color(0.92, 0.48, 1.0, 1.0),
		self,
		_splash_percent,
		_splash_radius,
		{
			"pierce_enabled": _pierce_enabled,
			"pierce_falloff": _pierce_falloff,
		}
	)
	var game_audio: Node = get_tree().root.get_node_or_null("GameAudio")
	if game_audio != null:
		game_audio.call("play_player_attack")


# 查找玩家攻击范围内最近的敌人。
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


# 优先把子弹挂到统一的世界投射物节点下。
func _get_projectile_parent() -> Node:
	if get_tree() == null:
		return null
	var scene_root: Node = get_tree().current_scene
	if scene_root != null:
		var projectile_root: Node = scene_root.get_node_or_null("World/Projectiles")
		if projectile_root != null:
			return projectile_root
	return get_parent()


# 玩家死亡后停止冲刺并通知外部。
func _die() -> void:
	_is_alive = false
	_is_sprinting = false
	if attack_range_indicator != null:
		attack_range_indicator.call("set_active", false)
	_emit_stamina_changed()
	_refresh_sprint_bar()
	died.emit()


# 把累计经验同步回兼容字段，避免旧调用方崩掉。
func _sync_exp_alias() -> void:
	current_exp = total_exp


# 根据累计经验重新计算待选升级次数。
func _sync_pending_level_ups() -> void:
	var unlocked_level: int = 1
	while unlocked_level < MAX_LEVEL and total_exp >= _get_cumulative_exp_to_reach_level(unlocked_level + 1):
		unlocked_level += 1
	pending_level_ups = maxi(0, unlocked_level - level)


# 计算到目标等级为止的累计经验阈值。
func _get_cumulative_exp_to_reach_level(target_level: int) -> int:
	if target_level <= 1:
		return 0
	var total: int = 0
	for current_level in range(1, target_level):
		total += get_required_exp_for_level(current_level)
	return total


# 刷新玩家头顶冲刺条，只有冲刺中或体力未回满时显示。
func _refresh_sprint_bar() -> void:
	if sprint_bar == null:
		return
	var ratio: float = current_stamina / max_stamina if max_stamina > 0.0 else 0.0
	sprint_bar.max_value = 1.0
	sprint_bar.value = clampf(ratio, 0.0, 1.0)
	sprint_bar.visible = _is_sprinting or current_stamina < max_stamina - 0.01


# 让玩家的探测范围和实际攻击半径保持一致。
func _apply_attack_range_shape() -> void:
	if attack_range_shape == null:
		return
	var circle: CircleShape2D = attack_range_shape.shape as CircleShape2D
	if circle == null:
		circle = CircleShape2D.new()
	else:
		circle = circle.duplicate() as CircleShape2D
	circle.radius = attack_range
	attack_range_shape.shape = circle


# 记录进入玩家攻击范围的敌人，供范围圈显隐使用。
func _on_attack_range_body_entered(body: Node) -> void:
	if not _is_enemy_range_target(body):
		return
	_attack_range_targets[int(body.get_instance_id())] = body
	_refresh_attack_range_indicator()


# 在敌人离开攻击范围时移除对应记录。
func _on_attack_range_body_exited(body: Node) -> void:
	if body == null:
		return
	_attack_range_targets.erase(int(body.get_instance_id()))
	_refresh_attack_range_indicator()


# 清掉已经死亡或已释放的敌人引用，避免范围圈卡住不消失。
func _prune_attack_range_targets() -> void:
	if _attack_range_targets.is_empty():
		return
	for target_id in _attack_range_targets.keys():
		var target: Node = _attack_range_targets.get(target_id) as Node
		if not is_instance_valid(target) or target.is_queued_for_deletion():
			_attack_range_targets.erase(target_id)


# 根据范围内是否仍有敌人刷新玩家范围圈。
func _refresh_attack_range_indicator() -> void:
	if attack_range_indicator == null:
		return
	attack_range_indicator.call("set_active", _is_alive and not _attack_range_targets.is_empty())


# 判断一个进入探测区的物体是不是敌人。
func _is_enemy_range_target(body: Node) -> bool:
	return body != null and body.is_in_group("enemies")
