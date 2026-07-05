class_name SurvivorEnemy
extends CharacterBody2D
## 生存模式敌人，负责索敌、攻击、召唤和死亡掉落。

signal died(enemy: Node, gold_reward: int, exp_reward: int)

enum BossState {
	CHASE,
	ATTACK,
	SUMMON,
}

enum AttackState {
	READY,
	WINDUP,
	ACTIVE,
	RECOVERY,
}

enum RouteState {
	ROUTE,
	CHASE,
	RETURN,
}

const FLOATING_TEXT_SCENE: PackedScene = preload("res://Scenes/UIorgan/floating_text.tscn")
const ENEMY_PROJECTILE_SCENE: PackedScene = preload("res://Scenes/Game/Survivor/enemy_projectile.tscn")
const PLAYER_LAYER_MASK: int = 1
const STRUCTURE_LAYER_MASK: int = 4

## 击杀后掉落的金币。
@export var gold_reward: int = 1
## 击杀后掉落的经验。
@export var exp_reward: int = 12
## 玩家进入多近才会优先追击。
@export var player_chase_radius: float = 150.0
## 房子优先级半径。
@export var house_priority_radius: float = 300.0
## 锚点吸引半径。
@export var anchor_chase_radius: float = 200.0
## 常规攻击判定半径。
@export var attack_range: float = 36.0
## 打玩家时额外补的距离，避免角色碰撞体先顶住导致无法进攻击距离。
@export var player_attack_padding: float = 96.0
## 打房子和锚点时额外补的距离。
@export var structure_attack_padding: float = 132.0
## 受击停顿时长。
@export var hit_stop_duration: float = 0.05
## 受击后减速时长。
@export var post_hit_slow_duration: float = 0.1
## 受击后保留的速度倍率。
@export var post_hit_slow_multiplier: float = 0.7
## 冲刺攻击最短时长。
@export var player_dash_duration: float = 0.16
## 冲刺攻击的最小速度。
@export var player_dash_min_speed: float = 260.0
## 冲刺攻击的最大速度。
@export var player_dash_max_speed: float = 620.0
## 近战攻击前摇结束后额外向前冲的距离。
@export var melee_lunge_extra_distance: float = 118.0
## 近战冲刺命中玩家时允许的轻量距离补偿。
@export var player_lunge_hit_padding: float = 58.0
## 重新寻路的最短刷新间隔。
@export var path_refresh_interval: float = 0.18
## 认为已经走到当前路径点的距离阈值。
@export var path_point_reach_distance: float = 18.0
## 认为敌人已经卡住并需要重新寻路的最短时间。
@export var stuck_repath_duration: float = 0.45
## 判定卡住时每帧最小位移。
@export var stuck_min_move_distance: float = 1.0
## 追击玩家或防御塔时认为可直线追击的距离，超出后重新请求避障路径。
@export var direct_chase_distance: float = 420.0
## 近战攻击前摇时长，给玩家留出闪避窗口。
@export var attack_windup_duration: float = 0.22
## 近战攻击真正能命中的时间窗口。
@export var attack_active_duration: float = 0.1
## 近战攻击后摇时长，避免贴脸连续瞬伤。
@export var attack_recovery_duration: float = 0.18
## 卡住后临时绕障的侧向推动强度。
@export var stuck_avoidance_strength: float = 0.46
## 同一路线上的横向错位宽度，用于减少群体重叠。
@export var route_lane_width: float = 54.0
## 敌人之间轻量分离的检测半径。
@export var separation_radius: float = 46.0
## 敌人分离 steering 对移动方向的影响。
@export var separation_strength: float = 0.44
## 防御塔只在贴近攻击距离时吸引仇恨，避免远处敌人离路跑塔。
@export var anchor_aggro_padding: float = 24.0

@onready var visual: Polygon2D = $Visual
@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var attack_area: Area2D = $AttackArea
@onready var boss_health_bar: ProgressBar = $BossHealthBar
@onready var animation_player: AnimationPlayer = $AnimationPlayer

var max_hp: int = 100
var attack_damage: int = 5
var speed: float = 130.0
var attack_cooldown: float = 1.0
var is_ranged: bool = false
var projectile_speed: float = 520.0
var projectile_color: Color = Color(0.74, 0.26, 1.0, 1.0)
var default_animation: StringName = &"idle"

var _hp: int = 100
var _attack_timer: float = 0.0
var _slow_multiplier: float = 1.0
var _slow_timer: float = 0.0
var _hit_stop_timer: float = 0.0
var _house: Node2D
var _player: Node2D
var _anchor_provider: Callable
var _path_provider: Callable
var _return_path_provider: Callable
var _is_alive: bool = true
var _enemy_id: String = "slime_blue"
var _level: int = 1
var _is_boss: bool = false
var _boss_state: BossState = BossState.CHASE
var _summon_enemy_id: String = ""
var _summon_entries: Array[Dictionary] = []
var _summon_count: int = 0
var _summon_interval: float = 6.0
var _summon_ring_radius: float = 120.0
var _summon_timer: float = 0.0
var _summon_callback: Callable
var _attack_dash_timer: float = 0.0
var _attack_dash_speed: float = 0.0
var _attack_dash_destination: Vector2 = Vector2.ZERO
var _pending_player_hit: bool = false
var _attack_state: AttackState = AttackState.READY
var _attack_state_timer: float = 0.0
var _attack_target: Node2D
var _attack_damage_applied: bool = false
var _stuck_avoidance_timer: float = 0.0
var _stuck_avoidance_direction: Vector2 = Vector2.ZERO
var _attack_visual_tween: Tween
var _death_tween: Tween
var _route_state: RouteState = RouteState.ROUTE
var _spawn_index: int = 0
var _route_points: PackedVector2Array = PackedVector2Array()
var _route_index: int = 0
var _route_lateral_offset: float = 0.0
var _return_points: PackedVector2Array = PackedVector2Array()
var _return_index: int = 0
var _nav_refresh_timer: float = 0.0
var _navigation_points: PackedVector2Array = PackedVector2Array()
var _navigation_index: int = 0
var _last_nav_target_position: Vector2 = Vector2(999999.0, 999999.0)
var _last_nav_target_id: int = 0
var _last_physics_position: Vector2 = Vector2.ZERO
var _stuck_timer: float = 0.0
var _base_visual_offset: Vector2 = Vector2.ZERO
var _float_phase: float = 0.0
var _base_visual_color: Color = Color.WHITE


