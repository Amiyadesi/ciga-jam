extends Button
class_name ShaderButton
## 着色器风格按钮
##
## 职责：视觉交互（shader 动画、悬停辉光、点击波纹）
## 不负责：业务逻辑、对话触发、提示系统

const ButtonShader := preload("uid://b3o26w6ijhf1i")

@export var h_expend: float = 10
@export var v_expend: float = 5
@export var panel_style_box: StyleBox
@export_group("BBcode")
@export_multiline var bb_text: String

@onready var text_label: RichTextLabel = $Label
@onready var panel: Panel = $Panel

var _exit_tween: Tween
var _is_mouse_over: bool = false
var _original_label_modulate: Color = Color.WHITE
var _center_click: Vector2 = Vector2(0.5, 0.5)
var _center_hover: Vector2 = Vector2(0.5, 0.5)


func _ready() -> void:
	if panel_style_box != null:
		panel.add_theme_stylebox_override("panel", panel_style_box)

	text_label.text = bb_text if not bb_text.is_empty() else text
	text_label.add_theme_font_size_override("font_size", get_theme_font_size("font_size"))
	text = ""

	material = ButtonShader.duplicate()
	material.set("shader_parameter/size", size)
	material.set("shader_parameter/time1", 1.0)
	material.set("shader_parameter/time2", 0.0)
	material.set("shader_parameter/center1", _center_click)
	material.set("shader_parameter/center2", _center_hover)

	var normal_style = get_theme_stylebox("normal")
	if normal_style is StyleBoxFlat:
		material.set("shader_parameter/corner_radius", normal_style.corner_radius_top_left / size.y * 2)

	material.set("shader_parameter/color", modulate)

	pressed.connect(_on_pressed)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

	_original_label_modulate = text_label.modulate

	# 等一帧让布局稳定后再居中文字
	await get_tree().process_frame
	_center_label()


func _process(_delta: float) -> void:
	if disabled:
		modulate.a = 0.5
		return
	var local_mouse := (get_global_transform().affine_inverse() * get_global_mouse_position()) / size
	if _is_mouse_over:
		_center_hover = local_mouse
		material.set("shader_parameter/center2", _center_hover)
	material.set("shader_parameter/center1", _center_click)


# ─────────────────────────────────────────────
# 公开 API
# ─────────────────────────────────────────────

func set_bbtext(bbtext: String) -> void:
	bb_text = bbtext
	if text_label != null:
		text_label.text = bbtext
		await get_tree().process_frame
		_center_label()


func set_panel_box(style_box: StyleBox) -> void:
	panel_style_box = style_box
	if panel != null:
		panel.add_theme_stylebox_override("panel", style_box)


func reset_visuals() -> void:
	## 重置到初始视觉状态（用于对象池回收时调用）
	_is_mouse_over = false
	_center_click = Vector2(0.5, 0.5)
	_center_hover = Vector2(0.5, 0.5)
	if material:
		material.set("shader_parameter/time1", 1.0)
		material.set("shader_parameter/time2", 0.0)
		material.set("shader_parameter/glow", 0.0)
		material.set("shader_parameter/center1", _center_click)
		material.set("shader_parameter/center2", _center_hover)
	if text_label:
		text_label.modulate = _original_label_modulate
	modulate.a = 1.0


# ─────────────────────────────────────────────
# 信号处理
# ─────────────────────────────────────────────

func _on_pressed() -> void:
	$PressAudio.play()
	_center_click = (get_global_transform().affine_inverse() * get_global_mouse_position()) / size
	create_tween().tween_property(material, "shader_parameter/time1", 1.0, 0.5).from(0.0)


func _on_mouse_entered() -> void:
	if disabled:
		return
	$SelectAudio.play()
	_is_mouse_over = true
	if _exit_tween:
		_exit_tween.kill()
	create_tween().tween_property(material, "shader_parameter/glow", 2.0, 0.2)
	create_tween().tween_property(material, "shader_parameter/time2", 0.35, 0.2)
	text_label.modulate = _original_label_modulate * 2


func _on_mouse_exited() -> void:
	if disabled:
		return
	_is_mouse_over = false
	var exit_target := Vector2(0.5, 0.5) + (_center_hover - Vector2(0.5, 0.5)).normalized() * 2.0
	_exit_tween = create_tween()
	_exit_tween.parallel().tween_property(self, "_center_hover", exit_target, 0.3)
	_exit_tween.parallel().tween_property(material, "shader_parameter/time2", 0.0, 0.3)
	_exit_tween.parallel().tween_property(material, "shader_parameter/glow", 0.0, 0.2)
	_exit_tween.tween_callback(func():
		_center_hover = Vector2(0.5, 0.5)
	)
	text_label.modulate = _original_label_modulate


# ─────────────────────────────────────────────
# 内部工具
# ─────────────────────────────────────────────

func _center_label() -> void:
	if text_label != null and size.x > 0:
		text_label.position.x = (size.x / 2.0 - text_label.size.x / 2.0)


func _on_label_resized() -> void:
	if text_label != null and size < text_label.size:
		size = text_label.size + Vector2(h_expend, v_expend)
