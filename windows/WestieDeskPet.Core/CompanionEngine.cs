using System;
using System.Collections.Generic;

namespace WestieDeskPet.Core;

public sealed record SpriteRenderLayer(
    bool IsVisible,
    SpriteAssetKey AssetKey,
    PetSpecies Species,
    Vec2 AnchorPos,
    Vec2 AnchorPoint,
    Size2D Size,
    double ScaleX,
    double ScaleY,
    double RotationRad,
    double Opacity);

public sealed class SnackCrumbParticle
{
    public double X { get; set; }
    public double Y { get; set; }
    public double Vx { get; set; }
    public double Vy { get; set; }
    public double Size { get; }
    public string ColorHex { get; }
    public double Elapsed { get; set; }
    public double Duration { get; }
    public string? LabelText { get; }

    public SnackCrumbParticle(
        double x, double y, double vx, double vy, double size,
        string colorHex, double duration, string? labelText = null)
    {
        X = x; Y = y; Vx = vx; Vy = vy;
        Size = size; ColorHex = colorHex;
        Duration = duration; LabelText = labelText;
    }
}

public sealed record TreatRenderState(
    bool IsVisible,
    SpriteAssetKey AssetKey,
    PetSpecies Species,
    Vec2 CenterPos,
    double Size);

public sealed record InviteBadgeRenderState(
    bool IsVisible,
    Vec2 CenterPos);

public enum ClipMaskKind
{
    None,
    /// <summary>Clips to `x >= ClipEdge` (hides pixels inside active window during right-edge peek).</summary>
    RightOfX,
    /// <summary>Clips to `y >= ClipEdge` (hides pixels below window top bar during climb/retract).</summary>
    AboveY
}

public sealed record CompanionRenderSnapshot(
    SpriteRenderLayer PrimarySprite,
    SpriteRenderLayer FadeOutSprite,
    ClipMaskKind ClipKind,
    double ClipEdge,
    TreatRenderState Treat,
    InviteBadgeRenderState InviteBadge,
    IReadOnlyList<SnackCrumbParticle> Particles);

/// <summary>
/// Full platform-agnostic port of macOS `CompanionController` (v0.5 parity):
/// screen-right default, dwell-debounced stealth transitions, in-place fullscreen ducking,
/// 3s top-edge peek, 3-frame hop left, stationary-body head-turn look, 4-frame walk right,
/// 5-beat bipedal Flash-Step ("闪身步"), smile sit, yawn, drowsy, sleep, and snack chewing + crumbs.
/// </summary>
public sealed class CompanionEngine
{
    public const double DragStartThreshold = 4.0;
    private static readonly SpriteAssetKey[] WalkCycleFrames =
    [
        SpriteAssetKey.WestieWalk1,
        SpriteAssetKey.WestieWalk2,
        SpriteAssetKey.WestieWalk3,
        SpriteAssetKey.WestieWalk4
    ];

    private readonly Random _rng = new();
    private readonly int _ownPid;

    public CompanionPreferences Preferences { get; }
    public PerchZone PerchZone { get; private set; } = PerchZone.ScreenRightPeek;
    public WindowPlatform? CurrentPlatform { get; private set; }
    public RightEdgeAnchor? CurrentRightAnchor { get; private set; }
    public CompanionStateKind StateKind { get; private set; } = CompanionStateKind.PeekingRight;
    public StealthPhaseKind StealthPhase { get; private set; }
    public TopStoryStepKind TopStoryStep { get; private set; }
    public FlashStepBeatKind FlashStepBeat { get; private set; }
    public PendingWindowSwitch? PendingWindowSwitch { get; private set; }

    public Vec2 Position { get; private set; } = new(520, 420);
    public ulong TrackedWindowId { get; private set; }
    public bool IsHoveringDog { get; private set; }
    public bool IsPointerDownOnDog { get; private set; }
    public double ShyRetreatTimer { get; private set; }
    public double RightPeekDwellTimer { get; private set; }

    public bool ForceQuietSleep
    {
        get => _forceQuietSleep;
        set
        {
            _forceQuietSleep = value;
            if (_forceQuietSleep)
            {
                if (PerchZone == PerchZone.WindowTop)
                    EnterTimedState(CompanionStateKind.Sleeping, 35.0);
            }
            else if (StateKind == CompanionStateKind.Sleeping)
            {
                EnterTimedState(CompanionStateKind.Loafing, 8.0);
            }
        }
    }

    public event Action? RequestStartTennis;

    public CompanionRenderSnapshot LatestRender { get; private set; }

    private bool _forceQuietSleep;
    private double _facingDirection = 1.0;
    private double _walkAnimTimer;
    private int _walkFrameIndex;
    private double _currentWalkSpeed;
    private double _breathPhase;
    private double _hoverWavePhase;
    private double _greetingPhase;
    private double _greetingTotalDuration = 10.0;
    private bool _didGreetingPerkHop;
    private double _greetingHoverAccumulator;
    private int _lastEatBiteIndex = -1;

    // Hover & drag
    private bool _isPeekHoverTextureActive;
    private Vec2 _pressStartScenePoint = Vec2.Zero;
    private Vec2 _dragGrabOffset = Vec2.Zero;
    private double _dragBlendProgress;
    private Vec2 _lastDragScenePoint = Vec2.Zero;
    private double _smoothedDragVelocityX;

    // Cross-fade
    private SpriteAssetKey _displayedSpriteKey = SpriteAssetKey.WestieIdle;
    private PetSpecies _displayedSpriteSpecies = PetSpecies.Westie;
    private SpriteAssetKey _retractTopSpriteKey = SpriteAssetKey.WestieSitTilt;
    private Size2D _retractTopSpriteSize = new(66, 66);
    private SpriteRenderLayer _lastPrimaryLayer;
    private SpriteRenderLayer _fadeOutLayer;
    private double _poseCrossfadeElapsed;
    private double _poseCrossfadeDuration;

    // Springs
    private DampedSpring _peekHoverSpring = new(0, 0, 0, 235, 17.5);
    private DampedSpring _peekEmergeSpring = new(0, 0, 0, 195, 18.5);
    private DampedSpring _squashSpring = new(0, 0, 0, 320, 15.5);
    private DampedSpring _tapHopSpring = new(0, 0, 0, 340, 16.5);
    private DampedSpring _swingRotationSpring = new(0, 0, 0, 190, 13.5);

    // State payload fields
    private double _stateRemaining = 20.0;
    private double _stateElapsed;
    private double _stateDuration = 1.0;
    private double _walkDirection = 1.0;

    // Top-story / hop / flash-step payload
    private int _hopsRemaining;
    private double _hopElapsed;
    private double _hopDuration = 0.56;
    private double _hopRestElapsed;
    private double _hopStartX;
    private double _hopTargetX;
    private int _flashRoundsRemaining;
    private double _flashStartX;
    private double _flashTargetX;

    // Stealth payload
    private PerchZone _stealthOriginZone = PerchZone.ScreenRightPeek;
    private StealthDestination _stealthDestination = new(PerchZone.ScreenRightPeek);
    private ulong _stealthOriginWindowId;
    private ulong _stealthDestWindowId;

    // Glide payload
    private Vec2 _glideFrom = Vec2.Zero;
    private Vec2 _glideTo = Vec2.Zero;
    private PerchZone _glideTargetZone = PerchZone.ScreenRightPeek;

    // Treat & particles
    private bool _hasTreatProp;
    private double _treatX;
    private double _treatBaseY;
    private double _treatDropElapsed;
    private readonly List<SnackCrumbParticle> _particles = [];

    // Window tracking offsets
    private Rect2D? _lastTrackedWindowFrame;
    private double _offsetFromWindowMinX = 240;
    private double _offsetFromWindowMaxY = 88;
    private double _screenRightCustomYRatio = 0.66;
    private double _focusAccumulator;
    private const double FocusInviteInterval = 25 * 60;

    private double ScaleFactor => Preferences.DogScale;
    private Size2D TopDogSize => new(66 * ScaleFactor, 66 * ScaleFactor);
    private Size2D YawnDogSize => new(54 * ScaleFactor, 54 * ScaleFactor);
    private Size2D ChinLedgeDogSize => new(54 * ScaleFactor, 54 * ScaleFactor);
    private Size2D TopPeekDogSize => new(44 * ScaleFactor, 44 * ScaleFactor);
    private Size2D PeekDogSize => new(76 * ScaleFactor, 76 * ScaleFactor);

    public bool IsGrounded => StateKind is not (CompanionStateKind.Gliding or CompanionStateKind.Dragged
        or CompanionStateKind.StealthTransition or CompanionStateKind.TuckedWaiting);

    public CompanionEngine(CompanionPreferences? preferences = null, int? ownPid = null)
    {
        Preferences = preferences ?? CompanionPreferences.Shared;
        _ownPid = ownPid ?? Environment.ProcessId;
        _displayedSpriteSpecies = Preferences.PetSpecies;

        _lastPrimaryLayer = new SpriteRenderLayer(
            false, SpriteAssetKey.WestieIdle, _displayedSpriteSpecies,
            Position, new Vec2(0.5, 0.04), TopDogSize, 1, 1, 0, 1);
        _fadeOutLayer = _lastPrimaryLayer with { IsVisible = false, Opacity = 0 };
        LatestRender = new CompanionRenderSnapshot(
            _lastPrimaryLayer, _fadeOutLayer, ClipMaskKind.None, 0,
            new TreatRenderState(false, SpriteAssetKey.BoneTreat, _displayedSpriteSpecies, Vec2.Zero, 28),
            new InviteBadgeRenderState(false, Vec2.Zero),
            _particles);
    }

    public void PlaceInitially(ActiveWorkspaceSnapshot snapshot, Size2D sceneSize)
    {
        PendingWindowSwitch = null;
        RightPeekDwellTimer = 0;
        var layout = snapshot.PerchLayout;
        TrackedWindowId = layout.ActiveWindowId ?? 0;

        if (layout.IsFullScreenMode)
        {
            SnapToScreenRightPeek(layout.ScreenRightPeek, sceneSize);
        }
        else
        {
            switch (Preferences.PerchPreference)
            {
                case PerchPreference.Auto:
                    SnapToScreenRightPeek(layout.ScreenRightPeek, sceneSize);
                    break;
                case PerchPreference.WindowTop:
                    if (layout.TopPerch is { } top)
                        LandOnWindowTop(top, top.ClampedX(top.MinX + top.Width * 0.62, 22));
                    else
                        SnapToScreenRightPeek(layout.ScreenRightPeek, sceneSize);
                    break;
                case PerchPreference.RightPeek:
                    if (layout.WindowRightPeek is { } right)
                        SnapToWindowRightPeek(right, layout.ActiveWindowFrame?.MaxY ?? right.MaxY);
                    else
                        SnapToScreenRightPeek(layout.ScreenRightPeek, sceneSize);
                    break;
            }
        }
        SyncVisuals(0);
    }

    public Rect2D InteractiveHitRect()
    {
        if (StateKind == CompanionStateKind.StealthTransition)
        {
            if (StealthPhase == StealthPhaseKind.HiddenTraverse) return Rect2D.Empty;
            if (StealthPhase == StealthPhaseKind.Retracting && _stateElapsed >= _stateDuration * 0.72) return Rect2D.Empty;
        }
        else if (StateKind == CompanionStateKind.TuckedWaiting && _stateElapsed >= _stateDuration * 0.55)
        {
            return Rect2D.Empty;
        }

        double k = ScaleFactor;
        Rect2D rect;
        if (StateKind == CompanionStateKind.Dragged)
        {
            rect = new Rect2D(Position.X - 42 * k, Position.Y - 16 * k, 84 * k, 84 * k);
        }
        else
        {
            switch (PerchZone)
            {
                case PerchZone.WindowTop:
                    rect = new Rect2D(Position.X - 36 * k, Position.Y - 4, 72 * k, 68 * k);
                    break;
                case PerchZone.ScreenRightPeek:
                {
                    bool expanded = IsHoveringDog || _peekHoverSpring.Value > 0.25;
                    double reach = (expanded ? 44 : 28) * k;
                    double halfH = (expanded ? 36 : 30) * k;
                    rect = new Rect2D(Position.X - reach, Position.Y - halfH, reach + 12, halfH * 2);
                    break;
                }
                case PerchZone.WindowRightPeek:
                default:
                {
                    bool expanded = IsHoveringDog || _peekHoverSpring.Value > 0.25;
                    double reach = (expanded ? 44 : 28) * k;
                    double halfH = (expanded ? 36 : 30) * k;
                    rect = new Rect2D(Position.X - 2, Position.Y - halfH, reach + 2, halfH * 2);
                    break;
                }
            }
        }

        if (LatestRender.InviteBadge.IsVisible)
        {
            var bp = LatestRender.InviteBadge.CenterPos;
            rect = rect.Union(new Rect2D(bp.X - 66, bp.Y - 20, 132, 40));
        }
        return rect;
    }

    public bool IsPointOnInviteBadge(Vec2 pt)
    {
        if (!LatestRender.InviteBadge.IsVisible) return false;
        var bp = LatestRender.InviteBadge.CenterPos;
        return new Rect2D(bp.X - 66, bp.Y - 20, 132, 40).Contains(pt);
    }

    public void PrepareForContextMenu()
    {
        ShyRetreatTimer = 0;
        IsPointerDownOnDog = false;
    }

    public void TriggerTennisInvite() => EnterTimedState(CompanionStateKind.HoldingTennisBall, 25.0);

