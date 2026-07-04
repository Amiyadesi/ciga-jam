@tool
class_name PauseScreen
extends SceneManagerBackdrop

signal setting_pressed
signal quit_pressed
signal continue_pressed

@onready var continue_button: ShaderButton = %ContinueButton
@onready var setting_button: ShaderButton = %SettingButton
@onready var quit_button: ShaderButton = %QuitButton

# 连接暂停菜单按钮并补局内确认音。
func _ready() -> void:
	super._ready()
	if Engine.is_editor_hint():
		return
	var game_audio: Node = get_tree().root.get_node_or_null("GameAudio")
	if game_audio != null:
		game_audio.call("setup_ingame_shader_button", continue_button)
		game_audio.call("setup_ingame_shader_button", setting_button)
		game_audio.call("setup_ingame_shader_button", quit_button)
	continue_button.pressed.connect(continue_pressed.emit)
	setting_button.pressed.connect(setting_pressed.emit)
	quit_button.pressed.connect(quit_pressed.emit)
