import AppKit
import SpriteKit

@MainActor
public final class CompanionController {
    public let rootNode = SKNode()

    private let cropNode = SKCropNode()
    private let cropMaskNode: SKSpriteNode
    private let fadeOutSprite: SKSpriteNode
    private let dogSprite: SKSpriteNode
    private let shadowNode: SKShapeNode
    private let inviteBadgeNode: SKNode
    private var treatNode: SKSpriteNode?

    public let preferences: CompanionPreferences
    private let ownPID: Int32

    public private(set) var perchZone: PerchZone = .windowTop
    public private(set) var currentPlatform: WindowPlatform?
    public private(set) var currentRightAnchor: RightEdgeAnchor?
    public private(set) var state: CompanionBehaviorState = .idle(remaining: 4.0)
    public private(set) var pendingWindowSwitch: PendingWindowSwitch?

    public var perchPreference: PerchPreference {
        get { preferences.perchPreference }
        set { preferences.perchPreference = newValue }
    }

    public var forceQuietSleep: Bool = false {
        didSet {
            if forceQuietSleep {
                if perchZone == .windowTop {
                    state = .sleeping(remaining: 35.0)
                }
            } else if case .sleeping = state {
                state = .loafing(remaining: 8.0)
            }
        }
    }

    public var onRequestStartTennis: (() -> Void)?

    public static let dragStartThreshold: CGFloat = 4.0

    public private(set) var position: CGPoint = CGPoint(x: 520, y: 420)
    private var facingDirection: CGFloat = 1.0
    private var walkAnimTimer: TimeInterval = 0
    private var walkFrameIndex: Int = 0
    private var currentWalkSpeed: CGFloat = 0

    private static let bearShakeFrames: [SpriteAssetKey] = [
        .westieBearShake1, .westieBearShake2, .westieBearShake3, .westieBearShake4,
        .westieBearShake5, .westieBearShake6, .westieBearShake7, .westieBearShake8
    ]
    private static let bearShakeDurations: [TimeInterval] = [
        0.16, 0.15, 0.24, 0.16, 0.18, 0.14, 0.24, 0.15
    ]
    private static let bearShakeOffsets: [CGFloat] = [
        7.0, 9.0, 10.0, 0.0, -9.0, -10.0, -8.0, 1.0
    ]

    private static let wandererKickFrames: [SpriteAssetKey] = [
        .westieWandererKick1, .westieWandererKick2, .westieWandererKick3,
        .westieWandererKick4, .westieWandererKick5, .westieWandererKick6
    ]
    private static let wandererKickDurations: [TimeInterval] = [
        0.24, 0.30, 0.48, 0.10, 0.74, 0.24
    ]

    private static let bellyRollIdleTimeout: TimeInterval = 10.0

    // Exact 5-tilt cascade from `歪头杀.gif`:
    // tongue-out sit -> deep Left (-34°) -> center -> Right (+20°) -> center pause
    // -> deep Left (-34°) -> center -> Right 2-stage (+20° -> +33°) -> fast whip -> Hero Left (-36°) -> calm center!
    private static let headTiltSequence: [(key: SpriteAssetKey, duration: TimeInterval)] = [
        (.westieHeadTilt1, 0.36),
        (.westieHeadTilt3, 0.42),
        (.westieHeadTilt2, 0.09),
        (.westieHeadTilt4, 0.38),
        (.westieHeadTilt2, 0.34),
        (.westieHeadTilt3, 0.42),
        (.westieHeadTilt2, 0.08),
        (.westieHeadTilt4, 0.18),
        (.westieHeadTilt5, 0.36),
        (.westieHeadTilt2, 0.07),
        (.westieHeadTilt6, 0.72),
        (.westieHeadTilt2, 0.28)
    ]

    private static let walkCycleFrames: [SpriteAssetKey] = [
        .westieWalk1, .westieWalk2, .westieWalk3, .westieWalk4
    ]
    private var breathPhase: CGFloat = 0
    private var hoverWavePhase: CGFloat = 0
    private var greetingPhase: CGFloat = 0
    private var greetingTotalDuration: TimeInterval = 10.0
    private var didGreetingPerkHop: Bool = false
    private var lastEatBiteIndex: Int = -1

    // Smooth pose cross-fade layer (eliminates jarring 1-frame texture pops on top bar!)
    private var displayedSpriteKey: SpriteAssetKey = .westieIdle
    private var displayedSpriteSpecies: PetSpecies = .westie
    private var retractTopSpriteKey: SpriteAssetKey = .westieSitTilt
    private var retractTopSpriteSize: CGSize = CGSize(width: 66, height: 66)
    private var poseCrossfadeElapsed: TimeInterval = 0
    private var poseCrossfadeDuration: TimeInterval = 0

    // Hover, shy-retreat, & tactile press/drag tracking
    public private(set) var isHoveringDog: Bool = false
    public private(set) var isPointerDownOnDog: Bool = false
    public private(set) var shyRetreatTimer: TimeInterval = 0
    private var greetingHoverAccumulator: TimeInterval = 0
    private var isPeekHoverTextureActive: Bool = false
    private var pressStartScenePoint: CGPoint = .zero
    private var dragGrabOffset: CGPoint = .zero
    private var dragBlendProgress: CGFloat = 0
    private var lastDragScenePoint: CGPoint = .zero
    private var smoothedDragVelocityX: CGFloat = 0

    // Second-order damped springs for silky organic feel
    private var peekHoverSpring = DampedSpring(value: 0, velocity: 0, target: 0, stiffness: 235, damping: 17.5)
    private var peekEmergeSpring = DampedSpring(value: 0, velocity: 0, target: 0, stiffness: 195, damping: 18.5)
    private var squashSpring = DampedSpring(value: 0, velocity: 0, target: 0, stiffness: 320, damping: 15.5)
    private var tapHopSpring = DampedSpring(value: 0, velocity: 0, target: 0, stiffness: 340, damping: 16.5)
    private var swingRotationSpring = DampedSpring(value: 0, velocity: 0, target: 0, stiffness: 190, damping: 13.5)

    // Active window & edge offset tracking
    public private(set) var trackedWindowID: UInt32 = 0
    private var lastTrackedWindowFrame: CGRect?
    private var offsetFromWindowMinX: CGFloat = 240
    private var offsetFromWindowMaxY: CGFloat = 88
    private var screenRightCustomYRatio: CGFloat = 0.66
    private var zoneStayTimer: TimeInterval = 0
    public private(set) var rightPeekDwellTimer: TimeInterval = 0
    public private(set) var topBarEffectTimer: TimeInterval = 0
    private var lastAutoTopEffect: TopBarEffect?

    // Focus timer -> gently hold tennis ball after 25 minutes of work
    private var focusAccumulator: TimeInterval = 0
    private let focusInviteInterval: TimeInterval = 25 * 60

    private var scaleFactor: CGFloat { CGFloat(preferences.dogScale) }
    private var topDogSize: CGSize { CGSize(width: 66 * scaleFactor, height: 66 * scaleFactor) }
    private var flashStepDogSize: CGSize { CGSize(width: 99 * scaleFactor, height: 66 * scaleFactor) }
    private var yawnDogSize: CGSize { CGSize(width: 54 * scaleFactor, height: 54 * scaleFactor) }
    private var chinLedgeDogSize: CGSize { CGSize(width: 48 * scaleFactor, height: 48 * scaleFactor) }
    private var topPeekDogSize: CGSize { CGSize(width: 48 * scaleFactor, height: 48 * scaleFactor) }
    private var peekDogSize: CGSize { CGSize(width: 76 * scaleFactor, height: 76 * scaleFactor) }

    public var isNeedingHighFPS: Bool {
        state.isHighFrameRateNeeded
            || treatNode != nil
            || isHoveringDog
            || isPointerDownOnDog
            || shyRetreatTimer > 0
            || poseCrossfadeDuration > 0
            || !peekHoverSpring.isSettled
            || !peekEmergeSpring.isSettled
            || !squashSpring.isSettled
            || !tapHopSpring.isSettled
            || !swingRotationSpring.isSettled
    }

    public init(
        preferences: CompanionPreferences = .shared,
        ownPID: Int32 = ProcessInfo.processInfo.processIdentifier
    ) {
        self.preferences = preferences
        self.ownPID = ownPID

        shadowNode = SKShapeNode(ellipseOf: CGSize(width: 42, height: 9))
        shadowNode.fillColor = .clear
        shadowNode.strokeColor = .clear
        shadowNode.isHidden = true
        shadowNode.zPosition = 1

        cropMaskNode = SKSpriteNode(color: .white, size: CGSize(width: 4096, height: 4096))
        cropMaskNode.anchorPoint = CGPoint(x: 0.0, y: 0.5)

        let initScale = CGFloat(preferences.dogScale)
        let initTopSize = CGSize(width: 66 * initScale, height: 66 * initScale)
        let initSpecies = preferences.petSpecies
        self.displayedSpriteSpecies = initSpecies

        fadeOutSprite = SKSpriteNode(
            texture: SpriteBank.shared.texture(for: .westieIdle, species: initSpecies),
            color: .clear,
            size: initTopSize
        )
        fadeOutSprite.anchorPoint = CGPoint(x: 0.5, y: 0.04)
        fadeOutSprite.zPosition = 2.9
        fadeOutSprite.alpha = 0
        fadeOutSprite.isHidden = true

        dogSprite = SKSpriteNode(
            texture: SpriteBank.shared.texture(for: .westieIdle, species: initSpecies),
            color: .clear,
            size: initTopSize
        )
        dogSprite.anchorPoint = CGPoint(x: 0.5, y: 0.04)
        dogSprite.zPosition = 3

        inviteBadgeNode = CompanionController.buildInviteBadge()
        inviteBadgeNode.position = CGPoint(x: 0, y: 78)
        inviteBadgeNode.zPosition = 10
        inviteBadgeNode.isHidden = true

        rootNode.addChild(shadowNode)
        cropNode.zPosition = 3
        cropNode.addChild(fadeOutSprite)
        cropNode.addChild(dogSprite)
        rootNode.addChild(cropNode)
        rootNode.addChild(inviteBadgeNode)
    }

    private static func buildInviteBadge() -> SKNode {
        let container = SKNode()
        let bg = SKShapeNode(rectOf: CGSize(width: 118, height: 28), cornerRadius: 9)
        bg.fillColor = NSColor(calibratedRed: 0.11, green: 0.38, blue: 0.24, alpha: 0.94)
        bg.strokeColor = NSColor(calibratedRed: 0.78, green: 0.98, blue: 0.30, alpha: 0.95)
        bg.lineWidth = 1.5
        container.addChild(bg)

        let label = SKLabelNode(fontNamed: "Menlo-Bold")
        label.text = "🎾 来打网球!"
        label.fontSize = 12
        label.fontColor = .white
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        container.addChild(label)
        return container
    }

    public func placeInitially(snapshot: ActiveWorkspaceSnapshot, sceneSize: CGSize) {
        pendingWindowSwitch = nil
        rightPeekDwellTimer = 0
        let layout = snapshot.perchLayout
        trackedWindowID = layout.activeWindowID ?? 0

        if layout.isFullScreenMode {
            snapToScreenRightPeek(layout.screenRightPeek, sceneSize: sceneSize)
        } else {
            switch perchPreference {
            case .auto:
                // Default: rest peacefully on the screen's right bezel (zero app-window edge intrusion!)
                snapToScreenRightPeek(layout.screenRightPeek, sceneSize: sceneSize)
            case .windowTop:
                if let top = layout.topPerch {
                    let startX = top.clampedX(top.minX + top.width * 0.62, margin: 22)
                    landOnWindowTop(top, atX: startX)
                } else {
                    snapToScreenRightPeek(layout.screenRightPeek, sceneSize: sceneSize)
                }
            case .rightPeek:
                if let right = layout.windowRightPeek {
                    snapToWindowRightPeek(right, windowMaxY: layout.activeWindowFrame?.maxY ?? right.maxY)
                } else {
                    snapToScreenRightPeek(layout.screenRightPeek, sceneSize: sceneSize)
                }
            }
        }
        syncVisuals(dt: 0)
    }

    /// Tight interactive hitbox in scene coordinates matching Westie's visible silhouette!
    /// Uses compact entry width on right-edge peek (28*k) expanding to 44*k once hovered so Westie never peeks prematurely.
    public func interactiveHitRect() -> CGRect {
        // Never intercept mouse clicks while hidden behind a window during stealth traverse or early occlusion tuck
        switch state {
        case .stealthTransition(let phase, _, _, _, _):
            if case .hiddenTraverse = phase { return .zero }
            if case .retracting(let elapsed, let dur) = phase, elapsed >= dur * 0.72 { return .zero }
        case .tuckedWaiting(let elapsed, let dur, _):
            if elapsed >= dur * 0.55 { return .zero }
        default:
            break
        }

        let k = scaleFactor
        var rect: CGRect
        if case .dragged = state {
            rect = CGRect(x: position.x - 42 * k, y: position.y - 16 * k, width: 84 * k, height: 84 * k)
        } else {
            switch perchZone {
            case .windowTop:
                rect = CGRect(
                    x: position.x - 36 * k,
                    y: position.y - 4,
                    width: 72 * k,
                    height: 68 * k
                )
            case .screenRightPeek:
                // Tight trigger when calm (28*k ≈ visible head width), comfortable hysteresis when waving (44*k),
                // extending past position.x + 12 so cursor slammed against screen bezel always hits!
                let reach: CGFloat = (isHoveringDog || peekHoverSpring.value > 0.25) ? (44 * k) : (28 * k)
                let halfH: CGFloat = (isHoveringDog || peekHoverSpring.value > 0.25) ? (36 * k) : (30 * k)
                rect = CGRect(
                    x: position.x - reach,
                    y: position.y - halfH,
                    width: reach + 12,
                    height: halfH * 2
                )
            case .windowRightPeek:
                let reach: CGFloat = (isHoveringDog || peekHoverSpring.value > 0.25) ? (44 * k) : (28 * k)
                let halfH: CGFloat = (isHoveringDog || peekHoverSpring.value > 0.25) ? (36 * k) : (30 * k)
                rect = CGRect(
                    x: position.x - 2,
                    y: position.y - halfH,
                    width: reach + 2,
                    height: halfH * 2
                )
            }
        }

        if !inviteBadgeNode.isHidden {
            let badgePos = inviteBadgeNode.position
            let badgeRect = CGRect(
                x: badgePos.x - 66,
                y: badgePos.y - 20,
                width: 132,
                height: 40
            )
            rect = rect.union(badgeRect)
        }
        return rect
    }

    public func isPointOnInviteBadge(_ scenePoint: CGPoint) -> Bool {
        guard !inviteBadgeNode.isHidden else { return false }
        let badgePos = inviteBadgeNode.position
        let badgeRect = CGRect(
            x: badgePos.x - 66,
            y: badgePos.y - 20,
            width: 132,
            height: 40
        )
        return badgeRect.contains(scenePoint)
    }

    // MARK: - User & Menu Actions

    public func prepareForContextMenu() {
        shyRetreatTimer = 0
        isPointerDownOnDog = false
    }

    public func triggerTennisInvite() {
        state = .holdingTennisBall(remaining: 25.0)
    }

    public func summonToFrontWindow(snapshot: ActiveWorkspaceSnapshot, sceneSize: CGSize) {
        let layout = snapshot.perchLayout
        pendingWindowSwitch = nil
        rightPeekDwellTimer = 0
        treatNode?.removeFromParent()
        treatNode = nil
        trackedWindowID = layout.activeWindowID ?? 0

        if layout.isFullScreenMode {
            snapToScreenRightPeek(layout.screenRightPeek, sceneSize: sceneSize)
            return
        }
        switch perchPreference {
        case .auto:
            snapToScreenRightPeek(layout.screenRightPeek, sceneSize: sceneSize)
        case .windowTop:
            if let top = layout.topPerch {
                let x = top.clampedX(top.minX + top.width * 0.62, margin: 22)
                landOnWindowTop(top, atX: x)
                state = .sitCalm(remaining: 5.0)
            } else {
                snapToScreenRightPeek(layout.screenRightPeek, sceneSize: sceneSize)
            }
        case .rightPeek:
            if let right = layout.windowRightPeek {
                snapToWindowRightPeek(right, windowMaxY: layout.activeWindowFrame?.maxY ?? right.maxY)
            } else {
                snapToScreenRightPeek(layout.screenRightPeek, sceneSize: sceneSize)
            }
        }
    }

    public func moveImmediatelyToZone(_ targetZone: PerchZone, snapshot: ActiveWorkspaceSnapshot, sceneSize: CGSize) {
        pendingWindowSwitch = nil
        rightPeekDwellTimer = 0
        topBarEffectTimer = 0
        let layout = snapshot.perchLayout
        switch targetZone {
        case .windowTop:
            if let top = layout.topPerch {
                let x = top.clampedX(top.minX + top.width * 0.62, margin: 22)
                beginStealthClimbToTop(
                    targetX: x,
                    windowID: layout.activeWindowID ?? trackedWindowID,
                    effectOnArrival: nil
                )
            }
        case .windowRightPeek:
            if let right = layout.windowRightPeek {
                emergeIntoRightPeek(
                    anchor: right,
                    targetY: right.clampedY(position.y),
                    zone: .windowRightPeek,
                    layout: layout
                )
            } else {
                emergeIntoRightPeek(
                    anchor: layout.screenRightPeek,
                    targetY: layout.screenRightPeek.clampedY(position.y),
                    zone: .screenRightPeek,
                    layout: layout
                )
            }
        case .screenRightPeek:
            let y = layout.screenRightPeek.clampedY(position.y)
            emergeIntoRightPeek(
                anchor: layout.screenRightPeek,
                targetY: y,
                zone: .screenRightPeek,
                layout: layout
            )
        }
    }

