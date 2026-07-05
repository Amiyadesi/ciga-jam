@tool
class_name SettingScreen
extends SceneManagerBackdrop

signal thanks_requested

const SLIDER_THEME := preload("res://reousrces/settings_slider.tres")
const AUDIO_KEYS := ["master_volume", "music_volume", "sfx_volume", "ambient_volume", "screen_shake"]
const AUDIO_DEFAULTS := {
	"master_volume": 0.8,
	"music_volume": 0.8,
	"sfx_volume": 0.8,
	"ambient_volume": 0.8,
	"screen_shake": 0.5,
}
const AUDIO_HINTS := {
	"master_volume": "统一控制整体音量。先调这里，再微调其它声部。",
	"music_volume": "调整背景音乐音量。",
	"sfx_volume": "调整动作、界面反馈和机关音效音量。",
	"ambient_volume": "调整环境声和氛围声响。",
	"screen_shake": "调整爆炸等强反馈时的屏幕震动强度。设为0则禁用震动。",
}
const GAMEPLAY_ACTION_LABELS := {
	"left": "向左移动",
	"right": "向右移动",
	"up": "向上移动",
	"down": "向下移动",
	"attack": "锚点攻击",
	"sprint": "奔跑",
	"pause": "暂停",
}
const GAMEPLAY_ACTIONS: Array[String] = ["left", "right", "up", "down", "attack", "sprint", "pause"]

var is_in_menu_flag:bool

@onready var return_button: Button = %ReturnButton
@onready var audio_tab: Button = %AudioTab
@onready var controls_tab: Button = %ControlsTab
@onready var audio_page: ScrollContainer = %AudioPage
@onready var controls_page: ScrollContainer = %ControlsPage
@onready var hint_label: Label = %HintLabel
@onready var reset_audio_button: Button = %ResetAudioButton
@onready var thanks_button: Button = %ThanksButton

@onready var master_row: VBoxContainer = %MasterRow
@onready var master_slider: HSlider = %MasterSlider
@onready var master_value: Label = %MasterValue
@onready var music_row: VBoxContainer = %MusicRow
@onready var music_slider: HSlider = %MusicSlider
@onready var music_value: Label = %MusicValue
@onready var sfx_row: VBoxContainer = %SfxRow
@onready var sfx_slider: HSlider = %SfxSlider
@onready var sfx_value: Label = %SfxValue
@onready var ambient_row: VBoxContainer = %AmbientRow
@onready var ambient_slider: HSlider = %AmbientSlider
@onready var ambient_value: Label = %AmbientValue
@onready var screen_shake_row: VBoxContainer = %ScreenShakeRow
@onready var screen_shake_slider: HSlider = %ScreenShakeSlider
@onready var screen_shake_value: Label = %ScreenShakeValue
@onready var keybinding_ui: KeybindingUI = %KeybindingUI

var _audio_rows:Array[Dictionary] = []
var _current_tab:int = 0
var _ignore_ui_changes:bool
var _tab_active_style:StyleBoxFlat
var _tab_inactive_style:StyleBoxFlat
var _tab_hover_style:StyleBoxFlat
var _button_style:StyleBoxFlat
var _button_hover_style:StyleBoxFlat
var _button_pressed_style:StyleBoxFlat


func _ready() -> void:
	super._ready()
	if Engine.is_editor_hint():
		return
	_make_runtime_styles()
	_register_audio_rows()
	_connect_signals()
	_configure_button_audio()
	_sync_menu_only_controls()
	refresh_from_settings()
	_set_tab(0)
	_style_keybinding_ui()


func refresh_from_settings() -> void:
	_ignore_ui_changes = true
	for item in _audio_rows:
		var key := String(item["key"])
		var slider := item["slider"] as HSlider
		var value_label := item["value"] as Label
		slider.value = _get_setting_value(key)
		_update_value_label(value_label, slider.value)
	_ignore_ui_changes = false
	if keybinding_ui != null and keybinding_ui.has_method("refresh_all"):
		keybinding_ui.refresh_all()


func _connect_signals() -> void:
	return_button.pressed.connect(_on_return_pressed)
	thanks_button.pressed.connect(_on_thanks_pressed)
	reset_audio_button.pressed.connect(_on_reset_audio_pressed)
	audio_tab.pressed.connect(_set_tab.bind(0))
	controls_tab.pressed.connect(_set_tab.bind(1))
	visibility_changed.connect(_on_visibility_changed)
	close_modal_requested.connect(_on_return_pressed)
	for item in _audio_rows:
		var key := String(item["key"])
		var row := item["row"] as Control
		var slider := item["slider"] as HSlider
		row.mouse_entered.connect(_set_hint.bind(AUDIO_HINTS[key]))
		row.mouse_entered.connect(_highlight_audio_row.bind(row))
		slider.focus_entered.connect(_set_hint.bind(AUDIO_HINTS[key]))
		slider.focus_entered.connect(_highlight_audio_row.bind(row))
		slider.value_changed.connect(_on_audio_slider_changed.bind(key, item["value"]))


