extends Control

@export_range(0.0, 1.0, 0.01) var intensity: float = 0.82

@onready var _key_light: PointLight2D = $KeyLight
@onready var _accent_light: PointLight2D = $AccentLight

var _time: float
var _rect_size := Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_key_light.blend_mode = Light2D.BLEND_MODE_ADD
	_accent_light.blend_mode = Light2D.BLEND_MODE_ADD
	_key_light.shadow_enabled = false
	_accent_light.shadow_enabled = false
	_sync_rect_size()
	resized.connect(_sync_rect_size)
	set_process(true)


func _process(delta: float) -> void:
	_time += delta
	_sync_light_positions()


func _sync_rect_size() -> void:
	_rect_size = size
	if _rect_size.x <= 0.0 or _rect_size.y <= 0.0:
		_rect_size = get_viewport_rect().size
	_sync_light_positions()


func _sync_light_positions() -> void:
	var key_base := Vector2(_rect_size.x * 0.29, _rect_size.y * 0.25)
	var accent_base := Vector2(_rect_size.x * 0.76, _rect_size.y * 0.43)
	_key_light.position = key_base + Vector2(sin(_time * 0.42) * 22.0, cos(_time * 0.31) * 14.0)
	_accent_light.position = accent_base + Vector2(cos(_time * 0.36) * 18.0, sin(_time * 0.48) * 20.0)
	_key_light.energy = (0.17 + sin(_time * 0.9) * 0.02) * intensity
	_accent_light.energy = (0.11 + cos(_time * 0.72) * 0.018) * intensity
