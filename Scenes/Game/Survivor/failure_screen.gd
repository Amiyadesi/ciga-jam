@tool
class_name FailureScreen
extends SceneManagerBackdrop
## Result modal shown when the survivor run ends.

signal retry_pressed
signal menu_pressed

@onready var summary_label: Label = %SummaryLabel
@onready var retry_button: ShaderButton = %RetryButton
@onready var menu_button: ShaderButton = %MenuButton
@onready var title_label: Label = $PanelRoot/OuterMargin/ShellPanel/ShellMargin/MainVBox/Title
@onready var message_label: Label = $PanelRoot/OuterMargin/ShellPanel/ShellMargin/MainVBox/Body/MessageLabel


# 连接失败界面按钮并补局内确认音。
func _ready() -> void:
	super._ready()
	if Engine.is_editor_hint():
		return
	var game_audio: Node = get_tree().root.get_node_or_null("GameAudio")
	if game_audio != null:
		game_audio.call("setup_ingame_shader_button", retry_button)
		game_audio.call("setup_ingame_shader_button", menu_button)
		if game_audio.has_method("setup_plain_button"):
			game_audio.call("setup_plain_button", menu_button, "cancel")
	retry_button.pressed.connect(retry_pressed.emit)
	menu_button.pressed.connect(menu_pressed.emit)


# 打开失败界面前刷新本局结算摘要。保留旧接口，避免场景外调用断裂。
func set_summary(kills: int, gold: int) -> void:
	set_result(false, kills, gold, 0, 0, 0)


# 打开结算界面前刷新胜负、波次和成长点折算信息。
func set_result(is_victory: bool, kills: int, gold: int, growth_points: int, cleared_waves: int, total_waves: int) -> void:
	if title_label != null:
		title_label.text = "守护成功" if is_victory else "作战失败"
	if message_label != null:
		if is_victory:
			message_label.text = "史莱姆王被击退，森林暂时安全。剩余金币已折算为成长点。"
		else:
			message_label.text = "守护中断。剩余金币已折算为成长点。"
	if summary_label == null:
		return
	var wave_text: String = "完成波次  %d/%d    |    " % [cleared_waves, total_waves] if total_waves > 0 else ""
	summary_label.text = "%s本局击杀  %d    |    剩余金币  %d    |    成长点 +%d" % [wave_text, kills, gold, growth_points]
	if retry_button != null:
		retry_button.text = "再守一次" if is_victory else "再来一次"
