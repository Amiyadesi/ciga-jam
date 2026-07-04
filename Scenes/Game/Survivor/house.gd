class_name SurvivorHouse
extends StaticBody2D
## 被守护的房子实体，负责承伤、血条和展示。

signal health_changed(current_hp: int, max_hp: int)
signal died

@export var data: Resource

@onready var visual: Polygon2D = $Visual
@onready var door: Polygon2D = $Door
@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var health_bar: ProgressBar = $HealthBar
@onready var animation_player: AnimationPlayer = $AnimationPlayer

var current_hp: float = 50.0
var max_hp: float = 50.0
var _is_alive: bool = true


# 初始化房子生命值并注册分组。
func _ready() -> void:
	add_to_group("house")
	_apply_data()
	current_hp = max_hp
	_refresh_health_bar()
	health_changed.emit(int(round(current_hp)), int(round(max_hp)))


# 承受敌人伤害，血量归零后发出死亡信号。
func take_damage(amount: float) -> void:
	if amount <= 0.0 or not _is_alive:
		return
	current_hp = maxf(0.0, current_hp - amount)
	_flash_damage()
	_refresh_health_bar()
	health_changed.emit(int(round(current_hp)), int(round(max_hp)))
	if is_zero_approx(current_hp):
		_is_alive = false
		died.emit()


# 返回房子是否还存活。
func is_alive() -> bool:
	return _is_alive


# 返回敌人是否还应该索敌房子。
func is_targetable() -> bool:
	return _is_alive and current_hp > 0.0


# 返回详情面板或 HUD 需要的房子数据。
func get_detail_data() -> Dictionary:
	return {
		"display_name": "房子",
		"hp": current_hp,
		"max_hp": max_hp
	}


# 刷新房子脚下世界血条。
func _refresh_health_bar() -> void:
	if health_bar == null:
		return
	health_bar.max_value = maxf(1.0, max_hp)
	health_bar.value = clampf(current_hp, 0.0, max_hp)
	health_bar.visible = true


# 播放简易受击闪色反馈。
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


# 把房子资源数据同步到显示节点。
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
	if health_bar != null:
		health_bar.position = house_data.get("health_bar_offset") as Vector2
	var default_animation: StringName = house_data.get("default_animation") as StringName
	if default_animation.is_empty():
		default_animation = &"idle"
	if animated_sprite != null and animated_sprite.visible and animated_sprite.sprite_frames != null and animated_sprite.sprite_frames.has_animation(default_animation):
		animated_sprite.play(default_animation)
	elif animation_player != null and animation_player.has_animation(default_animation):
		animation_player.play(default_animation)