    /// Triggers an independent top-bar effect (`patrol`, `flashStep`, or `yawnSleep`) on demand.
    /// If perched on the right edge, climbs onto the active window's top bar first;
    /// if resting in the initial head-on-ledge peek pose, rises smoothly onto all four paws first!
    public func triggerTopBarEffect(
        _ effect: TopBarEffect,
        snapshot: ActiveWorkspaceSnapshot,
        sceneSize: CGSize
    ) {
        pendingWindowSwitch = nil
        rightPeekDwellTimer = 0
        topBarEffectTimer = 0
        treatNode?.removeFromParent()
        treatNode = nil

        guard let top = snapshot.perchLayout.topPerch else { return }
        let activeWinID = snapshot.perchLayout.activeWindowID ?? trackedWindowID

        if perchZone == .windowTop && trackedWindowID == activeWinID {
            currentPlatform = top
            if case .chinRest = state {
                facingDirection = -1.0
                state = .topStory(step: .risingToFullBody(elapsed: 0, duration: 0.62, nextEffect: effect))
            } else {
                startTopBarEffect(effect, on: top)
            }
        } else {
            let targetX = top.clampedX(top.maxX - min(110, top.width * 0.26), margin: 22)
            beginStealthClimbToTop(targetX: targetX, windowID: activeWinID, effectOnArrival: effect)
        }
    }

    private func startTopBarEffect(_ effect: TopBarEffect, on top: WindowPlatform) {
        topBarEffectTimer = 0
        currentWalkSpeed = 0
        lastAutoTopEffect = effect
        switch effect {
        case .patrol:
            facingDirection = -1.0
            state = .topStory(step: .postClimbPause(elapsed: 0, duration: 0.35))

        case .flashStep:
            facingDirection = 1.0
            let desiredDist = min(30.0 * scaleFactor, max(14.0, top.width * 0.08))
            let safeOriginX = top.clampedX(max(position.x, top.minX + desiredDist + 26.0), margin: 26.0)
            let maxLeftRoom = max(12.0, safeOriginX - (top.minX + 24.0))
            let travelDist = min(desiredDist, maxLeftRoom)
            position = CGPoint(x: safeOriginX, y: top.y)
            offsetFromWindowMinX = safeOriginX - top.windowMinX
            state = .topStory(step: .flashStep(
                roundsRemaining: 2,
                originX: safeOriginX,
                travelDist: travelDist,
                beat: .holdStart(elapsed: 0, duration: 0.14)
            ))

        case .bearShake:
            facingDirection = 1.0
            let marginX: CGFloat = max(28.0, 14.0 * scaleFactor + 18.0)
            let safeOriginX = top.clampedX(position.x, margin: marginX)
            position = CGPoint(x: safeOriginX, y: top.y)
            offsetFromWindowMinX = safeOriginX - top.windowMinX
            state = .topStory(step: .bearShake(
                cyclesRemaining: 2,
                originX: safeOriginX,
                frameIndex: 0,
                elapsed: 0
            ))

        case .wandererKick:
            facingDirection = 1.0
            let safeX = top.clampedX(position.x, margin: 26.0)
            position = CGPoint(x: safeX, y: top.y)
            offsetFromWindowMinX = safeX - top.windowMinX
            state = .topStory(step: .wandererKick(
                roundsRemaining: 2,
                mirrorSign: 1.0,
                frameIndex: 0,
                elapsed: 0
            ))

        case .headTilt:
            facingDirection = 1.0
            let safeX = top.clampedX(position.x, margin: 22.0)
            position = CGPoint(x: safeX, y: top.y)
            offsetFromWindowMinX = safeX - top.windowMinX
            state = .topStory(step: .headTilt(stepIndex: 0, elapsed: 0))

        case .windowRoll:
            facingDirection = 1.0
            let safeX = top.clampedX(position.x, margin: 26.0)
            position = CGPoint(x: safeX, y: top.y)
            offsetFromWindowMinX = safeX - top.windowMinX
            state = .topStory(step: .bellyRoll(
                phase: .flopDown(elapsed: 0, duration: 0.24),
                sideSign: 1.0
            ))

        case .yawnSleep:
            facingDirection = 1.0
            state = .yawning(elapsed: 0, duration: 1.85)
        }
    }

    public func dropBoneTreat(snapshot: ActiveWorkspaceSnapshot, sceneSize: CGSize) {
        let layout = snapshot.perchLayout
        guard let top = layout.topPerch else {
            // In fullscreen / right-peek mode, give a springy happy peek wave without cluttering screen
            peekHoverSpring.impulse(3.2)
            squashSpring.impulse(2.0)
            return
        }

        if perchZone != .windowTop || trackedWindowID != layout.activeWindowID {
            let startX = top.clampedX(top.minX + top.width * 0.62, margin: 24)
            landOnWindowTop(top, atX: startX)
        }

        treatNode?.removeFromParent()
        let treatX: CGFloat
        if top.width > 140 {
            let candidate = (position.x < top.midX) ? min(top.maxX - 28, position.x + 110) : max(top.minX + 28, position.x - 110)
            treatX = top.clampedX(candidate, margin: 24)
        } else {
            treatX = top.midX
        }

        let treatTex = SpriteBank.shared.texture(for: .boneTreat, species: preferences.petSpecies)
        let treatDim: CGFloat = 28.0 * scaleFactor
        let node = SKSpriteNode(texture: treatTex)
        node.size = CGSize(width: treatDim, height: treatDim)
        node.position = CGPoint(x: treatX, y: top.y + treatDim * 0.48)
        node.zPosition = 2
        rootNode.addChild(node)
        // Lively double-bounce drop onto the top edge!
        node.run(SKAction.sequence([
            SKAction.moveBy(x: 0, y: 18, duration: 0.0),
            SKAction.moveBy(x: 0, y: -18, duration: 0.14),
            SKAction.moveBy(x: 0, y: 7, duration: 0.08),
            SKAction.moveBy(x: 0, y: -7, duration: 0.08)
        ]))
        treatNode = node
        squashSpring.impulse(1.8)
        state = .chasingTreat(treatX: treatX)
    }

    private func spawnSnackCrumbs(finalSparkle: Bool = false) {
        let k = scaleFactor
        let mouthX = position.x + (facingDirection >= 0 ? 14.0 : -14.0) * k
        let mouthY = position.y + 18.0 * k
        let crumbColor = preferences.petSpecies.isCat
            ? NSColor(calibratedRed: 0.88, green: 0.67, blue: 0.36, alpha: 0.95)
            : NSColor(calibratedRed: 0.96, green: 0.91, blue: 0.78, alpha: 0.95)

        let count = finalSparkle ? 5 : 3
        for _ in 0..<count {
            let sz = CGFloat.random(in: 2.5...4.5) * max(0.85, k * 0.85)
            let crumb = SKSpriteNode(color: crumbColor, size: CGSize(width: sz, height: sz))
            crumb.position = CGPoint(x: mouthX, y: mouthY)
            crumb.zPosition = 6
            rootNode.addChild(crumb)

            let vx = CGFloat.random(in: -22...22) * k
            let vy = CGFloat.random(in: 12...26) * k
            let dur = TimeInterval.random(in: 0.28...0.42)
            let flyUp = SKAction.moveBy(x: vx * 0.55, y: vy, duration: dur * 0.45)
            flyUp.timingMode = .easeOut
            let fallDown = SKAction.moveBy(x: vx * 0.45, y: -(vy + 10 * k), duration: dur * 0.55)
            fallDown.timingMode = .easeIn
            let seq = SKAction.group([
                SKAction.sequence([flyUp, fallDown]),
                SKAction.sequence([SKAction.wait(forDuration: dur * 0.5), SKAction.fadeOut(withDuration: dur * 0.5)])
            ])
            crumb.run(SKAction.sequence([seq, SKAction.removeFromParent()]))
        }

        if finalSparkle {
            let note = SKLabelNode(fontNamed: "Menlo-Bold")
            note.text = preferences.petSpecies.isCat ? "🐟✨" : "🦴✨"
            note.fontSize = 13 * max(0.9, k * 0.85)
            note.position = CGPoint(x: position.x, y: position.y + 52 * k)
            note.zPosition = 7
            rootNode.addChild(note)
            let rise = SKAction.moveBy(x: 0, y: 18 * k, duration: 0.55)
            rise.timingMode = .easeOut
            note.run(SKAction.sequence([
                SKAction.group([rise, SKAction.fadeOut(withDuration: 0.55)]),
                SKAction.removeFromParent()
            ]))
        }
    }

    /// Updates continuous hover & shy-retreat state with pointer speed awareness and zero intrusive popups!
    public func setHovering(_ hovering: Bool, pointerSpeed: CGFloat = 0, nearZone: Bool = false) {
        if preferences.shyRetreatEnabled,
           !isPointerDownOnDog,
           state != .dragged,
           (hovering || nearZone),
           pointerSpeed >= 580.0
        {
            // Fast mouse sweep past Westie -> shy micro-retreat out of the cursor's path (anti-misclick!)
            shyRetreatTimer = 0.45
            isHoveringDog = false
            peekHoverSpring.target = -0.35
            if perchZone == .windowTop && state.isGrounded {
                squashSpring.target = -0.07
            }
            return
        }

        if hovering && pointerSpeed < 240.0 {
            shyRetreatTimer = 0
            if perchZone == .windowTop && !isPointerDownOnDog {
                squashSpring.target = 0
            }
        }

        if shyRetreatTimer > 0 {
            isHoveringDog = false
            return
        }

        guard isHoveringDog != hovering else { return }
        isHoveringDog = hovering
        peekHoverSpring.target = hovering ? 1.0 : 0.0
        if hovering {
            if perchZone == .screenRightPeek || perchZone == .windowRightPeek {
                squashSpring.impulse(1.2)
            } else if state.isGrounded {
                // Top bar: gentle tactile spring nudge only — never swaps sprites or wakes sleeping dog!
                if case .sleeping = state {
                    // Stay peacefully asleep on hover
                } else {
                    squashSpring.impulse(0.45)
                }
            }
        }
    }

    public func handleMouseDown(at scenePoint: CGPoint) -> Bool {
        if isPointOnInviteBadge(scenePoint) {
            onRequestStartTennis?()
            return true
        }
        if case .holdingTennisBall = state, interactiveHitRect().contains(scenePoint) {
            onRequestStartTennis?()
            return true
        }
        guard interactiveHitRect().insetBy(dx: -4, dy: -4).contains(scenePoint) else { return false }

        // Record exact grab offset WITHOUT teleporting Westie! Drag only begins past 4pt threshold.
        isPointerDownOnDog = true
        pressStartScenePoint = scenePoint
        lastDragScenePoint = scenePoint
        dragGrabOffset = CGPoint(x: position.x - scenePoint.x, y: position.y - scenePoint.y)
        dragBlendProgress = 0
        smoothedDragVelocityX = 0
        squashSpring.target = -0.11
        return true
    }

    public func handleMouseDragged(to scenePoint: CGPoint) {
        guard isPointerDownOnDog else { return }

        if state != .dragged {
            let movedDist = hypot(scenePoint.x - pressStartScenePoint.x, scenePoint.y - pressStartScenePoint.y)
            guard movedDist >= Self.dragStartThreshold else { return }

            // Crossed drag threshold -> smoothly lift Westie by the scruff!
            state = .dragged
            treatNode?.removeFromParent()
            treatNode = nil
            squashSpring.target = 0
            squashSpring.impulse(2.3)
        }

        let dx = scenePoint.x - lastDragScenePoint.x
        lastDragScenePoint = scenePoint

        smoothedDragVelocityX = smoothedDragVelocityX * 0.62 + (dx * 60.0) * 0.38
        swingRotationSpring.target = min(max(-smoothedDragVelocityX * 0.00055, -0.30), 0.30)

        if abs(dx) > 1.2 {
            facingDirection = dx > 0 ? 1.0 : -1.0
        }

        // Smoothly ease grab anchor from exact click point toward natural scruff hold (zero frame-1 snap!)
        dragBlendProgress = min(1.0, dragBlendProgress + 0.14)
        let naturalScruffOffset = CGPoint(x: 0, y: -22)
        let blendedOffset = CGPoint(
            x: dragGrabOffset.x + (naturalScruffOffset.x - dragGrabOffset.x) * dragBlendProgress,
            y: dragGrabOffset.y + (naturalScruffOffset.y - dragGrabOffset.y) * dragBlendProgress
        )
        position = CGPoint(x: scenePoint.x + blendedOffset.x, y: scenePoint.y + blendedOffset.y)
    }

    /// Seamlessly carries an active scruff-drag onto a new monitor's local scene coordinate space!
    public func continueDragOnNewScreen(at newScenePoint: CGPoint) {
        guard isPointerDownOnDog || state == .dragged else { return }
        isPointerDownOnDog = true
        state = .dragged
        pendingWindowSwitch = nil
        currentPlatform = nil
        currentRightAnchor = nil
        trackedWindowID = 0
        treatNode?.removeFromParent()
        treatNode = nil
        dragGrabOffset = CGPoint(x: 0, y: -22)
        dragBlendProgress = 1.0
        lastDragScenePoint = newScenePoint
        smoothedDragVelocityX = 0
        swingRotationSpring.target = 0
        position = CGPoint(x: newScenePoint.x, y: newScenePoint.y - 22)
        syncVisuals(dt: 0)
    }

    public func handleMouseUp(at scenePoint: CGPoint, snapshot: ActiveWorkspaceSnapshot?, sceneSize: CGSize) {
        guard isPointerDownOnDog || state == .dragged else { return }
        let wasDragging = (state == .dragged)
        isPointerDownOnDog = false
        squashSpring.target = 0
        swingRotationSpring.target = 0
        smoothedDragVelocityX = 0

        // Tap / Gentle Pet (< 4pt movement): respond with a lively tactile spring bounce instead of dropping!
        if !wasDragging {
            handleGentleTap()
            return
        }

        guard let layout = snapshot?.perchLayout else {
            state = .idle(remaining: 5.0)
            return
        }

        // Snap cleanly to whichever valid perch is closest to where the user dropped Westie!
        if layout.isFullScreenMode {
            let anchor = layout.screenRightPeek
            let clampedY = anchor.clampedY(scenePoint.y)
            if sceneSize.height > 100 {
                screenRightCustomYRatio = min(max(clampedY / sceneSize.height, 0.15), 0.88)
            }
            beginSmoothGlide(to: CGPoint(x: anchor.edgeX, y: clampedY), targetZone: .screenRightPeek, layout: layout)
            return
        }

        // Check distance to valid perches (screen right edge + active window top; window right edge only if opted-in)
        var candidates: [(dist: CGFloat, point: CGPoint, zone: PerchZone)] = []

        if let top = layout.topPerch {
            let targetX = top.clampedX(scenePoint.x, margin: 20)
            let pt = CGPoint(x: targetX, y: top.y)
            candidates.append((hypot(scenePoint.x - pt.x, scenePoint.y - pt.y), pt, .windowTop))
        }
        if perchPreference == .rightPeek, let right = layout.windowRightPeek {
            let targetY = right.clampedY(scenePoint.y)
            let pt = CGPoint(x: right.edgeX, y: targetY)
            candidates.append((hypot(scenePoint.x - pt.x, scenePoint.y - pt.y), pt, .windowRightPeek))
        }
        do {
            let anchor = layout.screenRightPeek
            let clampedY = anchor.clampedY(scenePoint.y)
            let pt = CGPoint(x: anchor.edgeX, y: clampedY)
            candidates.append((hypot(scenePoint.x - pt.x, scenePoint.y - pt.y), pt, .screenRightPeek))
        }

        if let best = candidates.min(by: { $0.dist < $1.dist }) {
            if best.zone == .windowRightPeek, let winMaxY = layout.activeWindowFrame?.maxY {
                offsetFromWindowMaxY = max(42, winMaxY - best.point.y)
            } else if best.zone == .screenRightPeek, sceneSize.height > 100 {
                screenRightCustomYRatio = min(max(best.point.y / sceneSize.height, 0.15), 0.88)
            }
            beginSmoothGlide(to: best.point, targetZone: best.zone, layout: layout)
        } else {
            let anchor = layout.screenRightPeek
            beginSmoothGlide(to: CGPoint(x: anchor.edgeX, y: anchor.defaultY), targetZone: .screenRightPeek, layout: layout)
        }
    }

    private func currentTopTapPose() -> TopTapPose? {
        switch state {
        case .sitCalm: return .sitSmile
        case .loafing: return .loafCalm
        case .chinRest: return .bigHeadPeek
        case .sleeping: return .sleep
        default: return nil
        }
    }

    private func applyTopTapPose(_ pose: TopTapPose) {
        facingDirection = 1.0
        switch pose {
        case .sitSmile:
            state = .sitCalm(remaining: 14.0)
        case .loafCalm:
            state = .loafing(remaining: 16.0)
        case .bigHeadPeek:
            state = .chinRest(remaining: 14.0)
        case .sleep:
            state = .sleeping(remaining: 35.0)
        }
    }

    private func handleGentleTap() {
        // 1. Right-edge peek mode: playful spring wiggle in place
        if perchZone == .screenRightPeek || perchZone == .windowRightPeek {
            peekHoverSpring.impulse(3.0)
            squashSpring.impulse(2.1)
            return
        }

        // 1b. Interactive Belly-Up Roll-Over (`翻肚皮打滚`):
        //     Clicking while lying belly-up flips the pet smoothly onto the OTHER side and resets the 10s timer!
        if case .topStory(step: .bellyRoll(let phase, let sideSign)) = state {
            switch phase {
            case .waitingBellyUp, .flopDown:
                let nextSide: CGFloat = -sideSign
                let nudge: CGFloat = nextSide * 10.0 * scaleFactor
                let startX = position.x
                let targetX = currentPlatform?.clampedX(startX + nudge, margin: 24.0) ?? startX
                squashSpring.impulse(1.8)
                spawnBellyRubSparkle()
                state = .topStory(step: .bellyRoll(
                    phase: .rollingOver(
                        elapsed: 0,
                        duration: 0.56,
                        fromSide: sideSign,
                        toSide: nextSide,
                        startX: startX,
                        targetX: targetX
                    ),
                    sideSign: nextSide
                ))
                return
            case .rollingOver:
                // Already mid-roll; give a cute extra bounce without double-canceling!
                squashSpring.impulse(1.2)
                return
            case .standingUp:
                break
            }
        }

        // 2. Top-bar unified tap interaction ("摸摸头"):
        //    Cycles cleanly through the user's selected `topTapEnabledPoses` (default: sitSmile -> loafCalm -> bigHeadPeek)!
        greetingHoverAccumulator = 0
        currentWalkSpeed = 0

        if forceQuietSleep {
            squashSpring.impulse(1.4)
            return
        }

        let enabled = preferences.orderedEnabledTopTapPoses
        let nextPose: TopTapPose
        if let current = currentTopTapPose(),
           let idx = enabled.firstIndex(of: current)
        {
            nextPose = enabled[(idx + 1) % enabled.count]
        } else if case .sleeping = state {
            // If sleeping isn't in the user's enabled list, wake into the first awake enabled pose!
            nextPose = enabled.first(where: { $0 != .sleep }) ?? enabled[0]
        } else {
            nextPose = enabled[0]
        }

        tapHopSpring.impulse(nextPose == .sleep ? 75.0 : 125.0)
        squashSpring.impulse(nextPose == .sleep ? 1.5 : 2.3)
        applyTopTapPose(nextPose)
    }

