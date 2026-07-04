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
const PLAYER_SCENE: PackedScene = preload("res://Scenes/Game/Survivor/player.tscn")
const ENEMY_SCENE: PackedScene = preload("res://Scenes/Game/Survivor/enemy.tscn")
const OBSTACLE_SCENE: PackedScene = preload("res://Scenes/Game/Survivor/obstacle.tscn")
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
@export var obstacle_count: int = 120
@export var obstacle_cell_size: float = 190.0
@export var obstacle_noise_threshold: float = 0.1

@onready var world: Node2D = $World
@onready var ground: Polygon2D = $World/Ground
@onready var road_container: Node2D = $World/Roads
@onready var boundary_container: Node2D = $World/Boundaries
@onready var obstacle_container: Node2D = $World/Obstacles
@onready var anchor_container: Node2D = $World/Anchors
@onready var enemy_container: Node2D = $World/Enemies
@onready var projectile_container: Node2D = $World/Projectiles
@onready var pickup_container: Node2D = $World/Pickups
@onready var placement_preview: Node2D = $World/PlacementPreview
@onready var preview_visual: Polygon2D = $World/PlacementPreview/PreviewVisual
@onready var camera: Camera2D = $Camera2D
@onready var gold_label: Label = $HUD/Root/TopBar/GoldLabel
@onready var hp_orb: Control = $HUD/Root/TopBar/HpOrb
@onready var wave_label: Label = $HUD/Root/WaveLabel
@onready var hotbar: Control = $HUD/Root/Hotbar
@onready var skill_summary_panel: PanelContainer = $HUD/Root/SkillSummaryPanel
@onready var skill_summary_label: Label = $HUD/Root/SkillSummaryPanel/Margin/VBox/SkillSummaryLabel
@onready var level_up_button: Button = $HUD/Root/LevelUpButton
@onready var anchor_detail_panel: Control = $HUD/Root/AnchorDetailPanel
@onready var recycle_dialog: Control = $HUD/Root/AnchorRecycleDialog
@onready var level_up_panel: Control = $HUD/Root/LevelUpPanel
@onready var exp_progress_bar: ProgressBar = $HUD/Root/ExpProgressBar
@onready var exp_value_label: Label = $HUD/Root/ExpProgressBar/ValueLabel
@onready var center_notice_label: Label = $HUD/Root/CenterNoticeLabel
@onready var pause_screen: Control = $HUD/PauseScreen
@onready var setting_screen: Control = $HUD/SettingScreen
@onready var failure_screen: Control = $HUD/FailureScreen

var _state: GameState = GameState.PREPARE
var _player: Node2D
var _house: Node2D
var _kills: int = 0
var _wave_index: int = 0
var _spawn_queue: Array[Dictionary] = []
var _spawn_elapsed_time: float = 0.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _map_seed: int = 0
var _obstacle_rects: Array[Rect2] = []
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


# 构建地图、实体和 HUD，并连接所有局内流程。
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	get_tree().paused = false
	Engine.time_scale = 1.0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	SkillDb.validate()
	_prepare_save_slot()
	_setup_world()
	_spawn_house()
	_spawn_player()
	_setup_camera()
	_connect_ui()
	set_game_state(GameState.PREPARE)
	_update_hud()
	_play_enter_transition()


# 每帧驱动放置预览、掉落补发和波次收尾检查。
func _process(delta: float) -> void:
	_update_placement_preview()
	_update_anchor_upgrade_affordances()
	_flush_pending_pickups()
	_update_screen_shake(delta)
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
				_try_place_selected_anchor()
				get_viewport().set_input_as_handled()
			elif mouse_event.button_index == MOUSE_BUTTON_RIGHT and mouse_event.pressed:
				_clear_anchor_selection()
				get_viewport().set_input_as_handled()


# 离开场景时恢复全局状态并写回存档。
func _exit_tree() -> void:
	Engine.time_scale = 1.0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_save_slot()


