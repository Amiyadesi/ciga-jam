class_name MineExplosionVfx
extends Node2D
## 地雷爆炸特效，负责显示爆炸范围、中心满伤圈和由红到白的烟雾粒子。

@onready var blast_particles: GPUParticles2D = $BlastParticles
@onready var smoke_particles: GPUParticles2D = $SmokeParticles
@onready var flash_fill: Polygon2D = $FlashFill
@onready var outer_ring: Line2D = $OuterRing
@onready var core_ring: Line2D = $CoreRing


# 按攻击半径和满伤半径配置本次爆炸，并启动全部表现节点。
func setup(radius: float, full_damage_radius: float, tint: Color) -> void:
	var outer_radius: float = maxf(36.0, radius * 1.06)
	var core_radius: float = maxf(18.0, full_damage_radius)
	var outer_scale: float = outer_radius / 100.0
	var core_scale: float = core_radius / 100.0
	_configure_ring(outer_ring, tint, maxf(6.0, outer_radius * 0.038), outer_scale, 0.92)
	_configure_ring(core_ring, Color(1.0, 0.96, 0.9, 1.0), maxf(3.0, core_radius * 0.055), core_scale, 0.82)
	_configure_flash_fill(tint, core_scale)
	_configure_particle_material(blast_particles, outer_radius, core_radius, tint, true)
	_configure_particle_material(smoke_particles, outer_radius, core_radius, tint, false)
	_play_range_animation(outer_scale, core_scale)
	blast_particles.emitting = true
	smoke_particles.emitting = true
	blast_particles.restart()
	smoke_particles.restart()


# 爆炸结束后自动回收整组特效节点。
func _ready() -> void:
	smoke_particles.finished.connect(queue_free)


# 写入外圈和中心圈的颜色、粗细与最终缩放值。
func _configure_ring(target_ring: Line2D, tint: Color, width: float, final_scale: float, alpha: float) -> void:
	if target_ring == null:
		return
	target_ring.width = width
	target_ring.default_color = Color(tint.r, tint.g, tint.b, alpha)
	target_ring.scale = Vector2.ONE * final_scale


# 配置爆炸中心的高亮面片，强调中心区域的满伤范围。
func _configure_flash_fill(tint: Color, core_scale: float) -> void:
	if flash_fill == null:
		return
	flash_fill.color = Color(tint.r, tint.g * 0.72, tint.b * 0.55, 0.28)
	flash_fill.scale = Vector2.ONE * maxf(0.18, core_scale * 0.55)


# 复制粒子材质并按当前半径调节速度、发射范围与尺寸。
func _configure_particle_material(particles: GPUParticles2D, outer_radius: float, core_radius: float, _tint: Color, fast_burst: bool) -> void:
	if particles == null or not (particles.process_material is ParticleProcessMaterial):
		return
	var material: ParticleProcessMaterial = (particles.process_material as ParticleProcessMaterial).duplicate() as ParticleProcessMaterial
	material.emission_sphere_radius = maxf(10.0, core_radius * (0.22 if fast_burst else 0.4))
	if fast_burst:
		material.initial_velocity_min = outer_radius * 0.92
		material.initial_velocity_max = outer_radius * 1.42
		material.scale_min = maxf(1.6, outer_radius * 0.013)
		material.scale_max = maxf(3.2, outer_radius * 0.024)
	else:
		material.initial_velocity_min = outer_radius * 0.36
		material.initial_velocity_max = outer_radius * 0.68
		material.scale_min = maxf(2.8, outer_radius * 0.022)
		material.scale_max = maxf(5.4, outer_radius * 0.036)
	particles.process_material = material
	particles.modulate = Color.WHITE


# 用 tween 扩散外圈、放大中心闪光并同步淡出，让爆炸范围更明确。
func _play_range_animation(outer_scale: float, core_scale: float) -> void:
	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.set_ignore_time_scale(true)
	if outer_ring != null:
		outer_ring.scale = Vector2.ONE * maxf(0.18, outer_scale * 0.18)
		tween.tween_property(outer_ring, "scale", Vector2.ONE * outer_scale, 0.22)
		tween.tween_property(outer_ring, "modulate:a", 0.0, 0.28)
	if core_ring != null:
		core_ring.scale = Vector2.ONE * maxf(0.22, core_scale * 0.7)
		tween.tween_property(core_ring, "scale", Vector2.ONE * core_scale, 0.18)
		tween.tween_property(core_ring, "modulate:a", 0.0, 0.22)
	if flash_fill != null:
		tween.tween_property(flash_fill, "scale", Vector2.ONE * maxf(core_scale * 1.55, outer_scale * 0.52), 0.2)
		tween.tween_property(flash_fill, "modulate:a", 0.0, 0.24)