## 初始化敌人自身状态与碰撞监听。
func _ready() -> void:
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	add_to_group("enemies")
	_hp = max_hp
	if visual != null:
		_base_visual_offset = visual.position
		_base_visual_color = visual.color
	elif animated_sprite != null:
		_base_visual_offset = animated_sprite.position
		_base_visual_color = animated_sprite.modulate
	if attack_area != null:
		attack_area.body_entered.connect(_on_attack_area_body_entered)
	_last_physics_position = global_position


## 根据 EnemyData 或兼容字典写入运行时参数。
func setup(enemy_spec: Variant, enemy_level: int, house: Node2D, player: Node2D, anchors_provider: Callable = Callable(), summon_callback: Callable = Callable(), path_provider: Callable = Callable()) -> void:
	_house = house
	_player = player
	_anchor_provider = anchors_provider
	_summon_callback = summon_callback
	_path_provider = path_provider
	_level = maxi(1, enemy_level)
	var runtime: Dictionary = {}
	if enemy_spec is Dictionary:
		runtime = (enemy_spec as Dictionary).duplicate(true)
	elif enemy_spec is Resource and (enemy_spec as Resource).has_method("to_runtime_dictionary"):
		runtime = (enemy_spec as Resource).call("to_runtime_dictionary", _level)
	else:
		runtime = _build_legacy_stats(str(enemy_spec), _level)
	_apply_runtime_stats(runtime)
	_hp = max_hp
	_reset_navigation_state()
	_reset_route_state()
	_reset_attack_state()
	_last_physics_position = global_position
	_stuck_timer = 0.0


## 配置固定进攻路线，默认推房时沿 authored path 前进。
func configure_route(spawn_index: int, route_points: PackedVector2Array, return_path_provider: Callable = Callable()) -> void:
	_spawn_index = spawn_index
	_route_points = route_points
	_return_path_provider = return_path_provider
	_route_index = 0
	_return_points = PackedVector2Array()
	_return_index = 0
	_route_state = RouteState.ROUTE
	_route_lateral_offset = _calculate_route_lateral_offset()
	if _enemy_id == "bat":
		_route_lateral_offset = 0.0
	_advance_route_index_past_spawn()


## 让非出生点生成的敌人从当前位置规划一次接回路线。
func begin_return_to_route() -> void:
	_begin_return_to_route()


## 每个物理帧处理索敌、追击、攻击与召唤。
func _physics_process(delta: float) -> void:
	if not _is_alive:
		return
	_update_float(delta)
	_attack_timer = maxf(0.0, _attack_timer - delta)
	_update_status(delta)
	if _hit_stop_timer > 0.0:
		velocity = Vector2.ZERO
		move_and_slide()
		return
	if _update_attack_state(delta):
		move_and_slide()
		return
	if _is_boss and _summon_callback.is_valid() and _can_summon_pack():
		_summon_timer = maxf(0.0, _summon_timer - delta)
		if _summon_timer <= 0.0:
			velocity = Vector2.ZERO
			_boss_state = BossState.SUMMON
			_perform_summon()
			move_and_slide()
			return
	var target: Node2D = _pick_attack_target()
	if _is_valid_attack_target(target):
		var distance: float = global_position.distance_to(target.global_position)
		if distance <= _get_attack_start_reach_for(target):
			velocity = Vector2.ZERO
			_try_attack(target)
		else:
			_boss_state = BossState.CHASE
			_update_route_state_for_target(target)
			var direction: Vector2 = _get_movement_direction(target, delta)
			if direction == Vector2.ZERO and is_instance_valid(target) and global_position.distance_to(target.global_position) > 6.0:
				direction = global_position.direction_to(target.global_position)
			direction = _apply_stuck_avoidance(direction, delta)
			direction = _apply_separation(direction)
			velocity = direction * speed * _slow_multiplier
			_update_facing(direction)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, speed * delta)
	var was_trying_to_move: bool = velocity.length_squared() > 1.0
	move_and_slide()
	_update_stuck_recovery(was_trying_to_move, target, delta)


## 承受伤害，并触发受击停顿、减速和死亡流程。
func take_damage(amount: float, _source_position: Vector2 = Vector2.INF) -> void:
	if amount <= 0.0 or _hp <= 0:
		return
	_spawn_damage_text(amount)
	_hp = maxi(0, int(round(float(_hp) - amount)))
	_refresh_boss_health_bar()
	apply_hit_stop()
	apply_slow(post_hit_slow_multiplier, post_hit_slow_duration)
	_flash_damage()
	if _hp == 0:
		_die()


## 应用短暂受击停顿。
func apply_hit_stop() -> void:
	_hit_stop_timer = maxf(_hit_stop_timer, hit_stop_duration)


## 应用减速效果，较强效果会覆盖较弱效果。
func apply_slow(multiplier: float, duration: float) -> void:
	_slow_multiplier = minf(_slow_multiplier, clampf(multiplier, 0.05, 1.0))
	_slow_timer = maxf(_slow_timer, duration)


## 按当前威胁选择目标；贴脸玩家和可受伤锚点不能被房子优先级吞掉。
func _pick_attack_target() -> Node2D:
	if _is_valid_attack_target(_player) and global_position.distance_to(_player.global_position) <= _get_attack_start_reach_for(_player):
		return _player
	var immediate_anchor: Node2D = _nearest_anchor_in_radius(_get_anchor_attack_start_radius())
	if immediate_anchor != null:
		return immediate_anchor
	if _is_valid_attack_target(_house) and global_position.distance_to(_house.global_position) <= _get_attack_reach_for(_house):
		return _house
	if _is_valid_attack_target(_player) and global_position.distance_to(_player.global_position) <= _get_player_engage_radius():
		return _player
	var anchor: Node2D = _nearest_anchor_in_radius(_get_anchor_aggro_radius())
	if anchor != null:
		return anchor
	if _is_valid_attack_target(_house) and global_position.distance_to(_house.global_position) <= house_priority_radius:
		return _house
	if _is_valid_attack_target(_house):
		return _house
	return _player if _is_valid_attack_target(_player) else null


## 返回防御塔允许吸引仇恨的近距离半径。
func _get_anchor_aggro_radius() -> float:
	if is_ranged:
		return minf(attack_range, 120.0)
	return minf(anchor_chase_radius, attack_range + structure_attack_padding * 0.7 + anchor_aggro_padding)


## 返回可受伤锚点能触发攻击前摇的距离，只影响开始攻击不直接扣血。
func _get_anchor_attack_start_radius() -> float:
	if is_ranged:
		return attack_range
	return _get_attack_start_reach_for(_house)


## 返回玩家能触发近战追击的半径，补偿放大后的角色体积。
func _get_player_engage_radius() -> float:
	if is_ranged:
		return player_chase_radius
	return maxf(player_chase_radius, attack_range + player_attack_padding + melee_lunge_extra_distance * 0.45)


