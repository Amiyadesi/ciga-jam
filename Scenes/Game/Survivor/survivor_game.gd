class_name SurvivorGame
extends Node2D
## Composition root for the CIGA survivor tower-defense vertical slice.

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
const TOTAL_WAVES: int = 3
const PLAYER_SCENE: PackedScene = preload("res://Scenes/Game/Survivor/player.tscn")
const ENEMY_SCENE: PackedScene = preload("res://Scenes/Game/Survivor/enemy.tscn")
const OBSTACLE_SCENE: PackedScene = preload("res://Scenes/Game/Survivor/obstacle.tscn")
const HOUSE_SCENE: PackedScene = preload("res://Scenes/Game/Survivor/house.tscn")
const ANCHOR_SCENE: PackedScene = preload("res://Scenes/Game/Survivor/magic_anchor.tscn")
const PICKUP_SCENE: PackedScene = preload("res://Scenes/Game/Survivor/pickup.tscn")
const AnchorDb = preload("res://Scenes/Game/Survivor/anchor_database.gd")
const SkillDb = preload("res://Scenes/Game/Survivor/skill_database.gd")
const HOUSE_DATA = preload("res://Scenes/Game/Survivor/Data/house_default.tres")
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
@onready var house_label: Label = $HUD/Root/TopBar/HouseLabel
@onready var stamina_orb: Control = $HUD/Root/TopBar/StaminaOrb
@onready var wave_label: Label = $HUD/Root/WaveLabel
@onready var status_label: Label = $HUD/Root/StatusLabel
@onready var hotbar: Control = $HUD/Root/Hotbar
@onready var level_up_button: Button = $HUD/Root/LevelUpButton
@onready var anchor_detail_panel: Control = $HUD/Root/AnchorDetailPanel
@onready var level_up_panel: Control = $HUD/Root/LevelUpPanel
@onready var exp_progress_bar: ProgressBar = $HUD/Root/ExpProgressBar
@onready var pause_screen: Control = $HUD/PauseScreen
@onready var setting_screen: Control = $HUD/SettingScreen
@onready var failure_screen: Control = $HUD/FailureScreen

var _state: GameState = GameState.PREPARE
var _player: Node2D
var _house: Node2D
var _kills: int = 0
var _wave_index: int = 0
var _spawn_queue: Array[Dictionary] = []
var _spawn_timer: float = 0.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _map_seed: int = 0
var _obstacle_rects: Array[Rect2] = []
var _selected_anchor_id: String = ""
var _anchor_inventory: Dictionary = {"xiu_xiu": 3, "double_xiu_xiu": 1, "mine": 2}
var _exiting: bool = false
var _settings_from_pause: bool = false
var _pending_level_up: bool = false
var _screen_shake_time: float = 0.0
var _screen_shake_strength: float = 0.0
var _screen_shake_total_time: float = 0.0
var _camera_base_position: Vector2 = Vector2.ZERO


# Builds the CIGA runtime map, entities, HUD, and modal connections.
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


# Drives spawning, placement previews, and wave completion checks.
func _process(delta: float) -> void:
	_update_placement_preview()
	_update_anchor_upgrade_affordances()
	_update_screen_shake(delta)
	if _exiting or _state != GameState.COMBAT:
		return
	_update_spawn_queue(delta)
	_check_wave_completion()


# Handles pause, slow-time panel exits, and placement mouse input after UI.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		_handle_pause_pressed()
		get_viewport().set_input_as_handled()
		return
	if _state == GameState.PREPARE or _state == GameState.WAVE_CLEAR:
		if event is InputEventMouseButton:
			var mouse_event: InputEventMouseButton = event as InputEventMouseButton
			if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
				_try_place_selected_anchor()
				get_viewport().set_input_as_handled()
			elif mouse_event.button_index == MOUSE_BUTTON_RIGHT and mouse_event.pressed:
				_clear_anchor_selection()
				get_viewport().set_input_as_handled()


# Restores global state and saves the slot when leaving the scene.
func _exit_tree() -> void:
	Engine.time_scale = 1.0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_save_slot()


