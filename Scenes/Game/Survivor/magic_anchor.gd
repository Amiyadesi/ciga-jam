extends StaticBody2D
## 通用已放置锚点实体，由资源数据和行为子场景共同驱动。

signal died(anchor: Node)
signal open_detail_requested(anchor: Node)
signal upgrade_requested(anchor: Node)

const AnchorDb = preload("res://Scenes/Game/Survivor/anchor_database.gd")
const SOLID_ANCHOR_LAYER: int = 4
const INTANGIBLE_PICK_LAYER: int = 16

@onready var visual: Polygon2D = $VisualRoot/Visual
@onready var core: Polygon2D = $VisualRoot/Core
@onready var animated_sprite: AnimatedSprite2D = $VisualRoot/AnimatedSprite2D
@onready var range_area: Area2D = $RangeArea
@onready var range_shape: CollisionShape2D = $RangeArea/CollisionShape2D
@onready var attack_range_indicator: Node2D = $AttackRangeIndicator
@onready var level_label: Label = $LevelLabel
@onready var hp_label: Label = $HpLabel
@onready var upgrade_button: Button = $UpgradeButton
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var aura_light: PointLight2D = $AuraLight

@export var damage_invulnerability_duration: float = 0.5

var anchor_id: String = ""
var level: int = 1
var current_hp: float = 1.0
var max_hp: float = 1.0
var attack_damage: float = 1.0
var attack_cooldown: float = 1.0
var attack_radius: float = 120.0
var attack_type: String = "单体"
var trigger_radius: float = 80.0
var full_damage_radius: float = 32.0
var min_damage_ratio: float = 0.3
var display_name: String = ""
var short_name: String = ""
var default_animation: StringName = &"idle"
var behavior_params: Dictionary = {}
var resource_data: Resource
var current_gold: int = 0

var _is_alive: bool = true
var _behavior: Node
var _runtime_modifiers: Dictionary = {}
var _base_attack_damage: float = 1.0
var _range_targets: Dictionary = {}
var _visual_base_position: Vector2 = Vector2.ZERO
var _float_phase: float = 0.0
var _base_sprite_modulate: Color = Color.WHITE
var _damage_cooldown_timer: float = 0.0
var _base_attack_cooldown: float = 1.0


# 连接交互按钮，并注册锚点分组。
func _ready() -> void:
	add_to_group("anchors")
	_visual_base_position = $VisualRoot.position
	upgrade_button.pressed.connect(func() -> void: upgrade_requested.emit(self))
	upgrade_button.visible = false
	if range_area != null:
		range_area.body_entered.connect(_on_range_area_body_entered)
		range_area.body_exited.connect(_on_range_area_body_exited)
	_apply_range_shape()
	_configure_range_indicator(Color(0.42, 0.75, 1.0, 1.0))
	_refresh_labels()


# 每帧清理无效目标，并根据当前范围内敌人更新提示圈显隐。
func _physics_process(_delta: float) -> void:
	_damage_cooldown_timer = maxf(0.0, _damage_cooldown_timer - _delta)
	_update_visual_float(_delta)
	_prune_range_targets()
	_refresh_range_indicator()


