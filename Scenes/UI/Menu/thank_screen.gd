@tool
class_name ThankScreen
extends SceneManagerBackdrop

signal return_requested

@onready var return_button: ShaderButton = %ReturnButton

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	super._ready()
	return_button.pressed.connect(return_requested.emit)
