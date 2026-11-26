import CoreGraphics
import Foundation

public enum PetSpecies: String, CaseIterable, Identifiable, Sendable {
    case westie = "westie"
    case goldenCat = "goldenCat"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .westie: return "🐶 西高地小狗"
        case .goldenCat: return "🐱 金渐层小猫"
        }
    }

    public var shortName: String {
        switch self {
        case .westie: return "西高地"
        case .goldenCat: return "金渐层"
        }
    }

    public var filePrefix: String {
        switch self {
        case .westie: return "westie_"
        case .goldenCat: return "cat_"
        }
    }
}

public enum TopClimbRoutine: String, CaseIterable, Identifiable, Sendable {
    case classicStory = "classicStory"
    case flashStep = "flashStep"
    case random = "random"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .classicStory: return "🐾 悠闲巡逻 (跳走+张望+打哈欠)"
        case .flashStep: return "⚡ 闪身步 (起势→右闪→停→准备→左闪)"
        case .random: return "🎲 随机轮换"
        }
    }

    public var shortLabel: String {
        switch self {
        case .classicStory: return "悠闲巡逻"
        case .flashStep: return "闪身步"
        case .random: return "随机轮换"
        }
    }
}

public enum PerchZone: String, Equatable, Sendable {
    case windowTop = "windowTop"
    case windowRightPeek = "windowRightPeek"
    case screenRightPeek = "screenRightPeek"
}

public enum PerchPreference: String, CaseIterable, Sendable {
    case auto = "屏幕右侧边 + 定时爬顶 (默认)"
    case windowTop = "优先窗口正上方"
    case rightPeek = "跟随窗口右侧边"
}

public enum TopTapPose: String, CaseIterable, Identifiable, Sendable {
    case sitSmile = "sitSmile"
    case loafCalm = "loafCalm"
    case bigHeadPeek = "bigHeadPeek"
    case sleep = "sleep"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .sitSmile: return "😊 微笑歪头坐"
        case .loafCalm: return "🐾 安静趴卧"
        case .bigHeadPeek: return "🐶 大头趴窗盯镜头"
        case .sleep: return "💤 团成团子睡觉"
        }
    }

    public static let defaultSelection: [TopTapPose] = [.sitSmile, .loafCalm, .bigHeadPeek]
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

public enum StealthDestination: Equatable, Sendable {
    case windowTop(targetX: CGFloat, climbToGreet: Bool, routineOverride: TopClimbRoutine? = nil)
    case windowRightPeek(targetY: CGFloat)
    case screenRightPeek(targetY: CGFloat)

    public var perchZone: PerchZone {
        switch self {
        case .windowTop: return .windowTop
        case .windowRightPeek: return .windowRightPeek
        case .screenRightPeek: return .screenRightPeek
        }
    }
}

public enum StealthPhase: Equatable, Sendable {
    case retracting(elapsed: TimeInterval, duration: TimeInterval)
    case hiddenTraverse(elapsed: TimeInterval, duration: TimeInterval)
    case tentativePeek(elapsed: TimeInterval, duration: TimeInterval)
    case settlingOut(elapsed: TimeInterval, duration: TimeInterval)
}

public struct PendingWindowSwitch: Equatable, Sendable {
    public let targetWindowID: UInt32
    public var elapsed: TimeInterval
}

public enum FlashStepBeat: Equatable, Sendable {
    case stance(elapsed: TimeInterval, duration: TimeInterval)
    case dodgeRight(elapsed: TimeInterval, duration: TimeInterval, startX: CGFloat, targetX: CGFloat)
    case stopMid(elapsed: TimeInterval, duration: TimeInterval)
    case readyLeft(elapsed: TimeInterval, duration: TimeInterval)
    case dodgeLeft(elapsed: TimeInterval, duration: TimeInterval, startX: CGFloat, targetX: CGFloat)
    case finishStop(elapsed: TimeInterval, duration: TimeInterval)
}

