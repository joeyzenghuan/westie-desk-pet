using System;

namespace WestieDeskPet.Core;

public enum PetSpecies
{
    Westie,
    GoldenCat
}

public static class PetSpeciesExtensions
{
    public static string DisplayName(this PetSpecies sp) => sp switch
    {
        PetSpecies.Westie => "🐶 西高地小狗",
        PetSpecies.GoldenCat => "🐱 金渐层小猫",
        _ => "🐶 西高地小狗"
    };

    public static string ShortName(this PetSpecies sp) => sp switch
    {
        PetSpecies.Westie => "西高地",
        PetSpecies.GoldenCat => "金渐层",
        _ => "西高地"
    };
}

public enum TopClimbRoutine
{
    ClassicStory,
    FlashStep,
    Random
}

public static class TopClimbRoutineExtensions
{
    public static string DisplayName(this TopClimbRoutine rt) => rt switch
    {
        TopClimbRoutine.ClassicStory => "🐾 悠闲巡逻 (跳走+张望+打哈欠)",
        TopClimbRoutine.FlashStep => "⚡ 闪身步 (起势→右闪→停→准备→左闪)",
        TopClimbRoutine.Random => "🎲 随机轮换",
        _ => "🐾 悠闲巡逻"
    };

    public static string ShortLabel(this TopClimbRoutine rt) => rt switch
    {
        TopClimbRoutine.ClassicStory => "悠闲巡逻",
        TopClimbRoutine.FlashStep => "闪身步",
        TopClimbRoutine.Random => "随机轮换",
        _ => "悠闲巡逻"
    };
}

public enum PerchZone
{
    WindowTop,
    WindowRightPeek,
    ScreenRightPeek
}

public enum PerchPreference
{
    Auto,
    WindowTop,
    RightPeek
}

public static class PerchPreferenceExtensions
{
    public static string DisplayName(this PerchPreference p) => p switch
    {
        PerchPreference.Auto => "屏幕右侧边 + 定时爬顶 (默认)",
        PerchPreference.WindowTop => "优先窗口正上方",
        PerchPreference.RightPeek => "跟随窗口右侧边",
        _ => "屏幕右侧边 + 定时爬顶 (默认)"
    };
}

public enum TopTapPose
{
    SitSmile,
    LoafCalm,
    BigHeadPeek,
    Sleep
}

public static class TopTapPoseExtensions
{
    public static readonly TopTapPose[] DefaultSelection =
    [
        TopTapPose.SitSmile,
        TopTapPose.LoafCalm,
        TopTapPose.BigHeadPeek
    ];

    public static string DisplayName(this TopTapPose pose) => pose switch
    {
        TopTapPose.SitSmile => "😊 微笑歪头坐",
        TopTapPose.LoafCalm => "🐾 安静趴卧",
        TopTapPose.BigHeadPeek => "🐶 大头趴窗盯镜头",
        TopTapPose.Sleep => "💤 团成团子睡觉",
        _ => "😊 微笑歪头坐"
    };
}

public struct DampedSpring
{
    public double Value;
    public double Velocity;
    public double Target;
    public double Stiffness;
    public double Damping;

    public DampedSpring(double value = 0, double velocity = 0, double target = 0, double stiffness = 260, double damping = 18)
    {
        Value = value;
        Velocity = velocity;
        Target = target;
        Stiffness = stiffness;
        Damping = damping;
    }

    public bool IsSettled => Math.Abs(Target - Value) < 0.0015 && Math.Abs(Velocity) < 0.008;

    public void Step(double dt)
    {
        double clampedDt = Math.Clamp(dt, 0.0005, 0.05);
        int substeps = clampedDt > 0.014 ? 2 : 1;
        double h = clampedDt / substeps;
        for (int i = 0; i < substeps; i++)
        {
            double accel = (Target - Value) * Stiffness - Velocity * Damping;
            Velocity += accel * h;
            Value += Velocity * h;
        }
        if (IsSettled)
        {
            Value = Target;
            Velocity = 0;
        }
    }

