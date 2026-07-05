@tool
class_name GrowthScreen
extends SceneManagerBackdrop
## Out-of-run growth modal backed by PlayerModule custom growth points.

const MAX_GROWTH_LEVEL: int = 5
const GROWTH_ITEMS: Array[Dictionary] = [
	{
		"key": "stamina_level",
		"row": "StaminaRow",
		"title": "体能强化",
		"effect": "最大体力 +%d",
		"effect_step": 10,
		"cost_base": 5,
		"cost_step": 5,
	},
	{
		"key": "move_speed_level",
		"row": "MoveSpeedRow",
		"title": "疾行训练",
		"effect": "移动速度 +%d%%",
		"effect_step": 5,
		"cost_base": 5,
		"cost_step": 5,
	},
	{
		"key": "attack_speed_level",
		"row": "AttackSpeedRow",
		"title": "快速施法",
		"effect": "攻击速度 +%d%%",
		"effect_step": 5,
		"cost_base": 5,
		"cost_step": 5,
	},
	{
		"key": "start_gold_level",
		"row": "StartGoldRow",
		"title": "开局补给",
		"effect": "初始金币 +%d",
		"effect_step": 500,
		"cost_base": 6,
		"cost_step": 6,
	},
]

signal return_requested

@onready var gold_label: Label = %GoldLabel
@onready var return_button: ShaderButton = %ReturnButton


# Wires growth buttons and initializes visible save data.
func _ready() -> void:
	super._ready()
	if Engine.is_editor_hint():
		return
	_configure_button_audio()
	_connect_upgrade_buttons()
	return_button.pressed.connect(return_requested.emit)
	visibility_changed.connect(_on_visibility_changed)
	refresh_from_save()


# Refreshes growth points and all upgrade rows from the active save slot.
func refresh_from_save() -> void:
	var growth_points: int = _get_growth_points()
	gold_label.text = "成长点  %d" % growth_points
	for item in GROWTH_ITEMS:
		_refresh_upgrade_row(item, growth_points)


# Compatibility entry for the original stamina-only button path.
func purchase_stamina_upgrade() -> void:
	purchase_growth_upgrade("stamina_level")


# Buys one level for the configured growth item and persists the active slot.
func purchase_growth_upgrade(growth_key: String) -> void:
	if PlayerModule.instance == null:
		return
	var item: Dictionary = _find_growth_item(growth_key)
	if item.is_empty():
		refresh_from_save()
		return
	var level: int = _get_growth_level(growth_key)
	if level >= MAX_GROWTH_LEVEL:
		refresh_from_save()
		return
	var cost: int = _get_next_cost(item, level)
	var growth_points: int = _get_growth_points()
	if growth_points < cost:
		refresh_from_save()
		return
	PlayerModule.instance.custom["growth_points"] = growth_points - cost
	PlayerModule.instance.custom[growth_key] = level + 1
	_save_slot()
	refresh_from_save()


# Refreshes data whenever the modal becomes visible.
func _on_visibility_changed() -> void:
	if visible:
		refresh_from_save()


# Connects authored upgrade row buttons by growth key.
func _connect_upgrade_buttons() -> void:
	for item in GROWTH_ITEMS:
		var row: Control = _get_growth_row(item)
		if row == null:
			push_error("GrowthScreen: missing growth row '%s'" % str(item.get("row", "")))
			continue
		var buy_button: ShaderButton = row.get_node("RowBox/BuyButton") as ShaderButton
		if buy_button == null:
			push_error("GrowthScreen: missing BuyButton under '%s'" % row.name)
			continue
		var growth_key: String = str(item.get("key", ""))
		buy_button.pressed.connect(func() -> void:
			purchase_growth_upgrade(growth_key)
		)


