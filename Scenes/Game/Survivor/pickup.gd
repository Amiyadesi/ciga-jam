class_name SurvivorPickup
extends Area2D
## 经验球或金币球，会在玩家靠近后吸附过去。

signal collected(kind: String, amount: int)

@export var pickup_radius: float = 80.0
@export var fly_speed: float = 620.0

@onready var visual: Polygon2D = $Visual
@onready var collision: CollisionShape2D = $CollisionShape2D

var kind: String = "gold"
var amount: int = 1

var _target: Node2D
var _is_collecting: bool = false


# 注册掉落分组，便于统一管理。
func _ready() -> void:
	add_to_group("pickups")


# 玩家靠近后开始吸附，并飞向玩家。
func _physics_process(delta: float) -> void:
	if not is_instance_valid(_target):
		return
	if not _is_collecting and global_position.distance_to(_target.global_position) <= pickup_radius:
		_is_collecting = true
	if not _is_collecting:
		return
	global_position = global_position.move_toward(_target.global_position, fly_speed * delta)
	if global_position.distance_to(_target.global_position) <= 14.0:
		collected.emit(kind, amount)
		queue_free()


# 初始化掉落类型、数值、目标和外观颜色。
func setup(pickup_kind: String, pickup_amount: int, player: Node2D) -> void:
	kind = pickup_kind
	amount = maxi(1, pickup_amount)
	_target = player
	if visual != null:
		visual.color = Color(1.0, 0.82, 0.26, 1.0) if kind == "gold" else Color(0.26, 1.0, 0.45, 1.0)