# Changes game state and updates HUD affordances.
func set_game_state(new_state: GameState) -> void:
	_state = new_state
	match _state:
		GameState.PREPARE:
			Engine.time_scale = 1.0
			get_tree().paused = false
			status_label.text = "准备阶段：放置锚点后点击底部开始战斗。"
			hotbar.call("set_prepare_state", true, _wave_index + 1, TOTAL_WAVES)
		GameState.COMBAT:
			Engine.time_scale = 1.0
			get_tree().paused = false
			status_label.text = "第 %d 波战斗中。" % (_wave_index + 1)
			hotbar.call("set_prepare_state", false, _wave_index + 1, TOTAL_WAVES)
		GameState.WAVE_CLEAR:
			Engine.time_scale = 1.0
			get_tree().paused = false
			status_label.text = "本波结束，继续布置锚点。"
			hotbar.call("set_prepare_state", true, _wave_index + 1, TOTAL_WAVES)
		GameState.VICTORY:
			Engine.time_scale = 1.0
			status_label.text = "3 波竖切完成。金币已保存。"
			hotbar.call("set_prepare_state", false, TOTAL_WAVES, TOTAL_WAVES)
			_save_slot()
		GameState.FAILURE:
			Engine.time_scale = 1.0
			hotbar.call("set_prepare_state", false, _wave_index + 1, TOTAL_WAVES)
	_update_hud()


# Initializes or loads slot data without overwriting existing gold.
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


# Creates ground, roads, boundaries, and forest obstacles.
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


# Draws the two-road sketch as authored Line2D placeholders.
func _configure_roads() -> void:
	var paths: Array[PackedVector2Array] = _get_road_paths()
	for i in range(paths.size()):
		var line: Line2D = road_container.get_node("Road%d" % (i + 1)) as Line2D
		if line == null:
			continue
		line.points = paths[i]
		line.width = 210.0
		line.default_color = Color(0.42, 0.34, 0.25, 1.0)


# Configures the authored collision walls around the map.
func _create_boundaries() -> void:
	_configure_boundary("NorthWall", Vector2(MAP_SIZE.x * 0.5, -32.0), Vector2(MAP_SIZE.x + 128.0, 64.0))
	_configure_boundary("SouthWall", Vector2(MAP_SIZE.x * 0.5, MAP_SIZE.y + 32.0), Vector2(MAP_SIZE.x + 128.0, 64.0))
	_configure_boundary("WestWall", Vector2(-32.0, MAP_SIZE.y * 0.5), Vector2(64.0, MAP_SIZE.y + 128.0))
	_configure_boundary("EastWall", Vector2(MAP_SIZE.x + 32.0, MAP_SIZE.y * 0.5), Vector2(64.0, MAP_SIZE.y + 128.0))


# Applies size and position to one authored boundary body.
func _configure_boundary(name: String, center: Vector2, size: Vector2) -> void:
	var body: StaticBody2D = boundary_container.get_node(name) as StaticBody2D
	if body == null:
		push_error("SurvivorGame: missing boundary '%s'" % name)
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


# Generates seeded obstacle clusters outside roads and safety zones.
func _generate_obstacles() -> void:
	_obstacle_rects.clear()
	var density_noise: FastNoiseLite = _make_noise(_map_seed, 0.0032)
	var detail_noise: FastNoiseLite = _make_noise(_map_seed + 719, 0.009)
	var candidates: Array[Dictionary] = _build_obstacle_candidates(density_noise)
	for item in candidates:
		if _obstacle_rects.size() >= obstacle_count:
			break
		var center: Vector2 = item["center"] as Vector2
		if _is_blocked_map_region(center, 96.0):
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


# Adds the defended house target to the world.
func _spawn_house() -> void:
	_house = HOUSE_SCENE.instantiate() as Node2D
	if _house.has_method("set"):
		_house.set("data", HOUSE_DATA)
	world.add_child(_house)
	_house.global_position = HOUSE_POSITION
	_house.connect("health_changed", _on_house_health_changed)
	_house.connect("died", _on_house_died)


