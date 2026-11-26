using System;

namespace WestieDeskPet.Core;

public enum TennisShotKind
{
    FlatDrive,
    ChargedTopspin,
    DropShot,
    HighLob,
    Serve
}

public enum CourtSide
{
    Player,
    Westie
}

public static class CourtSideExtensions
{
    public static CourtSide Opposite(this CourtSide side) =>
        side == CourtSide.Player ? CourtSide.Westie : CourtSide.Player;
}

public readonly record struct PointOutcome(bool IsPointWon, CourtSide Winner, string Reason)
{
    public static readonly PointOutcome Ongoing = new(false, CourtSide.Player, "");
    public static PointOutcome WonBy(CourtSide winner, string reason) => new(true, winner, reason);
}

public static class TennisCourtMetrics
{
    public const double HalfWidth = 175.0;
    public const double HalfLength = 240.0;
    public const double ApronMaxX = 235.0;
    public const double ApronMaxY = 295.0;
    public const double NetHeight = 24.0;
    public const double GravityZ = 690.0;
    public const double BounceRestitutionZ = 0.72;
}

public struct TennisBallState
{
    public double X;
    public double Y;
    public double Z;
    public double Vx;
    public double Vy;
    public double Vz;
    public double SpinDrag;
    public CourtSide LastHitter;
    public int BounceCountOnCurrentSide;
    public bool HasCrossedNet;

    public TennisBallState(
        double x = 0,
        double y = -210,
        double z = 18,
        double vx = 0,
        double vy = 0,
        double vz = 0,
        double spinDrag = 1.0,
        CourtSide lastHitter = CourtSide.Player,
        int bounceCount = 0,
        bool hasCrossedNet = false)
    {
        X = x;
        Y = y;
        Z = z;
        Vx = vx;
        Vy = vy;
        Vz = vz;
        SpinDrag = spinDrag;
        LastHitter = lastHitter;
        BounceCountOnCurrentSide = bounceCount;
        HasCrossedNet = hasCrossedNet;
    }
}

public static class TennisPhysics
{
    public static TennisBallState MakeShot(
        double originX,
        double originY,
        double originZ,
        CourtSide hitter,
        Vec2 target,
        TennisShotKind kind,
        double chargeRatio = 0.0)
    {
        double clampedCharge = Math.Clamp(chargeRatio, 0.0, 1.0);
        double signY = (hitter == CourtSide.Player) ? 1.0 : -1.0;

        double clampedTargetX = Math.Clamp(target.X, -TennisCourtMetrics.HalfWidth + 8, TennisCourtMetrics.HalfWidth - 8);
        double minDepth = (kind == TennisShotKind.DropShot) ? 44.0 : 75.0;
        double maxDepth = TennisCourtMetrics.HalfLength - 14.0;
        double targetY = signY * Math.Clamp(Math.Abs(target.Y), minDepth, maxDepth);

        double dx = clampedTargetX - originX;
        double dy = targetY - originY;
        double planarDist = Math.Max(80.0, Vec2.Hypot(dx, dy));

        double flightTime;
        double spinDrag;
        switch (kind)
        {
            case TennisShotKind.Serve:
                flightTime = planarDist / (460.0 + clampedCharge * 130.0);
                spinDrag = 0.94;
                break;
            case TennisShotKind.FlatDrive:
                flightTime = planarDist / (430.0 + clampedCharge * 110.0);
                spinDrag = 0.92;
                break;
            case TennisShotKind.ChargedTopspin:
                flightTime = planarDist / (520.0 + clampedCharge * 145.0);
                spinDrag = 0.96;
                break;
            case TennisShotKind.DropShot:
                flightTime = Math.Max(0.58, planarDist / 285.0);
                spinDrag = 0.56;
                break;
            case TennisShotKind.HighLob:
                flightTime = Math.Max(1.08, planarDist / 255.0);
                spinDrag = 0.80;
                break;
            default:
                flightTime = planarDist / 430.0;
                spinDrag = 0.92;
                break;
        }

        double vx = dx / flightTime;
        double vy = dy / flightTime;
        const double g = TennisCourtMetrics.GravityZ;
        double vz = (0.5 * g * flightTime * flightTime - originZ) / flightTime;

        double tNet = Math.Abs(originY) / Math.Max(Math.Abs(vy), 1.0);
        if (tNet > 0.04 && tNet < flightTime)
        {
            double zAtNet = originZ + vz * tNet - 0.5 * g * tNet * tNet;
            double minClearance = (kind == TennisShotKind.HighLob) ? 72.0 : (TennisCourtMetrics.NetHeight + 9.0);
            if (zAtNet < minClearance)
            {
                double neededVz = (minClearance - originZ + 0.5 * g * tNet * tNet) / tNet;
                vz = Math.Max(vz, neededVz);
            }
        }

        return new TennisBallState(
            originX, originY, Math.Max(originZ, 12.0),
            vx, vy, vz, spinDrag, hitter, 0, false);
    }

