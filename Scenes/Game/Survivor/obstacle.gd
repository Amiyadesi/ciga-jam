class_name SurvivorObstacle
extends StaticBody2D
## Placeholder static obstacle used by procedural forest generation.

@onready var collision: CollisionShape2D = $CollisionShape2D
@onready var visual: Polygon2D = $Visual

var footprint: Rect2 = Rect2()


# Sizes the authored obstacle scene without scaling physics nodes.
func setup(center: Vector2, obstacle_size: Vector2, color: Color) -> void:
	global_position = center
	var shape := collision.shape as RectangleShape2D
	if shape == null:
		shape = RectangleShape2D.new()
	else:
		shape = shape.duplicate() as RectangleShape2D
	collision.shape = shape
	shape.size = obstacle_size
	var half: Vector2 = obstacle_size * 0.5
	visual.polygon = PackedVector2Array([
		Vector2(-half.x, -half.y),
		Vector2(half.x, -half.y),
		Vector2(half.x, half.y),
		Vector2(-half.x, half.y),
	])
	visual.color = color
	footprint = Rect2(center - half, obstacle_size)


# Exposes the world-space rectangle used by spawn avoidance.
func get_footprint() -> Rect2:
	return footprint
