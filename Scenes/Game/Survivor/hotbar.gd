class_name SurvivorHotbar
extends Control
## 生存模式底部热栏，负责购买锚点与开始下一波。

signal anchor_selected(anchor_id: String)
signal wave_start_pressed
signal heal_pressed

const AnchorDb = preload("res://Scenes/Game/Survivor/anchor_database.gd")
const HEAL_SLOT_INDEX: int = 6

@onready var slots: HBoxContainer = $Panel/Margin/VBox/Row/Slots
@onready var start_button: Button = $Panel/Margin/VBox/Row/StartWaveButton

var _selected_anchor_id: String = ""
var _current_gold: int = 0
var _slot_buttons: Array[Button] = []
var _heal_cost: int = 1000
var _heal_enabled: bool = false
var _needs_heal: bool = false


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
			_configure_special_slot(button, i)
			continue
		var anchor_id: String = ids[i]
		var stats: Dictionary = AnchorDb.get_stats(anchor_id, 1)
		var meta: Dictionary = AnchorDb.get_anchor_meta(anchor_id)
		var price: int = int(stats.get("price", 0))
		var can_afford: bool = current_gold >= price
		button.visible = true
		button.disabled = not can_afford
		button.set_meta("slot_kind", "anchor")
		button.set_meta("anchor_id", anchor_id)
		button.icon = stats.get("icon_texture") as Texture2D
		button.expand_icon = true
		button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
		button.text = "%s\n%d金" % [str(meta.get("short_name", stats.get("short_name", anchor_id))), price]
		button.tooltip_text = _build_anchor_tooltip(anchor_id, stats, meta, price)
		var font_color: Color = Color(1.0, 0.88, 0.46, 1.0) if anchor_id == _selected_anchor_id else Color(0.86, 0.9, 0.95, 1.0)
		if not can_afford:
			font_color = Color(0.46, 0.49, 0.54, 1.0)
		button.add_theme_color_override("font_color", font_color)


# 刷新血瓶槽位状态。
func set_heal_state(cost: int, can_use: bool, needs_heal: bool) -> void:
	_heal_cost = cost
	_heal_enabled = can_use
	_needs_heal = needs_heal
	if _slot_buttons.size() > HEAL_SLOT_INDEX:
		_configure_heal_slot(_slot_buttons[HEAL_SLOT_INDEX])


# 只控制开波按钮，不阻止战斗中继续购买和放置锚点。
func set_prepare_state(is_prepare: bool, wave_index: int, total_waves: int, wave_name: String = "", wave_description: String = "") -> void:
	start_button.disabled = not is_prepare
	start_button.text = "开始战斗" if is_prepare else "战斗中"
	start_button.tooltip_text = ""


# 从点击的槽位里发出当前选中的锚点类型。
func _on_slot_pressed(button: Button) -> void:
	var slot_kind: String = str(button.get_meta("slot_kind", "anchor"))
	if slot_kind == "heal":
		if _heal_enabled:
			heal_pressed.emit()
		return
	var anchor_id: String = str(button.get_meta("anchor_id", ""))
	if anchor_id.is_empty():
		return
	var stats: Dictionary = AnchorDb.get_stats(anchor_id, 1)
	if _current_gold < int(stats.get("price", 0)):
		return
	_selected_anchor_id = anchor_id
	anchor_selected.emit(anchor_id)
	set_shop_state(_selected_anchor_id, _current_gold)


# 配置非塔槽位，最后一格为血瓶。
func _configure_special_slot(button: Button, index: int) -> void:
	if index == HEAL_SLOT_INDEX:
		_configure_heal_slot(button)
		return
	button.visible = true
	button.disabled = true
	if button.has_meta("anchor_id"):
		button.remove_meta("anchor_id")
	button.set_meta("slot_kind", "empty")
	button.icon = null
	button.text = "-"
	button.tooltip_text = "空槽位"
	button.add_theme_color_override("font_color", Color(0.32, 0.34, 0.38, 1.0))


# 配置血瓶槽位，不使用库存。
func _configure_heal_slot(button: Button) -> void:
	button.visible = true
	button.disabled = not _heal_enabled
	if button.has_meta("anchor_id"):
		button.remove_meta("anchor_id")
	button.set_meta("slot_kind", "heal")
	button.icon = null
	button.text = "血瓶\n%d金" % _heal_cost
	if _heal_enabled:
		button.tooltip_text = "花费 %d 金币回满生命" % _heal_cost
	else:
		button.tooltip_text = "金币不足"
	button.add_theme_color_override("font_color", Color(0.96, 0.38, 0.42, 1.0) if _heal_enabled else Color(0.46, 0.49, 0.54, 1.0))


# 组合塔位说明，方便测试时直接查看当前策划数值和特殊效果。
func _build_anchor_tooltip(anchor_id: String, stats: Dictionary, meta: Dictionary, price: int) -> String:
	var lines: Array[String] = [
		"%s  Lv1  %d金币" % [str(meta.get("display_name", anchor_id)), price],
		"类型：%s    范围：%dpx" % [str(stats.get("attack_type", "单体")), int(round(float(stats.get("attack_radius", 0.0))))],
	]
	var damage: float = float(stats.get("attack_damage", 0.0))
	var cooldown: float = float(stats.get("attack_cooldown", 0.0))
	if damage > 0.0:
		lines.append("攻击：%s    冷却：%.2fs" % [str(stats.get("attack_damage", 0.0)), cooldown])
	elif cooldown > 0.0:
		lines.append("触发冷却：%.2fs" % cooldown)
	var params: Dictionary = stats.get("behavior_params", {}) as Dictionary
	if params.has("blast_radius"):
		lines.append("爆炸半径：%dpx" % int(round(float(params.get("blast_radius", 0.0)))))
	if params.has("slow_percent"):
		lines.append("减速：%d%%" % int(round(float(params.get("slow_percent", 0.0)) * 100.0)))
	if bool(params.get("pierce_enabled", false)):
		lines.append("贯穿衰减：%d%%" % int(round(float(params.get("pierce_falloff", 0.0)) * 100.0)))
	if params.has("hit_slow_percent"):
		lines.append("命中减速：%d%%" % int(round(float(params.get("hit_slow_percent", 0.0)) * 100.0)))
	var description: String = str(meta.get("description", ""))
	if not description.is_empty():
		lines.append(description)
	return "\n".join(lines)
