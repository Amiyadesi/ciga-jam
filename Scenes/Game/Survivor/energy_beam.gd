class_name EnergyBeam
extends Node2D
## Damaging line between the player and a settled anchor.

signal expired

@export var damage_per_tick: int = 8
@export var tick_interval: float = 0.12
@export var beam_radius: float = 26.0
@export var slow_multiplier: float = 0.75
@export var slow_duration: float = 0.18

@onready var line: Line2D = $Line2D

var _player: Node2D
var _anchor: Node2D
var _tick_elapsed: float = 0.0


# Stores the endpoints used by the beam.
func setup(player: Node2D, anchor: Node2D) -> void:
	_player = player
	_anchor = anchor
	_tick_elapsed = 0.0
	_update_line()


# Keeps the visual line current and applies periodic damage.
func _process(delta: float) -> void:
	if not _endpoints_are_valid():
		expired.emit()
		queue_free()
		return

	_update_line()
	_tick_elapsed += delta
	if _tick_elapsed >= tick_interval:
		_tick_elapsed = 0.0
		_damage_enemies_on_segment()


# Updates Line2D points in world-local coordinates.
func _update_line() -> void:
	if not _endpoints_are_valid():
		return
	line.points = PackedVector2Array([_player.global_position, _anchor.global_position])


# Applies beam damage to every enemy intersecting the segment radius.
func _damage_enemies_on_segment() -> void:
	var start: Vector2 = _player.global_position
	var finish: Vector2 = _anchor.global_position
	var multiplier: float = float(_anchor.get("damage_multiplier"))
	var damage: int = maxi(1, int(round(float(damage_per_tick) * multiplier)))
	for node in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(node):
			continue
		if not node is Node2D:
			continue
		var enemy := node as Node2D
		var distance: float = _distance_to_segment(enemy.global_position, start, finish)
		if distance <= beam_radius and enemy.has_method("take_damage"):
			enemy.call("take_damage", damage)
			if enemy.has_method("apply_slow"):
				enemy.call("apply_slow", slow_multiplier, slow_duration)


# Returns true while both beam endpoints remain alive.
func _endpoints_are_valid() -> bool:
	return is_instance_valid(_player) and is_instance_valid(_anchor)


# Computes shortest distance from a point to the finite beam segment.
func _distance_to_segment(point: Vector2, start: Vector2, finish: Vector2) -> float:
	var segment: Vector2 = finish - start
	var length_sq: float = segment.length_squared()
	if is_zero_approx(length_sq):
		return point.distance_to(start)
	var t: float = clampf((point - start).dot(segment) / length_sq, 0.0, 1.0)
	var closest: Vector2 = start + segment * t
	return point.distance_to(closest)
