import CoreGraphics
import Foundation

public enum TennisShotKind: String, Sendable, Equatable {
    case flatDrive      // LMB tap
    case chargedTopspin // LMB hold charge
    case dropShot       // RMB aimed short
    case highLob        // RMB aimed deep
    case serve          // Opening serve
}

public enum CourtSide: String, Sendable, Equatable {
    case player // y < 0 (bottom half)
    case westie // y > 0 (top half)

    public var opposite: CourtSide {
        self == .player ? .westie : .player
    }
}

public enum PointOutcome: Equatable, Sendable {
    case ongoing
    case pointWon(by: CourtSide, reason: String)
}

public struct TennisCourtMetrics: Sendable {
    public static let halfWidth: CGFloat = 175.0      // Singles sideline X in [-175, +175]
    public static let halfLength: CGFloat = 240.0     // Baseline Y in [-240, +240]
    public static let apronMaxX: CGFloat = 235.0
    public static let apronMaxY: CGFloat = 295.0
    public static let netHeight: CGFloat = 24.0
    public static let gravityZ: CGFloat = 690.0
    public static let bounceRestitutionZ: CGFloat = 0.72
}

public struct TennisBallState: Sendable, Equatable {
    public var x: CGFloat
    public var y: CGFloat
    public var z: CGFloat
    public var vx: CGFloat
    public var vy: CGFloat
    public var vz: CGFloat
    public var spinDrag: CGFloat
    public var lastHitter: CourtSide
    public var bounceCountOnCurrentSide: Int
    public var hasCrossedNet: Bool

    public init(
        x: CGFloat = 0,
        y: CGFloat = -210,
        z: CGFloat = 18,
        vx: CGFloat = 0,
        vy: CGFloat = 0,
        vz: CGFloat = 0,
        spinDrag: CGFloat = 1.0,
        lastHitter: CourtSide = .player,
        bounceCountOnCurrentSide: Int = 0,
        hasCrossedNet: Bool = false
    ) {
        self.x = x
        self.y = y
        self.z = z
        self.vx = vx
        self.vy = vy
        self.vz = vz
        self.spinDrag = spinDrag
        self.lastHitter = lastHitter
        self.bounceCountOnCurrentSide = bounceCountOnCurrentSide
        self.hasCrossedNet = hasCrossedNet
    }
}

public enum TennisPhysics {
    /// Launches a shot from `(originX, originY, originZ)` aimed at `(targetX, targetY)` on the opponent's half.
    public static func makeShot(
        from origin: (x: CGFloat, y: CGFloat, z: CGFloat),
        hitter: CourtSide,
        target: CGPoint,
        kind: TennisShotKind,
        chargeRatio: CGFloat = 0.0
    ) -> TennisBallState {
        let clampedCharge = min(max(chargeRatio, 0.0), 1.0)
        let signY: CGFloat = (hitter == .player) ? 1.0 : -1.0

        // Clamp target within realistic court aiming region (slight wide margin allowed for risk/reward)
        let clampedTargetX = min(max(target.x, -TennisCourtMetrics.halfWidth + 8), TennisCourtMetrics.halfWidth - 8)
        let minDepth: CGFloat = (kind == .dropShot) ? 44.0 : 75.0
        let maxDepth: CGFloat = TennisCourtMetrics.halfLength - 14.0
        let rawDepth = abs(target.y)
        let targetY = signY * min(max(rawDepth, minDepth), maxDepth)

        let dx = clampedTargetX - origin.x
        let dy = targetY - origin.y
        let planarDist = max(80.0, hypot(dx, dy))

        let flightTime: CGFloat
        let spinDrag: CGFloat

        switch kind {
        case .serve:
            let speed: CGFloat = 460.0 + clampedCharge * 130.0
            flightTime = planarDist / speed
            spinDrag = 0.94
        case .flatDrive:
            let speed: CGFloat = 430.0 + clampedCharge * 110.0
            flightTime = planarDist / speed
            spinDrag = 0.92
        case .chargedTopspin:
            let speed: CGFloat = 520.0 + clampedCharge * 145.0
            flightTime = planarDist / speed
            spinDrag = 0.96
        case .dropShot:
            let speed: CGFloat = 285.0
            flightTime = max(0.58, planarDist / speed)
            spinDrag = 0.56 // Strong backspin brakes horizontal velocity on bounce!
        case .highLob:
            flightTime = max(1.08, planarDist / 255.0)
            spinDrag = 0.80
        }

        let vx = dx / flightTime
        let vy = dy / flightTime
        // Solve z(flightTime) = 0 => 0 = z0 + vz*T - 0.5*g*T^2 => vz = (0.5*g*T^2 - z0)/T
        let g = TennisCourtMetrics.gravityZ
        var vz = (0.5 * g * flightTime * flightTime - origin.z) / flightTime

        // Ensure comfortable net clearance when crossing y = 0
        let tNet = abs(origin.y) / max(abs(vy), 1.0)
        if tNet > 0.04 && tNet < flightTime {
            let zAtNet = origin.z + vz * tNet - 0.5 * g * tNet * tNet
            let minClearance: CGFloat = (kind == .highLob) ? 72.0 : (TennisCourtMetrics.netHeight + 9.0)
            if zAtNet < minClearance {
                let neededVz = (minClearance - origin.z + 0.5 * g * tNet * tNet) / tNet
                vz = max(vz, neededVz)
            }
        }

        return TennisBallState(
            x: origin.x,
            y: origin.y,
            z: max(origin.z, 12),
            vx: vx,
            vy: vy,
            vz: vz,
            spinDrag: spinDrag,
            lastHitter: hitter,
            bounceCountOnCurrentSide: 0,
            hasCrossedNet: false
        )
    }

