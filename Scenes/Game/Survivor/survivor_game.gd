class_name SurvivorGame
extends Node2D
## CIGA 生存模式主场景，负责地图、UI、刷怪与局内流程。

enum GameState {
	PREPARE,
	COMBAT,
	WAVE_CLEAR,
	VICTORY,
	FAILURE,
}

const MAP_SIZE: Vector2 = Vector2(5760.0, 3240.0)
const HOUSE_POSITION: Vector2 = Vector2(520.0, 1640.0)
const PLAYER_START: Vector2 = Vector2(860.0, 1640.0)
const SLOW_TIME_SCALE: float = 0.03
const RUN_START_GOLD: int = 3000
const GROWTH_POINT_DIVISOR: int = 500
const HEAL_POTION_COST: int = 1000
const HOUSE_REPAIR_COST: int = 1000
const HOUSE_REPAIR_AMOUNT: float = 20.0
const CONTROLS_HELP_SEEN_KEY: String = "survivor_controls_help_seen"
const SPAWN_CHIME_INTERVAL: float = 4.0
const BOTTOM_VIEW_SAFE_PADDING: float = 360.0
const BOTTOM_SPAWN_VISIBLE_OFFSET: float = 240.0
const NAVIGATION_CELL_SIZE: int = 72
const ROAD_NAV_WEIGHT: float = 0.5
const ROAD_SHOULDER_NAV_WEIGHT: float = 0.82
const FOREST_NAV_WEIGHT: float = 2.35
const ROAD_WALKABLE_HALF_WIDTH: float = 390.0
const ROAD_PLACEMENT_HALF_WIDTH: float = 330.0
const ANCHOR_PLACEMENT_RADIUS: float = 84.0
const ANCHOR_PLACEMENT_GRID_SIZE: int = 64
const ANCHOR_PLACEMENT_GRID_PROBE_RADIUS: float = 42.0
const ANCHOR_PLAYER_CLEARANCE: float = 140.0
const ANCHOR_ANCHOR_CLEARANCE: float = 164.0
const MOVE_SPEED_GROWTH_PER_LEVEL: float = 0.05
const ATTACK_SPEED_GROWTH_PER_LEVEL: float = 0.05
const START_GOLD_PER_LEVEL: int = 500
const PLAYER_SCENE: PackedScene = preload("res://Scenes/Game/Survivor/player.tscn")
const ENEMY_SCENE: PackedScene = preload("res://Scenes/Game/Survivor/enemy.tscn")
const HOUSE_SCENE: PackedScene = preload("res://Scenes/Game/Survivor/house.tscn")
const ANCHOR_SCENE: PackedScene = preload("res://Scenes/Game/Survivor/magic_anchor.tscn")
const PICKUP_SCENE: PackedScene = preload("res://Scenes/Game/Survivor/pickup.tscn")
const AnchorDb = preload("res://Scenes/Game/Survivor/anchor_database.gd")
const SkillDb = preload("res://Scenes/Game/Survivor/skill_database.gd")
const HOUSE_DATA = preload("res://Scenes/Game/Survivor/Data/house_default.tres")
const ENEMY_CATALOG = preload("res://Scenes/Game/Survivor/Data/enemy_catalog.tres")
const WAVE_TABLE = preload("res://Scenes/Game/Survivor/Data/wave_table.tres")
const MENU_SCENE_PATH: String = "res://Scenes/UI/Menu/menu.tscn"
const EXIT_TRANSITION = preload("res://reousrces/scene_transitions/stage_exit_fade_to_black.tres")
const ENTER_TRANSITION = preload("res://reousrces/scene_transitions/stage_enter_fade_to_black.tres")

@export var run_slot: int = 1

@onready var world: Node2D = $World
@onready var ground: Polygon2D = $World/Ground
@onready var map_background: Sprite2D = $World/MapBackground
@onready var road_container: Node2D = $World/Roads
@onready var boundary_container: Node2D = $World/Boundaries
@onready var anchor_container: Node2D = $World/Anchors
@onready var enemy_container: Node2D = $World/Enemies
@onready var projectile_container: Node2D = $World/Projectiles
@onready var pickup_container: Node2D = $World/Pickups
@onready var placement_preview: Node2D = $World/PlacementPreview
@onready var preview_range: Sprite2D = $World/PlacementPreview/PreviewRange
@onready var preview_visual: Polygon2D = $World/PlacementPreview/PreviewVisual
@onready var preview_sprite: AnimatedSprite2D = $World/PlacementPreview/PreviewSprite
@onready var mid_point: Node2D = $World/MidPoint
@onready var camera: Camera2D = $Camera2D
@onready var low_health_overlay: ColorRect = $HUD/Root/LowHealthOverlay
@onready var gold_label: Label = $HUD/Root/GoldLabel
@onready var hp_orb: Control = $HUD/Root/HpOrb
@onready var wave_label: Label = $HUD/Root/WaveLabel
@onready var hotbar: Control = $HUD/Root/Hotbar
@onready var skill_summary_panel: PanelContainer = $HUD/Root/SkillSummaryPanel
@onready var skill_summary_label: Label = $HUD/Root/SkillSummaryPanel/Margin/VBox/SkillSummaryLabel
@onready var level_up_button: Button = $HUD/Root/LevelUpButton
@onready var anchor_detail_panel: Control = $HUD/Root/AnchorDetailPanel
@onready var house_detail_panel: Control = $HUD/Root/HouseDetailPanel
@onready var recycle_dialog: Control = $HUD/Root/AnchorRecycleDialog
@onready var level_up_panel: Control = $HUD/Root/LevelUpPanel
@onready var exp_progress_bar: ProgressBar = $HUD/Root/ExpProgressBar
@onready var exp_value_label: Label = $HUD/Root/ExpProgressBar/ValueLabel
@onready var center_notice_label: Label = $HUD/Root/CenterNoticeLabel
@onready var pause_screen: Control = $HUD/PauseScreen
@onready var setting_screen: Control = $HUD/SettingScreen
@onready var failure_screen: Control = $HUD/FailureScreen
@onready var controls_help_panel: Control = $HUD/ControlsHelpPanel

var _state: GameState = GameState.PREPARE
var _player: Node2D
var _house: Node2D
var _kills: int = 0
var _run_gold: int = RUN_START_GOLD
var _growth_settled: bool = false
var _wave_index: int = 0
var _spawn_queue: Array[Dictionary] = []
var _spawn_elapsed_time: float = 0.0
var _spawn_chime_times: Dictionary = {}
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _map_seed: int = 0
var _selected_anchor_id: String = ""
var _exiting: bool = false
var _settings_from_pause: bool = false
var _pending_level_up: bool = false
var _screen_shake_time: float = 0.0
var _screen_shake_strength: float = 0.0
var _screen_shake_total_time: float = 0.0
var _camera_base_position: Vector2 = Vector2.ZERO
var _run_modifiers: Dictionary = {}
var _center_notice_tween: Tween
var _pending_pickups: Array[Dictionary] = []
var _navigation_grid: AStarGrid2D
var _direct_navigation_grid: AStarGrid2D
var _navigation_grid_size: Vector2i = Vector2i.ZERO
var _controls_help_paused_tree: bool = false
var _auto_repair_timer: float = 0.0
var _anchor_placement_origin: Vector2 = Vector2.ZERO
var _anchor_placement_grid_size: Vector2i = Vector2i.ZERO
var _anchor_placement_reachable_cells: Dictionary = {}


# 构建地图、实体和 HUD，并连接所有局内流程。
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	get_tree().paused = false
	Engine.time_scale = 1.0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	SkillDb.validate()
	_prepare_save_slot()
	_run_gold = _get_run_start_gold()
	_setup_world()
	_spawn_house()
	_spawn_player()
	_setup_camera()
	_connect_ui()
	set_game_state(GameState.PREPARE)
	_update_hud()
	_play_enter_transition()
	_maybe_open_controls_help()


# 每帧驱动放置预览、掉落补发和波次收尾检查。
func _process(delta: float) -> void:
	_update_placement_preview()
	_update_anchor_upgrade_affordances()
	_flush_pending_pickups()
	_update_screen_shake(delta)
	_update_auto_repair(delta)
	if _exiting or _state != GameState.COMBAT:
		return
	_update_spawn_queue(delta)
	_check_wave_completion()


# 处理暂停、慢速面板关闭和放置点击输入。
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		_handle_pause_pressed()
		get_viewport().set_input_as_handled()
		return
	if _state == GameState.PREPARE or _state == GameState.COMBAT or _state == GameState.WAVE_CLEAR:
		if event is InputEventMouseButton:
			var mouse_event: InputEventMouseButton = event as InputEventMouseButton
			if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
				_handle_world_left_click()
				get_viewport().set_input_as_handled()
			elif mouse_event.button_index == MOUSE_BUTTON_RIGHT and mouse_event.pressed:
				_clear_anchor_selection()
				get_viewport().set_input_as_handled()


# 离开场景时恢复全局状态并写回存档。
func _exit_tree() -> void:
	Engine.time_scale = 1.0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_settle_growth_points_once()
	_save_slot()


# 切换局内状态，并同步热栏和 HUD。
func set_game_state(new_state: GameState) -> void:
	_state = new_state
	var total_waves: int = _get_total_waves()
	var current_wave: int = clampi(_wave_index + 1, 1, total_waves)
	var game_audio: Node = _get_game_audio()
	match _state:
		GameState.PREPARE:
			Engine.time_scale = 1.0
			get_tree().paused = false
			_apply_hotbar_wave_state(true, current_wave, total_waves)
			if game_audio != null:
				game_audio.call("play_prepare_music")
		GameState.COMBAT:
			Engine.time_scale = 1.0
			get_tree().paused = false
			_apply_hotbar_wave_state(false, current_wave, total_waves)
			if game_audio != null:
				game_audio.call("play_combat_music")
				game_audio.call("play_spawn_chime")
		GameState.WAVE_CLEAR:
			Engine.time_scale = 1.0
			get_tree().paused = false
			_apply_hotbar_wave_state(true, clampi(_wave_index + 1, 1, total_waves), total_waves)
			if game_audio != null:
				game_audio.call("play_prepare_music")
		GameState.VICTORY:
			Engine.time_scale = 1.0
			_apply_hotbar_wave_state(false, total_waves, total_waves)
			if game_audio != null:
				game_audio.call("stop_music", 0.35)
			var gained_points: int = _settle_growth_points_once()
			_save_slot()
			_open_result_screen(true, gained_points)
			get_tree().paused = true
		GameState.FAILURE:
			Engine.time_scale = 1.0
			_apply_hotbar_wave_state(false, current_wave, total_waves)
			if game_audio != null:
				game_audio.call("stop_music", 0.2)
	_refresh_hotbar()
	_update_hud()


