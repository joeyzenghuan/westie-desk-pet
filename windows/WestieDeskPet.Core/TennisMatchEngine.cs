using System;
using System.Collections.Generic;

namespace WestieDeskPet.Core;

public enum TennisKey
{
    W, A, S, D,
    Up, Left, Down, Right,
    Space, R, Escape,
    Minus, Equal, LeftBracket, RightBracket
}

public sealed class TennisPopEffect
{
    public string Text { get; }
    public Vec2 Position { get; set; }
    public string ColorHex { get; }
    public double Elapsed { get; set; }
    public double Duration { get; }

    public TennisPopEffect(string text, Vec2 position, string colorHex, double duration = 0.55)
    {
        Text = text;
        Position = position;
        ColorHex = colorHex;
        Duration = duration;
    }
}

public sealed class TennisBounceMark
{
    public Vec2 Position { get; }
    public double Elapsed { get; set; }
    public double Duration { get; } = 0.35;

    public TennisBounceMark(Vec2 position) => Position = position;
}

public sealed class TennisMatchEngine
{
    private readonly CompanionPreferences _preferences;
    private readonly Random _rng = new();

    public bool IsActive { get; private set; }
    public int TargetPointsToWin => 5;
    public int PlayerScore { get; private set; }
    public int OpponentScore { get; private set; }
    public int RallyHits { get; private set; }
    public CourtSide Server { get; private set; } = CourtSide.Player;
    public bool IsAwaitingServe { get; private set; } = true;
    public bool IsMatchOver { get; private set; }

    public Vec2 PlayerPos { get; private set; } = new(0, -205);
    public Vec2 AimCourtPoint { get; private set; } = new(40, 165);
    public bool IsChargingLeftClick { get; private set; }
    public double CurrentChargeRatio { get; private set; }

    public WestieOpponentState Opponent => _opponent;
    public TennisBallState Ball => _ball;
    public string BannerText { get; private set; } = "";
    public IReadOnlyList<TennisPopEffect> PopEffects => _popEffects;
    public IReadOnlyList<TennisBounceMark> BounceMarks => _bounceMarks;

    public event Action? RequestExitTennis;

    private WestieOpponentState _opponent = WestieOpponentState.CreateDefault();
    private TennisBallState _ball = new();
    private readonly HashSet<TennisKey> _heldKeys = [];
    private readonly Dictionary<TennisKey, double> _lastKeyDownTime = [];
    private readonly List<TennisPopEffect> _popEffects = [];
    private readonly List<TennisBounceMark> _bounceMarks = [];

    private double _clock;
    private double _pointPauseTimer;
    private double _dashTimer;
    private Vec2 _dashDirection = Vec2.Zero;
    private double _dashCooldown;
    private double _playerSwingVisualTimer;
    private double _runAnimTimer;
    private bool _runFrameToggle;
    private double _chargeStartTime;

    public TennisDifficulty Difficulty
    {
        get => _preferences.TennisDifficulty;
        set => _preferences.TennisDifficulty = value;
    }

    public TennisGameSpeed GameSpeed
    {
        get => _preferences.TennisSpeed;
        set => _preferences.TennisSpeed = value;
    }

    public PetSpecies Species => _preferences.PetSpecies;

    public string ScoreboardText
    {
        get
        {
            string petText = Species switch
            {
                PetSpecies.GoldenCat => "金渐层 🐱",
                PetSpecies.Chinchilla => "金吉拉 🐈",
                PetSpecies.Labrador => "拉布拉多 🐕",
                _ => "西高地 🐶"
            };
            return $"🧑 你  {PlayerScore}  :  {OpponentScore}  {petText}   |   回合 {RallyHits}";
        }
    }

    public string DifficultyPillText => $"🐾 难度: {Difficulty.DisplayName(Species)}";
    public string SpeedPillText => $"球速: {GameSpeed.DisplayName()}";

    public SpriteAssetKey CurrentPlayerSprite =>
        _playerSwingVisualTimer > 0
            ? SpriteAssetKey.PlayerSwing
            : (_runFrameToggle ? SpriteAssetKey.PlayerRun : SpriteAssetKey.PlayerReady);

