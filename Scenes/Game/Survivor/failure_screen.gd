@tool
class_name FailureScreen
extends SceneManagerBackdrop
## Failure modal shown when the survivor run ends.

signal retry_pressed
signal menu_pressed

@onready var summary_label: Label = %SummaryLabel
@onready var retry_button: ShaderButton = %RetryButton
@onready var menu_button: ShaderButton = %MenuButton


# Wires result buttons after SceneManagerBackdrop captures the modal root.
func _ready() -> void:
	super._ready()
	if Engine.is_editor_hint():
		return
	retry_button.pressed.connect(retry_pressed.emit)
	menu_button.pressed.connect(menu_pressed.emit)


# Updates run stats before the modal opens.
func set_summary(kills: int, gold: int) -> void:
	if summary_label == null:
		return
	summary_label.text = "本局击杀  %d    |    当前金币  %d" % [kills, gold]
