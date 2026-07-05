extends Node
## 全局音频路由，统一管理局内外音乐、常用音效和按钮音频配置。

const DEFAULT_BUS_LAYOUT: AudioBusLayout = preload("res://default_bus_layout.tres")
const MENU_MUSIC: AudioStream = preload("uid://cvsmoirn0cwbv")
const PREPARE_MUSIC: AudioStream = preload("uid://bgjsas02td6b2")
const COMBAT_MUSIC: AudioStream = preload("uid://eaa2damffngl")
const PLAYER_ATTACK_SOUNDS: Array[AudioStream] = [
	preload("uid://bd4yd0ttirwpl"),
	preload("uid://dbrl4r72ewhm6"),
	preload("uid://chsafvo6g1mur"),
]
const PLAYER_HIT_SOUNDS: Array[AudioStream] = [
	preload("uid://1wvst0y6gtn0"),
	preload("uid://jjteqqxrh15y"),
	preload("uid://dcgnfeg4n2478"),
]
const FIREBALL_SOUND: AudioStream = preload("uid://dcnsgqptnwiqh")
const SLIME_ATTACK_SOUND: AudioStream = preload("uid://ssk8e73elgva")
const SPAWN_CHIME_SOUND: AudioStream = preload("uid://c8pvci7fi6vgh")
const UI_CANCEL_SOUND: AudioStream = preload("uid://dut6tih8yhfr3")
const UI_CONFIRM_INGAME_SOUND: AudioStream = preload("uid://4x4w6t8486u")
const UI_CONFIRM_MENU_SOUND: AudioStream = preload("uid://c5xdjhfpxba6o")
const UI_CONFIRM_MENU_VOLUME_DB: float = -12.0
const UI_CONFIRM_INGAME_VOLUME_DB: float = -13.0
const UI_CANCEL_VOLUME_DB: float = -12.0
const SILENCE_DB: float = -80.0

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _music_cache: Dictionary = {}
var _current_music_key: String = ""
var _bus_layout_applied: bool = false
var _settings_connected: bool = false
var _music_players: Array[AudioStreamPlayer] = []
var _active_music_player_index: int = -1
var _music_tween: Tween


# 初始化总线布局，并准备随机音效所需的随机源。
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	_apply_bus_layout()
	_ensure_music_players()
	_apply_sound_manager_buses()
	_connect_settings_signal()
	_apply_runtime_volumes()
	call_deferred("_play_startup_scene_music")


# 播放主菜单循环音乐。
func play_menu_music(crossfade_duration: float = 0.6) -> void:
	_play_music_track("menu", MENU_MUSIC, crossfade_duration)


# 菜单场景入场后再次确认 BGM 正在播放，避免场景切换时序漏播。
func ensure_menu_music() -> void:
	await get_tree().process_frame
	_ensure_track_playing("menu", MENU_MUSIC, 0.15)


# 播放准备阶段循环音乐。
func play_prepare_music(crossfade_duration: float = 0.6) -> void:
	_play_music_track("prepare", PREPARE_MUSIC, crossfade_duration)


# 播放战斗阶段循环音乐。
func play_combat_music(crossfade_duration: float = 0.6) -> void:
	_play_music_track("combat", COMBAT_MUSIC, crossfade_duration)


# 停止当前背景音乐，并清空当前轨道标记。
func stop_music(fade_out_duration: float = 0.3) -> void:
	_current_music_key = ""
	_stop_music_players(fade_out_duration)


# 查询当前全局音乐播放器是否真正处于播放状态。
func is_music_playing(track_key: String = "") -> bool:
	var active_player: AudioStreamPlayer = _get_active_music_player()
	if active_player == null or not active_player.playing or active_player.stream == null:
		return false
	return track_key.is_empty() or _current_music_key == track_key


# 随机播放一次玩家普通攻击音效。
func play_player_attack() -> void:
	_play_random_sound(PLAYER_ATTACK_SOUNDS)


# 随机播放一次玩家受伤音效。
func play_player_hit() -> void:
	_play_random_sound(PLAYER_HIT_SOUNDS)


# 播放一次火球施法音效，供投射物锚点复用。
func play_fireball() -> void:
	_play_sound(FIREBALL_SOUND)


# 播放一次史莱姆攻击音效。
func play_slime_attack() -> void:
	_play_sound(SLIME_ATTACK_SOUND)


