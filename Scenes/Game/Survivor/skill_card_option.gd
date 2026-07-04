class_name SkillCardOption
extends Button
## 升级三选一卡片，用来展示单条技能定义。

const SkillDb = preload("res://Scenes/Game/Survivor/skill_database.gd")

@onready var rarity_label: Label = $CardMargin/CardVBox/RarityLabel
@onready var title_label: Label = $CardMargin/CardVBox/TitleLabel
@onready var effect_label: Label = $CardMargin/CardVBox/EffectLabel
@onready var desc_label: Label = $CardMargin/CardVBox/DescriptionLabel


# 把一条技能数据渲染到卡片 UI 上。
func set_skill_data(skill: Dictionary) -> void:
	var rarity: int = int(skill.get("rarity", 1))
	set_meta("skill_id", int(skill.get("id", 0)))
	rarity_label.text = _rarity_text(rarity)
	title_label.text = str(skill.get("name", "技能"))
	effect_label.text = str(skill.get("display_description", skill.get("description", "")))
	desc_label.text = "前置：%s" % _prerequisite_text(int(skill.get("prerequisite", 0)))
	_apply_rarity_theme(rarity)


# 返回卡片顶部要显示的稀有度文案。
func _rarity_text(rarity: int) -> String:
	match rarity:
		1:
			return "普通"
		2:
			return "稀有"
		3:
			return "史诗"
		_:
			return "未知"


# 返回底部使用的前置需求摘要。
func _prerequisite_text(prerequisite: int) -> String:
	if prerequisite <= 0:
		return "无"
	var prerequisite_name: String = SkillDb.get_skill_name(prerequisite)
	return prerequisite_name if not prerequisite_name.is_empty() else "#%d" % prerequisite


# 根据稀有度给卡片主色调上色。
func _apply_rarity_theme(rarity: int) -> void:
	var title_color: Color = Color(0.98, 0.92, 0.82, 1.0)
	var accent_color: Color
	match rarity:
		1:
			accent_color = Color(0.74, 0.90, 0.98, 1.0)
		2:
			accent_color = Color(1.0, 0.82, 0.46, 1.0)
		3:
			accent_color = Color(1.0, 0.54, 0.42, 1.0)
		_:
			accent_color = Color(0.88, 0.88, 0.90, 1.0)
	rarity_label.add_theme_color_override("font_color", accent_color)
	title_label.add_theme_color_override("font_color", title_color)
	effect_label.add_theme_color_override("font_color", Color(0.94, 0.96, 0.98, 0.96))