# Refreshes one authored upgrade row.
func _refresh_upgrade_row(item: Dictionary, growth_points: int) -> void:
	var row: Control = _get_growth_row(item)
	if row == null:
		return
	var level_label: Label = row.get_node("RowBox/TextBox/LevelLabel") as Label
	var effect_label: Label = row.get_node("RowBox/TextBox/EffectLabel") as Label
	var cost_label: Label = row.get_node("RowBox/TextBox/CostLabel") as Label
	var buy_button: ShaderButton = row.get_node("RowBox/BuyButton") as ShaderButton
	if level_label == null or effect_label == null or cost_label == null or buy_button == null:
		push_error("GrowthScreen: invalid growth row structure '%s'" % row.name)
		return
	var key: String = str(item.get("key", ""))
	var level: int = _get_growth_level(key)
	var cost: int = _get_next_cost(item, level)
	var title: String = str(item.get("title", key))
	var effect_value: int = level * int(item.get("effect_step", 0))
	level_label.text = "%s  Lv.%d/%d" % [title, level, MAX_GROWTH_LEVEL]
	effect_label.text = str(item.get("effect", "+%d")) % effect_value
	if level >= MAX_GROWTH_LEVEL:
		cost_label.text = "已达到上限"
		buy_button.disabled = true
		_set_button_text(buy_button, "已满级")
	elif growth_points < cost:
		cost_label.text = "需要成长点 %d" % cost
		buy_button.disabled = true
		_set_button_text(buy_button, "点数不足")
	else:
		cost_label.text = "需要成长点 %d" % cost
		buy_button.disabled = false
		_set_button_text(buy_button, "购买")


# Returns one authored upgrade row by item config.
func _get_growth_row(item: Dictionary) -> Control:
	var row_name: String = str(item.get("row", ""))
	if row_name.is_empty():
		return null
	return get_node_or_null("PanelRoot/OuterMargin/ShellPanel/ShellMargin/MainVBox/Body/UpgradeList/%s" % row_name) as Control


# Finds a growth item config by custom data key.
func _find_growth_item(growth_key: String) -> Dictionary:
	for item in GROWTH_ITEMS:
		if str(item.get("key", "")) == growth_key:
			return item
	return {}


# Returns the out-of-run growth points without creating a new save system.
func _get_growth_points() -> int:
	if PlayerModule.instance == null:
		return 0
	return maxi(0, int(PlayerModule.instance.custom.get("growth_points", 0)))


# Reads a permanent growth level from PlayerModule custom data.
func _get_growth_level(growth_key: String) -> int:
	if PlayerModule.instance == null:
		return 0
	return clampi(int(PlayerModule.instance.custom.get(growth_key, 0)), 0, MAX_GROWTH_LEVEL)


# Computes the next upgrade price for a configured growth item.
func _get_next_cost(item: Dictionary, level: int) -> int:
	return int(item.get("cost_base", 5)) + level * int(item.get("cost_step", 5))


# Updates ShaderButton text through its RichText-aware API.
func _set_button_text(button: ShaderButton, text: String) -> void:
	button.text = text
	if button.has_method("set_bbtext"):
		button.call("set_bbtext", text)


# Persists the active slot through SaveSystem if it is available.
func _save_slot() -> void:
	var save_system: Node = _get_save_system()
	if save_system != null and save_system.has_method("save_slot"):
		save_system.call("save_slot", 1)


# Finds the SaveSystem autoload at runtime.
func _get_save_system() -> Node:
	if get_tree() == null or get_tree().root == null:
		return null
	return get_tree().root.get_node_or_null("SaveSystem")


# 给成长界面按钮接入菜单确认音效。
func _configure_button_audio() -> void:
	var game_audio: Node = _get_game_audio()
	if game_audio != null and game_audio.has_method("setup_menu_shader_button"):
		for item in GROWTH_ITEMS:
			var row: Control = _get_growth_row(item)
			if row != null:
				var buy_button: ShaderButton = row.get_node("RowBox/BuyButton") as ShaderButton
				if buy_button != null:
					game_audio.call("setup_menu_shader_button", buy_button)
		game_audio.call("setup_menu_shader_button", return_button)
	if game_audio != null and game_audio.has_method("setup_plain_button"):
		game_audio.call("setup_plain_button", return_button, "cancel")


# Finds the GameAudio autoload at runtime.
func _get_game_audio() -> Node:
	if get_tree() == null or get_tree().root == null:
		return null
	return get_tree().root.get_node_or_null("GameAudio")
