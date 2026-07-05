@tool
class_name ThankScreen
extends SceneManagerBackdrop

signal return_requested

@onready var return_button: ShaderButton = %ReturnButton

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	super._ready()
	if Engine.is_editor_hint():
		return
	var game_audio: Node = get_tree().root.get_node_or_null("GameAudio")
	if game_audio != null and game_audio.has_method("setup_menu_shader_button"):
		game_audio.call("setup_menu_shader_button", return_button)
	if game_audio != null and game_audio.has_method("setup_plain_button"):
		game_audio.call("setup_plain_button", return_button, "cancel")
	return_button.pressed.connect(return_requested.emit)