    public (SpriteAssetKey Key, double FacingX) CurrentOpponentVisual
    {
        get
        {
            if (_opponent.CelebrateTimer > 0 || (IsMatchOver && OpponentScore > PlayerScore))
                return (SpriteAssetKey.WestieVictory, 1.0);
            if (_opponent.DiveTimer > 0)
                return (SpriteAssetKey.WestieTennisDive, _opponent.FacingDirection < 0 ? -1.0 : 1.0);
            if (_opponent.SwingCooldown > 0.20)
                return (SpriteAssetKey.WestieTennisSwing, 1.0);
            if (!IsAwaitingServe && _ball.LastHitter == CourtSide.Player && Math.Abs(_opponent.LastStepDx) > 0.4)
                return (SpriteAssetKey.WestieTennisRun, _opponent.FacingDirection < 0 ? -1.0 : 1.0);
            return (SpriteAssetKey.WestieTennisReady, 1.0);
        }
    }

    public TennisMatchEngine(CompanionPreferences? preferences = null)
    {
        _preferences = preferences ?? CompanionPreferences.Shared;
    }

    public void StartMatch()
    {
        IsActive = true;
        PlayerScore = 0;
        OpponentScore = 0;
        Server = CourtSide.Player;
        IsMatchOver = false;
        _heldKeys.Clear();
        _popEffects.Clear();
        _bounceMarks.Clear();
        IsChargingLeftClick = false;
        CurrentChargeRatio = 0;
        ResetForNextPoint("🎾 抢 5 分对决开始！点击左键或按空格发球");
    }

    public void StopMatch()
    {
        IsActive = false;
        _heldKeys.Clear();
        IsChargingLeftClick = false;
    }

    private void ResetForNextPoint(string announcement)
    {
        IsAwaitingServe = true;
        RallyHits = 0;
        IsChargingLeftClick = false;
        CurrentChargeRatio = 0;

        PlayerPos = new Vec2((Server == CourtSide.Player) ? 48 : -48, -212);
        _opponent = WestieOpponentState.CreateDefault();
        _opponent.X = (Server == CourtSide.Westie) ? -48 : 48;
        _opponent.Y = 205;

        if (Server == CourtSide.Player)
        {
            _ball = new TennisBallState(PlayerPos.X + 14, PlayerPos.Y + 12, 22, lastHitter: CourtSide.Player);
        }
        else
        {
            _ball = new TennisBallState(_opponent.X, _opponent.Y - 12, 22, lastHitter: CourtSide.Westie);
            _pointPauseTimer = 0.85;
        }

        BannerText = announcement;
    }

    public void HandleKeyDown(TennisKey key, bool isRepeat = false)
    {
        if (!IsActive) return;

        if (key == TennisKey.Escape)
        {
            RequestExitTennis?.Invoke();
            return;
        }
        if (key == TennisKey.R)
        {
            StartMatch();
            return;
        }
        if (key is TennisKey.Minus or TennisKey.LeftBracket)
        {
            GameSpeed = GameSpeed.Slower();
            SpawnPop($"球速: {GameSpeed.DisplayName()}", new Vec2(0, 95), "#66FFFF");
            return;
        }
        if (key is TennisKey.Equal or TennisKey.RightBracket)
        {
            GameSpeed = GameSpeed.Faster();
            SpawnPop($"球速: {GameSpeed.DisplayName()}", new Vec2(0, 95), "#66FFFF");
            return;
        }
        if (key == TennisKey.Space)
        {
            if (IsMatchOver) { StartMatch(); return; }
            if (IsAwaitingServe && Server == CourtSide.Player)
            {
                PerformPlayerServe(0.35);
                return;
            }
            TriggerDashFromHeldKeys();
            return;
        }

        if (!isRepeat && key is TennisKey.W or TennisKey.A or TennisKey.S or TennisKey.D)
        {
            if (_lastKeyDownTime.TryGetValue(key, out double prev) && (_clock - prev) < 0.26 && _dashCooldown <= 0)
            {
                _heldKeys.Add(key);
                TriggerDashFromHeldKeys();
                _lastKeyDownTime[key] = -10;
                return;
            }
            _lastKeyDownTime[key] = _clock;
        }

        _heldKeys.Add(key);
    }

    public void HandleKeyUp(TennisKey key) => _heldKeys.Remove(key);

    public void ToggleDifficulty() =>
        Difficulty = (Difficulty == TennisDifficulty.Casual) ? TennisDifficulty.Pro : TennisDifficulty.Casual;

    public void CycleSpeed()
    {
        GameSpeed = GameSpeed.Next();
        SpawnPop($"球速切换: {GameSpeed.DisplayName()}", new Vec2(0, 95), "#66FFFF");
    }

