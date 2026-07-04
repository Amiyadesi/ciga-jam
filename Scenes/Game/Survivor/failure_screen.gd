@tool
class_name FailureScreen
extends SceneManagerBackdrop
## Failure modal shown when the survivor run ends.

signal retry_pressed
signal menu_pressed

@onready var summary_label: Label = %SummaryLabel
@onready var retry_button: ShaderButton = %RetryButton
@onready var menu_button: ShaderButton = %MenuButton


# 连接失败界面按钮并补局内确认音。
func _ready() -> void:
	super._ready()
	if Engine.is_editor_hint():
		return
	var game_audio: Node = get_tree().root.get_node_or_null("GameAudio")
	if game_audio != null:
		game_audio.call("setup_ingame_shader_button", retry_button)
		game_audio.call("setup_ingame_shader_button", menu_button)
	retry_button.pressed.connect(retry_pressed.emit)
	menu_button.pressed.connect(menu_pressed.emit)


# 打开失败界面前刷新本局结算摘要。
func set_summary(kills: int, gold: int) -> void:
	if summary_label == null:
		return
	summary_label.text = "本局击杀  %d    |    当前金币  %d" % [kills, gold]