    // MARK: - Frame Update

    public func update(dt: TimeInterval, snapshot: ActiveWorkspaceSnapshot, sceneSize: CGSize) {
        let clampedDt = min(max(dt, 0.001), 0.08)
        breathPhase += CGFloat(clampedDt) * 2.2
        zoneStayTimer += clampedDt

        // Decay shy-retreat timer from fast cursor sweeps
        if shyRetreatTimer > 0 {
            shyRetreatTimer = max(0, shyRetreatTimer - clampedDt)
            if shyRetreatTimer == 0 && !isPointerDownOnDog && state != .dragged {
                squashSpring.target = 0
            }
        }

        updateWindowMotionInertia(snapshot: snapshot, dt: clampedDt)

        // Step all physical springs
        if shyRetreatTimer > 0 {
            peekHoverSpring.target = -0.35
        } else {
            peekHoverSpring.target = isHoveringDog ? 1.0 : 0.0
        }
        peekHoverSpring.step(dt: clampedDt)
        peekEmergeSpring.step(dt: clampedDt)
        squashSpring.step(dt: clampedDt)
        tapHopSpring.step(dt: clampedDt)
        if state != .dragged {
            smoothedDragVelocityX *= 0.78
        }
        swingRotationSpring.step(dt: clampedDt)

        // Hysteresis on peek texture swap avoids rapid edge flicker
        if peekHoverSpring.value >= 0.44 {
            isPeekHoverTextureActive = true
        } else if peekHoverSpring.value <= 0.28 {
            isPeekHoverTextureActive = false
        }

        if peekHoverSpring.value > 0.04 {
            hoverWavePhase += CGFloat(clampedDt)
        } else {
            hoverWavePhase = 0
        }

        if !snapshot.isMeetingActive && !forceQuietSleep {
            focusAccumulator += clampedDt
        }

        reconcileWithActiveWindow(snapshot: snapshot, sceneSize: sceneSize, dt: clampedDt)

        let shouldInvite = focusAccumulator >= focusInviteInterval
        if shouldInvite {
            focusAccumulator = 0
        }
        let context = CompanionContext(
            isMeetingActive: snapshot.isMeetingActive,
            isCodingActive: snapshot.isCodingActive,
            forceQuietSleep: forceQuietSleep,
            shouldOfferTennisBreak: shouldInvite
        )

        stepState(dt: clampedDt, snapshot: snapshot, context: context, sceneSize: sceneSize)
        syncVisuals(dt: clampedDt)
    }

    private func updateWindowMotionInertia(snapshot: ActiveWorkspaceSnapshot, dt: TimeInterval) {
        let curFrame = snapshot.windowFramesByID[trackedWindowID]
            ?? ((snapshot.perchLayout.activeWindowID == trackedWindowID) ? snapshot.perchLayout.activeWindowFrame : nil)
        defer {
            lastTrackedWindowFrame = curFrame
        }
        guard state != .dragged,
              let prevFrame = lastTrackedWindowFrame,
              let curFrame,
              dt > 0.0005
        else {
            if state != .dragged {
                swingRotationSpring.target = 0
            }
            return
        }

        let winVelX = (curFrame.minX - prevFrame.minX) / CGFloat(dt)
        if abs(winVelX) > 8.0 {
            // Subtle inertial lean while riding on a user-dragged window!
            swingRotationSpring.target = min(max(-winVelX * 0.00015, -0.085), 0.085)
        } else {
            swingRotationSpring.target = 0
        }
    }

    // MARK: - Active Window Dwell Debounce, Occlusion Guard & Stealthy Transitions

    /// Resolves the destination on `newLayout` according to user perch preference:
    /// - `.auto` (default): quiet screen right bezel at the closest vertical height `Y` (zero window-edge intrusion!)
    /// - `.windowTop`: active window's top bar at closest `X`
    /// - `.rightPeek`: active window's right border at exact same `Y`
    public func resolveShortestPathDestination(
        from previousPosition: CGPoint,
        newLayout: ActiveWindowPerchLayout,
        sceneSize: CGSize
    ) -> StealthDestination {
        if newLayout.isFullScreenMode {
            let y = newLayout.screenRightPeek.clampedY(previousPosition.y)
            return .screenRightPeek(targetY: y)
        }

        switch perchPreference {
        case .auto:
            let y = newLayout.screenRightPeek.clampedY(previousPosition.y)
            return .screenRightPeek(targetY: y)

        case .windowTop:
            if let top = newLayout.topPerch {
                return .windowTop(targetX: top.clampedX(previousPosition.x, margin: 22), effectOnArrival: nil)
            }
            return .screenRightPeek(targetY: newLayout.screenRightPeek.clampedY(previousPosition.y))

        case .rightPeek:
            if let right = newLayout.windowRightPeek {
                return .windowRightPeek(targetY: right.clampedY(previousPosition.y))
            }
            return .screenRightPeek(targetY: newLayout.screenRightPeek.clampedY(previousPosition.y))
        }
    }

    private func currentVisibleSpriteRect() -> CGRect {
        let k = scaleFactor
        switch perchZone {
        case .windowTop:
            return CGRect(x: position.x - 28 * k, y: position.y + 4, width: 56 * k, height: 54 * k)
        case .windowRightPeek:
            return CGRect(x: position.x + 2, y: position.y - 30 * k, width: 46 * k, height: 60 * k)
        case .screenRightPeek:
            return CGRect(x: position.x - 50 * k, y: position.y - 30 * k, width: 48 * k, height: 60 * k)
        }
    }

    private func anchorPositionToWindowLayout(_ layout: ActiveWindowPerchLayout, sceneSize: CGSize) {
        switch perchZone {
        case .windowTop:
            if let top = layout.topPerch {
                let desiredX = top.clampedX(top.windowMinX + offsetFromWindowMinX, margin: 18)
                position = CGPoint(x: desiredX, y: top.y)
                currentPlatform = top
                if let treat = treatNode {
                    treat.position.y = top.y + 13
                    treat.position.x = top.clampedX(treat.position.x, margin: 20)
                }
            } else if perchPreference == .rightPeek, let right = layout.windowRightPeek {
                treatNode?.removeFromParent()
                treatNode = nil
                emergeIntoRightPeek(anchor: right, targetY: right.clampedY(position.y), zone: .windowRightPeek, layout: layout)
            } else {
                treatNode?.removeFromParent()
                treatNode = nil
                let anchor = layout.screenRightPeek
                let targetY = anchor.clampedY(position.y)
                if sceneSize.height > 100 {
                    screenRightCustomYRatio = min(max(targetY / sceneSize.height, 0.15), 0.88)
                }
                emergeIntoRightPeek(anchor: anchor, targetY: targetY, zone: .screenRightPeek, layout: layout)
            }

        case .windowRightPeek:
            if let right = layout.windowRightPeek {
                let winMaxY = layout.activeWindowFrame?.maxY ?? right.maxY
                let desiredY = right.clampedY(winMaxY - offsetFromWindowMaxY)
                position = CGPoint(x: right.edgeX, y: desiredY)
                currentRightAnchor = right
            } else if let top = layout.topPerch {
                let x = top.clampedX(top.minX + top.width * 0.65, margin: 20)
                beginStealthClimbToTop(targetX: x, windowID: layout.activeWindowID ?? trackedWindowID, effectOnArrival: nil)
            } else {
                snapToScreenRightPeek(layout.screenRightPeek, sceneSize: sceneSize)
            }

        case .screenRightPeek:
            let anchor = layout.screenRightPeek
            position = CGPoint(x: anchor.edgeX, y: anchor.clampedY(sceneSize.height * screenRightCustomYRatio))
            currentRightAnchor = anchor
        }
    }

    private func reconcileWithActiveWindow(snapshot: ActiveWorkspaceSnapshot, sceneSize: CGSize, dt: TimeInterval) {
        if case .dragged = state { return }
        if case .gliding = state { return }
        if case .stealthTransition = state { return }

        let layout = snapshot.perchLayout

        // 1. Fullscreen Space or maximized window -> duck smoothly in place behind the rising window,
        //    then emerge cleanly at the user's comfortable screen-right height (never jammed into the menu bar clock!)
        if layout.isFullScreenMode {
            pendingWindowSwitch = nil
            rightPeekDwellTimer = 0
            let anchor = layout.screenRightPeek
            let desiredY: CGFloat = (perchZone == .windowTop)
                ? anchor.clampedY(sceneSize.height * screenRightCustomYRatio)
                : anchor.clampedY(position.y)
            if perchZone != .screenRightPeek {
                treatNode?.removeFromParent()
                treatNode = nil
                if perchZone != .windowTop && sceneSize.height > 100 {
                    screenRightCustomYRatio = min(max(desiredY / sceneSize.height, 0.15), 0.88)
                }
                let alreadyHidden: Bool = {
                    if case .tuckedWaiting = state { return true }
                    return false
                }()
                beginStealthTransition(
                    to: .screenRightPeek(targetY: desiredY),
                    destWindowID: layout.activeWindowID ?? 0,
                    skipRetract: alreadyHidden,
                    retractDuration: (perchZone == .windowTop) ? 0.42 : 0.65
                )
            } else {
                currentRightAnchor = anchor
                position = CGPoint(x: anchor.edgeX, y: anchor.clampedY(sceneSize.height * screenRightCustomYRatio))
            }
            return
        }

        // 2. Resting on screen right bezel (default `.auto` mode):
        // Stay calmly on the screen's right edge with zero distraction! Just reset dwell timer if active window changes.
        let activeID = layout.activeWindowID ?? 0
        if perchZone == .screenRightPeek {
            if case .tuckedWaiting = state {
                // Guard: never allow `.tuckedWaiting` to persist on screen-right bezel!
                state = .peekingRight(remaining: 25.0)
                peekEmergeSpring.value = -0.8
                peekEmergeSpring.target = 0
            }
            if perchPreference == .auto {
                if activeID != 0 && activeID != trackedWindowID {
                    trackedWindowID = activeID
                    rightPeekDwellTimer = 0
                }
                pendingWindowSwitch = nil
                anchorPositionToWindowLayout(layout, sceneSize: sceneSize)
                return
            }

            // Explicit `.windowTop` or `.rightPeek` returning from Fullscreen -> stealthily emerge on the active app!
            let hasWindowTarget = (perchPreference == .windowTop && layout.topPerch != nil)
                || (perchPreference == .rightPeek && layout.windowRightPeek != nil)
            if hasWindowTarget {
                pendingWindowSwitch = nil
                rightPeekDwellTimer = 0
                let dest = resolveShortestPathDestination(from: position, newLayout: layout, sceneSize: sceneSize)
                beginStealthTransition(to: dest, destWindowID: activeID, skipRetract: false)
                return
            }
            anchorPositionToWindowLayout(layout, sceneSize: sceneSize)
            return
        }

        // 3. Non-fullscreen active window changed (Westie is on `windowTop` or `windowRightPeek`) ->
        // dwell debounce (default 5s) + early overlap tuck!
        if activeID != 0 && activeID != trackedWindowID {
            let oldWindowStillVisible = (trackedWindowID != 0) && (snapshot.windowFramesByID[trackedWindowID] != nil)

            // Keep Westie locked to the old window while waiting (if still visible)
            if oldWindowStillVisible, let oldLayout = snapshot.perchLayout(forWindowID: trackedWindowID) {
                anchorPositionToWindowLayout(oldLayout, sceneSize: sceneSize)

                // If `anchorPositionToWindowLayout` already fell back to `.screenRightPeek` (e.g. old window moved flush to menu bar),
                // bail out cleanly so we NEVER enter `.tuckedWaiting` on the screen bezel!
                if perchZone == .screenRightPeek {
                    pendingWindowSwitch = nil
                    trackedWindowID = activeID
                    rightPeekDwellTimer = 0
                    return
                }

                // Overlap guard (`tuck_early`): if the newly focused window covers Westie's current spot,
                // duck behind the old window immediately so Westie never floats awkwardly over foreground text!
                if case .tuckedWaiting = state {
                    // Already tucked safely behind the old window
                } else {
                    let occluded = PlatformPhysics.isRectOccludedByFrontWindows(
                        currentVisibleSpriteRect(),
                        ownerWindowID: trackedWindowID,
                        windowsFrontToBack: snapshot.windowsFrontToBack,
                        excludedPID: ownPID
                    )
                    if occluded {
                        treatNode?.removeFromParent()
                        treatNode = nil
                        state = .tuckedWaiting(elapsed: 0, duration: 0.28, originZone: perchZone)
                    }
                }
            }

            if pendingWindowSwitch?.targetWindowID == activeID {
                pendingWindowSwitch?.elapsed += dt
            } else {
                pendingWindowSwitch = PendingWindowSwitch(targetWindowID: activeID, elapsed: 0)
            }

            let delayNeeded = oldWindowStillVisible ? preferences.windowSwitchDelaySeconds : 0.0
            let elapsed = pendingWindowSwitch?.elapsed ?? 0
            if elapsed >= delayNeeded {
                pendingWindowSwitch = nil
                rightPeekDwellTimer = 0
                treatNode?.removeFromParent()
                treatNode = nil

                let skipRetract: Bool = {
                    if !oldWindowStillVisible { return true }
                    if case .tuckedWaiting(let t, let d, _) = state, t >= d * 0.85 { return true }
                    return false
                }()
                let dest = resolveShortestPathDestination(from: position, newLayout: layout, sceneSize: sceneSize)
                beginStealthTransition(to: dest, destWindowID: activeID, skipRetract: skipRetract)
            }
            return
        }

        // 4. Same active window (or user switched back before dwell delay expired!)
        if pendingWindowSwitch != nil {
            pendingWindowSwitch = nil
            // If we had tucked early while user glanced at another window, sneakily peek back out!
            if case .tuckedWaiting(_, _, let originZone) = state {
                let reemergeDest: StealthDestination
                switch originZone {
                case .windowTop:
                    let x = layout.topPerch?.clampedX(position.x, margin: 18) ?? position.x
                    reemergeDest = .windowTop(targetX: x, effectOnArrival: nil)
                case .windowRightPeek:
                    let y = layout.windowRightPeek?.clampedY(position.y) ?? position.y
                    reemergeDest = .windowRightPeek(targetY: y)
                case .screenRightPeek:
                    let y = layout.screenRightPeek.clampedY(position.y)
                    reemergeDest = .screenRightPeek(targetY: y)
                }
                state = .stealthTransition(
                    phase: .tentativePeek(elapsed: 0, duration: 0.44),
                    originZone: originZone,
                    destination: reemergeDest,
                    originWindowID: trackedWindowID,
                    destWindowID: trackedWindowID
                )
                return
            }
        }

        if trackedWindowID == 0 && activeID != 0 {
            trackedWindowID = activeID
        }
        anchorPositionToWindowLayout(layout, sceneSize: sceneSize)
    }

    /// Starts the 4-phase stealthy behind-window transition:
    /// slow retract -> hidden traverse -> two-stage tentative peek -> settle!
    public func beginStealthTransition(
        to destination: StealthDestination,
        destWindowID: UInt32,
        skipRetract: Bool,
        retractDuration: TimeInterval = 0.65
    ) {
        let originZone = perchZone
        let originWinID = trackedWindowID
        if originZone == .windowTop {
            retractTopSpriteKey = displayedSpriteKey
            retractTopSpriteSize = dogSprite.size
        }
        let initialPhase: StealthPhase = skipRetract
            ? .hiddenTraverse(elapsed: 0, duration: 0.24)
            : .retracting(elapsed: 0, duration: retractDuration)
        state = .stealthTransition(
            phase: initialPhase,
            originZone: originZone,
            destination: destination,
            originWindowID: originWinID,
            destWindowID: destWindowID
        )
    }

    /// Pure position-only anchor helper used during stealth transitions — NEVER mutates `state`, `perchZone`,
    /// or teleports Westie to another edge if the origin window suddenly maximizes/fullscreen!
    private func followAnchorDuringStealth(
        zone: PerchZone,
        layout: ActiveWindowPerchLayout,
        sceneSize: CGSize
    ) {
        switch zone {
        case .windowTop:
            if let top = layout.topPerch {
                let desiredX = top.clampedX(top.windowMinX + offsetFromWindowMinX, margin: 18)
                position = CGPoint(x: desiredX, y: top.y)
                currentPlatform = top
            }
            // If `topPerch == nil` (window just maximized / went fullscreen!), keep `position` right in place
            // so Westie smoothly ducks straight down behind the rising window instead of teleporting to the right edge!
        case .windowRightPeek:
            if let right = layout.windowRightPeek {
                let winMaxY = layout.activeWindowFrame?.maxY ?? right.maxY
                let desiredY = right.clampedY(winMaxY - offsetFromWindowMaxY)
                position = CGPoint(x: right.edgeX, y: desiredY)
                currentRightAnchor = right
            }
        case .screenRightPeek:
            let anchor = layout.screenRightPeek
            position = CGPoint(x: anchor.edgeX, y: anchor.clampedY(position.y))
            currentRightAnchor = anchor
        }
    }

    /// Stealthily retracts from the right edge and peeks/climbs onto the active window's top bar!
    /// - `effectOnArrival == nil`: peeks head, looks left & right, and rests in the initial head-on-ledge pose.
    /// - `effectOnArrival != nil`: climbs full-body onto top bar and immediately performs that effect!
    public func beginStealthClimbToTop(
        targetX: CGFloat,
        windowID: UInt32,
        effectOnArrival: TopBarEffect? = nil
    ) {
        let originZone = perchZone
        let originWinID = trackedWindowID
        if originZone == .windowTop {
            retractTopSpriteKey = displayedSpriteKey
            retractTopSpriteSize = dogSprite.size
        }
        let initialPhase: StealthPhase = (originZone == .windowTop)
            ? .hiddenTraverse(elapsed: 0, duration: 0.16)
            : .retracting(elapsed: 0, duration: 0.56)
        state = .stealthTransition(
            phase: initialPhase,
            originZone: originZone,
            destination: .windowTop(targetX: targetX, effectOnArrival: effectOnArrival),
            originWindowID: originWinID,
            destWindowID: windowID
        )
    }