# 初始化或读取当前存档槽，不覆盖已有金币。
func _prepare_save_slot() -> void:
	var save_system: Node = _get_save_system()
	if save_system == null:
		_rng.randomize()
		_map_seed = int(_rng.randi())
		return
	if save_system.has_method("slot_exists") and bool(save_system.call("slot_exists", run_slot)):
		save_system.call("load_slot", run_slot)
	elif save_system.has_method("new_game"):
		save_system.call("new_game", run_slot)
	if PlayerModule.instance != null:
		PlayerModule.instance.scene_path = scene_file_path
		var created_map_seed: bool = not PlayerModule.instance.custom.has("survivor_map_seed")
		_map_seed = _ensure_map_seed()
		_rng.seed = int(_map_seed)
		if created_map_seed:
			_save_slot()


# 创建地面、道路、边界和树林障碍。
func _setup_world() -> void:
	var visual_bottom: float = MAP_SIZE.y + BOTTOM_VIEW_SAFE_PADDING
	ground.polygon = PackedVector2Array([
		Vector2.ZERO,
		Vector2(MAP_SIZE.x, 0.0),
		Vector2(MAP_SIZE.x, visual_bottom),
		Vector2(0.0, visual_bottom),
	])
	ground.color = Color(0.17, 0.33, 0.19, 1.0)
	_configure_roads()
	_create_boundaries()
	call_deferred("_rebuild_anchor_placement_area")
	placement_preview.visible = false


# 用折线临时绘制策划草图里的道路。
func _configure_roads() -> void:
	var paths: Array[PackedVector2Array] = _get_road_paths()
	for i in range(paths.size()):
		var line: Line2D = road_container.get_node("Road%d" % (i + 1)) as Line2D
		if line == null:
			continue
		line.points = paths[i]
		line.width = 4.0
		line.default_color = Color(0.42, 0.34, 0.25, 0.0)
		line.visible = false


# 配置地图四周的空气墙。
func _create_boundaries() -> void:
	_configure_boundary("NorthWall", Vector2(MAP_SIZE.x * 0.5, -32.0), Vector2(MAP_SIZE.x + 128.0, 64.0))
	_configure_boundary("SouthWall", Vector2(MAP_SIZE.x * 0.5, MAP_SIZE.y + 32.0), Vector2(MAP_SIZE.x + 128.0, 64.0))
	_configure_boundary("WestWall", Vector2(-32.0, (MAP_SIZE.y + BOTTOM_VIEW_SAFE_PADDING) * 0.5), Vector2(64.0, MAP_SIZE.y + BOTTOM_VIEW_SAFE_PADDING + 128.0))
	_configure_boundary("EastWall", Vector2(MAP_SIZE.x + 32.0, (MAP_SIZE.y + BOTTOM_VIEW_SAFE_PADDING) * 0.5), Vector2(64.0, MAP_SIZE.y + BOTTOM_VIEW_SAFE_PADDING + 128.0))


# 把尺寸和位置写入单个边界碰撞体。
func _configure_boundary(boundary_name: String, center: Vector2, size: Vector2) -> void:
	var body: StaticBody2D = boundary_container.get_node(boundary_name) as StaticBody2D
	if body == null:
		push_error("SurvivorGame: missing boundary '%s'" % boundary_name)
		return
	var collision: CollisionShape2D = body.get_node("CollisionShape2D") as CollisionShape2D
	var shape: RectangleShape2D = collision.shape as RectangleShape2D
	if shape == null:
		shape = RectangleShape2D.new()
	else:
		shape = shape.duplicate() as RectangleShape2D
	collision.shape = shape
	shape.size = size
	body.global_position = center


# 生成被守护的房子。
func _spawn_house() -> void:
	_house = HOUSE_SCENE.instantiate() as Node2D
	if _house.has_method("set"):
		_house.set("data", HOUSE_DATA)
	world.add_child(_house)
	_house.global_position = HOUSE_POSITION
	_house.connect("health_changed", _on_house_health_changed)
	_house.connect("died", _on_house_died)
	_house.connect("open_detail_requested", _on_house_detail_requested)


# 生成玩家并连接战斗相关回调。
func _spawn_player() -> void:
	_player = PLAYER_SCENE.instantiate() as Node2D
	world.add_child(_player)
	_player.global_position = PLAYER_START
	_player.connect("health_changed", _on_player_health_changed)
	_player.connect("died", _on_player_died)
	_player.connect("exp_changed", _on_player_exp_changed)
	_player.connect("level_ready", _on_player_level_ready)
	_player.call("apply_growth_modifiers", _get_stamina_growth_level(), _get_move_speed_growth_level(), _get_attack_speed_growth_level())
	if PlayerModule.instance != null:
		var run_max_hp: int = maxi(1, int(PlayerModule.instance.max_hp))
		PlayerModule.instance.max_hp = run_max_hp
		PlayerModule.instance.hp = run_max_hp
		_player.call("apply_saved_health", run_max_hp, run_max_hp)
	_sync_run_modifiers_from_player()


# 设置跟随玩家的有边界相机。
func _setup_camera() -> void:
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = int(MAP_SIZE.x)
	camera.limit_bottom = int(MAP_SIZE.y + BOTTOM_VIEW_SAFE_PADDING)
	camera.global_position = _player.global_position
	camera.make_current()
	camera.reparent(_player)
	camera.position = Vector2.ZERO
	_camera_base_position = Vector2.ZERO


# 连接场景里已经摆好的 UI 与弹窗逻辑。
func _connect_ui() -> void:
	pause_screen.process_mode = Node.PROCESS_MODE_ALWAYS
	setting_screen.process_mode = Node.PROCESS_MODE_ALWAYS
	failure_screen.process_mode = Node.PROCESS_MODE_ALWAYS
	controls_help_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	hotbar.connect("anchor_selected", _on_hotbar_anchor_selected)
	hotbar.connect("wave_start_pressed", _on_wave_start_pressed)
	hotbar.connect("heal_pressed", _on_hotbar_heal_pressed)
	level_up_button.pressed.connect(_on_level_up_button_pressed)
	anchor_detail_panel.connect("closed", _on_anchor_detail_closed)
	anchor_detail_panel.connect("upgrade_requested", _on_anchor_upgrade_requested)
	anchor_detail_panel.connect("recycle_requested", _on_anchor_recycle_requested)
	house_detail_panel.connect("closed", _on_house_detail_closed)
	house_detail_panel.connect("repair_requested", _on_house_repair_requested)
	recycle_dialog.connect("confirmed", _on_anchor_recycle_confirmed)
	recycle_dialog.connect("cancelled", _on_anchor_recycle_cancelled)
	level_up_panel.connect("option_selected", _on_level_up_option_selected)
	pause_screen.connect("continue_pressed", _on_pause_continue_pressed)
	pause_screen.connect("setting_pressed", _on_pause_setting_pressed)
	pause_screen.connect("quit_pressed", _on_pause_quit_pressed)
	failure_screen.connect("retry_pressed", _on_failure_retry_pressed)
	failure_screen.connect("menu_pressed", _on_failure_menu_pressed)
	controls_help_panel.connect("dismissed", _on_controls_help_dismissed)
	setting_screen.visibility_changed.connect(_on_setting_visibility_changed)
	setting_screen.set("is_in_menu_flag", false)
	pause_screen.visible = false
	setting_screen.visible = false
	failure_screen.visible = false
	controls_help_panel.visible = false
	house_detail_panel.visible = false
	level_up_button.visible = false
	recycle_dialog.visible = false
	skill_summary_panel.visible = false
	if low_health_overlay != null:
		low_health_overlay.visible = false
		if low_health_overlay.material is ShaderMaterial:
			(low_health_overlay.material as ShaderMaterial).set_shader_parameter("intensity", 0.0)
	if center_notice_label != null:
		center_notice_label.visible = false
		center_notice_label.modulate.a = 0.0
	_refresh_hotbar()


# 开始当前波次，不额外改动局外存档进度。
func _on_wave_start_pressed() -> void:
	if _state != GameState.PREPARE and _state != GameState.WAVE_CLEAR:
		return
	if _wave_index >= _get_total_waves():
		set_game_state(GameState.VICTORY)
		return
	_spawn_queue = _build_wave_queue(_wave_index)
	_spawn_elapsed_time = 0.0
	_spawn_chime_times.clear()
	_clear_anchor_selection()
	set_game_state(GameState.COMBAT)
	var wave_info: Dictionary = _get_wave_display_data(_wave_index)
	var notice: String = str(wave_info.get("name", "战斗开始"))
	var description: String = str(wave_info.get("description", ""))
	if not description.is_empty():
		notice += "：%s" % description
	_show_center_notice(notice)


# 记录热栏当前选中的锚点类型。
func _on_hotbar_anchor_selected(anchor_id: String) -> void:
	_selected_anchor_id = anchor_id
	_refresh_hotbar()


# 使用热栏血瓶，消耗本局金币并回满玩家。
func _on_hotbar_heal_pressed() -> void:
	if not _can_use_heal_potion():
		_refresh_hotbar()
		return
	if not _spend_run_gold(HEAL_POTION_COST):
		_refresh_hotbar()
		return
	_player.call("heal_to_full")
	_show_center_notice("生命已回满")
	_refresh_hotbar()
	_update_hud()


# 打开三选一卡牌面板，并进入慢速时间。
func _on_level_up_button_pressed() -> void:
	if not is_instance_valid(_player) or int(_player.get("pending_level_ups")) <= 0:
		return
	var selected_skill_ids: Array[int] = []
	for item in _player.get("selected_skill_ids") as Array:
		selected_skill_ids.append(int(item))
	var options: Array[Dictionary] = SkillDb.get_available_options({"selected_skill_ids": selected_skill_ids}, 3)
	if options.is_empty():
		_pending_level_up = false
		level_up_button.visible = false
		return
	Engine.time_scale = SLOW_TIME_SCALE
	level_up_panel.call("open_options", options)
	level_up_button.visible = false


# 结算一次技能选择，并恢复正确的时间流速。
func _on_level_up_option_selected(skill_id: int) -> void:
	level_up_panel.call("close_panel")
	if is_instance_valid(_player):
		_player.call("level_up_with_skill", skill_id)
	_sync_run_modifiers_from_player()
	_pending_level_up = is_instance_valid(_player) and int(_player.get("pending_level_ups")) > 0
	level_up_button.visible = _pending_level_up
	_restore_slow_time_if_clear()
	_update_anchor_upgrade_affordances()
	if anchor_detail_panel.visible:
		anchor_detail_panel.call("refresh_current_anchor")
	_update_hud()


# 打开锚点详情并进入慢速时间。
func _on_anchor_detail_requested(anchor: Node) -> void:
	if _state == GameState.FAILURE:
		return
	if house_detail_panel.visible:
		house_detail_panel.call("close_panel")
	recycle_dialog.call("close_dialog")
	anchor_detail_panel.call("open_for_anchor", anchor)
	Engine.time_scale = SLOW_TIME_SCALE


