using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Shapes;
using WestieDeskPet.Core;
using WestieDeskPet.Windows.Native;
using WestieDeskPet.Windows.UI;

using WpfBrushes = System.Windows.Media.Brushes;
using WpfColor = System.Windows.Media.Color;
using WpfCursors = System.Windows.Input.Cursors;
using WpfImage = System.Windows.Controls.Image;
using WpfKey = System.Windows.Input.Key;
using WpfKeyEventArgs = System.Windows.Input.KeyEventArgs;
using WpfMouseEventArgs = System.Windows.Input.MouseEventArgs;
using WpfPoint = System.Windows.Point;
using WpfRect = System.Windows.Rect;

namespace WestieDeskPet.Windows.Rendering;

public enum AppInteractionMode
{
    Companion,
    Tennis
}

public partial class OverlayWindow : Window
{
    public CompanionPreferences Preferences { get; }
    public CompanionEngine Companion { get; }
    public TennisMatchEngine Tennis { get; }

    public AppInteractionMode Mode { get; private set; } = AppInteractionMode.Companion;
    public bool ForceQuietSleep => Companion.ForceQuietSleep;

    public event Action<AppInteractionMode>? ModeChanged;

    private readonly WindowsPlatformTracker _windowTracker = new();
    private MonitorGeometry _currentMonitor;
    private ActiveWorkspaceSnapshot? _latestSnapshot;

    private IntPtr _hwnd;
    private bool _isClickThrough = true;
    private bool _isContextMenuOpen;
    private PreferencesWindow? _preferencesWindow;

    private readonly Stopwatch _frameClock = Stopwatch.StartNew();
    private double _lastFrameSeconds;
    private double _fullSnapshotTimer;
    private double _monitorCheckTimer;
    private Vec2? _lastPointerScenePt;
    private double _lastPointerSampleTime;
    private double _smoothedPointerSpeed;

    // Reusable Tennis WPF visual nodes
    private bool _tennisVisualsBuilt;
    private Canvas _courtOrigin = null!;
    private Ellipse _playerShadow = null!;
    private Ellipse _opponentShadow = null!;
    private Ellipse _ballShadow = null!;
    private Ellipse _chargeRing = null!;
    private Grid _aimReticle = null!;
    private WpfImage _playerImage = null!;
    private WpfImage _opponentImage = null!;
    private WpfImage _ballImage = null!;
    private TextBlock _scoreLabel = null!;
    private TextBlock _bannerLabel = null!;
    private Border _difficultyPill = null!;
    private TextBlock _difficultyPillText = null!;
    private Border _speedPill = null!;
    private TextBlock _speedPillText = null!;
    private Border _exitPill = null!;
    private Canvas _tennisEffectsCanvas = null!;

    public OverlayWindow(CompanionPreferences preferences)
    {
        Preferences = preferences;
        Companion = new CompanionEngine(preferences);
        Tennis = new TennisMatchEngine(preferences);

        InitializeComponent();

        Companion.RequestStartTennis += () => SwitchToMode(AppInteractionMode.Tennis);
        Tennis.RequestExitTennis += () => SwitchToMode(AppInteractionMode.Companion);

        SourceInitialized += OnSourceInitialized;
        Loaded += OnLoaded;
        Closed += OnClosed;

        MouseLeftButtonDown += OnWindowMouseLeftDown;
        MouseMove += OnWindowMouseMove;
        MouseLeftButtonUp += OnWindowMouseLeftUp;
        MouseRightButtonDown += OnWindowMouseRightDown;
        KeyDown += OnWindowKeyDown;
        KeyUp += OnWindowKeyUp;
    }

    private void OnSourceInitialized(object? sender, EventArgs e)
    {
        _hwnd = new WindowInteropHelper(this).Handle;
        ApplyExStyle(clickThrough: true, noActivate: true);
    }

    private void OnLoaded(object sender, RoutedEventArgs e)
    {
        _currentMonitor = WindowsPlatformTracker.GetMonitorForForegroundOrCursor();
        AlignWindowToMonitor(_currentMonitor);
        WpfSpriteBank.Shared.PreloadSpecies(Preferences.PetSpecies);
        Preferences.Changed += () => Dispatcher.BeginInvoke(() => WpfSpriteBank.Shared.PreloadSpecies(Preferences.PetSpecies));

        _latestSnapshot = _windowTracker.CaptureSnapshot(_currentMonitor);
        Companion.PlaceInitially(_latestSnapshot, _currentMonitor.SizeDip);
        RenderCompanionFrame();

        _lastFrameSeconds = _frameClock.Elapsed.TotalSeconds;
        CompositionTarget.Rendering += OnCompositionRendering;
    }

    private void OnClosed(object? sender, EventArgs e)
    {
        CompositionTarget.Rendering -= OnCompositionRendering;
        _preferencesWindow?.Close();
    }

    private void AlignWindowToMonitor(MonitorGeometry mon)
    {
        _currentMonitor = mon;
        Left = mon.LeftDip;
        Top = mon.TopDip;
        Width = mon.WidthDip;
        Height = mon.HeightDip;
        PetClipCanvas.Width = mon.WidthDip;
        PetClipCanvas.Height = mon.HeightDip;

        if (_hwnd != IntPtr.Zero)
        {
            Win32Api.SetWindowPos(
                _hwnd, Win32Api.HWND_TOPMOST, 0, 0, 0, 0,
                Win32Api.SWP_NOMOVE | Win32Api.SWP_NOSIZE | Win32Api.SWP_NOACTIVATE | Win32Api.SWP_SHOWWINDOW);
        }
        LayoutTennisCourt();
    }