    /// Slides Westie's cute head smoothly out from behind a right window/screen border with spring overshoot (zero pop!).
    private func emergeIntoRightPeek(
        anchor: RightEdgeAnchor,
        targetY: CGFloat,
        zone: PerchZone,
        layout: ActiveWindowPerchLayout
    ) {
        trackedWindowID = layout.activeWindowID ?? trackedWindowID
        let clampedY = anchor.clampedY(targetY)
        if zone == .windowRightPeek {
            let winMaxY = layout.activeWindowFrame?.maxY ?? anchor.maxY
            snapToWindowRightPeek(anchor, windowMaxY: winMaxY, customY: clampedY)
        } else {
            perchZone = .screenRightPeek
            currentPlatform = nil
            currentRightAnchor = anchor
            position = CGPoint(x: anchor.edgeX, y: clampedY)
            zoneStayTimer = 0
            rightPeekDwellTimer = 0
            state = .peekingRight(remaining: 30.0)
        }
        peekEmergeSpring.value = -1.10
        peekEmergeSpring.velocity = 1.5
        peekEmergeSpring.target = 0.0
    }

    private func beginSmoothGlide(to target: CGPoint, targetZone: PerchZone, layout: ActiveWindowPerchLayout) {
        let dist = hypot(target.x - position.x, target.y - position.y)
        trackedWindowID = layout.activeWindowID ?? trackedWindowID
        if dist < 14 {
            finishGlideArrival(at: target, targetZone: targetZone, layout: layout)
            return
        }
        facingDirection = (target.x >= position.x) ? 1.0 : -1.0
        squashSpring.impulse(2.5) // Playful takeoff stretch!
        let duration = min(max(TimeInterval(dist / 880.0), 0.20), 0.40)
        state = .gliding(elapsed: 0, duration: duration, from: position, to: target, targetZone: targetZone)
    }

    private func finishGlideArrival(at target: CGPoint, targetZone: PerchZone, layout: ActiveWindowPerchLayout) {
        zoneStayTimer = 0
        switch targetZone {
        case .windowTop:
            squashSpring.impulse(-3.0) // Tactile landing cushion & bounce!
            if let top = layout.topPerch {
                landOnWindowTop(top, atX: target.x)
            } else {
                perchZone = .windowTop
                position = target
                state = .idle(remaining: 5.0)
            }
        case .windowRightPeek:
            if let right = layout.windowRightPeek {
                emergeIntoRightPeek(anchor: right, targetY: target.y, zone: .windowRightPeek, layout: layout)
            } else {
                perchZone = .windowRightPeek
                position = target
                state = .peekingRight(remaining: 20.0)
            }
        case .screenRightPeek:
            emergeIntoRightPeek(anchor: layout.screenRightPeek, targetY: target.y, zone: .screenRightPeek, layout: layout)
        }
    }

    private func landOnWindowTop(_ platform: WindowPlatform, atX rawX: CGFloat) {
        let x = platform.clampedX(rawX, margin: 18)
        perchZone = .windowTop
        currentPlatform = platform
        currentRightAnchor = nil
        trackedWindowID = platform.windowID
        offsetFromWindowMinX = x - platform.windowMinX
        position = CGPoint(x: x, y: platform.y)
        zoneStayTimer = 0
        topBarEffectTimer = 0
        if forceQuietSleep {
            state = .sleeping(remaining: 25.0)
        } else {
            state = .chinRest(remaining: 60.0)
        }
    }

    private func snapToWindowRightPeek(_ anchor: RightEdgeAnchor, windowMaxY: CGFloat, customY: CGFloat? = nil) {
        let y = anchor.clampedY(customY ?? anchor.defaultY)
        perchZone = .windowRightPeek
        currentPlatform = nil
        currentRightAnchor = anchor
        offsetFromWindowMaxY = max(42, windowMaxY - y)
        position = CGPoint(x: anchor.edgeX, y: y)
        zoneStayTimer = 0
        state = .peekingRight(remaining: Double.random(in: 18.0...28.0))
    }

    private func snapToScreenRightPeek(_ anchor: RightEdgeAnchor, sceneSize: CGSize) {
        let y = anchor.clampedY(sceneSize.height * screenRightCustomYRatio)
        perchZone = .screenRightPeek
        currentPlatform = nil
        currentRightAnchor = anchor
        position = CGPoint(x: anchor.edgeX, y: y)
        zoneStayTimer = 0
        state = .peekingRight(remaining: 30.0)
    }

    // MARK: - Calm Behavior & Stealth State Machine

    private static func easeInOutCubic(_ u: CGFloat) -> CGFloat {
        let t = min(max(u, 0), 1)
        return t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
    }

    private static func easeOutCubic(_ u: CGFloat) -> CGFloat {
        let t = min(max(u, 0), 1)
        return 1 - pow(1 - t, 3)
    }

    private func completeStealthArrival(
        destination: StealthDestination,
        destWindowID: UInt32,
        snapshot: ActiveWorkspaceSnapshot,
        sceneSize: CGSize
    ) {
        let destLayout = snapshot.perchLayout(forWindowID: destWindowID) ?? snapshot.perchLayout
        trackedWindowID = destWindowID != 0 ? destWindowID : (destLayout.activeWindowID ?? trackedWindowID)
        zoneStayTimer = 0
        rightPeekDwellTimer = 0
        greetingHoverAccumulator = 0

        switch destination {
        case .windowTop(let targetX, let effectOnArrival):
            topBarEffectTimer = 0
            if let top = destLayout.topPerch {
                landOnWindowTop(top, atX: targetX)
                if let effect = effectOnArrival, !forceQuietSleep && !snapshot.isMeetingActive {
                    squashSpring.impulse(-1.4)
                    startTopBarEffect(effect, on: top)
                } else if !forceQuietSleep && !snapshot.isMeetingActive {
                    // Default climb-to-top arrival: stay peacefully resting head+paws on top bar looking forward!
                    facingDirection = 1.0
                    state = .chinRest(remaining: 60.0)
                }
            } else {
                perchZone = .windowTop
                state = .chinRest(remaining: 60.0)
            }

        case .windowRightPeek(let targetY):
            if let right = destLayout.windowRightPeek {
                let winMaxY = destLayout.activeWindowFrame?.maxY ?? right.maxY
                snapToWindowRightPeek(right, windowMaxY: winMaxY, customY: targetY)
            } else {
                snapToScreenRightPeek(destLayout.screenRightPeek, sceneSize: sceneSize)
            }

        case .screenRightPeek(let targetY):
            let anchor = destLayout.screenRightPeek
            let clampedY = anchor.clampedY(targetY)
            if sceneSize.height > 100 {
                screenRightCustomYRatio = min(max(clampedY / sceneSize.height, 0.15), 0.88)
            }
            perchZone = .screenRightPeek
            currentPlatform = nil
            currentRightAnchor = anchor
            position = CGPoint(x: anchor.edgeX, y: clampedY)
            state = .peekingRight(remaining: 30.0)
        }
    }