# 关闭锚点详情，并在没有其他慢速面板时恢复时间。
func _on_anchor_detail_closed() -> void:
	anchor_detail_panel.call("close_panel")
	recycle_dialog.call("close_dialog")
	_restore_slow_time_if_clear()


# 打开房子详情并进入慢速时间。
func _on_house_detail_requested(house: Node) -> void:
	if _state == GameState.FAILURE:
		return
	if anchor_detail_panel.visible:
		anchor_detail_panel.call("close_panel")
	recycle_dialog.call("close_dialog")
	house_detail_panel.call("open_for_house", house)
	house_detail_panel.call("refresh_current_house", _get_gold())
	Engine.time_scale = SLOW_TIME_SCALE


# 关闭房子详情，并在没有其他慢速面板时恢复时间。
func _on_house_detail_closed() -> void:
	house_detail_panel.call("close_panel")
	_restore_slow_time_if_clear()


# 消耗本局金币修补房子。
func _on_house_repair_requested(house: Node) -> void:
	if not is_instance_valid(house):
		return
	if _get_gold() < HOUSE_REPAIR_COST:
		_show_center_notice("金币不足")
		house_detail_panel.call("refresh_current_house", _get_gold())
		return
	if not house.has_method("repair") or not bool(house.call("repair", HOUSE_REPAIR_AMOUNT)):
		_show_center_notice("房子不需要修补")
		house_detail_panel.call("refresh_current_house", _get_gold())
		return
	if not _spend_run_gold(HOUSE_REPAIR_COST):
		return
	house_detail_panel.call("refresh_current_house", _get_gold())
	_update_hud()


# 金币足够时升级锚点。
func _on_anchor_upgrade_requested(anchor: Node) -> void:
	if not is_instance_valid(anchor):
		return
	var cost: int = AnchorDb.get_upgrade_cost(str(anchor.get("anchor_id")), int(anchor.get("level")))
	if cost <= 0:
		_show_center_notice("该魔法锚点已满级")
		return
	if _get_gold() < cost:
		_show_center_notice("金币不足")
		anchor_detail_panel.call("refresh_current_anchor")
		return
	if not _spend_run_gold(cost):
		return
	if not bool(anchor.call("upgrade")):
		_add_run_gold(cost)
		_show_center_notice("升级失败")
		return
	_apply_run_modifiers_to_anchor(anchor)
	_refresh_hotbar()
	anchor_detail_panel.call("refresh_current_anchor")
	_update_anchor_upgrade_affordances()
	_update_hud()


# 打开锚点拆除确认框，不额外触发新的慢速来源。
func _on_anchor_recycle_requested(anchor: Node) -> void:
	if not is_instance_valid(anchor):
		return
	recycle_dialog.call("open_for_anchor", anchor)


# 确认拆除后返还金币并移除锚点。
func _on_anchor_recycle_confirmed(anchor: Node) -> void:
	if not is_instance_valid(anchor):
		_restore_slow_time_if_clear()
		return
	var refund: int = int(round(float(anchor.call("get_current_price")) * 0.6))
	_add_run_gold(refund)
	if anchor_detail_panel.visible:
		anchor_detail_panel.call("close_panel")
	anchor.queue_free()
	_refresh_hotbar()
	_update_anchor_upgrade_affordances()
	_restore_slow_time_if_clear()
	_show_center_notice("拆除完成，返还 %d 金币" % refund)
	_update_hud()


# 取消拆除后恢复到当前应有的时间流速。
func _on_anchor_recycle_cancelled() -> void:
	_restore_slow_time_if_clear()


# 同步玩家血量到存档模块，并刷新 HUD。
func _on_player_health_changed(current_hp: int, max_hp: int) -> void:
	if PlayerModule.instance != null:
		PlayerModule.instance.hp = current_hp
		PlayerModule.instance.max_hp = max_hp
	_update_hud()


# 玩家死亡后判负。
func _on_player_died() -> void:
	_fail_run("玩家倒下了。")


# 房子血量变化时刷新 HUD。
func _on_house_health_changed(_current_hp: int, _max_hp: int) -> void:
	if house_detail_panel.visible:
		house_detail_panel.call("refresh_current_house", _get_gold())
	_update_hud()


# 房子被摧毁后判负。
func _on_house_died() -> void:
	_fail_run("房子被魔物摧毁了。")


# 经验变化后刷新经验条和升级按钮。
func _on_player_exp_changed(_current_exp: int, _required_exp: int, _level: int) -> void:
	_pending_level_up = is_instance_valid(_player) and int(_player.get("pending_level_ups")) > 0
	level_up_button.visible = _pending_level_up and not level_up_panel.visible
	_update_hud()


# 标记当前还有待选升级。
func _on_player_level_ready() -> void:
	_pending_level_up = is_instance_valid(_player) and int(_player.get("pending_level_ups")) > 0
	level_up_button.visible = _pending_level_up and not level_up_panel.visible


# 敌人死亡后记录击杀，并把掉落放进延迟生成队列。
func _on_enemy_died(enemy: Node, gold_reward: int, exp_reward: int) -> void:
	_kills += 1
	if enemy is Node2D:
		var pos: Vector2 = (enemy as Node2D).global_position
		_pending_pickups.append({"kind": "gold", "amount": gold_reward, "position": pos + Vector2(-16.0, 0.0)})
		_pending_pickups.append({"kind": "exp", "amount": exp_reward, "position": pos + Vector2(16.0, 0.0)})
	_update_hud()


# 结算拾取物效果，并同步金币或经验。
func _on_pickup_collected(kind: String, amount: int) -> void:
	var final_amount: int = _scale_reward_amount(kind, amount)
	if kind == "gold":
		_add_run_gold(final_amount)
	elif kind == "exp" and is_instance_valid(_player):
		_player.call("add_exp", final_amount)
	_refresh_hotbar()
	if anchor_detail_panel.visible:
		anchor_detail_panel.call("refresh_current_anchor")
	_update_anchor_upgrade_affordances()
	_update_hud()


# 根据当前界面状态处理 Escape。
func _handle_pause_pressed() -> void:
	if controls_help_panel.visible:
		_on_controls_help_dismissed()
		return
	if recycle_dialog.visible:
		recycle_dialog.call("close_dialog")
		_restore_slow_time_if_clear()
		return
	if anchor_detail_panel.visible:
		_on_anchor_detail_closed()
		return
	if house_detail_panel.visible:
		_on_house_detail_closed()
		return
	if level_up_panel.visible:
		return
	if setting_screen.visible:
		setting_screen.call("close_modal")
		return
	if pause_screen.visible:
		_resume_game()
		return
	if failure_screen.visible or _state == GameState.FAILURE or _state == GameState.VICTORY:
		return
	Engine.time_scale = 1.0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	pause_screen.call("open_modal")
	get_tree().paused = true


# 从暂停面板回到游戏。
func _on_pause_continue_pressed() -> void:
	_resume_game()


# 从暂停面板进入设置，并保留暂停上下文。
func _on_pause_setting_pressed() -> void:
	_settings_from_pause = true
	pause_screen.call("close_modal")
	setting_screen.call("open_modal")
	get_tree().paused = true


# 从暂停面板保存并返回主菜单。
func _on_pause_quit_pressed() -> void:
	_return_to_menu()


# 从失败界面重开本局。
func _on_failure_retry_pressed() -> void:
	_retry_run()


# 从失败界面返回菜单。
func _on_failure_menu_pressed() -> void:
	_return_to_menu()


# 设置面板关闭后，如有需要重新打开暂停界面。
func _on_setting_visibility_changed() -> void:
	if setting_screen.visible or _exiting or _state == GameState.FAILURE or _state == GameState.VICTORY:
		return
	if _settings_from_pause:
		_settings_from_pause = false
		pause_screen.call("open_modal")
		get_tree().paused = true


# 关闭暂停界面并恢复游戏。
func _resume_game() -> void:
	if _state == GameState.FAILURE or _state == GameState.VICTORY:
		return
	pause_screen.call("close_modal")
	get_tree().paused = false
	_restore_slow_time_if_clear()


# 首次进入战斗时显示一次键位说明，并临时暂停世界。
func _maybe_open_controls_help() -> void:
	if controls_help_panel == null or _has_seen_controls_help():
		return
	Engine.time_scale = 1.0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_controls_help_paused_tree = not get_tree().paused
	controls_help_panel.call("open_panel")
	get_tree().paused = true


# 关闭首次键位说明并写入当前槽位，避免下次进入重复显示。
func _on_controls_help_dismissed() -> void:
	if controls_help_panel.visible:
		controls_help_panel.call("close_panel")
	_mark_controls_help_seen()
	if _controls_help_paused_tree and _state != GameState.FAILURE and _state != GameState.VICTORY:
		get_tree().paused = false
	_controls_help_paused_tree = false
	_restore_slow_time_if_clear()


# 判断当前槽位是否已经看过新手键位面板。
func _has_seen_controls_help() -> bool:
	if PlayerModule.instance == null:
		return false
	return bool(PlayerModule.instance.custom.get(CONTROLS_HELP_SEEN_KEY, false))


# 标记新手键位面板已读，并通过现有 SaveSystem 落盘。
func _mark_controls_help_seen() -> void:
	if PlayerModule.instance == null:
		return
	if bool(PlayerModule.instance.custom.get(CONTROLS_HELP_SEEN_KEY, false)):
		return
	PlayerModule.instance.custom[CONTROLS_HELP_SEEN_KEY] = true
	_save_slot()


# 写回当前进度并切回菜单场景。
func _return_to_menu() -> void:
	if _exiting:
		return
	_exiting = true
	Engine.time_scale = 1.0
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_reset_saved_health_for_next_run()
	_settle_growth_points_once()
	_save_slot()
	await _change_scene_with_transition(MENU_SCENE_PATH)


# 通过过场重载当前战斗场景。
func _retry_run() -> void:
	if _exiting:
		return
	_exiting = true
	Engine.time_scale = 1.0
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_reset_saved_health_for_next_run()
	_settle_growth_points_once()
	_save_slot()
	await _reload_scene_with_transition()


# 本局失败时关闭交互并打开失败界面。
func _fail_run(reason: String) -> void:
	if _state == GameState.FAILURE:
		return
	set_game_state(GameState.FAILURE)
	_spawn_queue.clear()
	_spawn_elapsed_time = 0.0
	placement_preview.visible = false
	anchor_detail_panel.call("close_panel")
	house_detail_panel.call("close_panel")
	recycle_dialog.call("close_dialog")
	level_up_panel.call("close_panel")
	level_up_button.visible = false
	_reset_saved_health_for_next_run()
	var gained_points: int = _settle_growth_points_once()
	_save_slot()
	_open_result_screen(false, gained_points)
	get_tree().paused = true
	_show_center_notice(reason)


