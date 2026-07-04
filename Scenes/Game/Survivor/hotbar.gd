class_name SurvivorHotbar
extends Control
## 生存模式底部热栏，负责购买锚点与开始下一波。

signal anchor_selected(anchor_id: String)
signal wave_start_pressed

const AnchorDb = preload("res://Scenes/Game/Survivor/anchor_database.gd")

@onready var slots: HBoxContainer = $Panel/Margin/VBox/Row/Slots
@onready var start_button: Button = $Panel/Margin/VBox/Row/StartWaveButton

var _selected_anchor_id: String = ""
var _current_gold: int = 0
var _slot_buttons: Array[Button] = []


# 收集场景里已经摆好的按钮并连接信号。
func _ready() -> void:
	for child in slots.get_children():
		if child is Button:
			var button: Button = child as Button
			_slot_buttons.append(button)
			button.pressed.connect(_on_slot_pressed.bind(button))
	start_button.pressed.connect(wave_start_pressed.emit)


# 根据当前金币和锚点目录刷新可购买槽位。
func set_shop_state(selected_anchor_id: String, current_gold: int) -> void:
	_selected_anchor_id = selected_anchor_id
	_current_gold = current_gold
	var ids: Array[String] = AnchorDb.get_anchor_ids()
	for i in range(_slot_buttons.size()):
		var button: Button = _slot_buttons[i]
		if i >= ids.size():
			button.visible = false
			continue
		var anchor_id: String = ids[i]
		var stats: Dictionary = AnchorDb.get_stats(anchor_id, 1)
		var meta: Dictionary = AnchorDb.get_anchor_meta(anchor_id)
		var price: int = int(stats.get("price", 0))
		var can_afford: bool = current_gold >= price
		button.visible = true
		button.disabled = not can_afford
		button.set_meta("anchor_id", anchor_id)
		button.icon = stats.get("icon_texture") as Texture2D
		button.expand_icon = true
		button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
		button.text = "%s\n%d金" % [str(meta.get("short_name", stats.get("short_name", anchor_id))), price]
		button.tooltip_text = "%s  Lv1  %d金币" % [str(meta.get("display_name", anchor_id)), price]
		var font_color: Color = Color(1.0, 0.88, 0.46, 1.0) if anchor_id == _selected_anchor_id else Color(0.86, 0.9, 0.95, 1.0)
		if not can_afford:
			font_color = Color(0.46, 0.49, 0.54, 1.0)
		button.add_theme_color_override("font_color", font_color)


# 只控制开波按钮，不阻止战斗中继续购买和放置锚点。
func set_prepare_state(is_prepare: bool, wave_index: int, total_waves: int) -> void:
	start_button.disabled = not is_prepare
	start_button.text = "开始战斗" if is_prepare else "战斗中"
	start_button.tooltip_text = "第 %d / %d 波" % [wave_index, total_waves]


# 从点击的槽位里发出当前选中的锚点类型。
func _on_slot_pressed(button: Button) -> void:
	var anchor_id: String = str(button.get_meta("anchor_id", ""))
	if anchor_id.is_empty():
		return
	var stats: Dictionary = AnchorDb.get_stats(anchor_id, 1)
	if _current_gold < int(stats.get("price", 0)):
		return
	_selected_anchor_id = anchor_id
	anchor_selected.emit(anchor_id)
	set_shop_state(_selected_anchor_id, _current_gold)