# 允许左键点击已放置锚点打开详情面板。
func _input_event(_viewport: Viewport, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			open_detail_requested.emit(self)
			get_viewport().set_input_as_handled()


# 把数据库里的等级数据写入当前锚点实例。
func setup(new_anchor_id: String, new_level: int, stats: Dictionary) -> void:
	anchor_id = new_anchor_id
	level = clampi(new_level, 1, int(stats.get("max_level", 3)))
	display_name = str(stats.get("display_name", new_anchor_id))
	short_name = str(stats.get("short_name", display_name))
	resource_data = stats.get("resource") as Resource
	max_hp = float(stats.get("max_hp", 1.0))
	current_hp = max_hp
	_base_attack_damage = float(stats.get("attack_damage", 1.0))
	attack_damage = _base_attack_damage
	_base_attack_cooldown = float(stats.get("attack_cooldown", 1.0))
	attack_cooldown = float(stats.get("attack_cooldown", 1.0))
	attack_radius = float(stats.get("attack_radius", 120.0))
	attack_type = str(stats.get("attack_type", "单体"))
	trigger_radius = float(stats.get("trigger_radius", attack_radius))
	full_damage_radius = float(stats.get("full_damage_radius", 32.0))
	min_damage_ratio = float(stats.get("min_damage_ratio", 0.3))
	default_animation = StringName(stats.get("default_animation", &"idle"))
	behavior_params = (stats.get("behavior_params", {}) as Dictionary).duplicate(true)
	var tint: Color = stats.get("tint", Color(0.42, 0.75, 1.0, 1.0)) as Color
	if visual != null:
		visual.color = tint
	if core != null:
		core.color = Color(0.08, 0.08, 0.14, 1.0)
	_apply_aura_light(tint)
	_apply_visual_resource(stats)
	_apply_collision_mode()
	_apply_runtime_modifiers()
	_apply_range_shape()
	_configure_range_indicator(tint)
	_setup_behavior(stats.get("behavior_scene") as PackedScene)
	_refresh_labels()
	_refresh_range_indicator()
	if animated_sprite != null and animated_sprite.sprite_frames != null and animated_sprite.sprite_frames.has_animation(default_animation):
		animated_sprite.play(default_animation)
	elif animation_player != null and animation_player.has_animation(default_animation):
		animation_player.play(default_animation)


# 承受敌人伤害，生命归零后移除锚点。
func take_damage(amount: float, _source_position: Vector2 = Vector2.INF) -> void:
	if amount <= 0.0 or not _is_alive or max_hp <= 0.0 or _damage_cooldown_timer > 0.0:
		return
	_damage_cooldown_timer = damage_invulnerability_duration
	current_hp = maxf(0.0, current_hp - amount)
	_flash_damage()
	_refresh_labels()
	if current_hp <= 0.0:
		_is_alive = false
		_apply_collision_mode()
		died.emit(self)
		queue_free()


# 升级到下一等级，并刷新当前生命值。
func upgrade() -> bool:
	var next_level: int = level + 1
	var stats: Dictionary = AnchorDb.get_stats(anchor_id, next_level)
	if stats.is_empty() or next_level > int(stats.get("max_level", 3)):
		return false
	setup(anchor_id, next_level, stats)
	return true


## 修复固定耐久值，不受受击冷却影响。
func repair(amount: float) -> bool:
	if amount <= 0.0 or not _is_alive or max_hp <= 0.0 or current_hp >= max_hp:
		return false
	current_hp = minf(max_hp, current_hp + amount)
	_refresh_labels()
	return true


## 按最大耐久百分比修复，供局内自动修复技能调用。
func repair_percent(percent: float) -> bool:
	if percent <= 0.0 or max_hp <= 0.0:
		return false
	return repair(max_hp * percent)


# 更新附近玩家可见的升级按钮和价格提示。
func set_upgrade_visible(show_upgrade: bool, gold: int) -> void:
	current_gold = gold
	if upgrade_button == null:
		return
	var next_cost: int = AnchorDb.get_upgrade_cost(anchor_id, level)
	var can_upgrade: bool = next_cost > 0
	upgrade_button.visible = show_upgrade and can_upgrade
	upgrade_button.disabled = not can_upgrade or gold < next_cost
	if not can_upgrade:
		upgrade_button.text = "满级"
		return
	upgrade_button.text = "升级 %d金币" % next_cost
	upgrade_button.add_theme_color_override("font_color", Color(0.48, 1.0, 0.42, 1.0) if gold >= next_cost else Color(1.0, 0.32, 0.28, 1.0))


# 应用本局共享修正，例如锚点攻击力和命中减速。
func set_runtime_modifiers(modifiers: Dictionary) -> void:
	_runtime_modifiers = modifiers.duplicate(true)
	_apply_runtime_modifiers()


# 返回详情面板需要的当前锚点信息。
func get_detail_data() -> Dictionary:
	return {
		"anchor_id": anchor_id,
		"display_name": display_name,
		"short_name": short_name,
		"level": level,
		"hp": current_hp,
		"max_hp": max_hp,
		"attack_damage": attack_damage,
		"attack_cooldown": attack_cooldown,
		"attack_radius": attack_radius,
		"trigger_radius": trigger_radius,
		"full_damage_radius": full_damage_radius,
		"min_damage_ratio": min_damage_ratio,
		"attack_type": attack_type,
		"is_targetable": is_targetable(),
		"price": get_current_price(),
		"behavior_params": behavior_params.duplicate(true),
	}


# 返回当前锚点是否可以被敌人索敌。
func is_targetable() -> bool:
	return _is_alive and max_hp > 0.0 and current_hp > 0.0


# 返回锚点伤害命中时应施加的状态效果数据。
func get_on_hit_status_effects() -> Array[Dictionary]:
	var effects: Array[Dictionary] = []
	var slow_percent: float = clampf(float(behavior_params.get("hit_slow_percent", _runtime_modifiers.get("anchor_hit_slow_percent", 0.0))), 0.0, 0.95)
	if slow_percent > 0.0:
		effects.append({
			"type": "slow",
			"multiplier": 1.0 - slow_percent,
			"duration": maxf(0.1, float(behavior_params.get("hit_slow_duration", _runtime_modifiers.get("anchor_hit_slow_duration", 1.0)))),
		})
	return effects


# 兼容旧行为名，范围伤害行为通过数据接口应用效果。
func apply_on_hit_effects(target: Node) -> void:
	if target == null:
		return
	for effect in get_on_hit_status_effects():
		match str(effect.get("type", "")):
			"slow":
				if target.has_method("apply_slow"):
					target.call(
						"apply_slow",
						clampf(float(effect.get("multiplier", 1.0)), 0.05, 1.0),
						maxf(0.0, float(effect.get("duration", 0.0)))
					)
			_:
				pass


# 根据生命值类型切换物理层，血量小于等于 0 的功能塔不阻挡敌人。
func _apply_collision_mode() -> void:
	collision_layer = SOLID_ANCHOR_LAYER if is_targetable() else INTANGIBLE_PICK_LAYER
	collision_mask = 0


# 查找攻击范围内最近的敌人。
func find_nearest_enemy() -> Node2D:
	var best: Node2D = null
	var best_distance_sq: float = INF
	for node in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(node) or not (node is Node2D):
			continue
		var enemy: Node2D = node as Node2D
		var dist_sq: float = global_position.distance_squared_to(enemy.global_position)
		if dist_sq <= attack_radius * attack_radius and dist_sq < best_distance_sq:
			best = enemy
			best_distance_sq = dist_sq
	return best


# 返回指定半径内的全部敌人。
func find_enemies_in_radius(radius: float) -> Array:
	var enemies: Array = []
	var radius_sq: float = radius * radius
	for node in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(node) or not (node is Node2D):
			continue
		var enemy: Node2D = node as Node2D
		if global_position.distance_squared_to(enemy.global_position) <= radius_sq:
			enemies.append(enemy)
	return enemies


# 返回当前等级配置里的价格，供拆除返金使用。
func get_current_price() -> int:
	return int(resource_data.get("price")) if resource_data != null else 0


# 让索敌判定半径和当前攻击范围保持一致。
func _apply_range_shape() -> void:
	if range_shape == null:
		return
	var circle: CircleShape2D = range_shape.shape as CircleShape2D
	if circle == null:
		circle = CircleShape2D.new()
	else:
		circle = circle.duplicate() as CircleShape2D
	circle.radius = attack_radius
	range_shape.shape = circle


# 刷新等级和血量文本。
func _refresh_labels() -> void:
	if level_label != null:
		level_label.text = "Lv%d" % level
	if hp_label != null:
		hp_label.text = "--" if max_hp < 0.0 else "%d/%d" % [int(round(current_hp)), int(round(max_hp))]


# 触发一次短促的受击闪白。
func _flash_damage() -> void:
	var stats: Dictionary = AnchorDb.get_stats(anchor_id, level)
	var tween: Tween = create_tween()
	if animated_sprite != null and animated_sprite.visible:
		animated_sprite.modulate = Color.WHITE
		tween.tween_property(animated_sprite, "modulate", Color.WHITE, 0.01)
		tween.tween_property(animated_sprite, "modulate", _base_sprite_modulate, 0.12)
		return
	if visual != null:
		visual.color = Color.WHITE
		tween.tween_property(visual, "color", stats.get("tint", Color(0.42, 0.75, 1.0, 1.0)), 0.12)


# 应用贴图动画资源，没有资源时继续使用占位多边形。
func _apply_visual_resource(stats: Dictionary) -> void:
	if animated_sprite == null:
		return
	var frames: SpriteFrames = stats.get("sprite_frames") as SpriteFrames
	animated_sprite.sprite_frames = frames
	var has_frames: bool = frames != null and frames.get_animation_names().size() > 0
	animated_sprite.visible = has_frames
	_base_sprite_modulate = stats.get("tint", Color.WHITE) as Color
	animated_sprite.modulate = _base_sprite_modulate
	animated_sprite.scale = _get_sprite_scale_for_anchor(anchor_id)
	animated_sprite.position = _get_sprite_offset_for_anchor(anchor_id)
	if visual != null:
		visual.visible = not has_frames
	if core != null:
		core.visible = not has_frames


# 用配置里的行为场景替换当前行为实例。
func _setup_behavior(behavior_scene: PackedScene) -> void:
	if is_instance_valid(_behavior):
		_behavior.queue_free()
		_behavior = null
	if behavior_scene == null:
		return
	_behavior = behavior_scene.instantiate()
	add_child(_behavior)
	if _behavior.has_method("setup"):
		_behavior.call("setup", self)


# 在 setup 或升级后重新套用共享修正。
func _apply_runtime_modifiers() -> void:
	attack_damage = _base_attack_damage * float(_runtime_modifiers.get("anchor_attack_multiplier", 1.0))
	attack_cooldown = maxf(0.01, _base_attack_cooldown * float(_runtime_modifiers.get("anchor_attack_cooldown_multiplier", 1.0)))


# 记录进入锚点攻击范围的敌人，用于范围圈显隐。
func _on_range_area_body_entered(body: Node) -> void:
	if not _is_enemy_range_target(body):
		return
	_range_targets[int(body.get_instance_id())] = body
	_refresh_range_indicator()


# 在敌人离开锚点攻击范围后移除对应记录。
func _on_range_area_body_exited(body: Node) -> void:
	if body == null:
		return
	_range_targets.erase(int(body.get_instance_id()))
	_refresh_range_indicator()


# 清理已死亡或已释放的敌人引用，避免范围圈残留。
func _prune_range_targets() -> void:
	if _range_targets.is_empty():
		return
	for target_id in _range_targets.keys():
		var target: Node = _range_targets.get(target_id) as Node
		if not is_instance_valid(target) or target.is_queued_for_deletion():
			_range_targets.erase(target_id)


# 根据索敌状态或特殊常驻规则更新锚点范围圈。
func _refresh_range_indicator() -> void:
	if attack_range_indicator == null:
		return
	var should_show: bool = _should_persist_range_indicator() or (not _range_targets.is_empty() and _is_alive)
	attack_range_indicator.call("set_active", should_show)


# 把锚点半径、颜色和常驻模式同步到范围圈实例。
func _configure_range_indicator(tint: Color) -> void:
	if attack_range_indicator == null:
		return
	attack_range_indicator.call("set_radius", attack_radius)
	attack_range_indicator.call("set_palette", tint)
	attack_range_indicator.call("set_persistent_visible", _should_persist_range_indicator())


# 按锚点颜色刷新局部光，让不同塔的识别色更清楚。
func _apply_aura_light(tint: Color) -> void:
	if aura_light == null:
		return
	aura_light.color = tint.lightened(0.18)
	aura_light.energy = 0.0 if max_hp == 0.0 else 0.82
	aura_light.texture_scale = 2.15 if attack_radius >= 260.0 else 1.75


# 判断当前锚点是否应该常驻显示攻击范围。
func _should_persist_range_indicator() -> bool:
	if bool(behavior_params.get("persistent_range_indicator", false)):
		return true
	return anchor_id == "mine" or anchor_id == "frost_circle"


# 判断进入范围区的物体是不是敌人。
func _is_enemy_range_target(body: Node) -> bool:
	return body != null and body.is_in_group("enemies")


# 已放置锚点保持轻微上下浮动，后续可替换为正式动画。
func _update_visual_float(delta: float) -> void:
	var visual_root: Node2D = $VisualRoot
	if visual_root == null:
		return
	_float_phase += delta * 2.4
	visual_root.position = _visual_base_position + Vector2(0.0, sin(_float_phase) * 4.0)


# 根据不同塔贴图尺寸选择接近碰撞体的显示大小。
func _get_sprite_scale_for_anchor(id: String) -> Vector2:
	match id:
		"xiu_xiu", "double_xiu_xiu":
			return Vector2(0.105, 0.105)
		"mine":
			return Vector2(0.15, 0.15)
		"frost_circle":
			return Vector2(0.18, 0.18)
		"mushroom_tower":
			return Vector2(0.19, 0.19)
		"frost_tower":
			return Vector2(0.15, 0.15)
		_:
			return Vector2(0.16, 0.16)


# 针对贴图重心微调显示偏移，碰撞体仍保留原位。
func _get_sprite_offset_for_anchor(id: String) -> Vector2:
	match id:
		"xiu_xiu", "double_xiu_xiu":
			return Vector2(0.0, -3.0)
		"mine":
			return Vector2(0.0, -2.0)
		"frost_circle":
			return Vector2.ZERO
		"mushroom_tower":
			return Vector2(0.0, -8.0)
		"frost_tower":
			return Vector2.ZERO
		_:
			return Vector2.ZERO