func _register_audio_rows() -> void:
	_audio_rows = [
		{"key": "master_volume", "row": master_row, "slider": master_slider, "value": master_value},
		{"key": "music_volume", "row": music_row, "slider": music_slider, "value": music_value},
		{"key": "sfx_volume", "row": sfx_row, "slider": sfx_slider, "value": sfx_value},
		{"key": "ambient_volume", "row": ambient_row, "slider": ambient_slider, "value": ambient_value},
		{"key": "screen_shake", "row": screen_shake_row, "slider": screen_shake_slider, "value": screen_shake_value},
	]
	for item in _audio_rows:
		var slider := item["slider"] as HSlider
		slider.min_value = 0.0
		slider.max_value = 1.0
		slider.step = 0.01
		slider.theme = SLIDER_THEME
		_prime_audio_row_style(item["row"] as Control)


func _set_tab(index:int) -> void:
	_current_tab = clampi(index, 0, 1)
	audio_page.visible = _current_tab == 0
	controls_page.visible = _current_tab == 1
	_style_tab(audio_tab, _current_tab == 0)
	_style_tab(controls_tab, _current_tab == 1)
	if _current_tab == 0:
		_set_hint("调整各类音量。改动会立即应用并自动保存。")
		master_slider.grab_focus()
		_highlight_audio_row(master_row)
	else:
		_set_hint("选择一个动作后按下新的按键或鼠标按钮。")
		controls_tab.grab_focus()
		_clear_audio_row_highlights()


func _style_tab(button:Button, active:bool) -> void:
	button.add_theme_stylebox_override("normal", _tab_active_style if active else _tab_inactive_style)
	button.add_theme_stylebox_override("hover", _tab_active_style if active else _tab_hover_style)
	button.add_theme_stylebox_override("pressed", _tab_active_style)
	button.add_theme_color_override("font_color", Color(1.0, 0.80, 0.42, 1.0) if active else Color(0.88, 0.87, 0.84, 0.82))
	button.add_theme_color_override("font_hover_color", Color(1.0, 0.88, 0.58, 1.0))


func _on_audio_slider_changed(value:float, key:String, value_label:Label) -> void:
	_update_value_label(value_label, value)
	if _ignore_ui_changes:
		return
	if SettingsModule.instance != null:
		SettingsModule.instance.set_value(key, value)
	var game_audio: Node = _get_game_audio()
	if game_audio != null and game_audio.has_method("refresh_runtime_volumes"):
		game_audio.call("refresh_runtime_volumes")


func _on_reset_audio_pressed() -> void:
	if SettingsModule.instance == null:
		return
	for key in AUDIO_KEYS:
		SettingsModule.instance.set_value(key, AUDIO_DEFAULTS[key])
	var game_audio: Node = _get_game_audio()
	if game_audio != null and game_audio.has_method("refresh_runtime_volumes"):
		game_audio.call("refresh_runtime_volumes")
	refresh_from_settings()
	_set_hint("音频设置已恢复默认。")


func _on_return_pressed() -> void:
	_save_global_settings()
	get_tree().paused = false
	close_modal()


func _on_thanks_pressed() -> void:
	_save_global_settings()
	thanks_requested.emit()


func _on_visibility_changed() -> void:
	_sync_menu_only_controls()
	if visible:
		refresh_from_settings()
		call_deferred("_restore_focus")
	else:
		_save_global_settings()


func _restore_focus() -> void:
	if not visible:
		return
	if _current_tab == 0:
		master_slider.grab_focus()
	else:
		controls_tab.grab_focus()


func _get_setting_value(key:String) -> float:
	if SettingsModule.instance == null:
		return float(AUDIO_DEFAULTS[key])
	return float(SettingsModule.instance.get_value(key, AUDIO_DEFAULTS[key]))


func _update_value_label(label:Label, value:float) -> void:
	label.text = "%d%%" % int(round(value * 100.0))


func _set_hint(text:String) -> void:
	hint_label.text = text


func _prime_audio_row_style(row: Control) -> void:
	var title := row.get_node_or_null("RowContent/Title") as Label
	if title != null:
		title.add_theme_color_override("font_color", Color(0.90, 0.88, 0.84, 0.92))
	var underline := row.get_node_or_null("Underline") as ColorRect
	if underline != null:
		underline.color = Color(1.0, 0.72, 0.32, 1.0)
		underline.modulate.a = 0.18


func _highlight_audio_row(active_row: Control) -> void:
	for item in _audio_rows:
		var row := item["row"] as Control
		var title := row.get_node_or_null("RowContent/Title") as Label
		var underline := row.get_node_or_null("Underline") as ColorRect
		var active := row == active_row
		if title != null:
			title.add_theme_color_override("font_color", Color(1.0, 0.90, 0.66, 1.0) if active else Color(0.90, 0.88, 0.84, 0.92))
		if underline != null:
			var target_alpha := 0.82 if active else 0.18
			var tween := create_tween()
			tween.tween_property(underline, "modulate:a", target_alpha, 0.14)


func _clear_audio_row_highlights() -> void:
	for item in _audio_rows:
		var row := item["row"] as Control
		var title := row.get_node_or_null("RowContent/Title") as Label
		var underline := row.get_node_or_null("Underline") as ColorRect
		if title != null:
			title.add_theme_color_override("font_color", Color(0.90, 0.88, 0.84, 0.92))
		if underline != null:
			underline.modulate.a = 0.18


