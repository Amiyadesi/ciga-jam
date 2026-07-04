extends Node2D
## Floating damage text that supports configurable color, scale, and decimals.


@onready var label: Label = $Label

# Starts the floating label with raw text for existing callers.
func start(text: String) -> void:
	show_float(text)


# Starts a formatted numeric damage label with up to two decimals.
func start_damage(amount: float, tint: Color = Color(1.0, 0.87, 0.48, 1.0), scale_boost: float = 1.0) -> void:
	label.modulate = tint
	scale = Vector2.ONE * scale_boost
	show_float(_format_damage(amount))


# Animates the label upward, then frees the scene.
func show_float(text: String) -> void:
	label.text = text
	var tween = create_tween()
	tween.set_parallel()
	tween.tween_property(self, "global_position", global_position + Vector2(0.0, -120.0), 0.55)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(self, "modulate:a", 0.0, 0.55)\
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)

	var scale_tween = create_tween()
	scale_tween.tween_property(self, "scale", Vector2.ONE * 1.3, 0.15).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	scale_tween.tween_property(self, "scale", Vector2.ONE, 0.15).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	tween.chain()
	tween.tween_callback(queue_free)


# Formats floating damage with at most two decimal places and no tail zeroes.
func _format_damage(amount: float) -> String:
	var rounded: float = snappedf(amount, 0.01)
	if is_zero_approx(rounded - roundf(rounded)):
		return str(int(round(rounded)))
	var text: String = "%.2f" % rounded
	while text.ends_with("0"):
		text = text.left(text.length() - 1)
	if text.ends_with("."):
		text = text.left(text.length() - 1)
	return text