# Adds the player instance and wires combat callbacks.
func _spawn_player() -> void:
	_player = PLAYER_SCENE.instantiate() as Node2D
	world.add_child(_player)
	_player.global_position = PLAYER_START
	_player.connect("health_changed", _on_player_health_changed)
	_player.connect("died", _on_player_died)
	_player.connect("stamina_changed", _on_player_stamina_changed)
	_player.connect("exp_changed", _on_player_exp_changed)
	_player.connect("level_ready", _on_player_level_ready)
	_player.call("apply_growth_modifiers", _get_stamina_growth_level())
	if PlayerModule.instance != null:
		_player.call("apply_saved_health", PlayerModule.instance.hp, PlayerModule.instance.max_hp)


# Sets a bounded camera that follows the player near map edges.
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


# Connects authored UI and modal buttons.
func _connect_ui() -> void:
	pause_screen.process_mode = Node.PROCESS_MODE_ALWAYS
	setting_screen.process_mode = Node.PROCESS_MODE_ALWAYS
	failure_screen.process_mode = Node.PROCESS_MODE_ALWAYS
	hotbar.connect("anchor_selected", _on_hotbar_anchor_selected)
	hotbar.connect("wave_start_pressed", _on_wave_start_pressed)
	level_up_button.pressed.connect(_on_level_up_button_pressed)
	anchor_detail_panel.connect("closed", _on_anchor_detail_closed)
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
	hotbar.call("set_inventory", _anchor_inventory, _selected_anchor_id)


# Starts the current wave without saving slot progress.
func _on_wave_start_pressed() -> void:
	if _state != GameState.PREPARE and _state != GameState.WAVE_CLEAR:
		return
	if _wave_index >= TOTAL_WAVES:
		set_game_state(GameState.VICTORY)
		return
	_spawn_queue = _build_wave_queue(_wave_index)
	_spawn_timer = 0.0
	_clear_anchor_selection()
	set_game_state(GameState.COMBAT)


# Updates selected anchor id from the bottom hotbar.
func _on_hotbar_anchor_selected(anchor_id: String) -> void:
	_selected_anchor_id = anchor_id
	hotbar.call("set_inventory", _anchor_inventory, _selected_anchor_id)


# Opens slow-time growth selection when the player has enough EXP.
func _on_level_up_button_pressed() -> void:
	if not _pending_level_up:
		return
	var selected_skill_ids: Array[int] = _player.get("selected_skill_ids") as Array[int]
	var options: Array[Dictionary] = SkillDb.get_available_options({"selected_skill_ids": selected_skill_ids}, 3)
	if options.is_empty():
		_pending_level_up = false
		level_up_button.visible = false
		return
	Engine.time_scale = SLOW_TIME_SCALE
	level_up_panel.call("open_options", options)
	level_up_button.visible = false


# Applies the chosen in-run skill and restores normal time.
func _on_level_up_option_selected(skill_id: int) -> void:
	level_up_panel.call("close_panel")
	_player.call("level_up_with_skill", skill_id)
	_pending_level_up = int(_player.get("current_exp")) >= int(_player.call("get_required_exp_for_next_level"))
	level_up_button.visible = _pending_level_up
	_restore_slow_time_if_clear()
	_update_hud()


# Opens the anchor detail panel and enters slow time.
func _on_anchor_detail_requested(anchor: Node) -> void:
	if _state == GameState.FAILURE:
		return
	anchor_detail_panel.call("open_for_anchor", anchor)
	Engine.time_scale = SLOW_TIME_SCALE


# Closes anchor detail and restores normal time if no other slow modal is open.
func _on_anchor_detail_closed() -> void:
	anchor_detail_panel.call("close_panel")
	_restore_slow_time_if_clear()


# Pays for and applies an anchor upgrade when affordable.
func _on_anchor_upgrade_requested(anchor: Node) -> void:
	if not is_instance_valid(anchor):
		return
	var cost: int = AnchorDb.get_upgrade_cost(str(anchor.get("anchor_id")), int(anchor.get("level")))
	if cost <= 0 or _get_gold() < cost:
		return
	if PlayerModule.instance != null:
		PlayerModule.instance.gold -= cost
	anchor.call("upgrade")
	_save_slot()
	_update_hud()


