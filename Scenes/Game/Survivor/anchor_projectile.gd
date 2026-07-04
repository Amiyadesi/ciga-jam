class_name AnchorProjectile
extends Area2D
## Moving anchor projectile that settles into a temporary beam endpoint.

signal settled(anchor: Node)
signal expired(anchor: Node)

@export var travel_speed: float = 980.0
@export var min_distance: float = 240.0
@export var max_distance: float = 920.0
@export var landed_duration: float = 2.6
@export var stuck_duration: float = 5.2
@export var landed_damage_multiplier: float = 1.0
@export var stuck_damage_multiplier: float = 1.55

@onready var visual: Polygon2D = $Visual
@onready var trail: Line2D = $Trail
@onready var collision_shape_2d: CollisionShape2D = $CollisionShape2D

var damage_multiplier: float = 1.0
var stuck_to_obstacle: bool = false

var _direction: Vector2 = Vector2.RIGHT
var _travel_limit: float = 360.0
var _travelled: float = 0.0
var _life_remaining: float = 0.0
var _settled: bool = false


# Connects obstacle collision detection for the projectile body.
func _ready() -> void:
	body_entered.connect(_on_body_entered)


# Configures launch direction and distance from the player's charge.
func setup(origin: Vector2, direction: Vector2, charge_ratio: float) -> void:
	global_position = origin
	_direction = direction.normalized()
	rotation = _direction.angle()
	_travel_limit = lerpf(min_distance, max_distance, clampf(charge_ratio, 0.0, 1.0))
	_travelled = 0.0
	_life_remaining = landed_duration
	_settled = false
	stuck_to_obstacle = false
	damage_multiplier = landed_damage_multiplier
	monitoring = true
	_update_trail()


# Advances flight until collision or maximum travel distance.
func _physics_process(delta: float) -> void:
	if _settled:
		_life_remaining -= delta
		if _life_remaining <= 0.0:
			expired.emit(self)
			queue_free()
		return

	var step: float = travel_speed * delta
	global_position += _direction * step
	_travelled += step
	_update_trail()
	if _travelled >= _travel_limit:
		_settle(false)


# Locks the anchor in place and chooses its beam strength.
func _settle(stuck: bool) -> void:
	if _settled:
		return
	_settled = true
	collision_shape_2d.set_deferred("disabled",true)
	stuck_to_obstacle = stuck
	_life_remaining = stuck_duration if stuck else landed_duration
	damage_multiplier = stuck_damage_multiplier if stuck else landed_damage_multiplier
	visual.color = Color(0.92, 0.34, 0.16, 1.0) if stuck else Color(0.9, 0.72, 0.28, 1.0)
	trail.default_color = Color(1.0, 0.34, 0.16, 0.72) if stuck else Color(1.0, 0.84, 0.36, 0.48)
	settled.emit(self)


# Updates the short motion streak behind the anchor.
func _update_trail() -> void:
	trail.points = PackedVector2Array([Vector2.ZERO, -_direction * 38.0])


# Sticks when the anchor hits world geometry.
func _on_body_entered(_body: Node2D) -> void:
	_settle(true)