    public void Impulse(double dv) => Velocity += dv;

    public void Snap(double newValue)
    {
        Value = newValue;
        Target = newValue;
        Velocity = 0;
    }
}

public enum CompanionStateKind
{
    Idle,
    Walking,
    SitCalm,
    Loafing,
    ChinRest,
    Sleeping,
    PeekingRight,
    GreetingOnTop,
    TopStory,
    Yawning,
    SettlingToSleep,
    TuckedWaiting,
    StealthTransition,
    Gliding,
    Dragged,
    HoldingTennisBall,
    ChasingTreat,
    EatingTreat
}

public enum StealthPhaseKind
{
    Retracting,
    HiddenTraverse,
    TentativePeek,
    SettlingOut
}

public enum TopStoryStepKind
{
    PostClimbPause,
    HopLeft,
    LookAroundPause,
    WalkRight,
    PostWalkPause,
    FlashStep,
    SmileSit,
    PreYawnWait
}

public enum FlashStepBeatKind
{
    Stance,
    DodgeRight,
    StopMid,
    ReadyLeft,
    DodgeLeft,
    FinishStop
}

public sealed record StealthDestination(
    PerchZone PerchZone,
    double TargetX = 0,
    double TargetY = 0,
    bool ClimbToGreet = false,
    TopClimbRoutine? RoutineOverride = null);

public sealed class PendingWindowSwitch
{
    public ulong TargetWindowId { get; }
    public double Elapsed { get; set; }

    public PendingWindowSwitch(ulong targetWindowId)
    {
        TargetWindowId = targetWindowId;
    }
}

public readonly record struct CompanionContext(
    bool IsMeetingActive = false,
    bool IsCodingActive = false,
    bool ForceQuietSleep = false,
    bool ShouldOfferTennisBreak = false);

public static class WestieBehaviorPlanner
{
    private static readonly Random Rng = new();

    public static (CompanionStateKind Kind, double Direction, double Duration) ChooseNextTopBehavior(
        double currentX,
        WindowPlatform platform,
        CompanionContext context,
        double? randomUnitOverride = null)
    {
        if (context.ForceQuietSleep || context.IsMeetingActive)
            return (CompanionStateKind.Sleeping, 1.0, 24.0);

        if (context.ShouldOfferTennisBreak)
            return (CompanionStateKind.HoldingTennisBall, 1.0, 22.0);

        double u = randomUnitOverride ?? Rng.NextDouble();
        if (context.IsCodingActive)
        {
            if (u < 0.36) return (CompanionStateKind.Loafing, 1.0, RandRange(10.0, 18.0));
            if (u < 0.64) return (CompanionStateKind.SitCalm, 1.0, RandRange(7.0, 12.0));
            if (u < 0.88) return (CompanionStateKind.Sleeping, 1.0, RandRange(14.0, 22.0));
            return (CompanionStateKind.Walking, PreferredWalkDirection(currentX, platform), RandRange(2.0, 3.8));
        }

        if (u < 0.28) return (CompanionStateKind.Walking, PreferredWalkDirection(currentX, platform), RandRange(2.4, 4.4));
        if (u < 0.56) return (CompanionStateKind.Loafing, 1.0, RandRange(9.0, 15.0));
        if (u < 0.78) return (CompanionStateKind.SitCalm, 1.0, RandRange(6.5, 11.0));
        if (u < 0.88) return (CompanionStateKind.Idle, 1.0, RandRange(4.5, 7.5));
        return (CompanionStateKind.Sleeping, 1.0, RandRange(12.0, 20.0));
    }

    public static double PreferredWalkDirection(double currentX, WindowPlatform platform)
    {
        double leftRoom = currentX - platform.MinX;
        double rightRoom = platform.MaxX - currentX;
        if (leftRoom < 42) return 1.0;
        if (rightRoom < 42) return -1.0;
        return Rng.Next(2) == 0 ? 1.0 : -1.0;
    }

    private static double RandRange(double lo, double hi) => lo + Rng.NextDouble() * (hi - lo);
}