# 播放一次敌人来袭提示音。
func play_spawn_chime() -> void:
	_play_sound(SPAWN_CHIME_SOUND)


# 播放游戏内确认音效。
func play_ui_confirm_ingame() -> void:
	_play_ui_sound(UI_CONFIRM_INGAME_SOUND, UI_CONFIRM_INGAME_VOLUME_DB)


# 播放菜单确认音效。
func play_ui_confirm_menu() -> void:
	_play_ui_sound(UI_CONFIRM_MENU_SOUND, UI_CONFIRM_MENU_VOLUME_DB)


# 播放取消操作音效。
func play_ui_cancel() -> void:
	_play_ui_sound(UI_CANCEL_SOUND, UI_CANCEL_VOLUME_DB)


# 根据按钮上配置的元数据播放菜单、局内或取消音效。
func play_ui_button_press(button: Node) -> void:
	var sound_kind: String = str(button.get_meta("ui_sound_kind", "ingame_confirm")) if button != null else "ingame_confirm"
	match sound_kind:
		"menu_confirm":
			play_ui_confirm_menu()
		"cancel":
			play_ui_cancel()
		"none":
			pass
		_:
			play_ui_confirm_ingame()


# 给主菜单里的 ShaderButton 填入菜单确认音。
func setup_menu_shader_button(button: Node) -> void:
	_set_shader_button_audio(button, UI_CONFIRM_MENU_SOUND, UI_CONFIRM_MENU_VOLUME_DB, "menu_confirm")


# 给局内 ShaderButton 填入游戏内确认音。
func setup_ingame_shader_button(button: Node) -> void:
	_set_shader_button_audio(button, UI_CONFIRM_INGAME_SOUND, UI_CONFIRM_INGAME_VOLUME_DB, "ingame_confirm")


# 给普通按钮写入统一音效类型，供 ButtonEffectModule 使用。
func setup_plain_button(button: Node, sound_kind: String = "ingame_confirm") -> void:
	if button == null:
		return
	button.set_meta("ui_sound_kind", sound_kind)


# 立即把设置里的音量值同步到运行时总线。
func refresh_runtime_volumes() -> void:
	_apply_bus_layout()
	_apply_sound_manager_buses()
	_apply_runtime_volumes()


# 把默认总线布局切到项目自带资源，确保 UI、SFX、Music 分轨生效。
func _apply_bus_layout() -> void:
	if _bus_layout_applied:
		return
	if DEFAULT_BUS_LAYOUT != null:
		AudioServer.set_bus_layout(DEFAULT_BUS_LAYOUT)
	_bus_layout_applied = true


# 把 SoundManager 的默认总线路由对齐到项目里的 SFX、UI、Ambient、Music。
func _apply_sound_manager_buses() -> void:
	var sound_manager: Node = _get_sound_manager()
	if sound_manager == null:
		return
	if sound_manager.has_method("set_default_sound_bus"):
		sound_manager.call("set_default_sound_bus", "SFX")
	if sound_manager.has_method("set_default_ui_sound_bus"):
		sound_manager.call("set_default_ui_sound_bus", "UI")
	if sound_manager.has_method("set_default_ambient_sound_bus"):
		sound_manager.call("set_default_ambient_sound_bus", "Ambient")
	if sound_manager.has_method("set_default_music_bus"):
		sound_manager.call("set_default_music_bus", "Music")
	_connect_settings_signal()