# 切换局内状态，并同步热栏和 HUD。
func set_game_state(new_state: GameState) -> void:
	_state = new_state
	var total_waves: int = _get_total_waves()
	var current_wave: int = clampi(_wave_index + 1, 1, total_waves)
	match _state:
		GameState.PREPARE:
			Engine.time_scale = 1.0
			get_tree().paused = false
			hotbar.call("set_prepare_state", true, current_wave, total_waves)
		GameState.COMBAT:
			Engine.time_scale = 1.0
			get_tree().paused = false
			hotbar.call("set_prepare_state", false, current_wave, total_waves)
		GameState.WAVE_CLEAR:
			Engine.time_scale = 1.0
			get_tree().paused = false
			hotbar.call("set_prepare_state", true, clampi(_wave_index + 1, 1, total_waves), total_waves)
		GameState.VICTORY:
			Engine.time_scale = 1.0
			hotbar.call("set_prepare_state", false, total_waves, total_waves)
			_save_slot()
		GameState.FAILURE:
			Engine.time_scale = 1.0
			hotbar.call("set_prepare_state", false, current_wave, total_waves)
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
	ground.polygon = PackedVector2Array([
		Vector2.ZERO,
		Vector2(MAP_SIZE.x, 0.0),
		MAP_SIZE,
		Vector2(0.0, MAP_SIZE.y),
	])
	ground.color = Color(0.17, 0.33, 0.19, 1.0)
	_configure_roads()
	_create_boundaries()
	_generate_obstacles()
	placement_preview.visible = false


# 用折线临时绘制策划草图里的道路。
func _configure_roads() -> void:
	var paths: Array[PackedVector2Array] = _get_road_paths()
	for i in range(paths.size()):
		var line: Line2D = road_container.get_node("Road%d" % (i + 1)) as Line2D
		if line == null:
			continue
		line.points = paths[i]
		line.width = 210.0
		line.default_color = Color(0.42, 0.34, 0.25, 1.0)


# 配置地图四周的空气墙。
func _create_boundaries() -> void:
	_configure_boundary("NorthWall", Vector2(MAP_SIZE.x * 0.5, -32.0), Vector2(MAP_SIZE.x + 128.0, 64.0))
	_configure_boundary("SouthWall", Vector2(MAP_SIZE.x * 0.5, MAP_SIZE.y + 32.0), Vector2(MAP_SIZE.x + 128.0, 64.0))
	_configure_boundary("WestWall", Vector2(-32.0, MAP_SIZE.y * 0.5), Vector2(64.0, MAP_SIZE.y + 128.0))
	_configure_boundary("EastWall", Vector2(MAP_SIZE.x + 32.0, MAP_SIZE.y * 0.5), Vector2(64.0, MAP_SIZE.y + 128.0))


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


# 按种子生成树林障碍，避开道路和主要安全区。
func _generate_obstacles() -> void:
	_obstacle_rects.clear()
	var density_noise: FastNoiseLite = _make_noise(_map_seed, 0.0032)
	var detail_noise: FastNoiseLite = _make_noise(_map_seed + 719, 0.009)
	var candidates: Array[Dictionary] = _build_obstacle_candidates(density_noise)
	for item in candidates:
		if _obstacle_rects.size() >= obstacle_count:
			break
		var center: Vector2 = item["center"] as Vector2
		if _is_reserved_map_region(center, 96.0):
			continue
		var detail: float = detail_noise.get_noise_2d(center.x, center.y)
		var size: Vector2 = _pick_obstacle_size(detail)
		var rect: Rect2 = Rect2(center - size * 0.5, size).grow(40.0)
		if _rect_overlaps_any(rect):
			continue
		var obstacle: StaticBody2D = OBSTACLE_SCENE.instantiate() as StaticBody2D
		obstacle_container.add_child(obstacle)
		obstacle.call("setup", center, size, _pick_obstacle_color(detail))
		var footprint: Rect2 = obstacle.call("get_footprint")
		_obstacle_rects.append(footprint.grow(46.0))


# 生成被守护的房子。
func _spawn_house() -> void:
	_house = HOUSE_SCENE.instantiate() as Node2D
	if _house.has_method("set"):
		_house.set("data", HOUSE_DATA)
	world.add_child(_house)
	_house.global_position = HOUSE_POSITION
	_house.connect("health_changed", _on_house_health_changed)
	_house.connect("died", _on_house_died)