    public void HandleMouseMoved(Vec2 courtLocalPoint)
    {
        double clampedX = Math.Clamp(courtLocalPoint.X, -TennisCourtMetrics.HalfWidth + 6, TennisCourtMetrics.HalfWidth - 6);
        double clampedY = Math.Clamp(courtLocalPoint.Y, 34, TennisCourtMetrics.HalfLength - 8);
        AimCourtPoint = new Vec2(clampedX, clampedY);
    }

    public void HandleLeftMouseDown(Vec2 courtLocalPoint)
    {
        if (!IsActive) return;
        if (IsMatchOver) { StartMatch(); return; }

        HandleMouseMoved(courtLocalPoint);

        if (IsAwaitingServe && Server == CourtSide.Player)
        {
            IsChargingLeftClick = true;
            _chargeStartTime = _clock;
            return;
        }

        if (CanPlayerStrikeBallNow())
        {
            ExecutePlayerHit(TennisShotKind.FlatDrive, 0.25);
        }
        else
        {
            IsChargingLeftClick = true;
            _chargeStartTime = _clock;
        }
    }

    public void HandleLeftMouseUp(Vec2 courtLocalPoint)
    {
        if (!IsActive) return;
        HandleMouseMoved(courtLocalPoint);
        if (!IsChargingLeftClick) return;

        double ratio = ComputeChargeRatio();
        IsChargingLeftClick = false;
        CurrentChargeRatio = 0;

        if (IsAwaitingServe && Server == CourtSide.Player)
        {
            PerformPlayerServe(ratio);
            return;
        }

        if (CanPlayerStrikeBallNow())
        {
            var kind = ratio >= 0.42 ? TennisShotKind.ChargedTopspin : TennisShotKind.FlatDrive;
            ExecutePlayerHit(kind, ratio);
        }
        else
        {
            _playerSwingVisualTimer = 0.20;
        }
    }

    public void HandleRightMouseDown(Vec2 courtLocalPoint)
    {
        if (!IsActive || IsMatchOver) return;
        HandleMouseMoved(courtLocalPoint);
        IsChargingLeftClick = false;
        CurrentChargeRatio = 0;

        if (IsAwaitingServe && Server == CourtSide.Player)
        {
            PerformPlayerServe(0.15);
            return;
        }

        if (CanPlayerStrikeBallNow())
        {
            var kind = AimCourtPoint.Y < 118 ? TennisShotKind.DropShot : TennisShotKind.HighLob;
            ExecutePlayerHit(kind, 0.3);
        }
        else
        {
            _playerSwingVisualTimer = 0.20;
        }
    }

    public void Update(double dt)
    {
        if (!IsActive) return;
        double clampedDt = Math.Clamp(dt, 0.001, 0.05);
        _clock += clampedDt;

        // Step floating effects & bounce rings
        for (int i = _popEffects.Count - 1; i >= 0; i--)
        {
            var e = _popEffects[i];
            e.Elapsed += clampedDt;
            e.Position = new Vec2(e.Position.X, e.Position.Y + 34.0 * clampedDt);
            if (e.Elapsed >= e.Duration) _popEffects.RemoveAt(i);
        }
        for (int i = _bounceMarks.Count - 1; i >= 0; i--)
        {
            _bounceMarks[i].Elapsed += clampedDt;
            if (_bounceMarks[i].Elapsed >= _bounceMarks[i].Duration) _bounceMarks.RemoveAt(i);
        }

        _dashTimer = Math.Max(0, _dashTimer - clampedDt);
        _dashCooldown = Math.Max(0, _dashCooldown - clampedDt);
        _playerSwingVisualTimer = Math.Max(0, _playerSwingVisualTimer - clampedDt);

        CurrentChargeRatio = IsChargingLeftClick ? ComputeChargeRatio() : 0;

        StepPlayerMovement(clampedDt * GameSpeed.PlayerMoveScale());

        if (IsMatchOver) return;

        if (_pointPauseTimer > 0)
        {
            _pointPauseTimer -= clampedDt;
            if (_pointPauseTimer <= 0 && IsAwaitingServe && Server == CourtSide.Westie)
                PerformOpponentServe();
            return;
        }

        if (IsAwaitingServe)
        {
            if (Server == CourtSide.Player)
            {
                _ball.X = PlayerPos.X + 14;
                _ball.Y = PlayerPos.Y + 12;
                _ball.Z = 22;
            }
            return;
        }

        if (IsChargingLeftClick && CanPlayerStrikeBallSweetSpot())
        {
            double ratio = ComputeChargeRatio();
            IsChargingLeftClick = false;
            CurrentChargeRatio = 0;
            var kind = ratio >= 0.42 ? TennisShotKind.ChargedTopspin : TennisShotKind.FlatDrive;
            ExecutePlayerHit(kind, ratio);
        }

        double simDt = clampedDt * GameSpeed.SimulationScale();

        var (bounced, hitNet, outcome) = TennisPhysics.StepBall(ref _ball, simDt);
        if (bounced) _bounceMarks.Add(new TennisBounceMark(new Vec2(_ball.X, _ball.Y)));
        if (hitNet) SpawnPop("NET!", new Vec2(_ball.X, 0), "#FFA500");

        if (outcome.IsPointWon)
        {
            AwardPoint(outcome.Winner, outcome.Reason);
            return;
        }

        bool oppHit = WestieTennisAI.Step(
            ref _opponent, ref _ball, !IsAwaitingServe, PlayerPos, Difficulty, simDt);
        if (oppHit)
        {
            RallyHits += 1;
            SpawnPop("✦", new Vec2(_opponent.X, _opponent.Y + 16), "#FFFFFF", 0.30);
        }
    }

