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

    // Focus timer -> gently hold tennis ball after 25 minutes of work
    private var focusAccumulator: TimeInterval = 0
    private let focusInviteInterval: TimeInterval = 25 * 60

    private var scaleFactor: CGFloat { CGFloat(preferences.dogScale) }
    private var topDogSize: CGSize { CGSize(width: 66 * scaleFactor, height: 66 * scaleFactor) }
    private var yawnDogSize: CGSize { CGSize(width: 54 * scaleFactor, height: 54 * scaleFactor) }
    private var chinLedgeDogSize: CGSize { CGSize(width: 54 * scaleFactor, height: 54 * scaleFactor) }
    private var topPeekDogSize: CGSize { CGSize(width: 44 * scaleFactor, height: 44 * scaleFactor) }
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
        let layout = snapshot.perchLayout
        switch targetZone {
        case .windowTop:
            if let top = layout.topPerch {
                let x = top.clampedX(top.minX + top.width * 0.62, margin: 22)
                beginStealthClimbToTop(
                    targetX: x,
                    windowID: layout.activeWindowID ?? trackedWindowID,
                    climbToGreet: false
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
        let crumbColor = (preferences.petSpecies == .goldenCat)
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
            note.text = (preferences.petSpecies == .goldenCat) ? "🐟✨" : "🦴✨"
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
                return .windowTop(targetX: top.clampedX(previousPosition.x, margin: 22), climbToGreet: false)
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
                beginStealthClimbToTop(targetX: x, windowID: layout.activeWindowID ?? trackedWindowID, climbToGreet: false)
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
                    reemergeDest = .windowTop(targetX: x, climbToGreet: false)
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

    /// Stealthily retracts from the right edge and climbs up from behind the active window's top bar!
    public func beginStealthClimbToTop(
        targetX: CGFloat,
        windowID: UInt32,
        climbToGreet: Bool,
        routineOverride: TopClimbRoutine? = nil
    ) {
        let originZone = perchZone
        let originWinID = trackedWindowID
        if originZone == .windowTop {
            retractTopSpriteKey = displayedSpriteKey
            retractTopSpriteSize = dogSprite.size
        }
        let initialPhase: StealthPhase = (originZone == .windowTop)
            ? .hiddenTraverse(elapsed: 0, duration: 0.16)
            : .retracting(elapsed: 0, duration: 0.62)
        state = .stealthTransition(
            phase: initialPhase,
            originZone: originZone,
            destination: .windowTop(targetX: targetX, climbToGreet: climbToGreet, routineOverride: routineOverride),
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
        if forceQuietSleep {
            state = .sleeping(remaining: 25.0)
        } else {
            state = .idle(remaining: 4.5)
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
        case .windowTop(let targetX, let climbToGreet, let routineOverride):
            squashSpring.impulse(-1.4) // Soft cushioned settle onto the top bar!
            if let top = destLayout.topPerch {
                landOnWindowTop(top, atX: targetX)
                if climbToGreet && !forceQuietSleep && !snapshot.isMeetingActive {
                    greetingPhase = 0
                    greetingTotalDuration = preferences.greetingDurationSeconds
                    didGreetingPerkHop = false
                    let chosenRoutine: TopClimbRoutine = {
                        let base = routineOverride ?? preferences.topClimbRoutine
                        if base == .random {
                            return Bool.random() ? .flashStep : .classicStory
                        }
                        return base
                    }()
                    if chosenRoutine == .flashStep {
                        // Start the iconic 5-beat upright bipedal "闪身步" dance (`起势 → 往右闪 → 停 → 准备 → 再往左闪 → 停`)!
                        facingDirection = 1.0
                        state = .topStory(step: .flashStep(
                            roundsRemaining: 2,
                            beat: .stance(elapsed: 0, duration: 0.44)
                        ))
                    } else {
                        // Classic story: orient briefly -> playful hop-walk LEFT -> look around -> walk RIGHT -> smile -> yawn -> sleep!
                        facingDirection = -1.0
                        state = .topStory(step: .postClimbPause(elapsed: 0, duration: 0.42))
                    }
                }
            } else {
                perchZone = .windowTop
                greetingPhase = 0
                greetingTotalDuration = preferences.greetingDurationSeconds
                didGreetingPerkHop = false
                state = climbToGreet ? .yawning(elapsed: 0, duration: 1.75) : .idle(remaining: 5.0)
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
                    case .windowTop(let targetX, let climbToGreet, let routineOverride):
                        if let top = destLayout.topPerch {
                            let clampedX = top.clampedX(targetX, margin: 18)
                            perchZone = .windowTop
                            currentPlatform = top
                            currentRightAnchor = nil
                            offsetFromWindowMinX = clampedX - top.windowMinX
                            position = CGPoint(x: clampedX, y: top.y)
                            destination = .windowTop(targetX: clampedX, climbToGreet: climbToGreet, routineOverride: routineOverride)
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
                    let settleDur: TimeInterval = (destination.perchZone == .windowTop) ? 0.72 : 0.44
                    state = .stealthTransition(
                        phase: .settlingOut(elapsed: 0, duration: settleDur),
                        originZone: originZone,
                        destination: destination,
                        originWindowID: originWindowID,
                        destWindowID: destWindowID
                    )
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

            case .flashStep(let roundsRemaining, let beat):
                currentWalkSpeed = 0
                facingDirection = 1.0
                let stepDist: CGFloat = min(52.0 * scaleFactor, max(24.0, top.width * 0.14))

                switch beat {
                case .stance(let elapsed, let duration):
                    let next = elapsed + dt
                    if next >= duration {
                        let rightX = min(top.maxX - 24, position.x + stepDist)
                        squashSpring.impulse(1.6)
                        state = .topStory(step: .flashStep(
                            roundsRemaining: roundsRemaining,
                            beat: .dodgeRight(elapsed: 0, duration: 0.48, startX: position.x, targetX: rightX)
                        ))
                    } else {
                        state = .topStory(step: .flashStep(
                            roundsRemaining: roundsRemaining,
                            beat: .stance(elapsed: next, duration: duration)
                        ))
                    }

                case .dodgeRight(let elapsed, let duration, let startX, let targetX):
                    let next = elapsed + dt
                    // Snappy dodge during first 48% of beat, then crisp swagger hold!
                    let dashU = min(1.0, CGFloat(next / max(duration * 0.48, 0.01)))
                    let eased = Self.easeOutCubic(dashU)
                    position.x = top.clampedX(startX + (targetX - startX) * eased, margin: 22)
                    offsetFromWindowMinX = position.x - top.windowMinX
                    if next >= duration {
                        squashSpring.impulse(-1.4)
                        state = .topStory(step: .flashStep(
                            roundsRemaining: roundsRemaining,
                            beat: .stopMid(elapsed: 0, duration: 0.42)
                        ))
                    } else {
                        state = .topStory(step: .flashStep(
                            roundsRemaining: roundsRemaining,
                            beat: .dodgeRight(elapsed: next, duration: duration, startX: startX, targetX: targetX)
                        ))
                    }

                case .stopMid(let elapsed, let duration):
                    let next = elapsed + dt
                    if next >= duration {
                        state = .topStory(step: .flashStep(
                            roundsRemaining: roundsRemaining,
                            beat: .readyLeft(elapsed: 0, duration: 0.38)
                        ))
                    } else {
                        state = .topStory(step: .flashStep(
                            roundsRemaining: roundsRemaining,
                            beat: .stopMid(elapsed: next, duration: duration)
                        ))
                    }

                case .readyLeft(let elapsed, let duration):
                    let next = elapsed + dt
                    if next >= duration {
                        let leftX = max(top.minX + 24, position.x - stepDist)
                        squashSpring.impulse(1.6)
                        state = .topStory(step: .flashStep(
                            roundsRemaining: roundsRemaining,
                            beat: .dodgeLeft(elapsed: 0, duration: 0.50, startX: position.x, targetX: leftX)
                        ))
                    } else {
                        state = .topStory(step: .flashStep(
                            roundsRemaining: roundsRemaining,
                            beat: .readyLeft(elapsed: next, duration: duration)
                        ))
                    }

                case .dodgeLeft(let elapsed, let duration, let startX, let targetX):
                    let next = elapsed + dt
                    let dashU = min(1.0, CGFloat(next / max(duration * 0.48, 0.01)))
                    let eased = Self.easeOutCubic(dashU)
                    position.x = top.clampedX(startX + (targetX - startX) * eased, margin: 22)
                    offsetFromWindowMinX = position.x - top.windowMinX
                    if next >= duration {
                        squashSpring.impulse(-1.4)
                        state = .topStory(step: .flashStep(
                            roundsRemaining: roundsRemaining,
                            beat: .finishStop(elapsed: 0, duration: 0.46)
                        ))
                    } else {
                        state = .topStory(step: .flashStep(
                            roundsRemaining: roundsRemaining,
                            beat: .dodgeLeft(elapsed: next, duration: duration, startX: startX, targetX: targetX)
                        ))
                    }

                case .finishStop(let elapsed, let duration):
                    let next = elapsed + dt
                    if next >= duration {
                        let remainingRounds = roundsRemaining - 1
                        if remainingRounds > 0 {
                            // Repeat one more rhythmic beat starting right back into `起势`!
                            state = .topStory(step: .flashStep(
                                roundsRemaining: remainingRounds,
                                beat: .stance(elapsed: 0, duration: 0.38)
                            ))
                        } else {
                            // Done dancing -> sit smiling proudly, then quiet pause -> yawn -> sleep!
                            state = .topStory(step: .smileSit(elapsed: 0, duration: 4.2))
                        }
                    } else {
                        state = .topStory(step: .flashStep(
                            roundsRemaining: roundsRemaining,
                            beat: .finishStop(elapsed: next, duration: duration)
                        ))
                    }
                }

            case .smileSit(let elapsed, let duration):
                currentWalkSpeed = 0
                facingDirection = 1.0
                // If owner hovers gently while Westie smiles at them, extend cozy smile a bit or happily loaf
                let next = elapsed + dt
                if next >= duration {
                    // Quiet 2.6s stillness pause before yawning ("hmm, owner is busy...")
                    state = .topStory(step: .preYawnWait(elapsed: 0, duration: 2.6))
                } else {
                    state = .topStory(step: .smileSit(elapsed: next, duration: duration))
                }

            case .preYawnWait(let elapsed, let duration):
                currentWalkSpeed = 0
                facingDirection = 1.0
                let next = elapsed + dt
                if next >= duration {
                    state = .yawning(elapsed: 0, duration: 1.85)
                } else {
                    state = .topStory(step: .preYawnWait(elapsed: next, duration: duration))
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
            let next = remaining - dt
            if next <= 0 {
                if perchZone == .windowTop, let top = layout.topPerch {
                    state = WestieBehaviorPlanner.chooseNextTopBehavior(
                        currentX: position.x,
                        platform: top,
                        context: context
                    )
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
                beginStealthClimbToTop(
                    targetX: targetX,
                    windowID: layout.activeWindowID ?? trackedWindowID,
                    climbToGreet: true
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

    /// Smoothly cross-fades `dogSprite` to `nextKey` (for current `preferences.petSpecies`) using `fadeOutSprite`,
    /// eliminating 1-frame texture pops!
    private func applySpriteTexture(
        _ nextKey: SpriteAssetKey,
        size: CGSize,
        crossfadeDuration: TimeInterval,
        bank: SpriteBank
    ) {
        let species = preferences.petSpecies
        let speciesChanged = (displayedSpriteSpecies != species)
        if displayedSpriteKey != nextKey || speciesChanged {
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
        }
        dogSprite.texture = bank.texture(for: nextKey, species: species)
        dogSprite.size = size
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
        // Smooth S-curve dissolve; keep outgoing sprite anchored to live window position while fading
        let eased = Self.easeInOutCubic(u)
        fadeOutSprite.position = dogSprite.position
        fadeOutSprite.alpha = 1.0 - eased
        dogSprite.alpha = eased
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
            // Mask y >= position.y so Westie cleanly emerges from / sinks behind the window title bar!
            cropMaskNode.anchorPoint = CGPoint(x: 0.5, y: 0.0)
            cropMaskNode.position = CGPoint(x: position.x, y: position.y)
            cropNode.maskNode = cropMaskNode
            dogSprite.anchorPoint = CGPoint(x: 0.5, y: 0.04)
            let targetSize = topSize ?? topDogSize
            applySpriteTexture(topTextureKey, size: targetSize, crossfadeDuration: crossfadeDuration, bank: bank)
            let sinkY = f * (targetSize.height + 4.0)
            // Keep top-peek left/right un-mirrored so Left literally looks left and Right literally looks right!
            let isDirectionalPeek = (topTextureKey == .westieTopPeekCenter
                || topTextureKey == .westieTopPeekLeft
                || topTextureKey == .westieTopPeekRight)
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
        var fadeDur: TimeInterval = 0.24

        if case .walking = state, currentWalkSpeed < 5.0 {
            desiredKey = .westieIdle // Stay calmly standing on hover — never flash to sitting sprite!
        } else {
            switch state {
            case .topStory(let step):
                switch step {
                case .postClimbPause, .postWalkPause:
                    desiredKey = .westieIdle
                    fadeDur = 0.18
                    let br = sin(breathPhase * 0.9) * 0.014
                    breathYScale = 1.0 + br
                    breathXScale = 1.0 - br * 0.5

                case .hopLeft(_, let hopElapsed, let hopDuration, _, _, _):
                    if hopElapsed < hopDuration {
                        let u = CGFloat(hopElapsed / max(hopDuration, 0.01))
                        // Dedicated 3-frame playful puppy bound cycle (mirrored LEFT via dirSign = -1):
                        // 0.00..0.18: anticipation crouch on ground (`westieHopCrouch`)
                        // 0.18..0.76: true airborne puppy leap (`westieHopAir`, smooth 13pt parabolic arc!)
                        // 0.76..1.00: front-paw cushioned landing (`westieHopLand`)
                        if u < 0.18 {
                            desiredKey = .westieHopCrouch
                            fadeDur = 0.06
                            let dip = sin((u / 0.18) * .pi) * 0.06
                            breathYScale = 1.0 - dip
                            breathXScale = 1.0 + dip * 0.45
                        } else if u < 0.76 {
                            let airU = (u - 0.18) / 0.58
                            bobY += sin(airU * .pi) * 13.0
                            desiredKey = .westieHopAir
                            fadeDur = 0.05
                            strideTilt = cos(airU * .pi) * -0.07
                            let stretch = sin(airU * .pi) * 0.05
                            breathYScale = 1.0 + stretch
                            breathXScale = 1.0 - stretch * 0.35
                        } else {
                            let landU = (u - 0.76) / 0.24
                            desiredKey = .westieHopLand
                            fadeDur = 0.06
                            let cushion = sin(landU * .pi) * 0.05
                            breathYScale = 1.0 - cushion
                            breathXScale = 1.0 + cushion * 0.4
                        }
                    } else {
                        // Brief grounded beat between bouncy hops
                        desiredKey = .westieHopCrouch
                        fadeDur = 0.08
                    }

                case .lookAroundPause(let elapsed, _):
                    // Stationary body facing LEFT (`xScale = +1.0` unmirrored!); ONLY the head turns:
                    // 0.00..0.35s: settle looking left
                    // 0.35..0.50s -> 0.50..1.35s: peek RIGHT first (over shoulder!)
                    // 1.35..1.50s -> 1.50..2.35s: peek LEFT!
                    // 2.35..2.50s -> 2.50..3.50s: peek RIGHT again before strolling right!
                    fadeDur = 0.14
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
                        desiredKey = .westieIdle // Calm pause in place on hover — no jarring sprite swap!
                        fadeDur = 0.16
                    } else {
                        let speedRatio = max(0.35, Double(currentWalkSpeed / 44.0))
                        walkAnimTimer += dt * speedRatio
                        if walkAnimTimer >= 0.125 {
                            walkAnimTimer = 0
                            walkFrameIndex = (walkFrameIndex + 1) % Self.walkCycleFrames.count
                        }
                        desiredKey = Self.walkCycleFrames[walkFrameIndex]
                        fadeDur = 0
                        let isPassingFrame = (walkFrameIndex == 1 || walkFrameIndex == 3)
                        let speedFactor = min(1.0, currentWalkSpeed / 44.0)
                        bobY += (isPassingFrame ? 1.6 : 0.0) * speedFactor
                        strideTilt = sin(breathPhase * 2.6) * 0.020 * speedFactor
                    }

                case .flashStep(_, let beat):
                    // Viral upright bipedal "闪身步" dance: crisp pose beats + snappy hop-dash sidesteps!
                    fadeDur = 0.07
                    switch beat {
                    case .stance(let elapsed, let duration):
                        desiredKey = .westieFlashStep1
                        let u = CGFloat(elapsed / max(duration, 0.01))
                        let coil = Self.smoothTiltPulse(t: u, center: 0.72, radius: 0.30, amplitude: 0.06)
                        breathYScale = 1.0 - coil
                        breathXScale = 1.0 + coil * 0.45

                    case .dodgeRight(let elapsed, let duration, _, _):
                        desiredKey = .westieFlashStep2
                        let dashU = min(1.0, CGFloat(elapsed / max(duration * 0.48, 0.01)))
                        let hopY: CGFloat = sin(dashU * .pi) * 6.5 * scaleFactor
                        bobY += hopY
                        strideTilt = -sin(dashU * .pi) * 0.08

                    case .stopMid(let elapsed, let duration), .finishStop(let elapsed, let duration):
                        desiredKey = .westieFlashStep3
                        let u = CGFloat(elapsed / max(duration, 0.01))
                        let snap = Self.smoothTiltPulse(t: u, center: 0.22, radius: 0.22, amplitude: 0.05)
                        breathYScale = 1.0 + snap
                        breathXScale = 1.0 - snap * 0.35

                    case .readyLeft(let elapsed, let duration):
                        desiredKey = .westieFlashStep4
                        let u = CGFloat(elapsed / max(duration, 0.01))
                        let coil = Self.smoothTiltPulse(t: u, center: 0.72, radius: 0.30, amplitude: 0.06)
                        breathYScale = 1.0 - coil
                        breathXScale = 1.0 + coil * 0.45

                    case .dodgeLeft(let elapsed, let duration, _, _):
                        desiredKey = .westieFlashStep5
                        let dashU = min(1.0, CGFloat(elapsed / max(duration * 0.48, 0.01)))
                        let hopY: CGFloat = sin(dashU * .pi) * 6.5 * scaleFactor
                        bobY += hopY
                        strideTilt = sin(dashU * .pi) * 0.08
                    }

                case .smileSit(let elapsed, _):
                    // Smiling warmly at camera (`westieSitTilt`) with spaced, playful head sways + natural pauses!
                    desiredKey = .westieSitTilt
                    fadeDur = 0.26
                    let t = CGFloat(elapsed)
                    // Beat 1 (0.7..1.6s): tilt left +6.5° -> calm pause -> Beat 2 (2.2..3.1s): tilt right -6.5° -> Beat 3 (3.5..4.2s): tiny tilt left +4°
                    strideTilt = Self.smoothTiltPulse(t: t, center: 1.15, radius: 0.48, amplitude: 0.115)
                        - Self.smoothTiltPulse(t: t, center: 2.65, radius: 0.48, amplitude: 0.115)
                        + Self.smoothTiltPulse(t: t, center: 3.85, radius: 0.38, amplitude: 0.070)
                    let br = sin(breathPhase * 0.85) * 0.016
                    breathYScale = 1.0 + br
                    breathXScale = 1.0 - br * 0.5

                case .preYawnWait:
                    // Quiet 2.6s stillness sitting calmly before getting sleepy and yawning
                    desiredKey = .westieSitTilt
                    fadeDur = 0.24
                    let br = sin(breathPhase * 0.65) * 0.015
                    breathYScale = 1.0 + br
                    breathXScale = 1.0 - br * 0.5
                }

            case .yawning(let elapsed, let duration):
                desiredKey = .westieYawn
                desiredSize = yawnDogSize // Match real head/body scale to walk/sit/loaf frames (54pt vs 66pt)
                fadeDur = 0.26
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
                    fadeDur = 0.30
                } else {
                    desiredKey = .westieDrowsy
                    fadeDur = 0.38
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
                fadeDur = (displayedSpriteKey == .westieSleep) ? 0.36 : 0.26
                let br = sin(breathPhase * 0.72) * 0.015
                breathYScale = 1.0 + br
                breathXScale = 1.0 - br * 0.5

            case .chinRest:
                desiredKey = .westieChinLedge
                desiredSize = chinLedgeDogSize // Head scale matched 1:1 with full-body poses!
                let br = sin(breathPhase * 0.75) * 0.014
                breathYScale = 1.0 + br
                breathXScale = 1.0 - br * 0.5

            case .sleeping:
                desiredKey = .westieSleep
                // Identical silhouette to `westieDrowsy` / `westieLoafCalm` -> 0.44s dissolve looks like eyes smoothly closing!
                fadeDur = (displayedSpriteKey == .westieDrowsy || displayedSpriteKey == .westieLoafCalm) ? 0.44 : 0.32
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
                fadeDur = 0.05
                let chewPhase = CGFloat((elapsed / 0.28).truncatingRemainder(dividingBy: 1.0))
                let munchSquash = sin(chewPhase * .pi) * 0.055
                breathYScale = 1.0 - munchSquash
                breathXScale = 1.0 + munchSquash * 0.45
                strideTilt = (chewIdx == 0 ? -0.035 : 0.030)

            case .peekingRight, .gliding, .dragged, .tuckedWaiting, .stealthTransition:
                desiredKey = .westieIdle
            }
        }

        applySpriteTexture(desiredKey, size: desiredSize, crossfadeDuration: fadeDur, bank: bank)

        if state != .walking(direction: facingDirection, remaining: 0) {
            if case .walking = state {} else if case .topStory(step: .walkRight) = state {} else if case .chasingTreat = state {} else {
                currentWalkSpeed = 0
            }
        }

        // Stationary-body look-around & front-facing Flash-Step sprites have explicit left/right orientation -> do NOT mirror!
        let isUnmirroredSprite = (desiredKey == .westieLookLeftHeadLeft
            || desiredKey == .westieLookLeftHeadCenter
            || desiredKey == .westieLookLeftHeadRight
            || desiredKey == .westieFlashStep1
            || desiredKey == .westieFlashStep2
            || desiredKey == .westieFlashStep3
            || desiredKey == .westieFlashStep4
            || desiredKey == .westieFlashStep5)
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