## 在给定半径内找到最近的可索敌锚点。
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
		if not _is_valid_attack_target(anchor):
			continue
		var dist_sq: float = global_position.distance_squared_to(anchor.global_position)
		if dist_sq <= best_distance_sq:
			best = anchor
			best_distance_sq = dist_sq
	return best


## 在攻击冷却结束后开始一次攻击动作。
func _try_attack(target: Node2D) -> bool:
	if _attack_timer > 0.0 or not _is_valid_attack_target(target) or not target.has_method("take_damage"):
		return false
	_boss_state = BossState.ATTACK if _is_boss else BossState.CHASE
	velocity = Vector2.ZERO
	if is_ranged:
		_fire_projectile(target)
		return true
	_begin_melee_attack(target)
	return true


## 开始一次有前摇和命中帧的近战攻击。
func _begin_melee_attack(target: Node2D) -> void:
	_attack_target = target
	_attack_state = AttackState.WINDUP
	_attack_state_timer = attack_windup_duration
	_attack_damage_applied = false
	_attack_timer = attack_cooldown
	_update_facing(global_position.direction_to(target.global_position))
	_play_attack_feedback()


## 推进近战攻击状态，只在命中帧内尝试结算伤害。
func _update_attack_state(delta: float) -> bool:
	if _attack_state == AttackState.READY:
		return false
	_attack_state_timer = maxf(0.0, _attack_state_timer - delta)
	if _attack_state == AttackState.WINDUP:
		velocity = Vector2.ZERO
		if _attack_state_timer <= 0.0:
			_attack_state = AttackState.ACTIVE
			_attack_state_timer = attack_active_duration
			_start_melee_lunge()
			_try_apply_melee_hit()
		return true
	if _attack_state == AttackState.ACTIVE:
		_update_melee_lunge_motion(delta)
		_try_apply_melee_hit()
		if _attack_state_timer <= 0.0:
			_finish_player_dash()
			_attack_state = AttackState.RECOVERY
			_attack_state_timer = attack_recovery_duration
		return true
	if _attack_state == AttackState.RECOVERY:
		velocity = Vector2.ZERO
		if _attack_state_timer <= 0.0:
			_reset_attack_state()
		return true
	return false


## 命中帧内检查目标是否仍在有效命中区。
func _try_apply_melee_hit() -> void:
	if _attack_damage_applied or not _is_valid_attack_target(_attack_target):
		return
	if not _is_target_in_melee_hit_window(_attack_target):
		return
	_call_take_damage(_attack_target, attack_damage)
	_attack_damage_applied = true


## 判断近战目标是否处在本次攻击命中窗口。
func _is_target_in_melee_hit_window(target: Node2D) -> bool:
	if target == null:
		return false
	if target == _player:
		return _is_player_in_attack_area(target)
	if target == _house or target.is_in_group("anchors"):
		return _does_structure_overlap_melee_sweep(target)
	return global_position.distance_to(target.global_position) <= _get_attack_reach_for(target)


## 玩家近战命中优先使用 AttackArea，避免退回纯距离瞬伤。
func _is_player_in_attack_area(target: Node2D) -> bool:
	if attack_area != null:
		for body in attack_area.get_overlapping_bodies():
			if body == target:
				return true
	if _does_player_overlap_melee_sweep(target):
		return true
	var active_padding: float = player_lunge_hit_padding if _attack_state == AttackState.ACTIVE else maxf(8.0, player_attack_padding * 0.35)
	return global_position.distance_to(target.global_position) <= attack_range + active_padding


## 清空当前近战攻击缓存。
func _reset_attack_state() -> void:
	_attack_state = AttackState.READY
	_attack_state_timer = 0.0
	_attack_target = null
	_attack_damage_applied = false


## 发射一枚远程弹幕。
func _fire_projectile(target: Node2D) -> void:
	_attack_timer = attack_cooldown
	_play_attack_feedback()
	var projectile: Area2D = ENEMY_PROJECTILE_SCENE.instantiate() as Area2D
	var projectile_parent: Node = _get_projectile_parent()
	projectile_parent.add_child(projectile)
	projectile.call("setup", global_position, target, attack_damage, projectile_speed, projectile_color)


## 开始一次朝玩家的短冲刺攻击。
func _begin_player_dash(target: Node2D) -> void:
	_attack_timer = attack_cooldown
	_pending_player_hit = true
	var direction: Vector2 = global_position.direction_to(target.global_position)
	if direction == Vector2.ZERO:
		direction = Vector2.LEFT if animated_sprite != null and animated_sprite.scale.x < 0.0 else Vector2.RIGHT
	var dash_distance: float = minf(global_position.distance_to(target.global_position) + melee_lunge_extra_distance, attack_range + player_attack_padding + melee_lunge_extra_distance)
	_attack_dash_destination = global_position + direction * dash_distance
	_attack_dash_timer = player_dash_duration
	_attack_dash_speed = clampf(dash_distance / maxf(player_dash_duration, 0.01), player_dash_min_speed, player_dash_max_speed)


## 在冲刺期间推动敌人前进，并检测是否真的撞到玩家。
func _update_player_dash_motion(delta: float) -> bool:
	if _attack_dash_timer <= 0.0:
		return false
	_attack_dash_timer = maxf(0.0, _attack_dash_timer - delta)
	var direction: Vector2 = global_position.direction_to(_attack_dash_destination)
	velocity = direction * _attack_dash_speed * _slow_multiplier
	_update_facing(direction)
	_check_player_dash_hit()
	if global_position.distance_to(_attack_dash_destination) <= 8.0 or _attack_dash_timer <= 0.0:
		_finish_player_dash()
	return true


## 命中帧开始时向当前近战目标短冲刺，解决史莱姆站桩够不到玩家的问题。
func _start_melee_lunge() -> void:
	if not _is_valid_attack_target(_attack_target):
		return
	if _attack_target == _player:
		_begin_player_dash(_attack_target)
		return
	var direction: Vector2 = global_position.direction_to(_attack_target.global_position)
	if direction == Vector2.ZERO:
		return
	var dash_distance: float = minf(global_position.distance_to(_attack_target.global_position), attack_range + structure_attack_padding)
	_attack_dash_destination = global_position + direction * dash_distance
	_attack_dash_timer = maxf(attack_active_duration, 0.04)
	_attack_dash_speed = clampf(dash_distance / maxf(_attack_dash_timer, 0.01), player_dash_min_speed, player_dash_max_speed)
	_update_facing(direction)


