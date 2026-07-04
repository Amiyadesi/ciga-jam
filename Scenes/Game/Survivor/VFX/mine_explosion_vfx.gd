class_name MineExplosionVfx
extends Node2D
## Simple authored mine explosion effect that scales with the configured radius.

@onready var particles: GPUParticles2D = $GPUParticles2D
@onready var ring: Line2D = $Ring


# Applies the explosion radius and starts playback once spawned.
func setup(radius: float, tint: Color) -> void:
	var normalized_radius: float = maxf(24.0, radius)
	ring.default_color = Color(tint.r, tint.g, tint.b, 0.9)
	ring.width = maxf(4.0, normalized_radius * 0.04)
	ring.scale = Vector2.ONE * normalized_radius / 100.0
	if particles.process_material is ParticleProcessMaterial:
		var material: ParticleProcessMaterial = (particles.process_material as ParticleProcessMaterial).duplicate() as ParticleProcessMaterial
		material.color = tint
		material.initial_velocity_min = normalized_radius * 1.1
		material.initial_velocity_max = normalized_radius * 1.7
		particles.process_material = material
	particles.restart()


# Removes the one-shot effect after it finishes emitting.
func _ready() -> void:
	particles.finished.connect(queue_free)