    private func stepState(
        dt: TimeInterval,
        snapshot: ActiveWorkspaceSnapshot,
        context: CompanionContext,
        sceneSize: CGSize
    ) {
        let layout = snapshot.perchLayout

        switch state {
        case .tuckedWaiting(let elapsed, let duration, let originZone):
            // Defensive invariant: `.tuckedWaiting` is ONLY valid while awaiting a pending window switch off-bezel!
            if pendingWindowSwitch == nil || perchZone == .screenRightPeek {
                state = (perchZone == .windowTop) ? .idle(remaining: 5.0) : .peekingRight(remaining: 25.0)
                break
            }
            let next = min(duration, elapsed + dt)
            state = .tuckedWaiting(elapsed: next, duration: duration, originZone: originZone)

        case .stealthTransition(let phase, let originZone, var destination, let originWindowID, let destWindowID):
            switch phase {
            case .retracting(let elapsed, let duration):
                // Follow origin window ONLY if its matching edge still exists — NEVER teleport to another edge mid-retract!
                if let originLayout = snapshot.perchLayout(forWindowID: originWindowID) {
                    followAnchorDuringStealth(zone: originZone, layout: originLayout, sceneSize: sceneSize)
                }
                let next = elapsed + dt
                if next >= duration {
                    state = .stealthTransition(
                        phase: .hiddenTraverse(elapsed: 0, duration: 0.28),
                        originZone: originZone,
                        destination: destination,
                        originWindowID: originWindowID,
                        destWindowID: destWindowID
                    )
                } else {
                    state = .stealthTransition(
                        phase: .retracting(elapsed: next, duration: duration),
                        originZone: originZone,
                        destination: destination,
                        originWindowID: originWindowID,
                        destWindowID: destWindowID
                    )
                }

            case .hiddenTraverse(let elapsed, let duration):
                let next = elapsed + dt
                if next >= duration {
                    // Position invisibly behind the destination window's border before peeking out!
                    let destLayout = snapshot.perchLayout(forWindowID: destWindowID) ?? layout
                    trackedWindowID = destWindowID != 0 ? destWindowID : (destLayout.activeWindowID ?? trackedWindowID)
                    switch destination {
                    case .windowTop(let targetX, let effectOnArrival):
                        if let top = destLayout.topPerch {
                            let clampedX = top.clampedX(targetX, margin: 18)
                            perchZone = .windowTop
                            currentPlatform = top
                            currentRightAnchor = nil
                            offsetFromWindowMinX = clampedX - top.windowMinX
                            position = CGPoint(x: clampedX, y: top.y)
                            destination = .windowTop(targetX: clampedX, effectOnArrival: effectOnArrival)
                        }
                    case .windowRightPeek(let targetY):
                        if let right = destLayout.windowRightPeek {
                            let clampedY = right.clampedY(targetY)
                            let winMaxY = destLayout.activeWindowFrame?.maxY ?? right.maxY
                            perchZone = .windowRightPeek
                            currentPlatform = nil
                            currentRightAnchor = right
                            offsetFromWindowMaxY = max(42, winMaxY - clampedY)
                            position = CGPoint(x: right.edgeX, y: clampedY)
                            destination = .windowRightPeek(targetY: clampedY)
                        } else {
                            let anchor = destLayout.screenRightPeek
                            let clampedY = anchor.clampedY(targetY)
                            perchZone = .screenRightPeek
                            currentPlatform = nil
                            currentRightAnchor = anchor
                            position = CGPoint(x: anchor.edgeX, y: clampedY)
                            destination = .screenRightPeek(targetY: clampedY)
                        }
                    case .screenRightPeek(let targetY):
                        let anchor = destLayout.screenRightPeek
                        let clampedY = anchor.clampedY(targetY)
                        perchZone = .screenRightPeek
                        currentPlatform = nil
                        currentRightAnchor = anchor
                        position = CGPoint(x: anchor.edgeX, y: clampedY)
                        destination = .screenRightPeek(targetY: clampedY)
                    }

                    let useTwoStagePeek: Bool = {
                        if case .windowTop = destination {
                            return preferences.climbPawsPeekEnabled
                        }
                        return true
                    }()

                    if useTwoStagePeek {
                        // Top-bar climb peeks head out for 3.0s and looks left/right before pulling full body up!
                        let peekDur: TimeInterval = (destination.perchZone == .windowTop) ? 3.0 : 0.56
                        state = .stealthTransition(
                            phase: .tentativePeek(elapsed: 0, duration: peekDur),
                            originZone: originZone,
                            destination: destination,
                            originWindowID: originWindowID,
                            destWindowID: destWindowID
                        )
                    } else {
                        state = .stealthTransition(
                            phase: .settlingOut(elapsed: 0, duration: 0.60),
                            originZone: originZone,
                            destination: destination,
                            originWindowID: originWindowID,
                            destWindowID: destWindowID
                        )
                    }
                } else {
                    state = .stealthTransition(
                        phase: .hiddenTraverse(elapsed: next, duration: duration),
                        originZone: originZone,
                        destination: destination,
                        originWindowID: originWindowID,
                        destWindowID: destWindowID
                    )
                }

            case .tentativePeek(let elapsed, let duration):
                // Stay locked to live destination window frame while peeking ears & paws out (pure position-only)!
                if let destLayout = snapshot.perchLayout(forWindowID: destWindowID) {
                    followAnchorDuringStealth(zone: destination.perchZone, layout: destLayout, sceneSize: sceneSize)
                }
                let next = elapsed + dt
                if next >= duration {
                    // If arriving at `windowTop` with NO immediate full-body effect, stay seamlessly in the exact same
                    // head-on-ledge forward pose (ZERO jump / ZERO full-body popup!).
                    if case .windowTop(_, let effectOnArrival) = destination, effectOnArrival == nil {
                        completeStealthArrival(
                            destination: destination,
                            destWindowID: destWindowID,
                            snapshot: snapshot,
                            sceneSize: sceneSize
                        )
                    } else {
                        let settleDur: TimeInterval = (destination.perchZone == .windowTop) ? 0.68 : 0.44
                        state = .stealthTransition(
                            phase: .settlingOut(elapsed: 0, duration: settleDur),
                            originZone: originZone,
                            destination: destination,
                            originWindowID: originWindowID,
                            destWindowID: destWindowID
                        )
                    }
                } else {
                    state = .stealthTransition(
                        phase: .tentativePeek(elapsed: next, duration: duration),
                        originZone: originZone,
                        destination: destination,
                        originWindowID: originWindowID,
                        destWindowID: destWindowID
                    )
                }

            case .settlingOut(let elapsed, let duration):
                if let destLayout = snapshot.perchLayout(forWindowID: destWindowID) {
                    followAnchorDuringStealth(zone: destination.perchZone, layout: destLayout, sceneSize: sceneSize)
                }
                let next = elapsed + dt
                if next >= duration {
                    completeStealthArrival(
                        destination: destination,
                        destWindowID: destWindowID,
                        snapshot: snapshot,
                        sceneSize: sceneSize
                    )
                } else {
                    state = .stealthTransition(
                        phase: .settlingOut(elapsed: next, duration: duration),
                        originZone: originZone,
                        destination: destination,
                        originWindowID: originWindowID,
                        destWindowID: destWindowID
                    )
                }
            }

        case .topStory(let step):
            guard perchZone == .windowTop, let top = currentPlatform else {
                state = .yawning(elapsed: 0, duration: 1.85)
                return
            }

            switch step {
            case .risingToFullBody(let elapsed, let duration, let nextEffect):
                currentWalkSpeed = 0
                let next = elapsed + dt
                if next >= duration {
                    squashSpring.impulse(-1.4)
                    startTopBarEffect(nextEffect, on: top)
                } else {
                    state = .topStory(step: .risingToFullBody(elapsed: next, duration: duration, nextEffect: nextEffect))
                }

            case .postClimbPause(let elapsed, let duration):
                currentWalkSpeed = 0
                facingDirection = -1.0
                let next = elapsed + dt
                if next >= duration {
                    // Launch 3~4 playful bouncy puppy hops leftward!
                    let availLeft = max(0, position.x - (top.minX + 28))
                    let hopStep: CGFloat = min(44.0, max(26.0, availLeft / 3.5))
                    let hopCount = availLeft >= 26 ? max(2, min(4, Int((availLeft / hopStep).rounded()))) : 0
                    if hopCount > 0 {
                        let firstTarget = max(top.minX + 24, position.x - hopStep)
                        state = .topStory(step: .hopLeft(
                            hopsRemaining: hopCount,
                            hopElapsed: 0,
                            hopDuration: 0.56,
                            restElapsed: 0,
                            startX: position.x,
                            targetX: firstTarget
                        ))
                    } else {
                        state = .topStory(step: .lookAroundPause(elapsed: 0, duration: 3.5))
                    }
                } else {
                    state = .topStory(step: .postClimbPause(elapsed: next, duration: duration))
                }

            case .hopLeft(let hopsRemaining, let hopElapsed, let hopDuration, let restElapsed, let startX, let targetX):
                facingDirection = -1.0
                currentWalkSpeed = 0
                if hopElapsed < hopDuration {
                    // Always finish the current airborne hop smoothly (never freeze Westie mid-air on hover!)
                    let nextHop = min(hopDuration, hopElapsed + dt)
                    let u = CGFloat(nextHop / max(hopDuration, 0.01))
                    // Only travel horizontally during the actual airborne window (u: 0.18 -> 0.86)
                    // so paws stay planted during crouch (0..0.18) and landing absorb (0.86..1.0)!
                    let airU = min(max((u - 0.18) / 0.68, 0), 1)
                    let eased = Self.easeOutCubic(airU)
                    let liveX = top.clampedX(startX + (targetX - startX) * eased, margin: 20)
                    position.x = liveX
                    offsetFromWindowMinX = position.x - top.windowMinX
                    if nextHop >= hopDuration {
                        squashSpring.impulse(-1.4) // Soft cushioned paw landing!
                    }
                    state = .topStory(step: .hopLeft(
                        hopsRemaining: hopsRemaining,
                        hopElapsed: nextHop,
                        hopDuration: hopDuration,
                        restElapsed: 0,
                        startX: startX,
                        targetX: targetX
                    ))
                } else {
                    // Only pause politely ON THE GROUND between hops if mouse is resting on Westie
                    if isHoveringDog || isPointerDownOnDog {
                        return
                    }
                    // Brief natural beat (0.14s) between little puppy hops!
                    let nextRest = restElapsed + dt
                    if nextRest >= 0.14 {
                        let remaining = hopsRemaining - 1
                        let availLeft = position.x - (top.minX + 26)
                        if remaining > 0 && availLeft >= 20 {
                            let hopStep = min(44.0, availLeft)
                            let nextTarget = max(top.minX + 24, position.x - hopStep)
                            state = .topStory(step: .hopLeft(
                                hopsRemaining: remaining,
                                hopElapsed: 0,
                                hopDuration: 0.56,
                                restElapsed: 0,
                                startX: position.x,
                                targetX: nextTarget
                            ))
                        } else {
                            // Done hopping left -> stop with stationary body and look RIGHT -> LEFT -> RIGHT!
                            state = .topStory(step: .lookAroundPause(elapsed: 0, duration: 3.5))
                        }
                    } else {
                        state = .topStory(step: .hopLeft(
                            hopsRemaining: hopsRemaining,
                            hopElapsed: hopElapsed,
                            hopDuration: hopDuration,
                            restElapsed: nextRest,
                            startX: startX,
                            targetX: targetX
                        ))
                    }
                }

            case .lookAroundPause(let elapsed, let duration):
                currentWalkSpeed = 0
                // Body stays completely still facing LEFT while ONLY the head looks RIGHT -> LEFT -> RIGHT!
                facingDirection = -1.0
                let next = elapsed + dt
                if next >= duration {
                    facingDirection = 1.0
                    let availRight = max(0, (top.maxX - 28) - position.x)
                    let walkDur = min(max(TimeInterval(min(availRight, 155.0) / 44.0), 1.6), 3.2)
                    state = .topStory(step: .walkRight(remaining: walkDur))
                } else {
                    state = .topStory(step: .lookAroundPause(elapsed: next, duration: duration))
                }

            case .walkRight(let remaining):
                let desiredSpeed: CGFloat = (isHoveringDog || isPointerDownOnDog) ? 0.0 : 44.0
                currentWalkSpeed += (desiredSpeed - currentWalkSpeed) * min(1.0, CGFloat(dt) * 10.0)
                if currentWalkSpeed < 1.0 && (isHoveringDog || isPointerDownOnDog) {
                    currentWalkSpeed = 0
                    return
                }
                facingDirection = 1.0
                var nextX = position.x + currentWalkSpeed * CGFloat(dt)
                var hitRightEdge = false
                if nextX >= top.maxX - 24 {
                    nextX = top.maxX - 24
                    hitRightEdge = true
                }
                position.x = nextX
                offsetFromWindowMinX = position.x - top.windowMinX

                let nextRem = remaining - dt
                if hitRightEdge || nextRem <= 0 {
                    state = .topStory(step: .postWalkPause(elapsed: 0, duration: 0.55))
                } else {
                    state = .topStory(step: .walkRight(remaining: nextRem))
                }

            case .postWalkPause(let elapsed, let duration):
                currentWalkSpeed += (0 - currentWalkSpeed) * min(1.0, CGFloat(dt) * 14.0)
                if currentWalkSpeed < 0.8 { currentWalkSpeed = 0 }
                facingDirection = 1.0
                let next = elapsed + dt
                if next >= duration {
                    currentWalkSpeed = 0
                    // Sit smiling warmly at the camera for 4.8s with spaced gentle head sways!
                    state = .topStory(step: .smileSit(elapsed: 0, duration: 4.8))
                } else {
                    state = .topStory(step: .postWalkPause(elapsed: next, duration: duration))
                }

            case .flashStep(let roundsRemaining, let originX, let travelDist, let beat):
                currentWalkSpeed = 0
                facingDirection = 1.0
                // Keep `originX` locked relative to window if user drags window mid-dance!
                let d = travelDist

                func setRelX(_ frac: CGFloat) {
                    let nx = top.clampedX(originX + frac * d, margin: 20)
                    position.x = nx
                    offsetFromWindowMinX = nx - top.windowMinX
                }

                switch beat {
                case .holdStart(let elapsed, let duration):
                    setRelX(0.0)
                    let next = elapsed + dt
                    if next >= duration {
                        state = .topStory(step: .flashStep(
                            roundsRemaining: roundsRemaining, originX: originX, travelDist: d,
                            beat: .popLeft(elapsed: 0, duration: 0.08)
                        ))
                    } else {
                        state = .topStory(step: .flashStep(
                            roundsRemaining: roundsRemaining, originX: originX, travelDist: d,
                            beat: .holdStart(elapsed: next, duration: duration)
                        ))
                    }

                case .popLeft(let elapsed, let duration):
                    let next = elapsed + dt
                    let u = min(1.0, CGFloat(next / max(duration, 0.01)))
                    setRelX(-0.02 * u)
                    if next >= duration {
                        state = .topStory(step: .flashStep(
                            roundsRemaining: roundsRemaining, originX: originX, travelDist: d,
                            beat: .splitFeintLeft(elapsed: 0, duration: 0.22)
                        ))
                    } else {
                        state = .topStory(step: .flashStep(
                            roundsRemaining: roundsRemaining, originX: originX, travelDist: d,
                            beat: .popLeft(elapsed: next, duration: duration)
                        ))
                    }

                case .splitFeintLeft(let elapsed, let duration):
                    let next = elapsed + dt
                    let u = min(1.0, CGFloat(next / max(duration, 0.01)))
                    // Counter-overshoot +6% RIGHT (fake-out!) during first 60%, then whip into -8% LEFT!
                    let frac: CGFloat = (u < 0.60)
                        ? (0.06 * (u / 0.60))
                        : (0.06 - 0.14 * ((u - 0.60) / 0.40))
                    setRelX(frac)
                    if next >= duration {
                        state = .topStory(step: .flashStep(
                            roundsRemaining: roundsRemaining, originX: originX, travelDist: d,
                            beat: .glideWideLeft(elapsed: 0, duration: 0.18)
                        ))
                    } else {
                        state = .topStory(step: .flashStep(
                            roundsRemaining: roundsRemaining, originX: originX, travelDist: d,
                            beat: .splitFeintLeft(elapsed: next, duration: duration)
                        ))
                    }

                case .glideWideLeft(let elapsed, let duration):
                    let next = elapsed + dt
                    let u = min(1.0, CGFloat(next / max(duration, 0.01)))
                    // Ease-out quad: teleport surge from -8% -> -60% LEFT over pinned left foot!
                    let eased = 1.0 - (1.0 - u) * (1.0 - u)
                    setRelX(-0.08 - 0.52 * eased)
                    if next >= duration {
                        state = .topStory(step: .flashStep(
                            roundsRemaining: roundsRemaining, originX: originX, travelDist: d,
                            beat: .snapCloseLeft(elapsed: 0, duration: 0.18)
                        ))
                    } else {
                        state = .topStory(step: .flashStep(
                            roundsRemaining: roundsRemaining, originX: originX, travelDist: d,
                            beat: .glideWideLeft(elapsed: next, duration: duration)
                        ))
                    }

                case .snapCloseLeft(let elapsed, let duration):
                    let next = elapsed + dt
                    let u = min(1.0, CGFloat(next / max(duration, 0.01)))
                    let eased = Self.easeOutCubic(u)
                    setRelX(-0.60 - 0.38 * eased)
                    if next >= duration {
                        setRelX(-1.0)
                        state = .topStory(step: .flashStep(
                            roundsRemaining: roundsRemaining, originX: originX, travelDist: d,
                            beat: .statueFreezeLeft(elapsed: 0, duration: 0.72)
                        ))
                    } else {
                        state = .topStory(step: .flashStep(
                            roundsRemaining: roundsRemaining, originX: originX, travelDist: d,
                            beat: .snapCloseLeft(elapsed: next, duration: duration)
                        ))
                    }

                case .statueFreezeLeft(let elapsed, let duration):
                    setRelX(-1.0)
                    let next = elapsed + dt
                    if next >= duration {
                        state = .topStory(step: .flashStep(
                            roundsRemaining: roundsRemaining, originX: originX, travelDist: d,
                            beat: .popRight(elapsed: 0, duration: 0.08)
                        ))
                    } else {
                        state = .topStory(step: .flashStep(
                            roundsRemaining: roundsRemaining, originX: originX, travelDist: d,
                            beat: .statueFreezeLeft(elapsed: next, duration: duration)
                        ))
                    }

                case .popRight(let elapsed, let duration):
                    let next = elapsed + dt
                    let u = min(1.0, CGFloat(next / max(duration, 0.01)))
                    setRelX(-1.0 + 0.02 * u)
                    if next >= duration {
                        state = .topStory(step: .flashStep(
                            roundsRemaining: roundsRemaining, originX: originX, travelDist: d,
                            beat: .splitFeintRight(elapsed: 0, duration: 0.23)
                        ))
                    } else {
                        state = .topStory(step: .flashStep(
                            roundsRemaining: roundsRemaining, originX: originX, travelDist: d,
                            beat: .popRight(elapsed: next, duration: duration)
                        ))
                    }

                case .splitFeintRight(let elapsed, let duration):
                    let next = elapsed + dt
                    let u = min(1.0, CGFloat(next / max(duration, 0.01)))
                    // Exact mirror fake-out: overshoot -7% LEFT during first 55%, then surge to -88%!
                    let frac: CGFloat = (u < 0.55)
                        ? (-1.0 - 0.07 * (u / 0.55))
                        : (-1.07 + 0.19 * ((u - 0.55) / 0.45))
                    setRelX(frac)
                    if next >= duration {
                        state = .topStory(step: .flashStep(
                            roundsRemaining: roundsRemaining, originX: originX, travelDist: d,
                            beat: .glideWideRight(elapsed: 0, duration: 0.18)
                        ))
                    } else {
                        state = .topStory(step: .flashStep(
                            roundsRemaining: roundsRemaining, originX: originX, travelDist: d,
                            beat: .splitFeintRight(elapsed: next, duration: duration)
                        ))
                    }

                case .glideWideRight(let elapsed, let duration):
                    let next = elapsed + dt
                    let u = min(1.0, CGFloat(next / max(duration, 0.01)))
                    let eased = 1.0 - (1.0 - u) * (1.0 - u)
                    setRelX(-0.88 + 0.53 * eased)
                    if next >= duration {
                        state = .topStory(step: .flashStep(
                            roundsRemaining: roundsRemaining, originX: originX, travelDist: d,
                            beat: .snapCloseRight(elapsed: 0, duration: 0.20)
                        ))
                    } else {
                        state = .topStory(step: .flashStep(
                            roundsRemaining: roundsRemaining, originX: originX, travelDist: d,
                            beat: .glideWideRight(elapsed: next, duration: duration)
                        ))
                    }

                case .snapCloseRight(let elapsed, let duration):
                    let next = elapsed + dt
                    let u = min(1.0, CGFloat(next / max(duration, 0.01)))
                    let eased = Self.easeOutCubic(u)
                    setRelX(-0.35 + 0.33 * eased)
                    if next >= duration {
                        setRelX(0.0)
                        state = .topStory(step: .flashStep(
                            roundsRemaining: roundsRemaining, originX: originX, travelDist: d,
                            beat: .statueFinish(elapsed: 0, duration: 0.70)
                        ))
                    } else {
                        state = .topStory(step: .flashStep(
                            roundsRemaining: roundsRemaining, originX: originX, travelDist: d,
                            beat: .snapCloseRight(elapsed: next, duration: duration)
                        ))
                    }

                case .statueFinish(let elapsed, let duration):
                    setRelX(0.0)
                    let next = elapsed + dt
                    if next >= duration {
                        let remainingRounds = roundsRemaining - 1
                        if remainingRounds > 0 {
                            state = .topStory(step: .flashStep(
                                roundsRemaining: remainingRounds, originX: originX, travelDist: d,
                                beat: .popLeft(elapsed: 0, duration: 0.08)
                            ))
                        } else {
                            // Done with Flash-Step -> brief proud smile sit, then calm resting on top bar!
                            state = .topStory(step: .smileSit(elapsed: 0, duration: 3.4))
                        }
                    } else {
                        state = .topStory(step: .flashStep(
                            roundsRemaining: roundsRemaining, originX: originX, travelDist: d,
                            beat: .statueFinish(elapsed: next, duration: duration)
                        ))
                    }
                }

            case .bearShake(let cyclesRemaining, let originX, let frameIndex, let elapsed):
                currentWalkSpeed = 0
                facingDirection = 1.0
                let idx = min(max(frameIndex, 0), Self.bearShakeDurations.count - 1)
                let dur = Self.bearShakeDurations[idx]
                let offsetX = Self.bearShakeOffsets[idx] * scaleFactor
                let liveX = top.clampedX(originX + offsetX, margin: 20)
                position.x = liveX
                offsetFromWindowMinX = liveX - top.windowMinX

                let next = elapsed + dt
                if next >= dur {
                    let nextIdx = idx + 1
                    if nextIdx < Self.bearShakeDurations.count {
                        state = .topStory(step: .bearShake(
                            cyclesRemaining: cyclesRemaining,
                            originX: originX,
                            frameIndex: nextIdx,
                            elapsed: 0
                        ))
                    } else if cyclesRemaining > 1 {
                        state = .topStory(step: .bearShake(
                            cyclesRemaining: cyclesRemaining - 1,
                            originX: originX,
                            frameIndex: 0,
                            elapsed: 0
                        ))
                    } else {
                        let restX = top.clampedX(originX, margin: 20)
                        position.x = restX
                        offsetFromWindowMinX = restX - top.windowMinX
                        state = .topStory(step: .smileSit(elapsed: 0, duration: 2.6))
                    }
                } else {
                    state = .topStory(step: .bearShake(
                        cyclesRemaining: cyclesRemaining,
                        originX: originX,
                        frameIndex: idx,
                        elapsed: next
                    ))
                }

            case .wandererKick(let roundsRemaining, let mirrorSign, let frameIndex, let elapsed):
                currentWalkSpeed = 0
                facingDirection = mirrorSign
                let idx = min(max(frameIndex, 0), Self.wandererKickDurations.count - 1)
                let dur = Self.wandererKickDurations[idx]
                let next = elapsed + dt
                if next >= dur {
                    let nextIdx = idx + 1
                    if nextIdx < Self.wandererKickDurations.count {
                        if nextIdx == 3 {
                            squashSpring.impulse(1.8) // Punchy whip-kick snap!
                        }
                        state = .topStory(step: .wandererKick(
                            roundsRemaining: roundsRemaining,
                            mirrorSign: mirrorSign,
                            frameIndex: nextIdx,
                            elapsed: 0
                        ))
                    } else if roundsRemaining > 1 {
                        // Flip horizontally for symmetric opposite-leg kick!
                        state = .topStory(step: .wandererKick(
                            roundsRemaining: roundsRemaining - 1,
                            mirrorSign: -mirrorSign,
                            frameIndex: 1, // Jump straight into crouch for snappy combo!
                            elapsed: 0
                        ))
                    } else {
                        facingDirection = 1.0
                        state = .topStory(step: .smileSit(elapsed: 0, duration: 2.6))
                    }
                } else {
                    state = .topStory(step: .wandererKick(
                        roundsRemaining: roundsRemaining,
                        mirrorSign: mirrorSign,
                        frameIndex: idx,
                        elapsed: next
                    ))
                }

            case .headTilt(let stepIndex, let elapsed):
                currentWalkSpeed = 0
                facingDirection = 1.0
                let idx = min(max(stepIndex, 0), Self.headTiltSequence.count - 1)
                let dur = Self.headTiltSequence[idx].duration
                let next = elapsed + dt
                if next >= dur {
                    let nextIdx = idx + 1
                    if nextIdx < Self.headTiltSequence.count {
                        if nextIdx == 10 {
                            squashSpring.impulse(0.9) // Cute micro-perk on hero -36° tilt!
                        }
                        state = .topStory(step: .headTilt(stepIndex: nextIdx, elapsed: 0))
                    } else {
                        topBarEffectTimer = 0
                        state = .sitCalm(remaining: 60.0)
                    }
                } else {
                    state = .topStory(step: .headTilt(stepIndex: idx, elapsed: next))
                }

            case .bellyRoll(let phase, let sideSign):
                currentWalkSpeed = 0
                switch phase {
                case .flopDown(let elapsed, let duration):
                    facingDirection = sideSign
                    let next = elapsed + dt
                    if next >= duration {
                        squashSpring.impulse(-1.2)
                        state = .topStory(step: .bellyRoll(
                            phase: .waitingBellyUp(idleElapsed: 0, timeout: Self.bellyRollIdleTimeout, wiggleElapsed: 0),
                            sideSign: sideSign
                        ))
                    } else {
                        state = .topStory(step: .bellyRoll(
                            phase: .flopDown(elapsed: next, duration: duration),
                            sideSign: sideSign
                        ))
                    }

                case .waitingBellyUp(let idleElapsed, let timeout, let wiggleElapsed):
                    facingDirection = sideSign
                    let nextIdle = idleElapsed + dt
                    let nextWiggle = wiggleElapsed + dt
                    if nextIdle >= timeout {
                        // 10 seconds with no click -> roll back upright and end this interactive effect!
                        state = .topStory(step: .bellyRoll(
                            phase: .standingUp(elapsed: 0, duration: 0.28),
                            sideSign: sideSign
                        ))
                    } else {
                        state = .topStory(step: .bellyRoll(
                            phase: .waitingBellyUp(idleElapsed: nextIdle, timeout: timeout, wiggleElapsed: nextWiggle),
                            sideSign: sideSign
                        ))
                    }

                case .rollingOver(let elapsed, let duration, let fromSide, let toSide, let startX, let targetX):
                    let next = elapsed + dt
                    let u = min(1.0, CGFloat(next / max(duration, 0.01)))
                    let liveX = top.clampedX(startX + (targetX - startX) * Self.easeInOutCubic(u), margin: 22)
                    position.x = liveX
                    offsetFromWindowMinX = liveX - top.windowMinX
                    // Flip facing right at the supine apex midpoint (u == 0.45)
                    facingDirection = (u < 0.45) ? fromSide : toSide
                    if next >= duration {
                        facingDirection = toSide
                        squashSpring.impulse(-1.4)
                        state = .topStory(step: .bellyRoll(
                            phase: .waitingBellyUp(idleElapsed: 0, timeout: Self.bellyRollIdleTimeout, wiggleElapsed: 0),
                            sideSign: toSide
                        ))
                    } else {
                        state = .topStory(step: .bellyRoll(
                            phase: .rollingOver(
                                elapsed: next,
                                duration: duration,
                                fromSide: fromSide,
                                toSide: toSide,
                                startX: startX,
                                targetX: targetX
                            ),
                            sideSign: toSide
                        ))
                    }

                case .standingUp(let elapsed, let duration):
                    facingDirection = sideSign
                    let next = elapsed + dt
                    if next >= duration {
                        facingDirection = 1.0
                        topBarEffectTimer = 0
                        squashSpring.impulse(1.0)
                        state = .sitCalm(remaining: 60.0)
                    } else {
                        state = .topStory(step: .bellyRoll(
                            phase: .standingUp(elapsed: next, duration: duration),
                            sideSign: sideSign
                        ))
                    }
                }

            case .smileSit(let elapsed, let duration):
                currentWalkSpeed = 0
                facingDirection = 1.0
                let next = elapsed + dt
                if next >= duration {
                    // Independent effect complete -> settle calmly sitting on top bar (yawn/sleep is its own effect!)
                    topBarEffectTimer = 0
                    state = .sitCalm(remaining: 24.0)
                } else {
                    state = .topStory(step: .smileSit(elapsed: next, duration: duration))
                }
            }

        case .yawning(let elapsed, let duration):
            currentWalkSpeed = 0
            facingDirection = 1.0
            let next = elapsed + dt
            if next >= duration {
                squashSpring.impulse(-1.1) // Gentle weight drop as Westie curls down after yawning
                state = .settlingToSleep(elapsed: 0, duration: 4.2)
            } else {
                state = .yawning(elapsed: next, duration: duration)
            }

        case .settlingToSleep(let elapsed, let duration):
            currentWalkSpeed = 0
            facingDirection = 1.0
            let next = elapsed + dt
            if next >= duration {
                state = .sleeping(remaining: 45.0)
            } else {
                state = .settlingToSleep(elapsed: next, duration: duration)
            }

        case .greetingOnTop(let remaining):
            let isTyping = preferences.typingPauseEnabled && snapshot.secondsSinceLastKeyDown < 2.5
            if !isTyping {
                greetingPhase += CGFloat(dt)
                // One soft polite perk micro-hop around 2.6s into the sit-tilt greeting (never a repetitive loop!)
                if !didGreetingPerkHop && greetingPhase >= 2.6 && remaining > 3.8 {
                    didGreetingPerkHop = true
                    tapHopSpring.impulse(48.0)
                    squashSpring.impulse(1.1)
                }
            }

            // If owner gently hovers over Westie while it greets, happily acknowledge!
            if isHoveringDog && shyRetreatTimer == 0 {
                greetingHoverAccumulator += dt
                if greetingHoverAccumulator >= 0.35 {
                    tapHopSpring.impulse(120.0)
                    squashSpring.impulse(2.2)
                    greetingHoverAccumulator = 0
                    state = .loafing(remaining: 15.0)
                    return
                }
            } else {
                greetingHoverAccumulator = 0
            }

            let next = remaining - dt
            if next <= 0 {
                // Owner stayed focused & ignored Westie -> smoothly close eyes into peaceful nap on top!
                greetingHoverAccumulator = 0
                state = .sleeping(remaining: 45.0)
            } else {
                state = .greetingOnTop(remaining: next)
            }

        case .idle(let remaining),
             .sitCalm(let remaining),
             .loafing(let remaining),
             .chinRest(let remaining),
             .sleeping(let remaining):
            // Periodic independent Top-Bar Effect scheduler (while awake & resting on `windowTop`)
            let isRestingAwakeOnTop: Bool = {
                if case .sleeping = state { return false }
                return perchZone == .windowTop && pendingWindowSwitch == nil
            }()
            if isRestingAwakeOnTop,
               preferences.topEffectsEnabled,
               !context.forceQuietSleep,
               !context.isMeetingActive,
               !isHoveringDog,
               !isPointerDownOnDog
            {
                topBarEffectTimer += dt
                let isTypingPaused = preferences.typingPauseEnabled && snapshot.secondsSinceLastKeyDown < 2.5
                if !isTypingPaused,
                   topBarEffectTimer >= preferences.topEffectIntervalSeconds,
                   let top = layout.topPerch
                {
                    topBarEffectTimer = 0
                    let pool = preferences.orderedEnabledTopEffects
                    let candidates = (pool.count > 1 && lastAutoTopEffect != nil)
                        ? pool.filter { $0 != lastAutoTopEffect }
                        : pool
                    let chosen = candidates.randomElement() ?? pool[0]
                    if case .chinRest = state {
                        facingDirection = -1.0
                        state = .topStory(step: .risingToFullBody(elapsed: 0, duration: 0.62, nextEffect: chosen))
                    } else {
                        startTopBarEffect(chosen, on: top)
                    }
                    return
                }
            }

            let next = remaining - dt
            if next <= 0 {
                if perchZone == .windowTop {
                    if context.forceQuietSleep || context.isMeetingActive {
                        state = .sleeping(remaining: 24.0)
                    } else if context.shouldOfferTennisBreak {
                        state = .holdingTennisBall(remaining: 22.0)
                    } else if case .sleeping = state {
                        // Wake gently from nap into calm open-eye loafing so periodic effects can resume!
                        topBarEffectTimer = 0
                        state = .loafing(remaining: 60.0)
                    } else {
                        // Stay calm in current resting pose (`chinRest`, `sitCalm`, `loafing`, `idle`)
                        // until the user taps or `topEffectIntervalSeconds` triggers an independent effect!
                        switch state {
                        case .idle: state = .idle(remaining: 60.0)
                        case .sitCalm: state = .sitCalm(remaining: 60.0)
                        case .loafing: state = .loafing(remaining: 60.0)
                        case .chinRest: state = .chinRest(remaining: 60.0)
                        default: break
                        }
                    }
                } else {
                    state = .peekingRight(remaining: 22.0)
                }
            } else {
                switch state {
                case .idle: state = .idle(remaining: next)
                case .sitCalm: state = .sitCalm(remaining: next)
                case .loafing: state = .loafing(remaining: next)
                case .chinRest: state = .chinRest(remaining: next)
                case .sleeping: state = .sleeping(remaining: next)
                default: break
                }
            }

        case .peekingRight(let remaining):
            // Accumulate calm dwell time while peeking on screen right edge (default) or active window right edge
            // so Westie climbs up onto the active window's top bar after `climbToTopIntervalSeconds`!
            let canClimbFromRightPeek =
                ((perchZone == .screenRightPeek && !layout.isFullScreenMode && layout.topPerch != nil)
                    || (perchZone == .windowRightPeek && pendingWindowSwitch == nil))
            if canClimbFromRightPeek && !isHoveringDog && !context.forceQuietSleep && !context.isMeetingActive {
                rightPeekDwellTimer += dt
            }

            let isTypingPaused = preferences.typingPauseEnabled && snapshot.secondsSinceLastKeyDown < 2.5
            if canClimbFromRightPeek,
               preferences.climbToTopEnabled,
               !context.forceQuietSleep,
               !context.isMeetingActive,
               !isHoveringDog,
               !isTypingPaused,
               rightPeekDwellTimer >= preferences.climbToTopIntervalSeconds,
               let top = layout.topPerch
            {
                rightPeekDwellTimer = 0
                let targetX = top.clampedX(top.maxX - min(110, top.width * 0.26), margin: 22)
                // Default climb-to-top: simple peek left & right, then rest head-on-ledge facing forward!
                beginStealthClimbToTop(
                    targetX: targetX,
                    windowID: layout.activeWindowID ?? trackedWindowID,
                    effectOnArrival: nil
                )
                return
            }

            let next = remaining - dt
            if next <= 0 {
                if context.shouldOfferTennisBreak {
                    state = .holdingTennisBall(remaining: 22.0)
                } else {
                    state = .peekingRight(remaining: Double.random(in: 18.0...28.0))
                }
            } else {
                state = .peekingRight(remaining: next)
            }

        case .holdingTennisBall(let remaining):
            let next = remaining - dt
            if next <= 0 {
                state = (perchZone == .windowTop) ? .idle(remaining: 5.0) : .peekingRight(remaining: 20.0)
            } else {
                state = .holdingTennisBall(remaining: next)
            }

        case .chasingTreat(let treatX):
            let dx = treatX - position.x
            if abs(dx) < 14 {
                treatNode?.removeFromParent()
                treatNode = nil
                currentWalkSpeed = 0
                lastEatBiteIndex = -1
                squashSpring.impulse(-1.6)
                state = .eatingTreat(elapsed: 0, duration: 2.6)
            } else if let top = currentPlatform {
                let dir: CGFloat = dx > 0 ? 1.0 : -1.0
                facingDirection = dir
                currentWalkSpeed = 115.0
                position.x = top.clampedX(position.x + dir * 115.0 * CGFloat(dt), margin: 18)
                offsetFromWindowMinX = position.x - top.windowMinX
            } else {
                treatNode?.removeFromParent()
                treatNode = nil
                state = .idle(remaining: 4.0)
            }

        case .eatingTreat(let elapsed, let duration):
            currentWalkSpeed = 0
            let next = elapsed + dt
            let biteIdx = Int(next / 0.28)
            if biteIdx != lastEatBiteIndex {
                lastEatBiteIndex = biteIdx
                squashSpring.impulse(0.95)
                if biteIdx % 2 == 1 {
                    spawnSnackCrumbs(finalSparkle: false)
                }
            }
            if next >= duration {
                lastEatBiteIndex = -1
                tapHopSpring.impulse(75.0)
                squashSpring.impulse(1.9)
                spawnSnackCrumbs(finalSparkle: true)
                state = .sitCalm(remaining: 11.0)
            } else {
                state = .eatingTreat(elapsed: next, duration: duration)
            }

        case .walking(var dir, let remaining):
            guard perchZone == .windowTop, let top = currentPlatform else {
                state = .peekingRight(remaining: 20.0)
                return
            }
            // Smoothly decelerate to 0 when cursor hovers or presses Westie (zero 1-frame dead stop!)
            let desiredSpeed: CGFloat = (isHoveringDog || isPointerDownOnDog) ? 0.0 : 38.0
            let blend = min(1.0, CGFloat(dt) * 14.0)
            currentWalkSpeed += (desiredSpeed - currentWalkSpeed) * blend

            if currentWalkSpeed < 1.0 && (isHoveringDog || isPointerDownOnDog) {
                currentWalkSpeed = 0
                return
            }

            facingDirection = dir
            var nextX = position.x + dir * currentWalkSpeed * CGFloat(dt)

            if nextX <= top.minX + 18 || nextX >= top.maxX - 18 {
                dir = -dir
                facingDirection = dir
                nextX = top.clampedX(nextX, margin: 18)
            }

            position.x = nextX
            offsetFromWindowMinX = position.x - top.windowMinX

            let nextRem = remaining - dt
            if nextRem <= 0 {
                state = WestieBehaviorPlanner.chooseNextTopBehavior(
                    currentX: position.x,
                    platform: top,
                    context: context
                )
            } else {
                state = .walking(direction: dir, remaining: nextRem)
            }

        case .gliding(let elapsed, let duration, let from, var to, let targetZone):
            // Keep target anchored to live window frame during the short glide
            switch targetZone {
            case .windowTop:
                if let top = layout.topPerch {
                    to = CGPoint(x: top.clampedX(to.x, margin: 18), y: top.y)
                }
            case .windowRightPeek:
                if let right = layout.windowRightPeek {
                    to = CGPoint(x: right.edgeX, y: right.clampedY(to.y))
                }
            case .screenRightPeek:
                to = CGPoint(x: layout.screenRightPeek.edgeX, y: layout.screenRightPeek.clampedY(to.y))
            }

            let t = elapsed + dt
            if t >= duration {
                finishGlideArrival(at: to, targetZone: targetZone, layout: layout)
            } else {
                let u = CGFloat(t / max(duration, 0.01))
                let eased = 1.0 - pow(1.0 - u, 3)
                let dist = hypot(to.x - from.x, to.y - from.y)
                let arcHeight = min(max(dist * 0.16, 18.0), 52.0)
                let arcHop = sin(u * .pi) * arcHeight
                position = CGPoint(
                    x: from.x + (to.x - from.x) * eased,
                    y: from.y + (to.y - from.y) * eased + arcHop
                )
                state = .gliding(elapsed: t, duration: duration, from: from, to: to, targetZone: targetZone)
            }

        case .dragged:
            break
        }
    }

