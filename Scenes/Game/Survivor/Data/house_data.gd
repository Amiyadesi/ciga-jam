class_name HouseData
extends Resource
## Immutable house definition used by the map house entity.

@export var house_id: String = "house"
@export var display_name: String = "房子"
@export var max_hp: float = 50.0
@export var sprite_frames: SpriteFrames
@export var default_animation: StringName = &"idle"
@export var health_bar_offset: Vector2 = Vector2(0.0, 98.0)
@export var tint: Color = Color(0.72, 0.38, 0.20, 1.0)
