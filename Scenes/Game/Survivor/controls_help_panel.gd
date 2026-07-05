@tool
class_name ControlsHelpPanel
extends SceneManagerBackdrop
## First-run control reference modal for survivor mode.

signal dismissed

@onready var understood_button: ShaderButton = %UnderstoodButton


func _ready() -> void:
	super._ready()
	if Engine.is_editor_hint():
		return
	var game_audio: Node = get_tree().root.get_node_or_null("GameAudio")
	if game_audio != null:
		game_audio.call("setup_ingame_shader_button", understood_button)
	understood_button.pressed.connect(_request_dismiss)
	close_modal_requested.connect(_request_dismiss)


func open_panel() -> void:
	if visible:
		return
	open_modal()
	understood_button.grab_focus()


func close_panel() -> void:
	if visible:
		close_modal()


func is_open() -> bool:
	return visible


func _request_dismiss() -> void:
	dismissed.emit()
