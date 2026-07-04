class_name SurvivorEnemy
extends CharacterBody2D
## 生存模式敌人，负责索敌、攻击、召唤和死亡掉落。

signal died(enemy: Node, gold_reward: int, exp_reward: int)

enum BossState {
	CHASE,
	ATTACK,
	SUMMON,
}

const FLOATING_TEXT_SCENE: PackedScene = preload("res://Scenes/UIorgan/floating_text.tscn")

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
## 打房子和锚点时额外补的距离。
@export var structure_attack_padding: float = 95.0
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
## 重新寻路的最短刷新间隔。
@export var path_refresh_interval: float = 0.18
## 认为已经走到当前路径点的距离阈值。
@export var path_point_reach_distance: float = 18.0

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
var _path_provider: Callable
var _is_alive: bool = true
var _enemy_id: String = "slime_blue"
var _level: int = 1
var _is_boss: bool = false
var _boss_state: BossState = BossState.CHASE
var _summon_enemy_id: String = ""
var _summon_count: int = 0
var _summon_interval: float = 6.0
var _summon_ring_radius: float = 120.0
var _summon_timer: float = 0.0
var _summon_callback: Callable
var _attack_dash_timer: float = 0.0
var _attack_dash_speed: float = 0.0
var _attack_dash_destination: Vector2 = Vector2.ZERO
var _pending_player_hit: bool = false
var _attack_visual_tween: Tween
var _death_tween: Tween
var _nav_refresh_timer: float = 0.0
var _navigation_points: PackedVector2Array = PackedVector2Array()
var _navigation_index: int = 0
var _last_nav_target_position: Vector2 = Vector2(999999.0, 999999.0)
var _last_nav_target_id: int = 0


## 初始化敌人自身状态与碰撞监听。
func _ready() -> void:
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	add_to_group("enemies")
	_hp = max_hp
	if attack_area != null:
		attack_area.body_entered.connect(_on_attack_area_body_entered)


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


## 每个物理帧处理索敌、追击、攻击与召唤。
func _physics_process(delta: float) -> void:
	if not _is_alive:
		return
	_attack_timer = maxf(0.0, _attack_timer - delta)
	_update_status(delta)
	if _hit_stop_timer > 0.0:
		velocity = Vector2.ZERO
		move_and_slide()
		return
	if _update_player_dash_motion(delta):
		move_and_slide()
		return
	if _is_boss and _summon_callback.is_valid() and not _summon_enemy_id.is_empty():
		_summon_timer = maxf(0.0, _summon_timer - delta)
		if _summon_timer <= 0.0:
			velocity = Vector2.ZERO
			_boss_state = BossState.SUMMON
			_perform_summon()
			move_and_slide()
			return
	var target: Node2D = _pick_target()
	if is_instance_valid(target):
		var distance: float = global_position.distance_to(target.global_position)
		if distance <= _get_attack_reach_for(target):
			if _try_attack(target):
				move_and_slide()
				return
			velocity = Vector2.ZERO
		else:
			_boss_state = BossState.CHASE
			var direction: Vector2 = _get_navigation_direction(target, delta)
			velocity = direction * speed * _slow_multiplier
			_update_facing(direction)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, speed * delta)
	move_and_slide()


## 承受伤害，并触发受击停顿、减速和死亡流程。
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


## 应用短暂受击停顿。
func apply_hit_stop() -> void:
	_hit_stop_timer = maxf(_hit_stop_timer, hit_stop_duration)


## 应用减速效果，较强效果会覆盖较弱效果。
func apply_slow(multiplier: float, duration: float) -> void:
	_slow_multiplier = minf(_slow_multiplier, clampf(multiplier, 0.05, 1.0))
	_slow_timer = maxf(_slow_timer, duration)


## 依据优先级选择当前目标：房子、玩家、可索敌锚点。
func _pick_target() -> Node2D:
	if is_instance_valid(_house) and global_position.distance_to(_house.global_position) <= house_priority_radius:
		return _house
	if is_instance_valid(_player) and global_position.distance_to(_player.global_position) <= player_chase_radius:
		return _player
	var anchor: Node2D = _nearest_anchor_in_radius(anchor_chase_radius)
	if anchor != null:
		return anchor
	return _house if is_instance_valid(_house) else _player


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
		if anchor.has_method("is_targetable") and not bool(anchor.call("is_targetable")):
			continue
		var dist_sq: float = global_position.distance_squared_to(anchor.global_position)
		if dist_sq <= best_distance_sq:
			best = anchor
			best_distance_sq = dist_sq
	return best


## 在攻击冷却结束后开始一次攻击动作。
func _try_attack(target: Node2D) -> bool:
	if _attack_timer > 0.0 or not target.has_method("take_damage"):
		return false
	_boss_state = BossState.ATTACK if _is_boss else BossState.CHASE
	if target == _player:
		_begin_player_dash(target)
		return true
	_play_attack_feedback()
	target.call("take_damage", attack_damage)
	_attack_timer = attack_cooldown
	return true