# 按波次队列持续刷出敌人。
func _update_spawn_queue(delta: float) -> void:
	if _spawn_queue.is_empty():
		return
	_spawn_elapsed_time += delta
	while not _spawn_queue.is_empty():
		var next_spawn_time: float = float(_spawn_queue[0].get("spawn_time", 0.0))
		if next_spawn_time > _spawn_elapsed_time:
			return
		var entry: Dictionary = _spawn_queue.pop_front()
		_spawn_enemy(entry)


# 当计划刷怪和场上敌人都清空时结束本波。
func _check_wave_completion() -> void:
	if not _spawn_queue.is_empty():
		return
	if get_tree().get_nodes_in_group("enemies").size() > 0:
		return
	_wave_index += 1
	if _wave_index >= _get_total_waves():
		set_game_state(GameState.VICTORY)
	else:
		set_game_state(GameState.WAVE_CLEAR)


# 从一条波次配置实例化一个敌人。
func _spawn_enemy(entry: Dictionary) -> void:
	var enemy_id: String = str(entry.get("enemy_id", "slime_blue"))
	var level: int = int(entry.get("level", 1))
	var runtime: Dictionary = ENEMY_CATALOG.call("get_runtime_stats", enemy_id, level)
	if runtime.is_empty():
		return
	var enemy: CharacterBody2D = ENEMY_SCENE.instantiate() as CharacterBody2D
	enemy_container.add_child(enemy)
	var spawn_points: Array[Vector2] = _get_spawn_points()
	var spawn_index: int = int(entry.get("spawn", 0)) % spawn_points.size()
	var spawn_point: Vector2 = _get_enemy_spawn_position(spawn_index)
	enemy.global_position = spawn_point
	enemy.call(
		"setup",
		runtime,
		level,
		_house,
		_player,
		Callable(self, "_get_anchor_nodes"),
		Callable(self, "_spawn_summoned_pack"),
		Callable(self, "_get_enemy_navigation_path")
	)
	if enemy.has_method("configure_route"):
		enemy.call("configure_route", spawn_index, _get_enemy_route(spawn_index), Callable(self, "_get_enemy_return_path"))
	enemy.connect("died", _on_enemy_died)
	_play_spawn_chime_for_spawn_index(spawn_index)


# 在实际刷新点出怪时播放提示音，并按刷新点节流。
func _play_spawn_chime_for_spawn_index(spawn_index: int) -> void:
	var key: String = str(spawn_index)
	var last_time: float = float(_spawn_chime_times.get(key, -SPAWN_CHIME_INTERVAL))
	if _spawn_elapsed_time - last_time < SPAWN_CHIME_INTERVAL:
		return
	_spawn_chime_times[key] = _spawn_elapsed_time
	var game_audio: Node = _get_game_audio()
	if game_audio != null:
		game_audio.call("play_spawn_chime")


# 实例化一个掉落物，并连接拾取信号。
func _spawn_pickup(kind: String, amount: int, pickup_position: Vector2) -> void:
	var pickup: Area2D = PICKUP_SCENE.instantiate() as Area2D
	pickup_container.call_deferred("add_child",pickup)
	pickup.global_position = pickup_position
	pickup.call("setup", kind, amount, _player)
	pickup.connect("collected", _on_pickup_collected)


# 把上一帧记录的掉落延迟到空闲阶段再真正生成，避开 physics flush。
func _flush_pending_pickups() -> void:
	if _pending_pickups.is_empty():
		return
	var queued: Array[Dictionary] = _pending_pickups.duplicate(true)
	_pending_pickups.clear()
	for item in queued:
		_spawn_pickup(str(item.get("kind", "gold")), int(item.get("amount", 1)), item.get("position", Vector2.ZERO) as Vector2)


# 把当前波次配置展开成按时间排序的刷怪队列。
func _build_wave_queue(wave: int) -> Array[Dictionary]:
	var wave_data: Dictionary = WAVE_TABLE.call("get_wave", wave)
	var specs: Array = wave_data.get("entries", []) as Array
	var queue: Array[Dictionary] = []
	for spec in specs:
		if not (spec is Dictionary):
			continue
		var entry: Dictionary = spec as Dictionary
		var count: int = maxi(1, int(entry.get("count", 1)))
		var delay: float = maxf(0.0, float(entry.get("delay", 0.0)))
		var interval: float = maxf(0.01, float(entry.get("interval", 0.6)))
		for i in range(count):
			var expanded: Dictionary = entry.duplicate(true)
			expanded["spawn_time"] = delay + interval * float(i)
			queue.append(expanded)
	queue.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_time: float = float(a.get("spawn_time", 0.0))
		var b_time: float = float(b.get("spawn_time", 0.0))
		if is_equal_approx(a_time, b_time):
			return int(a.get("spawn", 0)) < int(b.get("spawn", 0))
		return a_time < b_time
	)
	return queue


# 尝试把当前选中的锚点放到鼠标位置。
func _try_place_selected_anchor() -> void:
	if _selected_anchor_id.is_empty():
		return
	if _get_anchor_nodes().size() >= _get_anchor_limit():
		_show_center_notice("无法放置更多魔法锚点")
		return
	var stats: Dictionary = AnchorDb.get_stats(_selected_anchor_id, 1)
	if stats.is_empty():
		_clear_anchor_selection()
		return
	var price: int = int(stats.get("price", 0))
	if _get_gold() < price:
		_show_center_notice("金币不足")
		_refresh_hotbar()
		return
	var placement_position: Vector2 = get_global_mouse_position()
	if not _can_place_anchor_at(placement_position):
		_show_center_notice("这里不能放置锚点")
		return
	var anchor: StaticBody2D = ANCHOR_SCENE.instantiate() as StaticBody2D
	anchor_container.add_child(anchor)
	anchor.global_position = placement_position
	anchor.call("setup", _selected_anchor_id, 1, stats)
	_apply_run_modifiers_to_anchor(anchor)
	anchor.connect("open_detail_requested", _on_anchor_detail_requested)
	anchor.connect("upgrade_requested", _on_anchor_upgrade_requested)
	anchor.connect("died", _on_anchor_died)
	if not _spend_run_gold(price):
		anchor.queue_free()
		return
	_refresh_hotbar()
	_update_anchor_upgrade_affordances()
	_show_center_notice("%s 已放置" % str(stats.get("display_name", _selected_anchor_id)))
	_update_hud()


# 优先把左键点击分派给房子或已放置锚点，没有命中时才尝试放置。
func _handle_world_left_click() -> void:
	if pause_screen.visible or setting_screen.visible or failure_screen.visible or level_up_panel.visible or recycle_dialog.visible:
		return
	var target: Node = _find_detail_target_at(get_global_mouse_position())
	if target != null:
		_open_detail_target(target)
		return
	_try_place_selected_anchor()


# 查找鼠标位置下可打开详情的世界物体，避开同层障碍物抢点击。
func _find_detail_target_at(world_position: Vector2) -> Node:
	var query := PhysicsPointQueryParameters2D.new()
	query.position = world_position
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.collision_mask = 4 | 16
	var hits: Array[Dictionary] = get_world_2d().direct_space_state.intersect_point(query, 24)
	for hit in hits:
		var collider: Object = hit.get("collider")
		if collider is Node and _is_detail_click_target(collider as Node):
			return collider as Node
	return _find_nearest_detail_target(world_position)


# 用较小半径兜底贴图边缘点击，避免碰撞体比占位图略小导致打不开面板。
func _find_nearest_detail_target(world_position: Vector2) -> Node:
	var best: Node = null
	var best_distance_sq: float = 96.0 * 96.0
	if is_instance_valid(_house) and _is_detail_click_target(_house):
		var house_distance_sq: float = (_house as Node2D).global_position.distance_squared_to(world_position)
		if house_distance_sq < best_distance_sq:
			best = _house
			best_distance_sq = house_distance_sq
	for node in _get_anchor_nodes():
		if not _is_detail_click_target(node):
			continue
		var anchor_distance_sq: float = (node as Node2D).global_position.distance_squared_to(world_position)
		if anchor_distance_sq < best_distance_sq:
			best = node
			best_distance_sq = anchor_distance_sq
	return best


# 判断一个节点是否应该响应详情面板点击。
func _is_detail_click_target(node: Node) -> bool:
	if not is_instance_valid(node) or not (node is Node2D):
		return false
	if node == _house:
		return true
	if node.is_in_group("anchors"):
		return true
	return false


# 根据点击对象打开对应右侧详情面板。
func _open_detail_target(target: Node) -> void:
	if target == _house:
		_on_house_detail_requested(target)
	elif target.is_in_group("anchors"):
		_on_anchor_detail_requested(target)


# 锚点死亡后刷新附近升级提示和热栏。
func _on_anchor_died(_anchor: Node) -> void:
	if anchor_detail_panel.visible:
		anchor_detail_panel.call("refresh_current_anchor")
	_update_anchor_upgrade_affordances()
	_refresh_hotbar()


# 清空当前热栏选中的锚点类型。
func _clear_anchor_selection() -> void:
	_selected_anchor_id = ""
	_refresh_hotbar()
	placement_preview.visible = false
	preview_range.visible = false
	preview_sprite.visible = false
	preview_visual.visible = true


# 更新鼠标下方的放置预览。
func _update_placement_preview() -> void:
	if _selected_anchor_id.is_empty() or (_state != GameState.PREPARE and _state != GameState.COMBAT and _state != GameState.WAVE_CLEAR):
		placement_preview.visible = false
		return
	if _get_anchor_nodes().size() >= _get_anchor_limit():
		placement_preview.visible = false
		return
	var mouse_world: Vector2 = get_global_mouse_position()
	placement_preview.visible = true
	placement_preview.global_position = mouse_world
	var stats: Dictionary = AnchorDb.get_stats(_selected_anchor_id, 1)
	var price: int = int(stats.get("price", 0))
	var legal: bool = _can_place_anchor_at(mouse_world) and _get_gold() >= price
	var base_color: Color = stats.get("tint", Color(0.42, 0.75, 1.0, 1.0)) as Color
	_apply_anchor_preview_visual(stats, base_color, legal)


# 用当前锚点贴图刷新放置预览，资源缺失时才显示旧占位轮廓。
func _apply_anchor_preview_visual(stats: Dictionary, base_color: Color, legal: bool) -> void:
	var alpha: float = 0.4 if legal else 0.22
	var preview_color: Color = base_color if legal else Color(1.0, 0.22, 0.18, 1.0)
	_apply_anchor_preview_range(stats, preview_color, legal)
	var frames: SpriteFrames = stats.get("sprite_frames") as SpriteFrames
	var has_frames: bool = frames != null and frames.get_animation_names().size() > 0
	preview_visual.visible = true
	preview_visual.color = Color(preview_color.r, preview_color.g, preview_color.b, 0.24 if legal else 0.18)
	if has_frames:
		preview_sprite.visible = true
		preview_sprite.sprite_frames = frames
		var animation_names: PackedStringArray = frames.get_animation_names()
		var default_animation: StringName = animation_names[0]
		preview_sprite.animation = default_animation
		if frames.has_animation(default_animation) and not preview_sprite.is_playing():
			preview_sprite.play(default_animation)
		preview_sprite.scale = _get_anchor_preview_sprite_scale(_selected_anchor_id)
		preview_sprite.position = _get_anchor_preview_sprite_offset(_selected_anchor_id)
		preview_sprite.modulate = Color(preview_color.r, preview_color.g, preview_color.b, alpha)
		return
	preview_sprite.visible = false
	preview_visual.color = Color(preview_color.r, preview_color.g, preview_color.b, alpha)


