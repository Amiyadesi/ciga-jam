@tool
class_name SettingScreen
extends SceneManagerBackdrop

signal thanks_requested

const SLIDER_THEME := preload("res://reousrces/settings_slider.tres")
const WINDOW_RESOLUTIONS := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]
const GENERAL_KEYS := [
	"display_mode", "borderless_enabled", "window_width", "window_height", "vsync_enabled",
	"master_volume", "music_volume", "sfx_volume", "ui_volume", "ambient_volume", "screen_shake",
]
const GENERAL_DEFAULTS := {
	"display_mode": "fullscreen",
	"borderless_enabled": false,
	"window_width": 1920,
	"window_height": 1080,
	"vsync_enabled": true,
	"master_volume": 0.8,
	"music_volume": 0.8,
	"sfx_volume": 0.8,
	"ui_volume": 0.8,
	"ambient_volume": 0.8,
	"screen_shake": 0.5,
}
const GENERAL_HINTS := {
	"display_mode": "选择全屏或固定窗口分辨率。窗口模式会立即关闭无边框显示。",
	"vsync_enabled": "开启垂直同步可减少画面撕裂。",
	"master_volume": "统一控制整体音量。先调这里，再微调其它声部。",
	"music_volume": "调整背景音乐音量。",
	"sfx_volume": "调整动作、界面反馈和机关音效音量。",
	"ui_volume": "调整按钮确认、取消和菜单反馈音效音量。",
	"ambient_volume": "调整环境声和氛围声响。",
	"screen_shake": "调整爆炸等强反馈时的屏幕震动强度。设为 0 则禁用震动。",
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

var is_in_menu_flag: bool

@onready var return_button: Button = %ReturnButton
@onready var general_tab: Button = %AudioTab
@onready var controls_tab: Button = %ControlsTab
@onready var general_page: ScrollContainer = %AudioPage
@onready var controls_page: ScrollContainer = %ControlsPage
@onready var hint_label: Label = %HintLabel
@onready var reset_general_button: Button = %ResetAudioButton
@onready var thanks_button: Button = %ThanksButton
@onready var display_mode_row: VBoxContainer = %DisplayModeRow
@onready var display_mode_option: OptionButton = %DisplayModeOption
@onready var vsync_row: VBoxContainer = %VSyncRow
@onready var vsync_toggle: CheckButton = %VSyncToggle
@onready var master_row: VBoxContainer = %MasterRow
@onready var master_slider: HSlider = %MasterSlider
@onready var master_value: Label = %MasterValue
@onready var music_row: VBoxContainer = %MusicRow
@onready var music_slider: HSlider = %MusicSlider
@onready var music_value: Label = %MusicValue
@onready var sfx_row: VBoxContainer = %SfxRow
@onready var sfx_slider: HSlider = %SfxSlider
@onready var sfx_value: Label = %SfxValue
@onready var ui_row: VBoxContainer = %UIRow
@onready var ui_slider: HSlider = %UISlider
@onready var ui_value: Label = %UIValue
@onready var ambient_row: VBoxContainer = %AmbientRow
@onready var ambient_slider: HSlider = %AmbientSlider
@onready var ambient_value: Label = %AmbientValue
@onready var screen_shake_row: VBoxContainer = %ScreenShakeRow
@onready var screen_shake_slider: HSlider = %ScreenShakeSlider
@onready var screen_shake_value: Label = %ScreenShakeValue
@onready var keybinding_ui: KeybindingUI = %KeybindingUI

var _setting_rows: Array[Dictionary] = []
var _current_tab := 0
var _ignore_ui_changes: bool
var _tab_active_style: StyleBoxFlat
var _tab_inactive_style: StyleBoxFlat
var _tab_hover_style: StyleBoxFlat
var _button_style: StyleBoxFlat
var _button_hover_style: StyleBoxFlat
var _button_pressed_style: StyleBoxFlat


# Wires the authored controls to the global settings module.
func _ready() -> void:
	super._ready()
	if Engine.is_editor_hint():
		return
	_make_runtime_styles()
	_configure_display_options()
	_register_general_rows()
	_connect_signals()
	_configure_button_audio()
	_sync_menu_only_controls()
	refresh_from_settings()
	_set_tab(0)
	_style_keybinding_ui()


# Refreshes every visible control from the persisted global settings.
func refresh_from_settings() -> void:
	_ignore_ui_changes = true
	for item in _setting_rows:
		var key := String(item["key"])
		var slider := item["slider"] as HSlider
		var value_label := item["value"] as Label
		slider.value = _get_setting_value(key)
		_update_value_label(value_label, slider.value)
	_sync_display_controls()
	_ignore_ui_changes = false
	if keybinding_ui.has_method("refresh_all"):
		keybinding_ui.refresh_all()


# Connects the authored controls once for live settings changes.
func _connect_signals() -> void:
	return_button.pressed.connect(_on_return_pressed)
	thanks_button.pressed.connect(_on_thanks_pressed)
	reset_general_button.pressed.connect(_on_reset_general_pressed)
	general_tab.pressed.connect(_set_tab.bind(0))
	controls_tab.pressed.connect(_set_tab.bind(1))
	display_mode_option.item_selected.connect(_on_display_mode_selected)
	vsync_toggle.toggled.connect(_on_vsync_toggled)
	display_mode_row.mouse_entered.connect(_set_hint.bind(GENERAL_HINTS["display_mode"]))
	vsync_row.mouse_entered.connect(_set_hint.bind(GENERAL_HINTS["vsync_enabled"]))
	visibility_changed.connect(_on_visibility_changed)
	close_modal_requested.connect(_on_return_pressed)
	for item in _setting_rows:
		var key := String(item["key"])
		var row := item["row"] as Control
		var slider := item["slider"] as HSlider
		row.mouse_entered.connect(_set_hint.bind(GENERAL_HINTS[key]))
		row.mouse_entered.connect(_highlight_general_row.bind(row))
		slider.focus_entered.connect(_set_hint.bind(GENERAL_HINTS[key]))
		slider.focus_entered.connect(_highlight_general_row.bind(row))
		slider.value_changed.connect(_on_general_slider_changed.bind(key, item["value"]))


# Adds the fixed display choices exposed by the general settings page.
func _configure_display_options() -> void:
	display_mode_option.clear()
	display_mode_option.add_item("全屏")
	for resolution in WINDOW_RESOLUTIONS:
		display_mode_option.add_item("%d x %d" % [resolution.x, resolution.y])


# Registers authored slider rows with their matching saved fields.
func _register_general_rows() -> void:
	_setting_rows = [
		{"key": "master_volume", "row": master_row, "slider": master_slider, "value": master_value},
		{"key": "music_volume", "row": music_row, "slider": music_slider, "value": music_value},
		{"key": "sfx_volume", "row": sfx_row, "slider": sfx_slider, "value": sfx_value},
		{"key": "ui_volume", "row": ui_row, "slider": ui_slider, "value": ui_value},
		{"key": "ambient_volume", "row": ambient_row, "slider": ambient_slider, "value": ambient_value},
		{"key": "screen_shake", "row": screen_shake_row, "slider": screen_shake_slider, "value": screen_shake_value},
	]
	for item in _setting_rows:
		var slider := item["slider"] as HSlider
		slider.min_value = 0.0
		slider.max_value = 1.0
		slider.step = 0.01
		slider.theme = SLIDER_THEME
		_prime_general_row_style(item["row"] as Control)


# Synchronizes display selectors after loading or restoring settings.
func _sync_display_controls() -> void:
	var display_mode := str(SettingsModule.instance.get_value("display_mode", "fullscreen"))
	if display_mode == "fullscreen":
		display_mode_option.select(0)
	else:
		var saved_resolution := Vector2i(
			int(SettingsModule.instance.get_value("window_width", 1920)),
			int(SettingsModule.instance.get_value("window_height", 1080))
		)
		display_mode_option.select(WINDOW_RESOLUTIONS.size())
		for index in WINDOW_RESOLUTIONS.size():
			if WINDOW_RESOLUTIONS[index] == saved_resolution:
				display_mode_option.select(index + 1)
				break
	vsync_toggle.button_pressed = bool(SettingsModule.instance.get_value("vsync_enabled", true))


# Switches between general settings and keybinding pages.
func _set_tab(index: int) -> void:
	_current_tab = clampi(index, 0, 1)
	general_page.visible = _current_tab == 0
	controls_page.visible = _current_tab == 1
	_style_tab(general_tab, _current_tab == 0)
	_style_tab(controls_tab, _current_tab == 1)
	if _current_tab == 0:
		_set_hint("调整显示、声音与辅助设置。改动会立即应用并自动保存。")
		display_mode_option.grab_focus()
		_clear_general_row_highlights()
	else:
		_set_hint("选择一个动作后按下新的按键或鼠标按钮。")
		controls_tab.grab_focus()
		_clear_general_row_highlights()


# Applies the active visual treatment to the selected page tab.
func _style_tab(button: Button, active: bool) -> void:
	button.add_theme_stylebox_override("normal", _tab_active_style if active else _tab_inactive_style)
	button.add_theme_stylebox_override("hover", _tab_active_style if active else _tab_hover_style)
	button.add_theme_stylebox_override("pressed", _tab_active_style)
	button.add_theme_color_override("font_color", Color(1.0, 0.80, 0.42, 1.0) if active else Color(0.88, 0.87, 0.84, 0.82))
	button.add_theme_color_override("font_hover_color", Color(1.0, 0.88, 0.58, 1.0))


# Stores one slider value and immediately updates runtime audio services.
func _on_general_slider_changed(value: float, key: String, value_label: Label) -> void:
	_update_value_label(value_label, value)
	if _ignore_ui_changes:
		return
	SettingsModule.instance.set_value(key, value)
	GameAudio.refresh_runtime_volumes()


# Applies the selected fullscreen or fixed window preset.
func _on_display_mode_selected(index: int) -> void:
	if _ignore_ui_changes:
		return
	if index == 0:
		SettingsModule.instance.set_value("display_mode", "fullscreen")
		SettingsModule.instance.set_value("borderless_enabled", false)
		return
	var resolution: Vector2i = WINDOW_RESOLUTIONS[index - 1]
	_apply_window_resolution(resolution)


# Writes an explicit window size and disables borderless presentation.
func _apply_window_resolution(resolution: Vector2i) -> void:
	SettingsModule.instance.set_value("display_mode", "windowed")
	SettingsModule.instance.set_value("borderless_enabled", false)
	SettingsModule.instance.set_value("window_width", resolution.x)
	SettingsModule.instance.set_value("window_height", resolution.y)


# Persists the VSync switch as soon as it changes.
func _on_vsync_toggled(enabled: bool) -> void:
	if _ignore_ui_changes:
		return
	SettingsModule.instance.set_value("vsync_enabled", enabled)


# Restores only general display, sound, and accessibility fields.
func _on_reset_general_pressed() -> void:
	for key in GENERAL_KEYS:
		SettingsModule.instance.set_value(key, GENERAL_DEFAULTS[key])
	GameAudio.refresh_runtime_volumes()
	refresh_from_settings()
	_set_hint("通用设置已恢复默认。")


# Closes the modal after flushing the global settings save.
func _on_return_pressed() -> void:
	_save_global_settings()
	get_tree().paused = false
	close_modal()


# Hands off from settings to the authored credits modal.
func _on_thanks_pressed() -> void:
	_save_global_settings()
	thanks_requested.emit()


# Refreshes settings while opening and persists them while closing.
func _on_visibility_changed() -> void:
	_sync_menu_only_controls()
	if visible:
		refresh_from_settings()
		call_deferred("_restore_focus")
	else:
		_save_global_settings()


# Restores keyboard focus to the active settings page.
func _restore_focus() -> void:
	if not visible:
		return
	if _current_tab == 0:
		display_mode_option.grab_focus()
	else:
		controls_tab.grab_focus()


# Reads a slider field from the registered global settings module.
func _get_setting_value(key: String) -> float:
	return float(SettingsModule.instance.get_value(key, GENERAL_DEFAULTS[key]))


# Formats slider values consistently as whole-number percentages.
func _update_value_label(label: Label, value: float) -> void:
	label.text = "%d%%" % int(round(value * 100.0))


# Updates the two-line explanation panel under the page content.
func _set_hint(text: String) -> void:
	hint_label.text = text


# Initializes the resting visual state for one general settings row.
func _prime_general_row_style(row: Control) -> void:
	var title := row.get_node_or_null("RowContent/Title") as Label
	if title != null:
		title.add_theme_color_override("font_color", Color(0.90, 0.88, 0.84, 0.92))
	var underline := row.get_node_or_null("Underline") as ColorRect
	if underline != null:
		underline.color = Color(1.0, 0.72, 0.32, 1.0)
		underline.modulate.a = 0.18


# Highlights the row currently hovered or focused by the player.
func _highlight_general_row(active_row: Control) -> void:
	for item in _setting_rows:
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


# Clears row emphasis when moving into the keybinding page.
func _clear_general_row_highlights() -> void:
	for item in _setting_rows:
		var row := item["row"] as Control
		var title := row.get_node_or_null("RowContent/Title") as Label
		var underline := row.get_node_or_null("Underline") as ColorRect
		if title != null:
			title.add_theme_color_override("font_color", Color(0.90, 0.88, 0.84, 0.92))
		if underline != null:
			underline.modulate.a = 0.18


# Persists global settings through the registered project save system.
func _save_global_settings() -> void:
	SaveSystem.save_global()


# Connects this page's buttons to the shared UI audio router.
func _configure_button_audio() -> void:
	GameAudio.setup_ingame_shader_button(return_button)
	GameAudio.setup_ingame_shader_button(thanks_button)
	GameAudio.setup_ingame_shader_button(reset_general_button)
	GameAudio.setup_plain_button(return_button, "cancel")
	GameAudio.setup_plain_button(general_tab)
	GameAudio.setup_plain_button(controls_tab)
	GameAudio.setup_plain_button(display_mode_option)
	GameAudio.setup_plain_button(vsync_toggle)


# Shows the credits shortcut only when this modal is opened from the menu.
func _sync_menu_only_controls() -> void:
	thanks_button.visible = is_in_menu_flag
	thanks_button.disabled = not is_in_menu_flag


# Builds the reusable visual styles for authored buttons and selectors.
func _make_runtime_styles() -> void:
	_tab_active_style = _make_style(Color(0.30, 0.20, 0.08, 0.34), Color(0.98, 0.72, 0.32, 0.92), 1)
	_tab_inactive_style = _make_style(Color(0.01, 0.01, 0.012, 0.34), Color(0.42, 0.38, 0.30, 0.34), 1)
	_tab_hover_style = _make_style(Color(0.18, 0.12, 0.05, 0.42), Color(0.88, 0.62, 0.28, 0.72), 1)
	_button_style = _make_style(Color(0.02, 0.018, 0.016, 0.48), Color(0.54, 0.40, 0.22, 0.72), 1)
	_button_hover_style = _make_style(Color(0.22, 0.14, 0.06, 0.58), Color(0.96, 0.70, 0.34, 0.96), 1)
	_button_pressed_style = _make_style(Color(0.70, 0.48, 0.20, 0.78), Color(1.0, 0.78, 0.42, 1.0), 1)
	_apply_button_style(return_button)
	_apply_button_style(thanks_button)
	_apply_button_style(display_mode_option)
	_apply_button_style(vsync_toggle)


# Applies the current glass-shell button appearance to one control.
func _apply_button_style(button: Button) -> void:
	button.add_theme_stylebox_override("normal", _button_style)
	button.add_theme_stylebox_override("hover", _button_hover_style)
	button.add_theme_stylebox_override("pressed", _button_pressed_style)
	button.add_theme_color_override("font_color", Color(0.92, 0.92, 0.94, 1.0))
	button.add_theme_color_override("font_hover_color", Color(1.0, 0.96, 0.78, 1.0))
	button.add_theme_color_override("font_pressed_color", Color(0.06, 0.06, 0.07, 1.0))


# Restricts the rebinding page to current survivor prototype actions.
func _style_keybinding_ui() -> void:
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


# Restyles newly-created rebinding controls after the addon rebuilds its rows.
func _on_keybinding_child_added(node: Node) -> void:
	_attach_keybinding_listener(node)
	call_deferred("_restyle_keybinding_buttons")


# Watches the addon tree for nested rebinding controls.
func _attach_keybinding_listener(node: Node) -> void:
	if not node.child_entered_tree.is_connected(_on_keybinding_descendant_added):
		node.child_entered_tree.connect(_on_keybinding_descendant_added)
	for child in node.get_children():
		_attach_keybinding_listener(child)


# Defers a restyle until an addon-owned control has entered the tree.
func _on_keybinding_descendant_added(_node: Node) -> void:
	call_deferred("_restyle_keybinding_buttons")


# Applies the template button treatment to all rebinding buttons.
func _restyle_keybinding_buttons() -> void:
	_walk_and_style_buttons(keybinding_ui)


# Traverses the authored addon subtree to style its button nodes.
func _walk_and_style_buttons(node: Node) -> void:
	if node is Button:
		_apply_button_style(node)
	for child in node.get_children():
		_walk_and_style_buttons(child)


# Creates one compact glass-frame style resource at runtime.
func _make_style(bg: Color, border: Color, border_width: int) -> StyleBoxFlat:
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