# 生成玩家并连接战斗相关回调。
func _spawn_player() -> void:
	_player = PLAYER_SCENE.instantiate() as Node2D
	world.add_child(_player)
	_player.global_position = PLAYER_START
	_player.connect("health_changed", _on_player_health_changed)
	_player.connect("died", _on_player_died)
	_player.connect("exp_changed", _on_player_exp_changed)
	_player.connect("level_ready", _on_player_level_ready)
	_player.call("apply_growth_modifiers", _get_stamina_growth_level())
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
	camera.limit_bottom = int(MAP_SIZE.y)
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
	hotbar.connect("anchor_selected", _on_hotbar_anchor_selected)
	hotbar.connect("wave_start_pressed", _on_wave_start_pressed)
	level_up_button.pressed.connect(_on_level_up_button_pressed)
	anchor_detail_panel.connect("closed", _on_anchor_detail_closed)
	anchor_detail_panel.connect("upgrade_requested", _on_anchor_upgrade_requested)
	anchor_detail_panel.connect("recycle_requested", _on_anchor_recycle_requested)
	recycle_dialog.connect("confirmed", _on_anchor_recycle_confirmed)
	recycle_dialog.connect("cancelled", _on_anchor_recycle_cancelled)
	level_up_panel.connect("option_selected", _on_level_up_option_selected)
	pause_screen.connect("continue_pressed", _on_pause_continue_pressed)
	pause_screen.connect("setting_pressed", _on_pause_setting_pressed)
	pause_screen.connect("quit_pressed", _on_pause_quit_pressed)
	failure_screen.connect("retry_pressed", _on_failure_retry_pressed)
	failure_screen.connect("menu_pressed", _on_failure_menu_pressed)
	setting_screen.visibility_changed.connect(_on_setting_visibility_changed)
	setting_screen.set("is_in_menu_flag", false)
	pause_screen.visible = false
	setting_screen.visible = false
	failure_screen.visible = false
	level_up_button.visible = false
	recycle_dialog.visible = false
	skill_summary_panel.visible = false
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
	_clear_anchor_selection()
	set_game_state(GameState.COMBAT)


# 记录热栏当前选中的锚点类型。
func _on_hotbar_anchor_selected(anchor_id: String) -> void:
	_selected_anchor_id = anchor_id
	_refresh_hotbar()


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
	recycle_dialog.call("close_dialog")
	anchor_detail_panel.call("open_for_anchor", anchor)
	Engine.time_scale = SLOW_TIME_SCALE


# 关闭锚点详情，并在没有其他慢速面板时恢复时间。
func _on_anchor_detail_closed() -> void:
	anchor_detail_panel.call("close_panel")
	recycle_dialog.call("close_dialog")
	_restore_slow_time_if_clear()


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
	if PlayerModule.instance != null:
		PlayerModule.instance.gold -= cost
	if not bool(anchor.call("upgrade")):
		if PlayerModule.instance != null:
			PlayerModule.instance.gold += cost
		_show_center_notice("升级失败")
		return
	_apply_run_modifiers_to_anchor(anchor)
	_save_slot()
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
	if PlayerModule.instance != null:
		PlayerModule.instance.gold += refund
	if anchor_detail_panel.visible:
		anchor_detail_panel.call("close_panel")
	anchor.queue_free()
	_save_slot()
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
		if PlayerModule.instance != null:
			PlayerModule.instance.gold += final_amount
		_save_slot()
	elif kind == "exp" and is_instance_valid(_player):
		_player.call("add_exp", final_amount)
	_refresh_hotbar()
	if anchor_detail_panel.visible:
		anchor_detail_panel.call("refresh_current_anchor")
	_update_anchor_upgrade_affordances()
	_update_hud()


# 根据当前界面状态处理 Escape。
func _handle_pause_pressed() -> void:
	if recycle_dialog.visible:
		recycle_dialog.call("close_dialog")
		_restore_slow_time_if_clear()
		return
	if anchor_detail_panel.visible:
		_on_anchor_detail_closed()
		return
	if level_up_panel.visible:
		return
	if setting_screen.visible:
		setting_screen.call("close_modal")
		return
	if pause_screen.visible:
		_resume_game()
		return
	if _state == GameState.FAILURE:
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
	if setting_screen.visible or _exiting or _state == GameState.FAILURE:
		return
	if _settings_from_pause:
		_settings_from_pause = false
		pause_screen.call("open_modal")
		get_tree().paused = true


# 关闭暂停界面并恢复游戏。
func _resume_game() -> void:
	if _state == GameState.FAILURE:
		return
	pause_screen.call("close_modal")
	get_tree().paused = false
	_restore_slow_time_if_clear()