    public void SummonToFrontWindow(ActiveWorkspaceSnapshot snapshot, Size2D sceneSize)
    {
        var layout = snapshot.PerchLayout;
        PendingWindowSwitch = null;
        RightPeekDwellTimer = 0;
        _hasTreatProp = false;
        TrackedWindowId = layout.ActiveWindowId ?? 0;

        if (layout.IsFullScreenMode)
        {
            SnapToScreenRightPeek(layout.ScreenRightPeek, sceneSize);
            return;
        }
        switch (Preferences.PerchPreference)
        {
            case PerchPreference.Auto:
                SnapToScreenRightPeek(layout.ScreenRightPeek, sceneSize);
                break;
            case PerchPreference.WindowTop:
                if (layout.TopPerch is { } top)
                {
                    LandOnWindowTop(top, top.ClampedX(top.MinX + top.Width * 0.62, 22));
                    EnterTimedState(CompanionStateKind.SitCalm, 5.0);
                }
                else
                {
                    SnapToScreenRightPeek(layout.ScreenRightPeek, sceneSize);
                }
                break;
            case PerchPreference.RightPeek:
                if (layout.WindowRightPeek is { } right)
                    SnapToWindowRightPeek(right, layout.ActiveWindowFrame?.MaxY ?? right.MaxY);
                else
                    SnapToScreenRightPeek(layout.ScreenRightPeek, sceneSize);
                break;
        }
    }

    public void MoveImmediatelyToZone(PerchZone targetZone, ActiveWorkspaceSnapshot snapshot, Size2D sceneSize)
    {
        PendingWindowSwitch = null;
        RightPeekDwellTimer = 0;
        var layout = snapshot.PerchLayout;
        switch (targetZone)
        {
            case PerchZone.WindowTop:
                if (layout.TopPerch is { } top)
                {
                    double x = top.ClampedX(top.MinX + top.Width * 0.62, 22);
                    BeginStealthClimbToTop(x, layout.ActiveWindowId ?? TrackedWindowId, climbToGreet: false);
                }
                break;
            case PerchZone.WindowRightPeek:
                if (layout.WindowRightPeek is { } right)
                    EmergeIntoRightPeek(right, right.ClampedY(Position.Y), PerchZone.WindowRightPeek, layout);
                else
                    EmergeIntoRightPeek(layout.ScreenRightPeek, layout.ScreenRightPeek.ClampedY(Position.Y), PerchZone.ScreenRightPeek, layout);
                break;
            case PerchZone.ScreenRightPeek:
                EmergeIntoRightPeek(layout.ScreenRightPeek, layout.ScreenRightPeek.ClampedY(Position.Y), PerchZone.ScreenRightPeek, layout);
                break;
        }
    }

    public void DropSnackTreat(ActiveWorkspaceSnapshot snapshot, Size2D sceneSize)
    {
        var layout = snapshot.PerchLayout;
        if (layout.TopPerch is not { } top)
        {
            _peekHoverSpring.Impulse(3.2);
            _squashSpring.Impulse(2.0);
            return;
        }

        if (PerchZone != PerchZone.WindowTop || TrackedWindowId != layout.ActiveWindowId)
        {
            double startX = top.ClampedX(top.MinX + top.Width * 0.62, 24);
            LandOnWindowTop(top, startX);
        }

        double treatX = top.Width > 140
            ? top.ClampedX(Position.X < top.MidX ? Math.Min(top.MaxX - 28, Position.X + 110) : Math.Max(top.MinX + 28, Position.X - 110), 24)
            : top.MidX;

        _hasTreatProp = true;
        _treatX = treatX;
        _treatBaseY = top.Y;
        _treatDropElapsed = 0;
        _squashSpring.Impulse(1.8);
        StateKind = CompanionStateKind.ChasingTreat;
    }

    public void SetHovering(bool hovering, double pointerSpeed = 0, bool nearZone = false)
    {
        if (Preferences.ShyRetreatEnabled && !IsPointerDownOnDog && StateKind != CompanionStateKind.Dragged &&
            (hovering || nearZone) && pointerSpeed >= 580.0)
        {
            ShyRetreatTimer = 0.45;
            IsHoveringDog = false;
            _peekHoverSpring.Target = -0.35;
            if (PerchZone == PerchZone.WindowTop && IsGrounded)
                _squashSpring.Target = -0.07;
            return;
        }

        if (hovering && pointerSpeed < 240.0)
        {
            ShyRetreatTimer = 0;
            if (PerchZone == PerchZone.WindowTop && !IsPointerDownOnDog)
                _squashSpring.Target = 0;
        }

        if (ShyRetreatTimer > 0)
        {
            IsHoveringDog = false;
            return;
        }

        if (IsHoveringDog == hovering) return;
        IsHoveringDog = hovering;
        _peekHoverSpring.Target = hovering ? 1.0 : 0.0;
        if (hovering)
        {
            if (PerchZone is PerchZone.ScreenRightPeek or PerchZone.WindowRightPeek)
                _squashSpring.Impulse(1.2);
            else if (IsGrounded && StateKind != CompanionStateKind.Sleeping)
                _squashSpring.Impulse(0.45);
        }
    }

    public bool HandleMouseDown(Vec2 scenePoint)
    {
        if (IsPointOnInviteBadge(scenePoint))
        {
            RequestStartTennis?.Invoke();
            return true;
        }
        if (StateKind == CompanionStateKind.HoldingTennisBall && InteractiveHitRect().Contains(scenePoint))
        {
            RequestStartTennis?.Invoke();
            return true;
        }
        if (!InteractiveHitRect().InsetBy(-4, -4).Contains(scenePoint)) return false;

        IsPointerDownOnDog = true;
        _pressStartScenePoint = scenePoint;
        _lastDragScenePoint = scenePoint;
        _dragGrabOffset = new Vec2(Position.X - scenePoint.X, Position.Y - scenePoint.Y);
        _dragBlendProgress = 0;
        _smoothedDragVelocityX = 0;
        _squashSpring.Target = -0.11;
        return true;
    }

    public void HandleMouseDragged(Vec2 scenePoint)
    {
        if (!IsPointerDownOnDog) return;

        if (StateKind != CompanionStateKind.Dragged)
        {
            if (Vec2.Distance(scenePoint, _pressStartScenePoint) < DragStartThreshold) return;
            StateKind = CompanionStateKind.Dragged;
            _hasTreatProp = false;
            _squashSpring.Target = 0;
            _squashSpring.Impulse(2.3);
        }

        double dx = scenePoint.X - _lastDragScenePoint.X;
        _lastDragScenePoint = scenePoint;
        _smoothedDragVelocityX = _smoothedDragVelocityX * 0.62 + (dx * 60.0) * 0.38;
        _swingRotationSpring.Target = Math.Clamp(-_smoothedDragVelocityX * 0.00055, -0.30, 0.30);

        if (Math.Abs(dx) > 1.2) _facingDirection = dx > 0 ? 1.0 : -1.0;

        _dragBlendProgress = Math.Min(1.0, _dragBlendProgress + 0.14);
        double offX = _dragGrabOffset.X + (0 - _dragGrabOffset.X) * _dragBlendProgress;
        double offY = _dragGrabOffset.Y + (-22 - _dragGrabOffset.Y) * _dragBlendProgress;
        Position = new Vec2(scenePoint.X + offX, scenePoint.Y + offY);
    }

    public void HandleMouseUp(Vec2 scenePoint, ActiveWorkspaceSnapshot? snapshot, Size2D sceneSize)
    {
        if (!IsPointerDownOnDog && StateKind != CompanionStateKind.Dragged) return;
        bool wasDragging = StateKind == CompanionStateKind.Dragged;
        IsPointerDownOnDog = false;
        _squashSpring.Target = 0;
        _swingRotationSpring.Target = 0;
        _smoothedDragVelocityX = 0;

        if (!wasDragging)
        {
            HandleGentleTap();
            return;
        }

        if (snapshot?.PerchLayout is not { } layout)
        {
            EnterTimedState(CompanionStateKind.Idle, 5.0);
            return;
        }

        if (layout.IsFullScreenMode)
        {
            var anchor = layout.ScreenRightPeek;
            double clampedY = anchor.ClampedY(scenePoint.Y);
            if (sceneSize.Height > 100)
                _screenRightCustomYRatio = Math.Clamp(clampedY / sceneSize.Height, 0.15, 0.88);
            BeginSmoothGlide(new Vec2(anchor.EdgeX, clampedY), PerchZone.ScreenRightPeek, layout);
            return;
        }

        var candidates = new List<(double Dist, Vec2 Point, PerchZone Zone)>();
        if (layout.TopPerch is { } top)
        {
            var pt = new Vec2(top.ClampedX(scenePoint.X, 20), top.Y);
            candidates.Add((Vec2.Distance(scenePoint, pt), pt, PerchZone.WindowTop));
        }
        if (Preferences.PerchPreference == PerchPreference.RightPeek && layout.WindowRightPeek is { } right)
        {
            var pt = new Vec2(right.EdgeX, right.ClampedY(scenePoint.Y));
            candidates.Add((Vec2.Distance(scenePoint, pt), pt, PerchZone.WindowRightPeek));
        }
        {
            var anchor = layout.ScreenRightPeek;
            var pt = new Vec2(anchor.EdgeX, anchor.ClampedY(scenePoint.Y));
            candidates.Add((Vec2.Distance(scenePoint, pt), pt, PerchZone.ScreenRightPeek));
        }

        candidates.Sort((a, b) => a.Dist.CompareTo(b.Dist));
        var best = candidates[0];
        if (best.Zone == PerchZone.WindowRightPeek && layout.ActiveWindowFrame is { } f)
            _offsetFromWindowMaxY = Math.Max(42, f.MaxY - best.Point.Y);
        else if (best.Zone == PerchZone.ScreenRightPeek && sceneSize.Height > 100)
            _screenRightCustomYRatio = Math.Clamp(best.Point.Y / sceneSize.Height, 0.15, 0.88);

        BeginSmoothGlide(best.Point, best.Zone, layout);
    }

    private TopTapPose? CurrentTopTapPose() => StateKind switch
    {
        CompanionStateKind.SitCalm => TopTapPose.SitSmile,
        CompanionStateKind.Loafing => TopTapPose.LoafCalm,
        CompanionStateKind.ChinRest => TopTapPose.BigHeadPeek,
        CompanionStateKind.Sleeping => TopTapPose.Sleep,
        _ => null
    };

    private void ApplyTopTapPose(TopTapPose pose)
    {
        _facingDirection = 1.0;
        switch (pose)
        {
            case TopTapPose.SitSmile: EnterTimedState(CompanionStateKind.SitCalm, 14.0); break;
            case TopTapPose.LoafCalm: EnterTimedState(CompanionStateKind.Loafing, 16.0); break;
            case TopTapPose.BigHeadPeek: EnterTimedState(CompanionStateKind.ChinRest, 14.0); break;
            case TopTapPose.Sleep: EnterTimedState(CompanionStateKind.Sleeping, 35.0); break;
        }
    }

    private void HandleGentleTap()
    {
        if (PerchZone is PerchZone.ScreenRightPeek or PerchZone.WindowRightPeek)
        {
            _peekHoverSpring.Impulse(3.0);
            _squashSpring.Impulse(2.1);
            return;
        }

        _greetingHoverAccumulator = 0;
        _currentWalkSpeed = 0;

        if (ForceQuietSleep)
        {
            _squashSpring.Impulse(1.4);
            return;
        }

        var enabled = Preferences.OrderedEnabledTopTapPoses;
        TopTapPose nextPose;
        if (CurrentTopTapPose() is { } cur)
        {
            int idx = -1;
            for (int i = 0; i < enabled.Count; i++)
                if (enabled[i] == cur) { idx = i; break; }
            nextPose = idx >= 0 ? enabled[(idx + 1) % enabled.Count] : enabled[0];
        }
        else if (StateKind == CompanionStateKind.Sleeping)
        {
            nextPose = enabled[0];
            foreach (var p in enabled)
                if (p != TopTapPose.Sleep) { nextPose = p; break; }
        }
        else
        {
            nextPose = enabled[0];
        }

        _tapHopSpring.Impulse(nextPose == TopTapPose.Sleep ? 75.0 : 125.0);
        _squashSpring.Impulse(nextPose == TopTapPose.Sleep ? 1.5 : 2.3);
        ApplyTopTapPose(nextPose);
    }

    // MARK: - Main Frame Update

