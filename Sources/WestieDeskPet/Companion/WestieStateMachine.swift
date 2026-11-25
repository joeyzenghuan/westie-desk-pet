import CoreGraphics
import Foundation

public enum PerchZone: String, Equatable, Sendable {
    case windowTop = "windowTop"
    case windowRightPeek = "windowRightPeek"
    case screenRightPeek = "screenRightPeek"
}

public enum PerchPreference: String, CaseIterable, Sendable {
    case auto = "自动切换 (正上方 + 右侧)"
    case windowTop = "优先窗口正上方"
    case rightPeek = "优先右侧探头"
}

/// Second-order damped harmonic oscillator used for silky Squash & Stretch, peek overshoot, and pendulum swing.
public struct DampedSpring: Sendable, Equatable {
    public var value: CGFloat
    public var velocity: CGFloat
    public var target: CGFloat
    public var stiffness: CGFloat
    public var damping: CGFloat

    public init(
        value: CGFloat = 0,
        velocity: CGFloat = 0,
        target: CGFloat = 0,
        stiffness: CGFloat = 260,
        damping: CGFloat = 18
    ) {
        self.value = value
        self.velocity = velocity
        self.target = target
        self.stiffness = stiffness
        self.damping = damping
    }

    public mutating func step(dt: TimeInterval) {
        let clampedDt = min(max(CGFloat(dt), 0.0005), 0.05)
        let substeps = clampedDt > 0.014 ? 2 : 1
        let h = clampedDt / CGFloat(substeps)
        for _ in 0..<substeps {
            let accel = (target - value) * stiffness - velocity * damping
            velocity += accel * h
            value += velocity * h
        }
        if isSettled {
            value = target
            velocity = 0
        }
    }

    public mutating func impulse(_ dv: CGFloat) {
        velocity += dv
    }

    public mutating func snap(to newValue: CGFloat) {
        value = newValue
        target = newValue
        velocity = 0
    }

    public var isSettled: Bool {
        abs(target - value) < 0.0015 && abs(velocity) < 0.008
    }
}

public enum CompanionBehaviorState: Equatable, Sendable {
    case idle(remaining: TimeInterval)
    case walking(direction: CGFloat, remaining: TimeInterval)
    case sitCalm(remaining: TimeInterval)
    case loafing(remaining: TimeInterval)
    case chinRest(remaining: TimeInterval)
    case sleeping(remaining: TimeInterval)
    case peekingRight(remaining: TimeInterval)
    case gliding(elapsed: TimeInterval, duration: TimeInterval, from: CGPoint, to: CGPoint, targetZone: PerchZone)
    case dragged
    case holdingTennisBall(remaining: TimeInterval)
    case chasingTreat(treatX: CGFloat)

    public var isGrounded: Bool {
        switch self {
        case .gliding, .dragged:
            return false
        default:
            return true
        }
    }

    public var isHighFrameRateNeeded: Bool {
        switch self {
        case .walking, .gliding, .dragged, .chasingTreat:
            return true
        case .idle, .sitCalm, .loafing, .chinRest, .sleeping, .peekingRight, .holdingTennisBall:
            return false
        }
    }
}

public struct CompanionContext: Sendable {
    public let isMeetingActive: Bool
    public let isCodingActive: Bool
    public let forceQuietSleep: Bool
    public let shouldOfferTennisBreak: Bool

    public init(
        isMeetingActive: Bool = false,
        isCodingActive: Bool = false,
        forceQuietSleep: Bool = false,
        shouldOfferTennisBreak: Bool = false
    ) {
        self.isMeetingActive = isMeetingActive
        self.isCodingActive = isCodingActive
        self.forceQuietSleep = forceQuietSleep
        self.shouldOfferTennisBreak = shouldOfferTennisBreak
    }
}

public enum WestieBehaviorPlanner {
    /// Chooses the next calm, non-intrusive grounded behavior on the active window's top edge.
    public static func chooseNextTopBehavior(
        currentX: CGFloat,
        platform: WindowPlatform,
        context: CompanionContext,
        randomUnit: Double = Double.random(in: 0...1)
    ) -> CompanionBehaviorState {
        if context.forceQuietSleep || context.isMeetingActive {
            return .sleeping(remaining: 24.0)
        }

        if context.shouldOfferTennisBreak {
            return .holdingTennisBall(remaining: 22.0)
        }

        // Calm office-friendly distribution: mostly loafing, chin-resting, sitting quietly, or slow strolling
        if context.isCodingActive {
            if randomUnit < 0.28 {
                return .loafing(remaining: Double.random(in: 9.0...16.0))
            } else if randomUnit < 0.52 {
                return .chinRest(remaining: Double.random(in: 7.0...13.0))
            } else if randomUnit < 0.74 {
                return .sitCalm(remaining: Double.random(in: 6.0...11.0))
            } else if randomUnit < 0.88 {
                return .sleeping(remaining: Double.random(in: 12.0...20.0))
            } else {
                let dir = preferredWalkDirection(currentX: currentX, platform: platform)
                return .walking(direction: dir, remaining: Double.random(in: 2.0...3.8))
            }
        }

        if randomUnit < 0.26 {
            let dir = preferredWalkDirection(currentX: currentX, platform: platform)
            return .walking(direction: dir, remaining: Double.random(in: 2.4...4.4))
        } else if randomUnit < 0.48 {
            return .loafing(remaining: Double.random(in: 8.0...14.0))
        } else if randomUnit < 0.68 {
            return .chinRest(remaining: Double.random(in: 6.5...11.0))
        } else if randomUnit < 0.86 {
            return .idle(remaining: Double.random(in: 4.5...8.0))
        } else {
            return .sleeping(remaining: Double.random(in: 10.0...18.0))
        }
    }

    public static func preferredWalkDirection(currentX: CGFloat, platform: WindowPlatform) -> CGFloat {
        let leftRoom = currentX - platform.minX
        let rightRoom = platform.maxX - currentX
        if leftRoom < 42 { return 1.0 }
        if rightRoom < 42 { return -1.0 }
        return Bool.random() ? 1.0 : -1.0
    }
}