## 近战 ACTIVE 窗口内推动敌人向前一小段。
func _update_melee_lunge_motion(delta: float) -> void:
	if _attack_dash_timer <= 0.0:
		velocity = Vector2.ZERO
		return
	_attack_dash_timer = maxf(0.0, _attack_dash_timer - delta)
	var direction: Vector2 = global_position.direction_to(_attack_dash_destination)
	if direction == Vector2.ZERO:
		velocity = Vector2.ZERO
		return
	velocity = direction * _attack_dash_speed * _slow_multiplier
	_update_facing(direction)
	_check_player_dash_hit()
	if global_position.distance_to(_attack_dash_destination) <= 8.0:
		_finish_player_dash()


## 检查冲刺攻击期间是否与玩家碰撞重合。
func _check_player_dash_hit() -> void:
	if not _pending_player_hit:
		return
	if attack_area != null:
		for body in attack_area.get_overlapping_bodies():
			_on_attack_area_body_entered(body)
			if not _pending_player_hit:
				return
	if _is_valid_attack_target(_player) and _does_player_overlap_melee_sweep(_player):
		_on_attack_area_body_entered(_player)


## 结束当前冲刺攻击。
func _finish_player_dash() -> void:
	_attack_dash_timer = 0.0
	_pending_player_hit = false
	velocity = Vector2.ZERO


## 根据当前目标切换路线、追击和回路状态。
func _update_route_state_for_target(target: Node2D) -> void:
	if target == _house:
		if _route_state == RouteState.CHASE:
			_begin_return_to_route()
		elif _route_state != RouteState.ROUTE:
			_finish_return_to_route()
		return
	if _route_state != RouteState.CHASE:
		_route_state = RouteState.CHASE
		_reset_navigation_state()


## 根据路线状态返回本帧移动方向。
func _get_movement_direction(target: Node2D, delta: float) -> Vector2:
	if _route_state == RouteState.ROUTE and not _route_points.is_empty():
		return _follow_route_points()
	if _route_state == RouteState.RETURN and not _return_points.is_empty():
		return _follow_return_points()
	return _get_navigation_direction(target, delta)


## 按当前目标刷新一次寻路，并给出本帧应前进的方向。
func _get_navigation_direction(target: Node2D, delta: float) -> Vector2:
	if not is_instance_valid(target):
		return Vector2.ZERO
	var target_position: Vector2 = target.global_position
	if _enemy_id == "bat" and not _should_prefer_roads_for_target(target) and global_position.distance_to(target_position) <= direct_chase_distance:
		_reset_navigation_state()
		return global_position.direction_to(target_position)
	if _path_provider.is_valid():
		_nav_refresh_timer = maxf(0.0, _nav_refresh_timer - delta)
		var target_changed: bool = _last_nav_target_id != target.get_instance_id()
		var moved_far_enough: bool = _last_nav_target_id == 0 or _last_nav_target_position.distance_to(target_position) >= 64.0
		if _nav_refresh_timer <= 0.0 or target_changed or moved_far_enough or _navigation_points.is_empty():
			_request_navigation_path(target)
		var path_direction: Vector2 = _follow_navigation_points(target_position)
		if path_direction != Vector2.ZERO:
			return path_direction
	return global_position.direction_to(target_position)


## 沿固定进攻路线前进，路线点带少量横向错位。
func _follow_route_points() -> Vector2:
	while _route_index < _route_points.size():
		var next_point: Vector2 = _get_offset_route_point(_route_index)
		if global_position.distance_to(next_point) > path_point_reach_distance:
			break
		_route_index += 1
	if _route_index >= _route_points.size():
		return global_position.direction_to(_house.global_position) if is_instance_valid(_house) else Vector2.ZERO
	var route_point: Vector2 = _get_offset_route_point(_route_index)
	return global_position.direction_to(route_point)


## 沿一次性回路路径前进，完成后重新接入固定路线。
func _follow_return_points() -> Vector2:
	while _return_index < _return_points.size():
		var next_point: Vector2 = _return_points[_return_index]
		if global_position.distance_to(next_point) > path_point_reach_distance:
			break
		_return_index += 1
	if _return_index >= _return_points.size():
		_finish_return_to_route()
		return _follow_route_points()
	var target_point: Vector2 = _return_points[_return_index]
	return global_position.direction_to(target_point)


## 仇恨源消失时只接回前进目标：下路未过中点去中点，否则去房子。
func _begin_return_to_route() -> void:
	_reset_navigation_state()
	_route_index = _get_forward_route_index_for_position(global_position)
	_return_points = PackedVector2Array()
	_return_index = 0
	var reconnect_target: Vector2 = _get_offset_route_point(_route_index)
	if _path_provider.is_valid():
		var result: Variant = _path_provider.call(global_position, reconnect_target, false)
		if result is PackedVector2Array:
			_return_points = result
	if _return_points.is_empty():
		_finish_return_to_route()
		return
	_route_state = RouteState.RETURN


## 结束回路状态并继续沿固定路线推房。
func _finish_return_to_route() -> void:
	_route_state = RouteState.ROUTE
	_return_points = PackedVector2Array()
	_return_index = 0
	_reset_navigation_state()


## 路线推进卡住时临时规划一段避障路径接回当前路线点。
func _start_route_recovery_path() -> void:
	if _route_points.is_empty() or not _path_provider.is_valid():
		return
	var target_index: int = clampi(_route_index, 0, _route_points.size() - 1)
	var route_point: Vector2 = _get_offset_route_point(target_index)
	var result: Variant = _path_provider.call(global_position, route_point, false)
	if result is PackedVector2Array:
		_return_points = result
		_return_index = 0
		_route_state = RouteState.RETURN


## 路线点附近卡住时直接跳到下一个路线点，避免重复寻路把怪物锁死。
func _advance_route_after_stuck() -> void:
	if _route_points.is_empty():
		return
	if _route_index < _route_points.size() - 1:
		_route_index += 1
		return
	_route_index = _route_points.size()


## 给路线点加横向错位，临近房子时自动收束。
func _get_offset_route_point(index: int) -> Vector2:
	if _route_points.is_empty():
		return Vector2.ZERO
	var safe_index: int = clampi(index, 0, _route_points.size() - 1)
	var base: Vector2 = _route_points[safe_index]
	if safe_index >= _route_points.size() - 1:
		return base
	var previous: Vector2 = _route_points[maxi(0, safe_index - 1)]
	var next: Vector2 = _route_points[mini(_route_points.size() - 1, safe_index + 1)]
	var tangent: Vector2 = (next - previous).normalized()
	if tangent == Vector2.ZERO:
		tangent = Vector2.RIGHT
	var normal: Vector2 = Vector2(-tangent.y, tangent.x)
	var fade: float = 0.35 if safe_index >= _route_points.size() - 2 else 1.0
	return base + normal * _route_lateral_offset * fade