# Updates player HP and mirrors it into the slot module.
func _on_player_health_changed(current_hp: int, max_hp: int) -> void:
	if PlayerModule.instance != null:
		PlayerModule.instance.hp = current_hp
		PlayerModule.instance.max_hp = max_hp
	_update_hud()


# Fails the run when the player dies.
func _on_player_died() -> void:
	_fail_run("玩家倒下了。")


# Updates house HP in the HUD.
func _on_house_health_changed(_current_hp: int, _max_hp: int) -> void:
	_update_hud()


# Fails the run when the defended house is destroyed.
func _on_house_died() -> void:
	_fail_run("房子被魔物摧毁了。")


# Updates EXP display and reveals the level-up button when ready.
func _on_player_exp_changed(_current_exp: int, _required_exp: int, _level: int) -> void:
	_update_hud()


# Marks a pending level-up selection.
func _on_player_level_ready() -> void:
	_pending_level_up = true
	level_up_button.visible = true


# Updates the liquid stamina HUD from player state.
func _on_player_stamina_changed(current: float, max_value: float, ratio: float, is_sprinting: bool) -> void:
	if stamina_orb != null and stamina_orb.has_method("set_stamina"):
		stamina_orb.call("set_stamina", current, max_value, ratio, is_sprinting)


# Drops rewards when an enemy dies.
func _on_enemy_died(enemy: Node, gold_reward: int, exp_reward: int) -> void:
	_kills += 1
	if enemy is Node2D:
		var pos: Vector2 = (enemy as Node2D).global_position
		_spawn_pickup("gold", gold_reward, pos + Vector2(-16.0, 0.0))
		_spawn_pickup("exp", exp_reward, pos + Vector2(16.0, 0.0))
	_update_hud()


# Applies pickup effects to the player and slot save.
func _on_pickup_collected(kind: String, amount: int) -> void:
	if kind == "gold":
		if PlayerModule.instance != null:
			PlayerModule.instance.gold += amount
		_save_slot()
	elif kind == "exp" and is_instance_valid(_player):
		_player.call("add_exp", amount)
	_update_hud()


# Handles Escape depending on current modal state.
func _handle_pause_pressed() -> void:
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


# Resumes combat from the pause modal.
func _on_pause_continue_pressed() -> void:
	_resume_game()


# Opens settings from pause and keeps the pause context.
func _on_pause_setting_pressed() -> void:
	_settings_from_pause = true
	pause_screen.call("close_modal")
	setting_screen.call("open_modal")
	get_tree().paused = true


# Saves and returns to the main menu from pause.
func _on_pause_quit_pressed() -> void:
	_return_to_menu()


# Restarts the combat scene from the failure modal.
func _on_failure_retry_pressed() -> void:
	_retry_run()


# Returns to the menu from the failure modal.
func _on_failure_menu_pressed() -> void:
	_return_to_menu()


# Reopens pause when settings closes from the in-run pause flow.
func _on_setting_visibility_changed() -> void:
	if setting_screen.visible or _exiting or _state == GameState.FAILURE:
		return
	if _settings_from_pause:
		_settings_from_pause = false
		pause_screen.call("open_modal")
		get_tree().paused = true


# Closes pause UI and restores combat time.
func _resume_game() -> void:
	if _state == GameState.FAILURE:
		return
	pause_screen.call("close_modal")
	get_tree().paused = false
	_restore_slow_time_if_clear()


# Writes current progress and changes to the menu scene.
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


# Saves and reloads the current combat scene through a transition.
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


# Fails the run, saves earned gold, and opens the failure modal.
func _fail_run(reason: String) -> void:
	if _state == GameState.FAILURE:
		return
	set_game_state(GameState.FAILURE)
	status_label.text = reason
	_spawn_queue.clear()
	placement_preview.visible = false
	anchor_detail_panel.call("close_panel")
	level_up_panel.call("close_panel")
	level_up_button.visible = false
	_reset_saved_health_for_next_run()
	_save_slot()
	failure_screen.call("set_summary", _kills, _get_gold())
	failure_screen.call("open_modal")
	get_tree().paused = true


