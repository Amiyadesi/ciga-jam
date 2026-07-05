class_name AnchorDetailPanel
extends Control
## 右侧锚点详情面板，用于查看、升级和拆除。

signal closed
signal upgrade_requested(anchor: Node)
signal recycle_requested(anchor: Node)

const AnchorDb = preload("res://Scenes/Game/Survivor/anchor_database.gd")

@onready var close_button: Button = $Panel/Margin/VBox/Header/CloseButton
@onready var panel: PanelContainer = $Panel
@onready var title_label: Label = $Panel/Margin/VBox/Header/TitleLabel
@onready var body_label: Label = $Panel/Margin/VBox/BodyLabel
@onready var upgrade_button: Button = $Panel/Margin/VBox/ActionSection/UpgradeButton
@onready var recycle_button: Button = $Panel/Margin/VBox/ActionSection/RecycleButton

var _current_anchor: Node
var _is_open: bool = false
var _panel_tween: Tween


# 连接详情面板按钮并默认隐藏。
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	close_button.pressed.connect(closed.emit)
	upgrade_button.pressed.connect(_on_upgrade_button_pressed)
	recycle_button.pressed.connect(_on_recycle_button_pressed)
	panel.pivot_offset = Vector2.ZERO
	panel.modulate.a = 0.0
	hide()


# 打开面板并展示当前锚点数据。
func open_for_anchor(anchor: Node) -> void:
	if not is_instance_valid(anchor):
		return
	_current_anchor = anchor
	_refresh_content()
	_is_open = true
	_play_open_animation()


# 关闭详情面板。
func close_panel() -> void:
	_current_anchor = null
	_is_open = false
	_play_close_animation()


# 升级或金币变化后，重刷当前锚点数据。
func refresh_current_anchor() -> void:
	if not is_instance_valid(_current_anchor):
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


# 发出一次升级请求。
func _on_upgrade_button_pressed() -> void:
	if is_instance_valid(_current_anchor):
		upgrade_requested.emit(_current_anchor)


# 发出一次拆除请求。
func _on_recycle_button_pressed() -> void:
	if is_instance_valid(_current_anchor):
		recycle_requested.emit(_current_anchor)


# 渲染锚点详情文本和操作按钮文案。
func _refresh_content() -> void:
	var data: Dictionary = _current_anchor.call("get_detail_data")
	title_label.text = "%s  Lv%d" % [str(data.get("display_name", "锚点")), int(data.get("level", 1))]
	var max_hp: float = float(data.get("max_hp", 0.0))
	var hp_text: String = "耐久值：--"
	if max_hp > 0.0:
		hp_text = "耐久值：%d / %d" % [int(round(float(data.get("hp", 0.0)))), int(round(max_hp))]
	var trigger_radius: float = float(data.get("trigger_radius", 0.0))
	var extra_radius_line: String = ""
	if trigger_radius > 0.0 and not is_equal_approx(trigger_radius, float(data.get("attack_radius", 0.0))):
		extra_radius_line = "\n触发半径：%d" % int(round(trigger_radius))
	var extra_lines: Array[String] = _build_special_lines(data)
	body_label.text = "%s\n攻击力：%s\n攻击冷却：%.2f 秒\n攻击半径：%d%s\n攻击类型：%s%s" % [
		hp_text,
		str(data.get("attack_damage", 0.0)),
		float(data.get("attack_cooldown", 0.0)),
		int(round(float(data.get("attack_radius", 0.0)))),
		extra_radius_line,
		str(data.get("attack_type", "单体")),
		"\n%s" % "\n".join(extra_lines) if not extra_lines.is_empty() else ""
	]
	_refresh_action_buttons(data)


# 生成不同锚点各自的特殊字段说明。
func _build_special_lines(data: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	var behavior_params: Dictionary = data.get("behavior_params", {}) as Dictionary
	if behavior_params.has("blast_radius"):
		lines.append("爆炸半径：%d" % int(round(float(behavior_params.get("blast_radius", 0.0)))))
	if behavior_params.has("slow_percent"):
		lines.append("减速：%d%%" % int(round(float(behavior_params.get("slow_percent", 0.0)) * 100.0)))
	if data.has("full_damage_radius") and float(data.get("attack_damage", 0.0)) > 0.0 and str(data.get("attack_type", "")) == "范围":
		lines.append("满伤半径：%d" % int(round(float(data.get("full_damage_radius", 0.0)))))
		lines.append("边缘伤害：%d%%" % int(round(float(data.get("min_damage_ratio", 0.0)) * 100.0)))
	return lines


# 根据锚点当前状态刷新升级与拆除按钮。
func _refresh_action_buttons(data: Dictionary) -> void:
	var anchor_id: String = str(data.get("anchor_id", ""))
	var level: int = int(data.get("level", 1))
	var next_cost: int = AnchorDb.get_upgrade_cost(anchor_id, level)
	var current_price: int = int(data.get("price", 0))
	var recycle_gold: int = int(round(float(current_price) * 0.6))
	upgrade_button.disabled = next_cost <= 0
	upgrade_button.text = "升级 %d金币" % next_cost if next_cost > 0 else "已满级"
	recycle_button.disabled = current_price <= 0
	recycle_button.text = "拆除 +%d金币" % recycle_gold
