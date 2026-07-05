class_name EnemyProjectile
extends Area2D
## 敌人远程弹幕，占位色块投射物。

@export var lifetime: float = 3.0
@export var hit_radius: float = 36.0

@onready var visual: Polygon2D = $Visual

var _target: Node2D
var _direction: Vector2 = Vector2.RIGHT
var _speed: float = 520.0
var _damage: int = 1
var _alive_time: float = 0.0


# 初始化弹幕起点、目标、伤害和颜色。
func setup(start_position: Vector2, target: Node2D, damage: int, speed: float, color: Color) -> void:
	global_position = start_position
	_target = target
	_damage = maxi(1, damage)
	_speed = maxf(1.0, speed)
	if is_instance_valid(_target):
		_direction = global_position.direction_to(_target.global_position)
	if visual != null:
		visual.color = color
	rotation = _direction.angle()


# 推进弹幕，并在接近目标时结算伤害。
func _physics_process(delta: float) -> void:
	_alive_time += delta
	if _alive_time >= lifetime:
		queue_free()
		return
	if is_instance_valid(_target):
		_direction = global_position.direction_to(_target.global_position)
		rotation = _direction.angle()
		if global_position.distance_to(_target.global_position) <= hit_radius:
			_apply_hit(_target)
			return
	global_position += _direction * _speed * delta


# 对命中的目标造成伤害后移除弹幕。
func _apply_hit(target: Node) -> void:
	if target.has_method("take_damage"):
		target.call("take_damage", _damage, global_position)
	queue_free()