## 根据实例 id 生成稳定横向错位。
func _calculate_route_lateral_offset() -> float:
	var lane_slot: int = posmod(int(get_instance_id()) + _spawn_index * 17, 7) - 3
	return float(lane_slot) * route_lane_width / 3.0


## 跳过出生点附近已经到达的路线点。
func _advance_route_index_past_spawn() -> void:
	_route_index = _get_forward_route_index_for_position(global_position)


## 找到离给定位置最近的固定路线点。
func _find_closest_route_index(point: Vector2) -> int:
	if _route_points.is_empty():
		return 0
	var best_index: int = 0
	var best_distance_sq: float = INF
	for i in range(_route_points.size()):
		var distance_sq: float = point.distance_squared_to(_route_points[i])
		if distance_sq < best_distance_sq:
			best_distance_sq = distance_sq
			best_index = i
	return best_index


## 根据当前路线进度返回下一步应前往的前进节点。
func _get_forward_route_index_for_position(point: Vector2) -> int:
	if _route_points.is_empty():
		return 0
	if _route_points.size() <= 2:
		return mini(1, _route_points.size() - 1)
	var midpoint_index: int = 1
	var midpoint_progress: float = _get_route_checkpoint_progress(midpoint_index)
	var current_progress: float = _get_route_progress_for_position(point)
	if current_progress >= midpoint_progress - path_point_reach_distance * 1.5:
		return _route_points.size() - 1
	return midpoint_index


## 计算路线指定节点的累计距离。
func _get_route_checkpoint_progress(index: int) -> float:
	if _route_points.size() <= 1:
		return 0.0
	var safe_index: int = clampi(index, 0, _route_points.size() - 1)
	var progress: float = 0.0
	for i in range(1, safe_index + 1):
		progress += _route_points[i - 1].distance_to(_route_points[i])
	return progress


## 把当前位置投影到固定路线，得到沿路线的近似进度。
func _get_route_progress_for_position(point: Vector2) -> float:
	if _route_points.size() <= 1:
		return 0.0
	var best_progress: float = 0.0
	var best_distance_sq: float = INF
	var accumulated: float = 0.0
	for i in range(1, _route_points.size()):
		var from: Vector2 = _route_points[i - 1]
		var to: Vector2 = _route_points[i]
		var segment: Vector2 = to - from
		var length_sq: float = segment.length_squared()
		if length_sq <= 0.01:
			continue
		var t: float = clampf((point - from).dot(segment) / length_sq, 0.0, 1.0)
		var closest: Vector2 = from + segment * t
		var distance_sq: float = point.distance_squared_to(closest)
		if distance_sq < best_distance_sq:
			best_distance_sq = distance_sq
			best_progress = accumulated + sqrt(length_sq) * t
		accumulated += sqrt(length_sq)
	return best_progress


## 清空路线状态，等待主场景提供路线。
func _reset_route_state() -> void:
	_route_state = RouteState.ROUTE
	_route_index = 0
	_return_points = PackedVector2Array()
	_return_index = 0


## 向主场景请求一条避障且更偏向道路的导航路径。
func _request_navigation_path(target: Node2D) -> void:
	if not _path_provider.is_valid() or not is_instance_valid(target):
		return
	var prefer_roads: bool = _should_prefer_roads_for_target(target) and _stuck_avoidance_timer <= 0.0
	var path_result: Variant = _path_provider.call(global_position, target.global_position, prefer_roads)
	if path_result is PackedVector2Array:
		_navigation_points = path_result
	else:
		_navigation_points = PackedVector2Array()
	_navigation_index = 0
	_nav_refresh_timer = path_refresh_interval
	_last_nav_target_id = target.get_instance_id()
	_last_nav_target_position = target.global_position


# 只有默认推房子时偏向道路；被玩家或防御塔吸引后直接从当前位置追击。
func _should_prefer_roads_for_target(target: Node2D) -> bool:
	if target == _house:
		return true
	return false


## 沿着当前路径点逐个前进，并在接近后自动切换到下一个点。
func _follow_navigation_points(target_position: Vector2) -> Vector2:
	if _navigation_points.is_empty():
		return Vector2.ZERO
	while _navigation_index < _navigation_points.size():
		var next_point: Vector2 = _navigation_points[_navigation_index]
		if global_position.distance_to(next_point) > path_point_reach_distance:
			break
		_navigation_index += 1
	if _navigation_index >= _navigation_points.size():
		return global_position.direction_to(target_position)
	var target_point: Vector2 = _navigation_points[_navigation_index]
	return global_position.direction_to(target_point)


## 清空上一次目标留下的路径缓存，避免换目标时继续走旧路。
func _reset_navigation_state() -> void:
	_nav_refresh_timer = 0.0
	_navigation_points = PackedVector2Array()
	_navigation_index = 0
	_last_nav_target_position = Vector2(999999.0, 999999.0)
	_last_nav_target_id = 0


## 玩家进入攻击判定区时结算冲刺伤害。
func _on_attack_area_body_entered(body: Node) -> void:
	if not _pending_player_hit or not _is_alive:
		return
	if body != _player or not is_instance_valid(_player):
		return
	if body.has_method("take_damage"):
		_call_take_damage(body, attack_damage)
	_attack_damage_applied = true
	_pending_player_hit = false
	_attack_dash_timer = 0.0
	velocity = Vector2.ZERO


## 在命中帧做一次前向扫掠判定，避免 Area2D 同步滞后一帧导致玩家不受伤。
func _does_player_overlap_melee_sweep(target: Node2D) -> bool:
	if target == null or get_world_2d() == null:
		return false
	var reach: float = attack_range + player_attack_padding + player_lunge_hit_padding
	var direction: Vector2 = global_position.direction_to(target.global_position)
	if direction == Vector2.ZERO:
		direction = velocity.normalized()
	if direction == Vector2.ZERO:
		direction = Vector2.LEFT if animated_sprite != null and animated_sprite.scale.x < 0.0 else Vector2.RIGHT
	var check_radius: float = maxf(52.0, player_lunge_hit_padding + 28.0)
	var sweep_center: Vector2 = global_position + direction * minf(reach * 0.72, maxf(48.0, global_position.distance_to(target.global_position)))
	var circle := CircleShape2D.new()
	circle.radius = check_radius
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = circle
	query.transform = Transform2D(0.0, sweep_center)
	query.collision_mask = PLAYER_LAYER_MASK
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.exclude = [get_rid()]
	var results: Array[Dictionary] = get_world_2d().direct_space_state.intersect_shape(query, 8)
	for result in results:
		if result.get("collider") == target:
			return true
	return _distance_to_melee_sweep(target.global_position, direction) <= check_radius + 56.0


