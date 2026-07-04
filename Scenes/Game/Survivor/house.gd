class_name SurvivorHouse
extends StaticBody2D
## Defended house target split into data definition and world entity.

signal health_changed(current_hp: int, max_hp: int)
signal died

@export var data: Resource

@onready var visual: Polygon2D = $Visual
@onready var door: Polygon2D = $Door
@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var hp_label: Label = $HpLabel
@onready var animation_player: AnimationPlayer = $AnimationPlayer

var current_hp: float = 50.0
var max_hp: float = 50.0
var _is_alive: bool = true


# Initializes the house HP and group membership.
func _ready() -> void:
	add_to_group("house")
	_apply_data()
	current_hp = max_hp
	_refresh_label()
	health_changed.emit(int(round(current_hp)), int(round(max_hp)))


# Applies enemy damage and emits failure once HP reaches zero.
func take_damage(amount: float) -> void:
	if amount <= 0.0 or not _is_alive:
		return
	current_hp = maxf(0.0, current_hp - amount)
	_flash_damage()
	_refresh_label()
	health_changed.emit(int(round(current_hp)), int(round(max_hp)))
	if is_zero_approx(current_hp):
		_is_alive = false
		died.emit()


# Returns true while the house can still be targeted.
func is_alive() -> bool:
	return _is_alive


# Returns whether the house should remain targetable for enemies.
func is_targetable() -> bool:
	return _is_alive and current_hp > 0.0


# Returns UI-ready details used by shared HUD code.
func get_detail_data() -> Dictionary:
	return {
		"display_name": "房子",
		"hp": current_hp,
		"max_hp": max_hp
	}


# Updates the small world label above the placeholder house.
func _refresh_label() -> void:
	if hp_label != null:
		hp_label.text = "%d/%d" % [int(round(current_hp)), int(round(max_hp))]


# Plays placeholder hit feedback without requiring final art.
func _flash_damage() -> void:
	var tween := create_tween()
	var target_color: Color = Color(0.72, 0.38, 0.20, 1.0)
	if data != null:
		target_color = data.get("tint") as Color
	if animated_sprite != null and animated_sprite.visible:
		animated_sprite.modulate = Color(1.0, 0.82, 0.62, 1.0)
		tween.tween_property(animated_sprite, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.12)
		return
	visual.color = Color(1.0, 0.72, 0.48, 1.0)
	tween.tween_property(visual, "color", target_color, 0.12)


# Applies the authored house resource to visuals and labels.
func _apply_data() -> void:
	if data == null:
		return
	var house_data: Resource = data
	max_hp = house_data.get("max_hp")
	var frames: SpriteFrames = house_data.get("sprite_frames") as SpriteFrames
	var has_frames: bool = frames != null and frames.get_animation_names().size() > 0
	if animated_sprite != null:
		animated_sprite.sprite_frames = frames
		animated_sprite.visible = has_frames
	if visual != null:
		visual.visible = not has_frames
		visual.color = house_data.get("tint") as Color
	if door != null:
		door.visible = not has_frames
	if hp_label != null:
		hp_label.position = house_data.get("health_bar_offset") as Vector2
	var default_animation: StringName = house_data.get("default_animation") as StringName
	if default_animation.is_empty():
		default_animation = &"idle"
	if animated_sprite != null and animated_sprite.visible and animated_sprite.sprite_frames != null and animated_sprite.sprite_frames.has_animation(default_animation):
		animated_sprite.play(default_animation)
	elif animation_player != null and animation_player.has_animation(default_animation):
		animation_player.play(default_animation)