func _save_global_settings() -> void:
	var save_system := _get_save_system()
	if save_system != null and save_system.has_method("save_global"):
		save_system.call("save_global")


func _get_save_system() -> Node:
	if get_tree() == null or get_tree().root == null:
		return null
	return get_tree().root.get_node_or_null("SaveSystem")


# 给设置界面所有按钮接入统一 UI 音效。
func _configure_button_audio() -> void:
	var game_audio: Node = _get_game_audio()
	if game_audio == null:
		return
	if game_audio.has_method("setup_ingame_shader_button"):
		game_audio.call("setup_ingame_shader_button", return_button)
		game_audio.call("setup_ingame_shader_button", thanks_button)
		game_audio.call("setup_ingame_shader_button", reset_audio_button)
	if game_audio.has_method("setup_plain_button"):
		game_audio.call("setup_plain_button", return_button, "cancel")
		game_audio.call("setup_plain_button", audio_tab)
		game_audio.call("setup_plain_button", controls_tab)


# 查找项目全局音频路由。
func _get_game_audio() -> Node:
	if get_tree() == null or get_tree().root == null:
		return null
	return get_tree().root.get_node_or_null("GameAudio")


func _make_runtime_styles() -> void:
	_tab_active_style = _make_style(Color(0.30, 0.20, 0.08, 0.34), Color(0.98, 0.72, 0.32, 0.92), 1)
	_tab_inactive_style = _make_style(Color(0.01, 0.01, 0.012, 0.34), Color(0.42, 0.38, 0.30, 0.34), 1)
	_tab_hover_style = _make_style(Color(0.18, 0.12, 0.05, 0.42), Color(0.88, 0.62, 0.28, 0.72), 1)
	_button_style = _make_style(Color(0.02, 0.018, 0.016, 0.48), Color(0.54, 0.40, 0.22, 0.72), 1)
	_button_hover_style = _make_style(Color(0.22, 0.14, 0.06, 0.58), Color(0.96, 0.70, 0.34, 0.96), 1)
	_button_pressed_style = _make_style(Color(0.70, 0.48, 0.20, 0.78), Color(1.0, 0.78, 0.42, 1.0), 1)
	_apply_button_style(return_button)
	_apply_button_style(thanks_button)


func _sync_menu_only_controls() -> void:
	if thanks_button == null:
		return
	thanks_button.visible = is_in_menu_flag
	thanks_button.disabled = not is_in_menu_flag


func _apply_button_style(button:Button) -> void:
	button.add_theme_stylebox_override("normal", _button_style)
	button.add_theme_stylebox_override("hover", _button_hover_style)
	button.add_theme_stylebox_override("pressed", _button_pressed_style)
	button.add_theme_color_override("font_color", Color(0.92, 0.92, 0.94, 1.0))
	button.add_theme_color_override("font_hover_color", Color(1.0, 0.96, 0.78, 1.0))
	button.add_theme_color_override("font_pressed_color", Color(0.06, 0.06, 0.07, 1.0))


# Restricts the rebinding page to the current survivor prototype actions.
func _style_keybinding_ui() -> void:
	if keybinding_ui == null:
		return
	keybinding_ui.action_allowlist = PackedStringArray(GAMEPLAY_ACTIONS)
	keybinding_ui.label_map = GAMEPLAY_ACTION_LABELS
	if keybinding_ui.has_method("_build_rows"):
		keybinding_ui.call("_build_rows")
	elif keybinding_ui.has_method("refresh_all"):
		keybinding_ui.refresh_all()
	_restyle_keybinding_buttons()
	keybinding_ui.child_entered_tree.connect(_on_keybinding_child_added)
	for child in keybinding_ui.get_children():
		_attach_keybinding_listener(child)


func _on_keybinding_child_added(node: Node) -> void:
	_attach_keybinding_listener(node)
	call_deferred("_restyle_keybinding_buttons")


func _attach_keybinding_listener(node: Node) -> void:
	if not (node is Node):
		return
	if not node.child_entered_tree.is_connected(_on_keybinding_descendant_added):
		node.child_entered_tree.connect(_on_keybinding_descendant_added)
	for child in node.get_children():
		_attach_keybinding_listener(child)


func _on_keybinding_descendant_added(_node: Node) -> void:
	call_deferred("_restyle_keybinding_buttons")


func _restyle_keybinding_buttons() -> void:
	if keybinding_ui == null:
		return
	_walk_and_style_buttons(keybinding_ui)


func _walk_and_style_buttons(node: Node) -> void:
	if node is Button:
		_apply_button_style(node)
	for child in node.get_children():
		_walk_and_style_buttons(child)


func _make_style(bg:Color, border:Color, border_width:int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.border_width_left = border_width
	style.border_width_top = border_width
	style.border_width_right = border_width
	style.border_width_bottom = border_width
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 14
	style.content_margin_top = 8
	style.content_margin_right = 14
	style.content_margin_bottom = 8
	return style
