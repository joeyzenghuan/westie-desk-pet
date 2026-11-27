import CoreGraphics
import Foundation

public enum TennisDifficulty: String, CaseIterable, Sendable {
    case casual = "休闲小狗"
    case pro = "网球狗王"

    public func displayName(for species: PetSpecies) -> String {
        switch (self, species.isCat) {
        case (.casual, false): return "休闲小狗"
        case (.pro, false): return "网球狗王"
        case (.casual, true): return "休闲小猫"
        case (.pro, true): return "网球猫王"
        }
    }
}

public enum TennisGameSpeed: String, CaseIterable, Sendable {
    case slow = "慢速"
    case medium = "适中"
    case standard = "标准"
    case fast = "快速"

    public var displayName: String {
        switch self {
        case .slow: return "🐢 慢速"
        case .medium: return "🎾 适中"
        case .standard: return "⚡️ 标准"
        case .fast: return "🔥 快速"
        }
    }

    /// Scales ball flight & AI movement `dt` while keeping trajectory physics 100% accurate.
    public var simulationScale: CGFloat {
        switch self {
        case .slow: return 0.62
        case .medium: return 0.80
        case .standard: return 1.00
        case .fast: return 1.20
        }
    }

    /// Keeps human WASD responsive even in slow-ball mode so movement never feels sluggish.
    public var playerMoveScale: CGFloat {
        switch self {
        case .slow: return 0.88
        case .medium: return 0.94
        case .standard: return 1.00
        case .fast: return 1.08
        }
    }

    public func next() -> TennisGameSpeed {
        let all = Self.allCases
        guard let idx = all.firstIndex(of: self) else { return .slow }
        return all[(idx + 1) % all.count]
    }

    public func slower() -> TennisGameSpeed {
        let all = Self.allCases
        guard let idx = all.firstIndex(of: self), idx > 0 else { return .slow }
        return all[idx - 1]
    }

    public func faster() -> TennisGameSpeed {
        let all = Self.allCases
        guard let idx = all.firstIndex(of: self), idx + 1 < all.count else { return .fast }
        return all[idx + 1]
    }
}

public struct WestieOpponentState: Sendable {
    public var x: CGFloat = 0
    public var y: CGFloat = 195
    public var lastStepDX: CGFloat = 0
    public var facingDirection: CGFloat = 1.0
    public var swingCooldown: TimeInterval = 0
    public var diveTimer: TimeInterval = 0
    public var celebrateTimer: TimeInterval = 0

    public init() {}
}

public enum WestieTennisAI {
    public static func step(
        opponent: inout WestieOpponentState,
        ball: inout TennisBallState,
        isBallLive: Bool,
        playerPosition: CGPoint,
        difficulty: TennisDifficulty,
        dt: CGFloat
    ) -> Bool {
        opponent.swingCooldown = max(0, opponent.swingCooldown - TimeInterval(dt))
        opponent.diveTimer = max(0, opponent.diveTimer - TimeInterval(dt))
        opponent.celebrateTimer = max(0, opponent.celebrateTimer - TimeInterval(dt))

        let moveSpeed: CGFloat = (difficulty == .pro) ? 255.0 : 178.0
        let reachRadius: CGFloat = (difficulty == .pro) ? 52.0 : 44.0

        guard isBallLive else {
            // Drift back to center baseline ready position
            moveToward(opponent: &opponent, target: CGPoint(x: 0, y: 195), speed: moveSpeed * 0.75, dt: dt)
            return false
        }

        // When ball is heading toward Westie (top half, vy > 0 or on Westie's side)
        if ball.lastHitter == .player {
            let predicted = TennisPhysics.predictLandingPoint(for: ball)
            let targetY = min(max(predicted.y + 18, 54), TennisCourtMetrics.halfLength + 24)
            let targetX = min(max(predicted.x, -TennisCourtMetrics.halfWidth - 28), TennisCourtMetrics.halfWidth + 28)

            let distToPredicted = hypot(targetX - opponent.x, targetY - opponent.y)
            let effectiveSpeed: CGFloat
            if distToPredicted > 95 && opponent.diveTimer <= 0 && abs(ball.y - opponent.y) < 95 {
                // Dive lunge to save wide ball!
                opponent.diveTimer = 0.34
                effectiveSpeed = moveSpeed * 1.48
            } else {
                effectiveSpeed = moveSpeed
            }

            moveToward(opponent: &opponent, target: CGPoint(x: targetX, y: targetY), speed: effectiveSpeed, dt: dt)

            // Check strike window when ball is on Westie's half and low enough to hit
            let planarDist = hypot(ball.x - opponent.x, ball.y - opponent.y)
            if ball.y > 14,
               ball.z <= 58,
               planarDist <= reachRadius,
               opponent.swingCooldown <= 0
            {
                opponent.swingCooldown = 0.42

                // Pick clever return target away from player!
                let openCornerX: CGFloat = (playerPosition.x >= 0)
                    ? CGFloat.random(in: -148 ... -55)
                    : CGFloat.random(in: 55 ... 148)
                let jitterX: CGFloat = (difficulty == .pro) ? CGFloat.random(in: -12...12) : CGFloat.random(in: -35...35)
                let aimX = min(max(openCornerX + jitterX, -156), 156)

                let shotKind: TennisShotKind
                let aimY: CGFloat
                let roll = Double.random(in: 0...1)
                if difficulty == .pro && playerPosition.y < -185 && roll < 0.25 {
                    shotKind = .dropShot
                    aimY = -68
                } else if playerPosition.y > -95 && roll < 0.32 {
                    shotKind = .highLob
                    aimY = -215
                } else {
                    shotKind = (difficulty == .pro && roll < 0.45) ? .chargedTopspin : .flatDrive
                    aimY = CGFloat.random(in: -215 ... -125)
                }

                ball = TennisPhysics.makeShot(
                    from: (opponent.x, opponent.y, max(ball.z, 18)),
                    hitter: .westie,
                    target: CGPoint(x: aimX, y: aimY),
                    kind: shotKind,
                    chargeRatio: (difficulty == .pro) ? 0.65 : 0.25
                )
                return true
            }
        } else {
            // Recover toward center-top after hitting
            let recoveryY: CGFloat = (difficulty == .pro) ? 182 : 200
            moveToward(opponent: &opponent, target: CGPoint(x: ball.x * 0.22, y: recoveryY), speed: moveSpeed * 0.72, dt: dt)
        }

        return false
    }

    private static func moveToward(opponent: inout WestieOpponentState, target: CGPoint, speed: CGFloat, dt: CGFloat) {
        let dx = target.x - opponent.x
        let dy = target.y - opponent.y
        let dist = hypot(dx, dy)
        guard dist > 2.0 else {
            opponent.lastStepDX = 0
            return
        }
        let stepDist = min(dist, speed * dt)
        let stepX = (dx / dist) * stepDist
        opponent.x += stepX
        opponent.y += (dy / dist) * stepDist
        opponent.lastStepDX = stepX
        if abs(dx) > 3.0 {
            opponent.facingDirection = dx >= 0 ? 1.0 : -1.0
        }
    }
}