# 写回当前进度并切回菜单场景。
func _return_to_menu() -> void:
	if _exiting:
		return
	_exiting = true
	Engine.time_scale = 1.0
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_reset_saved_health_for_next_run()
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
	recycle_dialog.call("close_dialog")
	level_up_panel.call("close_panel")
	level_up_button.visible = false
	_reset_saved_health_for_next_run()
	_save_slot()
	failure_screen.call("set_summary", _kills, _get_gold())
	failure_screen.call("open_modal")
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
	var spawn_point: Vector2 = spawn_points[int(entry.get("spawn", 0)) % spawn_points.size()]
	enemy.global_position = spawn_point
	enemy.call(
		"setup",
		runtime,
		level,
		_house,
		_player,
		Callable(self, "_get_anchor_nodes"),
		Callable(self, "_spawn_summoned_pack")
	)
	enemy.connect("died", _on_enemy_died)


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
	if PlayerModule.instance != null:
		PlayerModule.instance.gold -= price
	_save_slot()
	_refresh_hotbar()
	_update_anchor_upgrade_affordances()
	_show_center_notice("%s 已放置" % str(stats.get("display_name", _selected_anchor_id)))
	_update_hud()


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
	preview_visual.color = Color(base_color.r, base_color.g, base_color.b, 0.4 if legal else 0.22)


# 检查当前位置是否允许放置锚点。
func _can_place_anchor_at(candidate_position: Vector2) -> bool:
	if _is_anchor_placement_blocked_region(candidate_position, 42.0):
		return false
	if is_instance_valid(_player) and candidate_position.distance_to(_player.global_position) < 78.0:
		return false
	for rect in _obstacle_rects:
		if rect.has_point(candidate_position):
			return false
	for node in _get_anchor_nodes():
		if is_instance_valid(node) and (node as Node2D).global_position.distance_to(candidate_position) < 82.0:
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


# 根据当前金币和选中状态刷新热栏。
func _refresh_hotbar() -> void:
	if _selected_anchor_id.is_empty():
		hotbar.call("set_shop_state", "", _get_gold())
		return
	var stats: Dictionary = AnchorDb.get_stats(_selected_anchor_id, 1)
	if stats.is_empty() or _get_gold() < int(stats.get("price", 0)):
		_selected_anchor_id = ""
	hotbar.call("set_shop_state", _selected_anchor_id, _get_gold())


# 根据已选卡牌重建本局运行时修正。
func _sync_run_modifiers_from_player() -> void:
	var selected_skill_ids: Array[int] = []
	if is_instance_valid(_player):
		for item in _player.get("selected_skill_ids") as Array:
			selected_skill_ids.append(int(item))
	_run_modifiers = SkillDb.build_run_modifiers(selected_skill_ids)
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
func _spawn_summoned_pack(enemy_id: String, level: int, center: Vector2, count: int, radius: float) -> void:
	var runtime: Dictionary = ENEMY_CATALOG.call("get_runtime_stats", enemy_id, level)
	if runtime.is_empty():
		return
	var safe_count: int = maxi(1, count)
	for i in range(safe_count):
		var enemy: CharacterBody2D = ENEMY_SCENE.instantiate() as CharacterBody2D
		enemy_container.add_child(enemy)
		var angle: float = TAU * float(i) / float(safe_count) + _rng.randf_range(-0.2, 0.2)
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
			Callable(self, "_spawn_summoned_pack")
		)
		enemy.connect("died", _on_enemy_died)


# 判断一个矩形是否与已有障碍占地重叠。
func _rect_overlaps_any(rect: Rect2) -> bool:
	for existing in _obstacle_rects:
		if rect.intersects(existing):
			return true
	return false


# 返回障碍和树林生成时需要避开的保留区，包含道路。
func _is_reserved_map_region(point: Vector2, radius: float) -> bool:
	if point.x < radius or point.y < radius or point.x > MAP_SIZE.x - radius or point.y > MAP_SIZE.y - radius:
		return true
	if point.distance_to(HOUSE_POSITION) < 240.0 + radius:
		return true
	if point.distance_to(PLAYER_START) < 260.0 + radius:
		return true
	for spawn_point in _get_spawn_points():
		if point.distance_to(spawn_point) < 260.0 + radius:
			return true
	for path in _get_road_paths():
		if _distance_to_polyline(point, path) < 126.0 + radius:
			return true
	return false


# 返回锚点放置时要避开的区域，不再把道路视为禁放区。
func _is_anchor_placement_blocked_region(point: Vector2, radius: float) -> bool:
	if point.x < radius or point.y < radius or point.x > MAP_SIZE.x - radius or point.y > MAP_SIZE.y - radius:
		return true
	if point.distance_to(HOUSE_POSITION) < 240.0 + radius:
		return true
	if point.distance_to(PLAYER_START) < 120.0 + radius:
		return true
	for spawn_point in _get_spawn_points():
		if point.distance_to(spawn_point) < 200.0 + radius:
			return true
	return false


