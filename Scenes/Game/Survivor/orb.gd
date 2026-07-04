class_name SurvivorOrb
extends Control
## Generic liquid orb HUD widget used for stamina and health meters.

@export var shader: Shader
@export var title_text: String = "ORB"
@export var liquid_color: Color = Color(0.18, 0.74, 0.92, 1.0)
@export var liquid_back_color: Color = Color(0.06, 0.32, 0.55, 1.0)
@export var danger_color: Color = Color(1.0, 0.24, 0.0, 1.0)
@export var rim_color: Color = Color(0.88, 0.96, 1.0, 1.0)
@export var bg_color: Color = Color(0.0, 0.0, 0.0, 0.24)
@export var shine_color: Color = Color(1.0, 1.0, 1.0, 0.28)
@export var title_color: Color = Color(0.77, 0.93, 1.0, 0.92)
@export var value_color: Color = Color(0.88, 0.96, 1.0, 0.92)
@export var alert_value_color: Color = Color(1.0, 0.72, 0.56, 1.0)

@onready var orb: ColorRect = $Orb
@onready var title_label: Label = $TitleLabel
@onready var value_label: Label = $ValueLabel

var _material: ShaderMaterial


# Duplicates the shader material so each orb instance can override its colors.
func _ready() -> void:
	_prepare_material()
	_apply_visuals()
	set_meter(100.0, 100.0, 1.0, false)


# Updates the orb fill, title, and numeric text from gameplay state.
func set_meter(current: float, max_value: float, ratio: float, is_alert: bool = false) -> void:
	var clamped_ratio: float = clampf(ratio, 0.0, 1.0)
	if _material != null:
		_material.set_shader_parameter("progress", clamped_ratio)
	value_label.text = "%d/%d" % [int(round(current)), int(round(max_value))]
	value_label.modulate = alert_value_color if is_alert else value_color


# Updates only the orb title while preserving the existing layout.
func set_title(text: String) -> void:
	title_text = text
	title_label.text = title_text


# Creates a per-instance material copy and applies the exported shader.
func _prepare_material() -> void:
	if orb.material is ShaderMaterial:
		_material = (orb.material as ShaderMaterial).duplicate() as ShaderMaterial
	else:
		_material = ShaderMaterial.new()
	orb.material = _material
	if shader != null:
		_material.shader = shader


# Pushes exported colors into the shader material and visible labels.
func _apply_visuals() -> void:
	if _material != null:
		_material.set_shader_parameter("liquid_color", liquid_color)
		_material.set_shader_parameter("liquid_back_color", liquid_back_color)
		_material.set_shader_parameter("danger_color", danger_color)
		_material.set_shader_parameter("rim_color", rim_color)
		_material.set_shader_parameter("bg_color", bg_color)
		_material.set_shader_parameter("shine_color", shine_color)
	title_label.text = title_text
	title_label.modulate = title_color
	value_label.modulate = value_color
