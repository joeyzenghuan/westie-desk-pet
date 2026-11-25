import CoreGraphics
import Foundation

public enum CompanionBehaviorState: Equatable, Sendable {
    case idle(remaining: TimeInterval)
    case walking(direction: CGFloat, remaining: TimeInterval)
    case sitHeadTilt(remaining: TimeInterval)
    case sleeping(remaining: TimeInterval)
    case jumping(elapsed: TimeInterval, duration: TimeInterval, start: CGPoint, velocity: CGVector)
    case falling(velocity: CGVector)
    case petted(remaining: TimeInterval)
    case dragged
    case holdingTennisBall(remaining: TimeInterval)
    case chasingTreat(treatX: CGFloat)

    public var isGrounded: Bool {
        switch self {
        case .jumping, .falling, .dragged:
            return false
        default:
            return true
        }
    }

    public var isHighFrameRateNeeded: Bool {
        switch self {
        case .walking, .jumping, .falling, .dragged, .petted, .chasingTreat:
            return true
        case .idle, .sitHeadTilt, .sleeping, .holdingTennisBall:
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
    /// Chooses the next autonomous grounded behavior when a timer finishes.
    public static func chooseNextBehavior(
        currentX: CGFloat,
        platform: WindowPlatform,
        context: CompanionContext,
        randomUnit: Double = Double.random(in: 0...1)
    ) -> CompanionBehaviorState {
        if context.forceQuietSleep || context.isMeetingActive {
            return .sleeping(remaining: 18.0)
        }

        if context.shouldOfferTennisBreak {
            return .holdingTennisBall(remaining: 22.0)
        }

        // During coding, Westie is calmer: sits/tilts head or naps more often, walks gently
        if context.isCodingActive {
            if randomUnit < 0.34 {
                return .sitHeadTilt(remaining: 6.5)
            } else if randomUnit < 0.58 {
                return .idle(remaining: 5.5)
            } else if randomUnit < 0.78 {
                return .sleeping(remaining: 12.0)
            } else {
                let dir = preferredWalkDirection(currentX: currentX, platform: platform)
                return .walking(direction: dir, remaining: Double.random(in: 2.2...4.2))
            }
        }

        // Normal lively desktop companion distribution
        if randomUnit < 0.38 {
            let dir = preferredWalkDirection(currentX: currentX, platform: platform)
            return .walking(direction: dir, remaining: Double.random(in: 2.5...5.0))
        } else if randomUnit < 0.64 {
            return .idle(remaining: Double.random(in: 3.0...5.5))
        } else if randomUnit < 0.85 {
            return .sitHeadTilt(remaining: Double.random(in: 4.0...6.5))
        } else {
            return .sleeping(remaining: Double.random(in: 9.0...15.0))
        }
    }

    public static func preferredWalkDirection(currentX: CGFloat, platform: WindowPlatform) -> CGFloat {
        let leftRoom = currentX - platform.minX
        let rightRoom = platform.maxX - currentX
        if leftRoom < 48 { return 1.0 }
        if rightRoom < 48 { return -1.0 }
        return Bool.random() ? 1.0 : -1.0
    }
}