## 开始一次朝玩家的短冲刺攻击。
func _begin_player_dash(target: Node2D) -> void:
	_attack_timer = attack_cooldown
	_pending_player_hit = true
	_attack_dash_destination = target.global_position
	_attack_dash_timer = player_dash_duration
	var dash_distance: float = global_position.distance_to(_attack_dash_destination)
	_attack_dash_speed = clampf(dash_distance / maxf(player_dash_duration, 0.01), player_dash_min_speed, player_dash_max_speed)
	_play_attack_feedback()


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


## 检查冲刺攻击期间是否与玩家碰撞重合。
func _check_player_dash_hit() -> void:
	if not _pending_player_hit or attack_area == null:
		return
	for body in attack_area.get_overlapping_bodies():
		_on_attack_area_body_entered(body)
		if not _pending_player_hit:
			return


## 结束当前冲刺攻击。
func _finish_player_dash() -> void:
	_attack_dash_timer = 0.0
	_pending_player_hit = false
	velocity = Vector2.ZERO


## 按当前目标刷新一次寻路，并给出本帧应前进的方向。
func _get_navigation_direction(target: Node2D, delta: float) -> Vector2:
	if not is_instance_valid(target):
		return Vector2.ZERO
	var target_position: Vector2 = target.global_position
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


## 向主场景请求一条避障且更偏向道路的导航路径。
func _request_navigation_path(target: Node2D) -> void:
	if not _path_provider.is_valid() or not is_instance_valid(target):
		return
	var path_result: Variant = _path_provider.call(global_position, target.global_position)
	if path_result is PackedVector2Array:
		_navigation_points = path_result
	else:
		_navigation_points = PackedVector2Array()
	_navigation_index = 0
	_nav_refresh_timer = path_refresh_interval
	_last_nav_target_id = target.get_instance_id()
	_last_nav_target_position = target.global_position


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
		body.call("take_damage", attack_damage)
	_pending_player_hit = false
	_attack_dash_timer = 0.0
	velocity = Vector2.ZERO


## 大目标的中心更远，因此为房子和锚点额外补攻击距离。
func _get_attack_reach_for(target: Node2D) -> float:
	if target == _house or target.is_in_group("anchors"):
		return attack_range + structure_attack_padding
	return attack_range


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
		visual.scale.x = 1.0
	elif direction.x < -0.05:
		visual.scale.x = -1.0


## 简单播放一次攻击动作，没有成品动画时用缩放代替。
func _play_attack_feedback() -> void:
	if _enemy_id.begins_with("slime"):
		var game_audio: Node = get_tree().root.get_node_or_null("GameAudio")
		if game_audio != null:
			game_audio.call("play_slime_attack")
	if animation_player != null and animation_player.has_animation(&"attack"):
		animation_player.play(&"attack")
		return
	if not is_instance_valid(visual):
		return
	if is_instance_valid(_attack_visual_tween):
		_attack_visual_tween.kill()
	_attack_visual_tween = create_tween()
	_attack_visual_tween.tween_property(visual, "scale:y", 0.84, 0.05)
	_attack_visual_tween.tween_property(visual, "scale:y", 1.0, 0.08)


## 受击时快速闪白。
func _flash_damage() -> void:
	var old_color: Color = visual.color
	visual.color = Color.WHITE
	var tween: Tween = create_tween()
	tween.tween_property(visual, "color", old_color, 0.12)


## 在敌人头上生成伤害漂字。
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


## 敌人死亡时先播一个短演出，再淡出删除。
func _die() -> void:
	if not _is_alive:
		return
	_is_alive = false
	_finish_player_dash()
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
	player_chase_radius = float(runtime.get("player_chase_radius", player_chase_radius))
	house_priority_radius = float(runtime.get("house_priority_radius", house_priority_radius))
	anchor_chase_radius = float(runtime.get("anchor_chase_radius", anchor_chase_radius))
	structure_attack_padding = float(runtime.get("structure_attack_padding", structure_attack_padding))
	exp_reward = int(runtime.get("exp_reward", exp_reward))
	gold_reward = int(runtime.get("gold_reward", gold_reward))
	_is_boss = bool(runtime.get("is_boss", false))
	_boss_state = BossState.CHASE
	_summon_enemy_id = str(runtime.get("summon_enemy_id", ""))
	_summon_count = int(runtime.get("summon_count", 0))
	_summon_interval = float(runtime.get("summon_interval", 6.0))
	_summon_ring_radius = float(runtime.get("summon_ring_radius", 120.0))
	_summon_timer = _summon_interval
	visual.color = runtime.get("tint", Color(0.20, 0.68, 0.36, 1.0)) as Color
	scale = Vector2.ONE * float(runtime.get("scale_multiplier", 1.0))
	_apply_attack_area()


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
	shape.radius = attack_range
	collision.shape = shape


## 通过游戏根节点回调生成 Boss 召唤的小怪。
func _perform_summon() -> void:
	_summon_timer = _summon_interval
	if not _summon_callback.is_valid() or _summon_count <= 0:
		return
	_summon_callback.call(_summon_enemy_id, maxi(1, _level - 2), global_position, _summon_count, _summon_ring_radius)