    private void ApplyExStyle(bool clickThrough, bool noActivate)
    {
        if (_hwnd == IntPtr.Zero) return;
        long style = Win32Api.GetWindowLongPtr(_hwnd, Win32Api.GWL_EXSTYLE);
        style |= Win32Api.WS_EX_TOOLWINDOW | Win32Api.WS_EX_TOPMOST;
        if (clickThrough) style |= Win32Api.WS_EX_TRANSPARENT;
        else style &= ~Win32Api.WS_EX_TRANSPARENT;

        if (noActivate) style |= Win32Api.WS_EX_NOACTIVATE;
        else style &= ~Win32Api.WS_EX_NOACTIVATE;

        Win32Api.SetWindowLongPtr(_hwnd, Win32Api.GWL_EXSTYLE, style);
        _isClickThrough = clickThrough;
    }

    // MARK: - Public Controls (called by Tray, Context Menu, Preferences)

    public void SwitchToMode(AppInteractionMode target)
    {
        if (Mode == target) return;
        Mode = target;

        if (Mode == AppInteractionMode.Tennis)
        {
            Companion.SetHovering(false);
            CompanionCanvas.Visibility = Visibility.Collapsed;
            EnsureTennisVisualsBuilt();
            LayoutTennisCourt();
            TennisLayer.Visibility = Visibility.Visible;
            Tennis.StartMatch();

            ApplyExStyle(clickThrough: false, noActivate: false);
            Activate();
            Focus();
            Cursor = WpfCursors.Arrow;
            RenderTennisFrame();
        }
        else
        {
            Tennis.StopMatch();
            TennisLayer.Visibility = Visibility.Collapsed;
            CompanionCanvas.Visibility = Visibility.Visible;

            ApplyExStyle(clickThrough: true, noActivate: true);
            _latestSnapshot = _windowTracker.CaptureSnapshot(_currentMonitor);
            Companion.SummonToFrontWindow(_latestSnapshot, _currentMonitor.SizeDip);
            RenderCompanionFrame();
        }

        ModeChanged?.Invoke(Mode);
    }

    public void ToggleTennisMode() =>
        SwitchToMode(Mode == AppInteractionMode.Companion ? AppInteractionMode.Tennis : AppInteractionMode.Companion);

    public void TriggerTennisInvite()
    {
        if (Mode == AppInteractionMode.Tennis) return;
        Companion.TriggerTennisInvite();
    }

    public void SummonToActiveWindow()
    {
        if (Mode == AppInteractionMode.Tennis) SwitchToMode(AppInteractionMode.Companion);
        _latestSnapshot = _windowTracker.CaptureSnapshot(_currentMonitor);
        Companion.SummonToFrontWindow(_latestSnapshot, _currentMonitor.SizeDip);
    }

    public void MoveToZone(PerchZone zone)
    {
        if (Mode == AppInteractionMode.Tennis) SwitchToMode(AppInteractionMode.Companion);
        _latestSnapshot = _windowTracker.CaptureSnapshot(_currentMonitor);
        Companion.MoveImmediatelyToZone(zone, _latestSnapshot, _currentMonitor.SizeDip);
    }

    public void MoveToRightEdge()
    {
        if (Mode == AppInteractionMode.Tennis) SwitchToMode(AppInteractionMode.Companion);
        _latestSnapshot = _windowTracker.CaptureSnapshot(_currentMonitor);
        bool useWindowRight = Preferences.PerchPreference == PerchPreference.RightPeek
            && _latestSnapshot.PerchLayout.IsFullScreenMode == false;
        Companion.MoveImmediatelyToZone(
            useWindowRight ? PerchZone.WindowRightPeek : PerchZone.ScreenRightPeek,
            _latestSnapshot, _currentMonitor.SizeDip);
    }

    public void PreviewClimbPeekOnTop()
    {
        if (Mode == AppInteractionMode.Tennis) SwitchToMode(AppInteractionMode.Companion);
        _latestSnapshot = _windowTracker.CaptureSnapshot(_currentMonitor);
        if (_latestSnapshot.PerchLayout.TopPerch is not { } top) return;
        double targetX = top.ClampedX(top.MaxX - Math.Min(110, top.Width * 0.26), 22);
        Companion.BeginStealthClimbToTop(
            targetX,
            _latestSnapshot.PerchLayout.ActiveWindowId ?? Companion.TrackedWindowId,
            effectOnArrival: null);
    }

    public void PlayTopBarEffect(TopBarEffect effect)
    {
        if (Mode == AppInteractionMode.Tennis) SwitchToMode(AppInteractionMode.Companion);
        _latestSnapshot = _windowTracker.CaptureSnapshot(_currentMonitor);
        Companion.TriggerTopBarEffect(effect, _latestSnapshot, _currentMonitor.SizeDip);
    }

    public void FeedSnack()
    {
        if (Mode == AppInteractionMode.Tennis) return;
        _latestSnapshot = _windowTracker.CaptureSnapshot(_currentMonitor);
        Companion.DropSnackTreat(_latestSnapshot, _currentMonitor.SizeDip);
    }

    public void ToggleQuietSleep() => Companion.ForceQuietSleep = !Companion.ForceQuietSleep;

    public void OpenPreferences()
    {
        if (_preferencesWindow is { IsLoaded: true })
        {
            _preferencesWindow.Show();
            _preferencesWindow.Activate();
            return;
        }
        _preferencesWindow = new PreferencesWindow(
            Preferences,
            onPreviewPeek: PreviewClimbPeekOnTop,
            onPlayEffect: PlayTopBarEffect,
            onPerchChanged: SummonToActiveWindow);
        _preferencesWindow.Closed += (_, _) => _preferencesWindow = null;
        _preferencesWindow.Show();
        _preferencesWindow.Activate();
    }

    // MARK: - 60/120Hz Render Loop

