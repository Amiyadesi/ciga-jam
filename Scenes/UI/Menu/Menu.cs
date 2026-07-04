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

    // Wires menu buttons and child modal callbacks when the scene opens.
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

        Visible = true;
        Modulate = Colors.White;
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
    }

    // Initializes the default save slot, fades the menu, and enters combat.
    private async void _on_start_pressed()
    {
        EmitSignal(SignalName.start_requested);
        PrepareSaveSlot();
        await ChangeToSurvivorScene();
    }

    // Opens the growth modal after ensuring slot data exists.
    private void _on_growth_pressed()
    {
        PrepareSaveSlot();
        _growthScreen?.Call("refresh_from_save");
        _growthScreen?.Call("open_modal");
    }

    // Shows the short boot flash animation over the menu.
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

    // Returns from the credits modal to the settings modal.
    private async void _on_thank_return_requested()
    {
        _thankScreen?.Call("close_modal");
        _settingScreen?.Call("open_modal");
    }

    // Opens the credits modal from settings.
    private async void _on_setting_thanks_requested()
    {
        _settingScreen?.Call("close_modal");
        _thankScreen?.Call("open_modal");
    }

    // Loads an existing slot or prepares a new one without overwriting progress.
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

    // Changes to the survivor prototype using SceneManager transitions when available.
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

    // Plays the reverse transition when the menu scene becomes active.
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

    // Connects a signal once to avoid duplicate callbacks after scene reloads.
    private static void ConnectIfNeeded(Node node, StringName signal, Callable callable)
    {
        if (node != null && !node.IsConnected(signal, callable))
        {
            node.Connect(signal, callable);
        }
    }
}