# Spawns enemies from the queued wave definitions.
func _update_spawn_queue(delta: float) -> void:
	if _spawn_queue.is_empty():
		return
	_spawn_timer -= delta
	if _spawn_timer > 0.0:
		return
	var entry: Dictionary = _spawn_queue.pop_front()
	_spawn_enemy(entry)
	_spawn_timer = float(entry.get("interval", 0.8))


# Ends a wave when all planned spawns and active enemies are gone.
func _check_wave_completion() -> void:
	if not _spawn_queue.is_empty():
		return
	if get_tree().get_nodes_in_group("enemies").size() > 0:
		return
	_wave_index += 1
	if _wave_index >= TOTAL_WAVES:
		set_game_state(GameState.VICTORY)
	else:
		set_game_state(GameState.WAVE_CLEAR)


# Instantiates one enemy from a wave queue entry.
func _spawn_enemy(entry: Dictionary) -> void:
	var enemy: CharacterBody2D = ENEMY_SCENE.instantiate() as CharacterBody2D
	enemy_container.add_child(enemy)
	var spawn_points: Array[Vector2] = _get_spawn_points()
	var spawn_point: Vector2 = spawn_points[int(entry.get("spawn", 0)) % spawn_points.size()]
	enemy.global_position = spawn_point
	enemy.call("setup", str(entry.get("type", "slime")), int(entry.get("level", 1)), _house, _player, Callable(self, "_get_anchor_nodes"))
	enemy.connect("died", _on_enemy_died)


# Creates a pickup and wires its collection signal.
func _spawn_pickup(kind: String, amount: int, position: Vector2) -> void:
	var pickup: Area2D = PICKUP_SCENE.instantiate() as Area2D
	pickup_container.add_child(pickup)
	pickup.global_position = position
	pickup.call("setup", kind, amount, _player)
	pickup.connect("collected", _on_pickup_collected)


# Builds an expanded spawn queue for one of the three prototype waves.
func _build_wave_queue(wave: int) -> Array[Dictionary]:
	var specs: Array[Dictionary] = []
	match wave:
		0:
			specs = [
				{"type": "slime", "level": 1, "count": 6, "spawn": 0, "interval": 0.75},
			]
		1:
			specs = [
				{"type": "slime", "level": 2, "count": 7, "spawn": 0, "interval": 0.65},
				{"type": "bat", "level": 1, "count": 3, "spawn": 1, "interval": 0.75},
			]
		_:
			specs = [
				{"type": "slime", "level": 3, "count": 8, "spawn": 0, "interval": 0.55},
				{"type": "bat", "level": 2, "count": 5, "spawn": 2, "interval": 0.62},
			]
	var queue: Array[Dictionary] = []
	for spec in specs:
		for _i in range(int(spec.get("count", 1))):
			queue.append(spec.duplicate(true))
	return queue


# Tries to place the selected anchor at the mouse world position.
func _try_place_selected_anchor() -> void:
	if _selected_anchor_id.is_empty() or int(_anchor_inventory.get(_selected_anchor_id, 0)) <= 0:
		return
	var position: Vector2 = get_global_mouse_position()
	if not _can_place_anchor_at(position):
		status_label.text = "这里不能放置锚点。"
		return
	var anchor: StaticBody2D = ANCHOR_SCENE.instantiate() as StaticBody2D
	anchor_container.add_child(anchor)
	anchor.global_position = position
	var stats: Dictionary = AnchorDb.get_stats(_selected_anchor_id, 1)
	anchor.call("setup", _selected_anchor_id, 1, stats)
	anchor.connect("open_detail_requested", _on_anchor_detail_requested)
	anchor.connect("upgrade_requested", _on_anchor_upgrade_requested)
	anchor.connect("died", _on_anchor_died)
	_anchor_inventory[_selected_anchor_id] = int(_anchor_inventory.get(_selected_anchor_id, 0)) - 1
	if int(_anchor_inventory.get(_selected_anchor_id, 0)) <= 0:
		_selected_anchor_id = ""
	hotbar.call("set_inventory", _anchor_inventory, _selected_anchor_id)
	status_label.text = "锚点已放置。"