    private void OnCompositionRendering(object? sender, EventArgs e)
    {
        double now = _frameClock.Elapsed.TotalSeconds;
        double dt = Math.Clamp(now - _lastFrameSeconds, 0.001, 0.08);
        _lastFrameSeconds = now;

        if (Mode == AppInteractionMode.Companion)
        {
            // Periodically check if active monitor changed (multi-monitor support!)
            _monitorCheckTimer -= dt;
            if (_monitorCheckTimer <= 0 && !Companion.IsPointerDownOnDog && Companion.StateKind != CompanionStateKind.Dragged)
            {
                _monitorCheckTimer = 0.45;
                var activeMon = WindowsPlatformTracker.GetMonitorForForegroundOrCursor();
                if (activeMon.Handle != _currentMonitor.Handle ||
                    activeMon.PhysicalMonitor.Width != _currentMonitor.PhysicalMonitor.Width ||
                    activeMon.PhysicalMonitor.Height != _currentMonitor.PhysicalMonitor.Height ||
                    Math.Abs(activeMon.DpiScaleX - _currentMonitor.DpiScaleX) > 0.01)
                {
                    AlignWindowToMonitor(activeMon);
                    _latestSnapshot = _windowTracker.CaptureSnapshot(_currentMonitor);
                }
            }

            _fullSnapshotTimer -= dt;
            if (_fullSnapshotTimer <= 0 || _latestSnapshot is null)
            {
                _fullSnapshotTimer = 0.16;
                _latestSnapshot = _windowTracker.CaptureSnapshot(_currentMonitor);
            }
            else
            {
                _latestSnapshot = _windowTracker.FastRefreshActiveWindow(_latestSnapshot, _currentMonitor, Companion.TrackedWindowId);
            }

            SyncCompanionPointerAndClickThrough(now);
            Companion.Update(dt, _latestSnapshot, _currentMonitor.SizeDip);
            RenderCompanionFrame();
        }
        else
        {
            Tennis.Update(dt);
            RenderTennisFrame();
        }
    }

    private void SyncCompanionPointerAndClickThrough(double now)
    {
        if (_isContextMenuOpen) return;

        Win32Api.GetCursorPos(out var physPt);
        Vec2 scenePt = _currentMonitor.CursorPhysicalToLocalBottomLeftDip(physPt);

        if (_lastPointerScenePt is { } prevPt)
        {
            double pDt = Math.Max(now - _lastPointerSampleTime, 1.0 / 240.0);
            double instSpeed = Vec2.Distance(scenePt, prevPt) / pDt;
            _smoothedPointerSpeed = _smoothedPointerSpeed * 0.55 + instSpeed * 0.45;
        }
        else
        {
            _smoothedPointerSpeed = 0;
        }
        _lastPointerScenePt = scenePt;
        _lastPointerSampleTime = now;

        bool activelyDragging = Companion.IsPointerDownOnDog || Companion.StateKind == CompanionStateKind.Dragged;
        bool shouldCapture;

        if (activelyDragging)
        {
            shouldCapture = true;
        }
        else
        {
            var hitRect = Companion.InteractiveHitRect();
            if (hitRect.IsEmpty)
            {
                Companion.SetHovering(false, 0, false);
                shouldCapture = false;
            }
            else
            {
                var captureRect = Companion.IsHoveringDog ? hitRect.InsetBy(-4, -4) : hitRect;
                var nearRect = hitRect.InsetBy(-12, -12);
                bool inside = captureRect.Contains(scenePt);
                bool near = nearRect.Contains(scenePt);
                Companion.SetHovering(inside, _smoothedPointerSpeed, near);
                shouldCapture = inside;
            }
        }

        if (_isClickThrough == shouldCapture)
        {
            ApplyExStyle(clickThrough: !shouldCapture, noActivate: true);
        }

        if (shouldCapture)
        {
            if (activelyDragging) Cursor = WpfCursors.SizeAll;
            else if (Companion.IsPointOnInviteBadge(scenePt)) Cursor = WpfCursors.Hand;
            else Cursor = WpfCursors.Hand;
        }
    }

    // MARK: - Companion WPF Rendering

    private void RenderCompanionFrame()
    {
        var snap = Companion.LatestRender;
        double h = _currentMonitor.HeightDip;
        double w = _currentMonitor.WidthDip;

        // 1. Clip mask (mirrors SKCropNode!)
        PetClipCanvas.Clip = snap.ClipKind switch
        {
            ClipMaskKind.RightOfX => new RectangleGeometry(new WpfRect(snap.ClipEdge, 0, Math.Max(0, w - snap.ClipEdge + 200), h)),
            ClipMaskKind.AboveY => new RectangleGeometry(new WpfRect(0, 0, w, Math.Max(0, h - snap.ClipEdge))),
            _ => null
        };

        // 2. Primary + Cross-Fade Sprite Layers
        ApplySpriteLayer(FadeOutPetImage, snap.FadeOutSprite, h);
        ApplySpriteLayer(PrimaryPetImage, snap.PrimarySprite, h);

        // 3. Dropped Treat Prop
        if (snap.Treat.IsVisible)
        {
            TreatImage.Source = WpfSpriteBank.Shared.GetImage(snap.Treat.AssetKey, snap.Treat.Species);
            TreatImage.Width = snap.Treat.Size;
            TreatImage.Height = snap.Treat.Size;
            Canvas.SetLeft(TreatImage, snap.Treat.CenterPos.X - snap.Treat.Size * 0.5);
            Canvas.SetTop(TreatImage, h - snap.Treat.CenterPos.Y - snap.Treat.Size * 0.5);
            TreatImage.Visibility = Visibility.Visible;
        }
        else
        {
            TreatImage.Visibility = Visibility.Collapsed;
        }

        // 4. Snack Crumb & Sparkle Particles
        ParticleCanvas.Children.Clear();
        foreach (var p in snap.Particles)
        {
            double fade = 1.0 - Math.Clamp(p.Elapsed / Math.Max(p.Duration, 0.01), 0, 1);
            if (p.LabelText is not null)
            {
                var tb = new TextBlock
                {
                    Text = p.LabelText,
                    FontSize = p.Size,
                    Foreground = WpfBrushes.White,
                    Opacity = fade
                };
                Canvas.SetLeft(tb, p.X - 14);
                Canvas.SetTop(tb, h - p.Y - 10);
                ParticleCanvas.Children.Add(tb);
            }
            else
            {
                var col = (WpfColor)System.Windows.Media.ColorConverter.ConvertFromString(p.ColorHex);
                var rect = new System.Windows.Shapes.Rectangle
                {
                    Width = p.Size,
                    Height = p.Size,
                    Fill = new SolidColorBrush(col),
                    Opacity = fade
                };
                Canvas.SetLeft(rect, p.X - p.Size * 0.5);
                Canvas.SetTop(rect, h - p.Y - p.Size * 0.5);
                ParticleCanvas.Children.Add(rect);
            }
        }

        // 5. Tennis Invite Badge
        if (snap.InviteBadge.IsVisible)
        {
            Canvas.SetLeft(InviteBadge, snap.InviteBadge.CenterPos.X - 59);
            Canvas.SetTop(InviteBadge, h - snap.InviteBadge.CenterPos.Y - 14);
            InviteBadge.Visibility = Visibility.Visible;
        }
        else
        {
            InviteBadge.Visibility = Visibility.Collapsed;
        }
    }

