class_name AnchorData
extends Resource
## Immutable anchor definition used by placed anchor scenes and catalogs.

@export_group("Identity")
@export var anchor_id: String = ""
@export var display_name: String = ""
@export var short_name: String = ""

@export_group("Combat")
@export var max_hp: float = 1.0
@export var attack_damage: float = 1.0
@export var attack_cooldown: float = 1.0
@export var price: int = 0
@export var attack_type: String = "单体"
@export var attack_radius: float = 120.0
@export var trigger_radius: float = 80.0
@export var full_damage_radius: float = 32.0
@export_range(0.0, 1.0, 0.01) var min_damage_ratio: float = 0.3

@export_group("Visual")
@export var icon_texture: Texture2D
@export var sprite_frames: SpriteFrames
@export var default_animation: StringName = &"idle"
@export var tint: Color = Color(0.42, 0.75, 1.0, 1.0)

@export_group("Behavior")
@export var behavior_scene: PackedScene


# Returns a detail dictionary consumed by authored UI panels.
func to_runtime_dictionary(level: int, max_level: int) -> Dictionary:
	return {
		"resource": self,
		"anchor_id": anchor_id,
		"display_name": display_name,
		"short_name": short_name,
		"max_hp": max_hp,
		"attack_damage": attack_damage,
		"attack_cooldown": attack_cooldown,
		"price": price,
		"attack_type": attack_type,
		"attack_radius": attack_radius,
		"trigger_radius": trigger_radius,
		"full_damage_radius": full_damage_radius,
		"min_damage_ratio": min_damage_ratio,
		"icon_texture": icon_texture,
		"sprite_frames": sprite_frames,
		"default_animation": default_animation,
		"behavior_scene": behavior_scene,
		"tint": tint,
		"level": level,
		"max_level": max_level,
	}