    public void Update(double dt, ActiveWorkspaceSnapshot snapshot, Size2D sceneSize)
    {
        double clampedDt = Math.Clamp(dt, 0.001, 0.08);
        _breathPhase += clampedDt * 2.2;

        if (ShyRetreatTimer > 0)
        {
            ShyRetreatTimer = Math.Max(0, ShyRetreatTimer - clampedDt);
            if (ShyRetreatTimer == 0 && !IsPointerDownOnDog && StateKind != CompanionStateKind.Dragged)
                _squashSpring.Target = 0;
        }

        UpdateWindowMotionInertia(snapshot, clampedDt);

        _peekHoverSpring.Target = ShyRetreatTimer > 0 ? -0.35 : (IsHoveringDog ? 1.0 : 0.0);
        _peekHoverSpring.Step(clampedDt);
        _peekEmergeSpring.Step(clampedDt);
        _squashSpring.Step(clampedDt);
        _tapHopSpring.Step(clampedDt);
        if (StateKind != CompanionStateKind.Dragged) _smoothedDragVelocityX *= 0.78;
        _swingRotationSpring.Step(clampedDt);

        if (_peekHoverSpring.Value >= 0.44) _isPeekHoverTextureActive = true;
        else if (_peekHoverSpring.Value <= 0.28) _isPeekHoverTextureActive = false;

        _hoverWavePhase = _peekHoverSpring.Value > 0.04 ? _hoverWavePhase + clampedDt : 0;

        if (!snapshot.IsMeetingActive && !ForceQuietSleep)
            _focusAccumulator += clampedDt;

        StepParticles(clampedDt);
        if (_hasTreatProp) _treatDropElapsed += clampedDt;

        ReconcileWithActiveWindow(snapshot, sceneSize, clampedDt);

        bool shouldInvite = _focusAccumulator >= FocusInviteInterval;
        if (shouldInvite) _focusAccumulator = 0;
        var context = new CompanionContext(
            snapshot.IsMeetingActive, snapshot.IsCodingActive, ForceQuietSleep, shouldInvite);

        StepState(clampedDt, snapshot, context, sceneSize);
        SyncVisuals(clampedDt);
    }

    private void StepParticles(double dt)
    {
        for (int i = _particles.Count - 1; i >= 0; i--)
        {
            var p = _particles[i];
            p.Elapsed += dt;
            if (p.Elapsed >= p.Duration)
            {
                _particles.RemoveAt(i);
                continue;
            }
            if (p.LabelText is null)
            {
                p.Vy -= 140.0 * ScaleFactor * dt;
            }
            p.X += p.Vx * dt;
            p.Y += p.Vy * dt;
        }
    }

    private void SpawnSnackCrumbs(bool finalSparkle)
    {
        double k = ScaleFactor;
        double mouthX = Position.X + (_facingDirection >= 0 ? 14.0 : -14.0) * k;
        double mouthY = Position.Y + 18.0 * k;
        string color = Preferences.PetSpecies == PetSpecies.GoldenCat ? "#E0AB5C" : "#F5E8C7";

        int count = finalSparkle ? 5 : 3;
        for (int i = 0; i < count; i++)
        {
            double sz = (2.5 + _rng.NextDouble() * 2.0) * Math.Max(0.85, k * 0.85);
            double vx = (-38 + _rng.NextDouble() * 76) * k;
            double vy = (42 + _rng.NextDouble() * 44) * k;
            double dur = 0.28 + _rng.NextDouble() * 0.14;
            _particles.Add(new SnackCrumbParticle(mouthX, mouthY, vx, vy, sz, color, dur));
        }

        if (finalSparkle)
        {
            string txt = Preferences.PetSpecies == PetSpecies.GoldenCat ? "🐟✨" : "🦴✨";
            _particles.Add(new SnackCrumbParticle(
                Position.X, Position.Y + 52 * k, 0, 32 * k, 13 * Math.Max(0.9, k * 0.85), "#FFFFFF", 0.55, txt));
        }
    }

    private void UpdateWindowMotionInertia(ActiveWorkspaceSnapshot snapshot, double dt)
    {
        Rect2D? curFrame = snapshot.WindowFramesById.TryGetValue(TrackedWindowId, out var f)
            ? f
            : (snapshot.PerchLayout.ActiveWindowId == TrackedWindowId ? snapshot.PerchLayout.ActiveWindowFrame : null);

        if (StateKind != CompanionStateKind.Dragged && _lastTrackedWindowFrame is { } prev && curFrame is { } cur && dt > 0.0005)
        {
            double winVelX = (cur.MinX - prev.MinX) / dt;
            _swingRotationSpring.Target = Math.Abs(winVelX) > 8.0
                ? Math.Clamp(-winVelX * 0.00015, -0.085, 0.085)
                : 0;
        }
        else if (StateKind != CompanionStateKind.Dragged)
        {
            _swingRotationSpring.Target = 0;
        }

        _lastTrackedWindowFrame = curFrame;
    }

    public StealthDestination ResolveShortestPathDestination(Vec2 previousPosition, ActiveWindowPerchLayout newLayout)
    {
        if (newLayout.IsFullScreenMode)
            return new StealthDestination(PerchZone.ScreenRightPeek, TargetY: newLayout.ScreenRightPeek.ClampedY(previousPosition.Y));

        return Preferences.PerchPreference switch
        {
            PerchPreference.Auto => new StealthDestination(
                PerchZone.ScreenRightPeek, TargetY: newLayout.ScreenRightPeek.ClampedY(previousPosition.Y)),
            PerchPreference.WindowTop => newLayout.TopPerch is { } top
                ? new StealthDestination(PerchZone.WindowTop, TargetX: top.ClampedX(previousPosition.X, 22))
                : new StealthDestination(PerchZone.ScreenRightPeek, TargetY: newLayout.ScreenRightPeek.ClampedY(previousPosition.Y)),
            PerchPreference.RightPeek => newLayout.WindowRightPeek is { } right
                ? new StealthDestination(PerchZone.WindowRightPeek, TargetY: right.ClampedY(previousPosition.Y))
                : new StealthDestination(PerchZone.ScreenRightPeek, TargetY: newLayout.ScreenRightPeek.ClampedY(previousPosition.Y)),
            _ => new StealthDestination(PerchZone.ScreenRightPeek, TargetY: newLayout.ScreenRightPeek.ClampedY(previousPosition.Y))
        };
    }

    private Rect2D CurrentVisibleSpriteRect()
    {
        double k = ScaleFactor;
        return PerchZone switch
        {
            PerchZone.WindowTop => new Rect2D(Position.X - 28 * k, Position.Y + 4, 56 * k, 54 * k),
            PerchZone.WindowRightPeek => new Rect2D(Position.X + 2, Position.Y - 30 * k, 46 * k, 60 * k),
            _ => new Rect2D(Position.X - 50 * k, Position.Y - 30 * k, 48 * k, 60 * k)
        };
    }

    private void AnchorPositionToWindowLayout(ActiveWindowPerchLayout layout, Size2D sceneSize)
    {
        switch (PerchZone)
        {
            case PerchZone.WindowTop:
                if (layout.TopPerch is { } top)
                {
                    Position = new Vec2(top.ClampedX(top.WindowMinX + _offsetFromWindowMinX, 18), top.Y);
                    CurrentPlatform = top;
                    if (_hasTreatProp)
                    {
                        _treatBaseY = top.Y;
                        _treatX = top.ClampedX(_treatX, 20);
                    }
                }
                else if (Preferences.PerchPreference == PerchPreference.RightPeek && layout.WindowRightPeek is { } right)
                {
                    _hasTreatProp = false;
                    EmergeIntoRightPeek(right, right.ClampedY(Position.Y), PerchZone.WindowRightPeek, layout);
                }
                else
                {
                    _hasTreatProp = false;
                    var anchor = layout.ScreenRightPeek;
                    double targetY = anchor.ClampedY(Position.Y);
                    if (sceneSize.Height > 100)
                        _screenRightCustomYRatio = Math.Clamp(targetY / sceneSize.Height, 0.15, 0.88);
                    EmergeIntoRightPeek(anchor, targetY, PerchZone.ScreenRightPeek, layout);
                }
                break;

            case PerchZone.WindowRightPeek:
                if (layout.WindowRightPeek is { } r)
                {
                    double winMaxY = layout.ActiveWindowFrame?.MaxY ?? r.MaxY;
                    Position = new Vec2(r.EdgeX, r.ClampedY(winMaxY - _offsetFromWindowMaxY));
                    CurrentRightAnchor = r;
                }
                else if (layout.TopPerch is { } t)
                {
                    BeginStealthClimbToTop(t.ClampedX(t.MinX + t.Width * 0.65, 20), layout.ActiveWindowId ?? TrackedWindowId, false);
                }
                else
                {
                    SnapToScreenRightPeek(layout.ScreenRightPeek, sceneSize);
                }
                break;

            case PerchZone.ScreenRightPeek:
                var sr = layout.ScreenRightPeek;
                Position = new Vec2(sr.EdgeX, sr.ClampedY(sceneSize.Height * _screenRightCustomYRatio));
                CurrentRightAnchor = sr;
                break;
        }
    }

    private void FollowAnchorDuringStealth(PerchZone zone, ActiveWindowPerchLayout layout)
    {
        switch (zone)
        {
            case PerchZone.WindowTop:
                if (layout.TopPerch is { } top)
                {
                    Position = new Vec2(top.ClampedX(top.WindowMinX + _offsetFromWindowMinX, 18), top.Y);
                    CurrentPlatform = top;
                }
                break;
            case PerchZone.WindowRightPeek:
                if (layout.WindowRightPeek is { } right)
                {
                    double winMaxY = layout.ActiveWindowFrame?.MaxY ?? right.MaxY;
                    Position = new Vec2(right.EdgeX, right.ClampedY(winMaxY - _offsetFromWindowMaxY));
                    CurrentRightAnchor = right;
                }
                break;
            case PerchZone.ScreenRightPeek:
                var sr = layout.ScreenRightPeek;
                Position = new Vec2(sr.EdgeX, sr.ClampedY(Position.Y));
                CurrentRightAnchor = sr;
                break;
        }
    }

    private void ReconcileWithActiveWindow(ActiveWorkspaceSnapshot snapshot, Size2D sceneSize, double dt)
    {
        if (StateKind is CompanionStateKind.Dragged or CompanionStateKind.Gliding or CompanionStateKind.StealthTransition)
            return;

        var layout = snapshot.PerchLayout;

        // 1. Fullscreen or maximized window -> smooth in-place duck behind rising window, then emerge on screen right!
        if (layout.IsFullScreenMode)
        {
            PendingWindowSwitch = null;
            RightPeekDwellTimer = 0;
            var anchor = layout.ScreenRightPeek;
            double desiredY = PerchZone == PerchZone.WindowTop
                ? anchor.ClampedY(sceneSize.Height * _screenRightCustomYRatio)
                : anchor.ClampedY(Position.Y);

            if (PerchZone != PerchZone.ScreenRightPeek)
            {
                _hasTreatProp = false;
                if (PerchZone != PerchZone.WindowTop && sceneSize.Height > 100)
                    _screenRightCustomYRatio = Math.Clamp(desiredY / sceneSize.Height, 0.15, 0.88);
                bool alreadyHidden = StateKind == CompanionStateKind.TuckedWaiting;
                BeginStealthTransition(
                    new StealthDestination(PerchZone.ScreenRightPeek, TargetY: desiredY),
                    layout.ActiveWindowId ?? 0,
                    skipRetract: alreadyHidden,
                    retractDuration: PerchZone == PerchZone.WindowTop ? 0.42 : 0.65);
            }
            else
            {
                CurrentRightAnchor = anchor;
                Position = new Vec2(anchor.EdgeX, anchor.ClampedY(sceneSize.Height * _screenRightCustomYRatio));
            }
            return;
        }

        // 2. Resting on screen right edge (default `.auto` stays calm with zero distraction!)
        ulong activeId = layout.ActiveWindowId ?? 0;
        if (PerchZone == PerchZone.ScreenRightPeek)
        {
            if (Preferences.PerchPreference == PerchPreference.Auto)
            {
                if (activeId != 0 && activeId != TrackedWindowId)
                {
                    TrackedWindowId = activeId;
                    RightPeekDwellTimer = 0;
                }
                PendingWindowSwitch = null;
                AnchorPositionToWindowLayout(layout, sceneSize);
                return;
            }

            bool hasTarget = (Preferences.PerchPreference == PerchPreference.WindowTop && layout.TopPerch is not null) ||
                             (Preferences.PerchPreference == PerchPreference.RightPeek && layout.WindowRightPeek is not null);
            if (hasTarget)
            {
                PendingWindowSwitch = null;
                RightPeekDwellTimer = 0;
                BeginStealthTransition(ResolveShortestPathDestination(Position, layout), activeId, false);
                return;
            }
            AnchorPositionToWindowLayout(layout, sceneSize);
            return;
        }

        // 3. Active window changed while perched on windowTop / windowRightPeek -> dwell debounce + overlap early-tuck
        if (activeId != 0 && activeId != TrackedWindowId)
        {
            bool oldStillVisible = TrackedWindowId != 0 && snapshot.WindowFramesById.ContainsKey(TrackedWindowId);
            if (oldStillVisible && snapshot.GetPerchLayoutForWindow(TrackedWindowId) is { } oldLayout)
            {
                AnchorPositionToWindowLayout(oldLayout, sceneSize);
                if (StateKind != CompanionStateKind.TuckedWaiting)
                {
                    bool occluded = PlatformPhysics.IsRectOccludedByFrontWindows(
                        CurrentVisibleSpriteRect(), TrackedWindowId, snapshot.WindowsFrontToBack, _ownPid);
                    if (occluded)
                    {
                        _hasTreatProp = false;
                        if (PerchZone == PerchZone.WindowTop)
                        {
                            _retractTopSpriteKey = _displayedSpriteKey;
                            _retractTopSpriteSize = _lastPrimaryLayer.Size;
                        }
                        _stealthOriginZone = PerchZone;
                        StateKind = CompanionStateKind.TuckedWaiting;
                        _stateElapsed = 0;
                        _stateDuration = 0.28;
                    }
                }
            }

            if (PendingWindowSwitch?.TargetWindowId == activeId)
                PendingWindowSwitch.Elapsed += dt;
            else
                PendingWindowSwitch = new PendingWindowSwitch(activeId);

            double delayNeeded = oldStillVisible ? Preferences.WindowSwitchDelaySeconds : 0.0;
            if (PendingWindowSwitch.Elapsed >= delayNeeded)
            {
                PendingWindowSwitch = null;
                RightPeekDwellTimer = 0;
                _hasTreatProp = false;
                bool skipRetract = !oldStillVisible ||
                    (StateKind == CompanionStateKind.TuckedWaiting && _stateElapsed >= _stateDuration * 0.85);
                BeginStealthTransition(ResolveShortestPathDestination(Position, layout), activeId, skipRetract);
            }
            return;
        }

        // 4. Returned to same window before dwell delay expired -> cancel & re-emerge if tucked early!
        if (PendingWindowSwitch is not null)
        {
            PendingWindowSwitch = null;
            if (StateKind == CompanionStateKind.TuckedWaiting)
            {
                var reemergeDest = _stealthOriginZone switch
                {
                    PerchZone.WindowTop => new StealthDestination(PerchZone.WindowTop, TargetX: layout.TopPerch?.ClampedX(Position.X, 18) ?? Position.X),
                    PerchZone.WindowRightPeek => new StealthDestination(PerchZone.WindowRightPeek, TargetY: layout.WindowRightPeek?.ClampedY(Position.Y) ?? Position.Y),
                    _ => new StealthDestination(PerchZone.ScreenRightPeek, TargetY: layout.ScreenRightPeek.ClampedY(Position.Y))
                };
                StateKind = CompanionStateKind.StealthTransition;
                StealthPhase = StealthPhaseKind.TentativePeek;
                _stateElapsed = 0;
                _stateDuration = 0.44;
                _stealthDestination = reemergeDest;
                _stealthOriginWindowId = TrackedWindowId;
                _stealthDestWindowId = TrackedWindowId;
                return;
            }
        }

        if (TrackedWindowId == 0 && activeId != 0) TrackedWindowId = activeId;
        AnchorPositionToWindowLayout(layout, sceneSize);
    }