    private static void ApplySpriteLayer(WpfImage img, SpriteRenderLayer layer, double canvasHeight)
    {
        if (!layer.IsVisible || layer.Opacity <= 0.005)
        {
            img.Visibility = Visibility.Collapsed;
            return;
        }

        img.Source = WpfSpriteBank.Shared.GetImage(layer.AssetKey, layer.Species);
        img.Width = layer.Size.Width;
        img.Height = layer.Size.Height;
        img.Opacity = layer.Opacity;
        img.Visibility = Visibility.Visible;

        // Convert bottom-left anchorPoint (ax, ay) into WPF top-left RenderTransformOrigin (ax, 1 - ay)
        double left = layer.AnchorPos.X - layer.AnchorPoint.X * layer.Size.Width;
        double top = (canvasHeight - layer.AnchorPos.Y) - (1.0 - layer.AnchorPoint.Y) * layer.Size.Height;
        Canvas.SetLeft(img, left);
        Canvas.SetTop(img, top);

        img.RenderTransformOrigin = new WpfPoint(layer.AnchorPoint.X, 1.0 - layer.AnchorPoint.Y);
        var tg = new TransformGroup();
        tg.Children.Add(new ScaleTransform(layer.ScaleX, layer.ScaleY));
        // SpriteKit +zRotation is counter-clockwise; WPF RotateTransform +Angle is clockwise -> negate!
        tg.Children.Add(new RotateTransform(-layer.RotationRad * (180.0 / Math.PI)));
        img.RenderTransform = tg;
    }

    // MARK: - Mouse & Keyboard Input

    private Vec2 MouseEventToBottomLeftScene(WpfMouseEventArgs e)
    {
        var p = e.GetPosition(RootGrid);
        return new Vec2(p.X, _currentMonitor.HeightDip - p.Y);
    }

    private Vec2 SceneToTennisCourt(Vec2 scenePt) =>
        new(scenePt.X - _currentMonitor.WidthDip * 0.5, scenePt.Y - _currentMonitor.HeightDip * 0.5);

    private void OnWindowMouseLeftDown(object sender, MouseButtonEventArgs e)
    {
        var pt = MouseEventToBottomLeftScene(e);
        if (Mode == AppInteractionMode.Tennis)
        {
            Tennis.HandleLeftMouseDown(SceneToTennisCourt(pt));
            return;
        }

        if (Keyboard.Modifiers.HasFlag(ModifierKeys.Control))
        {
            ShowCompanionContextMenu();
            return;
        }

        if (Companion.HandleMouseDown(pt))
        {
            CaptureMouse();
        }
    }

    private void OnWindowMouseMove(object sender, WpfMouseEventArgs e)
    {
        var pt = MouseEventToBottomLeftScene(e);
        if (Mode == AppInteractionMode.Tennis)
        {
            Tennis.HandleMouseMoved(SceneToTennisCourt(pt));
        }
        else if (Companion.IsPointerDownOnDog || Companion.StateKind == CompanionStateKind.Dragged)
        {
            Companion.HandleMouseDragged(pt);
        }
    }

    private void OnWindowMouseLeftUp(object sender, MouseButtonEventArgs e)
    {
        var pt = MouseEventToBottomLeftScene(e);
        if (Mode == AppInteractionMode.Tennis)
        {
            Tennis.HandleLeftMouseUp(SceneToTennisCourt(pt));
            return;
        }

        if (IsMouseCaptured) ReleaseMouseCapture();
        if (Companion.IsPointerDownOnDog || Companion.StateKind == CompanionStateKind.Dragged)
        {
            _latestSnapshot = _windowTracker.CaptureSnapshot(_currentMonitor);
            Companion.HandleMouseUp(pt, _latestSnapshot, _currentMonitor.SizeDip);
        }
    }

    private void OnWindowMouseRightDown(object sender, MouseButtonEventArgs e)
    {
        var pt = MouseEventToBottomLeftScene(e);
        if (Mode == AppInteractionMode.Tennis)
        {
            Tennis.HandleRightMouseDown(SceneToTennisCourt(pt));
        }
        else
        {
            ShowCompanionContextMenu();
        }
    }

    private void OnWindowKeyDown(object sender, WpfKeyEventArgs e)
    {
        if (Mode != AppInteractionMode.Tennis) return;
        if (MapWpfKey(e.Key) is { } tk)
        {
            Tennis.HandleKeyDown(tk, e.IsRepeat);
            e.Handled = true;
        }
    }

