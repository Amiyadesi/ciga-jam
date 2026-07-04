class_name AnchorRecycleDialog
extends Control
## 拆除锚点前的中央确认弹窗。

signal confirmed(anchor: Node)
signal cancelled

@onready var prompt_label: Label = $Panel/Margin/VBox/PromptLabel
@onready var cancel_button: Button = $Panel/Margin/VBox/ButtonRow/CancelButton
@onready var confirm_button: Button = $Panel/Margin/VBox/ButtonRow/ConfirmButton

var _anchor: Node


# 连接确认与取消按钮，并默认隐藏。
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	cancel_button.pressed.connect(_on_cancel_button_pressed)
	confirm_button.pressed.connect(_on_confirm_button_pressed)
	hide()


# 为指定锚点打开确认弹窗。
func open_for_anchor(anchor: Node) -> void:
	if not is_instance_valid(anchor):
		return
	_anchor = anchor
	prompt_label.text = "是否拆除该魔法锚点"
	show()


# 关闭弹窗并清空当前锚点引用。
func close_dialog() -> void:
	_anchor = null
	hide()


# 取消拆除流程。
func _on_cancel_button_pressed() -> void:
	close_dialog()
	cancelled.emit()


# 确认拆除当前锚点。
func _on_confirm_button_pressed() -> void:
	var anchor: Node = _anchor
	close_dialog()
	if is_instance_valid(anchor):
		confirmed.emit(anchor)