# Removes dead anchors from local affordance updates.
func _on_anchor_died(_anchor: Node) -> void:
	_update_anchor_upgrade_affordances()


# Clears the current hotbar selection.
func _clear_anchor_selection() -> void:
	_selected_anchor_id = ""
	hotbar.call("set_inventory", _anchor_inventory, _selected_anchor_id)
	placement_preview.visible = false


# Updates transparent placement preview under the mouse.
func _update_placement_preview() -> void:
	if _selected_anchor_id.is_empty() or (_state != GameState.PREPARE and _state != GameState.WAVE_CLEAR):
		placement_preview.visible = false
		return
	var mouse_world: Vector2 = get_global_mouse_position()
	placement_preview.visible = true
	placement_preview.global_position = mouse_world
	var legal: bool = _can_place_anchor_at(mouse_world)
	var stats: Dictionary = AnchorDb.get_stats(_selected_anchor_id, 1)
	var base_color: Color = stats.get("color", Color(0.42, 0.75, 1.0, 1.0))
	preview_visual.color = Color(base_color.r, base_color.g, base_color.b, 0.4 if legal else 0.22)


# Checks all placement rules for a proposed anchor position.
func _can_place_anchor_at(position: Vector2) -> bool:
	if _is_blocked_map_region(position, 42.0):
		return false
	if is_instance_valid(_player) and position.distance_to(_player.global_position) < 78.0:
		return false
	for rect in _obstacle_rects:
		if rect.has_point(position):
			return false
	for node in _get_anchor_nodes():
		if is_instance_valid(node) and (node as Node2D).global_position.distance_to(position) < 82.0:
			return false
	return true


# Updates world upgrade buttons for anchors near the player.
func _update_anchor_upgrade_affordances() -> void:
	if not is_instance_valid(_player):
		return
	for node in _get_anchor_nodes():
		if not (node is Node2D):
			continue
		var anchor: Node2D = node as Node2D
		var near: bool = anchor.global_position.distance_to(_player.global_position) <= 50.0
		anchor.call("set_upgrade_visible", near and _state != GameState.FAILURE, _get_gold())


# Returns current placed anchors as an array for enemy AI.
func _get_anchor_nodes() -> Array:
	return anchor_container.get_children()


# Reports whether a new obstacle or placement rectangle overlaps existing blockers.
func _rect_overlaps_any(rect: Rect2) -> bool:
	for existing in _obstacle_rects:
		if rect.intersects(existing):
			return true
	return false


# Returns whether a point is blocked by map bounds, roads, house, spawns, or safe zones.
func _is_blocked_map_region(position: Vector2, radius: float) -> bool:
	if position.x < radius or position.y < radius or position.x > MAP_SIZE.x - radius or position.y > MAP_SIZE.y - radius:
		return true
	if position.distance_to(HOUSE_POSITION) < 240.0 + radius:
		return true
	if position.distance_to(PLAYER_START) < 260.0 + radius:
		return true
	for spawn_point in _get_spawn_points():
		if position.distance_to(spawn_point) < 260.0 + radius:
			return true
	for path in _get_road_paths():
		if _distance_to_polyline(position, path) < 126.0 + radius:
			return true
	return false


# Builds a reusable FastNoiseLite instance for seeded map sampling.
func _make_noise(seed: int, frequency: float) -> FastNoiseLite:
	var noise: FastNoiseLite = FastNoiseLite.new()
	noise.seed = seed
	noise.frequency = frequency
	noise.fractal_octaves = 3
	noise.fractal_lacunarity = 2.1
	noise.fractal_gain = 0.5
	return noise


# Produces sorted obstacle candidate points from density noise.
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