    private void OnWindowKeyUp(object sender, WpfKeyEventArgs e)
    {
        if (Mode != AppInteractionMode.Tennis) return;
        if (MapWpfKey(e.Key) is { } tk)
        {
            Tennis.HandleKeyUp(tk);
            e.Handled = true;
        }
    }

    private static TennisKey? MapWpfKey(WpfKey key) => key switch
    {
        WpfKey.W => TennisKey.W,
        WpfKey.A => TennisKey.A,
        WpfKey.S => TennisKey.S,
        WpfKey.D => TennisKey.D,
        WpfKey.Up => TennisKey.Up,
        WpfKey.Left => TennisKey.Left,
        WpfKey.Down => TennisKey.Down,
        WpfKey.Right => TennisKey.Right,
        WpfKey.Space => TennisKey.Space,
        WpfKey.R => TennisKey.R,
        WpfKey.Escape => TennisKey.Escape,
        WpfKey.OemMinus or WpfKey.Subtract => TennisKey.Minus,
        WpfKey.OemPlus or WpfKey.Add => TennisKey.Equal,
        WpfKey.OemOpenBrackets => TennisKey.LeftBracket,
        WpfKey.OemCloseBrackets => TennisKey.RightBracket,
        _ => null
    };

    // MARK: - Rich Right-Click Context Menu on Pet

    private void ShowCompanionContextMenu()
    {
        if (_isContextMenuOpen || Mode != AppInteractionMode.Companion) return;
        _isContextMenuOpen = true;
        Companion.PrepareForContextMenu();

        var menu = BuildPetContextMenu();
        menu.Closed += (_, _) => _isContextMenuOpen = false;
        menu.Placement = System.Windows.Controls.Primitives.PlacementMode.MousePoint;
        menu.IsOpen = true;
    }

    private ContextMenu BuildPetContextMenu()
    {
        var prefs = Preferences;
        var sp = prefs.PetSpecies;
        var menu = new ContextMenu();

        MenuItem MakeItem(string header, Action action, bool? isChecked = null)
        {
            var mi = new MenuItem { Header = header };
            if (isChecked.HasValue) mi.IsChecked = isChecked.Value;
            mi.Click += (_, _) => action();
            return mi;
        }

        // 1. Most-used: Playable Top-Bar Effects right on Level 1!
        menu.Items.Add(MakeItem("👀 探头张望", PreviewClimbPeekOnTop));
        foreach (var eff in Enum.GetValues<TopBarEffect>())
        {
            var e = eff;
            menu.Items.Add(MakeItem(e.DisplayName(), () => PlayTopBarEffect(e)));
        }

        menu.Items.Add(new Separator());

        // 2. Feed Snack & Quiet Sleep right after effects!
        menu.Items.Add(MakeItem(sp.IsCat() ? "🐟 喂一条小鱼干" : "🦴 喂一根骨头饼干", FeedSnack));
        menu.Items.Add(MakeItem(ForceQuietSleep ? "☀️ 取消固定趴睡" : "💤 安静趴睡模式", ToggleQuietSleep));

        menu.Items.Add(new Separator());

        // 3. Tennis & Tennis Speed grouped together!
        menu.Items.Add(MakeItem("🎾 开始打网球 (WASD + 鼠标)", () => SwitchToMode(AppInteractionMode.Tennis)));
        var speedMenu = new MenuItem { Header = $"⏱ 网球球速: {prefs.TennisSpeed.ShortName()}" };
        foreach (var spd in Enum.GetValues<TennisGameSpeed>())
        {
            var s = spd;
            string suffix = s == TennisGameSpeed.Slow ? " (默认)" : "";
            speedMenu.Items.Add(MakeItem($"{s.DisplayName()}{suffix}", () => prefs.TennisSpeed = s, s == prefs.TennisSpeed));
        }
        menu.Items.Add(speedMenu);

        menu.Items.Add(new Separator());

        // 4. Quick Position Move
        menu.Items.Add(MakeItem("📍 移到当前窗口正上方", () => MoveToZone(PerchZone.WindowTop)));
        menu.Items.Add(MakeItem("👀 移到屏幕右侧边", MoveToRightEdge));

        menu.Items.Add(new Separator());

        // 5. Pet Species Switch in its own standalone section!
        var speciesMenu = new MenuItem { Header = $"🎭 切换宠物: {sp.ShortName()}" };
        foreach (var cand in Enum.GetValues<PetSpecies>())
        {
            var c = cand;
            speciesMenu.Items.Add(MakeItem(c.DisplayName(), () => prefs.PetSpecies = c, c == sp));
        }
        menu.Items.Add(speciesMenu);

        menu.Items.Add(new Separator());

        // 5. All Settings grouped cleanly under Level-2 Submenu!
        var settingsMenu = new MenuItem { Header = "⚙️ 设置" };

        var perchMenu = new MenuItem { Header = "🧭 陪伴位置偏好" };
        foreach (var pp in Enum.GetValues<PerchPreference>())
        {
            var p = pp;
            perchMenu.Items.Add(MakeItem(p.DisplayName(), () => { prefs.PerchPreference = p; SummonToActiveWindow(); }, p == prefs.PerchPreference));
        }
        settingsMenu.Items.Add(perchMenu);

        var delayMenu = new MenuItem { Header = $"🕵️ 换窗等待: {CompanionPreferences.FormatDuration(prefs.WindowSwitchDelaySeconds)}" };
        foreach (var (title, secs) in CompanionPreferences.SwitchDelayPresets)
        {
            double s = secs;
            delayMenu.Items.Add(MakeItem(title, () => prefs.WindowSwitchDelaySeconds = s, Math.Abs(prefs.WindowSwitchDelaySeconds - s) < 0.1));
        }
        settingsMenu.Items.Add(delayMenu);

        string climbLabel = prefs.ClimbToTopEnabled ? CompanionPreferences.FormatDuration(prefs.ClimbToTopIntervalSeconds) : "已关闭";
        var climbMenu = new MenuItem { Header = $"🐾 爬顶等待: {climbLabel}" };
        foreach (var (title, en, secs) in CompanionPreferences.ClimbIntervalPresets)
        {
            bool enabled = en;
            double s = secs;
            bool sel = enabled ? (prefs.ClimbToTopEnabled && Math.Abs(prefs.ClimbToTopIntervalSeconds - s) < 0.5) : !prefs.ClimbToTopEnabled;
            climbMenu.Items.Add(MakeItem(title, () => { prefs.ClimbToTopEnabled = enabled; if (enabled) prefs.ClimbToTopIntervalSeconds = s; }, sel));
        }
        settingsMenu.Items.Add(climbMenu);

        string effectLabel = prefs.TopEffectsEnabled ? CompanionPreferences.FormatDuration(prefs.TopEffectIntervalSeconds) : "已关闭";
        var effectMenu = new MenuItem { Header = $"✨ 特效间隔: {effectLabel}" };
        foreach (var (title, en, secs) in CompanionPreferences.EffectIntervalPresets)
        {
            bool enabled = en;
            double s = secs;
            bool sel = enabled ? (prefs.TopEffectsEnabled && Math.Abs(prefs.TopEffectIntervalSeconds - s) < 0.5) : !prefs.TopEffectsEnabled;
            effectMenu.Items.Add(MakeItem(title, () => { prefs.TopEffectsEnabled = enabled; if (enabled) prefs.TopEffectIntervalSeconds = s; }, sel));
        }
        settingsMenu.Items.Add(effectMenu);

        var scaleMenu = new MenuItem { Header = $"📏 宠物大小: {CompanionPreferences.FormatScale(prefs.DogScale)}" };
        foreach (var (title, scale) in CompanionPreferences.DogScalePresets)
        {
            double sc = scale;
            scaleMenu.Items.Add(MakeItem(title, () => prefs.DogScale = sc, Math.Abs(prefs.DogScale - sc) < 0.03));
        }
        settingsMenu.Items.Add(scaleMenu);

        settingsMenu.Items.Add(new Separator());
        settingsMenu.Items.Add(MakeItem("⚙️ 陪伴偏好设置…", OpenPreferences));
        menu.Items.Add(settingsMenu);

        menu.Items.Add(new Separator());
        menu.Items.Add(MakeItem("退出 Westie Desk Pet", () => System.Windows.Application.Current.Shutdown()));

        return menu;
    }