    public void BeginStealthTransition(
        StealthDestination destination,
        ulong destWindowId,
        bool skipRetract,
        double retractDuration = 0.65)
    {
        _stealthOriginZone = PerchZone;
        _stealthOriginWindowId = TrackedWindowId;
        _stealthDestWindowId = destWindowId;
        _stealthDestination = destination;
        if (_stealthOriginZone == PerchZone.WindowTop)
        {
            _retractTopSpriteKey = _displayedSpriteKey;
            _retractTopSpriteSize = _lastPrimaryLayer.Size;
        }
        StateKind = CompanionStateKind.StealthTransition;
        StealthPhase = skipRetract ? StealthPhaseKind.HiddenTraverse : StealthPhaseKind.Retracting;
        _stateElapsed = 0;
        _stateDuration = skipRetract ? 0.24 : retractDuration;
    }

    public void BeginStealthClimbToTop(
        double targetX,
        ulong windowId,
        bool climbToGreet,
        TopClimbRoutine? routineOverride = null)
    {
        bool alreadyTop = PerchZone == PerchZone.WindowTop;
        BeginStealthTransition(
            new StealthDestination(PerchZone.WindowTop, TargetX: targetX, ClimbToGreet: climbToGreet, RoutineOverride: routineOverride),
            windowId,
            skipRetract: alreadyTop,
            retractDuration: 0.62);
        if (alreadyTop) _stateDuration = 0.16;
    }

    private void EmergeIntoRightPeek(RightEdgeAnchor anchor, double targetY, PerchZone zone, ActiveWindowPerchLayout layout)
    {
        TrackedWindowId = layout.ActiveWindowId ?? TrackedWindowId;
        double clampedY = anchor.ClampedY(targetY);
        if (zone == PerchZone.WindowRightPeek)
        {
            SnapToWindowRightPeek(anchor, layout.ActiveWindowFrame?.MaxY ?? anchor.MaxY, clampedY);
        }
        else
        {
            PerchZone = PerchZone.ScreenRightPeek;
            CurrentPlatform = null;
            CurrentRightAnchor = anchor;
            Position = new Vec2(anchor.EdgeX, clampedY);
            RightPeekDwellTimer = 0;
            EnterTimedState(CompanionStateKind.PeekingRight, 30.0);
        }
        _peekEmergeSpring.Value = -1.10;
        _peekEmergeSpring.Velocity = 1.5;
        _peekEmergeSpring.Target = 0.0;
    }

    private void BeginSmoothGlide(Vec2 target, PerchZone targetZone, ActiveWindowPerchLayout layout)
    {
        double dist = Vec2.Distance(target, Position);
        TrackedWindowId = layout.ActiveWindowId ?? TrackedWindowId;
        if (dist < 14)
        {
            FinishGlideArrival(target, targetZone, layout);
            return;
        }
        _facingDirection = target.X >= Position.X ? 1.0 : -1.0;
        _squashSpring.Impulse(2.5);
        StateKind = CompanionStateKind.Gliding;
        _stateElapsed = 0;
        _stateDuration = Math.Clamp(dist / 880.0, 0.20, 0.40);
        _glideFrom = Position;
        _glideTo = target;
        _glideTargetZone = targetZone;
    }

    private void FinishGlideArrival(Vec2 target, PerchZone targetZone, ActiveWindowPerchLayout layout)
    {
        switch (targetZone)
        {
            case PerchZone.WindowTop:
                _squashSpring.Impulse(-3.0);
                if (layout.TopPerch is { } top) LandOnWindowTop(top, target.X);
                else { PerchZone = PerchZone.WindowTop; Position = target; EnterTimedState(CompanionStateKind.Idle, 5.0); }
                break;
            case PerchZone.WindowRightPeek:
                if (layout.WindowRightPeek is { } right) EmergeIntoRightPeek(right, target.Y, PerchZone.WindowRightPeek, layout);
                else { PerchZone = PerchZone.WindowRightPeek; Position = target; EnterTimedState(CompanionStateKind.PeekingRight, 20.0); }
                break;
            case PerchZone.ScreenRightPeek:
                EmergeIntoRightPeek(layout.ScreenRightPeek, target.Y, PerchZone.ScreenRightPeek, layout);
                break;
        }
    }

    private void LandOnWindowTop(WindowPlatform platform, double rawX)
    {
        double x = platform.ClampedX(rawX, 18);
        PerchZone = PerchZone.WindowTop;
        CurrentPlatform = platform;
        CurrentRightAnchor = null;
        TrackedWindowId = platform.WindowId;
        _offsetFromWindowMinX = x - platform.WindowMinX;
        Position = new Vec2(x, platform.Y);
        EnterTimedState(ForceQuietSleep ? CompanionStateKind.Sleeping : CompanionStateKind.Idle, ForceQuietSleep ? 25.0 : 4.5);
    }

    private void SnapToWindowRightPeek(RightEdgeAnchor anchor, double windowMaxY, double? customY = null)
    {
        double y = anchor.ClampedY(customY ?? anchor.DefaultY);
        PerchZone = PerchZone.WindowRightPeek;
        CurrentPlatform = null;
        CurrentRightAnchor = anchor;
        _offsetFromWindowMaxY = Math.Max(42, windowMaxY - y);
        Position = new Vec2(anchor.EdgeX, y);
        EnterTimedState(CompanionStateKind.PeekingRight, 18.0 + _rng.NextDouble() * 10.0);
    }

    private void SnapToScreenRightPeek(RightEdgeAnchor anchor, Size2D sceneSize)
    {
        double y = anchor.ClampedY(sceneSize.Height * _screenRightCustomYRatio);
        PerchZone = PerchZone.ScreenRightPeek;
        CurrentPlatform = null;
        CurrentRightAnchor = anchor;
        Position = new Vec2(anchor.EdgeX, y);
        EnterTimedState(CompanionStateKind.PeekingRight, 30.0);
    }

    private void EnterTimedState(CompanionStateKind kind, double remaining)
    {
        StateKind = kind;
        _stateRemaining = remaining;
        _stateElapsed = 0;
        _stateDuration = remaining;
    }

    private void CompleteStealthArrival(ActiveWorkspaceSnapshot snapshot, Size2D sceneSize)
    {
        var destLayout = snapshot.GetPerchLayoutForWindow(_stealthDestWindowId) ?? snapshot.PerchLayout;
        TrackedWindowId = _stealthDestWindowId != 0 ? _stealthDestWindowId : (destLayout.ActiveWindowId ?? TrackedWindowId);
        RightPeekDwellTimer = 0;
        _greetingHoverAccumulator = 0;

        switch (_stealthDestination.PerchZone)
        {
            case PerchZone.WindowTop:
                _squashSpring.Impulse(-1.4);
                if (destLayout.TopPerch is { } top)
                {
                    LandOnWindowTop(top, _stealthDestination.TargetX);
                    if (_stealthDestination.ClimbToGreet && !ForceQuietSleep && !snapshot.IsMeetingActive)
                    {
                        _greetingPhase = 0;
                        _greetingTotalDuration = Preferences.GreetingDurationSeconds;
                        _didGreetingPerkHop = false;
                        var baseRoutine = _stealthDestination.RoutineOverride ?? Preferences.TopClimbRoutine;
                        var chosen = baseRoutine == TopClimbRoutine.Random
                            ? (_rng.Next(2) == 0 ? TopClimbRoutine.FlashStep : TopClimbRoutine.ClassicStory)
                            : baseRoutine;

                        if (chosen == TopClimbRoutine.FlashStep)
                        {
                            _facingDirection = 1.0;
                            StateKind = CompanionStateKind.TopStory;
                            TopStoryStep = TopStoryStepKind.FlashStep;
                            FlashStepBeat = FlashStepBeatKind.Stance;
                            _flashRoundsRemaining = 2;
                            _stateElapsed = 0;
                            _stateDuration = 0.44;
                        }
                        else
                        {
                            _facingDirection = -1.0;
                            StateKind = CompanionStateKind.TopStory;
                            TopStoryStep = TopStoryStepKind.PostClimbPause;
                            _stateElapsed = 0;
                            _stateDuration = 0.42;
                        }
                    }
                }
                else
                {
                    PerchZone = PerchZone.WindowTop;
                    EnterTimedState(_stealthDestination.ClimbToGreet ? CompanionStateKind.Yawning : CompanionStateKind.Idle,
                        _stealthDestination.ClimbToGreet ? 1.75 : 5.0);
                }
                break;

            case PerchZone.WindowRightPeek:
                if (destLayout.WindowRightPeek is { } right)
                    SnapToWindowRightPeek(right, destLayout.ActiveWindowFrame?.MaxY ?? right.MaxY, _stealthDestination.TargetY);
                else
                    SnapToScreenRightPeek(destLayout.ScreenRightPeek, sceneSize);
                break;

            case PerchZone.ScreenRightPeek:
                var anchor = destLayout.ScreenRightPeek;
                double clampedY = anchor.ClampedY(_stealthDestination.TargetY);
                if (sceneSize.Height > 100)
                    _screenRightCustomYRatio = Math.Clamp(clampedY / sceneSize.Height, 0.15, 0.88);
                PerchZone = PerchZone.ScreenRightPeek;
                CurrentPlatform = null;
                CurrentRightAnchor = anchor;
                Position = new Vec2(anchor.EdgeX, clampedY);
                EnterTimedState(CompanionStateKind.PeekingRight, 30.0);
                break;
        }
    }

    // MARK: - Behavior State Machine