    /// Advances 2.5D ball state by `dt` and evaluates net collisions, in/out bounces, and double-bounce winners.
    public static func stepBall(ball: inout TennisBallState, dt: CGFloat) -> (bounced: Bool, hitNet: Bool, outcome: PointOutcome) {
        let prevY = ball.y
        ball.x += ball.vx * dt
        ball.y += ball.vy * dt
        ball.vz -= TennisCourtMetrics.gravityZ * dt
        ball.z += ball.vz * dt

        var hitNet = false
        var bounced = false

        // 1. Check net plane crossing (y = 0)
        if (prevY < 0 && ball.y >= 0) || (prevY > 0 && ball.y <= 0) {
            if ball.z < TennisCourtMetrics.netHeight {
                // Net cord collision!
                hitNet = true
                if ball.z > TennisCourtMetrics.netHeight - 4.0 {
                    // Lucky net-cord dribble: slows down and pops slightly over!
                    ball.vx *= 0.55
                    ball.vy *= 0.48
                    ball.vz = max(ball.vz, 95.0)
                    ball.z = TennisCourtMetrics.netHeight + 2.0
                    ball.hasCrossedNet = true
                    ball.bounceCountOnCurrentSide = 0
                } else {
                    // Into the net -> point to opponent of lastHitter
                    ball.vx *= -0.2
                    ball.vy *= -0.22
                    ball.vz = 40
                    return (false, true, .pointWon(by: ball.lastHitter.opposite, reason: "下网失误 Net!"))
                }
            } else {
                ball.hasCrossedNet = true
                ball.bounceCountOnCurrentSide = 0
            }
        }

        // 2. Check ground bounce (z <= 0)
        if ball.z <= 0 {
            ball.z = 0
            bounced = true
            let landedSide: CourtSide = (ball.y >= 0) ? .westie : .player

            // If ball bounced on hitter's own side before crossing net -> fault
            if landedSide == ball.lastHitter && !ball.hasCrossedNet {
                return (true, hitNet, .pointWon(by: ball.lastHitter.opposite, reason: "未过网失误!"))
            }

            ball.bounceCountOnCurrentSide += 1

            // First bounce must land inside court lines!
            if ball.bounceCountOnCurrentSide == 1 {
                let inBounds = abs(ball.x) <= (TennisCourtMetrics.halfWidth + 6.0) &&
                    abs(ball.y) <= (TennisCourtMetrics.halfLength + 6.0)
                if !inBounds {
                    return (true, hitNet, .pointWon(by: ball.lastHitter.opposite, reason: "出界 Out!"))
                }
            } else if ball.bounceCountOnCurrentSide >= 2 {
                // Second bounce -> clean winner for lastHitter!
                return (true, hitNet, .pointWon(by: ball.lastHitter, reason: "落地得分 Winner!"))
            }

            ball.vz = abs(ball.vz) * TennisCourtMetrics.bounceRestitutionZ
            ball.vx *= ball.spinDrag
            ball.vy *= ball.spinDrag
        }

        // 3. Far out-of-apron safety boundary (e.g., ball flies way past back fence after 1st bounce)
        if ball.bounceCountOnCurrentSide >= 1 &&
            (abs(ball.y) > TennisCourtMetrics.apronMaxY + 55 || abs(ball.x) > TennisCourtMetrics.apronMaxX + 75)
        {
            return (bounced, hitNet, .pointWon(by: ball.lastHitter, reason: "穿越制胜球 Ace/Winner!"))
        }

        return (bounced, hitNet, .ongoing)
    }

    /// Predicts where the ball will next bounce (`z == 0`), used by Westie AI to anticipate shots.
    public static func predictLandingPoint(for ball: TennisBallState) -> CGPoint {
        let g = TennisCourtMetrics.gravityZ
        let discriminant = max(0, ball.vz * ball.vz + 2.0 * g * max(0, ball.z))
        let t = (ball.vz + sqrt(discriminant)) / g
        return CGPoint(
            x: ball.x + ball.vx * t,
            y: ball.y + ball.vy * t
        )
    }
}