# Chooses obstacle dimensions from noise.
func _pick_obstacle_size(detail: float) -> Vector2:
	if detail > 0.22:
		return Vector2(_rng.randf_range(54.0, 88.0), _rng.randf_range(146.0, 260.0))
	if detail < -0.24:
		return Vector2(_rng.randf_range(128.0, 220.0), _rng.randf_range(92.0, 178.0))
	return Vector2(_rng.randf_range(88.0, 178.0), _rng.randf_range(78.0, 170.0))


# Chooses placeholder colors from noise.
func _pick_obstacle_color(detail: float) -> Color:
	if detail > 0.18:
		return Color(0.12, 0.36, 0.17, 1.0)
	if detail < -0.20:
		return Color(0.38, 0.38, 0.35, 1.0)
	return Color(0.18, 0.43, 0.20, 1.0)


# Returns the fixed enemy spawn points from the map sketch.
func _get_spawn_points() -> Array[Vector2]:
	return [
		Vector2(5420.0, 1700.0),
		Vector2(2980.0, 3040.0),
		Vector2(3560.0, 3040.0),
	]


# Returns the placeholder road polylines used by drawing and blocker checks.
func _get_road_paths() -> Array[PackedVector2Array]:
	return [
		PackedVector2Array([Vector2(420.0, 1640.0), Vector2(1580.0, 1640.0), Vector2(2780.0, 1640.0), Vector2(3960.0, 1640.0), Vector2(5420.0, 1700.0)]),
		PackedVector2Array([Vector2(2980.0, 3040.0), Vector2(2920.0, 2500.0), Vector2(2860.0, 2100.0), Vector2(2780.0, 1640.0)]),
		PackedVector2Array([Vector2(3560.0, 3040.0), Vector2(3420.0, 2460.0), Vector2(3240.0, 2040.0), Vector2(2780.0, 1640.0)]),
	]


# Computes shortest distance from a point to a polyline.
func _distance_to_polyline(point: Vector2, path: PackedVector2Array) -> float:
	var best: float = INF
	for i in range(path.size() - 1):
		best = minf(best, _distance_to_segment(point, path[i], path[i + 1]))
	return best


# Computes shortest distance from a point to a finite segment.
func _distance_to_segment(point: Vector2, start: Vector2, finish: Vector2) -> float:
	var segment: Vector2 = finish - start
	var length_sq: float = segment.length_squared()
	if is_zero_approx(length_sq):
		return point.distance_to(start)
	var t: float = clampf((point - start).dot(segment) / length_sq, 0.0, 1.0)
	return point.distance_to(start + segment * t)


# Restores normal time unless another slow-time panel remains open.
func _restore_slow_time_if_clear() -> void:
	if anchor_detail_panel.visible or level_up_panel.visible:
		Engine.time_scale = SLOW_TIME_SCALE
	else:
		Engine.time_scale = 1.0


# Refreshes HUD labels from runtime and save-module state.
func _update_hud() -> void:
	gold_label.text = "金币 %d" % _get_gold()
	wave_label.text = "第 %d/%d 波  击杀 %d" % [mini(_wave_index + 1, TOTAL_WAVES), TOTAL_WAVES, _kills]
	if is_instance_valid(_house):
		house_label.text = "房子 %d/%d" % [int(round(_house.get("current_hp"))), int(round(_house.get("max_hp")))]
	else:
		house_label.text = "房子 --/--"
	if is_instance_valid(_player) and hp_orb != null and hp_orb.has_method("set_meter"):
		var current_hp: float = _player.get("current_hp")
		var max_hp: float = _player.get("max_hp")
		var hp_ratio: float = current_hp / max_hp if max_hp > 0.0 else 0.0
		hp_orb.call("set_meter", current_hp, max_hp, hp_ratio, hp_ratio <= 0.35)
	if exp_progress_bar != null and is_instance_valid(_player):
		var current_exp: int = int(_player.get("current_exp"))
		var required_exp: int = int(_player.call("get_required_exp_for_next_level"))
		exp_progress_bar.max_value = maxf(1.0, float(required_exp))
		exp_progress_bar.value = current_exp
		exp_progress_bar.show_percentage = false
		exp_progress_bar.tooltip_text = "Lv.%d  EXP %d/%d" % [int(_player.get("level")), current_exp, required_exp]


