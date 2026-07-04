class_name WaveTable
extends Resource
## Lightweight wave schedule resource for the 15-wave survivor run.

@export var waves: Array[Dictionary] = []


# Returns the total number of authored waves.
func get_total_waves() -> int:
	return waves.size()


# Returns one authored wave dictionary by index.
func get_wave(index: int) -> Dictionary:
	if index < 0 or index >= waves.size():
		return {}
	return (waves[index] as Dictionary).duplicate(true)
