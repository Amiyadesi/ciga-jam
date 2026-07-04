class_name AnchorDetailPanel
extends Control
## Right-side slow-time details panel for a selected placed anchor.

signal closed

@onready var close_button: Button = $Panel/Margin/VBox/Header/CloseButton
@onready var title_label: Label = $Panel/Margin/VBox/Header/TitleLabel
@onready var body_label: Label = $Panel/Margin/VBox/BodyLabel


# Wires the close button.
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	close_button.pressed.connect(closed.emit)
	hide()


# Opens the panel with current anchor data.
func open_for_anchor(anchor: Node) -> void:
	if not is_instance_valid(anchor):
		return
	var data: Dictionary = anchor.call("get_detail_data")
	title_label.text = "%s  Lv%d" % [str(data.get("display_name", "锚点")), int(data.get("level", 1))]
	var max_hp: float = float(data.get("max_hp", 0.0))
	var hp_text: String = "耐久值：--"
	if max_hp > 0.0:
		hp_text = "耐久值：%d / %d" % [int(round(float(data.get("hp", 0.0)))), int(round(max_hp))]
	var trigger_radius: float = float(data.get("trigger_radius", 0.0))
	var extra_radius_line: String = ""
	if trigger_radius > 0.0 and not is_equal_approx(trigger_radius, float(data.get("attack_radius", 0.0))):
		extra_radius_line = "\n触发半径：%d" % int(round(trigger_radius))
	body_label.text = "%s\n攻击力：%s\n攻击冷却：%.2f 秒\n攻击半径：%d%s\n攻击类型：%s" % [
		hp_text,
		str(data.get("attack_damage", 0.0)),
		float(data.get("attack_cooldown", 0.0)),
		int(round(float(data.get("attack_radius", 0.0)))),
		extra_radius_line,
		str(data.get("attack_type", "单体"))
	]
	show()


# Closes the detail panel.
func close_panel() -> void:
	hide()