    private void StepPlayerMovement(double dt)
    {
        double moveX = 0, moveY = 0;
        if (_heldKeys.Contains(TennisKey.W) || _heldKeys.Contains(TennisKey.Up)) moveY += 1;
        if (_heldKeys.Contains(TennisKey.S) || _heldKeys.Contains(TennisKey.Down)) moveY -= 1;
        if (_heldKeys.Contains(TennisKey.A) || _heldKeys.Contains(TennisKey.Left)) moveX -= 1;
        if (_heldKeys.Contains(TennisKey.D) || _heldKeys.Contains(TennisKey.Right)) moveX += 1;

        double px = PlayerPos.X, py = PlayerPos.Y;
        if (_dashTimer > 0)
        {
            px += _dashDirection.X * 420.0 * dt;
            py += _dashDirection.Y * 420.0 * dt;
        }
        else if (moveX != 0 || moveY != 0)
        {
            double len = Vec2.Hypot(moveX, moveY);
            double speed = 235.0 * (IsChargingLeftClick ? 0.76 : 1.0);
            px += (moveX / len) * speed * dt;
            py += (moveY / len) * speed * dt;

            _runAnimTimer += dt;
            if (_runAnimTimer >= 0.13)
            {
                _runAnimTimer = 0;
                _runFrameToggle = !_runFrameToggle;
            }
        }
        else
        {
            _runFrameToggle = false;
        }

        px = Math.Clamp(px, -TennisCourtMetrics.ApronMaxX + 20, TennisCourtMetrics.ApronMaxX - 20);
        py = Math.Clamp(py, -TennisCourtMetrics.ApronMaxY + 18, -28);
        PlayerPos = new Vec2(px, py);
    }

    private void TriggerDashFromHeldKeys()
    {
        if (_dashCooldown > 0) return;
        double dx = 0, dy = 0;
        if (_heldKeys.Contains(TennisKey.W) || _heldKeys.Contains(TennisKey.Up)) dy += 1;
        if (_heldKeys.Contains(TennisKey.S) || _heldKeys.Contains(TennisKey.Down)) dy -= 1;
        if (_heldKeys.Contains(TennisKey.A) || _heldKeys.Contains(TennisKey.Left)) dx -= 1;
        if (_heldKeys.Contains(TennisKey.D) || _heldKeys.Contains(TennisKey.Right)) dx += 1;
        double len = Vec2.Hypot(dx, dy);
        if (len <= 0.01) return;
        _dashDirection = new Vec2(dx / len, dy / len);
        _dashTimer = 0.16;
        _dashCooldown = 0.52;
        SpawnPop("💨", PlayerPos, "#FFFFFF", 0.35);
    }

    private double ComputeChargeRatio() => Math.Clamp((_clock - _chargeStartTime) / 0.72, 0.0, 1.0);

    private bool CanPlayerStrikeBallNow() =>
        !IsAwaitingServe && _ball.LastHitter == CourtSide.Westie && _ball.Y <= 10 && _ball.Z <= 64 &&
        Vec2.Hypot(_ball.X - PlayerPos.X, _ball.Y - PlayerPos.Y) <= 58.0;

