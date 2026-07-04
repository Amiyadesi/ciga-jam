class_name AttackRangeIndicator
extends Node2D
## 通用攻击范围提示圈，用于玩家和锚点的范围显隐反馈。

@export var radius: float = 120.0
@export var ring_color: Color = Color(0.88, 0.96, 1.0, 0.92)
@export var fill_color: Color = Color(0.42, 0.8, 1.0, 0.12)
@export var persistent_visible: bool = false
@export_range(12, 96, 1) var segment_count: int = 48
@export var pulse_speed: float = 3.2
@export_range(0.0, 0.3, 0.01) var pulse_strength: float = 0.08

@onready var fill: Polygon2D = $Fill
@onready var glow_ring: Line2D = $GlowRing
@onready var ring: Line2D = $Ring

var _target_strength: float = 0.0
var _display_strength: float = 0.0


# 初始化圆环形状，并根据常驻模式决定初始显隐。
func _ready() -> void:
	set_radius(radius)
	_target_strength = 1.0 if persistent_visible else 0.0
	_display_strength = _target_strength
	visible = persistent_visible
	_apply_visuals()


# 每帧平滑更新透明度和轻微脉冲，让范围圈有一点亮起的感觉。
func _process(delta: float) -> void:
	_display_strength = move_toward(_display_strength, _target_strength, delta * 6.5)
	if _display_strength <= 0.01 and _target_strength <= 0.01 and not persistent_visible:
		visible = false
		return
	visible = true
	_apply_visuals()


# 按当前半径重建圆形多边形和线段点位。
func set_radius(new_radius: float) -> void:
	radius = maxf(8.0, new_radius)
	var points: PackedVector2Array = _build_circle_points(radius, maxi(12, segment_count))
	if fill != null:
		fill.polygon = points
	if glow_ring != null:
		glow_ring.points = points
		glow_ring.width = clampf(radius * 0.085, 7.0, 24.0)
	if ring != null:
		ring.points = points
		ring.width = clampf(radius * 0.026, 3.0, 9.0)
	_apply_visuals()


# 切换是否常驻显示，供地雷和寒冰法阵这类特殊锚点使用。
func set_persistent_visible(enabled: bool) -> void:
	persistent_visible = enabled
	if persistent_visible:
		_target_strength = 1.0
	elif _target_strength > 0.0:
		_target_strength = 0.0
	_apply_visuals()


# 根据索敌状态切换显隐；常驻模式下始终保持亮起。
func set_active(active: bool) -> void:
	_target_strength = 1.0 if (active or persistent_visible) else 0.0
	if _target_strength > 0.0:
		visible = true


# 用一组主色更新边线和填充色，避免玩家和不同锚点全都长得一样。
func set_palette(main_color: Color) -> void:
	ring_color = Color(main_color.r, main_color.g, main_color.b, 0.92)
	fill_color = Color(main_color.r, main_color.g, main_color.b, 0.12)
	_apply_visuals()


# 生成闭合圆形需要的点集。
func _build_circle_points(circle_radius: float, segments: int) -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()
	for i in range(segments):
		var angle: float = TAU * float(i) / float(segments)
		points.append(Vector2.RIGHT.rotated(angle) * circle_radius)
	return points


# 根据当前显隐强度和脉冲值刷新颜色与微缩放。
func _apply_visuals() -> void:
	if fill == null or glow_ring == null or ring == null:
		return
	var pulse_wave: float = 1.0 + sin(Time.get_ticks_msec() * 0.001 * pulse_speed) * pulse_strength * _display_strength
	glow_ring.width = clampf(radius * 0.085, 7.0, 24.0) * pulse_wave
	ring.width = clampf(radius * 0.026, 3.0, 9.0) * (1.0 + (pulse_wave - 1.0) * 0.6)
	fill.color = Color(fill_color.r, fill_color.g, fill_color.b, fill_color.a * _display_strength)
	glow_ring.default_color = Color(ring_color.r, ring_color.g, ring_color.b, 0.34 * _display_strength)
	ring.default_color = Color(ring_color.r, ring_color.g, ring_color.b, ring_color.a * _display_strength)
