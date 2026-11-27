using System;

namespace WestieDeskPet.Core;

public enum TennisDifficulty
{
    Casual,
    Pro
}

public static class TennisDifficultyExtensions
{
    public static string DisplayName(this TennisDifficulty diff, PetSpecies species) => (diff, species.IsCat()) switch
    {
        (TennisDifficulty.Casual, false) => "休闲小狗",
        (TennisDifficulty.Pro, false) => "网球狗王",
        (TennisDifficulty.Casual, true) => "休闲小猫",
        (TennisDifficulty.Pro, true) => "网球猫王",
        _ => "休闲小狗"
    };
}

public enum TennisGameSpeed
{
    Slow,
    Medium,
    Standard,
    Fast
}

public static class TennisGameSpeedExtensions
{
    public static string ShortName(this TennisGameSpeed spd) => spd switch
    {
        TennisGameSpeed.Slow => "慢速",
        TennisGameSpeed.Medium => "适中",
        TennisGameSpeed.Standard => "标准",
        TennisGameSpeed.Fast => "快速",
        _ => "慢速"
    };

    public static string DisplayName(this TennisGameSpeed spd) => spd switch
    {
        TennisGameSpeed.Slow => "🐢 慢速",
        TennisGameSpeed.Medium => "🎾 适中",
        TennisGameSpeed.Standard => "⚡️ 标准",
        TennisGameSpeed.Fast => "🔥 快速",
        _ => "🐢 慢速"
    };

    public static double SimulationScale(this TennisGameSpeed spd) => spd switch
    {
        TennisGameSpeed.Slow => 0.62,
        TennisGameSpeed.Medium => 0.80,
        TennisGameSpeed.Standard => 1.00,
        TennisGameSpeed.Fast => 1.20,
        _ => 0.62
    };

    public static double PlayerMoveScale(this TennisGameSpeed spd) => spd switch
    {
        TennisGameSpeed.Slow => 0.88,
        TennisGameSpeed.Medium => 0.94,
        TennisGameSpeed.Standard => 1.00,
        TennisGameSpeed.Fast => 1.08,
        _ => 0.88
    };

    public static TennisGameSpeed Next(this TennisGameSpeed spd)
    {
        var all = Enum.GetValues<TennisGameSpeed>();
        int idx = Array.IndexOf(all, spd);
        return all[(idx + 1) % all.Length];
    }

    public static TennisGameSpeed Slower(this TennisGameSpeed spd)
    {
        var all = Enum.GetValues<TennisGameSpeed>();
        int idx = Array.IndexOf(all, spd);
        return idx > 0 ? all[idx - 1] : TennisGameSpeed.Slow;
    }

    public static TennisGameSpeed Faster(this TennisGameSpeed spd)
    {
        var all = Enum.GetValues<TennisGameSpeed>();
        int idx = Array.IndexOf(all, spd);
        return idx + 1 < all.Length ? all[idx + 1] : TennisGameSpeed.Fast;
    }
}

public struct WestieOpponentState
{
    public double X;
    public double Y;
    public double LastStepDx;
    public double FacingDirection;
    public double SwingCooldown;
    public double DiveTimer;
    public double CelebrateTimer;

    public static WestieOpponentState CreateDefault() => new()
    {
        X = 0,
        Y = 195,
        LastStepDx = 0,
        FacingDirection = 1.0,
        SwingCooldown = 0,
        DiveTimer = 0,
        CelebrateTimer = 0
    };
}

public static class WestieTennisAI
{
    private static readonly Random Rng = new();