    // MARK: - 2.5D Tennis Court Construction & Rendering

    private void EnsureTennisVisualsBuilt()
    {
        if (_tennisVisualsBuilt) return;
        _tennisVisualsBuilt = true;

        _courtOrigin = new Canvas();
        TennisCanvas.Children.Add(_courtOrigin);

        const double hw = TennisCourtMetrics.HalfWidth;
        const double hl = TennisCourtMetrics.HalfLength;
        const double aw = TennisCourtMetrics.ApronMaxX;
        const double ah = TennisCourtMetrics.ApronMaxY;

        // Outer green apron
        var apron = new Border
        {
            Width = aw * 2,
            Height = ah * 2,
            CornerRadius = new CornerRadius(14),
            Background = new SolidColorBrush(WpfColor.FromArgb(228, 22, 74, 52)),
            BorderBrush = new SolidColorBrush(WpfColor.FromArgb(200, 145, 220, 175)),
            BorderThickness = new Thickness(2)
        };
        Canvas.SetLeft(apron, -aw);
        Canvas.SetTop(apron, -ah);
        _courtOrigin.Children.Add(apron);

        // Inner playing surface
        var surface = new System.Windows.Shapes.Rectangle
        {
            Width = hw * 2,
            Height = hl * 2,
            Fill = new SolidColorBrush(WpfColor.FromArgb(242, 34, 128, 84)),
            Stroke = WpfBrushes.White,
            StrokeThickness = 2.2
        };
        Canvas.SetLeft(surface, -hw);
        Canvas.SetTop(surface, -hl);
        _courtOrigin.Children.Add(surface);

        // Service boxes & center service line
        AddCourtLine(-hw, -118, hw, -118, 1.6);
        AddCourtLine(-hw, 118, hw, 118, 1.6);
        AddCourtLine(0, -118, 0, 118, 1.6);
        // Baseline center ticks
        AddCourtLine(0, -hl, 0, -hl + 10, 1.8);
        AddCourtLine(0, hl - 10, 0, hl, 1.8);

        // Net shadow + net mesh bar
        var netBar = new Border
        {
            Width = (hw + 16) * 2,
            Height = 14,
            Background = new SolidColorBrush(WpfColor.FromArgb(145, 20, 34, 28)),
            BorderBrush = new SolidColorBrush(WpfColor.FromArgb(230, 240, 248, 242)),
            BorderThickness = new Thickness(0, 2, 0, 1),
            IsHitTestVisible = false
        };
        Canvas.SetLeft(netBar, -(hw + 16));
        Canvas.SetTop(netBar, -14);
        _courtOrigin.Children.Add(netBar);

        // Aim Reticle
        _aimReticle = new Grid { Width = 28, Height = 28, IsHitTestVisible = false };
        _aimReticle.Children.Add(new Ellipse
        {
            Width = 24, Height = 24,
            Stroke = new SolidColorBrush(WpfColor.FromArgb(230, 232, 255, 80)),
            StrokeThickness = 2
        });
        _aimReticle.Children.Add(new Ellipse
        {
            Width = 4, Height = 4,
            Fill = new SolidColorBrush(WpfColor.FromArgb(230, 232, 255, 80))
        });
        _courtOrigin.Children.Add(_aimReticle);

        // Shadows & Charge ring
        _playerShadow = MakeShadowEllipse(36, 11, 76);
        _opponentShadow = MakeShadowEllipse(36, 11, 76);
        _ballShadow = MakeShadowEllipse(16, 7, 92);
        _chargeRing = new Ellipse
        {
            Width = 48, Height = 48,
            Stroke = new SolidColorBrush(WpfColor.FromArgb(242, 255, 220, 56)),
            Fill = new SolidColorBrush(WpfColor.FromArgb(36, 255, 220, 56)),
            StrokeThickness = 2.5,
            Visibility = Visibility.Collapsed,
            IsHitTestVisible = false
        };
        _courtOrigin.Children.Add(_playerShadow);
        _courtOrigin.Children.Add(_opponentShadow);
        _courtOrigin.Children.Add(_ballShadow);
        _courtOrigin.Children.Add(_chargeRing);

        // Sprites
        _opponentImage = new WpfImage { Width = 64, Height = 64, IsHitTestVisible = false };
        RenderOptions.SetBitmapScalingMode(_opponentImage, BitmapScalingMode.NearestNeighbor);
        _playerImage = new WpfImage { Width = 62, Height = 62, IsHitTestVisible = false };
        RenderOptions.SetBitmapScalingMode(_playerImage, BitmapScalingMode.NearestNeighbor);
        _ballImage = new WpfImage { Width = 20, Height = 20, IsHitTestVisible = false };
        RenderOptions.SetBitmapScalingMode(_ballImage, BitmapScalingMode.NearestNeighbor);

        _courtOrigin.Children.Add(_opponentImage);
        _courtOrigin.Children.Add(_playerImage);
        _courtOrigin.Children.Add(_ballImage);

        _tennisEffectsCanvas = new Canvas { IsHitTestVisible = false };
        _courtOrigin.Children.Add(_tennisEffectsCanvas);

        // HUD: Score, Banner, Controls Hint
        _scoreLabel = new TextBlock
        {
            Width = 480,
            TextAlignment = TextAlignment.Center,
            FontFamily = new System.Windows.Media.FontFamily("Consolas, Microsoft YaHei UI"),
            FontWeight = FontWeights.Bold,
            FontSize = 15,
            Foreground = WpfBrushes.White,
            IsHitTestVisible = false
        };
        Canvas.SetLeft(_scoreLabel, -240);
        Canvas.SetTop(_scoreLabel, -(ah + 28));
        _courtOrigin.Children.Add(_scoreLabel);

        _bannerLabel = new TextBlock
        {
            Width = 520,
            TextAlignment = TextAlignment.Center,
            FontFamily = new System.Windows.Media.FontFamily("Consolas, Microsoft YaHei UI"),
            FontWeight = FontWeights.Bold,
            FontSize = 15,
            Foreground = new SolidColorBrush(WpfColor.FromRgb(255, 245, 130)),
            IsHitTestVisible = false
        };
        Canvas.SetLeft(_bannerLabel, -260);
        Canvas.SetTop(_bannerLabel, -54);
        _courtOrigin.Children.Add(_bannerLabel);

        var hintLabel = new TextBlock
        {
            Width = 600,
            Text = "WASD 移动 | 双击/Space 冲刺 | 左键平击/蓄力上旋 | 右键小球/高吊 | [-][+] 调速 | ESC 退出",
            TextAlignment = TextAlignment.Center,
            FontFamily = new System.Windows.Media.FontFamily("Consolas, Microsoft YaHei UI"),
            FontSize = 11.5,
            Foreground = new SolidColorBrush(WpfColor.FromArgb(215, 232, 246, 238)),
            IsHitTestVisible = false
        };
        Canvas.SetLeft(hintLabel, -300);
        Canvas.SetTop(hintLabel, ah + 12);
        _courtOrigin.Children.Add(hintLabel);

        // Top Interactive Pills
        (_difficultyPill, _difficultyPillText) = BuildPillButton(148, "#EB245C47", () => Tennis.ToggleDifficulty());
        Canvas.SetLeft(_difficultyPill, -236);
        Canvas.SetTop(_difficultyPill, -(ah + 62));
        _courtOrigin.Children.Add(_difficultyPill);

        (_speedPill, _speedPillText) = BuildPillButton(142, "#EB2B5E8A", () => Tennis.CycleSpeed());
        Canvas.SetLeft(_speedPill, -71);
        Canvas.SetTop(_speedPill, -(ah + 62));
        _courtOrigin.Children.Add(_speedPill);

        (_exitPill, var exitText) = BuildPillButton(148, "#EB404A54", () => SwitchToMode(AppInteractionMode.Companion));
        exitText.Text = "× 收起球场 (ESC)";
        Canvas.SetLeft(_exitPill, 88);
        Canvas.SetTop(_exitPill, -(ah + 62));
        _courtOrigin.Children.Add(_exitPill);
    }

