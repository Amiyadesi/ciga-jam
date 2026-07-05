extends ComponentBase
class_name ButtonEffectModule

## 按钮轻量交互反馈组件。

## 缓动曲线类型。
@export var ease_type: Tween.EaseType
## 过渡类型。
@export var trans_type: Tween.TransitionType
## 单次动画时长。
@export var anim_duration:float = 0.07
## 悬停或点击时的缩放幅度。
@export var scale_amount:Vector2 = Vector2.ONE * 1.1
## 悬停或点击时的随机旋转幅度。
@export var rotation_amount:float = 3.
## 普通按钮按下时要播放的界面音类型。
@export_enum("none", "confirm", "cancel") var press_sound_kind: String = "confirm"

@onready var button:Button = get_parent()

var tween: Tween

func _component_ready() -> void:
	_on_enable()

func _on_disable() -> void:
	button.mouse_entered.disconnect(_on_mouse_hovered.bind(true))
	button.mouse_exited.disconnect(_on_mouse_hovered.bind(false))
	button.pressed.disconnect(_on_button_pressed)
	

func _on_enable() -> void:
	button.mouse_entered.connect(_on_mouse_hovered.bind(true))
	button.mouse_exited.connect(_on_mouse_hovered.bind(false))
	button.pressed.connect(_on_button_pressed)
	button.pivot_offset_ratio = Vector2.ONE / 2

func _on_button_pressed() -> void:
	_play_press_sound()
	_reset_tween()
	tween.tween_property(button, "scale", 
		scale_amount, anim_duration).from(Vector2.ONE * .8)
	tween.tween_property(button,"rotation_degrees",
		rotation_amount * [-1,1].pick_random(), anim_duration).from(0)

func _reset_tween() -> void:
	if tween:
		tween.kill()
	tween = create_tween().set_ease(ease_type).set_trans(trans_type).set_parallel()
	tween.set_ignore_time_scale(true)

func _on_mouse_hovered(hovered:bool) -> void:
	_reset_tween()
	tween.tween_property(button, "scale", 
		scale_amount if hovered else Vector2.ONE, anim_duration)
	tween.tween_property(button,"rotation_degrees",
		rotation_amount * [-1,1].pick_random() if hovered else 0., anim_duration)


# 给普通 Button 统一补一个界面确认/取消音，避免和 ShaderButton 自带音频重复。
func _play_press_sound() -> void:
	if press_sound_kind == "none":
		return
	if button is ShaderButton:
		return
	var game_audio: Node = _get_game_audio()
	if game_audio == null:
		return
	match press_sound_kind:
		"confirm":
			if game_audio.has_method("play_ui_button_press"):
				game_audio.call("play_ui_button_press", button)
			else:
				game_audio.call("play_ui_confirm_ingame")
		"cancel":
			game_audio.call("play_ui_cancel")
		_:
			pass


# 在运行时查找全局音频路由节点。
func _get_game_audio() -> Node:
	if get_tree() == null or get_tree().root == null:
		return null
	return get_tree().root.get_node_or_null("GameAudio")
	
