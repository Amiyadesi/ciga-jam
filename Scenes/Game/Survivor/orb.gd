class_name SurvivorOrb
extends Control
## 通用液体圆球 HUD 组件，可用于生命等百分比读数。

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


# 复制一份独立材质，避免不同圆球实例互相串色。
func _ready() -> void:
	_prepare_material()
	_apply_visuals()
	set_meter(100.0, 100.0, 1.0, false)


# 根据当前数值刷新圆球填充和百分比文本。
func set_meter(_current: float, _max_value: float, ratio: float, is_alert: bool = false) -> void:
	var clamped_ratio: float = clampf(ratio, 0.0, 1.0)
	if _material != null:
		_material.set_shader_parameter("progress", clamped_ratio)
	value_label.text = "%d%%" % int(round(clamped_ratio * 100.0))
	value_label.modulate = alert_value_color if is_alert else value_color


# 只更新标题，不改布局。
func set_title(text: String) -> void:
	title_text = text
	title_label.text = title_text


# 创建实例独有材质并应用导出的 shader。
func _prepare_material() -> void:
	if orb.material is ShaderMaterial:
		_material = (orb.material as ShaderMaterial).duplicate() as ShaderMaterial
	else:
		_material = ShaderMaterial.new()
	orb.material = _material
	if shader != null:
		_material.shader = shader


# 把导出颜色同步到 shader 和文本上。
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
