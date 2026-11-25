import AppKit
import SpriteKit

@MainActor
public final class CompanionController {
    public let rootNode = SKNode()

    private let cropNode = SKCropNode()
    private let cropMaskNode: SKSpriteNode
    private let dogSprite: SKSpriteNode
    private let shadowNode: SKShapeNode
    private let inviteBadgeNode: SKNode
    private var treatNode: SKSpriteNode?

    public private(set) var perchZone: PerchZone = .windowTop
    public private(set) var currentPlatform: WindowPlatform?
    public private(set) var currentRightAnchor: RightEdgeAnchor?
    public private(set) var state: CompanionBehaviorState = .idle(remaining: 4.0)

    public var perchPreference: PerchPreference = .auto {
        didSet {
            UserDefaults.standard.set(perchPreference.rawValue, forKey: "westie.companion.perchPreference")
        }
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
    private var walkFrameToggle: Bool = false
    private var currentWalkSpeed: CGFloat = 0
    private var breathPhase: CGFloat = 0
    private var hoverWavePhase: CGFloat = 0

    // Hover & tactile press/drag tracking
    public private(set) var isHoveringDog: Bool = false
    public private(set) var isPointerDownOnDog: Bool = false
    private var isPeekHoverTextureActive: Bool = false
    private var pressStartScenePoint: CGPoint = .zero
    private var dragGrabOffset: CGPoint = .zero
    private var dragBlendProgress: CGFloat = 0
    private var lastDragScenePoint: CGPoint = .zero
    private var smoothedDragVelocityX: CGFloat = 0
    private var calmTapPoseIndex: Int = 0

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
    private var offsetFromWindowMaxY: CGFloat = 68
    private var screenRightCustomYRatio: CGFloat = 0.66
    private var zoneStayTimer: TimeInterval = 0

    // Focus timer -> gently hold tennis ball after 25 minutes of work
    private var focusAccumulator: TimeInterval = 0
    private let focusInviteInterval: TimeInterval = 25 * 60

    private let topDogSize = CGSize(width: 66, height: 66)
    private let peekDogSize = CGSize(width: 76, height: 76)

    public var isNeedingHighFPS: Bool {
        state.isHighFrameRateNeeded
            || treatNode != nil
            || isHoveringDog
            || isPointerDownOnDog
            || !peekHoverSpring.isSettled
            || !peekEmergeSpring.isSettled
            || !squashSpring.isSettled
            || !tapHopSpring.isSettled
            || !swingRotationSpring.isSettled
    }

    public init() {
        if let saved = UserDefaults.standard.string(forKey: "westie.companion.perchPreference"),
           let pref = PerchPreference(rawValue: saved)
        {
            self.perchPreference = pref
        }

        shadowNode = SKShapeNode(ellipseOf: CGSize(width: 42, height: 9))
        shadowNode.fillColor = NSColor(calibratedWhite: 0.0, alpha: 0.20)
        shadowNode.strokeColor = .clear
        shadowNode.zPosition = 1

        cropMaskNode = SKSpriteNode(color: .white, size: CGSize(width: 4096, height: 4096))
        cropMaskNode.anchorPoint = CGPoint(x: 0.0, y: 0.5)

        dogSprite = SKSpriteNode(
            texture: SpriteBank.shared.texture(for: .westieIdle),
            color: .clear,
            size: topDogSize
        )
        dogSprite.anchorPoint = CGPoint(x: 0.5, y: 0.04)
        dogSprite.zPosition = 3

        inviteBadgeNode = CompanionController.buildInviteBadge()
        inviteBadgeNode.position = CGPoint(x: 0, y: 78)
        inviteBadgeNode.zPosition = 10
        inviteBadgeNode.isHidden = true

        rootNode.addChild(shadowNode)
        cropNode.zPosition = 3
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
        let layout = snapshot.perchLayout
        if layout.isFullScreenMode {
            snapToScreenRightPeek(layout.screenRightPeek, sceneSize: sceneSize)
        } else if perchPreference == .rightPeek, let right = layout.windowRightPeek {
            trackedWindowID = layout.activeWindowID ?? 0
            snapToWindowRightPeek(right, windowMaxY: layout.activeWindowFrame?.maxY ?? right.maxY)
        } else if let top = layout.topPerch {
            let startX = top.clampedX(top.minX + top.width * 0.62, margin: 22)
            landOnWindowTop(top, atX: startX)
        } else if let right = layout.windowRightPeek {
            trackedWindowID = layout.activeWindowID ?? 0
            snapToWindowRightPeek(right, windowMaxY: layout.activeWindowFrame?.maxY ?? right.maxY)
        } else {
            snapToScreenRightPeek(layout.screenRightPeek, sceneSize: sceneSize)
        }
        syncVisuals(dt: 0)
    }

    /// Interactive hitbox in scene coordinates — padded generously around Westie without blocking window content!
    public func interactiveHitRect() -> CGRect {
        var rect: CGRect
        if case .dragged = state {
            rect = CGRect(x: position.x - 48, y: position.y - 20, width: 96, height: 96)
        } else {
            switch perchZone {
            case .windowTop:
                rect = CGRect(
                    x: position.x - 44,
                    y: position.y - 8,
                    width: 88,
                    height: 80
                )
            case .screenRightPeek:
                // Peeking leftward from right screen edge (`position.x == screenWidth`)
                rect = CGRect(
                    x: position.x - 58,
                    y: position.y - 46,
                    width: 62,
                    height: 92
                )
            case .windowRightPeek:
                // Peeking rightward from active window's right border (`position.x == windowMaxX`)
                // Starts at `position.x - 2` so we never block the window's inner scrollbar!
                rect = CGRect(
                    x: position.x - 2,
                    y: position.y - 46,
                    width: 58,
                    height: 92
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

    public func triggerTennisInvite() {
        state = .holdingTennisBall(remaining: 25.0)
    }

    public func summonToFrontWindow(snapshot: ActiveWorkspaceSnapshot, sceneSize: CGSize) {
        let layout = snapshot.perchLayout
        treatNode?.removeFromParent()
        treatNode = nil

        if layout.isFullScreenMode {
            snapToScreenRightPeek(layout.screenRightPeek, sceneSize: sceneSize)
            return
        }
        if perchPreference == .rightPeek, let right = layout.windowRightPeek {
            trackedWindowID = layout.activeWindowID ?? 0
            snapToWindowRightPeek(right, windowMaxY: layout.activeWindowFrame?.maxY ?? right.maxY)
        } else if let top = layout.topPerch {
            let x = top.clampedX(top.minX + top.width * 0.62, margin: 22)
            landOnWindowTop(top, atX: x)
            state = .sitCalm(remaining: 5.0)
        } else if let right = layout.windowRightPeek {
            trackedWindowID = layout.activeWindowID ?? 0
            snapToWindowRightPeek(right, windowMaxY: layout.activeWindowFrame?.maxY ?? right.maxY)
        } else {
            snapToScreenRightPeek(layout.screenRightPeek, sceneSize: sceneSize)
        }
    }

    public func moveImmediatelyToZone(_ targetZone: PerchZone, snapshot: ActiveWorkspaceSnapshot, sceneSize: CGSize) {
        let layout = snapshot.perchLayout
        switch targetZone {
        case .windowTop:
            if let top = layout.topPerch {
                let x = top.clampedX(top.minX + top.width * 0.62, margin: 22)
                beginSmoothGlide(to: CGPoint(x: x, y: top.y), targetZone: .windowTop, layout: layout)
            }
        case .windowRightPeek:
            if let right = layout.windowRightPeek {
                emergeIntoRightPeek(
                    anchor: right,
                    targetY: right.defaultY,
                    zone: .windowRightPeek,
                    layout: layout
                )
            } else {
                emergeIntoRightPeek(
                    anchor: layout.screenRightPeek,
                    targetY: layout.screenRightPeek.clampedY(sceneSize.height * screenRightCustomYRatio),
                    zone: .screenRightPeek,
                    layout: layout
                )
            }
        case .screenRightPeek:
            let y = layout.screenRightPeek.clampedY(sceneSize.height * screenRightCustomYRatio)
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

        let node = SKSpriteNode(texture: SpriteBank.shared.texture(for: .boneTreat))
        node.size = CGSize(width: 26, height: 26)
        node.position = CGPoint(x: treatX, y: top.y + 13)
        node.zPosition = 2
        rootNode.addChild(node)
        node.run(SKAction.sequence([
            SKAction.moveBy(x: 0, y: 10, duration: 0.11),
            SKAction.moveBy(x: 0, y: -10, duration: 0.13)
        ]))
        treatNode = node
        squashSpring.impulse(1.8)
        state = .chasingTreat(treatX: treatX)
    }

    /// Updates continuous hover state with spring physics and zero intrusive popups!
    public func setHovering(_ hovering: Bool) {
        guard isHoveringDog != hovering else { return }
        isHoveringDog = hovering
        peekHoverSpring.target = hovering ? 1.0 : 0.0
        if hovering {
            if perchZone == .screenRightPeek || perchZone == .windowRightPeek {
                squashSpring.impulse(1.2)
            } else if state.isGrounded {
                squashSpring.impulse(0.8)
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

        // Check distance to screen right edge, active window right edge, and active window top edge
        var candidates: [(dist: CGFloat, point: CGPoint, zone: PerchZone)] = []

        if let top = layout.topPerch {
            let targetX = top.clampedX(scenePoint.x, margin: 20)
            let pt = CGPoint(x: targetX, y: top.y)
            candidates.append((hypot(scenePoint.x - pt.x, scenePoint.y - pt.y), pt, .windowTop))
        }
        if let right = layout.windowRightPeek {
            let targetY = right.clampedY(scenePoint.y)
            let pt = CGPoint(x: right.edgeX, y: targetY)
            candidates.append((hypot(scenePoint.x - pt.x, scenePoint.y - pt.y), pt, .windowRightPeek))
        }
        if scenePoint.x >= sceneSize.width - 108 {
            let anchor = layout.screenRightPeek
            let clampedY = anchor.clampedY(scenePoint.y)
            if sceneSize.height > 100 {
                screenRightCustomYRatio = min(max(clampedY / sceneSize.height, 0.15), 0.88)
            }
            let pt = CGPoint(x: anchor.edgeX, y: clampedY)
            candidates.append((hypot(scenePoint.x - pt.x, scenePoint.y - pt.y), pt, .screenRightPeek))
        }

        if let best = candidates.min(by: { $0.dist < $1.dist }) {
            if best.zone == .windowRightPeek, let winMaxY = layout.activeWindowFrame?.maxY {
                offsetFromWindowMaxY = max(42, winMaxY - best.point.y)
            }
            beginSmoothGlide(to: best.point, targetZone: best.zone, layout: layout)
        } else {
            let anchor = layout.screenRightPeek
            beginSmoothGlide(to: CGPoint(x: anchor.edgeX, y: anchor.defaultY), targetZone: .screenRightPeek, layout: layout)
        }
    }

    private func handleGentleTap() {
        if perchZone == .screenRightPeek || perchZone == .windowRightPeek {
            peekHoverSpring.impulse(3.0)
            squashSpring.impulse(2.1)
            return
        }

        // Gentle Q-bounce hop + cycle through calm companion poses on top bar
        tapHopSpring.impulse(135.0)
        squashSpring.impulse(2.5)
        if !forceQuietSleep {
            calmTapPoseIndex = (calmTapPoseIndex + 1) % 4
            switch calmTapPoseIndex {
            case 0: state = .sitCalm(remaining: 9.0)
            case 1: state = .loafing(remaining: 11.0)
            case 2: state = .chinRest(remaining: 10.0)
            default: state = .idle(remaining: 7.0)
            }
        }
    }

    // MARK: - Frame Update

    public func update(dt: TimeInterval, snapshot: ActiveWorkspaceSnapshot, sceneSize: CGSize) {
        let clampedDt = min(max(dt, 0.001), 0.08)
        breathPhase += CGFloat(clampedDt) * 2.2
        zoneStayTimer += clampedDt

        let layout = snapshot.perchLayout
        updateWindowMotionInertia(layout: layout, dt: clampedDt)

        // Step all physical springs
        peekHoverSpring.target = isHoveringDog ? 1.0 : 0.0
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

        reconcileWithActiveWindow(layout: layout, sceneSize: sceneSize)

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

        stepState(dt: clampedDt, layout: layout, context: context, sceneSize: sceneSize)
        syncVisuals(dt: clampedDt)
    }

    private func updateWindowMotionInertia(layout: ActiveWindowPerchLayout, dt: TimeInterval) {
        defer {
            lastTrackedWindowFrame = (layout.activeWindowID == trackedWindowID) ? layout.activeWindowFrame : nil
        }
        guard state != .dragged,
              layout.activeWindowID == trackedWindowID,
              let prevFrame = lastTrackedWindowFrame,
              let curFrame = layout.activeWindowFrame,
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

    // MARK: - Active Window & Fullscreen Perch Tracking

    private func reconcileWithActiveWindow(layout: ActiveWindowPerchLayout, sceneSize: CGSize) {
        if case .dragged = state { return }
        if case .gliding = state { return }

        // 1. Fullscreen Space or maximized window -> smoothly emerge from right edge of screen!
        if layout.isFullScreenMode {
            let anchor = layout.screenRightPeek
            let desiredY = anchor.clampedY(sceneSize.height * screenRightCustomYRatio)
            if perchZone != .screenRightPeek {
                treatNode?.removeFromParent()
                treatNode = nil
                emergeIntoRightPeek(anchor: anchor, targetY: desiredY, zone: .screenRightPeek, layout: layout)
            } else {
                currentRightAnchor = anchor
                position = CGPoint(x: anchor.edgeX, y: desiredY)
            }
            return
        }

        // 2. Non-fullscreen mode: did the user switch to a different active window (or exit fullscreen)?
        let activeID = layout.activeWindowID ?? 0
        let switchedWindow = (activeID != 0 && activeID != trackedWindowID)
        let returningFromFullScreen = (perchZone == .screenRightPeek && (layout.topPerch != nil || layout.windowRightPeek != nil))

        if switchedWindow || returningFromFullScreen {
            treatNode?.removeFromParent()
            treatNode = nil
            trackedWindowID = activeID
            lastTrackedWindowFrame = layout.activeWindowFrame
            transitionToActiveWindowPreferredSpot(layout: layout, sceneSize: sceneSize)
            return
        }

        // 3. Same active window: locked at 60/120Hz to live window top or right border!
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
            } else if let right = layout.windowRightPeek {
                // Window moved up to touch menu bar -> smoothly peek out from its right border!
                treatNode?.removeFromParent()
                treatNode = nil
                emergeIntoRightPeek(anchor: right, targetY: right.defaultY, zone: .windowRightPeek, layout: layout)
            } else {
                snapToScreenRightPeek(layout.screenRightPeek, sceneSize: sceneSize)
            }

        case .windowRightPeek:
            if let right = layout.windowRightPeek {
                let winMaxY = layout.activeWindowFrame?.maxY ?? right.maxY
                let desiredY = right.clampedY(winMaxY - offsetFromWindowMaxY)
                position = CGPoint(x: right.edgeX, y: desiredY)
                currentRightAnchor = right
            } else if let top = layout.topPerch {
                // Window moved flush to right edge of screen -> hop onto its top border!
                let x = top.clampedX(top.minX + top.width * 0.65, margin: 20)
                beginSmoothGlide(to: CGPoint(x: x, y: top.y), targetZone: .windowTop, layout: layout)
            } else {
                snapToScreenRightPeek(layout.screenRightPeek, sceneSize: sceneSize)
            }

        case .screenRightPeek:
            let anchor = layout.screenRightPeek
            position = CGPoint(x: anchor.edgeX, y: anchor.clampedY(sceneSize.height * screenRightCustomYRatio))
            currentRightAnchor = anchor
        }
    }

    private func transitionToActiveWindowPreferredSpot(layout: ActiveWindowPerchLayout, sceneSize: CGSize) {
        if perchPreference == .rightPeek, let right = layout.windowRightPeek {
            emergeIntoRightPeek(anchor: right, targetY: right.defaultY, zone: .windowRightPeek, layout: layout)
        } else if let top = layout.topPerch {
            let preferredX = top.clampedX(top.minX + top.width * 0.62, margin: 22)
            // If emerging from screen/window right peek near the same corner, hop smoothly onto the top edge!
            beginSmoothGlide(to: CGPoint(x: preferredX, y: top.y), targetZone: .windowTop, layout: layout)
        } else if let right = layout.windowRightPeek {
            emergeIntoRightPeek(anchor: right, targetY: right.defaultY, zone: .windowRightPeek, layout: layout)
        } else {
            let anchor = layout.screenRightPeek
            let desiredY = anchor.clampedY(sceneSize.height * screenRightCustomYRatio)
            emergeIntoRightPeek(anchor: anchor, targetY: desiredY, zone: .screenRightPeek, layout: layout)
        }
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

    // MARK: - Calm Behavior State Machine

    private func stepState(
        dt: TimeInterval,
        layout: ActiveWindowPerchLayout,
        context: CompanionContext,
        sceneSize: CGSize
    ) {
        switch state {
        case .idle(let remaining),
             .sitCalm(let remaining),
             .loafing(let remaining),
             .chinRest(let remaining),
             .sleeping(let remaining):
            let next = remaining - dt
            if next <= 0 {
                if perchZone == .windowTop, let top = layout.topPerch {
                    // Occasionally visit the active window's right edge (`右侧`) when in `.auto` mode!
                    if perchPreference == .auto,
                       !context.forceQuietSleep,
                       !isHoveringDog,
                       zoneStayTimer >= 26.0,
                       let right = layout.windowRightPeek,
                       Double.random(in: 0...1) < 0.28
                    {
                        emergeIntoRightPeek(
                            anchor: right,
                            targetY: right.defaultY,
                            zone: .windowRightPeek,
                            layout: layout
                        )
                    } else {
                        state = WestieBehaviorPlanner.chooseNextTopBehavior(
                            currentX: position.x,
                            platform: top,
                            context: context
                        )
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
            let next = remaining - dt
            if next <= 0 {
                // If non-fullscreen and `.auto` mode, occasionally climb back onto the active window's top edge!
                if perchZone == .windowRightPeek,
                   perchPreference == .auto,
                   !isHoveringDog,
                   let top = layout.topPerch
                {
                    let targetX = top.clampedX(top.maxX - min(96, top.width * 0.28), margin: 22)
                    beginSmoothGlide(to: CGPoint(x: targetX, y: top.y), targetZone: .windowTop, layout: layout)
                } else if context.shouldOfferTennisBreak {
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
            if abs(dx) < 12 {
                treatNode?.removeFromParent()
                treatNode = nil
                squashSpring.impulse(-2.2)
                state = .loafing(remaining: 8.0)
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
                // If walking right up to the right corner in `.auto` mode, sometimes peek over the right edge!
                if nextX >= top.maxX - 18,
                   perchPreference == .auto,
                   zoneStayTimer >= 18.0,
                   let right = layout.windowRightPeek,
                   Double.random(in: 0...1) < 0.35
                {
                    emergeIntoRightPeek(
                        anchor: right,
                        targetY: right.defaultY,
                        zone: .windowRightPeek,
                        layout: layout
                    )
                    return
                }
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

    // MARK: - Visual Sync

    private func syncVisuals(dt: TimeInterval) {
        let bank = SpriteBank.shared
        let s = min(max(squashSpring.value, -0.30), 0.30)
        let dirSign: CGFloat = facingDirection >= 0 ? 1.0 : -1.0

        // 1. Dragged Pose: velocity pendulum swing + squash/stretch
        if case .dragged = state {
            cropNode.maskNode = nil
            dogSprite.size = topDogSize
            dogSprite.anchorPoint = CGPoint(x: 0.5, y: 0.04)
            dogSprite.texture = bank.texture(for: .westieDangling)
            dogSprite.position = position
            dogSprite.xScale = dirSign * (1.0 - s * 0.28)
            dogSprite.yScale = 1.0 + s * 0.32
            dogSprite.zRotation = swingRotationSpring.value + sin(breathPhase * 2.2) * 0.035
            shadowNode.isHidden = true
            inviteBadgeNode.isHidden = true
            return
        }

        // 2. Parabolic Hop / Gliding Pose: mid-air scamper paws + dynamic pitch tilt + projected shadow
        if case .gliding(let elapsed, let duration, _, let to, _) = state {
            cropNode.maskNode = nil
            dogSprite.size = topDogSize
            dogSprite.anchorPoint = CGPoint(x: 0.5, y: 0.04)
            walkAnimTimer += dt
            if walkAnimTimer >= 0.085 {
                walkAnimTimer = 0
                walkFrameToggle.toggle()
            }
            dogSprite.texture = bank.texture(for: walkFrameToggle ? .westieWalk1 : .westieWalk2)
            dogSprite.position = position
            dogSprite.xScale = dirSign * (1.0 - s * 0.30)
            dogSprite.yScale = 1.0 + s * 0.34
            let u = CGFloat(elapsed / max(duration, 0.01))
            let pitchTilt = cos(u * .pi) * 0.16 * dirSign
            dogSprite.zRotation = pitchTilt

            shadowNode.position = CGPoint(x: position.x, y: to.y + 1)
            let heightAboveTarget = max(0, position.y - to.y)
            let shadowScale = max(0.45, 1.0 - heightAboveTarget / 140.0)
            shadowNode.setScale(shadowScale)
            shadowNode.isHidden = false
            inviteBadgeNode.isHidden = true
            return
        }

        // 3. Right-Edge Peeking Modes (Fullscreen Screen-Right OR Non-Fullscreen Window-Right)
        if perchZone == .screenRightPeek || perchZone == .windowRightPeek {
            let hoverSlide = min(max(peekHoverSpring.value, -0.25), 1.25)
            // Negative `peekEmergeSpring.value` tucks Westie behind the edge and springs smoothly out to 0!
            let emergeTuck = max(0, -peekEmergeSpring.value) * 34.0 - min(max(peekEmergeSpring.value, 0), 0.22) * 7.0

            dogSprite.size = peekDogSize
            dogSprite.anchorPoint = CGPoint(x: 1.0, y: 0.5)
            dogSprite.texture = bank.texture(for: isPeekHoverTextureActive ? .westiePeekHover : .westiePeekCalm)

            let stretchMag = 1.0 + s * 0.22
            let squashPerp = 1.0 - s * 0.18
            dogSprite.yScale = squashPerp

            // Subtle friendly ear/paw tilt ONLY while hovered — completely still otherwise!
            let subtleHoverTilt: CGFloat = (peekHoverSpring.value > 0.04)
                ? sin(hoverWavePhase * 5.2) * 0.036 * min(max(hoverSlide, 0), 1.0)
                : 0.0

            if perchZone == .screenRightPeek {
                // Monitor right bezel clips x > screenWidth naturally; peek LEFTWARD (`xScale > 0`)
                cropNode.maskNode = nil
                let tuckInward: CGFloat = max(-3.0, 11.0 * (1.0 - hoverSlide) + emergeTuck)
                dogSprite.xScale = stretchMag
                dogSprite.position = CGPoint(x: position.x + tuckInward, y: position.y)
                dogSprite.zRotation = subtleHoverTilt
                inviteBadgeNode.position = CGPoint(x: position.x - 68, y: position.y + 46)
            } else {
                // Window right border: mask `x >= position.x` so ZERO pixels overlap inside the active window!
                cropMaskNode.position = CGPoint(x: position.x, y: position.y)
                cropNode.maskNode = cropMaskNode
                let tuckBehindWindow: CGFloat = max(-3.0, 10.0 * (1.0 - hoverSlide) + emergeTuck)
                dogSprite.xScale = -stretchMag // Mirrored to peek RIGHTWARD out from behind the active window!
                dogSprite.position = CGPoint(x: position.x - tuckBehindWindow, y: position.y)
                dogSprite.zRotation = -subtleHoverTilt + swingRotationSpring.value * 0.4
                inviteBadgeNode.position = CGPoint(x: position.x + 64, y: position.y + 46)
            }

            shadowNode.isHidden = true
            if case .holdingTennisBall = state {
                inviteBadgeNode.isHidden = false
            } else {
                inviteBadgeNode.isHidden = true
            }
            return
        }

        // 4. Active Window Top-Edge Mode (`正上方` — springy tap bounce, smooth stride, zero intrusive popups)
        cropNode.maskNode = nil
        dogSprite.size = topDogSize
        dogSprite.anchorPoint = CGPoint(x: 0.5, y: 0.04)

        var bobY: CGFloat = max(0, tapHopSpring.value)
        var strideTilt: CGFloat = 0

        if case .walking = state, currentWalkSpeed < 5.0 {
            dogSprite.texture = bank.texture(for: isHoveringDog ? .westieChinLedge : .westieIdle)
        } else {
            switch state {
            case .idle:
                dogSprite.texture = bank.texture(for: isHoveringDog ? .westieChinLedge : .westieIdle)
            case .sitCalm:
                dogSprite.texture = bank.texture(for: .westieSitTilt)
            case .loafing:
                dogSprite.texture = bank.texture(for: .westieLoafCalm)
            case .chinRest:
                dogSprite.texture = bank.texture(for: .westieChinLedge)
            case .sleeping:
                dogSprite.texture = bank.texture(for: .westieSleep)
            case .holdingTennisBall:
                dogSprite.texture = bank.texture(for: .westieHoldingBall)
            case .walking, .chasingTreat:
                let speedRatio: Double = {
                    if case .chasingTreat = state { return 1.8 }
                    return max(0.25, Double(currentWalkSpeed / 38.0))
                }()
                walkAnimTimer += dt * speedRatio
                if walkAnimTimer >= 0.19 {
                    walkAnimTimer = 0
                    walkFrameToggle.toggle()
                }
                dogSprite.texture = bank.texture(for: walkFrameToggle ? .westieWalk1 : .westieWalk2)
                let speedFactor = min(1.0, currentWalkSpeed / 38.0)
                bobY += abs(sin(breathPhase * 2.2)) * 1.4 * speedFactor
                strideTilt = sin(breathPhase * 2.2) * 0.024 * speedFactor
            case .peekingRight, .gliding, .dragged:
                dogSprite.texture = bank.texture(for: .westieIdle)
            }
        }

        if state != .walking(direction: facingDirection, remaining: 0) {
            if case .walking = state {} else if case .chasingTreat = state {} else {
                currentWalkSpeed = 0
            }
        }

        dogSprite.position = CGPoint(x: position.x, y: position.y + bobY)
        dogSprite.xScale = dirSign * (1.0 - s * 0.30)
        dogSprite.yScale = 1.0 + s * 0.34
        dogSprite.zRotation = swingRotationSpring.value + strideTilt

        shadowNode.position = CGPoint(x: position.x, y: (currentPlatform?.y ?? position.y) + 1)
        let hopScale = max(0.70, 1.0 - max(0, tapHopSpring.value) / 55.0)
        shadowNode.setScale(hopScale)
        shadowNode.isHidden = false

        if case .holdingTennisBall = state {
            inviteBadgeNode.isHidden = false
            inviteBadgeNode.position = CGPoint(x: position.x, y: position.y + 80)
        } else {
            inviteBadgeNode.isHidden = true
        }
    }
}