    // MARK: - Smooth Cross-Fade & Organic Easing Helpers

    private func spawnBellyRubSparkle() {
        let k = scaleFactor
        let sparkle = SKLabelNode(text: "💕")
        sparkle.fontSize = 14 * max(0.85, k * 0.85)
        sparkle.position = CGPoint(x: position.x, y: position.y + 42 * k)
        sparkle.zPosition = 9
        rootNode.addChild(sparkle)
        let rise = SKAction.moveBy(x: CGFloat.random(in: -10...10) * k, y: 24 * k, duration: 0.55)
        rise.timingMode = .easeOut
        sparkle.run(.sequence([
            .group([rise, .fadeOut(withDuration: 0.55)]),
            .removeFromParent()
        ]))
    }

    /// Smoothly cross-fades `dogSprite` to `nextKey` (for current `preferences.petSpecies`) using `fadeOutSprite`.
    /// Only reassigns GPU texture when `nextKey` or `species` actually changes (zero per-frame texture churn!).
    private func applySpriteTexture(
        _ nextKey: SpriteAssetKey,
        size: CGSize,
        crossfadeDuration: TimeInterval,
        bank: SpriteBank
    ) {
        let species = preferences.petSpecies
        let speciesChanged = (displayedSpriteSpecies != species)
        if speciesChanged {
            // Defer background CGImage decode off-main-thread AFTER the current SpriteKit frame finishes!
            DispatchQueue.main.async {
                SpriteBank.shared.preloadSpecies(species)
            }
        }
        let needsSwap = (displayedSpriteKey != nextKey || speciesChanged || dogSprite.texture == nil)
        if needsSwap {
            if !speciesChanged && crossfadeDuration > 0.01 && !dogSprite.isHidden && dogSprite.texture != nil {
                fadeOutSprite.texture = dogSprite.texture
                fadeOutSprite.size = dogSprite.size
                fadeOutSprite.anchorPoint = dogSprite.anchorPoint
                fadeOutSprite.position = dogSprite.position
                fadeOutSprite.xScale = dogSprite.xScale
                fadeOutSprite.yScale = dogSprite.yScale
                fadeOutSprite.zRotation = dogSprite.zRotation
                fadeOutSprite.alpha = 1.0
                fadeOutSprite.isHidden = false
                poseCrossfadeElapsed = 0
                poseCrossfadeDuration = crossfadeDuration
            } else {
                clearCrossfade()
            }
            displayedSpriteKey = nextKey
            displayedSpriteSpecies = species
            dogSprite.texture = bank.texture(for: nextKey, species: species)
        }
        if dogSprite.size != size {
            dogSprite.size = size
        }
    }

    private func clearCrossfade() {
        poseCrossfadeElapsed = 0
        poseCrossfadeDuration = 0
        fadeOutSprite.isHidden = true
        fadeOutSprite.alpha = 0
        dogSprite.alpha = 1.0
    }

    private func stepCrossfade(dt: TimeInterval) {
        guard poseCrossfadeDuration > 0 else {
            dogSprite.alpha = 1.0
            fadeOutSprite.isHidden = true
            return
        }
        poseCrossfadeElapsed += dt
        if poseCrossfadeElapsed >= poseCrossfadeDuration {
            clearCrossfade()
            return
        }
        let u = CGFloat(poseCrossfadeElapsed / poseCrossfadeDuration)
        // Opaque-backing dissolve: keep outgoing sprite at alpha=1.0 while incoming ramps 0->1 over first 75%,
        // then fade outgoing 1->0 over final 25% so combined opacity stays >= 94% (ZERO white background flash!).
        fadeOutSprite.position = dogSprite.position
        dogSprite.alpha = min(1.0, Self.easeInOutCubic(min(1.0, u / 0.75)))
        fadeOutSprite.alpha = (u < 0.75) ? 1.0 : max(0.0, 1.0 - (u - 0.75) / 0.25)
    }

    /// Bell-curve smooth head tilt pulse around `center` with half-width `radius` (returns 0 outside window).
    private static func smoothTiltPulse(t: CGFloat, center: CGFloat, radius: CGFloat, amplitude: CGFloat) -> CGFloat {
        let dist = abs(t - center)
        guard dist < radius else { return 0 }
        let u = 1.0 - (dist / radius)
        let bell = u * u * (3.0 - 2.0 * u) // smoothstep bell
        return bell * amplitude
    }

    // MARK: - Visual Sync

    private func renderMaskedRetractOrPeek(
        zone: PerchZone,
        retractFraction: CGFloat,
        curiousTilt: CGFloat,
        topTextureKey: SpriteAssetKey = .westieTopPeekCenter,
        topSize: CGSize? = nil,
        crossfadeDuration: TimeInterval = 0,
        bank: SpriteBank
    ) {
        let f = min(max(retractFraction, 0), 1)
        dogSprite.isHidden = false
        inviteBadgeNode.isHidden = true

        let k = scaleFactor
        switch zone {
        case .windowRightPeek:
            clearCrossfade()
            // Mask x >= position.x - 0.5 so Westie's fur sits pixel-flush against the app window's right border (zero gap!)
            cropMaskNode.anchorPoint = CGPoint(x: 0.0, y: 0.5)
            cropMaskNode.position = CGPoint(x: position.x - 0.5, y: position.y)
            cropNode.maskNode = cropMaskNode
            dogSprite.anchorPoint = CGPoint(x: 1.0, y: 0.5)
            applySpriteTexture(.westiePeekCalm, size: peekDogSize, crossfadeDuration: 0, bank: bank)
            let tuck = (14.5 + f * 64.0) * k
            dogSprite.xScale = -1.0
            dogSprite.yScale = 1.0
            dogSprite.position = CGPoint(x: position.x - tuck, y: position.y)
            dogSprite.zRotation = curiousTilt
            shadowNode.isHidden = true

        case .screenRightPeek:
            clearCrossfade()
            cropNode.maskNode = nil
            dogSprite.anchorPoint = CGPoint(x: 1.0, y: 0.5)
            applySpriteTexture(.westiePeekCalm, size: peekDogSize, crossfadeDuration: 0, bank: bank)
            let tuck = (14.5 + f * 66.0) * k
            dogSprite.xScale = 1.0
            dogSprite.yScale = 1.0
            dogSprite.position = CGPoint(x: position.x + tuck, y: position.y)
            dogSprite.zRotation = curiousTilt
            shadowNode.isHidden = true

        case .windowTop:
            // Keep top-peek left/right un-mirrored so Left literally looks left and Right literally looks right!
            let isDirectionalPeek = (topTextureKey == .westieTopPeekCenter
                || topTextureKey == .westieTopPeekLeft
                || topTextureKey == .westieTopPeekRight)
            // Only apply bottom stencil mask while actively sliding behind/out from the title bar;
            // once emerged (`f <= 0.005`), release the mask so hanging paws drape naturally over the window edge!
            if f > 0.005 {
                cropMaskNode.anchorPoint = CGPoint(x: 0.5, y: 0.0)
                cropMaskNode.position = CGPoint(x: position.x, y: position.y)
                cropNode.maskNode = cropMaskNode
            } else {
                cropNode.maskNode = nil
            }
            // Top-peek sprites have paws hanging ~5px below the flat chin/shoulder ledge line (`y = 0.088`),
            // anchoring at `0.088` seats the chin & shoulders 100% flush onto the window top edge with ZERO gap!
            dogSprite.anchorPoint = CGPoint(x: 0.5, y: isDirectionalPeek ? 0.088 : 0.04)
            let targetSize = topSize ?? topDogSize
            applySpriteTexture(topTextureKey, size: targetSize, crossfadeDuration: 0, bank: bank)
            let sinkY = f * (targetSize.height + 4.0)
            dogSprite.xScale = isDirectionalPeek ? 1.0 : (facingDirection >= 0 ? 1.0 : -1.0)
            dogSprite.yScale = 1.0
            dogSprite.position = CGPoint(x: position.x, y: position.y - sinkY)
            dogSprite.zRotation = curiousTilt
            shadowNode.isHidden = true
        }
    }