public enum TopStoryStep: Equatable, Sendable {
    /// Brief calm landing beat after climbing onto top edge (already facing left!)
    case postClimbPause(elapsed: TimeInterval, duration: TimeInterval)
    /// Playful bouncy puppy hops going LEFT (`hopsRemaining` little parabolic bounds)
    case hopLeft(hopsRemaining: Int, hopElapsed: TimeInterval, hopDuration: TimeInterval, restElapsed: TimeInterval, startX: CGFloat, targetX: CGFloat)
    /// Stop and look around curiously left & right before heading back
    case lookAroundPause(elapsed: TimeInterval, duration: TimeInterval)
    /// Calm 4-frame quadruped stroll going RIGHT
    case walkRight(remaining: TimeInterval)
    /// Brief stop after walking right before sitting down
    case postWalkPause(elapsed: TimeInterval, duration: TimeInterval)
    /// Viral bipedal "闪身步" dance (`起势 → 往右闪 → 停 → 准备 → 再往左闪 → 停`, `roundsRemaining` cycles!)
    case flashStep(roundsRemaining: Int, beat: FlashStepBeat)
    /// Smiling warmly at the camera (`westieSitTilt`) with spaced, gentle head sways
    case smileSit(elapsed: TimeInterval, duration: TimeInterval)
    /// Quiet 2.5s stillness ("owner is busy...") before yawning
    case preYawnWait(elapsed: TimeInterval, duration: TimeInterval)
}

public enum CompanionBehaviorState: Equatable, Sendable {
    case idle(remaining: TimeInterval)
    case walking(direction: CGFloat, remaining: TimeInterval)
    case sitCalm(remaining: TimeInterval)
    case loafing(remaining: TimeInterval)
    case chinRest(remaining: TimeInterval)
    case sleeping(remaining: TimeInterval)
    case peekingRight(remaining: TimeInterval)
    case greetingOnTop(remaining: TimeInterval)
    case topStory(step: TopStoryStep)
    case yawning(elapsed: TimeInterval, duration: TimeInterval)
    case settlingToSleep(elapsed: TimeInterval, duration: TimeInterval)
    case tuckedWaiting(elapsed: TimeInterval, duration: TimeInterval, originZone: PerchZone)
    case stealthTransition(
        phase: StealthPhase,
        originZone: PerchZone,
        destination: StealthDestination,
        originWindowID: UInt32,
        destWindowID: UInt32
    )
    case gliding(elapsed: TimeInterval, duration: TimeInterval, from: CGPoint, to: CGPoint, targetZone: PerchZone)
    case dragged
    case holdingTennisBall(remaining: TimeInterval)
    case chasingTreat(treatX: CGFloat)
    case eatingTreat(elapsed: TimeInterval, duration: TimeInterval)

    public var isGrounded: Bool {
        switch self {
        case .gliding, .dragged, .stealthTransition, .tuckedWaiting:
            return false
        default:
            return true
        }
    }

    public var isHighFrameRateNeeded: Bool {
        switch self {
        case .walking, .gliding, .dragged, .chasingTreat, .eatingTreat, .stealthTransition, .tuckedWaiting, .greetingOnTop,
             .topStory, .yawning, .settlingToSleep:
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

        // Calm office-friendly distribution: full-body cohesive poses only (loafing, sitting, sleeping, slow strolling)
        if context.isCodingActive {
            if randomUnit < 0.36 {
                return .loafing(remaining: Double.random(in: 10.0...18.0))
            } else if randomUnit < 0.64 {
                return .sitCalm(remaining: Double.random(in: 7.0...12.0))
            } else if randomUnit < 0.88 {
                return .sleeping(remaining: Double.random(in: 14.0...22.0))
            } else {
                let dir = preferredWalkDirection(currentX: currentX, platform: platform)
                return .walking(direction: dir, remaining: Double.random(in: 2.0...3.8))
            }
        }

        if randomUnit < 0.28 {
            let dir = preferredWalkDirection(currentX: currentX, platform: platform)
            return .walking(direction: dir, remaining: Double.random(in: 2.4...4.4))
        } else if randomUnit < 0.56 {
            return .loafing(remaining: Double.random(in: 9.0...15.0))
        } else if randomUnit < 0.78 {
            return .sitCalm(remaining: Double.random(in: 6.5...11.0))
        } else if randomUnit < 0.88 {
            return .idle(remaining: Double.random(in: 4.5...7.5))
        } else {
            return .sleeping(remaining: Double.random(in: 12.0...20.0))
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
