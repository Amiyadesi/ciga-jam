class_name SurvivorHotbar
extends Control
## Bottom hotbar for selecting owned anchors and starting the next wave.

signal anchor_selected(anchor_id: String)
signal wave_start_pressed

const AnchorDb = preload("res://Scenes/Game/Survivor/anchor_database.gd")

@onready var slots: HBoxContainer = $Panel/Margin/VBox/Row/Slots
@onready var start_button: Button = $Panel/Margin/VBox/Row/StartWaveButton
@onready var hint_label: Label = $Panel/Margin/VBox/HintLabel

var _inventory: Dictionary = {}
var _selected_anchor_id: String = ""
var _slot_buttons: Array[Button] = []


# Collects authored buttons and wires signals.
func _ready() -> void:
	for child in slots.get_children():
		if child is Button:
			var button: Button = child as Button
			_slot_buttons.append(button)
			button.pressed.connect(_on_slot_pressed.bind(button))
	start_button.pressed.connect(wave_start_pressed.emit)


# Refreshes visible slots from current anchor inventory.
func set_inventory(inventory: Dictionary, selected_anchor_id: String) -> void:
	_inventory = inventory.duplicate(true)
	_selected_anchor_id = selected_anchor_id
	var ids: Array[String] = AnchorDb.get_anchor_ids()
	for i in range(_slot_buttons.size()):
		var button: Button = _slot_buttons[i]
		if i >= ids.size():
			button.visible = false
			continue
		var anchor_id: String = ids[i]
		var count: int = int(_inventory.get(anchor_id, 0))
		if count <= 0:
			button.visible = false
			button.set_meta("anchor_id", "")
			continue
		var stats: Dictionary = AnchorDb.get_stats(anchor_id, 1)
		button.visible = true
		button.disabled = false
		button.set_meta("anchor_id", anchor_id)
		button.icon = stats.get("icon_texture") as Texture2D
		button.expand_icon = true
		button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.alignment = HORIZONTAL_ALIGNMENT_RIGHT
		button.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
		button.text = "x%d" % count if button.icon != null else "%s\nx%d" % [str(stats.get("short_name", anchor_id)), count]
		button.add_theme_color_override("font_color", Color(1.0, 0.88, 0.46, 1.0) if anchor_id == _selected_anchor_id else Color(0.86, 0.9, 0.95, 1.0))


# Enables the wave start button only during preparation.
func set_prepare_state(is_prepare: bool, wave_index: int, total_waves: int) -> void:
	start_button.disabled = not is_prepare
	start_button.text = "开始战斗" if is_prepare else "战斗中"
	hint_label.text = "第 %d / %d 波准备中：选择锚点并放置" % [wave_index, total_waves] if is_prepare else "第 %d / %d 波战斗中" % [wave_index, total_waves]


# Emits the selected anchor id from an authored slot button.
func _on_slot_pressed(button: Button) -> void:
	var anchor_id: String = str(button.get_meta("anchor_id", ""))
	if anchor_id.is_empty():
		return
	_selected_anchor_id = anchor_id
	anchor_selected.emit(anchor_id)
	set_inventory(_inventory, _selected_anchor_id)
