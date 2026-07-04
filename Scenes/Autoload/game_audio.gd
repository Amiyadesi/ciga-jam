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

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _music_cache: Dictionary = {}
var _current_music_key: String = ""
var _bus_layout_applied: bool = false


# 初始化总线布局，并准备随机音效所需的随机源。
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	_apply_bus_layout()
	_apply_sound_manager_buses()


# 播放主菜单循环音乐。
func play_menu_music(crossfade_duration: float = 0.6) -> void:
	_play_music_track("menu", MENU_MUSIC, crossfade_duration)


# 播放准备阶段循环音乐。
func play_prepare_music(crossfade_duration: float = 0.6) -> void:
	_play_music_track("prepare", PREPARE_MUSIC, crossfade_duration)


# 播放战斗阶段循环音乐。
func play_combat_music(crossfade_duration: float = 0.6) -> void:
	_play_music_track("combat", COMBAT_MUSIC, crossfade_duration)


# 停止当前背景音乐，并清空当前轨道标记。
func stop_music(fade_out_duration: float = 0.3) -> void:
	var sound_manager: Node = _get_sound_manager()
	_current_music_key = ""
	if sound_manager != null and sound_manager.has_method("stop_music"):
		sound_manager.call("stop_music", fade_out_duration)


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
	_play_ui_sound(UI_CONFIRM_INGAME_SOUND)


# 播放菜单确认音效。
func play_ui_confirm_menu() -> void:
	_play_ui_sound(UI_CONFIRM_MENU_SOUND)


# 播放取消操作音效。
func play_ui_cancel() -> void:
	_play_ui_sound(UI_CANCEL_SOUND)


# 给主菜单里的 ShaderButton 填入菜单确认音。
func setup_menu_shader_button(button: Node) -> void:
	_set_shader_button_audio(button, UI_CONFIRM_MENU_SOUND)


# 给局内 ShaderButton 填入游戏内确认音。
func setup_ingame_shader_button(button: Node) -> void:
	_set_shader_button_audio(button, UI_CONFIRM_INGAME_SOUND)


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
	if SettingsModule.instance != null:
		SettingsModule.instance.apply_all()


# 播放一条循环背景音乐；如果当前已经在播同一轨，就不重复重开。
func _play_music_track(track_key: String, stream: AudioStream, crossfade_duration: float) -> void:
	var sound_manager: Node = _get_sound_manager()
	if sound_manager == null or stream == null:
		return
	_apply_bus_layout()
	_apply_sound_manager_buses()
	if _current_music_key == track_key and sound_manager.has_method("is_music_playing") and bool(sound_manager.call("is_music_playing")):
		return
	_current_music_key = track_key
	sound_manager.call("play_music", _get_looped_music_stream(track_key, stream), crossfade_duration)


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
	sound_manager.call("play_sound", stream)


# 走 UI 总线播放一次界面音效。
func _play_ui_sound(stream: AudioStream) -> void:
	var sound_manager: Node = _get_sound_manager()
	if sound_manager == null or stream == null:
		return
	_apply_bus_layout()
	_apply_sound_manager_buses()
	sound_manager.call("play_ui_sound", stream)


# 把 ShaderButton 场景内部的 AudioStreamPlayer 绑定到指定音频资源。
func _set_shader_button_audio(button: Node, press_stream: AudioStream, hover_stream: AudioStream = null) -> void:
	if button == null:
		return
	var press_audio: AudioStreamPlayer = button.get_node_or_null("PressAudio") as AudioStreamPlayer
	var select_audio: AudioStreamPlayer = button.get_node_or_null("SelectAudio") as AudioStreamPlayer
	if press_audio != null:
		press_audio.bus = "UI"
		press_audio.stream = press_stream
	if select_audio != null:
		select_audio.bus = "UI"
		select_audio.stream = hover_stream


# 在运行时查找 SoundManager 自动加载节点。
func _get_sound_manager() -> Node:
	if get_tree() == null or get_tree().root == null:
		return null
	return get_tree().root.get_node_or_null("SoundManager")