    public static (bool Bounced, bool HitNet, PointOutcome Outcome) StepBall(ref TennisBallState ball, double dt)
    {
        double prevY = ball.Y;
        ball.X += ball.Vx * dt;
        ball.Y += ball.Vy * dt;
        ball.Vz -= TennisCourtMetrics.GravityZ * dt;
        ball.Z += ball.Vz * dt;

        bool hitNet = false;
        bool bounced = false;

        if ((prevY < 0 && ball.Y >= 0) || (prevY > 0 && ball.Y <= 0))
        {
            if (ball.Z < TennisCourtMetrics.NetHeight)
            {
                hitNet = true;
                if (ball.Z > TennisCourtMetrics.NetHeight - 4.0)
                {
                    ball.Vx *= 0.55;
                    ball.Vy *= 0.48;
                    ball.Vz = Math.Max(ball.Vz, 95.0);
                    ball.Z = TennisCourtMetrics.NetHeight + 2.0;
                    ball.HasCrossedNet = true;
                    ball.BounceCountOnCurrentSide = 0;
                }
                else
                {
                    ball.Vx *= -0.2;
                    ball.Vy *= -0.22;
                    ball.Vz = 40;
                    return (false, true, PointOutcome.WonBy(ball.LastHitter.Opposite(), "下网失误 Net!"));
                }
            }
            else
            {
                ball.HasCrossedNet = true;
                ball.BounceCountOnCurrentSide = 0;
            }
        }

        if (ball.Z <= 0)
        {
            ball.Z = 0;
            bounced = true;
            CourtSide landedSide = (ball.Y >= 0) ? CourtSide.Westie : CourtSide.Player;

            if (landedSide == ball.LastHitter && !ball.HasCrossedNet)
                return (true, hitNet, PointOutcome.WonBy(ball.LastHitter.Opposite(), "未过网失误!"));

            ball.BounceCountOnCurrentSide += 1;

            if (ball.BounceCountOnCurrentSide == 1)
            {
                bool inBounds = Math.Abs(ball.X) <= TennisCourtMetrics.HalfWidth + 6.0 &&
                                Math.Abs(ball.Y) <= TennisCourtMetrics.HalfLength + 6.0;
                if (!inBounds)
                    return (true, hitNet, PointOutcome.WonBy(ball.LastHitter.Opposite(), "出界 Out!"));
            }
            else if (ball.BounceCountOnCurrentSide >= 2)
            {
                return (true, hitNet, PointOutcome.WonBy(ball.LastHitter, "落地得分 Winner!"));
            }

            ball.Vz = Math.Abs(ball.Vz) * TennisCourtMetrics.BounceRestitutionZ;
            ball.Vx *= ball.SpinDrag;
            ball.Vy *= ball.SpinDrag;
        }

        if (ball.BounceCountOnCurrentSide >= 1 &&
            (Math.Abs(ball.Y) > TennisCourtMetrics.ApronMaxY + 55 || Math.Abs(ball.X) > TennisCourtMetrics.ApronMaxX + 75))
        {
            return (bounced, hitNet, PointOutcome.WonBy(ball.LastHitter, "穿越制胜球 Ace/Winner!"));
        }

        return (bounced, hitNet, PointOutcome.Ongoing);
    }

    public static Vec2 PredictLandingPoint(in TennisBallState ball)
    {
        const double g = TennisCourtMetrics.GravityZ;
        double disc = Math.Max(0, ball.Vz * ball.Vz + 2.0 * g * Math.Max(0, ball.Z));
        double t = (ball.Vz + Math.Sqrt(disc)) / g;
        return new Vec2(ball.X + ball.Vx * t, ball.Y + ball.Vy * t);
    }
}