    public static bool Step(
        ref WestieOpponentState opponent,
        ref TennisBallState ball,
        bool isBallLive,
        Vec2 playerPosition,
        TennisDifficulty difficulty,
        double dt)
    {
        opponent.SwingCooldown = Math.Max(0, opponent.SwingCooldown - dt);
        opponent.DiveTimer = Math.Max(0, opponent.DiveTimer - dt);
        opponent.CelebrateTimer = Math.Max(0, opponent.CelebrateTimer - dt);

        double moveSpeed = (difficulty == TennisDifficulty.Pro) ? 255.0 : 178.0;
        double reachRadius = (difficulty == TennisDifficulty.Pro) ? 52.0 : 44.0;

        if (!isBallLive)
        {
            MoveToward(ref opponent, new Vec2(0, 195), moveSpeed * 0.75, dt);
            return false;
        }

        if (ball.LastHitter == CourtSide.Player)
        {
            Vec2 predicted = TennisPhysics.PredictLandingPoint(in ball);
            double targetY = Math.Clamp(predicted.Y + 18, 54, TennisCourtMetrics.HalfLength + 24);
            double targetX = Math.Clamp(predicted.X, -TennisCourtMetrics.HalfWidth - 28, TennisCourtMetrics.HalfWidth + 28);

            double distToPredicted = Vec2.Hypot(targetX - opponent.X, targetY - opponent.Y);
            double effectiveSpeed;
            if (distToPredicted > 95 && opponent.DiveTimer <= 0 && Math.Abs(ball.Y - opponent.Y) < 95)
            {
                opponent.DiveTimer = 0.34;
                effectiveSpeed = moveSpeed * 1.48;
            }
            else
            {
                effectiveSpeed = moveSpeed;
            }

            MoveToward(ref opponent, new Vec2(targetX, targetY), effectiveSpeed, dt);

            double planarDist = Vec2.Hypot(ball.X - opponent.X, ball.Y - opponent.Y);
            if (ball.Y > 14 && ball.Z <= 58 && planarDist <= reachRadius && opponent.SwingCooldown <= 0)
            {
                opponent.SwingCooldown = 0.42;

                double openCornerX = (playerPosition.X >= 0)
                    ? RandRange(-148, -55)
                    : RandRange(55, 148);
                double jitterX = (difficulty == TennisDifficulty.Pro) ? RandRange(-12, 12) : RandRange(-35, 35);
                double aimX = Math.Clamp(openCornerX + jitterX, -156, 156);

                TennisShotKind shotKind;
                double aimY;
                double roll = Rng.NextDouble();
                if (difficulty == TennisDifficulty.Pro && playerPosition.Y < -185 && roll < 0.25)
                {
                    shotKind = TennisShotKind.DropShot;
                    aimY = -68;
                }
                else if (playerPosition.Y > -95 && roll < 0.32)
                {
                    shotKind = TennisShotKind.HighLob;
                    aimY = -215;
                }
                else
                {
                    shotKind = (difficulty == TennisDifficulty.Pro && roll < 0.45)
                        ? TennisShotKind.ChargedTopspin
                        : TennisShotKind.FlatDrive;
                    aimY = RandRange(-215, -125);
                }

                ball = TennisPhysics.MakeShot(
                    opponent.X, opponent.Y, Math.Max(ball.Z, 18),
                    CourtSide.Westie,
                    new Vec2(aimX, aimY),
                    shotKind,
                    (difficulty == TennisDifficulty.Pro) ? 0.65 : 0.25);
                return true;
            }
        }
        else
        {
            double recoveryY = (difficulty == TennisDifficulty.Pro) ? 182 : 200;
            MoveToward(ref opponent, new Vec2(ball.X * 0.22, recoveryY), moveSpeed * 0.72, dt);
        }

        return false;
    }

    private static void MoveToward(ref WestieOpponentState opponent, Vec2 target, double speed, double dt)
    {
        double dx = target.X - opponent.X;
        double dy = target.Y - opponent.Y;
        double dist = Vec2.Hypot(dx, dy);
        if (dist <= 2.0)
        {
            opponent.LastStepDx = 0;
            return;
        }
        double stepDist = Math.Min(dist, speed * dt);
        double stepX = (dx / dist) * stepDist;
        opponent.X += stepX;
        opponent.Y += (dy / dist) * stepDist;
        opponent.LastStepDx = stepX;
        if (Math.Abs(dx) > 3.0)
            opponent.FacingDirection = dx >= 0 ? 1.0 : -1.0;
    }

    private static double RandRange(double lo, double hi) => lo + Rng.NextDouble() * (hi - lo);
}