## 对房子和锚点执行结构物命中扫掠，避免中心点距离导致敌人冲到旁边也打不到。
func _does_structure_overlap_melee_sweep(target: Node2D) -> bool:
	if target == null or get_world_2d() == null:
		return false
	var direction: Vector2 = global_position.direction_to(target.global_position)
	if direction == Vector2.ZERO:
		direction = velocity.normalized()
	if direction == Vector2.ZERO:
		direction = Vector2.LEFT if animated_sprite != null and animated_sprite.scale.x < 0.0 else Vector2.RIGHT
	var reach: float = _get_attack_reach_for(target) + melee_lunge_extra_distance * 0.55
	var check_radius: float = 104.0 if target == _house else 92.0
	var sweep_center: Vector2 = global_position + direction * minf(reach * 0.78, maxf(54.0, global_position.distance_to(target.global_position)))
	var circle := CircleShape2D.new()
	circle.radius = check_radius
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = circle
	query.transform = Transform2D(0.0, sweep_center)
	query.collision_mask = STRUCTURE_LAYER_MASK
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.exclude = [get_rid()]
	var results: Array[Dictionary] = get_world_2d().direct_space_state.intersect_shape(query, 12)
	for result in results:
		if result.get("collider") == target:
			return true
	var fallback_padding: float = 116.0 if target == _house else 96.0
	return _distance_to_melee_sweep(target.global_position, direction) <= attack_range + structure_attack_padding + fallback_padding


## 返回目标点到本次近战前向扫掠线段的距离。
func _distance_to_melee_sweep(point: Vector2, direction: Vector2) -> float:
	if direction == Vector2.ZERO:
		return global_position.distance_to(point)
	var reach: float = attack_range + maxf(player_attack_padding, structure_attack_padding) + melee_lunge_extra_distance
	var finish: Vector2 = global_position + direction.normalized() * reach
	var segment: Vector2 = finish - global_position
	var length_sq: float = segment.length_squared()
	if length_sq <= 0.01:
		return global_position.distance_to(point)
	var t: float = clampf((point - global_position).dot(segment) / length_sq, 0.0, 1.0)
	return point.distance_to(global_position + segment * t)


## 大目标的中心更远，因此为房子和锚点额外补攻击距离。
func _get_attack_reach_for(target: Node2D) -> float:
	if is_ranged:
		return attack_range
	if target == _player:
		return attack_range + player_attack_padding
	if target == _house or target.is_in_group("anchors"):
		return attack_range + structure_attack_padding
	return attack_range


## 返回允许敌人开始前摇的距离，命中仍由 active 帧扫掠决定。
func _get_attack_start_reach_for(target: Node2D) -> float:
	if is_ranged:
		return attack_range
	if target == _player:
		return _get_attack_reach_for(target) + melee_lunge_extra_distance * 0.55
	if target == _house or target.is_in_group("anchors"):
		return _get_attack_reach_for(target) + melee_lunge_extra_distance * 0.45
	return _get_attack_reach_for(target)


# 判断一个节点是否仍然是敌人可攻击和可追踪的目标。
func _is_valid_attack_target(target: Node) -> bool:
	if not is_instance_valid(target):
		return false
	if target.has_method("is_targetable"):
		return bool(target.call("is_targetable"))
	if target.has_method("is_alive"):
		return bool(target.call("is_alive"))
	if target.get("current_hp") != null:
		return float(target.get("current_hp")) > 0.0
	return true


# 长时间原地推挤时丢弃旧路径，下一帧重新找路。
func _update_stuck_recovery(was_trying_to_move: bool, target: Node2D, delta: float) -> void:
	_stuck_avoidance_timer = maxf(0.0, _stuck_avoidance_timer - delta)
	var moved_distance: float = global_position.distance_to(_last_physics_position)
	_last_physics_position = global_position
	if not was_trying_to_move or not _is_valid_attack_target(target):
		_stuck_timer = 0.0
		return
	if moved_distance >= stuck_min_move_distance:
		_stuck_timer = 0.0
		return
	_stuck_timer += delta
	if _stuck_timer < stuck_repath_duration:
		return
	_stuck_timer = 0.0
	_start_stuck_avoidance(target)
	_reset_navigation_state()
	if _route_state == RouteState.ROUTE:
		_advance_route_after_stuck()
	elif _route_state == RouteState.RETURN:
		_finish_return_to_route()
	else:
		_route_state = RouteState.ROUTE


# 卡住后短暂给移动方向叠加一个侧向量，帮助从障碍边缘滑出。
func _start_stuck_avoidance(target: Node2D) -> void:
	if not is_instance_valid(target):
		return
	var to_target: Vector2 = global_position.direction_to(target.global_position)
	if to_target == Vector2.ZERO:
		to_target = Vector2.RIGHT
	var side_sign: float = 1.0 if randi() % 2 == 0 else -1.0
	_stuck_avoidance_direction = to_target.rotated(PI * 0.5 * side_sign).normalized()
	_stuck_avoidance_timer = 0.42


# 把卡住恢复的侧向避障合进寻路方向。
func _apply_stuck_avoidance(direction: Vector2, delta: float) -> Vector2:
	if _stuck_avoidance_timer <= 0.0 or _stuck_avoidance_direction == Vector2.ZERO:
		return direction
	_stuck_avoidance_timer = maxf(0.0, _stuck_avoidance_timer - delta)
	var mixed: Vector2 = direction + _stuck_avoidance_direction * stuck_avoidance_strength
	return mixed.normalized() if mixed.length_squared() > 0.01 else direction


## 对邻近敌人加入轻量分离，减少队列互相挤住。
func _apply_separation(direction: Vector2) -> Vector2:
	if separation_radius <= 0.0:
		return direction
	var push: Vector2 = Vector2.ZERO
	var radius_sq: float = separation_radius * separation_radius
	for node in get_tree().get_nodes_in_group("enemies"):
		if node == self or not is_instance_valid(node) or not (node is Node2D):
			continue
		var other: Node2D = node as Node2D
		var offset: Vector2 = global_position - other.global_position
		var distance_sq: float = offset.length_squared()
		if distance_sq <= 0.01 or distance_sq > radius_sq:
			continue
		var distance: float = sqrt(distance_sq)
		var weight: float = 1.0 - clampf(distance / separation_radius, 0.0, 1.0)
		push += offset.normalized() * weight
	if push.length_squared() <= 0.001:
		return direction
	var mixed: Vector2 = direction + push.normalized() * separation_strength
	return mixed.normalized() if mixed.length_squared() > 0.01 else direction


