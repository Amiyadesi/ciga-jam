class_name SlowAuraAnchorBehavior
extends Node
## Continuously reapplies a slowing aura to enemies inside the anchor radius.

var _anchor: Node
var _tick_timer: float = 0.0
var _tick_interval: float = 0.2
var _slow_percent: float = 0.6
var _slow_duration: float = 0.35


# Stores the owning anchor and behavior tuning loaded from anchor data.
func setup(anchor: Node) -> void:
	_anchor = anchor
	var params: Dictionary = anchor.get("behavior_params") as Dictionary
	_tick_interval = maxf(0.05, float(params.get("tick_interval", 0.2)))
	_slow_percent = clampf(float(params.get("slow_percent", 0.6)), 0.0, 0.95)
	_slow_duration = maxf(_tick_interval, float(params.get("slow_duration", 0.35)))
	_tick_timer = 0.0


# Reapplies the aura to every enemy in range at a fixed cadence.
func _physics_process(delta: float) -> void:
	if not is_instance_valid(_anchor):
		return
	_tick_timer = maxf(0.0, _tick_timer - delta)
	if _tick_timer > 0.0:
		return
	_tick_timer = _tick_interval
	var enemies: Array = _anchor.call("find_enemies_in_radius", float(_anchor.get("attack_radius")))
	for item in enemies:
		var enemy: Node = item as Node
		if enemy == null or not enemy.has_method("apply_slow"):
			continue
		enemy.call("apply_slow", 1.0 - _slow_percent, _slow_duration)
