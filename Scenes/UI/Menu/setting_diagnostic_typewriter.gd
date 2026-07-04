extends Label

const LINES: Array[String] = [
	"audio bus linked",
	"input map ready",
	"save layer stable",
	"signal route checked",
	"settings shell online",
]

var _rng := RandomNumberGenerator.new()
var _serial: int


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rng.randomize()
	add_theme_font_size_override("font_size", 14)
	add_theme_color_override("font_color", Color(1.0, 0.78, 0.42, 0.78))
	horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_start_loop()


func _start_loop() -> void:
	_serial += 1
	call_deferred("_run_loop", _serial)


func _run_loop(serial: int) -> void:
	while is_inside_tree() and serial == _serial:
		var line := LINES[_rng.randi_range(0, LINES.size() - 1)]
		text = "> "
		await _wait(_rng.randf_range(0.18, 0.46))
		for i in range(line.length()):
			if not is_inside_tree() or serial != _serial:
				return
			text = "> " + line.substr(0, i + 1) + "_"
			await _wait(_rng.randf_range(0.024, 0.064))
		await _wait(_rng.randf_range(1.0, 2.1))
		for i in range(line.length(), -1, -1):
			if not is_inside_tree() or serial != _serial:
				return
			text = "> " + line.substr(0, i) + "_"
			await _wait(_rng.randf_range(0.012, 0.036))
		await _wait(_rng.randf_range(0.44, 1.0))


func _wait(seconds: float) -> void:
	if get_tree() == null:
		return
	await get_tree().create_timer(seconds, true, false, true).timeout