    private void StepState(double dt, ActiveWorkspaceSnapshot snapshot, CompanionContext context, Size2D sceneSize)
    {
        var layout = snapshot.PerchLayout;

        switch (StateKind)
        {
            case CompanionStateKind.TuckedWaiting:
                _stateElapsed = Math.Min(_stateDuration, _stateElapsed + dt);
                break;

            case CompanionStateKind.StealthTransition:
                StepStealthTransition(dt, snapshot, sceneSize);
                break;

            case CompanionStateKind.TopStory:
                StepTopStory(dt);
                break;

            case CompanionStateKind.Yawning:
                _currentWalkSpeed = 0;
                _facingDirection = 1.0;
                _stateElapsed += dt;
                if (_stateElapsed >= _stateDuration)
                {
                    _squashSpring.Impulse(-1.1);
                    StateKind = CompanionStateKind.SettlingToSleep;
                    _stateElapsed = 0;
                    _stateDuration = 4.2;
                }
                break;

            case CompanionStateKind.SettlingToSleep:
                _currentWalkSpeed = 0;
                _facingDirection = 1.0;
                _stateElapsed += dt;
                if (_stateElapsed >= _stateDuration)
                    EnterTimedState(CompanionStateKind.Sleeping, 45.0);
                break;

            case CompanionStateKind.GreetingOnTop:
                bool typing = Preferences.TypingPauseEnabled && snapshot.SecondsSinceLastKeyDown < 2.5;
                if (!typing)
                {
                    _greetingPhase += dt;
                    if (!_didGreetingPerkHop && _greetingPhase >= 2.6 && _stateRemaining > 3.8)
                    {
                        _didGreetingPerkHop = true;
                        _tapHopSpring.Impulse(48.0);
                        _squashSpring.Impulse(1.1);
                    }
                }
                if (IsHoveringDog && ShyRetreatTimer == 0)
                {
                    _greetingHoverAccumulator += dt;
                    if (_greetingHoverAccumulator >= 0.35)
                    {
                        _tapHopSpring.Impulse(120.0);
                        _squashSpring.Impulse(2.2);
                        _greetingHoverAccumulator = 0;
                        EnterTimedState(CompanionStateKind.Loafing, 15.0);
                        return;
                    }
                }
                else
                {
                    _greetingHoverAccumulator = 0;
                }
                _stateRemaining -= dt;
                if (_stateRemaining <= 0) EnterTimedState(CompanionStateKind.Sleeping, 45.0);
                break;

            case CompanionStateKind.Idle:
            case CompanionStateKind.SitCalm:
            case CompanionStateKind.Loafing:
            case CompanionStateKind.ChinRest:
            case CompanionStateKind.Sleeping:
                _stateRemaining -= dt;
                if (_stateRemaining <= 0)
                {
                    if (PerchZone == PerchZone.WindowTop && layout.TopPerch is { } top)
                    {
                        var (nextKind, nextDir, nextDur) = WestieBehaviorPlanner.ChooseNextTopBehavior(Position.X, top, context);
                        _walkDirection = nextDir;
                        EnterTimedState(nextKind, nextDur);
                    }
                    else
                    {
                        EnterTimedState(CompanionStateKind.PeekingRight, 22.0);
                    }
                }
                break;

            case CompanionStateKind.PeekingRight:
            {
                bool canClimb = (PerchZone == PerchZone.ScreenRightPeek && !layout.IsFullScreenMode && layout.TopPerch is not null)
                    || (PerchZone == PerchZone.WindowRightPeek && PendingWindowSwitch is null);
                if (canClimb && !IsHoveringDog && !context.ForceQuietSleep && !context.IsMeetingActive)
                    RightPeekDwellTimer += dt;

                bool typingPaused = Preferences.TypingPauseEnabled && snapshot.SecondsSinceLastKeyDown < 2.5;
                if (canClimb && Preferences.ClimbToTopEnabled && !context.ForceQuietSleep && !context.IsMeetingActive &&
                    !IsHoveringDog && !typingPaused && RightPeekDwellTimer >= Preferences.ClimbToTopIntervalSeconds &&
                    layout.TopPerch is { } top)
                {
                    RightPeekDwellTimer = 0;
                    double targetX = top.ClampedX(top.MaxX - Math.Min(110, top.Width * 0.26), 22);
                    BeginStealthClimbToTop(targetX, layout.ActiveWindowId ?? TrackedWindowId, climbToGreet: true);
                    return;
                }

                _stateRemaining -= dt;
                if (_stateRemaining <= 0)
                {
                    if (context.ShouldOfferTennisBreak)
                        EnterTimedState(CompanionStateKind.HoldingTennisBall, 22.0);
                    else
                        EnterTimedState(CompanionStateKind.PeekingRight, 18.0 + _rng.NextDouble() * 10.0);
                }
                break;
            }

            case CompanionStateKind.HoldingTennisBall:
                _stateRemaining -= dt;
                if (_stateRemaining <= 0)
                    EnterTimedState(PerchZone == PerchZone.WindowTop ? CompanionStateKind.Idle : CompanionStateKind.PeekingRight, 12.0);
                break;

            case CompanionStateKind.ChasingTreat:
            {
                double dx = _treatX - Position.X;
                if (Math.Abs(dx) < 14)
                {
                    _hasTreatProp = false;
                    _currentWalkSpeed = 0;
                    _lastEatBiteIndex = -1;
                    _squashSpring.Impulse(-1.6);
                    StateKind = CompanionStateKind.EatingTreat;
                    _stateElapsed = 0;
                    _stateDuration = 2.6;
                }
                else if (CurrentPlatform is { } top)
                {
                    double dir = dx > 0 ? 1.0 : -1.0;
                    _facingDirection = dir;
                    _currentWalkSpeed = 115.0;
                    double nx = top.ClampedX(Position.X + dir * 115.0 * dt, 18);
                    Position = new Vec2(nx, Position.Y);
                    _offsetFromWindowMinX = nx - top.WindowMinX;
                }
                else
                {
                    _hasTreatProp = false;
                    EnterTimedState(CompanionStateKind.Idle, 4.0);
                }
                break;
            }

            case CompanionStateKind.EatingTreat:
                _currentWalkSpeed = 0;
                _stateElapsed += dt;
                int biteIdx = (int)(_stateElapsed / 0.28);
                if (biteIdx != _lastEatBiteIndex)
                {
                    _lastEatBiteIndex = biteIdx;
                    _squashSpring.Impulse(0.95);
                    if (biteIdx % 2 == 1) SpawnSnackCrumbs(false);
                }
                if (_stateElapsed >= _stateDuration)
                {
                    _lastEatBiteIndex = -1;
                    _tapHopSpring.Impulse(75.0);
                    _squashSpring.Impulse(1.9);
                    SpawnSnackCrumbs(true);
                    EnterTimedState(CompanionStateKind.SitCalm, 11.0);
                }
                break;

            case CompanionStateKind.Walking:
            {
                if (PerchZone != PerchZone.WindowTop || CurrentPlatform is not { } top)
                {
                    EnterTimedState(CompanionStateKind.PeekingRight, 20.0);
                    return;
                }
                double desiredSpeed = (IsHoveringDog || IsPointerDownOnDog) ? 0.0 : 38.0;
                _currentWalkSpeed += (desiredSpeed - _currentWalkSpeed) * Math.Min(1.0, dt * 14.0);
                if (_currentWalkSpeed < 1.0 && (IsHoveringDog || IsPointerDownOnDog))
                {
                    _currentWalkSpeed = 0;
                    return;
                }
                _facingDirection = _walkDirection;
                double nextX = Position.X + _walkDirection * _currentWalkSpeed * dt;
                if (nextX <= top.MinX + 18 || nextX >= top.MaxX - 18)
                {
                    _walkDirection = -_walkDirection;
                    _facingDirection = _walkDirection;
                    nextX = top.ClampedX(nextX, 18);
                }
                Position = new Vec2(nextX, Position.Y);
                _offsetFromWindowMinX = nextX - top.WindowMinX;
                _stateRemaining -= dt;
                if (_stateRemaining <= 0)
                {
                    var (nextKind, nextDir, nextDur) = WestieBehaviorPlanner.ChooseNextTopBehavior(Position.X, top, context);
                    _walkDirection = nextDir;
                    EnterTimedState(nextKind, nextDur);
                }
                break;
            }

            case CompanionStateKind.Gliding:
            {
                switch (_glideTargetZone)
                {
                    case PerchZone.WindowTop when layout.TopPerch is { } top:
                        _glideTo = new Vec2(top.ClampedX(_glideTo.X, 18), top.Y);
                        break;
                    case PerchZone.WindowRightPeek when layout.WindowRightPeek is { } r:
                        _glideTo = new Vec2(r.EdgeX, r.ClampedY(_glideTo.Y));
                        break;
                    case PerchZone.ScreenRightPeek:
                        _glideTo = new Vec2(layout.ScreenRightPeek.EdgeX, layout.ScreenRightPeek.ClampedY(_glideTo.Y));
                        break;
                }
                _stateElapsed += dt;
                if (_stateElapsed >= _stateDuration)
                {
                    FinishGlideArrival(_glideTo, _glideTargetZone, layout);
                }
                else
                {
                    double u = _stateElapsed / Math.Max(_stateDuration, 0.01);
                    double eased = 1.0 - Math.Pow(1.0 - u, 3);
                    double dist = Vec2.Distance(_glideTo, _glideFrom);
                    double arcH = Math.Clamp(dist * 0.16, 18.0, 52.0);
                    double hop = Math.Sin(u * Math.PI) * arcH;
                    Position = new Vec2(
                        _glideFrom.X + (_glideTo.X - _glideFrom.X) * eased,
                        _glideFrom.Y + (_glideTo.Y - _glideFrom.Y) * eased + hop);
                }
                break;
            }

            case CompanionStateKind.Dragged:
                break;
        }
    }

    private void StepStealthTransition(double dt, ActiveWorkspaceSnapshot snapshot, Size2D sceneSize)
    {
        switch (StealthPhase)
        {
            case StealthPhaseKind.Retracting:
                if (snapshot.GetPerchLayoutForWindow(_stealthOriginWindowId) is { } originLayout)
                    FollowAnchorDuringStealth(_stealthOriginZone, originLayout);
                _stateElapsed += dt;
                if (_stateElapsed >= _stateDuration)
                {
                    StealthPhase = StealthPhaseKind.HiddenTraverse;
                    _stateElapsed = 0;
                    _stateDuration = 0.28;
                }
                break;

            case StealthPhaseKind.HiddenTraverse:
                _stateElapsed += dt;
                if (_stateElapsed >= _stateDuration)
                {
                    var destLayout = snapshot.GetPerchLayoutForWindow(_stealthDestWindowId) ?? snapshot.PerchLayout;
                    TrackedWindowId = _stealthDestWindowId != 0 ? _stealthDestWindowId : (destLayout.ActiveWindowId ?? TrackedWindowId);
                    switch (_stealthDestination.PerchZone)
                    {
                        case PerchZone.WindowTop when destLayout.TopPerch is { } top:
                            double clampedX = top.ClampedX(_stealthDestination.TargetX, 18);
                            PerchZone = PerchZone.WindowTop;
                            CurrentPlatform = top;
                            CurrentRightAnchor = null;
                            _offsetFromWindowMinX = clampedX - top.WindowMinX;
                            Position = new Vec2(clampedX, top.Y);
                            _stealthDestination = _stealthDestination with { TargetX = clampedX };
                            break;
                        case PerchZone.WindowRightPeek when destLayout.WindowRightPeek is { } right:
                            double cy = right.ClampedY(_stealthDestination.TargetY);
                            PerchZone = PerchZone.WindowRightPeek;
                            CurrentPlatform = null;
                            CurrentRightAnchor = right;
                            _offsetFromWindowMaxY = Math.Max(42, (destLayout.ActiveWindowFrame?.MaxY ?? right.MaxY) - cy);
                            Position = new Vec2(right.EdgeX, cy);
                            _stealthDestination = _stealthDestination with { TargetY = cy };
                            break;
                        default:
                            var anchor = destLayout.ScreenRightPeek;
                            double sy = anchor.ClampedY(_stealthDestination.TargetY);
                            PerchZone = PerchZone.ScreenRightPeek;
                            CurrentPlatform = null;
                            CurrentRightAnchor = anchor;
                            Position = new Vec2(anchor.EdgeX, sy);
                            _stealthDestination = new StealthDestination(PerchZone.ScreenRightPeek, TargetY: sy);
                            break;
                    }

                    bool useTwoStage = _stealthDestination.PerchZone != PerchZone.WindowTop || Preferences.ClimbPawsPeekEnabled;
                    if (useTwoStage)
                    {
                        StealthPhase = StealthPhaseKind.TentativePeek;
                        _stateElapsed = 0;
                        _stateDuration = _stealthDestination.PerchZone == PerchZone.WindowTop ? 3.0 : 0.56;
                    }
                    else
                    {
                        StealthPhase = StealthPhaseKind.SettlingOut;
                        _stateElapsed = 0;
                        _stateDuration = 0.60;
                    }
                }
                break;

            case StealthPhaseKind.TentativePeek:
                if (snapshot.GetPerchLayoutForWindow(_stealthDestWindowId) is { } dl)
                    FollowAnchorDuringStealth(_stealthDestination.PerchZone, dl);
                _stateElapsed += dt;
                if (_stateElapsed >= _stateDuration)
                {
                    StealthPhase = StealthPhaseKind.SettlingOut;
                    _stateElapsed = 0;
                    _stateDuration = _stealthDestination.PerchZone == PerchZone.WindowTop ? 0.72 : 0.44;
                }
                break;

            case StealthPhaseKind.SettlingOut:
                if (snapshot.GetPerchLayoutForWindow(_stealthDestWindowId) is { } dl2)
                    FollowAnchorDuringStealth(_stealthDestination.PerchZone, dl2);
                _stateElapsed += dt;
                if (_stateElapsed >= _stateDuration)
                    CompleteStealthArrival(snapshot, sceneSize);
                break;
        }
    }