## 更新受击停顿和减速计时器。
func _update_status(delta: float) -> void:
	_hit_stop_timer = maxf(0.0, _hit_stop_timer - delta)
	if _slow_timer <= 0.0:
		_slow_multiplier = 1.0
		return
	_slow_timer = maxf(0.0, _slow_timer - delta)
	if _slow_timer <= 0.0:
		_slow_multiplier = 1.0


## 只根据水平朝向翻面。
func _update_facing(direction: Vector2) -> void:
	if direction.x > 0.05:
		_set_visual_facing(1.0)
	elif direction.x < -0.05:
		_set_visual_facing(-1.0)


## 简单播放一次攻击动作，没有成品动画时用缩放代替。
func _play_attack_feedback() -> void:
	if _enemy_id.begins_with("slime"):
		var game_audio: Node = get_tree().root.get_node_or_null("GameAudio")
		if game_audio != null:
			game_audio.call("play_slime_attack")
	if animation_player != null and animation_player.has_animation(&"attack"):
		animation_player.play(&"attack")
		return
	var squash_target: Node2D = _get_visible_visual_node()
	if not is_instance_valid(squash_target):
		return
	if is_instance_valid(_attack_visual_tween):
		_attack_visual_tween.kill()
	_attack_visual_tween = create_tween()
	_attack_visual_tween.tween_property(squash_target, "scale:y", absf(squash_target.scale.y) * 0.84, 0.05)
	_attack_visual_tween.tween_property(squash_target, "scale:y", absf(squash_target.scale.y), 0.08)


## 受击时快速闪白。
func _flash_damage() -> void:
	var target_visual: Node2D = _get_visible_visual_node()
	if target_visual == null:
		return
	var tween: Tween = create_tween()
	if target_visual == animated_sprite:
		var old_modulate: Color = animated_sprite.modulate
		animated_sprite.modulate = Color.WHITE
		tween.tween_property(animated_sprite, "modulate", old_modulate, 0.12)
	else:
		visual.color = Color.WHITE
		tween.tween_property(visual, "color", _base_visual_color, 0.12)


## 在敌人头上生成伤害漂字。
func _spawn_damage_text(amount: float) -> void:
	var scene_root: Node = get_tree().current_scene
	if scene_root == null:
		return
	var floating_text: Node2D = FLOATING_TEXT_SCENE.instantiate() as Node2D
	scene_root.add_child(floating_text)
	floating_text.global_position = global_position + _get_damage_text_offset()
	if floating_text.has_method("start_damage"):
		floating_text.call("start_damage", amount)
	else:
		floating_text.call("start", str(amount))


## 敌人死亡时先播一个短演出，再淡出删除。
func _die() -> void:
	if not _is_alive:
		return
	_is_alive = false
	_finish_player_dash()
	_reset_attack_state()
	_reset_navigation_state()
	remove_from_group("enemies")
	died.emit(self, gold_reward, exp_reward)
	if animation_player != null and animation_player.has_animation(&"death"):
		animation_player.play(&"death")
	if is_instance_valid(_death_tween):
		_death_tween.kill()
	_death_tween = create_tween()
	_death_tween.tween_property(self, "scale", scale * 1.12, 0.08)
	_death_tween.tween_property(self, "scale", scale * 0.92, 0.08)
	_death_tween.tween_property(self, "modulate:a", 0.0, 0.18)
	_death_tween.finished.connect(queue_free)


## 应用运行时敌人数值。
func _apply_runtime_stats(runtime: Dictionary) -> void:
	_enemy_id = str(runtime.get("enemy_id", "slime_blue"))
	max_hp = int(round(float(runtime.get("max_hp", 100.0))))
	attack_damage = int(round(float(runtime.get("attack_damage", 5.0))))
	speed = float(runtime.get("speed", 130.0))
	attack_cooldown = float(runtime.get("attack_cooldown", 1.0))
	attack_range = float(runtime.get("attack_range", attack_range))
	player_attack_padding = float(runtime.get("player_attack_padding", player_attack_padding))
	is_ranged = bool(runtime.get("is_ranged", false))
	projectile_speed = float(runtime.get("projectile_speed", projectile_speed))
	projectile_color = runtime.get("projectile_color", projectile_color) as Color
	default_animation = StringName(runtime.get("default_animation", &"idle"))
	player_chase_radius = float(runtime.get("player_chase_radius", player_chase_radius))
	house_priority_radius = float(runtime.get("house_priority_radius", house_priority_radius))
	anchor_chase_radius = float(runtime.get("anchor_chase_radius", anchor_chase_radius))
	structure_attack_padding = float(runtime.get("structure_attack_padding", structure_attack_padding))
	exp_reward = int(runtime.get("exp_reward", exp_reward))
	gold_reward = int(runtime.get("gold_reward", gold_reward))
	_is_boss = bool(runtime.get("is_boss", false))
	_boss_state = BossState.CHASE
	_summon_enemy_id = str(runtime.get("summon_enemy_id", ""))
	_summon_entries.clear()
	var raw_summon_entries: Variant = runtime.get("summon_entries", [])
	if raw_summon_entries is Array:
		for raw_entry in raw_summon_entries as Array:
			if raw_entry is Dictionary:
				_summon_entries.append((raw_entry as Dictionary).duplicate(true))
	_summon_count = int(runtime.get("summon_count", 0))
	_summon_interval = float(runtime.get("summon_interval", 6.0))
	_summon_ring_radius = float(runtime.get("summon_ring_radius", 120.0))
	_summon_timer = _summon_interval
	_base_visual_color = runtime.get("tint", Color(0.20, 0.68, 0.36, 1.0)) as Color
	scale = Vector2.ONE * float(runtime.get("scale_multiplier", 1.0)) * 2.0
	_refresh_boss_health_bar()
	_apply_collision_profile()
	_apply_visual_resource(runtime)
	_apply_visual_profile()
	_apply_attack_area()


# 按敌人类型切换占位轮廓，让蝙蝠和不同史莱姆更容易区分。
func _apply_visual_profile() -> void:
	if visual == null:
		return
	if _enemy_id == "bat":
		visual.polygon = PackedVector2Array([
			Vector2(-34.0, -8.0),
			Vector2(-12.0, -22.0),
			Vector2(0.0, -8.0),
			Vector2(12.0, -22.0),
			Vector2(34.0, -8.0),
			Vector2(13.0, 8.0),
			Vector2(0.0, 22.0),
			Vector2(-13.0, 8.0),
		])
		return
	if _enemy_id == "slime_lightning":
		visual.polygon = PackedVector2Array([
			Vector2(-16.0, -30.0),
			Vector2(22.0, -18.0),
			Vector2(10.0, -2.0),
			Vector2(28.0, 20.0),
			Vector2(-12.0, 28.0),
			Vector2(-28.0, 4.0),
		])
		return
	visual.polygon = PackedVector2Array([
		Vector2(-25.0, -17.0),
		Vector2(0.0, -28.0),
		Vector2(25.0, -17.0),
		Vector2(31.0, 8.0),
		Vector2(14.0, 27.0),
		Vector2(-16.0, 27.0),
		Vector2(-31.0, 8.0),
	])


