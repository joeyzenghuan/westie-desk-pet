#if canImport(Testing)
import CoreGraphics
import Testing
@testable import WestieDeskPetCore

@Suite("2.5D Tennis Physics & AI")
struct TennisPhysicsTests {
    @Test("Topspin shot clears the net and bounces inside opponent court")
    func shotClearsNetAndLandsInBounds() {
        var ball = TennisPhysics.makeShot(
            from: (x: 20, y: -205, z: 24),
            hitter: .player,
            target: CGPoint(x: -90, y: 175),
            kind: .chargedTopspin,
            chargeRatio: 0.8
        )

        var bouncedInWestieCourt = false
        var finalOutcome: PointOutcome = .ongoing

        for _ in 0..<240 {
            let res = TennisPhysics.stepBall(ball: &ball, dt: 1.0 / 60.0)
            if res.outcome != .ongoing {
                finalOutcome = res.outcome
                break
            }
            if res.bounced && ball.y > 0 {
                bouncedInWestieCourt = true
                break
            }
        }

        #expect(ball.hasCrossedNet)
        #expect(bouncedInWestieCourt)
        #expect(finalOutcome == .ongoing)
    }

    @Test("Drop shot brakes horizontal speed sharply after first bounce")
    func dropShotBackspinBraking() {
        var ball = TennisPhysics.makeShot(
            from: (x: 0, y: -120, z: 24),
            hitter: .player,
            target: CGPoint(x: 40, y: 55),
            kind: .dropShot,
            chargeRatio: 0.2
        )

        let preBounceSpeed = hypot(ball.vx, ball.vy)
        var postBounceSpeed: CGFloat?

        for _ in 0..<180 {
            let res = TennisPhysics.stepBall(ball: &ball, dt: 1.0 / 60.0)
            if res.bounced {
                postBounceSpeed = hypot(ball.vx, ball.vy)
                break
            }
        }

        #expect(postBounceSpeed != nil)
        #expect((postBounceSpeed ?? preBounceSpeed) < preBounceSpeed * 0.65)
    }

    @Test("Double bounce awards winner to last hitter")
    func doubleBounceAwardsPoint() {
        var ball = TennisPhysics.makeShot(
            from: (x: 0, y: -190, z: 26),
            hitter: .player,
            target: CGPoint(x: 0, y: 140),
            kind: .flatDrive,
            chargeRatio: 0.4
        )

        var outcome: PointOutcome = .ongoing
        for _ in 0..<400 {
            let res = TennisPhysics.stepBall(ball: &ball, dt: 1.0 / 60.0)
            if res.outcome != .ongoing {
                outcome = res.outcome
                break
            }
        }

        #expect(outcome == .pointWon(by: .player, reason: "落地得分 Winner!") ||
                outcome == .pointWon(by: .player, reason: "穿越制胜球 Ace/Winner!"))
    }

    @Test("Westie AI tracks incoming shot and returns it across the net")
    func westieAIReturnsIncomingBall() {
        var ball = TennisPhysics.makeShot(
            from: (x: 0, y: -200, z: 24),
            hitter: .player,
            target: CGPoint(x: 35, y: 170),
            kind: .flatDrive,
            chargeRatio: 0.3
        )
        var opponent = WestieOpponentState()
        opponent.x = 0
        opponent.y = 195

        var didReturn = false
        for _ in 0..<240 {
            let dt: CGFloat = 1.0 / 60.0
            _ = TennisPhysics.stepBall(ball: &ball, dt: dt)
            if WestieTennisAI.step(
                opponent: &opponent,
                ball: &ball,
                isBallLive: true,
                playerPosition: CGPoint(x: 0, y: -205),
                difficulty: .pro,
                dt: dt
            ) {
                didReturn = true
                break
            }
        }

        #expect(didReturn)
        #expect(ball.lastHitter == .westie)
        #expect(ball.vy < 0)
    }
}
#endif
