class_name MagicBullet
extends Area2D
## Simple placeholder projectile fired by the player and placed anchors.

@export var speed: float = 760.0
@export var lifetime: float = 1.4

var damage: float = 1.0
var splash_percent: float = 0.0
var splash_radius: float = 0.0
var pierce_enabled: bool = false
var pierce_falloff: float = 0.0
var status_effects: Array[Dictionary] = []
var source: Node

@onready var visual: Polygon2D = $Visual

var _direction: Vector2 = Vector2.RIGHT
var _elapsed: float = 0.0
var _hit_targets: Array[Node] = []


# Connects collision callbacks for projectile impacts.
func _ready() -> void:
	body_entered.connect(_on_body_entered)


# Moves the projectile until it hits something or times out.
func _physics_process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= lifetime:
		queue_free()
		return
	global_position += _direction * speed * delta


# Initializes projectile combat values and visual tint.
func setup(origin: Vector2, direction: Vector2, attack_damage: float, projectile_color: Color, projectile_source: Node = null, splash_damage_percent: float = 0.0, splash_range: float = 0.0, projectile_modifiers: Dictionary = {}) -> void:
	global_position = origin
	_direction = direction.normalized() if direction.length_squared() > 0.01 else Vector2.RIGHT
	damage = maxf(1.0, attack_damage)
	source = projectile_source
	splash_percent = maxf(0.0, splash_damage_percent)
	splash_radius = maxf(0.0, splash_range)
	pierce_enabled = bool(projectile_modifiers.get("pierce_enabled", false))
	pierce_falloff = clampf(float(projectile_modifiers.get("pierce_falloff", 0.0)), 0.0, 0.95)
	_load_status_effects(projectile_modifiers.get("status_effects", []))
	rotation = _direction.angle()
	if visual != null:
		visual.color = projectile_color


# Applies damage and projectile-carried effects to each valid enemy touched.
func _on_body_entered(body: Node2D) -> void:
	if _hit_targets.has(body):
		return
	if not body.has_method("take_damage"):
		return
	_hit_targets.append(body)
	body.call("take_damage", damage)
	_apply_status_effects(body)
	_apply_splash(body)
	if not pierce_enabled:
		queue_free()
		return
	damage = maxf(1.0, damage * (1.0 - pierce_falloff))


# Applies optional in-run explosion skill damage around the hit point.
func _apply_splash(primary: Node2D) -> void:
	if splash_percent <= 0.0 or splash_radius <= 0.0:
		return
	var splash_damage: float = maxf(1.0, damage * splash_percent)
	for node in get_tree().get_nodes_in_group("enemies"):
		if node == primary or not is_instance_valid(node):
			continue
		if not (node is Node2D):
			continue
		var enemy := node as Node2D
		if enemy.global_position.distance_to(primary.global_position) <= splash_radius and enemy.has_method("take_damage"):
			enemy.call("take_damage", splash_damage)
			_apply_status_effects(enemy)


# Copies status effect data onto the projectile so hit logic is source-agnostic.
func _load_status_effects(raw_effects: Variant) -> void:
	status_effects.clear()
	if not (raw_effects is Array):
		return
	for raw_effect in raw_effects as Array:
		if raw_effect is Dictionary:
			status_effects.append((raw_effect as Dictionary).duplicate(true))


# Applies projectile-carried status effects through target-side effect methods.
func _apply_status_effects(target: Node2D) -> void:
	if target == null or status_effects.is_empty():
		return
	for effect in status_effects:
		match str(effect.get("type", "")):
			"slow":
				if not target.has_method("apply_slow"):
					continue
				var multiplier: float = clampf(float(effect.get("multiplier", 1.0)), 0.05, 1.0)
				var duration: float = maxf(0.0, float(effect.get("duration", 0.0)))
				if multiplier < 1.0 and duration > 0.0:
					target.call("apply_slow", multiplier, duration)
			_:
				pass
