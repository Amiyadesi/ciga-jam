using Godot;
using System.Threading.Tasks;

[GlobalClass]
public partial class Menu : Control
{
    private const string SurvivorScenePath = "res://Scenes/Game/Survivor/survivor_game.tscn";
    private const string ExitTransitionPath = "res://reousrces/scene_transitions/stage_exit_fade_to_black.tres";
    private const string EnterTransitionPath = "res://reousrces/scene_transitions/stage_enter_fade_to_black.tres";

    [Signal]
    public delegate void start_requestedEventHandler();

    [Export(PropertyHint.Range, "0.05,2.0,0.05,suffix:s")]
    public float boot_flash_seconds = 0.22f;

    private Node _startButton;
    private Node _settingButton;
    private Node _growthButton;
    private Node _exitButton;
    private Node _settingScreen;
    private Node _thankScreen;
    private Node _growthScreen;
    private CanvasItem _bootFlash;
    private AudioStreamPlayer _audioStreamPlayer;

    // 进入主菜单时连接按钮、配置音频并播放开场表现。
    public override void _Ready()
    {
        _bootFlash = GetNodeOrNull<CanvasItem>("ButtonLayer/MonitorOverlay/BootFlash");
        _startButton = GetNode<Node>("ButtonLayer/StartButton");
        _settingButton = GetNode<Node>("ButtonLayer/SettingButton");
        _growthButton = GetNode<Node>("ButtonLayer/GrowthButton");
        _exitButton = GetNode<Node>("ButtonLayer/ExitButton");
        _settingScreen = GetNode<Node>("SettingScreen");
        _thankScreen = GetNode<Node>("ThankScreen");
        _growthScreen = GetNode<Node>("GrowthScreen");
        _audioStreamPlayer = GetNode<AudioStreamPlayer>("AudioStreamPlayer");

        Visible = true;
        Modulate = Colors.White;
        ConfigureMenuAudio();
        _settingScreen.Set("is_in_menu_flag", true);
        ConnectIfNeeded(_startButton, "pressed", Callable.From(_on_start_pressed));
        ConnectIfNeeded(_settingButton, "pressed", Callable.From(() => _settingScreen.Call("open_modal")));
        ConnectIfNeeded(_growthButton, "pressed", Callable.From(_on_growth_pressed));
        ConnectIfNeeded(_settingScreen, "thanks_requested", Callable.From(_on_setting_thanks_requested));
        ConnectIfNeeded(_thankScreen, "return_requested", Callable.From(_on_thank_return_requested));
        ConnectIfNeeded(_growthScreen, "return_requested", Callable.From(() => _growthScreen.Call("close_modal")));
        ConnectIfNeeded(_exitButton, "pressed", Callable.From(() => GetTree().Quit()));
        PlayEnterTransition();
        PlayBootFlash();
        CallDeferred(nameof(EnsureMenuMusic));
    }

    // 初始化默认存档槽，然后切入生存模式场景。
    private async void _on_start_pressed()
    {
        EmitSignal(SignalName.start_requested);
        PrepareSaveSlot();
        await ChangeToSurvivorScene();
    }

    // 确保存档槽存在后再打开成长页。
    private void _on_growth_pressed()
    {
        PrepareSaveSlot();
        _growthScreen?.Call("refresh_from_save");
        _growthScreen?.Call("open_modal");
    }

    // 播放一段短暂的开机闪屏。
    private async void PlayBootFlash()
    {
        if (_bootFlash == null)
        {
            return;
        }

        _bootFlash.Visible = true;
        _bootFlash.Modulate = new Color(1, 1, 1, 0.95f);
        var tween = CreateTween();
        tween.TweenProperty(_bootFlash, "modulate:a", 0.0f, boot_flash_seconds)
            .SetTrans(Tween.TransitionType.Cubic)
            .SetEase(Tween.EaseType.Out);
        await ToSignal(tween, Tween.SignalName.Finished);
        _bootFlash.Visible = false;
    }