    private void StepTopStory(double dt)
    {
        if (PerchZone != PerchZone.WindowTop || CurrentPlatform is not { } top)
        {
            EnterTimedState(CompanionStateKind.Yawning, 1.85);
            return;
        }

        switch (TopStoryStep)
        {
            case TopStoryStepKind.PostClimbPause:
                _currentWalkSpeed = 0;
                _facingDirection = -1.0;
                _stateElapsed += dt;
                if (_stateElapsed >= _stateDuration)
                {
                    double availLeft = Math.Max(0, Position.X - (top.MinX + 28));
                    double hopStep = Math.Clamp(availLeft / 3.5, 26.0, 44.0);
                    int hopCount = availLeft >= 26 ? Math.Clamp((int)Math.Round(availLeft / hopStep), 2, 4) : 0;
                    if (hopCount > 0)
                    {
                        TopStoryStep = TopStoryStepKind.HopLeft;
                        _hopsRemaining = hopCount;
                        _hopElapsed = 0;
                        _hopDuration = 0.56;
                        _hopRestElapsed = 0;
                        _hopStartX = Position.X;
                        _hopTargetX = Math.Max(top.MinX + 24, Position.X - hopStep);
                    }
                    else
                    {
                        TopStoryStep = TopStoryStepKind.LookAroundPause;
                        _stateElapsed = 0;
                        _stateDuration = 3.5;
                    }
                }
                break;

            case TopStoryStepKind.HopLeft:
                _facingDirection = -1.0;
                _currentWalkSpeed = 0;
                if (_hopElapsed < _hopDuration)
                {
                    _hopElapsed = Math.Min(_hopDuration, _hopElapsed + dt);
                    double u = _hopElapsed / Math.Max(_hopDuration, 0.01);
                    double airU = Math.Clamp((u - 0.18) / 0.68, 0, 1);
                    double eased = EaseOutCubic(airU);
                    double liveX = top.ClampedX(_hopStartX + (_hopTargetX - _hopStartX) * eased, 20);
                    Position = new Vec2(liveX, Position.Y);
                    _offsetFromWindowMinX = liveX - top.WindowMinX;
                    if (_hopElapsed >= _hopDuration) _squashSpring.Impulse(-1.4);
                }
                else
                {
                    if (IsHoveringDog || IsPointerDownOnDog) return;
                    _hopRestElapsed += dt;
                    if (_hopRestElapsed >= 0.14)
                    {
                        _hopsRemaining -= 1;
                        double availLeft = Position.X - (top.MinX + 26);
                        if (_hopsRemaining > 0 && availLeft >= 20)
                        {
                            double hopStep = Math.Min(44.0, availLeft);
                            _hopElapsed = 0;
                            _hopRestElapsed = 0;
                            _hopStartX = Position.X;
                            _hopTargetX = Math.Max(top.MinX + 24, Position.X - hopStep);
                        }
                        else
                        {
                            TopStoryStep = TopStoryStepKind.LookAroundPause;
                            _stateElapsed = 0;
                            _stateDuration = 3.5;
                        }
                    }
                }
                break;

            case TopStoryStepKind.LookAroundPause:
                _currentWalkSpeed = 0;
                _facingDirection = -1.0;
                _stateElapsed += dt;
                if (_stateElapsed >= _stateDuration)
                {
                    _facingDirection = 1.0;
                    double availRight = Math.Max(0, (top.MaxX - 28) - Position.X);
                    TopStoryStep = TopStoryStepKind.WalkRight;
                    _stateRemaining = Math.Clamp(Math.Min(availRight, 155.0) / 44.0, 1.6, 3.2);
                }
                break;

            case TopStoryStepKind.WalkRight:
                double desiredSpeed = (IsHoveringDog || IsPointerDownOnDog) ? 0.0 : 44.0;
                _currentWalkSpeed += (desiredSpeed - _currentWalkSpeed) * Math.Min(1.0, dt * 10.0);
                if (_currentWalkSpeed < 1.0 && (IsHoveringDog || IsPointerDownOnDog))
                {
                    _currentWalkSpeed = 0;
                    return;
                }
                _facingDirection = 1.0;
                double nx = Position.X + _currentWalkSpeed * dt;
                bool hitRight = false;
                if (nx >= top.MaxX - 24) { nx = top.MaxX - 24; hitRight = true; }
                Position = new Vec2(nx, Position.Y);
                _offsetFromWindowMinX = nx - top.WindowMinX;
                _stateRemaining -= dt;
                if (hitRight || _stateRemaining <= 0)
                {
                    TopStoryStep = TopStoryStepKind.PostWalkPause;
                    _stateElapsed = 0;
                    _stateDuration = 0.55;
                }
                break;

            case TopStoryStepKind.PostWalkPause:
                _currentWalkSpeed += (0 - _currentWalkSpeed) * Math.Min(1.0, dt * 14.0);
                if (_currentWalkSpeed < 0.8) _currentWalkSpeed = 0;
                _facingDirection = 1.0;
                _stateElapsed += dt;
                if (_stateElapsed >= _stateDuration)
                {
                    _currentWalkSpeed = 0;
                    TopStoryStep = TopStoryStepKind.SmileSit;
                    _stateElapsed = 0;
                    _stateDuration = 4.8;
                }
                break;

            case TopStoryStepKind.FlashStep:
                StepFlashStep(dt, top);
                break;

            case TopStoryStepKind.SmileSit:
                _currentWalkSpeed = 0;
                _facingDirection = 1.0;
                _stateElapsed += dt;
                if (_stateElapsed >= _stateDuration)
                {
                    TopStoryStep = TopStoryStepKind.PreYawnWait;
                    _stateElapsed = 0;
                    _stateDuration = 2.6;
                }
                break;

            case TopStoryStepKind.PreYawnWait:
                _currentWalkSpeed = 0;
                _facingDirection = 1.0;
                _stateElapsed += dt;
                if (_stateElapsed >= _stateDuration)
                    EnterTimedState(CompanionStateKind.Yawning, 1.85);
                break;
        }
    }

    private void StepFlashStep(double dt, WindowPlatform top)
    {
        _currentWalkSpeed = 0;
        _facingDirection = 1.0;
        double stepDist = Math.Min(52.0 * ScaleFactor, Math.Max(24.0, top.Width * 0.14));
        _stateElapsed += dt;

        switch (FlashStepBeat)
        {
            case FlashStepBeatKind.Stance:
                if (_stateElapsed >= _stateDuration)
                {
                    _flashStartX = Position.X;
                    _flashTargetX = Math.Min(top.MaxX - 24, Position.X + stepDist);
                    _squashSpring.Impulse(1.6);
                    FlashStepBeat = FlashStepBeatKind.DodgeRight;
                    _stateElapsed = 0;
                    _stateDuration = 0.48;
                }
                break;

            case FlashStepBeatKind.DodgeRight:
            {
                double dashU = Math.Min(1.0, _stateElapsed / Math.Max(_stateDuration * 0.48, 0.01));
                double x = top.ClampedX(_flashStartX + (_flashTargetX - _flashStartX) * EaseOutCubic(dashU), 22);
                Position = new Vec2(x, Position.Y);
                _offsetFromWindowMinX = x - top.WindowMinX;
                if (_stateElapsed >= _stateDuration)
                {
                    _squashSpring.Impulse(-1.4);
                    FlashStepBeat = FlashStepBeatKind.StopMid;
                    _stateElapsed = 0;
                    _stateDuration = 0.42;
                }
                break;
            }

            case FlashStepBeatKind.StopMid:
                if (_stateElapsed >= _stateDuration)
                {
                    FlashStepBeat = FlashStepBeatKind.ReadyLeft;
                    _stateElapsed = 0;
                    _stateDuration = 0.38;
                }
                break;

            case FlashStepBeatKind.ReadyLeft:
                if (_stateElapsed >= _stateDuration)
                {
                    _flashStartX = Position.X;
                    _flashTargetX = Math.Max(top.MinX + 24, Position.X - stepDist);
                    _squashSpring.Impulse(1.6);
                    FlashStepBeat = FlashStepBeatKind.DodgeLeft;
                    _stateElapsed = 0;
                    _stateDuration = 0.50;
                }
                break;

            case FlashStepBeatKind.DodgeLeft:
            {
                double dashU = Math.Min(1.0, _stateElapsed / Math.Max(_stateDuration * 0.48, 0.01));
                double x = top.ClampedX(_flashStartX + (_flashTargetX - _flashStartX) * EaseOutCubic(dashU), 22);
                Position = new Vec2(x, Position.Y);
                _offsetFromWindowMinX = x - top.WindowMinX;
                if (_stateElapsed >= _stateDuration)
                {
                    _squashSpring.Impulse(-1.4);
                    FlashStepBeat = FlashStepBeatKind.FinishStop;
                    _stateElapsed = 0;
                    _stateDuration = 0.46;
                }
                break;
            }

            case FlashStepBeatKind.FinishStop:
                if (_stateElapsed >= _stateDuration)
                {
                    _flashRoundsRemaining -= 1;
                    if (_flashRoundsRemaining > 0)
                    {
                        FlashStepBeat = FlashStepBeatKind.Stance;
                        _stateElapsed = 0;
                        _stateDuration = 0.38;
                    }
                    else
                    {
                        TopStoryStep = TopStoryStepKind.SmileSit;
                        _stateElapsed = 0;
                        _stateDuration = 4.2;
                    }
                }
                break;
        }
    }

    // MARK: - Visual Render Snapshot Synthesis

    private static double EaseInOutCubic(double u)
    {
        double t = Math.Clamp(u, 0, 1);
        return t < 0.5 ? 4 * t * t * t : 1 - Math.Pow(-2 * t + 2, 3) / 2;
    }

    private static double EaseOutCubic(double u)
    {
        double t = Math.Clamp(u, 0, 1);
        return 1 - Math.Pow(1 - t, 3);
    }

    private static double SmoothTiltPulse(double t, double center, double radius, double amplitude)
    {
        double dist = Math.Abs(t - center);
        if (dist >= radius) return 0;
        double u = 1.0 - dist / radius;
        return u * u * (3.0 - 2.0 * u) * amplitude;
    }

    private void ClearCrossfade()
    {
        _poseCrossfadeElapsed = 0;
        _poseCrossfadeDuration = 0;
        _fadeOutLayer = _fadeOutLayer with { IsVisible = false, Opacity = 0 };
    }

    private void ApplySpriteTransition(SpriteAssetKey nextKey, double fadeDuration)
    {
        var species = Preferences.PetSpecies;
        bool speciesChanged = _displayedSpriteSpecies != species;
        if (_displayedSpriteKey != nextKey || speciesChanged)
        {
            if (!speciesChanged && fadeDuration > 0.01 && _lastPrimaryLayer.IsVisible)
            {
                _fadeOutLayer = _lastPrimaryLayer with { IsVisible = true, Opacity = 1.0 };
                _poseCrossfadeElapsed = 0;
                _poseCrossfadeDuration = fadeDuration;
            }
            else
            {
                ClearCrossfade();
            }
            _displayedSpriteKey = nextKey;
            _displayedSpriteSpecies = species;
        }
    }

    private (double PrimaryAlpha, SpriteRenderLayer FadeLayer) StepCrossfade(double dt, Vec2 currentPos)
    {
        if (_poseCrossfadeDuration <= 0)
            return (1.0, _fadeOutLayer with { IsVisible = false, Opacity = 0 });

        _poseCrossfadeElapsed += dt;
        if (_poseCrossfadeElapsed >= _poseCrossfadeDuration)
        {
            ClearCrossfade();
            return (1.0, _fadeOutLayer);
        }
        double eased = EaseInOutCubic(_poseCrossfadeElapsed / _poseCrossfadeDuration);
        _fadeOutLayer = _fadeOutLayer with { IsVisible = true, AnchorPos = currentPos, Opacity = 1.0 - eased };
        return (eased, _fadeOutLayer);
    }

    private TreatRenderState BuildTreatRender()
    {
        if (!_hasTreatProp)
            return new TreatRenderState(false, SpriteAssetKey.BoneTreat, Preferences.PetSpecies, Vec2.Zero, 28 * ScaleFactor);

        double dim = 28.0 * ScaleFactor;
        double bounceOffset = 0;
        if (_treatDropElapsed < 0.14)
            bounceOffset = (1.0 - _treatDropElapsed / 0.14) * 18.0;
        else if (_treatDropElapsed < 0.30)
            bounceOffset = Math.Sin(((_treatDropElapsed - 0.14) / 0.16) * Math.PI) * 7.0;

        return new TreatRenderState(
            true,
            SpriteAssetKey.BoneTreat,
            Preferences.PetSpecies,
            new Vec2(_treatX, _treatBaseY + dim * 0.48 + bounceOffset),
            dim);
    }