# 显示当前锚点的攻击范围预览，和贴图预览分离。
func _apply_anchor_preview_range(stats: Dictionary, color: Color, legal: bool) -> void:
	if preview_range == null:
		return
	var radius: float = float(stats.get("attack_radius", 0.0))
	if radius <= 0.0:
		preview_range.visible = false
		return
	preview_range.visible = true
	preview_range.self_modulate = Color(color.r, color.g, color.b, 0.18 if legal else 0.12)
	if preview_range.texture != null:
		var diameter: float = maxf(1.0, float(preview_range.texture.get_width()))
		var scale_factor: float = radius * 2.0 / diameter
		preview_range.scale = Vector2.ONE * scale_factor


# 预览节点不在 MagicAnchor 的 VisualRoot 下，需要使用等效的世界显示缩放。
func _get_anchor_preview_sprite_scale(anchor_id: String) -> Vector2:
	match anchor_id:
		"xiu_xiu", "double_xiu_xiu":
			return Vector2(0.21, 0.21)
		"mine":
			return Vector2(0.30, 0.30)
		"frost_circle":
			return Vector2(0.36, 0.36)
		"mushroom_tower":
			return Vector2(0.38, 0.38)
		"frost_tower":
			return Vector2(0.30, 0.30)
		_:
			return Vector2(0.32, 0.32)


# 让预览贴图和实际放下后的锚点重心一致。
func _get_anchor_preview_sprite_offset(anchor_id: String) -> Vector2:
	match anchor_id:
		"xiu_xiu", "double_xiu_xiu":
			return Vector2(0.0, -6.0)
		"mine":
			return Vector2(0.0, -4.0)
		"mushroom_tower":
			return Vector2(0.0, -16.0)
		_:
			return Vector2.ZERO


# 检查当前位置是否允许放置锚点。
func _can_place_anchor_at(candidate_position: Vector2) -> bool:
	if _is_anchor_placement_blocked_region(candidate_position, ANCHOR_PLACEMENT_RADIUS):
		return false
	if not _is_in_anchor_placement_area(candidate_position):
		return false
	if _is_anchor_placement_shape_blocked(candidate_position):
		return false
	if is_instance_valid(_player) and candidate_position.distance_to(_player.global_position) < ANCHOR_PLAYER_CLEARANCE:
		return false
	for node in _get_anchor_nodes():
		if is_instance_valid(node) and (node as Node2D).global_position.distance_to(candidate_position) < ANCHOR_ANCHOR_CLEARANCE:
			return false
	return true


# 更新玩家附近锚点的升级按钮显隐。
func _update_anchor_upgrade_affordances() -> void:
	if not is_instance_valid(_player):
		return
	for node in _get_anchor_nodes():
		if not (node is Node2D) or not node.has_method("set_upgrade_visible"):
			continue
		var anchor: Node2D = node as Node2D
		var near: bool = anchor.global_position.distance_to(_player.global_position) <= 50.0
		anchor.call("set_upgrade_visible", near and _state != GameState.FAILURE, _get_gold())


# 返回场上当前所有已放置锚点。
func _get_anchor_nodes() -> Array:
	var anchors: Array = []
	for child in anchor_container.get_children():
		if is_instance_valid(child) and not child.is_queued_for_deletion():
			anchors.append(child)
	return anchors


# 返回当前波次表配置的总波数。
func _get_total_waves() -> int:
	return maxi(1, int(WAVE_TABLE.call("get_total_waves")))


# 返回当前波次给 UI 使用的名字和说明。
func _get_wave_display_data(wave_index: int) -> Dictionary:
	var total_waves: int = _get_total_waves()
	var safe_index: int = clampi(wave_index, 0, total_waves - 1)
	var wave_data: Dictionary = WAVE_TABLE.call("get_wave", safe_index)
	var fallback_name: String = "第 %d 波" % (safe_index + 1)
	return {
		"name": str(wave_data.get("name", fallback_name)),
		"description": str(wave_data.get("description", "")),
		"boss_wave": bool(wave_data.get("boss_wave", false)),
	}


# 把当前波次案内同步给底部开始按钮 tooltip。
func _apply_hotbar_wave_state(is_prepare: bool, wave_index: int, total_waves: int) -> void:
	var wave_info: Dictionary = _get_wave_display_data(wave_index - 1)
	hotbar.call(
		"set_prepare_state",
		is_prepare,
		wave_index,
		total_waves,
		str(wave_info.get("name", "")),
		str(wave_info.get("description", ""))
	)


# 根据当前金币和选中状态刷新热栏。
func _refresh_hotbar() -> void:
	var needs_heal: bool = is_instance_valid(_player) and int(_player.get("current_hp")) < int(_player.get("max_hp"))
	var heal_enabled: bool = _can_use_heal_potion()
	if _selected_anchor_id.is_empty():
		hotbar.call("set_shop_state", "", _get_gold())
		if hotbar.has_method("set_heal_state"):
			hotbar.call("set_heal_state", HEAL_POTION_COST, heal_enabled, needs_heal)
		return
	var stats: Dictionary = AnchorDb.get_stats(_selected_anchor_id, 1)
	if stats.is_empty() or _get_gold() < int(stats.get("price", 0)):
		_selected_anchor_id = ""
	hotbar.call("set_shop_state", _selected_anchor_id, _get_gold())
	if hotbar.has_method("set_heal_state"):
		hotbar.call("set_heal_state", HEAL_POTION_COST, heal_enabled, needs_heal)


# 根据已选卡牌重建本局运行时修正。
func _sync_run_modifiers_from_player() -> void:
	var selected_skill_ids: Array[int] = []
	if is_instance_valid(_player):
		for item in _player.get("selected_skill_ids") as Array:
			selected_skill_ids.append(int(item))
	_run_modifiers = SkillDb.build_run_modifiers(selected_skill_ids)
	_auto_repair_timer = 0.0 if float(_run_modifiers.get("auto_repair_percent", 0.0)) <= 0.0 else _auto_repair_timer
	if is_instance_valid(_player):
		_player.call("apply_run_skill_modifiers", _run_modifiers)
	for anchor in _get_anchor_nodes():
		_apply_run_modifiers_to_anchor(anchor)
	if anchor_detail_panel.visible:
		anchor_detail_panel.call("refresh_current_anchor")
	_refresh_hotbar()


# 把本局修正同步给一个已放置锚点。
func _apply_run_modifiers_to_anchor(anchor: Node) -> void:
	if is_instance_valid(anchor) and anchor.has_method("set_runtime_modifiers"):
		anchor.call("set_runtime_modifiers", _run_modifiers)


## 战斗中按技能配置自动修复房子和可受伤锚点。
func _update_auto_repair(delta: float) -> void:
	if _state != GameState.COMBAT:
		return
	var repair_percent: float = float(_run_modifiers.get("auto_repair_percent", 0.0))
	if repair_percent <= 0.0:
		return
	var interval: float = maxf(1.0, float(_run_modifiers.get("auto_repair_interval", 30.0)))
	_auto_repair_timer += delta
	if _auto_repair_timer < interval:
		return
	_auto_repair_timer = 0.0
	_apply_auto_repair_tick(repair_percent)


## 执行一次自动修复，并刷新相关面板。
func _apply_auto_repair_tick(percent: float) -> void:
	var repaired_any: bool = false
	if is_instance_valid(_house):
		var max_house_hp: float = float(_house.get("max_hp"))
		if _house.has_method("repair"):
			repaired_any = bool(_house.call("repair", max_house_hp * percent)) or repaired_any
	for anchor in _get_anchor_nodes():
		if not is_instance_valid(anchor) or not anchor.has_method("repair_percent"):
			continue
		repaired_any = bool(anchor.call("repair_percent", percent)) or repaired_any
	if repaired_any:
		if anchor_detail_panel.visible:
			anchor_detail_panel.call("refresh_current_anchor")
		if house_detail_panel.visible:
			house_detail_panel.call("refresh_current_house", _get_gold())
		_update_hud()


# 返回当前局内可放置锚点上限。
func _get_anchor_limit() -> int:
	return maxi(1, int(_run_modifiers.get("anchor_limit", 9)))


# 按本局经济修正缩放金币或经验收益。
func _scale_reward_amount(kind: String, amount: int) -> int:
	if amount <= 0:
		return 0
	var multiplier_key: String = "gold_multiplier" if kind == "gold" else "exp_multiplier"
	var multiplier: float = float(_run_modifiers.get(multiplier_key, 1.0))
	return maxi(1, int(round(float(amount) * multiplier)))


# 在屏幕中央弹出短时提示。
func _show_center_notice(text: String) -> void:
	if center_notice_label == null:
		return
	center_notice_label.text = text
	center_notice_label.visible = true
	center_notice_label.modulate.a = 1.0
	if is_instance_valid(_center_notice_tween):
		_center_notice_tween.kill()
	_center_notice_tween = create_tween()
	_center_notice_tween.set_ignore_time_scale(true)
	_center_notice_tween.tween_interval(1.0)
	_center_notice_tween.tween_property(center_notice_label, "modulate:a", 0.0, 0.3)
	_center_notice_tween.finished.connect(func() -> void:
		if center_notice_label != null:
			center_notice_label.visible = false
	)


# 刷新左上角当前已获得能力摘要，同组只显示最高级。
func _refresh_skill_summary() -> void:
	if skill_summary_panel == null or skill_summary_label == null:
		return
	if not is_instance_valid(_player):
		skill_summary_panel.visible = false
		return
	var selected_skill_ids: Array[int] = []
	for item in _player.get("selected_skill_ids") as Array:
		selected_skill_ids.append(int(item))
	var summaries: Array[Dictionary] = SkillDb.get_selected_skill_summaries(selected_skill_ids)
	if summaries.is_empty():
		skill_summary_panel.visible = false
		return
	var lines: Array[String] = []
	for summary in summaries:
		lines.append("- %s" % str(summary.get("summary_text", summary.get("name", "技能"))))
	skill_summary_label.text = "\n".join(lines)
	skill_summary_panel.visible = true