    private void AddCourtLine(double x1, double y1, double x2, double y2, double thickness)
    {
        _courtOrigin.Children.Add(new Line
        {
            X1 = x1, Y1 = -y1, X2 = x2, Y2 = -y2,
            Stroke = new SolidColorBrush(WpfColor.FromArgb(220, 255, 255, 255)),
            StrokeThickness = thickness,
            IsHitTestVisible = false
        });
    }

    private static Ellipse MakeShadowEllipse(double w, double h, byte alpha) => new()
    {
        Width = w, Height = h,
        Fill = new SolidColorBrush(WpfColor.FromArgb(alpha, 0, 0, 0)),
        IsHitTestVisible = false
    };

    private static (Border Pill, TextBlock Label) BuildPillButton(double width, string bgHex, Action onClick)
    {
        var label = new TextBlock
        {
            Foreground = WpfBrushes.White,
            FontFamily = new System.Windows.Media.FontFamily("Consolas, Microsoft YaHei UI"),
            FontWeight = FontWeights.SemiBold,
            FontSize = 12,
            HorizontalAlignment = System.Windows.HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Center
        };
        var pill = new Border
        {
            Width = width,
            Height = 28,
            CornerRadius = new CornerRadius(14),
            Background = new SolidColorBrush((WpfColor)System.Windows.Media.ColorConverter.ConvertFromString(bgHex)),
            BorderBrush = new SolidColorBrush(WpfColor.FromArgb(140, 255, 255, 255)),
            BorderThickness = new Thickness(1),
            Cursor = WpfCursors.Hand,
            Child = label
        };
        pill.MouseLeftButtonDown += (_, e) =>
        {
            e.Handled = true;
            onClick();
        };
        return (pill, label);
    }