    private void SyncVisuals(double dt)
    {
        var sp = Preferences.PetSpecies;
        double k = ScaleFactor;
        double s = Math.Clamp(_squashSpring.Value, -0.30, 0.30);
        double dirSign = _facingDirection >= 0 ? 1.0 : -1.0;
        var treat = BuildTreatRender();

        // 0a. Tucked early behind window
        if (StateKind == CompanionStateKind.TuckedWaiting)
        {
            ClearCrossfade();
            double u = _stateElapsed / Math.Max(_stateDuration, 0.01);
            if (u >= 0.99)
            {
                CommitRender(_lastPrimaryLayer with { IsVisible = false }, _fadeOutLayer, ClipMaskKind.None, 0, treat, new InviteBadgeRenderState(false, Vec2.Zero));
            }
            else
            {
                RenderMaskedRetractOrPeek(_stealthOriginZone, EaseInOutCubic(u), 0, _retractTopSpriteKey, _retractTopSpriteSize, 0, dt, treat);
            }
            return;
        }

        // 0b. 4-phase stealth transition
        if (StateKind == CompanionStateKind.StealthTransition)
        {
            double u = _stateElapsed / Math.Max(_stateDuration, 0.01);
            switch (StealthPhase)
            {
                case StealthPhaseKind.Retracting:
                    ClearCrossfade();
                    RenderMaskedRetractOrPeek(_stealthOriginZone, EaseInOutCubic(u), Math.Sin(u * Math.PI) * 0.025, _retractTopSpriteKey, _retractTopSpriteSize, 0, dt, treat);
                    return;

                case StealthPhaseKind.HiddenTraverse:
                    ClearCrossfade();
                    CommitRender(_lastPrimaryLayer with { IsVisible = false }, _fadeOutLayer, ClipMaskKind.None, 0, treat, new InviteBadgeRenderState(false, Vec2.Zero));
                    return;

                case StealthPhaseKind.TentativePeek:
                    if (_stealthDestination.PerchZone == PerchZone.WindowTop)
                    {
                        double retractFrac = _stateElapsed < 0.45 ? 1.0 - EaseOutCubic(_stateElapsed / 0.45) : 0.0;
                        SpriteAssetKey key;
                        double tilt;
                        if (_stateElapsed < 0.85) { key = SpriteAssetKey.WestieTopPeekCenter; tilt = 0; }
                        else if (_stateElapsed < 1.65) { key = SpriteAssetKey.WestieTopPeekLeft; tilt = SmoothTiltPulse(_stateElapsed, 1.25, 0.40, 0.055); }
                        else if (_stateElapsed < 1.95) { key = SpriteAssetKey.WestieTopPeekCenter; tilt = 0; }
                        else if (_stateElapsed < 2.75) { key = SpriteAssetKey.WestieTopPeekRight; tilt = -SmoothTiltPulse(_stateElapsed, 2.35, 0.40, 0.055); }
                        else { key = SpriteAssetKey.WestieTopPeekCenter; tilt = 0; }

                        double br = Math.Sin(_breathPhase * 0.9) * 0.015;
                        RenderMaskedRetractOrPeek(PerchZone.WindowTop, retractFrac, tilt, key, TopPeekDogSize, 0.16, dt, treat, 1.0 - br * 0.5, 1.0 + br);
                    }
                    else
                    {
                        ClearCrossfade();
                        double retract = u < 0.48 ? 1.0 - 0.52 * EaseOutCubic(u / 0.48) : 0.48;
                        double tilt = u < 0.48 ? 0 : SmoothTiltPulse((u - 0.48) / 0.52, 0.35, 0.32, 0.045) - SmoothTiltPulse((u - 0.48) / 0.52, 0.72, 0.28, 0.032);
                        RenderMaskedRetractOrPeek(_stealthDestination.PerchZone, retract, tilt, SpriteAssetKey.WestieTopPeekCenter, TopPeekDogSize, 0, dt, treat);
                    }
                    return;

                case StealthPhaseKind.SettlingOut:
                    if (_stealthDestination.PerchZone == PerchZone.WindowTop && Preferences.ClimbPawsPeekEnabled)
                    {
                        if (u < 0.18)
                        {
                            double dip = Math.Sin((u / 0.18) * Math.PI) * 0.08;
                            RenderMaskedRetractOrPeek(PerchZone.WindowTop, 0, 0, SpriteAssetKey.WestieTopPeekCenter, TopPeekDogSize, 0.12, dt, treat, 1.0 + dip * 0.5, 1.0 - dip);
                        }
                        else if (u < 0.68)
                        {
                            double climbU = (u - 0.18) / 0.50;
                            double retract = Math.Max(0, (1.0 - EaseOutCubic(climbU)) * 0.26);
                            double lift = Math.Sin(climbU * Math.PI) * 5.0;
                            RenderMaskedRetractOrPeek(PerchZone.WindowTop, retract, 0, SpriteAssetKey.WestieClimbUp, TopDogSize, 0.18, dt, treat, -1.0, 1.0, extraY: lift);
                        }
                        else
                        {
                            double landU = (u - 0.68) / 0.32;
                            double dip = Math.Sin(landU * Math.PI) * 0.06;
                            RenderMaskedRetractOrPeek(PerchZone.WindowTop, 0, 0, SpriteAssetKey.WestieIdle, TopDogSize, 0.20, dt, treat, -(1.0 + dip * 0.4), 1.0 - dip);
                        }
                    }
                    else
                    {
                        double retract = _stealthDestination.PerchZone == PerchZone.WindowTop
                            ? 1.0 - EaseOutCubic(u)
                            : 0.48 * (1.0 - EaseOutCubic(u));
                        RenderMaskedRetractOrPeek(_stealthDestination.PerchZone, retract, 0, SpriteAssetKey.WestieIdle, TopDogSize, 0, dt, treat);
                    }
                    return;
            }
        }

        // 1. Dragged
        if (StateKind == CompanionStateKind.Dragged)
        {
            ClearCrossfade();
            ApplySpriteTransition(SpriteAssetKey.WestieDangling, 0);
            var layer = new SpriteRenderLayer(
                true, SpriteAssetKey.WestieDangling, sp, Position, new Vec2(0.5, 0.04), TopDogSize,
                dirSign * (1.0 - s * 0.28), 1.0 + s * 0.32,
                _swingRotationSpring.Value + Math.Sin(_breathPhase * 2.2) * 0.035, 1.0);
            CommitRender(layer, _fadeOutLayer, ClipMaskKind.None, 0, treat, new InviteBadgeRenderState(false, Vec2.Zero));
            return;
        }

        // 2. Gliding
        if (StateKind == CompanionStateKind.Gliding)
        {
            ClearCrossfade();
            _walkAnimTimer += dt;
            if (_walkAnimTimer >= 0.08)
            {
                _walkAnimTimer = 0;
                _walkFrameIndex = (_walkFrameIndex + 1) % WalkCycleFrames.Length;
            }
            var wk = WalkCycleFrames[_walkFrameIndex];
            ApplySpriteTransition(wk, 0);
            double u = _stateElapsed / Math.Max(_stateDuration, 0.01);
            var layer = new SpriteRenderLayer(
                true, wk, sp, Position, new Vec2(0.5, 0.04), TopDogSize,
                dirSign * (1.0 - s * 0.30), 1.0 + s * 0.34,
                Math.Cos(u * Math.PI) * 0.16 * dirSign, 1.0);
            CommitRender(layer, _fadeOutLayer, ClipMaskKind.None, 0, treat, new InviteBadgeRenderState(false, Vec2.Zero));
            return;
        }

        // 3. Right-Edge Peeking Modes
        if (PerchZone is PerchZone.ScreenRightPeek or PerchZone.WindowRightPeek)
        {
            ClearCrossfade();
            double hoverSlide = Math.Clamp(_peekHoverSpring.Value, -0.40, 1.25);
            double emergeTuck = Math.Max(0, -_peekEmergeSpring.Value) * 34.0 - Math.Clamp(_peekEmergeSpring.Value, 0, 0.22) * 7.0;
            var key = _isPeekHoverTextureActive ? SpriteAssetKey.WestiePeekHover : SpriteAssetKey.WestiePeekCalm;
            ApplySpriteTransition(key, 0);

            double stretchMag = 1.0 + s * 0.22;
            double squashPerp = 1.0 - s * 0.18;
            double subtleTilt = _peekHoverSpring.Value > 0.04
                ? Math.Sin(_hoverWavePhase * 5.2) * 0.036 * Math.Clamp(hoverSlide, 0, 1.0)
                : 0.0;

            bool showInvite = StateKind == CompanionStateKind.HoldingTennisBall;
            if (PerchZone == PerchZone.ScreenRightPeek)
            {
                double tuck = Math.Max(5.5 * k, (5.5 + 9.0 * (1.0 - hoverSlide)) * k + emergeTuck * k);
                var layer = new SpriteRenderLayer(
                    true, key, sp, new Vec2(Position.X + tuck, Position.Y), new Vec2(1.0, 0.5), PeekDogSize,
                    stretchMag, squashPerp, subtleTilt, 1.0);
                CommitRender(layer, _fadeOutLayer, ClipMaskKind.None, 0, treat,
                    new InviteBadgeRenderState(showInvite, new Vec2(Position.X - 68 * k, Position.Y + 46 * k)));
            }
            else
            {
                double tuck = Math.Max(5.5 * k, (5.5 + 9.0 * (1.0 - hoverSlide)) * k + emergeTuck * k);
                var layer = new SpriteRenderLayer(
                    true, key, sp, new Vec2(Position.X - tuck, Position.Y), new Vec2(1.0, 0.5), PeekDogSize,
                    -stretchMag, squashPerp, -subtleTilt + _swingRotationSpring.Value * 0.4, 1.0);
                CommitRender(layer, _fadeOutLayer, ClipMaskKind.RightOfX, Position.X - 0.5, treat,
                    new InviteBadgeRenderState(showInvite, new Vec2(Position.X + 64 * k, Position.Y + 46 * k)));
            }
            return;
        }

        // 4. Active Window Top-Edge Mode
        double bobY = Math.Max(0, _tapHopSpring.Value);
        double strideTilt = 0;
        double breathYScale = 1.0;
        double breathXScale = 1.0;
        SpriteAssetKey desiredKey;
        Size2D desiredSize = TopDogSize;
        double fadeDur = 0.24;

        if (StateKind == CompanionStateKind.Walking && _currentWalkSpeed < 5.0)
        {
            desiredKey = SpriteAssetKey.WestieIdle;
        }
        else
        {
            switch (StateKind)
            {
                case CompanionStateKind.TopStory:
                    desiredKey = ComputeTopStoryVisual(dt, ref bobY, ref strideTilt, ref breathXScale, ref breathYScale, ref fadeDur);
                    break;

                case CompanionStateKind.Yawning:
                {
                    desiredKey = SpriteAssetKey.WestieYawn;
                    desiredSize = YawnDogSize;
                    fadeDur = 0.26;
                    double u = _stateElapsed / Math.Max(_stateDuration, 0.01);
                    double stretch = SmoothTiltPulse(u, 0.46, 0.44, 0.045) - SmoothTiltPulse(u, 0.88, 0.18, 0.040);
                    breathYScale = 1.0 + stretch;
                    breathXScale = 1.0 - stretch * 0.45;
                    break;
                }

                case CompanionStateKind.SettlingToSleep:
                {
                    if (_stateElapsed < _stateDuration * 0.48) { desiredKey = SpriteAssetKey.WestieLoafCalm; fadeDur = 0.30; }
                    else { desiredKey = SpriteAssetKey.WestieDrowsy; fadeDur = 0.38; }
                    double br = Math.Sin(_breathPhase * 0.65) * 0.016;
                    breathYScale = 1.0 + br;
                    breathXScale = 1.0 - br * 0.5;
                    break;
                }

                case CompanionStateKind.GreetingOnTop:
                {
                    double windDown = Math.Min(3.5, _greetingTotalDuration * 0.38);
                    if (_stateRemaining > windDown)
                    {
                        desiredKey = SpriteAssetKey.WestieSitTilt;
                        fadeDur = 0.26;
                        strideTilt = SmoothTiltPulse(_greetingPhase, 1.4, 0.9, 0.070) - SmoothTiltPulse(_greetingPhase, 4.1, 0.95, 0.055);
                        double br = Math.Sin(_breathPhase * 0.95) * 0.017;
                        breathYScale = 1.0 + br;
                        breathXScale = 1.0 - br * 0.5;
                    }
                    else
                    {
                        desiredKey = SpriteAssetKey.WestieLoafCalm;
                        fadeDur = 0.32;
                        double br = Math.Sin(_breathPhase * 0.72) * 0.015;
                        breathYScale = 1.0 + br;
                        breathXScale = 1.0 - br * 0.5;
                    }
                    break;
                }

                case CompanionStateKind.SitCalm:
                {
                    desiredKey = SpriteAssetKey.WestieSitTilt;
                    double br = Math.Sin(_breathPhase * 0.85) * 0.014;
                    breathYScale = 1.0 + br;
                    breathXScale = 1.0 - br * 0.5;
                    break;
                }

                case CompanionStateKind.Loafing:
                {
                    desiredKey = SpriteAssetKey.WestieLoafCalm;
                    fadeDur = _displayedSpriteKey == SpriteAssetKey.WestieSleep ? 0.36 : 0.26;
                    double br = Math.Sin(_breathPhase * 0.72) * 0.015;
                    breathYScale = 1.0 + br;
                    breathXScale = 1.0 - br * 0.5;
                    break;
                }

                case CompanionStateKind.ChinRest:
                {
                    desiredKey = SpriteAssetKey.WestieChinLedge;
                    desiredSize = ChinLedgeDogSize;
                    double br = Math.Sin(_breathPhase * 0.75) * 0.014;
                    breathYScale = 1.0 + br;
                    breathXScale = 1.0 - br * 0.5;
                    break;
                }

                case CompanionStateKind.Sleeping:
                {
                    desiredKey = SpriteAssetKey.WestieSleep;
                    fadeDur = _displayedSpriteKey is SpriteAssetKey.WestieDrowsy or SpriteAssetKey.WestieLoafCalm ? 0.44 : 0.32;
                    double br = Math.Sin(_breathPhase * 0.52) * 0.018;
                    breathYScale = 1.0 + br;
                    breathXScale = 1.0 - br * 0.5;
                    break;
                }

                case CompanionStateKind.HoldingTennisBall:
                {
                    desiredKey = SpriteAssetKey.WestieHoldingBall;
                    double br = Math.Sin(_breathPhase * 1.1) * 0.016;
                    breathYScale = 1.0 + br;
                    breathXScale = 1.0 - br * 0.5;
                    break;
                }

                case CompanionStateKind.EatingTreat:
                {
                    int chewIdx = (int)(_stateElapsed / 0.28) % 2;
                    desiredKey = chewIdx == 0 ? SpriteAssetKey.WestieEat1 : SpriteAssetKey.WestieEat2;
                    fadeDur = 0.05;
                    double chewPhase = (_stateElapsed / 0.28) % 1.0;
                    double munch = Math.Sin(chewPhase * Math.PI) * 0.055;
                    breathYScale = 1.0 - munch;
                    breathXScale = 1.0 + munch * 0.45;
                    strideTilt = chewIdx == 0 ? -0.035 : 0.030;
                    break;
                }

                case CompanionStateKind.Walking:
                case CompanionStateKind.ChasingTreat:
                {
                    double ratio = StateKind == CompanionStateKind.ChasingTreat ? 1.8 : Math.Max(0.35, _currentWalkSpeed / 44.0);
                    _walkAnimTimer += dt * ratio;
                    if (_walkAnimTimer >= 0.125)
                    {
                        _walkAnimTimer = 0;
                        _walkFrameIndex = (_walkFrameIndex + 1) % WalkCycleFrames.Length;
                    }
                    desiredKey = WalkCycleFrames[_walkFrameIndex];
                    fadeDur = 0;
                    bool passing = _walkFrameIndex is 1 or 3;
                    double speedFactor = Math.Min(1.0, _currentWalkSpeed / 44.0);
                    bobY += (passing ? 1.6 : 0.0) * speedFactor;
                    strideTilt = Math.Sin(_breathPhase * 2.6) * 0.020 * speedFactor;
                    break;
                }

                default:
                {
                    desiredKey = SpriteAssetKey.WestieIdle;
                    double br = Math.Sin(_breathPhase * 0.85) * 0.013;
                    breathYScale = 1.0 + br;
                    breathXScale = 1.0 - br * 0.5;
                    break;
                }
            }
        }

        if (StateKind is not (CompanionStateKind.Walking or CompanionStateKind.ChasingTreat) &&
            !(StateKind == CompanionStateKind.TopStory && TopStoryStep == TopStoryStepKind.WalkRight))
        {
            _currentWalkSpeed = 0;
        }

        ApplySpriteTransition(desiredKey, fadeDur);

        bool unmirrored = desiredKey is SpriteAssetKey.WestieLookLeftHeadLeft
            or SpriteAssetKey.WestieLookLeftHeadCenter
            or SpriteAssetKey.WestieLookLeftHeadRight
            or SpriteAssetKey.WestieFlashStep1
            or SpriteAssetKey.WestieFlashStep2
            or SpriteAssetKey.WestieFlashStep3
            or SpriteAssetKey.WestieFlashStep4
            or SpriteAssetKey.WestieFlashStep5;
        double effectiveDir = unmirrored ? 1.0 : dirSign;

        var finalPos = new Vec2(Position.X, Position.Y + bobY);
        var (alpha, fadeLayer) = StepCrossfade(dt, finalPos);
        var primary = new SpriteRenderLayer(
            true, desiredKey, sp, finalPos, new Vec2(0.5, 0.04), desiredSize,
            effectiveDir * (1.0 - s * 0.30) * breathXScale,
            (1.0 + s * 0.34) * breathYScale,
            _swingRotationSpring.Value + strideTilt,
            alpha);

        bool showTopInvite = StateKind == CompanionStateKind.HoldingTennisBall;
        CommitRender(primary, fadeLayer, ClipMaskKind.None, 0, treat,
            new InviteBadgeRenderState(showTopInvite, new Vec2(Position.X, Position.Y + 80 * k)));
    }