# 播放一条循环背景音乐；如果当前已经在播同一轨，就不重复重开。
func _play_music_track(track_key: String, stream: AudioStream, crossfade_duration: float) -> void:
	if stream == null:
		return
	_apply_bus_layout()
	_ensure_music_players()
	_apply_sound_manager_buses()
	_apply_runtime_volumes()
	if _music_players.is_empty():
		return
	var looped_stream: AudioStream = _get_looped_music_stream(track_key, stream)
	var active_player: AudioStreamPlayer = _get_active_music_player()
	if _current_music_key == track_key and active_player != null and active_player.playing and active_player.stream == looped_stream:
		return
	_current_music_key = track_key
	var next_index: int = 0 if _active_music_player_index != 0 else 1
	var next_player: AudioStreamPlayer = _music_players[next_index]
	var previous_player: AudioStreamPlayer = active_player
	_active_music_player_index = next_index
	if _music_tween != null and _music_tween.is_valid():
		_music_tween.kill()
	next_player.bus = "Music"
	next_player.stream = looped_stream
	next_player.stream_paused = false
	next_player.volume_db = SILENCE_DB if crossfade_duration > 0.0 else 0.0
	next_player.play()
	if crossfade_duration <= 0.0:
		if previous_player != null and previous_player != next_player:
			previous_player.stop()
			previous_player.stream = null
		next_player.volume_db = 0.0
		return
	_music_tween = create_tween()
	_music_tween.set_ignore_time_scale(true)
	_music_tween.parallel().tween_property(next_player, "volume_db", 0.0, crossfade_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if previous_player != null and previous_player != next_player and previous_player.playing:
		_music_tween.parallel().tween_property(previous_player, "volume_db", SILENCE_DB, crossfade_duration).set_trans(Tween.TRANS_CIRC).set_ease(Tween.EASE_IN)
		_music_tween.finished.connect(func() -> void:
			if is_instance_valid(previous_player) and previous_player != _get_active_music_player():
				previous_player.stop()
				previous_player.stream = null
		, CONNECT_ONE_SHOT)


# 确保指定曲目既有状态标记，也有实际播放器在跑。
func _ensure_track_playing(track_key: String, stream: AudioStream, crossfade_duration: float) -> void:
	var looped_stream: AudioStream = _get_looped_music_stream(track_key, stream)
	var active_player: AudioStreamPlayer = _get_active_music_player()
	if _current_music_key == track_key and (active_player == null or not active_player.playing or active_player.stream != looped_stream):
		_current_music_key = ""
		_active_music_player_index = -1
	_play_music_track(track_key, stream, crossfade_duration)


# Autoload 准备好后根据当前场景补播默认 BGM，避免菜单漏调时静音。
func _play_startup_scene_music() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if is_music_playing(_current_music_key):
		return
	var scene: Node = get_tree().current_scene if get_tree() != null else null
	var scene_path: String = scene.scene_file_path if scene != null else ""
	if scene_path.ends_with("survivor_game.tscn"):
		_ensure_track_playing("prepare", PREPARE_MUSIC, 0.1)
	else:
		_ensure_track_playing("menu", MENU_MUSIC, 0.1)


# 复制并缓存一份可循环的音乐资源，避免直接改动原始导入资源。
func _get_looped_music_stream(track_key: String, source: AudioStream) -> AudioStream:
	if _music_cache.has(track_key):
		return _music_cache[track_key] as AudioStream
	var duplicated: AudioStream = source.duplicate(true)
	if duplicated is AudioStreamWAV:
		var wav_stream: AudioStreamWAV = duplicated as AudioStreamWAV
		wav_stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav_stream.loop_begin = 0
	_music_cache[track_key] = duplicated
	return duplicated


# 创建并缓存两只全局 BGM 播放器，避免 SoundManager 用空 resource_path 误判曲目。
func _ensure_music_players() -> void:
	for index in range(_music_players.size() - 1, -1, -1):
		if _music_players[index] == null or not is_instance_valid(_music_players[index]):
			_music_players.remove_at(index)
	while _music_players.size() < 2:
		var player: AudioStreamPlayer = AudioStreamPlayer.new()
		player.name = "MusicPlayer%d" % _music_players.size()
		player.bus = "Music"
		player.volume_db = SILENCE_DB
		player.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(player)
		_music_players.append(player)


# 返回当前活跃 BGM 播放器，索引无效时返回空。
func _get_active_music_player() -> AudioStreamPlayer:
	if _active_music_player_index < 0 or _active_music_player_index >= _music_players.size():
		return null
	var player: AudioStreamPlayer = _music_players[_active_music_player_index]
	return player if is_instance_valid(player) else null


# 淡出并停止所有全局 BGM 播放器。
func _stop_music_players(fade_out_duration: float) -> void:
	_ensure_music_players()
	if _music_tween != null and _music_tween.is_valid():
		_music_tween.kill()
	if fade_out_duration <= 0.0:
		for player in _music_players:
			if is_instance_valid(player):
				player.stop()
				player.stream = null
				player.volume_db = SILENCE_DB
		_active_music_player_index = -1
		return
	_music_tween = create_tween()
	_music_tween.set_ignore_time_scale(true)
	for player in _music_players:
		if is_instance_valid(player) and player.playing:
			_music_tween.parallel().tween_property(player, "volume_db", SILENCE_DB, fade_out_duration).set_trans(Tween.TRANS_CIRC).set_ease(Tween.EASE_IN)
	_music_tween.finished.connect(func() -> void:
		for player in _music_players:
			if is_instance_valid(player):
				player.stop()
				player.stream = null
				player.volume_db = SILENCE_DB
		_active_music_player_index = -1
	, CONNECT_ONE_SHOT)


# 从一组音效里随机挑一条播放。
func _play_random_sound(candidates: Array[AudioStream]) -> void:
	if candidates.is_empty():
		return
	var index: int = _rng.randi_range(0, candidates.size() - 1)
	_play_sound(candidates[index])


# 走 SFX 总线播放一次普通动作音效。
func _play_sound(stream: AudioStream) -> void:
	var sound_manager: Node = _get_sound_manager()
	if sound_manager == null or stream == null:
		return
	_apply_bus_layout()
	_apply_sound_manager_buses()
	_apply_runtime_volumes()
	sound_manager.call("play_sound", stream)


# 走 UI 总线播放一次界面音效。
func _play_ui_sound(stream: AudioStream, volume_db: float = 0.0) -> void:
	var sound_manager: Node = _get_sound_manager()
	if sound_manager == null or stream == null:
		return
	_apply_bus_layout()
	_apply_sound_manager_buses()
	_apply_runtime_volumes()
	var player: AudioStreamPlayer = sound_manager.call("play_ui_sound", stream, "UI") as AudioStreamPlayer
	if player != null:
		player.volume_db = volume_db


# 把 ShaderButton 场景内部的 AudioStreamPlayer 绑定到指定音频资源。
func _set_shader_button_audio(button: Node, press_stream: AudioStream, press_volume_db: float, sound_kind: String, hover_stream: AudioStream = null) -> void:
	if button == null:
		return
	button.set_meta("ui_sound_kind", sound_kind)
	var press_audio: AudioStreamPlayer = button.get_node_or_null("PressAudio") as AudioStreamPlayer
	var select_audio: AudioStreamPlayer = button.get_node_or_null("SelectAudio") as AudioStreamPlayer
	if press_audio != null:
		press_audio.bus = "UI"
		press_audio.stream = press_stream
		press_audio.volume_db = press_volume_db
	if select_audio != null:
		select_audio.bus = "UI"
		select_audio.stream = hover_stream
		select_audio.volume_db = press_volume_db


# 监听设置变化，保证滑杆变化会立刻影响所有正在使用的音频总线。
func _connect_settings_signal() -> void:
	if _settings_connected or SettingsModule.instance == null:
		return
	SettingsModule.instance.settings_changed.connect(_on_settings_changed)
	_settings_connected = true


# 任何音量相关设置变化后重新同步总线。
func _on_settings_changed(_key: String, _value: Variant) -> void:
	_apply_runtime_volumes()


# 把 SettingsModule 的线性音量同步到 Godot AudioServer 总线。
func _apply_runtime_volumes() -> void:
	if SettingsModule.instance == null:
		return
	var master_volume: float = float(SettingsModule.instance.get_value("master_volume", 0.8))
	var music_volume: float = float(SettingsModule.instance.get_value("music_volume", 0.8))
	var sfx_volume: float = float(SettingsModule.instance.get_value("sfx_volume", 0.8))
	var ambient_volume: float = float(SettingsModule.instance.get_value("ambient_volume", 0.8))
	_set_bus_volume_linear("Master", master_volume)
	_set_bus_volume_linear("Music", music_volume)
	_set_bus_volume_linear("SFX", sfx_volume)
	_set_bus_volume_linear("UI", sfx_volume)
	_set_bus_volume_linear("Ambient", ambient_volume)


# 安全设置总线音量，并用 mute 处理 0 音量避免 -inf。
func _set_bus_volume_linear(bus_name: String, linear_volume: float) -> void:
	var bus_index: int = AudioServer.get_bus_index(bus_name)
	if bus_index < 0:
		return
	var clamped_volume: float = clampf(linear_volume, 0.0, 1.0)
	AudioServer.set_bus_mute(bus_index, clamped_volume <= 0.001)
	AudioServer.set_bus_volume_db(bus_index, SILENCE_DB if clamped_volume <= 0.001 else linear_to_db(clamped_volume))


# 在运行时查找 SoundManager 自动加载节点。
func _get_sound_manager() -> Node:
	if get_tree() == null or get_tree().root == null:
		return null
	return get_tree().root.get_node_or_null("SoundManager")
