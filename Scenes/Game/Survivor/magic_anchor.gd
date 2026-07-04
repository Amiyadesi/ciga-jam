extends StaticBody2D
## Generic placed anchor entity driven by Resource data plus behavior child scenes.

signal died(anchor: Node)
signal open_detail_requested(anchor: Node)
signal upgrade_requested(anchor: Node)

const AnchorDb = preload("res://Scenes/Game/Survivor/anchor_database.gd")

@onready var visual: Polygon2D = $VisualRoot/Visual
@onready var core: Polygon2D = $VisualRoot/Core
@onready var animated_sprite: AnimatedSprite2D = $VisualRoot/AnimatedSprite2D
@onready var range_area: Area2D = $RangeArea
@onready var range_shape: CollisionShape2D = $RangeArea/CollisionShape2D
@onready var level_label: Label = $LevelLabel
@onready var hp_label: Label = $HpLabel
@onready var upgrade_button: Button = $UpgradeButton
@onready var animation_player: AnimationPlayer = $AnimationPlayer

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
var resource_data: Resource
var current_gold: int = 0

var _is_alive: bool = true
var _behavior: Node


# Connects interaction controls and registers target group.
func _ready() -> void:
	add_to_group("anchors")
	upgrade_button.pressed.connect(func() -> void: upgrade_requested.emit(self))
	upgrade_button.visible = false
	_apply_range_shape()
	_refresh_labels()


# Lets left-click on the placed anchor open the detail panel.
func _input_event(_viewport: Viewport, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			open_detail_requested.emit(self)
			get_viewport().set_input_as_handled()


# Applies database stats to this placed anchor.
func setup(new_anchor_id: String, new_level: int, stats: Dictionary) -> void:
	anchor_id = new_anchor_id
	level = clampi(new_level, 1, int(stats.get("max_level", 3)))
	display_name = str(stats.get("display_name", new_anchor_id))
	short_name = str(stats.get("short_name", display_name))
	resource_data = stats.get("resource") as Resource
	max_hp = float(stats.get("max_hp", 1.0))
	current_hp = max_hp
	attack_damage = float(stats.get("attack_damage", 1.0))
	attack_cooldown = float(stats.get("attack_cooldown", 1.0))
	attack_radius = float(stats.get("attack_radius", 120.0))
	attack_type = str(stats.get("attack_type", "单体"))
	trigger_radius = float(stats.get("trigger_radius", attack_radius))
	full_damage_radius = float(stats.get("full_damage_radius", 32.0))
	min_damage_ratio = float(stats.get("min_damage_ratio", 0.3))
	default_animation = StringName(stats.get("default_animation", &"idle"))
	if visual != null:
		visual.color = stats.get("tint", Color(0.42, 0.75, 1.0, 1.0))
	if core != null:
		core.color = Color(0.08, 0.08, 0.14, 1.0)
	_apply_visual_resource(stats)
	_apply_range_shape()
	_setup_behavior(stats.get("behavior_scene") as PackedScene)
	_refresh_labels()
	if animated_sprite != null and animated_sprite.sprite_frames != null and animated_sprite.sprite_frames.has_animation(default_animation):
		animated_sprite.play(default_animation)
	elif animation_player != null and animation_player.has_animation(default_animation):
		animation_player.play(default_animation)


# Takes enemy damage and removes the anchor when HP reaches zero.
func take_damage(amount: float) -> void:
	if amount <= 0.0 or not _is_alive or max_hp <= 0.0:
		return
	current_hp = maxf(0.0, current_hp - amount)
	_flash_damage()
	_refresh_labels()
	if is_targetable() and is_zero_approx(current_hp):
		_is_alive = false
		died.emit(self)
		queue_free()


# Upgrades the placed anchor to the next stat row and refills HP.
func upgrade() -> bool:
	var next_level: int = level + 1
	var stats: Dictionary = AnchorDb.get_stats(anchor_id, next_level)
	if stats.is_empty() or next_level > int(stats.get("max_level", 3)):
		return false
	setup(anchor_id, next_level, stats)
	return true


# Updates nearby-player affordance and affordability text.
func set_upgrade_visible(is_visible: bool, gold: int) -> void:
	current_gold = gold
	if upgrade_button == null:
		return
	var next_cost: int = AnchorDb.get_upgrade_cost(anchor_id, level)
	var can_upgrade: bool = next_cost > 0
	upgrade_button.visible = is_visible and can_upgrade
	upgrade_button.disabled = not can_upgrade or gold < next_cost
	if not can_upgrade:
		upgrade_button.text = "满级"
		return
	upgrade_button.text = "升级 %d金币" % next_cost
	upgrade_button.add_theme_color_override("font_color", Color(0.48, 1.0, 0.42, 1.0) if gold >= next_cost else Color(1.0, 0.32, 0.28, 1.0))


# Returns current stats for the detail panel.
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
		"is_targetable": is_targetable()
	}


# Returns whether this anchor should be considered a valid enemy target.
func is_targetable() -> bool:
	return _is_alive and max_hp > 0.0 and current_hp > 0.0


# Finds nearest enemy inside this anchor's attack radius.
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


# Returns all enemy nodes inside the given radius.
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


# Keeps the sensor radius in sync with current stats.
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


# Refreshes visible placeholder labels.
func _refresh_labels() -> void:
	if level_label != null:
		level_label.text = "Lv%d" % level
	if hp_label != null:
		hp_label.text = "--" if max_hp < 0.0 else "%d/%d" % [int(round(current_hp)), int(round(max_hp))]


# Gives a short visual hit flash.
func _flash_damage() -> void:
	var stats: Dictionary = AnchorDb.get_stats(anchor_id, level)
	var tween: Tween = create_tween()
	if animated_sprite != null and animated_sprite.visible:
		animated_sprite.modulate = Color.WHITE
		tween.tween_property(animated_sprite, "modulate", Color.WHITE, 0.01)
		tween.tween_property(animated_sprite, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.12)
		return
	if visual != null:
		visual.color = Color.WHITE
		tween.tween_property(visual, "color", stats.get("tint", Color(0.42, 0.75, 1.0, 1.0)), 0.12)


# Applies optional sprite-frame visuals while keeping placeholder polygons as fallback.
func _apply_visual_resource(stats: Dictionary) -> void:
	if animated_sprite == null:
		return
	var frames: SpriteFrames = stats.get("sprite_frames") as SpriteFrames
	animated_sprite.sprite_frames = frames
	var has_frames: bool = frames != null and frames.get_animation_names().size() > 0
	animated_sprite.visible = has_frames
	if visual != null:
		visual.visible = not has_frames
	if core != null:
		core.visible = not has_frames


# Replaces the current child behavior scene with the configured one.
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