    private func syncVisuals(dt: TimeInterval) {
        let bank = SpriteBank.shared
        let s = min(max(squashSpring.value, -0.30), 0.30)
        let dirSign: CGFloat = facingDirection >= 0 ? 1.0 : -1.0

        // 0a. Tucked behind old window during 5s dwell wait because new window overlapped Westie (`tuck_early`)
        if case .tuckedWaiting(let elapsed, let duration, let originZone) = state {
            clearCrossfade()
            let u = CGFloat(elapsed / max(duration, 0.01))
            if u >= 0.99 {
                dogSprite.isHidden = true
                shadowNode.isHidden = true
                inviteBadgeNode.isHidden = true
            } else {
                let eased = Self.easeInOutCubic(u)
                renderMaskedRetractOrPeek(
                    zone: originZone,
                    retractFraction: eased,
                    curiousTilt: 0,
                    topTextureKey: .westieSitTilt,
                    topSize: topDogSize,
                    bank: bank
                )
            }
            return
        }

        // 0b. 4-Phase Stealthy Behind-Window Transition (retract -> hidden -> 3s head look-around -> climb-up -> idle!)
        if case .stealthTransition(let phase, let originZone, let destination, _, _) = state {
            switch phase {
            case .retracting(let elapsed, let duration):
                clearCrossfade()
                let u = CGFloat(elapsed / max(duration, 0.01))
                let eased = Self.easeInOutCubic(u)
                renderMaskedRetractOrPeek(
                    zone: originZone,
                    retractFraction: eased,
                    curiousTilt: sin(u * .pi) * 0.025,
                    topTextureKey: retractTopSpriteKey,
                    topSize: retractTopSpriteSize,
                    bank: bank
                )

            case .hiddenTraverse:
                clearCrossfade()
                dogSprite.isHidden = true
                shadowNode.isHidden = true
                inviteBadgeNode.isHidden = true

            case .tentativePeek(let elapsed, let duration):
                let u = CGFloat(elapsed / max(duration, 0.01))
                if destination.perchZone == .windowTop {
                    // 3.0s top-edge head peek choreography:
                    // 0.00..0.45s: rise smoothly from behind title bar -> paws resting on edge
                    // 0.45..0.85s: calm center look
                    // 0.85..1.65s: turn head LEFT curiously (dedicated sprite + gentle -3 deg lean!)
                    // 1.65..1.95s: return to center
                    // 1.95..2.75s: turn head RIGHT curiously (dedicated sprite + gentle +3 deg lean!)
                    // 2.75..3.00s: return to center ready to climb!
                    let riseDur: TimeInterval = 0.45
                    let retractFrac: CGFloat = (elapsed < riseDur)
                        ? (1.0 - Self.easeOutCubic(CGFloat(elapsed / riseDur)))
                        : 0.0

                    let peekKey: SpriteAssetKey
                    let tilt: CGFloat
                    let t = CGFloat(elapsed)
                    if elapsed < 0.85 {
                        peekKey = .westieTopPeekCenter
                        tilt = 0
                    } else if elapsed < 1.65 {
                        peekKey = .westieTopPeekLeft
                        tilt = Self.smoothTiltPulse(t: t, center: 1.25, radius: 0.40, amplitude: 0.055)
                    } else if elapsed < 1.95 {
                        peekKey = .westieTopPeekCenter
                        tilt = 0
                    } else if elapsed < 2.75 {
                        peekKey = .westieTopPeekRight
                        tilt = -Self.smoothTiltPulse(t: t, center: 2.35, radius: 0.40, amplitude: 0.055)
                    } else {
                        peekKey = .westieTopPeekCenter
                        tilt = 0
                    }

                    renderMaskedRetractOrPeek(
                        zone: .windowTop,
                        retractFraction: retractFrac,
                        curiousTilt: tilt,
                        topTextureKey: peekKey,
                        topSize: topPeekDogSize,
                        crossfadeDuration: 0.16,
                        bank: bank
                    )
                    // Subtle breathing while peering over the top edge
                    let br = sin(breathPhase * 0.9) * 0.015
                    dogSprite.yScale = 1.0 + br
                    dogSprite.xScale = 1.0 - br * 0.5
                    stepCrossfade(dt: dt)
                } else {
                    clearCrossfade()
                    let targetPeekRetract: CGFloat = 0.48
                    let retractFraction: CGFloat
                    let curiousTilt: CGFloat
                    if u < 0.48 {
                        let riseU = Self.easeOutCubic(u / 0.48)
                        retractFraction = 1.0 - (1.0 - targetPeekRetract) * riseU
                        curiousTilt = 0
                    } else {
                        let lookU = (u - 0.48) / 0.52
                        retractFraction = targetPeekRetract
                        curiousTilt = Self.smoothTiltPulse(t: lookU, center: 0.35, radius: 0.32, amplitude: 0.045)
                            - Self.smoothTiltPulse(t: lookU, center: 0.72, radius: 0.28, amplitude: 0.032)
                    }
                    renderMaskedRetractOrPeek(
                        zone: destination.perchZone,
                        retractFraction: retractFraction,
                        curiousTilt: curiousTilt,
                        bank: bank
                    )
                }

            case .settlingOut(let elapsed, let duration):
                let u = CGFloat(elapsed / max(duration, 0.01))
                if destination.perchZone == .windowTop {
                    if preferences.climbPawsPeekEnabled {
                        // Continuous 3-frame climb ALREADY MIRRORED LEFT (`xScale = -1.0`) so it flows seamlessly into hopping LEFT!
                        // 0.00..0.18: anticipation dip on `westieTopPeekCenter`
                        // 0.18..0.68: haul body over ledge (`westieClimbUp`, mirrored LEFT!) with upward stretch
                        // 0.68..1.00: land cleanly on all four paws (`westieIdle`, facing LEFT!) with soft cushion!
                        if u < 0.18 {
                            renderMaskedRetractOrPeek(
                                zone: .windowTop,
                                retractFraction: 0.0,
                                curiousTilt: 0,
                                topTextureKey: .westieTopPeekCenter,
                                topSize: topPeekDogSize,
                                crossfadeDuration: 0.12,
                                bank: bank
                            )
                            let dip = sin((u / 0.18) * .pi) * 0.08
                            dogSprite.yScale = 1.0 - dip
                            dogSprite.xScale = 1.0 + dip * 0.5
                        } else if u < 0.68 {
                            let climbU = (u - 0.18) / 0.50
                            renderMaskedRetractOrPeek(
                                zone: .windowTop,
                                retractFraction: max(0, (1.0 - Self.easeOutCubic(climbU)) * 0.26),
                                curiousTilt: 0,
                                topTextureKey: .westieClimbUp,
                                topSize: topDogSize,
                                crossfadeDuration: 0.18,
                                bank: bank
                            )
                            dogSprite.xScale = -1.0 // Mirrored LEFT so next frame's leftward hop has ZERO direction flip!
                            let arcLift = sin(climbU * .pi) * 5.0
                            dogSprite.position.y += arcLift
                        } else {
                            let landU = (u - 0.68) / 0.32
                            renderMaskedRetractOrPeek(
                                zone: .windowTop,
                                retractFraction: 0.0,
                                curiousTilt: 0,
                                topTextureKey: .westieIdle,
                                topSize: topDogSize,
                                crossfadeDuration: 0.20,
                                bank: bank
                            )
                            let settleDip = sin(landU * .pi) * 0.06
                            dogSprite.yScale = 1.0 - settleDip
                            dogSprite.xScale = -(1.0 + settleDip * 0.4)
                        }
                        stepCrossfade(dt: dt)
                    } else {
                        let eased = Self.easeOutCubic(u)
                        renderMaskedRetractOrPeek(
                            zone: .windowTop,
                            retractFraction: 1.0 - eased,
                            curiousTilt: 0,
                            topTextureKey: .westieIdle,
                            topSize: topDogSize,
                            bank: bank
                        )
                    }
                } else {
                    let eased = Self.easeOutCubic(u)
                    renderMaskedRetractOrPeek(
                        zone: destination.perchZone,
                        retractFraction: 0.48 * (1.0 - eased),
                        curiousTilt: 0,
                        bank: bank
                    )
                }
            }
            return
        }

        dogSprite.isHidden = false

        // 1. Dragged Pose: velocity pendulum swing + squash/stretch
        if case .dragged = state {
            clearCrossfade()
            cropNode.maskNode = nil
            dogSprite.anchorPoint = CGPoint(x: 0.5, y: 0.04)
            applySpriteTexture(.westieDangling, size: topDogSize, crossfadeDuration: 0, bank: bank)
            dogSprite.position = position
            dogSprite.xScale = dirSign * (1.0 - s * 0.28)
            dogSprite.yScale = 1.0 + s * 0.32
            dogSprite.zRotation = swingRotationSpring.value + sin(breathPhase * 2.2) * 0.035
            shadowNode.isHidden = true
            inviteBadgeNode.isHidden = true
            return
        }

        // 2. Parabolic Hop / Gliding Pose: mid-air scamper paws + dynamic pitch tilt
        if case .gliding(let elapsed, let duration, _, _, _) = state {
            clearCrossfade()
            cropNode.maskNode = nil
            dogSprite.anchorPoint = CGPoint(x: 0.5, y: 0.04)
            walkAnimTimer += dt
            if walkAnimTimer >= 0.08 {
                walkAnimTimer = 0
                walkFrameIndex = (walkFrameIndex + 1) % Self.walkCycleFrames.count
            }
            applySpriteTexture(Self.walkCycleFrames[walkFrameIndex], size: topDogSize, crossfadeDuration: 0, bank: bank)
            dogSprite.position = position
            dogSprite.xScale = dirSign * (1.0 - s * 0.30)
            dogSprite.yScale = 1.0 + s * 0.34
            let u = CGFloat(elapsed / max(duration, 0.01))
            let pitchTilt = cos(u * .pi) * 0.16 * dirSign
            dogSprite.zRotation = pitchTilt

            shadowNode.isHidden = true
            inviteBadgeNode.isHidden = true
            return
        }

        // 3. Right-Edge Peeking Modes (Fullscreen Screen-Right OR Non-Fullscreen Window-Right)
        if perchZone == .screenRightPeek || perchZone == .windowRightPeek {
            clearCrossfade()
            let hoverSlide = min(max(peekHoverSpring.value, -0.40), 1.25)
            // Negative `peekEmergeSpring.value` tucks Westie behind the edge and springs smoothly out to 0!
            let emergeTuck = max(0, -peekEmergeSpring.value) * 34.0 - min(max(peekEmergeSpring.value, 0), 0.22) * 7.0

            dogSprite.anchorPoint = CGPoint(x: 1.0, y: 0.5)
            applySpriteTexture(
                isPeekHoverTextureActive ? .westiePeekHover : .westiePeekCalm,
                size: peekDogSize,
                crossfadeDuration: 0,
                bank: bank
            )

            let stretchMag = 1.0 + s * 0.22
            let squashPerp = 1.0 - s * 0.18
            dogSprite.yScale = squashPerp

            // Subtle friendly ear/paw tilt ONLY while hovered — completely still otherwise!
            let subtleHoverTilt: CGFloat = (peekHoverSpring.value > 0.04)
                ? sin(hoverWavePhase * 5.2) * 0.036 * min(max(hoverSlide, 0), 1.0)
                : 0.0

            let k = scaleFactor
            if perchZone == .screenRightPeek {
                // Monitor right bezel clips x > screenWidth naturally; keep body >= 5.5*k tucked so zero gap ever opens!
                cropNode.maskNode = nil
                let tuckInward: CGFloat = max(5.5 * k, (5.5 + 9.0 * (1.0 - hoverSlide)) * k + emergeTuck * k)
                dogSprite.xScale = stretchMag
                dogSprite.position = CGPoint(x: position.x + tuckInward, y: position.y)
                dogSprite.zRotation = subtleHoverTilt
                inviteBadgeNode.position = CGPoint(x: position.x - 68 * k, y: position.y + 46 * k)
            } else {
                // Window right border: mask `x >= position.x - 0.5` and keep body >= 5.5*k tucked behind window.maxX
                // so the sprite's flush edge meets the app border with ZERO white gap at any scale!
                cropMaskNode.anchorPoint = CGPoint(x: 0.0, y: 0.5)
                cropMaskNode.position = CGPoint(x: position.x - 0.5, y: position.y)
                cropNode.maskNode = cropMaskNode
                let tuckBehindWindow: CGFloat = max(5.5 * k, (5.5 + 9.0 * (1.0 - hoverSlide)) * k + emergeTuck * k)
                dogSprite.xScale = -stretchMag // Mirrored to peek RIGHTWARD out from behind the active window!
                dogSprite.position = CGPoint(x: position.x - tuckBehindWindow, y: position.y)
                dogSprite.zRotation = -subtleHoverTilt + swingRotationSpring.value * 0.4
                inviteBadgeNode.position = CGPoint(x: position.x + 64 * k, y: position.y + 46 * k)
            }

            shadowNode.isHidden = true
            if case .holdingTennisBall = state {
                inviteBadgeNode.isHidden = false
            } else {
                inviteBadgeNode.isHidden = true
            }
            return
        }

        // 4. Active Window Top-Edge Mode (`正上方` — uniform scale, cross-faded pose transitions, organic breathing!)
        cropNode.maskNode = nil
        dogSprite.anchorPoint = CGPoint(x: 0.5, y: 0.04)

        var bobY: CGFloat = max(0, tapHopSpring.value)
        var strideTilt: CGFloat = 0
        var breathYScale: CGFloat = 1.0
        var breathXScale: CGFloat = 1.0

        let desiredKey: SpriteAssetKey
        var desiredSize: CGSize = topDogSize
        var fadeDur: TimeInterval = 0

        if case .walking = state, currentWalkSpeed < 5.0 {
            desiredKey = .westieIdle // Stay calmly standing on hover — never flash to sitting sprite!
        } else {
            switch state {
            case .topStory(let step):
                switch step {
                case .risingToFullBody(let elapsed, let duration, let nextEffect):
                    // Smoothly pull body up from resting head-on-ledge (`westieTopPeekCenter`) onto all four paws!
                    let u = CGFloat(elapsed / max(duration, 0.01))
                    if u < 0.20 {
                        desiredKey = .westieTopPeekCenter
                        desiredSize = topPeekDogSize
                        let dip = sin((u / 0.20) * .pi) * 0.08
                        breathYScale = 1.0 - dip
                        breathXScale = 1.0 + dip * 0.45
                    } else if u < 0.72 {
                        let climbU = (u - 0.20) / 0.52
                        desiredKey = .westieClimbUp
                        desiredSize = topDogSize
                        bobY += sin(climbU * .pi) * 5.0
                        facingDirection = (nextEffect == .patrol) ? -1.0 : 1.0
                    } else {
                        let landU = (u - 0.72) / 0.28
                        desiredKey = .westieIdle
                        desiredSize = topDogSize
                        let settle = sin(landU * .pi) * 0.05
                        breathYScale = 1.0 - settle
                        breathXScale = 1.0 + settle * 0.4
                    }

                case .postClimbPause, .postWalkPause:
                    desiredKey = .westieIdle
                    let br = sin(breathPhase * 0.9) * 0.014
                    breathYScale = 1.0 + br
                    breathXScale = 1.0 - br * 0.5

                case .hopLeft(_, let hopElapsed, let hopDuration, _, _, _):
                    if hopElapsed < hopDuration {
                        let u = CGFloat(hopElapsed / max(hopDuration, 0.01))
                        if u < 0.18 {
                            desiredKey = .westieHopCrouch
                            let dip = sin((u / 0.18) * .pi) * 0.06
                            breathYScale = 1.0 - dip
                            breathXScale = 1.0 + dip * 0.45
                        } else if u < 0.76 {
                            let airU = (u - 0.18) / 0.58
                            bobY += sin(airU * .pi) * 13.0
                            desiredKey = .westieHopAir
                            strideTilt = cos(airU * .pi) * -0.07
                            let stretch = sin(airU * .pi) * 0.05
                            breathYScale = 1.0 + stretch
                            breathXScale = 1.0 - stretch * 0.35
                        } else {
                            let landU = (u - 0.76) / 0.24
                            desiredKey = .westieHopLand
                            let cushion = sin(landU * .pi) * 0.05
                            breathYScale = 1.0 - cushion
                            breathXScale = 1.0 + cushion * 0.4
                        }
                    } else {
                        desiredKey = .westieHopCrouch
                    }

                case .lookAroundPause(let elapsed, _):
                    if elapsed < 0.35 {
                        desiredKey = .westieLookLeftHeadLeft
                    } else if elapsed < 0.50 {
                        desiredKey = .westieLookLeftHeadCenter
                    } else if elapsed < 1.35 {
                        desiredKey = .westieLookLeftHeadRight
                    } else if elapsed < 1.50 {
                        desiredKey = .westieLookLeftHeadCenter
                    } else if elapsed < 2.35 {
                        desiredKey = .westieLookLeftHeadLeft
                    } else if elapsed < 2.50 {
                        desiredKey = .westieLookLeftHeadCenter
                    } else {
                        desiredKey = .westieLookLeftHeadRight
                    }
                    let br = sin(breathPhase * 0.9) * 0.014
                    breathYScale = 1.0 + br
                    breathXScale = 1.0 - br * 0.5

                case .walkRight:
                    if currentWalkSpeed < 5.0 {
                        desiredKey = .westieIdle
                    } else {
                        let speedRatio = max(0.35, Double(currentWalkSpeed / 44.0))
                        walkAnimTimer += dt * speedRatio
                        if walkAnimTimer >= 0.125 {
                            walkAnimTimer = 0
                            walkFrameIndex = (walkFrameIndex + 1) % Self.walkCycleFrames.count
                        }
                        desiredKey = Self.walkCycleFrames[walkFrameIndex]
                        let isPassingFrame = (walkFrameIndex == 1 || walkFrameIndex == 3)
                        let speedFactor = min(1.0, currentWalkSpeed / 44.0)
                        bobY += (isPassingFrame ? 1.6 : 0.0) * speedFactor
                        strideTilt = sin(breathPhase * 2.6) * 0.020 * speedFactor
                    }

                case .flashStep(_, _, _, let beat):
                    // Authentic 8-frame "闪身步": crisp hard cuts (fadeDur = 0), wide 192x128 aspect ratio (99x66*k),
                    // ZERO upward hop — drops slightly DOWN (-5% H) in the split and glides dead-flat!
                    desiredSize = flashStepDogSize
                    fadeDur = 0
                    let h = topDogSize.height
                    switch beat {
                    case .holdStart, .statueFreezeLeft, .statueFinish:
                        desiredKey = .westieFlashStep1 // Stone-faced deadpan statue (zero bob or sway!)
                    case .popLeft, .popRight:
                        desiredKey = .westieFlashStep2
                        bobY -= 0.01 * h
                    case .splitFeintLeft:
                        desiredKey = .westieFlashStep3
                        bobY -= 0.05 * h // Grounded low A-frame drop!
                    case .glideWideLeft(let elapsed, let duration):
                        desiredKey = .westieFlashStep4
                        let u = min(1.0, CGFloat(elapsed / max(duration, 0.01)))
                        bobY -= (0.05 - 0.04 * u) * h
                    case .snapCloseLeft:
                        desiredKey = .westieFlashStep5
                    case .splitFeintRight:
                        desiredKey = .westieFlashStep6
                        bobY -= 0.055 * h // Grounded low A-frame drop!
                    case .glideWideRight(let elapsed, let duration):
                        desiredKey = .westieFlashStep7
                        let u = min(1.0, CGFloat(elapsed / max(duration, 0.01)))
                        bobY -= (0.05 - 0.04 * u) * h
                    case .snapCloseRight:
                        desiredKey = .westieFlashStep8
                    }

                case .bearShake(_, _, let frameIndex, let elapsed):
                    // Authentic 8-frame "狗熊哆嗦毛": 192x128 height-locked (99x66*k), crisp hard cuts!
                    desiredSize = flashStepDogSize
                    fadeDur = 0
                    let idx = min(max(frameIndex, 0), Self.bearShakeFrames.count - 1)
                    desiredKey = Self.bearShakeFrames[idx]
                    let dur = Self.bearShakeDurations[idx]
                    let u = min(1.0, CGFloat(elapsed / max(dur, 0.01)))
                    let h = topDogSize.height
                    switch idx {
                    case 1: // Forehead X-cross squat dip
                        bobY -= 0.035 * h
                        let dip = sin(u * .pi) * 0.05
                        breathYScale = 1.0 - dip
                        breathXScale = 1.0 + dip * 0.45
                    case 2: // Floppy wide T-pose wet-paw shake!
                        bobY -= 0.02 * h
                        strideTilt = sin(u * .pi * 4.0) * 0.032
                    case 3, 7: // Quick seesaw step transition
                        bobY += sin(u * .pi) * 0.035 * h
                    case 6: // Signature diagonal '/' lean floppy T-pose shake!
                        strideTilt = sin(u * .pi * 4.0) * 0.028
                    default:
                        break
                    }

                case .wandererKick(_, _, let frameIndex, let elapsed):
                    // Authentic 6-frame "浪子踢球": 192x128 height-locked (99x66*k), crisp folk-dance snap!
                    desiredSize = flashStepDogSize
                    fadeDur = 0
                    let idx = min(max(frameIndex, 0), Self.wandererKickFrames.count - 1)
                    desiredKey = Self.wandererKickFrames[idx]
                    let dur = Self.wandererKickDurations[idx]
                    let u = min(1.0, CGFloat(elapsed / max(dur, 0.01)))
                    let h = topDogSize.height
                    switch idx {
                    case 1: // Deep diagonal crouch
                        bobY -= 0.025 * h
                        breathYScale = 1.0 - sin(u * .pi) * 0.04
                    case 3: // Whip kick burst!
                        breathYScale = 1.0 + 0.05
                        breathXScale = 1.0 - 0.03
                    case 4: // Hero X-cross + W-arms showstopper hold!
                        let proud = sin(u * .pi) * 0.025
                        breathYScale = 1.0 + proud
                        breathXScale = 1.0 - proud * 0.4
                    default:
                        break
                    }

                case .headTilt(let stepIndex, _):
                    // Authentic 6-frame "歪头杀": stationary planted front paws, crisp zero-flash head tilts!
                    let idx = min(max(stepIndex, 0), Self.headTiltSequence.count - 1)
                    desiredKey = Self.headTiltSequence[idx].key
                    desiredSize = topDogSize
                    fadeDur = 0
                    let br = sin(breathPhase * 0.85) * 0.012
                    breathYScale = 1.0 + br
                    breathXScale = 1.0 - br * 0.45

                case .bellyRoll(let phase, _):
                    desiredSize = topDogSize
                    fadeDur = 0
                    switch phase {
                    case .flopDown(let elapsed, let duration):
                        desiredKey = .westieBellyRoll1
                        let u = CGFloat(elapsed / max(duration, 0.01))
                        let dip = sin(u * .pi) * 0.05
                        breathYScale = 1.0 - dip
                        breathXScale = 1.0 + dip * 0.45

                    case .waitingBellyUp(_, _, let wiggleElapsed):
                        // Gently alternate belly-up waiting poses (~0.65s) with cute tummy-rub breathing!
                        let wiggleIdx = Int(wiggleElapsed / 0.65) % 2
                        desiredKey = (wiggleIdx == 0) ? .westieBellyRoll2 : .westieBellyRoll3
                        let br = sin(breathPhase * 1.15) * 0.018
                        breathYScale = 1.0 + br
                        breathXScale = 1.0 - br * 0.45
                        strideTilt = sin(breathPhase * 0.9) * 0.022

                    case .rollingOver(let elapsed, let duration, _, _, _, _):
                        // Smooth 4-stage roll across spine (exact `打滚.mp4` pose sequence!):
                        //   0.00..0.22: tuck paws & tip back (`belly_roll_4`)
                        //   0.22..0.52: supine apex paws kicking in air (`belly_roll_5`, unmirrored!)
                        //   0.52..0.76: quarter-roll onto opposite side (`belly_roll_6`, mirrored!)
                        //   0.76..1.00: settle joyfully with paws curled (`belly_roll_3`, mirrored!)
                        let u = CGFloat(elapsed / max(duration, 0.01))
                        if u < 0.22 {
                            desiredKey = .westieBellyRoll4
                        } else if u < 0.52 {
                            desiredKey = .westieBellyRoll5
                            bobY += sin(((u - 0.22) / 0.30) * .pi) * 2.5 * scaleFactor
                        } else if u < 0.76 {
                            desiredKey = .westieBellyRoll6
                        } else {
                            desiredKey = .westieBellyRoll3
                        }

                    case .standingUp(let elapsed, let duration):
                        desiredKey = .westieBellyRoll1
                        let u = CGFloat(elapsed / max(duration, 0.01))
                        let push = sin(u * .pi) * 0.06
                        breathYScale = 1.0 + push
                        breathXScale = 1.0 - push * 0.4
                    }

                case .smileSit(let elapsed, _):
                    // Smiling warmly at camera (`westieSitTilt`) with spaced, playful head sways + natural pauses!
                    desiredKey = .westieSitTilt
                    fadeDur = 0
                    let t = CGFloat(elapsed)
                    strideTilt = Self.smoothTiltPulse(t: t, center: 1.05, radius: 0.48, amplitude: 0.115)
                        - Self.smoothTiltPulse(t: t, center: 2.45, radius: 0.48, amplitude: 0.115)
                        + Self.smoothTiltPulse(t: t, center: 3.55, radius: 0.38, amplitude: 0.070)
                    let br = sin(breathPhase * 0.85) * 0.016
                    breathYScale = 1.0 + br
                    breathXScale = 1.0 - br * 0.5
                }

            case .yawning(let elapsed, let duration):
                desiredKey = .westieYawn
                desiredSize = yawnDogSize // Match real head/body scale to walk/sit/loaf frames (54pt vs 66pt)
                fadeDur = 0
                let u = CGFloat(elapsed / max(duration, 0.01))
                // Subtle sleepy yawn stretch (+4.5% inhale -> -4% exhale)
                let yawnStretch = Self.smoothTiltPulse(t: u, center: 0.46, radius: 0.44, amplitude: 0.045)
                    - Self.smoothTiltPulse(t: u, center: 0.88, radius: 0.18, amplitude: 0.040)
                breathYScale = 1.0 + yawnStretch
                breathXScale = 1.0 - yawnStretch * 0.45

            case .settlingToSleep(let elapsed, let duration):
                // Smooth 2-step wind-down:
                // 1) Lie down with eyes open (`westieLoafCalm`)
                // 2) Heavy half-closed sleepy eyelids (`westieDrowsy`) -> then dissolves seamlessly into `westieSleep`!
                if elapsed < duration * 0.48 {
                    desiredKey = .westieLoafCalm
                    fadeDur = 0
                } else {
                    desiredKey = .westieDrowsy
                    fadeDur = 0.28
                }
                let br = sin(breathPhase * 0.65) * 0.016
                breathYScale = 1.0 + br
                breathXScale = 1.0 - br * 0.5

            case .greetingOnTop(let remaining):
                // Natural 2-stage wind-down with ZERO slideshow alternation:
                // Stage 1: stay in `westieSitTilt` with two spaced, organic curious head tilts & gentle breathing.
                // Stage 2 (final 3.5s if ignored): smoothly lie down into `westieLoafCalm` (eyes open),
                // which then cross-fades seamlessly (identical silhouette!) into `westieSleep` (eyes closing!).
                let windDownThreshold = min(3.5, greetingTotalDuration * 0.38)
                if remaining > windDownThreshold {
                    desiredKey = .westieSitTilt
                    fadeDur = 0.26
                    let t = greetingPhase
                    strideTilt = Self.smoothTiltPulse(t: t, center: 1.4, radius: 0.9, amplitude: 0.070)
                        - Self.smoothTiltPulse(t: t, center: 4.1, radius: 0.95, amplitude: 0.055)
                    let br = sin(breathPhase * 0.95) * 0.017
                    breathYScale = 1.0 + br
                    breathXScale = 1.0 - br * 0.5
                } else {
                    if displayedSpriteKey == .westieSitTilt {
                        squashSpring.impulse(-1.2) // Gentle weight settle as Westie lies down
                    }
                    desiredKey = .westieLoafCalm
                    fadeDur = 0.32
                    let br = sin(breathPhase * 0.72) * 0.015
                    breathYScale = 1.0 + br
                    breathXScale = 1.0 - br * 0.5
                }

            case .idle:
                desiredKey = .westieIdle // Hover never swaps idle sprite — tap to pet & sit!
                let br = sin(breathPhase * 0.85) * 0.013
                breathYScale = 1.0 + br
                breathXScale = 1.0 - br * 0.5

            case .sitCalm:
                desiredKey = .westieSitTilt
                let br = sin(breathPhase * 0.85) * 0.014
                breathYScale = 1.0 + br
                breathXScale = 1.0 - br * 0.5

            case .loafing:
                desiredKey = .westieLoafCalm
                fadeDur = (displayedSpriteKey == .westieSleep) ? 0.30 : 0
                let br = sin(breathPhase * 0.72) * 0.015
                breathYScale = 1.0 + br
                breathXScale = 1.0 - br * 0.5

            case .chinRest:
                // Exact same sprite & size as the end of `tentativePeek` -> ZERO jump after left/right glance!
                desiredKey = .westieTopPeekCenter
                desiredSize = topPeekDogSize
                let br = sin(breathPhase * 0.75) * 0.014
                breathYScale = 1.0 + br
                breathXScale = 1.0 - br * 0.5

            case .sleeping:
                desiredKey = .westieSleep
                // Identical silhouette to `westieDrowsy` / `westieLoafCalm` -> opaque-backing dissolve!
                fadeDur = (displayedSpriteKey == .westieDrowsy || displayedSpriteKey == .westieLoafCalm) ? 0.36 : 0
                let br = sin(breathPhase * 0.52) * 0.018
                breathYScale = 1.0 + br
                breathXScale = 1.0 - br * 0.5

            case .holdingTennisBall:
                desiredKey = .westieHoldingBall
                let br = sin(breathPhase * 1.1) * 0.016
                breathYScale = 1.0 + br
                breathXScale = 1.0 - br * 0.5

            case .walking, .chasingTreat:
                let speedRatio: Double = {
                    if case .chasingTreat = state { return 1.8 }
                    return max(0.35, Double(currentWalkSpeed / 44.0))
                }()
                walkAnimTimer += dt * speedRatio
                if walkAnimTimer >= 0.125 {
                    walkAnimTimer = 0
                    walkFrameIndex = (walkFrameIndex + 1) % Self.walkCycleFrames.count
                }
                desiredKey = Self.walkCycleFrames[walkFrameIndex]
                fadeDur = 0 // Crisp 4-frame pixel trot cycle without blur
                let isPassingFrame = (walkFrameIndex == 1 || walkFrameIndex == 3)
                let speedFactor = min(1.0, currentWalkSpeed / 44.0)
                bobY += (isPassingFrame ? 1.6 : 0.0) * speedFactor
                strideTilt = sin(breathPhase * 2.6) * 0.020 * speedFactor

            case .eatingTreat(let elapsed, _):
                // Happy 2-frame munching cycle (`eat_1` crunch <-> `eat_2` blissful ^ ^ chew) + tactile head bob!
                let chewIdx = Int(elapsed / 0.28) % 2
                desiredKey = (chewIdx == 0) ? .westieEat1 : .westieEat2
                fadeDur = 0
                let chewPhase = CGFloat((elapsed / 0.28).truncatingRemainder(dividingBy: 1.0))
                let munchSquash = sin(chewPhase * .pi) * 0.055
                breathYScale = 1.0 - munchSquash
                breathXScale = 1.0 + munchSquash * 0.45
                strideTilt = (chewIdx == 0 ? -0.035 : 0.030)

            case .peekingRight, .gliding, .dragged, .tuckedWaiting, .stealthTransition:
                desiredKey = .westieIdle
            }
        }

        // Anchor `westieTopPeek*` at `0.088` so the flat chin & shoulders rest 100% flush on the window top border
        // while the two rounded front paws hang naturally over the ledge with ZERO gap!
        let isTopPeekPose = (desiredKey == .westieTopPeekCenter
            || desiredKey == .westieTopPeekLeft
            || desiredKey == .westieTopPeekRight)
        dogSprite.anchorPoint = CGPoint(x: 0.5, y: isTopPeekPose ? 0.088 : 0.04)

        applySpriteTexture(desiredKey, size: desiredSize, crossfadeDuration: fadeDur, bank: bank)

        if state != .walking(direction: facingDirection, remaining: 0) {
            if case .walking = state {} else if case .topStory(step: .walkRight) = state {} else if case .chasingTreat = state {} else {
                currentWalkSpeed = 0
            }
        }

        // Stationary-body look-around, top-ledge peek, & front-facing symmetric dance sprites -> do NOT mirror!
        let isUnmirroredSprite = (desiredKey == .westieTopPeekCenter
            || desiredKey == .westieLookLeftHeadLeft
            || desiredKey == .westieLookLeftHeadCenter
            || desiredKey == .westieLookLeftHeadRight
            || desiredKey == .westieFlashStep1
            || desiredKey == .westieFlashStep2
            || desiredKey == .westieFlashStep3
            || desiredKey == .westieFlashStep4
            || desiredKey == .westieFlashStep5
            || desiredKey == .westieFlashStep6
            || desiredKey == .westieFlashStep7
            || desiredKey == .westieFlashStep8
            || desiredKey == .westieBearShake1
            || desiredKey == .westieBearShake2
            || desiredKey == .westieBearShake3
            || desiredKey == .westieBearShake4
            || desiredKey == .westieBearShake5
            || desiredKey == .westieBearShake6
            || desiredKey == .westieBearShake7
            || desiredKey == .westieBearShake8
            || desiredKey == .westieHeadTilt1
            || desiredKey == .westieHeadTilt2
            || desiredKey == .westieHeadTilt3
            || desiredKey == .westieHeadTilt4
            || desiredKey == .westieHeadTilt5
            || desiredKey == .westieHeadTilt6
            || desiredKey == .westieBellyRoll5)
        let effectiveDirSign: CGFloat = isUnmirroredSprite ? 1.0 : dirSign

        dogSprite.position = CGPoint(x: position.x, y: position.y + bobY)
        dogSprite.xScale = effectiveDirSign * (1.0 - s * 0.30) * breathXScale
        dogSprite.yScale = (1.0 + s * 0.34) * breathYScale
        dogSprite.zRotation = swingRotationSpring.value + strideTilt
        stepCrossfade(dt: dt)

        shadowNode.isHidden = true

        if case .holdingTennisBall = state {
            inviteBadgeNode.isHidden = false
            inviteBadgeNode.position = CGPoint(x: position.x, y: position.y + 80 * scaleFactor)
        } else {
            inviteBadgeNode.isHidden = true
        }
    }
}
