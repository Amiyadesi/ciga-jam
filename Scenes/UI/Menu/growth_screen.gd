@tool
class_name GrowthScreen
extends SceneManagerBackdrop
## Out-of-run growth modal backed by PlayerModule slot data.

const MAX_STAMINA_LEVEL := 5

signal return_requested

@onready var gold_label: Label = %GoldLabel
@onready var level_label: Label = %LevelLabel
@onready var effect_label: Label = %EffectLabel
@onready var cost_label: Label = %CostLabel
@onready var buy_button: ShaderButton = %BuyButton
@onready var return_button: ShaderButton = %ReturnButton


# Wires growth buttons and initializes visible save data.
func _ready() -> void:
	super._ready()
	if Engine.is_editor_hint():
		return
	buy_button.pressed.connect(purchase_stamina_upgrade)
	return_button.pressed.connect(return_requested.emit)
	visibility_changed.connect(_on_visibility_changed)
	refresh_from_save()


# Refreshes gold and upgrade labels from the active save slot.
func refresh_from_save() -> void:
	var gold := _get_gold()
	var level := _get_stamina_level()
	var cost := _get_next_cost(level)
	gold_label.text = "金币  %d" % gold
	level_label.text = "体能强化  Lv.%d/%d" % [level, MAX_STAMINA_LEVEL]
	effect_label.text = "最大体力 +%d" % (level * 10)
	if level >= MAX_STAMINA_LEVEL:
		cost_label.text = "已达到上限"
		buy_button.disabled = true
		_set_button_text(buy_button, "已满级")
	elif gold < cost:
		cost_label.text = "需要金币 %d" % cost
		buy_button.disabled = true
		_set_button_text(buy_button, "金币不足")
	else:
		cost_label.text = "需要金币 %d" % cost
		buy_button.disabled = false
		_set_button_text(buy_button, "购买升级")


# Buys one stamina level and persists the active slot.
func purchase_stamina_upgrade() -> void:
	if PlayerModule.instance == null:
		return
	var level := _get_stamina_level()
	if level >= MAX_STAMINA_LEVEL:
		refresh_from_save()
		return
	var cost := _get_next_cost(level)
	if PlayerModule.instance.gold < cost:
		refresh_from_save()
		return
	PlayerModule.instance.gold -= cost
	PlayerModule.instance.custom["stamina_level"] = level + 1
	_save_slot()
	refresh_from_save()


# Refreshes data whenever the modal becomes visible.
func _on_visibility_changed() -> void:
	if visible:
		refresh_from_save()


# Returns the active slot gold without creating a new save system.
func _get_gold() -> int:
	return PlayerModule.instance.gold if PlayerModule.instance != null else 0


# Reads the permanent stamina level from PlayerModule custom data.
func _get_stamina_level() -> int:
	if PlayerModule.instance == null:
		return 0
	return clampi(int(PlayerModule.instance.custom.get("stamina_level", 0)), 0, MAX_STAMINA_LEVEL)


# Computes the next stamina upgrade price.
func _get_next_cost(level: int) -> int:
	return 5 + level * 5


# Updates ShaderButton text through its RichText-aware API.
func _set_button_text(button: ShaderButton, text: String) -> void:
	button.text = text
	if button.has_method("set_bbtext"):
		button.call("set_bbtext", text)


# Persists the active slot through SaveSystem if it is available.
func _save_slot() -> void:
	var save_system := _get_save_system()
	if save_system != null and save_system.has_method("save_slot"):
		save_system.call("save_slot", 1)


# Finds the SaveSystem autoload at runtime.
func _get_save_system() -> Node:
	if get_tree() == null or get_tree().root == null:
		return null
	return get_tree().root.get_node_or_null("SaveSystem")