# 史莱姆使用 SpriteFrames；没有素材的敌人继续显示占位轮廓。
func _apply_visual_resource(runtime: Dictionary) -> void:
	var frames: SpriteFrames = runtime.get("sprite_frames") as SpriteFrames
	var has_frames: bool = frames != null and frames.get_animation_names().size() > 0
	if animated_sprite != null:
		animated_sprite.sprite_frames = frames
		animated_sprite.visible = has_frames
		animated_sprite.modulate = _base_visual_color
		animated_sprite.position = Vector2(0.0, -6.0)
		animated_sprite.scale = _get_sprite_scale_for_enemy(_enemy_id)
		if has_frames and animated_sprite.sprite_frames.has_animation(default_animation):
			animated_sprite.play(default_animation)
	if visual != null:
		visual.visible = not has_frames
		visual.color = _base_visual_color
		visual.modulate = Color.WHITE
	_base_visual_offset = animated_sprite.position if has_frames and animated_sprite != null else visual.position


# 飞行单位不与世界障碍碰撞，避免卡在树林或道路边缘。
func _apply_collision_profile() -> void:
	if _enemy_id == "bat":
		collision_mask = 1
	else:
		collision_mask = 5


## 优先把敌方弹幕挂到世界投射物节点下。
func _get_projectile_parent() -> Node:
	var scene_root: Node = get_tree().current_scene
	if scene_root != null:
		var projectile_root: Node = scene_root.get_node_or_null("World/Projectiles")
		if projectile_root != null:
			return projectile_root
	return get_parent()


# 统一调用承伤接口，并把攻击源位置传给支持击退的目标。
func _call_take_damage(target: Node, amount: int) -> void:
	if target == null or not target.has_method("take_damage"):
		return
	target.call("take_damage", amount, global_position)


# 返回当前正在显示的视觉节点。
func _get_visible_visual_node() -> Node2D:
	if animated_sprite != null and animated_sprite.visible:
		return animated_sprite
	if visual != null and visual.visible:
		return visual
	return null


# 史莱姆原图默认朝右，玩家图规则不同；这里按敌人素材方向翻转。
func _set_visual_facing(sign_x: float) -> void:
	if animated_sprite != null and animated_sprite.visible:
		animated_sprite.scale.x = absf(animated_sprite.scale.x) * sign_x
	if visual != null:
		visual.scale.x = absf(visual.scale.x) * sign_x


# 给敌人一点轻微浮动，和玩家/锚点的占位动画保持一致。
func _update_float(delta: float) -> void:
	_float_phase += delta * 3.0
	var offset_y: float = sin(_float_phase) * 2.6
	if animated_sprite != null and animated_sprite.visible:
		animated_sprite.position = _base_visual_offset + Vector2(0.0, offset_y)
	elif visual != null:
		visual.position = _base_visual_offset + Vector2(0.0, offset_y)


# 根据敌人类型和 boss 缩放选择合适的贴图尺寸。
func _get_sprite_scale_for_enemy(enemy_id: String) -> Vector2:
	if enemy_id == "slime_king":
		return Vector2(0.16, 0.16)
	return Vector2(0.10, 0.10)


## 根据敌人尺寸给伤害飘字找头顶位置。
func _get_damage_text_offset() -> Vector2:
	if _enemy_id == "slime_king":
		return Vector2(0.0, -112.0)
	if _enemy_id == "bat":
		return Vector2(0.0, -58.0)
	return Vector2(0.0, -50.0)


## Boss 显示头顶血条，普通敌人保持隐藏。
func _refresh_boss_health_bar() -> void:
	if boss_health_bar == null:
		return
	boss_health_bar.visible = _is_boss
	if not _is_boss:
		return
	boss_health_bar.max_value = float(maxi(1, max_hp))
	boss_health_bar.value = clampf(float(_hp), 0.0, boss_health_bar.max_value)


## 兼容仍然使用字符串刷怪的旧逻辑。
func _build_legacy_stats(enemy_type: String, enemy_level: int) -> Dictionary:
	if enemy_type == "bat":
		return {
			"enemy_id": "bat",
			"max_hp": 25 * enemy_level + 40,
			"attack_damage": 3 * enemy_level + 5,
			"speed": 190.0 + float(enemy_level) * 9.0,
			"attack_cooldown": 0.6,
			"exp_reward": 16 + enemy_level * 2,
			"gold_reward": 2,
			"tint": Color(0.35, 0.24, 0.68, 1.0),
		}
	return {
		"enemy_id": "slime_blue",
		"max_hp": 30 * enemy_level + 70,
		"attack_damage": 2 * enemy_level + 3,
		"speed": 132.0 + float(enemy_level) * 7.0,
		"attack_cooldown": 1.0,
		"exp_reward": 12 + enemy_level * 2,
		"gold_reward": 1,
		"tint": Color(0.20, 0.68, 0.36, 1.0),
	}


## 让攻击判定圈跟随当前攻击半径。
func _apply_attack_area() -> void:
	if attack_area == null:
		return
	var collision: CollisionShape2D = attack_area.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision == null:
		return
	var shape: CircleShape2D = collision.shape as CircleShape2D
	if shape == null:
		shape = CircleShape2D.new()
	else:
		shape = shape.duplicate() as CircleShape2D
	shape.radius = attack_range if is_ranged else maxf(attack_range, attack_range + player_attack_padding + player_lunge_hit_padding)
	collision.shape = shape


## 通过游戏根节点回调生成 Boss 召唤的小怪。
func _perform_summon() -> void:
	_summon_timer = _summon_interval
	if not _summon_callback.is_valid() or not _can_summon_pack():
		return
	if not _summon_entries.is_empty():
		_summon_callback.call(_summon_entries.duplicate(true), maxi(1, _level - 2), global_position, 1, _summon_ring_radius)
	else:
		_summon_callback.call(_summon_enemy_id, maxi(1, _level - 2), global_position, _summon_count, _summon_ring_radius)


## 判断当前 Boss 是否拥有可执行的召唤配置。
func _can_summon_pack() -> bool:
	if not _summon_entries.is_empty():
		return true
	return not _summon_enemy_id.is_empty() and _summon_count > 0