    private SpriteAssetKey ComputeTopStoryVisual(
        double dt,
        ref double bobY,
        ref double strideTilt,
        ref double breathXScale,
        ref double breathYScale,
        ref double fadeDur)
    {
        switch (TopStoryStep)
        {
            case TopStoryStepKind.PostClimbPause:
            case TopStoryStepKind.PostWalkPause:
            {
                fadeDur = 0.18;
                double br = Math.Sin(_breathPhase * 0.9) * 0.014;
                breathYScale = 1.0 + br;
                breathXScale = 1.0 - br * 0.5;
                return SpriteAssetKey.WestieIdle;
            }

            case TopStoryStepKind.HopLeft:
                if (_hopElapsed < _hopDuration)
                {
                    double u = _hopElapsed / Math.Max(_hopDuration, 0.01);
                    if (u < 0.18)
                    {
                        fadeDur = 0.06;
                        double dip = Math.Sin((u / 0.18) * Math.PI) * 0.06;
                        breathYScale = 1.0 - dip;
                        breathXScale = 1.0 + dip * 0.45;
                        return SpriteAssetKey.WestieHopCrouch;
                    }
                    if (u < 0.76)
                    {
                        double airU = (u - 0.18) / 0.58;
                        bobY += Math.Sin(airU * Math.PI) * 13.0;
                        fadeDur = 0.05;
                        strideTilt = Math.Cos(airU * Math.PI) * -0.07;
                        double stretch = Math.Sin(airU * Math.PI) * 0.05;
                        breathYScale = 1.0 + stretch;
                        breathXScale = 1.0 - stretch * 0.35;
                        return SpriteAssetKey.WestieHopAir;
                    }
                    double landU = (u - 0.76) / 0.24;
                    fadeDur = 0.06;
                    double cushion = Math.Sin(landU * Math.PI) * 0.05;
                    breathYScale = 1.0 - cushion;
                    breathXScale = 1.0 + cushion * 0.4;
                    return SpriteAssetKey.WestieHopLand;
                }
                fadeDur = 0.08;
                return SpriteAssetKey.WestieHopCrouch;

            case TopStoryStepKind.LookAroundPause:
            {
                fadeDur = 0.14;
                double br = Math.Sin(_breathPhase * 0.9) * 0.014;
                breathYScale = 1.0 + br;
                breathXScale = 1.0 - br * 0.5;
                if (_stateElapsed < 0.35) return SpriteAssetKey.WestieLookLeftHeadLeft;
                if (_stateElapsed < 0.50) return SpriteAssetKey.WestieLookLeftHeadCenter;
                if (_stateElapsed < 1.35) return SpriteAssetKey.WestieLookLeftHeadRight;
                if (_stateElapsed < 1.50) return SpriteAssetKey.WestieLookLeftHeadCenter;
                if (_stateElapsed < 2.35) return SpriteAssetKey.WestieLookLeftHeadLeft;
                if (_stateElapsed < 2.50) return SpriteAssetKey.WestieLookLeftHeadCenter;
                return SpriteAssetKey.WestieLookLeftHeadRight;
            }

            case TopStoryStepKind.WalkRight:
                if (_currentWalkSpeed < 5.0)
                {
                    fadeDur = 0.16;
                    return SpriteAssetKey.WestieIdle;
                }
                _walkAnimTimer += dt * Math.Max(0.35, _currentWalkSpeed / 44.0);
                if (_walkAnimTimer >= 0.125)
                {
                    _walkAnimTimer = 0;
                    _walkFrameIndex = (_walkFrameIndex + 1) % WalkCycleFrames.Length;
                }
                fadeDur = 0;
                bool passing = _walkFrameIndex is 1 or 3;
                double speedFactor = Math.Min(1.0, _currentWalkSpeed / 44.0);
                bobY += (passing ? 1.6 : 0.0) * speedFactor;
                strideTilt = Math.Sin(_breathPhase * 2.6) * 0.020 * speedFactor;
                return WalkCycleFrames[_walkFrameIndex];

            case TopStoryStepKind.FlashStep:
            {
                fadeDur = 0.07;
                switch (FlashStepBeat)
                {
                    case FlashStepBeatKind.Stance:
                    {
                        double u = _stateElapsed / Math.Max(_stateDuration, 0.01);
                        double coil = SmoothTiltPulse(u, 0.72, 0.30, 0.06);
                        breathYScale = 1.0 - coil;
                        breathXScale = 1.0 + coil * 0.45;
                        return SpriteAssetKey.WestieFlashStep1;
                    }
                    case FlashStepBeatKind.DodgeRight:
                    {
                        double dashU = Math.Min(1.0, _stateElapsed / Math.Max(_stateDuration * 0.48, 0.01));
                        bobY += Math.Sin(dashU * Math.PI) * 6.5 * ScaleFactor;
                        strideTilt = -Math.Sin(dashU * Math.PI) * 0.08;
                        return SpriteAssetKey.WestieFlashStep2;
                    }
                    case FlashStepBeatKind.StopMid:
                    case FlashStepBeatKind.FinishStop:
                    {
                        double u = _stateElapsed / Math.Max(_stateDuration, 0.01);
                        double snap = SmoothTiltPulse(u, 0.22, 0.22, 0.05);
                        breathYScale = 1.0 + snap;
                        breathXScale = 1.0 - snap * 0.35;
                        return SpriteAssetKey.WestieFlashStep3;
                    }
                    case FlashStepBeatKind.ReadyLeft:
                    {
                        double u = _stateElapsed / Math.Max(_stateDuration, 0.01);
                        double coil = SmoothTiltPulse(u, 0.72, 0.30, 0.06);
                        breathYScale = 1.0 - coil;
                        breathXScale = 1.0 + coil * 0.45;
                        return SpriteAssetKey.WestieFlashStep4;
                    }
                    case FlashStepBeatKind.DodgeLeft:
                    default:
                    {
                        double dashU = Math.Min(1.0, _stateElapsed / Math.Max(_stateDuration * 0.48, 0.01));
                        bobY += Math.Sin(dashU * Math.PI) * 6.5 * ScaleFactor;
                        strideTilt = Math.Sin(dashU * Math.PI) * 0.08;
                        return SpriteAssetKey.WestieFlashStep5;
                    }
                }
            }

            case TopStoryStepKind.SmileSit:
            {
                fadeDur = 0.26;
                strideTilt = SmoothTiltPulse(_stateElapsed, 1.15, 0.48, 0.115)
                    - SmoothTiltPulse(_stateElapsed, 2.65, 0.48, 0.115)
                    + SmoothTiltPulse(_stateElapsed, 3.85, 0.38, 0.070);
                double br = Math.Sin(_breathPhase * 0.85) * 0.016;
                breathYScale = 1.0 + br;
                breathXScale = 1.0 - br * 0.5;
                return SpriteAssetKey.WestieSitTilt;
            }

            case TopStoryStepKind.PreYawnWait:
            default:
            {
                fadeDur = 0.24;
                double br = Math.Sin(_breathPhase * 0.65) * 0.015;
                breathYScale = 1.0 + br;
                breathXScale = 1.0 - br * 0.5;
                return SpriteAssetKey.WestieSitTilt;
            }
        }
    }

    private void RenderMaskedRetractOrPeek(
        PerchZone zone,
        double retractFraction,
        double curiousTilt,
        SpriteAssetKey topKey,
        Size2D topSize,
        double fadeDur,
        double dt,
        TreatRenderState treat,
        double? customScaleX = null,
        double? customScaleY = null,
        double extraY = 0)
    {
        double f = Math.Clamp(retractFraction, 0, 1);
        double k = ScaleFactor;
        var sp = Preferences.PetSpecies;

        switch (zone)
        {
            case PerchZone.WindowRightPeek:
            {
                ClearCrossfade();
                ApplySpriteTransition(SpriteAssetKey.WestiePeekCalm, 0);
                double tuck = (14.5 + f * 64.0) * k;
                var layer = new SpriteRenderLayer(
                    true, SpriteAssetKey.WestiePeekCalm, sp,
                    new Vec2(Position.X - tuck, Position.Y), new Vec2(1.0, 0.5), PeekDogSize,
                    -1.0, 1.0, curiousTilt, 1.0);
                CommitRender(layer, _fadeOutLayer, ClipMaskKind.RightOfX, Position.X - 0.5, treat, new InviteBadgeRenderState(false, Vec2.Zero));
                break;
            }
            case PerchZone.ScreenRightPeek:
            {
                ClearCrossfade();
                ApplySpriteTransition(SpriteAssetKey.WestiePeekCalm, 0);
                double tuck = (14.5 + f * 66.0) * k;
                var layer = new SpriteRenderLayer(
                    true, SpriteAssetKey.WestiePeekCalm, sp,
                    new Vec2(Position.X + tuck, Position.Y), new Vec2(1.0, 0.5), PeekDogSize,
                    1.0, 1.0, curiousTilt, 1.0);
                CommitRender(layer, _fadeOutLayer, ClipMaskKind.None, 0, treat, new InviteBadgeRenderState(false, Vec2.Zero));
                break;
            }
            case PerchZone.WindowTop:
            {
                ApplySpriteTransition(topKey, fadeDur);
                double sinkY = f * (topSize.Height + 4.0);
                bool directionalPeek = topKey is SpriteAssetKey.WestieTopPeekCenter or SpriteAssetKey.WestieTopPeekLeft or SpriteAssetKey.WestieTopPeekRight;
                double sx = customScaleX ?? (directionalPeek ? 1.0 : (_facingDirection >= 0 ? 1.0 : -1.0));
                double sy = customScaleY ?? 1.0;
                var pos = new Vec2(Position.X, Position.Y - sinkY + extraY);
                var (alpha, fadeLayer) = StepCrossfade(dt, pos);
                var layer = new SpriteRenderLayer(
                    true, topKey, sp, pos, new Vec2(0.5, 0.04), topSize,
                    sx, sy, curiousTilt, alpha);
                CommitRender(layer, fadeLayer, ClipMaskKind.AboveY, Position.Y, treat, new InviteBadgeRenderState(false, Vec2.Zero));
                break;
            }
        }
    }

    private void CommitRender(
        SpriteRenderLayer primary,
        SpriteRenderLayer fadeOut,
        ClipMaskKind clipKind,
        double clipEdge,
        TreatRenderState treat,
        InviteBadgeRenderState badge)
    {
        _lastPrimaryLayer = primary;
        LatestRender = new CompanionRenderSnapshot(primary, fadeOut, clipKind, clipEdge, treat, badge, _particles);
    }
}
