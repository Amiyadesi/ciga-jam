class_name SpawnWarning
extends Node2D
## Red X telegraph shown before an enemy spawns.

signal finished(spawn_position: Vector2)

@export var duration: float = 0.85

@onready var line_a: Line2D = $LineA
@onready var line_b: Line2D = $LineB

var _elapsed: float = 0.0


# Places and times the warning marker.
func setup(spawn_position: Vector2, warning_duration: float) -> void:
	global_position = spawn_position
	duration = maxf(0.05, warning_duration)
	_elapsed = 0.0


# Blinks the marker and emits when spawning should occur.
func _process(delta: float) -> void:
	_elapsed += delta
	var pulse: float = 0.45 + 0.55 * abs(sin(_elapsed * 14.0))
	line_a.modulate.a = pulse
	line_b.modulate.a = pulse
	scale = Vector2.ONE * (1.0 + 0.18 * pulse)
	if _elapsed >= duration:
		finished.emit(global_position)
		queue_free()