    private void LayoutTennisCourt()
    {
        if (!_tennisVisualsBuilt) return;
        Canvas.SetLeft(_courtOrigin, _currentMonitor.WidthDip * 0.5);
        Canvas.SetTop(_courtOrigin, _currentMonitor.HeightDip * 0.5);
    }

    private void RenderTennisFrame()
    {
        if (!_tennisVisualsBuilt) return;
        var bank = WpfSpriteBank.Shared;

        _scoreLabel.Text = Tennis.ScoreboardText;
        _bannerLabel.Text = Tennis.BannerText;
        _difficultyPillText.Text = Tennis.DifficultyPillText;
        _speedPillText.Text = Tennis.SpeedPillText;

        // Aim Reticle (court Y is up -> canvas Y is -Y)
        Canvas.SetLeft(_aimReticle, Tennis.AimCourtPoint.X - 14);
        Canvas.SetTop(_aimReticle, -Tennis.AimCourtPoint.Y - 14);

        // Player
        var pp = Tennis.PlayerPos;
        _playerImage.Source = bank.GetImage(Tennis.CurrentPlayerSprite, PetSpecies.Westie);
        Canvas.SetLeft(_playerImage, pp.X - 31);
        Canvas.SetTop(_playerImage, -pp.Y - 57);
        Canvas.SetLeft(_playerShadow, pp.X - 18);
        Canvas.SetTop(_playerShadow, -(pp.Y + 3) - 5.5);

        if (Tennis.IsChargingLeftClick)
        {
            double sc = 0.75 + Tennis.CurrentChargeRatio * 0.55;
            double diam = 48 * sc;
            _chargeRing.Width = diam;
            _chargeRing.Height = diam;
            Canvas.SetLeft(_chargeRing, pp.X - diam * 0.5);
            Canvas.SetTop(_chargeRing, -(pp.Y + 6) - diam * 0.5);
            _chargeRing.Visibility = Visibility.Visible;
        }
        else
        {
            _chargeRing.Visibility = Visibility.Collapsed;
        }

        // Westie / Golden Cat Opponent
        var opp = Tennis.Opponent;
        var (oppKey, oppScaleX) = Tennis.CurrentOpponentVisual;
        _opponentImage.Source = bank.GetImage(oppKey, Tennis.Species);
        Canvas.SetLeft(_opponentImage, opp.X - 32);
        Canvas.SetTop(_opponentImage, -opp.Y - 59);
        _opponentImage.RenderTransformOrigin = new WpfPoint(0.5, 0.5);
        _opponentImage.RenderTransform = new ScaleTransform(oppScaleX, 1.0);
        Canvas.SetLeft(_opponentShadow, opp.X - 18);
        Canvas.SetTop(_opponentShadow, -(opp.Y + 3) - 5.5);

        // 2.5D Ball + Shadow
        var b = Tennis.Ball;
        double shadowScale = Math.Max(0.45, 1.0 - b.Z / 160.0);
        _ballShadow.Width = 16 * shadowScale;
        _ballShadow.Height = 7 * shadowScale;
        Canvas.SetLeft(_ballShadow, b.X - _ballShadow.Width * 0.5);
        Canvas.SetTop(_ballShadow, -b.Y - _ballShadow.Height * 0.5);

        double ballScale = 1.0 + Math.Min(b.Z / 220.0, 0.42);
        double ballDim = 20 * ballScale;
        _ballImage.Source = bank.GetImage(SpriteAssetKey.TennisBall, PetSpecies.Westie);
        _ballImage.Width = ballDim;
        _ballImage.Height = ballDim;
        Canvas.SetLeft(_ballImage, b.X - ballDim * 0.5);
        Canvas.SetTop(_ballImage, -(b.Y + b.Z * 0.85) - ballDim * 0.5);

        // Dynamic Bounce Rings & Floating Pop Texts
        _tennisEffectsCanvas.Children.Clear();
        foreach (var mark in Tennis.BounceMarks)
        {
            double u = Math.Clamp(mark.Elapsed / mark.Duration, 0, 1);
            double sc = 1.0 + u * 0.6;
            var ring = new Ellipse
            {
                Width = 14 * sc,
                Height = 7 * sc,
                Stroke = new SolidColorBrush(WpfColor.FromArgb((byte)(170 * (1 - u)), 255, 255, 255)),
                StrokeThickness = 1.2
            };
            Canvas.SetLeft(ring, mark.Position.X - ring.Width * 0.5);
            Canvas.SetTop(ring, -mark.Position.Y - ring.Height * 0.5);
            _tennisEffectsCanvas.Children.Add(ring);
        }
        foreach (var pop in Tennis.PopEffects)
        {
            double fade = 1.0 - Math.Clamp(pop.Elapsed / pop.Duration, 0, 1);
            var tb = new TextBlock
            {
                Text = pop.Text,
                FontFamily = new System.Windows.Media.FontFamily("Consolas, Microsoft YaHei UI"),
                FontWeight = FontWeights.Bold,
                FontSize = 13,
                Foreground = new SolidColorBrush((WpfColor)System.Windows.Media.ColorConverter.ConvertFromString(pop.ColorHex)),
                Opacity = fade
            };
            Canvas.SetLeft(tb, pop.Position.X - 36);
            Canvas.SetTop(tb, -pop.Position.Y - 10);
            _tennisEffectsCanvas.Children.Add(tb);
        }
    }
}