    // 从致谢页返回设置页。
    private async void _on_thank_return_requested()
    {
        _thankScreen?.Call("close_modal");
        _settingScreen?.Call("open_modal");
    }

    // 从设置页切到致谢页。
    private async void _on_setting_thanks_requested()
    {
        _settingScreen?.Call("close_modal");
        _thankScreen?.Call("open_modal");
    }

    // 读取已有存档，或在首次进入时创建默认槽位。
    private void PrepareSaveSlot()
    {
        var saveSystem = GetNodeOrNull<Node>("/root/SaveSystem");
        if (saveSystem == null)
        {
            return;
        }

        const int slot = 1;
        var hasSlot = false;
        if (saveSystem.HasMethod("slot_exists"))
        {
            hasSlot = saveSystem.Call("slot_exists", slot).AsBool();
        }

        if (hasSlot && saveSystem.HasMethod("load_slot"))
        {
            saveSystem.Call("load_slot", slot);
        }
        else if (saveSystem.HasMethod("new_game"))
        {
            saveSystem.Call("new_game", slot);
            if (saveSystem.HasMethod("save_slot"))
            {
                saveSystem.Call("save_slot", slot);
            }
        }
    }

    // 通过 SceneManager 过渡切进生存模式场景。
    private async Task ChangeToSurvivorScene()
    {
        var sceneManager = GetNodeOrNull<Node>("/root/SceneManager");
        if (sceneManager != null && sceneManager.HasMethod("transition_start") && sceneManager.HasMethod("change_scene_to_file"))
        {
            var transition = ResourceLoader.Load<Resource>(ExitTransitionPath);
            var tween = sceneManager.Call("transition_start", transition).AsGodotObject() as Tween;
            if (tween != null)
            {
                await ToSignal(tween, Tween.SignalName.Finished);
            }
            sceneManager.Call("change_scene_to_file", SurvivorScenePath);
            return;
        }

        GetTree().ChangeSceneToFile(SurvivorScenePath);
    }

    // 菜单重新成为当前场景时补一段入场淡入。
    private void PlayEnterTransition()
    {
        var sceneManager = GetNodeOrNull<Node>("/root/SceneManager");
        if (sceneManager == null || !sceneManager.HasMethod("transition_start"))
        {
            return;
        }

        var transition = ResourceLoader.Load<Resource>(EnterTransitionPath);
        sceneManager.Call("transition_start", transition, true);
    }

    // 给主菜单按钮配置菜单确认音，并开始循环菜单 BGM。
    private void ConfigureMenuAudio()
    {
        var gameAudio = GetNodeOrNull<Node>("/root/GameAudio");
        if (gameAudio == null)
        {
            return;
        }

        gameAudio.Call("setup_menu_shader_button", _startButton);
        gameAudio.Call("setup_menu_shader_button", _settingButton);
        gameAudio.Call("setup_menu_shader_button", _growthButton);
        gameAudio.Call("setup_menu_shader_button", _exitButton);
        if (gameAudio.HasMethod("setup_plain_button"))
        {
            gameAudio.Call("setup_plain_button", _exitButton, "cancel");
        }
        _audioStreamPlayer.Play();
    }

    // 菜单完全入树后再确认一次 BGM，避免 Autoload 初始化顺序导致漏播。
    private void EnsureMenuMusic()
    {
        var gameAudio = GetNodeOrNull<Node>("/root/GameAudio");
        if (gameAudio != null && gameAudio.HasMethod("ensure_menu_music"))
        {
            gameAudio.Call("ensure_menu_music");
        }
    }

    // 只连接一次信号，避免场景重进后重复回调。
    private static void ConnectIfNeeded(Node node, StringName signal, Callable callable)
    {
        if (node != null && !node.IsConnected(signal, callable))
        {
            node.Connect(signal, callable);
        }
    }
}
