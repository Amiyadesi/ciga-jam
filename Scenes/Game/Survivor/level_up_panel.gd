class_name LevelUpPanel
extends Control
## 局内升级三选一面板。

signal option_selected(skill_id: int)

@onready var title_label: Label = $Panel/Margin/VBox/TitleLabel
@onready var option_box: HBoxContainer = $Panel/Margin/VBox/OptionBox

var _buttons: Array[Button] = []


# 收集场景中已经摆好的三张卡片按钮。
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for child in option_box.get_children():
		if child is Button:
			var button: Button = child as Button
			_buttons.append(button)
			button.pressed.connect(_on_option_pressed.bind(button))
	hide()


# 打开面板并渲染当前可选技能。
func open_options(options: Array[Dictionary]) -> void:
	for i in range(_buttons.size()):
		var button: Button = _buttons[i]
		if i >= options.size():
			button.visible = false
			button.set_meta("skill_id", 0)
			continue
		var skill: Dictionary = options[i]
		var skill_id: int = int(skill.get("id", 0))
		button.visible = true
		button.disabled = false
		button.set_meta("skill_id", skill_id)
		if button.has_method("set_skill_data"):
			button.call("set_skill_data", skill)
		else:
			button.text = "%s\n%s" % [str(skill.get("name", "技能")), str(skill.get("display_description", skill.get("description", "")))]
	title_label.text = "选择成长"
	show()


# 关闭升级面板。
func close_panel() -> void:
	hide()


# 发出玩家当前选中的技能 id。
func _on_option_pressed(button: Button) -> void:
	var skill_id: int = int(button.get_meta("skill_id", 0))
	if skill_id <= 0:
		return
	option_selected.emit(skill_id)