# Persists the active player slot through the existing SaveSystem.
func _save_slot() -> void:
	if PlayerModule.instance != null and is_instance_valid(_player):
		PlayerModule.instance.position = _player.global_position
		PlayerModule.instance.scene_path = scene_file_path
	var save_system: Node = _get_save_system()
	if save_system != null and save_system.has_method("save_slot"):
		save_system.call("save_slot", run_slot)


# Finds the SaveSystem autoload at runtime.
func _get_save_system() -> Node:
	if get_tree() == null or get_tree().root == null:
		return null
	return get_tree().root.get_node_or_null("SaveSystem")


# Finds the SceneManager autoload when the plugin is enabled.
func _get_scene_manager() -> Node:
	if get_tree() == null or get_tree().root == null:
		return null
	return get_tree().root.get_node_or_null("SceneManager")


# Creates or retrieves the saved map seed for this slot.
func _ensure_map_seed() -> int:
	var custom: Dictionary = PlayerModule.instance.custom
	if not custom.has("survivor_map_seed"):
		var seed_rng: RandomNumberGenerator = RandomNumberGenerator.new()
		seed_rng.randomize()
		custom["survivor_map_seed"] = int(seed_rng.randi_range(1, 2147483646))
	return int(custom.get("survivor_map_seed", 1))


# Reads the permanent stamina upgrade level from slot custom data.
func _get_stamina_growth_level() -> int:
	if PlayerModule.instance == null:
		return 0
	return int(PlayerModule.instance.custom.get("stamina_level", 0))


# Restores saved HP so a failed run does not soft-lock future entries.
func _reset_saved_health_for_next_run() -> void:
	if PlayerModule.instance == null:
		return
	PlayerModule.instance.hp = PlayerModule.instance.max_hp


# Returns the current slot gold for HUD and result screens.
func _get_gold() -> int:
	if PlayerModule.instance == null:
		return 0
	return PlayerModule.instance.gold


# Plays the scene-enter fade if SceneManager is available.
func _play_enter_transition() -> void:
	var scene_manager: Node = _get_scene_manager()
	if scene_manager != null and scene_manager.has_method("transition_start"):
		scene_manager.call("transition_start", ENTER_TRANSITION, true)


# Applies one configurable screen shake burst from gameplay events.
func apply_screen_shake(strength: float, duration: float) -> void:
	var setting_strength: float = float(SettingsModule.instance.get_value("screen_shake", 0.5)) if SettingsModule.instance != null else 0.5
	if setting_strength <= 0.0:
		return
	_screen_shake_strength = maxf(_screen_shake_strength, strength * setting_strength * 12.0)
	_screen_shake_time = maxf(_screen_shake_time, duration)
	_screen_shake_total_time = maxf(_screen_shake_total_time, duration)


# Updates the camera local offset while a shake burst is active.
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


# Changes to a different scene after the configured fade-out transition.
func _change_scene_with_transition(path: String) -> void:
	var scene_manager: Node = _get_scene_manager()
	if scene_manager != null and scene_manager.has_method("transition_start") and scene_manager.has_method("change_scene_to_file"):
		var tween: Tween = scene_manager.call("transition_start", EXIT_TRANSITION)
		if tween != null:
			await tween.finished
		scene_manager.call("change_scene_to_file", path)
	else:
		get_tree().change_scene_to_file(path)


# Reloads this scene after the configured fade-out transition.
func _reload_scene_with_transition() -> void:
	var scene_manager: Node = _get_scene_manager()
	if scene_manager != null and scene_manager.has_method("transition_start") and scene_manager.has_method("reload_current_scene"):
		var tween: Tween = scene_manager.call("transition_start", EXIT_TRANSITION)
		if tween != null:
			await tween.finished
		scene_manager.call("reload_current_scene")
	else:
		get_tree().reload_current_scene()