# 在指定位置周围生成 Boss 召唤出来的一圈小怪。
func _spawn_summoned_pack(enemy_spec: Variant, level: int, center: Vector2, count: int, radius: float) -> void:
	var summon_entries: Array[Dictionary] = _normalize_summon_entries(enemy_spec, level, count)
	if summon_entries.is_empty():
		return
	var total_count: int = 0
	for entry in summon_entries:
		total_count += maxi(1, int(entry.get("count", 1)))
	var spawn_index: int = 0
	for entry in summon_entries:
		var enemy_id: String = str(entry.get("enemy_id", "slime_blue"))
		var enemy_level: int = maxi(1, int(entry.get("level", level)))
		var entry_count: int = maxi(1, int(entry.get("count", 1)))
		var runtime: Dictionary = ENEMY_CATALOG.call("get_runtime_stats", enemy_id, enemy_level)
		if runtime.is_empty():
			continue
		for i in range(entry_count):
			_spawn_summoned_enemy(runtime, enemy_level, center, radius, spawn_index, maxi(1, total_count))
			spawn_index += 1


# 把 Boss 召唤配置统一成敌人 id/等级/数量条目，兼容旧的单怪召唤格式。
func _normalize_summon_entries(enemy_spec: Variant, level: int, count: int) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	if enemy_spec is Array:
		for raw_entry in enemy_spec as Array:
			if not (raw_entry is Dictionary):
				continue
			var entry: Dictionary = (raw_entry as Dictionary).duplicate(true)
			if not entry.has("level"):
				entry["level"] = level
			entries.append(entry)
	elif enemy_spec is String:
		var enemy_id: String = str(enemy_spec)
		if not enemy_id.is_empty():
			entries.append({"enemy_id": enemy_id, "level": level, "count": maxi(1, count)})
	return entries


# 在 Boss 周围生成一只召唤小怪，并继承当前局内目标和寻路上下文。
func _spawn_summoned_enemy(runtime: Dictionary, level: int, center: Vector2, radius: float, index: int, total_count: int) -> void:
	var enemy: CharacterBody2D = ENEMY_SCENE.instantiate() as CharacterBody2D
	enemy_container.add_child(enemy)
	var angle: float = TAU * float(index) / float(maxi(1, total_count)) + _rng.randf_range(-0.2, 0.2)
	var distance: float = _rng.randf_range(radius * 0.35, radius)
	var spawn_position: Vector2 = center + Vector2.RIGHT.rotated(angle) * distance
	spawn_position.x = clampf(spawn_position.x, 72.0, MAP_SIZE.x - 72.0)
	spawn_position.y = clampf(spawn_position.y, 72.0, MAP_SIZE.y - 72.0)
	enemy.global_position = spawn_position
	enemy.call(
		"setup",
		runtime.duplicate(true),
		level,
		_house,
		_player,
		Callable(self, "_get_anchor_nodes"),
		Callable(self, "_spawn_summoned_pack"),
		Callable(self, "_get_enemy_navigation_path")
	)
	if enemy.has_method("configure_route"):
		var spawn_index_for_route: int = _get_nearest_spawn_index(spawn_position)
		enemy.call("configure_route", spawn_index_for_route, _get_enemy_route(spawn_index_for_route), Callable(self, "_get_enemy_return_path"))
		if enemy.has_method("begin_return_to_route"):
			enemy.call("begin_return_to_route")
	enemy.connect("died", _on_enemy_died)


# 返回修正后的敌人出生点，底部出生点沿路上移，避免被底部 HUD 遮住。
func _get_enemy_spawn_position(spawn_index: int) -> Vector2:
	var spawn_points: Array[Vector2] = _get_spawn_points()
	if spawn_points.is_empty():
		return PLAYER_START
	var safe_index: int = clampi(spawn_index, 0, spawn_points.size() - 1)
	var spawn_point: Vector2 = spawn_points[safe_index]
	if safe_index == 1:
		var path: PackedVector2Array = _get_enemy_route(1)
		if path.size() >= 2:
			var next_point: Vector2 = path[1]
			spawn_point = spawn_point.move_toward(next_point, BOTTOM_SPAWN_VISIBLE_OFFSET)
	return spawn_point


# 返回敌人默认推房用路线，方向统一为出生点到房子。
func _get_enemy_route(spawn_index: int) -> PackedVector2Array:
	var spawn_points: Array[Vector2] = _get_spawn_points()
	if spawn_points.is_empty():
		return PackedVector2Array([HOUSE_POSITION])
	var safe_index: int = clampi(spawn_index, 0, spawn_points.size() - 1)
	if safe_index == 1:
		return PackedVector2Array([spawn_points[safe_index], _get_midpoint_position(), HOUSE_POSITION])
	return PackedVector2Array([spawn_points[safe_index], HOUSE_POSITION])


# 返回地图中点；缺节点时用旧下路汇入点硬兜底并报错。
func _get_midpoint_position() -> Vector2:
	if mid_point == null:
		push_error("SurvivorGame: missing World/MidPoint for bottom enemy route")
		return Vector2(2920.0, 1258.0)
	return mid_point.global_position


# 从当前位置规划一次避障路径，接到离当前位置最近的推房路线点。
func _get_enemy_return_path(start_position: Vector2, spawn_index: int = 0) -> PackedVector2Array:
	var route: PackedVector2Array = _get_enemy_route(spawn_index)
	if route.is_empty():
		return _get_enemy_navigation_path(start_position, HOUSE_POSITION, false)
	var best_point: Vector2 = route[0]
	var best_distance_sq: float = INF
	for point in route:
		var distance_sq: float = start_position.distance_squared_to(point)
		if distance_sq < best_distance_sq:
			best_distance_sq = distance_sq
			best_point = point
	return _get_enemy_navigation_path(start_position, best_point, false)


# 返回离指定位置最近的出生点索引，供召唤怪接入合适路线。
func _get_nearest_spawn_index(world_position: Vector2) -> int:
	var spawn_points: Array[Vector2] = _get_spawn_points()
	if spawn_points.is_empty():
		return 0
	var best_index: int = 0
	var best_distance_sq: float = INF
	for i in range(spawn_points.size()):
		var distance_sq: float = world_position.distance_squared_to(spawn_points[i])
		if distance_sq < best_distance_sq:
			best_distance_sq = distance_sq
			best_index = i
	return best_index


# 用障碍碰撞重建敌人共用的道路偏好和直接追击导航网格。
func _rebuild_navigation_grid() -> void:
	_navigation_grid_size = Vector2i(
		int(ceil(MAP_SIZE.x / float(NAVIGATION_CELL_SIZE))),
		int(ceil(MAP_SIZE.y / float(NAVIGATION_CELL_SIZE)))
	)
	_navigation_grid = _create_enemy_navigation_grid(true)
	_direct_navigation_grid = _create_enemy_navigation_grid(false)


# 创建一张敌人导航网格，可选择是否用道路权重。
func _create_enemy_navigation_grid(prefer_roads: bool) -> AStarGrid2D:
	var grid: AStarGrid2D = AStarGrid2D.new()
	grid.region = Rect2i(Vector2i.ZERO, _navigation_grid_size)
	grid.cell_size = Vector2(NAVIGATION_CELL_SIZE, NAVIGATION_CELL_SIZE)
	grid.offset = Vector2(float(NAVIGATION_CELL_SIZE) * 0.5, float(NAVIGATION_CELL_SIZE) * 0.5)
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_AT_LEAST_ONE_WALKABLE
	grid.update()
	for y in range(_navigation_grid_size.y):
		for x in range(_navigation_grid_size.x):
			var cell: Vector2i = Vector2i(x, y)
			var world_point: Vector2 = _nav_cell_to_world(cell)
			if not _is_on_road_corridor(world_point, 0.0, ROAD_WALKABLE_HALF_WIDTH + 24.0):
				grid.set_point_solid(cell, true)
				continue
			grid.set_point_weight_scale(cell, _get_navigation_weight(world_point) if prefer_roads else 1.0)
	return grid


# 给敌人提供一条带避障的导航路径，默认推房子时更偏道路。
func _get_enemy_navigation_path(start: Vector2, target: Vector2, prefer_roads: bool = true) -> PackedVector2Array:
	var grid: AStarGrid2D = _navigation_grid if prefer_roads else _direct_navigation_grid
	if grid == null:
		return PackedVector2Array([target])
	var start_cell: Vector2i = _find_nearest_walkable_nav_cell(_world_to_nav_cell(start), 8, grid)
	var target_cell: Vector2i = _find_nearest_walkable_nav_cell(_world_to_nav_cell(target), 10, grid)
	if not _is_nav_cell_in_bounds(start_cell) or not _is_nav_cell_in_bounds(target_cell):
		return PackedVector2Array([target])
	var id_path: Array = grid.get_id_path(start_cell, target_cell)
	if id_path.is_empty() and prefer_roads and _direct_navigation_grid != null:
		start_cell = _find_nearest_walkable_nav_cell(_world_to_nav_cell(start), 8, _direct_navigation_grid)
		target_cell = _find_nearest_walkable_nav_cell(_world_to_nav_cell(target), 10, _direct_navigation_grid)
		if _is_nav_cell_in_bounds(start_cell) and _is_nav_cell_in_bounds(target_cell):
			id_path = _direct_navigation_grid.get_id_path(start_cell, target_cell)
			grid = _direct_navigation_grid
	if id_path.is_empty():
		return PackedVector2Array([target])
	var path_points: PackedVector2Array = PackedVector2Array()
	for i in range(id_path.size()):
		var cell: Vector2i = id_path[i]
		var world_point: Vector2 = _nav_cell_to_world(cell)
		if i == id_path.size() - 1:
			world_point = target
		path_points.append(world_point)
	return path_points


# 依据道路距离给导航格子设置权重，让怪物更倾向沿路推进。
func _get_navigation_weight(world_point: Vector2) -> float:
	var best_distance: float = INF
	for path in _get_road_paths():
		best_distance = minf(best_distance, _distance_to_polyline(world_point, path))
	if best_distance <= ROAD_PLACEMENT_HALF_WIDTH * 0.48:
		return ROAD_NAV_WEIGHT
	if best_distance <= ROAD_PLACEMENT_HALF_WIDTH:
		return ROAD_SHOULDER_NAV_WEIGHT
	return FOREST_NAV_WEIGHT


# 把世界坐标换算到导航网格编号。
func _world_to_nav_cell(world_position: Vector2) -> Vector2i:
	return Vector2i(
		clampi(int(floor(world_position.x / float(NAVIGATION_CELL_SIZE))), 0, _navigation_grid_size.x - 1),
		clampi(int(floor(world_position.y / float(NAVIGATION_CELL_SIZE))), 0, _navigation_grid_size.y - 1)
	)


# 把导航格子编号换回世界空间中心点。
func _nav_cell_to_world(cell: Vector2i) -> Vector2:
	return Vector2(
		float(cell.x * NAVIGATION_CELL_SIZE) + float(NAVIGATION_CELL_SIZE) * 0.5,
		float(cell.y * NAVIGATION_CELL_SIZE) + float(NAVIGATION_CELL_SIZE) * 0.5
	)


