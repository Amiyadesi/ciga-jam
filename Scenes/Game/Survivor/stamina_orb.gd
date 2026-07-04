class_name StaminaOrb
extends "res://Scenes/Game/Survivor/orb.gd"
## Compatibility wrapper around the generic orb for stamina-specific updates.


# Initializes the inherited orb with the stamina title.
func _ready() -> void:
	title_text = "STAMINA"
	super._ready()


# Keeps the old stamina-specific API used by SurvivorGame.
func set_stamina(current: float, max_value: float, ratio: float, is_sprinting: bool) -> void:
	set_meter(current, max_value, ratio, is_sprinting)