# 构建带种子的噪声采样器。
func _make_noise(noise_seed: int, frequency: float) -> FastNoiseLite:
	var noise: FastNoiseLite = FastNoiseLite.new()
	noise.seed = noise_seed
	noise.frequency = frequency
	noise.fractal_octaves = 3
	noise.fractal_lacunarity = 2.1
	noise.fractal_gain = 0.5
	return noise


# 从密度噪声里生成排序后的障碍候选点。
func _build_obstacle_candidates(noise: FastNoiseLite) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	var y: float = 180.0
	while y <= MAP_SIZE.y - 180.0:
		var x: float = 180.0
		while x <= MAP_SIZE.x - 180.0:
			var score: float = noise.get_noise_2d(x, y)
			if score >= obstacle_noise_threshold:
				var jitter: Vector2 = Vector2(
					_rng.randf_range(-obstacle_cell_size * 0.32, obstacle_cell_size * 0.32),
					_rng.randf_range(-obstacle_cell_size * 0.32, obstacle_cell_size * 0.32)
				)
				candidates.append({"center": Vector2(x, y) + jitter, "score": score})
			x += obstacle_cell_size
		y += obstacle_cell_size
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["score"]) > float(b["score"])
	)
	return candidates


# 根据细节噪声挑选障碍尺寸。
func _pick_obstacle_size(detail: float) -> Vector2:
	if detail > 0.22:
		return Vector2(_rng.randf_range(54.0, 88.0), _rng.randf_range(146.0, 260.0))
	if detail < -0.24:
		return Vector2(_rng.randf_range(128.0, 220.0), _rng.randf_range(92.0, 178.0))
	return Vector2(_rng.randf_range(88.0, 178.0), _rng.randf_range(78.0, 170.0))


# 根据噪声挑选占位障碍颜色。
func _pick_obstacle_color(detail: float) -> Color:
	if detail > 0.18:
		return Color(0.12, 0.36, 0.17, 1.0)
	if detail < -0.20:
		return Color(0.38, 0.38, 0.35, 1.0)
	return Color(0.18, 0.43, 0.20, 1.0)


# 返回地图草图上的三个固定出生点。
func _get_spawn_points() -> Array[Vector2]:
	return [
		Vector2(5420.0, 1700.0),
		Vector2(2980.0, 3040.0),
		Vector2(3560.0, 3040.0),
	]


# 返回道路折线，用于绘制和道路保留区计算。
func _get_road_paths() -> Array[PackedVector2Array]:
	return [
		PackedVector2Array([Vector2(420.0, 1640.0), Vector2(1580.0, 1640.0), Vector2(2780.0, 1640.0), Vector2(3960.0, 1640.0), Vector2(5420.0, 1700.0)]),
		PackedVector2Array([Vector2(2980.0, 3040.0), Vector2(2920.0, 2500.0), Vector2(2860.0, 2100.0), Vector2(2780.0, 1640.0)]),
		PackedVector2Array([Vector2(3560.0, 3040.0), Vector2(3420.0, 2460.0), Vector2(3240.0, 2040.0), Vector2(2780.0, 1640.0)]),
	]


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
	if anchor_detail_panel.visible or level_up_panel.visible:
		Engine.time_scale = SLOW_TIME_SCALE
	else:
		Engine.time_scale = 1.0


# 刷新顶部 HUD、经验条和当前已获能力展示。
func _update_hud() -> void:
	gold_label.text = "金币 %d" % _get_gold()
	var total_waves: int = _get_total_waves()
	wave_label.text = "第 %d/%d 波  击杀 %d" % [mini(_wave_index + 1, total_waves), total_waves, _kills]
	if is_instance_valid(_player) and hp_orb != null and hp_orb.has_method("set_meter"):
		var current_hp: float = _player.get("current_hp")
		var max_hp: float = _player.get("max_hp")
		var hp_ratio: float = current_hp / max_hp if max_hp > 0.0 else 0.0
		hp_orb.call("set_meter", current_hp, max_hp, hp_ratio, hp_ratio <= 0.35)
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


# 重置存档血量，避免失败后下次进入直接残血。
func _reset_saved_health_for_next_run() -> void:
	if PlayerModule.instance == null:
		return
	PlayerModule.instance.hp = PlayerModule.instance.max_hp


# 返回当前存档槽中的金币数量。
func _get_gold() -> int:
	if PlayerModule.instance == null:
		return 0
	return PlayerModule.instance.gold


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