# 判断一个导航格子编号是否仍在网格有效范围内。
func _is_nav_cell_in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < _navigation_grid_size.x and cell.y < _navigation_grid_size.y


# 如果目标格正好落在障碍里，就就近找一个可走格子兜底。
func _find_nearest_walkable_nav_cell(origin: Vector2i, max_radius: int, grid: AStarGrid2D = null) -> Vector2i:
	var active_grid: AStarGrid2D = grid if grid != null else _navigation_grid
	if active_grid == null:
		return Vector2i(-1, -1)
	if not _is_nav_cell_in_bounds(origin):
		return Vector2i(-1, -1)
	if not active_grid.is_point_solid(origin):
		return origin
	for radius in range(1, max_radius + 1):
		for y in range(origin.y - radius, origin.y + radius + 1):
			for x in range(origin.x - radius, origin.x + radius + 1):
				var cell: Vector2i = Vector2i(x, y)
				if not _is_nav_cell_in_bounds(cell):
					continue
				if active_grid.is_point_solid(cell):
					continue
				return cell
	return Vector2i(-1, -1)


# 在运行时查找全局音频路由节点。
func _get_game_audio() -> Node:
	if get_tree() == null or get_tree().root == null:
		return null
	return get_tree().root.get_node_or_null("GameAudio")


# 返回锚点放置时要避开的区域，不再把道路视为禁放区。
func _is_anchor_placement_blocked_region(point: Vector2, radius: float) -> bool:
	var placement_bounds: Rect2 = _get_current_map_rect().grow(-radius)
	if placement_bounds.size.x <= 0.0 or placement_bounds.size.y <= 0.0 or not placement_bounds.has_point(point):
		return true
	if point.distance_to(HOUSE_POSITION) < 240.0 + radius:
		return true
	if point.distance_to(PLAYER_START) < 120.0 + radius:
		return true
	for spawn_point in _get_spawn_points():
		if point.distance_to(spawn_point) < 200.0 + radius:
			return true
	return false


# 返回当前地图贴图在世界中的实际矩形，用作放置区和安全边界的来源。
func _get_current_map_rect() -> Rect2:
	if map_background != null and map_background.texture != null:
		var texture_size: Vector2 = map_background.texture.get_size() * map_background.global_scale.abs()
		var top_left: Vector2 = map_background.global_position - texture_size * 0.5
		return Rect2(top_left, texture_size)
	return Rect2(Vector2.ZERO, MAP_SIZE)


# 根据场景里已经摆好的围墙碰撞，从玩家初始点泛洪出当前可放置区域。
func _rebuild_anchor_placement_area() -> void:
	_anchor_placement_reachable_cells.clear()
	var map_rect: Rect2 = _get_current_map_rect()
	if map_rect.size.x <= 0.0 or map_rect.size.y <= 0.0:
		push_error("SurvivorGame: invalid map bounds for anchor placement")
		return
	_anchor_placement_origin = map_rect.position
	_anchor_placement_grid_size = Vector2i(
		maxi(1, int(ceil(map_rect.size.x / float(ANCHOR_PLACEMENT_GRID_SIZE)))),
		maxi(1, int(ceil(map_rect.size.y / float(ANCHOR_PLACEMENT_GRID_SIZE))))
	)
	var start_cell: Vector2i = _anchor_world_to_cell(PLAYER_START)
	if not _is_anchor_cell_in_bounds(start_cell):
		push_error("SurvivorGame: player start is outside current anchor placement map bounds")
		return
	start_cell = _find_nearest_open_anchor_cell(start_cell, 8)
	if not _is_anchor_cell_in_bounds(start_cell):
		push_error("SurvivorGame: no open anchor placement cell near player start")
		return
	var queue: Array[Vector2i] = [start_cell]
	_anchor_placement_reachable_cells[start_cell] = true
	var directions: Array[Vector2i] = [
		Vector2i.RIGHT,
		Vector2i.LEFT,
		Vector2i.DOWN,
		Vector2i.UP,
	]
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_front()
		for direction in directions:
			var next_cell: Vector2i = cell + direction
			if _anchor_placement_reachable_cells.has(next_cell):
				continue
			if not _is_anchor_cell_in_bounds(next_cell) or _is_anchor_cell_blocked(next_cell):
				continue
			_anchor_placement_reachable_cells[next_cell] = true
			queue.append(next_cell)


# 判断一个世界点是否落在当前围墙内连通的锚点放置区域。
func _is_in_anchor_placement_area(point: Vector2) -> bool:
	if _anchor_placement_reachable_cells.is_empty():
		return _get_current_map_rect().has_point(point)
	var cell: Vector2i = _anchor_world_to_cell(point)
	return _anchor_placement_reachable_cells.has(cell)


# 运行时检查当前候选点是否压到围墙、房子、已有塔等世界碰撞。
func _is_anchor_placement_shape_blocked(point: Vector2) -> bool:
	var shape := CircleShape2D.new()
	shape.radius = ANCHOR_PLACEMENT_GRID_PROBE_RADIUS
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, point)
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.collision_mask = 4
	var hits: Array[Dictionary] = get_world_2d().direct_space_state.intersect_shape(query, 12)
	for hit in hits:
		var collider: Object = hit.get("collider")
		if collider == _house or (collider is Node and (collider as Node).is_in_group("anchors")):
			return true
		if collider is Node:
			var node: Node = collider as Node
			if node.is_ancestor_of(placement_preview) or node == placement_preview:
				continue
		return true
	return false


# 把世界点转换为放置区网格格子。
func _anchor_world_to_cell(point: Vector2) -> Vector2i:
	var local: Vector2 = point - _anchor_placement_origin
	return Vector2i(
		int(floor(local.x / float(ANCHOR_PLACEMENT_GRID_SIZE))),
		int(floor(local.y / float(ANCHOR_PLACEMENT_GRID_SIZE)))
	)


# 把放置区格子转换为世界中心点。
func _anchor_cell_to_world(cell: Vector2i) -> Vector2:
	return _anchor_placement_origin + Vector2(
		float(cell.x * ANCHOR_PLACEMENT_GRID_SIZE) + float(ANCHOR_PLACEMENT_GRID_SIZE) * 0.5,
		float(cell.y * ANCHOR_PLACEMENT_GRID_SIZE) + float(ANCHOR_PLACEMENT_GRID_SIZE) * 0.5
	)


# 判断放置区格子是否还在当前地图贴图矩形内。
func _is_anchor_cell_in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < _anchor_placement_grid_size.x and cell.y < _anchor_placement_grid_size.y


# 判断放置区格子中心是否被场景围墙或障碍碰撞占住。
func _is_anchor_cell_blocked(cell: Vector2i) -> bool:
	return _is_anchor_placement_shape_blocked(_anchor_cell_to_world(cell))


# 起点落在碰撞边缘时，向周围找一个最近的开放格子。
func _find_nearest_open_anchor_cell(origin: Vector2i, max_radius: int) -> Vector2i:
	if _is_anchor_cell_in_bounds(origin) and not _is_anchor_cell_blocked(origin):
		return origin
	for radius in range(1, max_radius + 1):
		for y in range(origin.y - radius, origin.y + radius + 1):
			for x in range(origin.x - radius, origin.x + radius + 1):
				var cell: Vector2i = Vector2i(x, y)
				if not _is_anchor_cell_in_bounds(cell):
					continue
				if not _is_anchor_cell_blocked(cell):
					return cell
	return Vector2i(-1, -1)


# 返回地图草图上的两个固定出生点。
func _get_spawn_points() -> Array[Vector2]:
	return [
		Vector2(5480.0, 1820.0),
		Vector2(3130.0, 3030.0),
	]


# 返回道路折线，用于绘制和道路保留区计算。
func _get_road_paths() -> Array[PackedVector2Array]:
	return [
		PackedVector2Array([Vector2(520.0, 1640.0), Vector2(1180.0, 1620.0), Vector2(1940.0, 1580.0), Vector2(2720.0, 1510.0), Vector2(3480.0, 1420.0), Vector2(4240.0, 1540.0), Vector2(4920.0, 1730.0), Vector2(5480.0, 1820.0)]),
		PackedVector2Array([Vector2(2720.0, 1510.0), Vector2(2810.0, 1780.0), Vector2(2980.0, 2150.0), Vector2(3070.0, 2580.0), Vector2(3130.0, 3030.0)]),
	]


# 判断给定点是否位于地图道路走廊内。
func _is_on_road_corridor(point: Vector2, radius: float = 0.0, half_width: float = ROAD_WALKABLE_HALF_WIDTH) -> bool:
	if point.x < radius or point.y < radius or point.x > MAP_SIZE.x - radius or point.y > MAP_SIZE.y - radius:
		return false
	for path in _get_road_paths():
		if _distance_to_polyline(point, path) <= maxf(12.0, half_width - radius):
			return true
	return false


# 计算点到折线的最短距离。
func _distance_to_polyline(point: Vector2, path: PackedVector2Array) -> float:
	var best: float = INF
	for i in range(path.size() - 1):
		best = minf(best, _distance_to_segment(point, path[i], path[i + 1]))
	return best


# 计算点到线段的最短距离。
func _distance_to_segment(point: Vector2, start: Vector2, finish: Vector2) -> float:
	var segment: Vector2 = finish - start
	var length_sq: float = segment.length_squared()
	if is_zero_approx(length_sq):
		return point.distance_to(start)
	var t: float = clampf((point - start).dot(segment) / length_sq, 0.0, 1.0)
	return point.distance_to(start + segment * t)


# 只有详情面板或升级面板开着时才维持慢速时间。
func _restore_slow_time_if_clear() -> void:
	var anchor_open: bool = bool(anchor_detail_panel.call("is_open")) if anchor_detail_panel.has_method("is_open") else anchor_detail_panel.visible
	var house_open: bool = bool(house_detail_panel.call("is_open")) if house_detail_panel.has_method("is_open") else house_detail_panel.visible
	if anchor_open or house_open or level_up_panel.visible:
		Engine.time_scale = SLOW_TIME_SCALE
	else:
		Engine.time_scale = 1.0


