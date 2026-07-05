class_name HouseDetailPanel
extends Control
## 右侧房子详情面板，用于查看生命值和修补。

signal closed
signal repair_requested(house: Node)

const REPAIR_COST: int = 1000
const REPAIR_AMOUNT: int = 20

@onready var close_button: Button = $Panel/Margin/VBox/Header/CloseButton
@onready var panel: PanelContainer = $Panel
@onready var title_label: Label = $Panel/Margin/VBox/Header/TitleLabel
@onready var body_label: Label = $Panel/Margin/VBox/BodyLabel
@onready var repair_button: Button = $Panel/Margin/VBox/ActionSection/RepairButton

var _current_house: Node
var _current_gold: int = 0
var _is_open: bool = false
var _panel_tween: Tween


# 连接详情面板按钮并默认隐藏。
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	close_button.pressed.connect(closed.emit)
	repair_button.pressed.connect(_on_repair_button_pressed)
	panel.pivot_offset = Vector2.ZERO
	panel.modulate.a = 0.0
	hide()


# 打开面板并展示当前房子数据。
func open_for_house(house: Node) -> void:
	if not is_instance_valid(house):
		return
	_current_house = house
	_refresh_content()
	_is_open = true
	_play_open_animation()


# 关闭详情面板。
func close_panel() -> void:
	_current_house = null
	_is_open = false
	_play_close_animation()


# 金币或血量变化后，重刷当前房子数据。
func refresh_current_house(current_gold: int = 0) -> void:
	_current_gold = current_gold
	if not is_instance_valid(_current_house):
		close_panel()
		return
	_refresh_content()


# 返回逻辑打开状态，关闭动画期间不继续维持慢速时间。
func is_open() -> bool:
	return _is_open


# 播放忽略 time_scale 的滑入动画。
func _play_open_animation() -> void:
	show()
	_kill_panel_tween()
	panel.position.x = 72.0
	panel.modulate.a = 0.0
	_panel_tween = create_tween()
	_panel_tween.set_ignore_time_scale(true)
	_panel_tween.set_parallel(true)
	_panel_tween.tween_property(panel, "position:x", 0.0, 0.16).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_panel_tween.tween_property(panel, "modulate:a", 1.0, 0.12)


# 播放忽略 time_scale 的滑出动画，结束后再隐藏节点。
func _play_close_animation() -> void:
	_kill_panel_tween()
	_panel_tween = create_tween()
	_panel_tween.set_ignore_time_scale(true)
	_panel_tween.set_parallel(true)
	_panel_tween.tween_property(panel, "position:x", 72.0, 0.14).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_panel_tween.tween_property(panel, "modulate:a", 0.0, 0.1)
	_panel_tween.finished.connect(_hide_after_close_animation)


# 停掉上一段面板动画，避免快速点击时 tween 叠加。
func _kill_panel_tween() -> void:
	if is_instance_valid(_panel_tween):
		_panel_tween.kill()


# 关闭动画结束时隐藏节点，若中途重开则不隐藏。
func _hide_after_close_animation() -> void:
	if _is_open:
		return
	hide()


# 发出一次修补请求。
func _on_repair_button_pressed() -> void:
	if is_instance_valid(_current_house):
		repair_requested.emit(_current_house)


# 渲染房子详情文本和修补按钮文案。
func _refresh_content() -> void:
	var data: Dictionary = _current_house.call("get_detail_data")
	title_label.text = str(data.get("display_name", "房子"))
	var hp: float = float(data.get("hp", 0.0))
	var max_hp: float = maxf(1.0, float(data.get("max_hp", 1.0)))
	body_label.text = "生命值：%d / %d\n修补：+%d HP\n花费：%d 金币" % [
		int(round(hp)),
		int(round(max_hp)),
		REPAIR_AMOUNT,
		REPAIR_COST,
	]
	var can_repair: bool = hp < max_hp and _current_gold >= REPAIR_COST
	repair_button.disabled = not can_repair
	if hp >= max_hp:
		repair_button.text = "已满血"
	elif _current_gold < REPAIR_COST:
		repair_button.text = "金币不足"
	else:
		repair_button.text = "修补 %d金币" % REPAIR_COST