    private bool CanPlayerStrikeBallSweetSpot() =>
        !IsAwaitingServe && _ball.LastHitter == CourtSide.Westie && _ball.Y <= 4 && _ball.Z <= 48 &&
        Vec2.Hypot(_ball.X - PlayerPos.X, _ball.Y - PlayerPos.Y) <= 40.0;

    private void PerformPlayerServe(double chargeRatio)
    {
        IsAwaitingServe = false;
        _playerSwingVisualTimer = 0.26;
        BannerText = "";
        _ball = TennisPhysics.MakeShot(
            PlayerPos.X + 8, PlayerPos.Y + 10, 26,
            CourtSide.Player, AimCourtPoint, TennisShotKind.Serve, chargeRatio);
        RallyHits = 1;
        SpawnPop("🎾 发球!", new Vec2(PlayerPos.X, PlayerPos.Y + 46), "#FFE666");
    }

    private void PerformOpponentServe()
    {
        IsAwaitingServe = false;
        _opponent.SwingCooldown = 0.36;
        BannerText = "";
        double aimX = (_opponent.X >= 0) ? (-120 + _rng.NextDouble() * 90) : (30 + _rng.NextDouble() * 90);
        _ball = TennisPhysics.MakeShot(
            _opponent.X, _opponent.Y - 10, 24,
            CourtSide.Westie, new Vec2(aimX, -175), TennisShotKind.Serve,
            Difficulty == TennisDifficulty.Pro ? 0.55 : 0.20);
        RallyHits = 1;
        SpawnPop(Species.IsCat() ? "喵! 🎾" : "汪! 🎾", new Vec2(_opponent.X, _opponent.Y + 42), "#FFFFFF");
    }

    private void ExecutePlayerHit(TennisShotKind kind, double charge)
    {
        _playerSwingVisualTimer = 0.24;
        _ball = TennisPhysics.MakeShot(
            _ball.X, Math.Max(_ball.Y, PlayerPos.Y + 6), Math.Max(_ball.Z, 18),
            CourtSide.Player, AimCourtPoint, kind, charge);
        RallyHits += 1;

        string? label = kind switch
        {
            TennisShotKind.ChargedTopspin => "🔥 强力上旋!",
            TennisShotKind.DropShot => "🪶 网前小球!",
            TennisShotKind.HighLob => "🌈 高吊球!",
            _ => null
        };
        if (label is not null)
            SpawnPop(label, new Vec2(PlayerPos.X, PlayerPos.Y + 58), "#FFE644");
    }

    private void AwardPoint(CourtSide winner, string reason)
    {
        if (winner == CourtSide.Player)
            PlayerScore += 1;
        else
        {
            OpponentScore += 1;
            _opponent.CelebrateTimer = 1.2;
        }

        if (PlayerScore >= TargetPointsToWin || OpponentScore >= TargetPointsToWin)
        {
            IsMatchOver = true;
            IsAwaitingServe = true;
            if (PlayerScore > OpponentScore)
            {
                BannerText = $"🏆 你赢啦 ({PlayerScore} : {OpponentScore})！左键/R 再来一局 · ESC 回桌面";
            }
            else
            {
                BannerText = Species switch
                {
                    PetSpecies.GoldenCat => $"🐱 金渐层获胜 ({OpponentScore} : {PlayerScore}) 喵呜！左键/R 再战 · ESC 回桌面",
                    PetSpecies.Chinchilla => $"🐈 金吉拉获胜 ({OpponentScore} : {PlayerScore}) 喵呜！左键/R 再战 · ESC 回桌面",
                    PetSpecies.Labrador => $"🐕 拉布拉多获胜 ({OpponentScore} : {PlayerScore}) 汪汪！左键/R 再战 · ESC 回桌面",
                    _ => $"🐶 西高地获胜 ({OpponentScore} : {PlayerScore}) 汪汪！左键/R 再战 · ESC 回桌面"
                };
            }
            return;
        }

        Server = Server.Opposite();
        string petShort = Species.ShortName();
        string scorer = winner == CourtSide.Player ? "你得分" : $"{petShort}得分";
        string nextServe = Server == CourtSide.Player ? "轮到你发球(左键/空格)" : $"{petShort}准备发球...";
        ResetForNextPoint($"{reason} → {scorer}! {nextServe}");
        if (Server == CourtSide.Westie)
            _pointPauseTimer = 1.15;
    }

    private void SpawnPop(string text, Vec2 pos, string colorHex, double duration = 0.55) =>
        _popEffects.Add(new TennisPopEffect(text, pos, colorHex, duration));
}