# 刷新顶部 HUD、经验条和当前已获能力展示。
func _update_hud() -> void:
	gold_label.text = "金币 %d" % _get_gold()
	var total_waves: int = _get_total_waves()
	wave_label.text = _build_wave_label_text(total_waves)
	if is_instance_valid(_player) and hp_orb != null and hp_orb.has_method("set_meter"):
		var current_hp: float = _player.get("current_hp")
		var max_hp: float = _player.get("max_hp")
		var hp_ratio: float = current_hp / max_hp if max_hp > 0.0 else 0.0
		hp_orb.call("set_meter", current_hp, max_hp, hp_ratio, hp_ratio <= 0.35)
		_update_low_health_overlay(hp_ratio)
	else:
		_update_low_health_overlay(1.0)
	if exp_progress_bar != null and is_instance_valid(_player):
		var interval: Dictionary = _player.call("get_level_interval_bounds")
		var min_exp: int = int(interval.get("min_exp", 0))
		var max_exp: int = int(interval.get("max_exp", min_exp + 1))
		var total_exp: int = int(_player.get("total_exp"))
		var pending_level_ups: int = int(_player.get("pending_level_ups"))
		var is_max_level: bool = bool(interval.get("is_max_level", false))
		var display_max_exp: int = max_exp if not is_max_level else min_exp + 1
		exp_progress_bar.min_value = float(min_exp)
		exp_progress_bar.max_value = float(maxi(min_exp + 1, display_max_exp))
		exp_progress_bar.value = exp_progress_bar.max_value if is_max_level else float(mini(total_exp, display_max_exp))
		exp_progress_bar.show_percentage = false
		if exp_value_label != null:
			exp_value_label.text = "Lv.%d   %d / %d" % [int(_player.get("level")), mini(total_exp, max_exp), max_exp] if not is_max_level else "Lv.%d   已满级" % int(_player.get("level"))
		if is_max_level:
			exp_progress_bar.tooltip_text = "Lv.%d  已满级" % int(_player.get("level"))
		elif pending_level_ups > 0:
			exp_progress_bar.tooltip_text = "Lv.%d  EXP %d/%d  待升级 %d" % [int(_player.get("level")), mini(total_exp, max_exp), max_exp, pending_level_ups]
		else:
			exp_progress_bar.tooltip_text = "Lv.%d  EXP %d/%d" % [int(_player.get("level")), total_exp, max_exp]
	elif exp_value_label != null:
		exp_value_label.text = "-- / --"
	level_up_button.text = "升级 x%d" % int(_player.get("pending_level_ups")) if is_instance_valid(_player) and int(_player.get("pending_level_ups")) > 0 else "升级"
	level_up_button.visible = _pending_level_up and not level_up_panel.visible
	_refresh_skill_summary()


# 按当前状态组合波次标签，保留现有 HUD 位置但补足波名和阶段信息。
func _build_wave_label_text(total_waves: int) -> String:
	var current_wave: int = mini(_wave_index + 1, total_waves)
	var wave_data: Dictionary = WAVE_TABLE.call("get_wave", clampi(_wave_index, 0, total_waves - 1))
	var wave_name: String = str(wave_data.get("name", "第 %d 波" % current_wave))
	var state_text: String = ""
	match _state:
		GameState.PREPARE:
			state_text = "准备"
		GameState.COMBAT:
			state_text = "战斗"
		GameState.WAVE_CLEAR:
			state_text = "清场"
		GameState.VICTORY:
			state_text = "胜利"
		GameState.FAILURE:
			state_text = "失败"
		_:
			state_text = ""
	var boss_text: String = "  Boss" if bool(wave_data.get("boss_wave", false)) and not wave_name.to_lower().contains("boss") else ""
	return "%s%s  %d/%d  %s  击杀 %d" % [wave_name, boss_text, current_wave, total_waves, state_text, _kills]


# 按玩家剩余血量更新屏幕边缘的红色危险光效。
func _update_low_health_overlay(hp_ratio: float) -> void:
	if low_health_overlay == null or not (low_health_overlay.material is ShaderMaterial):
		return
	var normalized_ratio: float = clampf(hp_ratio, 0.0, 1.0)
	var t: float = clampf((0.3 - normalized_ratio) / 0.3, 0.0, 1.0)
	var eased: float = t * t * (3.0 - 2.0 * t)
	var material: ShaderMaterial = low_health_overlay.material as ShaderMaterial
	material.set_shader_parameter("intensity", eased * 0.92)
	low_health_overlay.visible = eased > 0.001


# 通过现有 SaveSystem 持久化当前存档槽。
func _save_slot() -> void:
	if PlayerModule.instance != null and is_instance_valid(_player):
		PlayerModule.instance.position = _player.global_position
		PlayerModule.instance.scene_path = scene_file_path
	var save_system: Node = _get_save_system()
	if save_system != null and save_system.has_method("save_slot"):
		save_system.call("save_slot", run_slot)


# 在运行时查找 SaveSystem 自动加载单例。
func _get_save_system() -> Node:
	if get_tree() == null or get_tree().root == null:
		return null
	return get_tree().root.get_node_or_null("SaveSystem")


# 在插件启用时查找 SceneManager 自动加载单例。
func _get_scene_manager() -> Node:
	if get_tree() == null or get_tree().root == null:
		return null
	return get_tree().root.get_node_or_null("SceneManager")


# 创建或读取当前存档槽对应的地图种子。
func _ensure_map_seed() -> int:
	var custom: Dictionary = PlayerModule.instance.custom
	if not custom.has("survivor_map_seed"):
		var seed_rng: RandomNumberGenerator = RandomNumberGenerator.new()
		seed_rng.randomize()
		custom["survivor_map_seed"] = int(seed_rng.randi_range(1, 2147483646))
	return int(custom.get("survivor_map_seed", 1))


# 从存档自定义数据里读取体力成长等级。
func _get_stamina_growth_level() -> int:
	if PlayerModule.instance == null:
		return 0
	return int(PlayerModule.instance.custom.get("stamina_level", 0))


# 从存档自定义数据里读取移动速度成长等级。
func _get_move_speed_growth_level() -> int:
	if PlayerModule.instance == null:
		return 0
	return int(PlayerModule.instance.custom.get("move_speed_level", 0))


# 从存档自定义数据里读取攻击速度成长等级。
func _get_attack_speed_growth_level() -> int:
	if PlayerModule.instance == null:
		return 0
	return int(PlayerModule.instance.custom.get("attack_speed_level", 0))


# 从存档自定义数据里读取初始金币成长等级。
func _get_start_gold_growth_level() -> int:
	if PlayerModule.instance == null:
		return 0
	return int(PlayerModule.instance.custom.get("start_gold_level", 0))


# 计算本局开局金币，局外成长只影响本局起始值。
func _get_run_start_gold() -> int:
	return RUN_START_GOLD + maxi(0, _get_start_gold_growth_level()) * START_GOLD_PER_LEVEL


# 重置存档血量，避免失败后下次进入直接残血。
func _reset_saved_health_for_next_run() -> void:
	if PlayerModule.instance == null:
		return
	PlayerModule.instance.hp = PlayerModule.instance.max_hp


# 返回当前局内金币数量。
func _get_gold() -> int:
	return _run_gold


# 尝试消耗本局金币。
func _spend_run_gold(amount: int) -> bool:
	if amount <= 0:
		return true
	if _run_gold < amount:
		return false
	_run_gold -= amount
	_refresh_hotbar()
	if house_detail_panel.visible:
		house_detail_panel.call("refresh_current_house", _get_gold())
	_update_hud()
	return true


# 增加本局金币。
func _add_run_gold(amount: int) -> void:
	if amount <= 0:
		return
	_run_gold += amount
	_refresh_hotbar()
	if house_detail_panel.visible:
		house_detail_panel.call("refresh_current_house", _get_gold())
	_update_hud()


# 判断热栏血瓶当前是否可用。
func _can_use_heal_potion() -> bool:
	if _state == GameState.FAILURE or not is_instance_valid(_player):
		return false
	if _get_gold() < HEAL_POTION_COST:
		return false
	return true


# 把剩余本局金币按比例结算成局外成长点，并防止重复结算。
func _settle_growth_points_once() -> int:
	if _growth_settled or PlayerModule.instance == null:
		return 0
	var gained_points: int = maxi(0, int(floor(float(_run_gold) / float(GROWTH_POINT_DIVISOR))))
	PlayerModule.instance.custom["growth_points"] = maxi(0, int(PlayerModule.instance.custom.get("growth_points", 0))) + gained_points
	_growth_settled = true
	return gained_points


# 打开战斗结果页，胜利和失败共用同一套 authored 玻璃面板。
func _open_result_screen(is_victory: bool, gained_points: int) -> void:
	if failure_screen == null:
		return
	var total_waves: int = _get_total_waves()
	var cleared_waves: int = total_waves if is_victory else clampi(_wave_index, 0, total_waves)
	failure_screen.call("set_result", is_victory, _kills, _get_gold(), gained_points, cleared_waves, total_waves)
	failure_screen.call("open_modal")


# 如果 SceneManager 可用，则播放入场淡入。
func _play_enter_transition() -> void:
	var scene_manager: Node = _get_scene_manager()
	if scene_manager != null and scene_manager.has_method("transition_start"):
		scene_manager.call("transition_start", ENTER_TRANSITION, true)


# 根据设置项应用一次屏幕震动。
func apply_screen_shake(strength: float, duration: float) -> void:
	var setting_strength: float = float(SettingsModule.instance.get_value("screen_shake", 0.5)) if SettingsModule.instance != null else 0.5
	if setting_strength <= 0.0:
		return
	_screen_shake_strength = maxf(_screen_shake_strength, strength * setting_strength * 12.0)
	_screen_shake_time = maxf(_screen_shake_time, duration)
	_screen_shake_total_time = maxf(_screen_shake_total_time, duration)


# 屏幕震动期间更新相机局部偏移。
func _update_screen_shake(delta: float) -> void:
	if camera == null:
		return
	if _screen_shake_time <= 0.0:
		_screen_shake_strength = 0.0
		_screen_shake_total_time = 0.0
		camera.position = _camera_base_position
		return
	_screen_shake_time = maxf(0.0, _screen_shake_time - delta)
	var normalized: float = _screen_shake_time / maxf(0.01, _screen_shake_total_time)
	var falloff: float = normalized * normalized
	var offset: Vector2 = Vector2(
		_rng.randf_range(-_screen_shake_strength, _screen_shake_strength),
		_rng.randf_range(-_screen_shake_strength, _screen_shake_strength)
	) * falloff
	camera.position = _camera_base_position + offset


# 在退场过渡后切换到其他场景。
func _change_scene_with_transition(path: String) -> void:
	var scene_manager: Node = _get_scene_manager()
	if scene_manager != null and scene_manager.has_method("transition_start") and scene_manager.has_method("change_scene_to_file"):
		var tween: Tween = scene_manager.call("transition_start", EXIT_TRANSITION)
		if tween != null:
			await tween.finished
		scene_manager.call("change_scene_to_file", path)
	else:
		get_tree().change_scene_to_file(path)


# 在退场过渡后重新加载当前场景。
func _reload_scene_with_transition() -> void:
	var scene_manager: Node = _get_scene_manager()
	if scene_manager != null and scene_manager.has_method("transition_start") and scene_manager.has_method("reload_current_scene"):
		var tween: Tween = scene_manager.call("transition_start", EXIT_TRANSITION)
		if tween != null:
			await tween.finished
		scene_manager.call("reload_current_scene")
	else:
		get_tree().reload_current_scene()
